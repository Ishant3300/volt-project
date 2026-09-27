/**
 * Import a Group Quantity sheet (CSV) straight into GroupedQuantity, instead
 * of building the group by hand in Admin one script at a time.
 *
 * Input format — one row per script, either:
 *   GROUP, EXCHANGE, SCRIPT, MAX_QTY, BREAK_QTY            (no header)
 *   GOLDMIN,NSEFUT,ABCAPITAL,"2,700.00","1,000.00"
 * or the 6-column export with a header row:
 *   User Type,Market Name,Script Name,Position,Min Order,Max Order
 *   HRY 3 LOT,NSEFUT,360ONE,1500,1,1500
 *   (Position -> max_qty, Max Order -> break_qty, Min Order ignored)
 * A script listed twice for the same exchange: the LAST row wins (reported).
 * EXCHANGE codes: NSEFUT, NSEOPT, MCXFUT, MCXOPT, COMEXFUT, GLOBAL FUTURES.
 * Numbers may carry thousands separators. The GROUP column is informational
 * only — the group name comes from --group (sheets sometimes carry typos).
 *
 * Behaviour:
 * - Script names are matched case-insensitively against ACTIVE instruments
 *   of that exchange (plus the ALIASES below for known renames). Rows that
 *   match nothing are skipped and listed in the report.
 * - lot_size is taken from the instrument, same as Admin's bulk create.
 * - --fill-from <group>: every active script the sheet does NOT list gets
 *   that group's max/break qty (e.g. Default). Without it, those scripts
 *   would have NO quantity limit for clients on this group — the trade path
 *   only enforces a limit when a ScriptQuantity row exists.
 * - Upsert per (exchange, group, script): re-running updates values, never
 *   duplicates. Each exchange is written in one transaction.
 * - Dry run by default; nothing is written without --apply.
 *
 * Usage:
 *   node scripts/importGroupedQuantity.js <file.csv> --group GOLDMIN --fill-from Default
 *   node scripts/importGroupedQuantity.js <file.csv> --group GOLDMIN --fill-from Default --apply
 */
require('dotenv').config();
const fs = require('fs');
const mongoose = require('mongoose');
const GroupedQuantity = require('../src/models/GroupedQuantity');
const KiteInstrument = require('../src/models/KiteInstrument');

const EXCHANGE_MAP = {
  NSEFUT: 'NFO-FUT',
  NSEOPT: 'NFO-OPT',
  MCXFUT: 'MCX-FUT',
  MCXOPT: 'MCX-OPT',
  COMEXFUT: 'COMEX-FUT',
  'GLOBAL FUTURES': 'INDICES', // GLOBAL groups are stored as INDICES
  GLOBAL: 'INDICES',
};

// Sheet name (upper-cased) -> current instrument raw_name, for renames.
const ALIASES = {
  TATAMOTORS: 'TMPV', // Tata Motors demerger — passenger vehicles
  LTIM: 'LTM', // LTIMindtree symbol change
  NASDAQ: 'Nasdaq 100',
};

function parseArgs(argv) {
  const args = { file: null, group: null, fillFrom: null, apply: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--group') args.group = argv[++i];
    else if (a === '--fill-from') args.fillFrom = argv[++i];
    else if (a === '--apply') args.apply = true;
    else if (!args.file) args.file = a;
  }
  if (!args.file || !args.group) {
    console.error('Usage: node scripts/importGroupedQuantity.js <file.csv> --group <NAME> [--fill-from <GROUP>] [--apply]');
    process.exit(1);
  }
  return args;
}

function parseCsvLine(line) {
  const out = [];
  let cur = '';
  let quoted = false;
  for (const ch of line) {
    if (ch === '"') quoted = !quoted;
    else if (ch === ',' && !quoted) { out.push(cur); cur = ''; }
    else cur += ch;
  }
  out.push(cur);
  return out.map((s) => s.trim());
}

function toNumber(s) {
  const n = Number(String(s).replace(/,/g, ''));
  return Number.isFinite(n) ? n : NaN;
}

function segmentFilter(exchange) {
  // Same instrument universe Admin's bulkCreateGroup uses.
  if (exchange === 'INDICES') return { is_active: true, segment: { $in: ['INDICES', 'GLOBAL'] } };
  return { is_active: true, segment: exchange };
}

async function main() {
  const args = parseArgs(process.argv);
  const lines = fs.readFileSync(args.file, 'utf8').split(/\r?\n/).filter((l) => l.trim());

  const byExchange = new Map();
  const badRows = [];
  const groupCol = new Map();
  lines.forEach((line, idx) => {
    const cols = parseCsvLine(line);
    if (idx === 0 && /^user type$/i.test(cols[0] || '')) return; // header row
    const [grp, exCode, script, maxRaw, breakRaw] =
      cols.length >= 6 ? [cols[0], cols[1], cols[2], cols[3], cols[5]] : cols;
    groupCol.set(grp, (groupCol.get(grp) || 0) + 1);
    const exchange = EXCHANGE_MAP[String(exCode || '').toUpperCase()];
    const max = toNumber(maxRaw);
    const brk = toNumber(breakRaw);
    if (!exchange || !script || Number.isNaN(max) || Number.isNaN(brk) || max < 0 || brk < 0) {
      badRows.push(`line ${idx + 1}: ${line}`);
      return;
    }
    if (!byExchange.has(exchange)) byExchange.set(exchange, []);
    byExchange.get(exchange).push({ script, max, brk, line: idx + 1 });
  });

  await mongoose.connect(process.env.MONGO_URI);
  console.log(`File: ${args.file}`);
  console.log(`Group: "${args.group}"   fill-from: ${args.fillFrom || '(none — unlisted scripts get NO limit)'}   mode: ${args.apply ? 'APPLY' : 'DRY RUN'}`);
  console.log(`Group column values in file: ${[...groupCol].map(([g, n]) => `${g}×${n}`).join(', ')}`);
  if (badRows.length) console.log(`Unparseable rows skipped (${badRows.length}):\n  ${badRows.join('\n  ')}`);

  let totalWritten = 0;
  for (const [exchange, rows] of byExchange) {
    const instruments = await KiteInstrument.aggregate([
      { $match: segmentFilter(exchange) },
      { $group: { _id: '$raw_name', lot_size: { $first: '$lot_size' } } },
    ]);
    const liveByUpper = new Map(instruments.map((i) => [String(i._id).toUpperCase(), i]));

    const planned = new Map(); // raw_name -> { max, brk, lot_size, source }
    const unmatched = [];
    const aliased = [];
    const seen = new Map();
    const dupes = [];
    const breakOverMax = [];
    for (const r of rows) {
      const key = r.script.toUpperCase();
      const prev = seen.get(key);
      if (prev && (prev.max !== r.max || prev.brk !== r.brk)) dupes.push(`${r.script} ${prev.max}/${prev.brk}→${r.max}/${r.brk}`);
      seen.set(key, r);
      if (r.brk > r.max) breakOverMax.push(`${r.script} ${r.max}/${r.brk}`);
      const aliasTarget = ALIASES[key];
      const inst = liveByUpper.get(key) || (aliasTarget && liveByUpper.get(aliasTarget.toUpperCase()));
      if (!inst) { unmatched.push(r.script); continue; }
      if (inst._id.toUpperCase() !== key) aliased.push(`${r.script}→${inst._id}`);
      planned.set(inst._id, { max: r.max, brk: r.brk, lot_size: inst.lot_size || 1, source: 'file' });
    }

    const notInFile = instruments.filter((i) => !planned.has(i._id));
    const filled = [];
    const stillUnlimited = [];
    if (args.fillFrom && notInFile.length) {
      const fillRows = await GroupedQuantity.find({ exchange_name: exchange, lot_name: args.fillFrom, deleted_at: null }).lean();
      const fillByUpper = new Map(fillRows.map((g) => [String(g.raw_name).toUpperCase(), g]));
      for (const i of notInFile) {
        const src = fillByUpper.get(String(i._id).toUpperCase());
        if (src) {
          planned.set(i._id, { max: src.max_qty, brk: src.break_qty, lot_size: i.lot_size || src.lot_size || 1, source: `fill:${args.fillFrom}` });
          filled.push(i._id);
        } else stillUnlimited.push(i._id);
      }
    } else {
      stillUnlimited.push(...notInFile.map((i) => i._id));
    }

    console.log(`\n== ${exchange}: from file ${rows.length - unmatched.length}/${rows.length}, filled from ${args.fillFrom || '-'} ${filled.length}, total to write ${planned.size} (live scripts ${instruments.length})`);
    if (aliased.length) console.log(`  renamed: ${aliased.join(', ')}`);
    if (dupes.length) console.log(`  DUPLICATE rows, last one used (${dupes.length}): ${dupes.join(', ')}`);
    if (breakOverMax.length) console.log(`  per-order qty > max qty (${breakOverMax.length}): ${breakOverMax.join(', ')}`);
    if (unmatched.length) console.log(`  SKIPPED — not a live script (${unmatched.length}): ${unmatched.join(', ')}`);
    if (stillUnlimited.length) console.log(`  NO LIMIT — live but not in file${args.fillFrom ? ` or ${args.fillFrom}` : ''} (${stillUnlimited.length}): ${stillUnlimited.join(', ')}`);

    if (!args.apply || planned.size === 0) continue;

    const now = new Date();
    const ops = [...planned].map(([rawName, p]) => ({
      updateOne: {
        filter: { exchange_name: exchange, lot_name: args.group, raw_name: rawName, deleted_at: null },
        update: {
          $setOnInsert: { exchange_name: exchange, lot_name: args.group, raw_name: rawName, instrument_id: '', instrument_symbol: rawName, created_at: now },
          $set: { max_qty: p.max, break_qty: p.brk, lot_size: p.lot_size, updated_at: now, deleted_at: null },
        },
        upsert: true,
      },
    }));
    const session = await mongoose.startSession();
    try {
      await session.withTransaction(async () => {
        const res = await GroupedQuantity.bulkWrite(ops, { session });
        console.log(`  WROTE: inserted ${res.upsertedCount}, updated ${res.modifiedCount}, unchanged ${ops.length - res.upsertedCount - res.modifiedCount}`);
      });
      totalWritten += ops.length;
    } finally {
      session.endSession();
    }
  }

  console.log(args.apply ? `\nDone — ${totalWritten} rows written for group "${args.group}".` : '\nDry run only — re-run with --apply to write.');
  await mongoose.disconnect();
}

main().catch((e) => { console.error(e); process.exit(1); });
