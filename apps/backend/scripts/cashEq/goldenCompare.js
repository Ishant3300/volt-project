'use strict';

// Golden check: Trade Terminal's original TypeScript vs the backend port (src/cashEq/engine.js).
//
//   node scripts/cashEq/goldenCompare.js [--tt D:/TradeTerminal] [--count 2000] [--write-hashes]
//
// The original lib/terminal/*.ts is transpiled (with Trade Terminal's own TypeScript) into
// a temp folder — Trade Terminal itself is only read. Every scenario is run through both,
// and the full outputs (every net rate, lot, ledger row, interest, carry) must be identical.
// --write-hashes stores the original's output hash per seed in
// tests/fixtures/cashEqGolden.json, so the jest test can check the port without D:.

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { makeScenario, runScenario, canonical } = require('./goldenScenarios');
const port = require('../../src/cashEq/engine');

const arg = (name, def) => {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : def;
};
const ttRoot = arg('--tt', 'D:/TradeTerminal');
const count = Number(arg('--count', '2000'));
const HASH_SEEDS = 300;

function loadOriginal() {
  const ts = require(path.join(ttRoot, 'node_modules', 'typescript'));
  const src = path.join(ttRoot, 'lib', 'terminal');
  const out = path.join(os.tmpdir(), 'cashEq-golden-tt');
  fs.mkdirSync(out, { recursive: true });
  for (const f of ['engine.ts', 'ledger.ts', 'types.ts', 'exchange-master.ts', 'fo-master.ts']) {
    const code = fs.readFileSync(path.join(src, f), 'utf8');
    const js = ts.transpileModule(code, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true },
    }).outputText;
    fs.writeFileSync(path.join(out, f.replace(/\.ts$/, '.js')), js);
  }
  const engine = require(path.join(out, 'engine.js'));
  const ledger = require(path.join(out, 'ledger.js'));
  return {
    computeTradeCalcs: engine.computeTradeCalcs,
    computePositions: engine.computePositions,
    buildEquityLots: ledger.buildEquityLots,
    computeClientLedger: ledger.computeClientLedger,
    carryToSettlement: (...a) => {
      const r = ledger.carryToSettlement(...a);
      return { trades: r.trades, calcs: r.calcs, since: r.since };
    },
  };
}

function firstDiff(a, b, p = '$') {
  if (typeof a !== typeof b) return `${p}: ${JSON.stringify(a)} vs ${JSON.stringify(b)}`;
  if (a && typeof a === 'object') {
    const keys = new Set([...Object.keys(a), ...Object.keys(b || {})]);
    for (const k of keys) {
      const d = firstDiff(a[k], b ? b[k] : undefined, `${p}.${k}`);
      if (d) return d;
    }
    return null;
  }
  return a === b ? null : `${p}: ${JSON.stringify(a)} vs ${JSON.stringify(b)}`;
}

const original = loadOriginal();
const hashes = {};
let checked = 0;
let rows = 0;
let trades = 0;
for (let seed = 1; seed <= count; seed++) {
  const sc = makeScenario(seed);
  const a = canonical(runScenario(sc, original));
  const b = canonical(runScenario(sc, port));
  if (a !== b) {
    console.error(`MISMATCH seed ${seed}: ${firstDiff(JSON.parse(a), JSON.parse(b))}`);
    process.exit(1);
  }
  if (seed <= HASH_SEEDS) hashes[seed] = crypto.createHash('sha256').update(a).digest('hex');
  checked++;
  trades += sc.trades.length;
  rows += JSON.parse(a).ledgers.reduce((s, l) => s + l.rows.length, 0);
}
console.log(`OK: ${checked} scenarios, ${trades} trades, ${rows} ledger rows — original and port identical`);

if (process.argv.includes('--write-hashes')) {
  const file = path.join(__dirname, '..', '..', 'tests', 'fixtures', 'cashEqGolden.json');
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify({ source: 'D:/TradeTerminal lib/terminal (original TS)', hashes }, null, 1)}\n`);
  console.log(`wrote ${Object.keys(hashes).length} hashes to ${path.relative(process.cwd(), file)}`);
}
