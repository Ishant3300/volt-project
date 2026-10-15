'use strict';

/**
 * Volt notice cards (PNG) for Telegram, ready to forward to clients:
 *   expiryOpenCard   — "New contract open" + old contract settlement (same
 *                      details as the expiry announcement)
 *   newStocksCard    — new F&O stocks added
 *   banCard          — NSE F&O ban list: new today / still banned / removed
 *   corpActionsCard  — splits, bonus, dividends, rights… for F&O stocks
 * One template (Volt indigo, as on the web terminal), large text, phone
 * width. Rendered with the headless Chrome the backend's puppeteer already
 * ships (same as fillImage.js). Nothing internal (clients, positions) is
 * ever drawn on a card — that goes in a separate text message.
 */
const path = require('path');

const APP = path.resolve(__dirname, '..', '..');
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/** '2026-10-16' → 'Fri, 16 Oct 2026' (long: 'Friday, 16 Oct 2026') */
function day(key, long = false) {
  const d = new Date(`${String(key).slice(0, 10)}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return esc(key);
  const name = DAYS[d.getUTCDay()];
  return `${long ? name : name.slice(0, 3)}, ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}
/** '23:30' → '11:30 PM' */
function time12(hhmm) {
  const [h, m] = String(hhmm || '').split(':').map(Number);
  if (!Number.isFinite(h)) return '';
  return `${((h + 11) % 12) + 1}:${String(m || 0).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}
/** Contract month label from an expiry date: '2026-11-19' → '19 Nov 2026' */
function expiryLabel(key) {
  const d = new Date(`${String(key).slice(0, 10)}T00:00:00Z`);
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}
const nowIst = () => {
  const d = new Date(Date.now() + 5.5 * 3600_000);
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}, ${time12(`${d.getUTCHours()}:${d.getUTCMinutes()}`)} IST`;
};

const CSS = `
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { width: 720px; font-family: 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background: #eef0f7; color: #1f2333; }
  .card { margin: 18px; background: #fff; border-radius: 22px; overflow: hidden; box-shadow: 0 6px 24px rgba(40, 44, 90, .12); }
  .head { background: linear-gradient(135deg, #4338ca 0%, #4f46e5 45%, #6d5efc 100%); color: #fff; padding: 26px 30px 24px; position: relative; }
  .brand { display: flex; align-items: center; gap: 12px; }
  .logo { width: 42px; height: 42px; border-radius: 11px; background: rgba(255,255,255,.16); border: 1.5px solid rgba(255,255,255,.45); display: grid; place-items: center; font-weight: 800; font-size: 22px; }
  .bname { font-size: 20px; font-weight: 800; letter-spacing: 2px; }
  .bsub { font-size: 13px; opacity: .8; letter-spacing: .5px; }
  .date { position: absolute; right: 30px; top: 30px; background: rgba(255,255,255,.16); border: 1px solid rgba(255,255,255,.35); border-radius: 999px; padding: 7px 16px; font-size: 15px; font-weight: 600; }
  .title { margin-top: 22px; font-size: 34px; font-weight: 800; letter-spacing: .5px; line-height: 1.15; }
  .subtitle { margin-top: 6px; font-size: 17px; opacity: .9; }
  .body { padding: 24px 30px 10px; }
  .sec { margin-bottom: 22px; }
  .pill { display: inline-block; background: #eef0ff; color: #4338ca; font-weight: 800; font-size: 15px; letter-spacing: 1.5px; padding: 6px 14px; border-radius: 8px; margin-bottom: 10px; }
  table { width: 100%; border-collapse: separate; border-spacing: 0; font-size: 19px; }
  th { text-align: left; font-size: 13px; letter-spacing: 1px; text-transform: uppercase; color: #7a7f99; font-weight: 700; padding: 0 12px 8px; }
  td { padding: 13px 12px; border-top: 1px solid #edeef5; vertical-align: top; }
  tr:first-child td { border-top: none; }
  .rows { background: #f8f9fd; border-radius: 14px; padding: 4px 6px; }
  .sym { font-weight: 800; font-size: 20px; color: #1b1f3b; }
  .muted { color: #6b7089; font-size: 15px; }
  .r { text-align: right; }
  .nw { white-space: nowrap; }
  .tag { display: inline-block; border-radius: 7px; padding: 3px 10px; font-size: 14px; font-weight: 700; }
  .t-green { background: #e3f7ea; color: #15803d; } .t-red { background: #fde8e8; color: #c02626; }
  .t-amber { background: #fff4d6; color: #a15c00; } .t-blue { background: #e6efff; color: #1d4ed8; } .t-grey { background: #eceef4; color: #4b5068; }
  .box { border-radius: 16px; padding: 18px 20px; margin-bottom: 20px; font-size: 18px; line-height: 1.45; }
  .box b { font-weight: 800; }
  .amber { background: #fff7e0; border: 1px solid #f3d27a; color: #6b4300; }
  .red { background: #fdecec; border: 1px solid #f2b8b8; color: #8a1c1c; }
  .blue { background: #eef2ff; border: 1px solid #c7cdfb; color: #2f2a8f; }
  .chips { display: flex; flex-wrap: wrap; gap: 10px; }
  .chip { background: #fff; border: 1.5px solid #dfe2ef; border-radius: 10px; padding: 9px 14px; font-weight: 800; font-size: 19px; }
  .chip.new { border-color: #e05252; color: #b42318; background: #fff5f5; }
  .chip.out { border-color: #3fb46b; color: #15803d; background: #f1fbf4; text-decoration: line-through; }
  .foot { display: flex; justify-content: space-between; padding: 14px 30px 20px; color: #8a8fa8; font-size: 13px; border-top: 1px solid #f0f1f6; margin-top: 6px; }
`;

function page({ title, subtitle, date, body }) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>${CSS}</style></head><body><div class="card">
    <div class="head">
      <div class="brand"><div class="logo">V</div><div><div class="bname">VOLT</div><div class="bsub">Trading notice</div></div></div>
      ${date ? `<div class="date">${esc(date)}</div>` : ''}
      <div class="title">${esc(title)}</div>
      ${subtitle ? `<div class="subtitle">${esc(subtitle)}</div>` : ''}
    </div>
    <div class="body">${body}</div>
    <div class="foot"><span>Volt · automatic notice</span><span>${esc(nowIst())}</span></div>
  </div></body></html>`;
}

/**
 * opens: [{ exchange: 'MCX', names: ['CRUDEOIL','CRUDEOILM'] | null (all), label: 'Crude oil', allLabel, newExpiries: ['2026-11-19'] }]
 * settlements: [{ date: '2026-10-16', time: '23:30', label }]
 */
function expiryOpenCard({ date, opens, settlements }) {
  const byExchange = new Map();
  for (const o of opens) {
    if (!byExchange.has(o.exchange)) byExchange.set(o.exchange, []);
    byExchange.get(o.exchange).push(o);
  }
  const secs = [...byExchange].map(([ex, list]) => `<div class="sec"><span class="pill">${esc(ex)}</span><div class="rows"><table>
      <tr><th>Script</th><th class="r">New contract</th></tr>
      ${list.flatMap((o) => (o.names ? o.names.map((n) => ({ n, exp: o.newExpiries })) : [{ n: o.allLabel || `All ${o.label}`, exp: o.newExpiries }]))
    .map((r) => `<tr><td class="sym">${esc(r.n)}</td><td class="r"><span class="tag t-green">${r.exp.map(expiryLabel).map(esc).join(' / ') || 'Next month'}</span></td></tr>`).join('')}
    </table></div></div>`).join('');
  const settle = settlements.map((s) => `<div class="box amber">${settlements.length > 1 ? `<b>${esc(s.label)}</b><br>` : ''}Old contract settlement:
      <b>${esc(day(s.date, true))}</b> at last quotation <b>(${esc(time12(s.time))})</b></div>`).join('');
  return page({ title: 'New Contract Open', subtitle: 'Next month contracts are now open for trading', date: day(date), body: secs + settle });
}

/** stocks: [{ name, company, lot, current: '2026-10-27', options: true, from: '2026-10-15' }] */
function newStocksCard({ date, stocks }) {
  const rows = stocks.map((s) => `<tr><td><div class="sym">${esc(s.name)}</div><div class="muted">${esc(s.company || '')}</div></td>
      <td class="r"><b>${esc(Number(s.lot).toLocaleString('en-IN'))}</b></td>
      <td class="r"><span class="tag t-green">${esc(expiryLabel(s.current))}</span>${s.options ? '<br><span class="tag t-blue" style="margin-top:6px">Options</span>' : ''}</td></tr>`).join('');
  return page({
    title: 'New F&O Stocks Added',
    subtitle: `${stocks.length} new stock${stocks.length > 1 ? 's' : ''} now available in NSE F&O`,
    date: day(date),
    body: `<div class="sec"><div class="rows"><table><tr><th>Stock</th><th class="r">Lot size</th><th class="r">Trading contract</th></tr>${rows}</table></div></div>
      <div class="box blue">Futures and options are open for trading from <b>${esc(day(stocks[0]?.from || date, true))}</b>. Only the current month trades; the next month opens with the regular expiry schedule.</div>`,
  });
}

/** { date, banned: [...], newToday: [...], removed: [...] } */
function banCard({ date, banned, newToday, removed }) {
  const newSet = new Set(newToday);
  const chips = banned.length ? `<div class="chips">${banned.map((s) => `<span class="chip${newSet.has(s) ? ' new' : ''}">${esc(s)}</span>`).join('')}</div>` : '<div class="muted">No stock is in the ban period today.</div>';
  const legend = newToday.length ? `<div class="muted" style="margin-top:12px"><span class="tag t-red">red</span> = entered the ban today</div>` : '';
  const out = removed.length ? `<div class="sec"><span class="pill">Out of ban today</span><div class="chips">${removed.map((s) => `<span class="chip out">${esc(s)}</span>`).join('')}</div></div>` : '';
  return page({
    title: 'NSE F&O Ban List',
    subtitle: `${banned.length} stock${banned.length === 1 ? '' : 's'} in the ban period`,
    date: day(date),
    body: `<div class="sec"><span class="pill">In ban</span>${chips}${legend}</div>${out}
      <div class="box red">For stocks in ban: <b>no new positions</b>. Existing positions can only be <b>reduced or closed</b>.</div>`,
  });
}

const CA_TAG = { split: 't-amber', bonus: 't-amber', dividend: 't-green', rights: 't-blue', other: 't-grey' };
/** actions: [{ symbol, company, kind, subject, exDate: '2026-10-15', recDate }] */
function corpActionsCard({ date, actions, title = 'Corporate Actions' }) {
  const rows = actions.map((a) => `<tr><td><div class="sym">${esc(a.symbol)}</div><div class="muted">${esc(a.company || '')}</div></td>
      <td><span class="tag ${CA_TAG[a.kind] || 't-grey'}">${esc(a.kind[0].toUpperCase() + a.kind.slice(1))}</span><div style="margin-top:6px;font-size:16px">${esc(a.subject)}</div></td>
      <td class="r nw"><b>${esc(expiryLabel(a.exDate))}</b><div class="muted">${esc(day(a.exDate).slice(0, 3))}${a.recDate && a.recDate !== a.exDate ? ` · record ${esc(expiryLabel(a.recDate))}` : ''}</div></td></tr>`).join('');
  const adjust = actions.some((a) => a.kind === 'split' || a.kind === 'bonus');
  return page({
    title,
    subtitle: 'F&O stocks with an upcoming ex-date',
    date: day(date),
    body: `<div class="sec"><div class="rows"><table><tr><th>Stock</th><th>Action</th><th class="r">Ex-date</th></tr>${rows}</table></div></div>
      ${adjust ? '<div class="box amber">On the ex-date of a <b>split or bonus</b>, the exchange adjusts F&O contracts (price, lot size and strikes). Review open positions in these stocks before the ex-date.</div>' : ''}`,
  });
}

/** Render HTML pages to PNG buffers (one browser per batch). */
async function render(htmlList) {
  const puppeteer = require(path.join(APP, 'node_modules', 'puppeteer'));
  const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu'] });
  try {
    const out = [];
    for (const html of htmlList) {
      const page = await browser.newPage();
      await page.setViewport({ width: 720, height: 600, deviceScaleFactor: 2 });
      await page.setContent(html, { waitUntil: 'load' });
      out.push(await page.screenshot({ type: 'png', fullPage: true }));
      await page.close();
    }
    return out;
  } finally {
    await browser.close();
  }
}

module.exports = { expiryOpenCard, newStocksCard, banCard, corpActionsCard, render, _test: { day, time12, expiryLabel } };
