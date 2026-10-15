'use strict';

/**
 * PNG for a fill that was better than the market — a 'Market Movement' style
 * 1-minute table (the exchange's own candles from Kite, latest first, the
 * fill's minute highlighted) and the client's trade underneath, ready to
 * forward to the client. Rendered with the headless Chrome that the backend's
 * puppeteer dependency already ships; the browser is started per batch and
 * closed right after.
 */
const path = require('path');

const APP = path.resolve(__dirname, '..', '..');
const IST_MS = 5.5 * 3600_000;
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const n2 = (x) => Number(x).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const istDate = (ms) => new Date(ms + IST_MS);
const hm12 = (ms) => {
  const d = istDate(ms);
  const h = d.getUTCHours();
  return `${String(((h + 11) % 12) + 1).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`;
};
const ampm = (ms) => (istDate(ms).getUTCHours() < 12 ? 'AM' : 'PM');

/** HTML for one fill. f: { client, sym, side, qty, ot, price, at(ms), id }, candles: Kite minute candles. */
function fillHtml(f, candles) {
  const fillMin = Math.floor(f.at / 60000) * 60000;
  const rows = [...candles].map((c) => ({ ...c, t: Date.parse(String(c.date).replace(/(\+\d{2})(\d{2})$/, '$1:$2')) })).sort((a, b) => b.t - a.t);
  const near = rows.filter((r) => Math.abs(r.t - fillMin) <= 60000);
  const own = rows.find((r) => r.t === fillMin);
  const lowNear = near.length ? Math.min(...near.map((r) => r.low)) : null;
  const highNear = near.length ? Math.max(...near.map((r) => r.high)) : null;
  const buy = f.side === 'BUY';
  const gap = buy ? (lowNear != null ? lowNear - f.price : 0) : (highNear != null ? f.price - highNear : 0);
  const d = istDate(f.at);
  const day = d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' });
  const secs = `${hm12(f.at)}:${String(d.getUTCSeconds()).padStart(2, '0')} ${ampm(f.at)}`;
  const entryMin = f.rt ? Math.floor(f.rt.entryAt / 60000) * 60000 : null;
  const rowClass = (t) => (t === fillMin ? 'hit' : t === entryMin ? 'entry' : '');
  const body = rows.map((r) => `<tr class="${rowClass(r.t)}"><td class="l">${hm12(r.t)}:00 ${ampm(r.t)}</td><td>${n2(r.open)}</td><td>${n2(r.high)}</td><td>${n2(r.low)}</td><td>${n2(r.close)}</td><td>${Number(r.volume || 0)}</td></tr>`).join('');
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    body{margin:0;background:#f0f0f0;font-family:'Noto Sans',sans-serif;width:900px}
    .bar{background:#e1e6f0;padding:7px 10px;font-size:17px;color:#141414}
    table{border-collapse:collapse;width:100%;background:#000}
    th{background:#fafafa;color:#1e1e1e;font-weight:400;font-size:17px;padding:4px 18px;text-align:right}
    th.l,td.l{text-align:left}
    td{color:#ebebeb;font-family:'Source Code Pro',monospace;font-size:16px;padding:3px 18px;text-align:right}
    tr.hit td{color:#ffe650;font-weight:700;background:#282800;outline:2px solid #ffd200}
    tr.entry td{color:#7dffa8;font-weight:700;background:#0c2814;outline:2px solid #2ecc71}
    .box{margin:10px;background:#fff;border:3px solid #c83c3c;padding:12px 16px;font-size:17px;color:#191919}
    .box h2{margin:0 0 8px;font-size:20px;color:#a01414}
    .box p{margin:4px 0}.red{color:#a01414;font-size:15px}
  </style></head><body>
  <div class="bar">Market Movement for FUTSTK&nbsp; ${esc(f.sym)} &nbsp;&nbsp;TimeInterval: 1 min &nbsp;&nbsp;(${esc(day)})</div>
  <table><tr><th class="l">Time</th><th>Open</th><th>High</th><th>Low</th><th>Close</th><th>Volume</th></tr>${body}</table>
  ${f.rt ? quickBox(f, day) : `<div class="box"><h2>Client trade — ${esc(f.client)}</h2>
    <p>${esc(f.side)} ${esc(f.qty)} ${esc(f.sym)} (${esc(f.ot)}) @ ${n2(f.price)}</p>
    <p>Executed: ${esc(day)}, ${esc(secs)} IST &nbsp;&nbsp; Trade ID: ${esc(f.id)}</p>
    ${own ? `<p>Exchange at ${hm12(fillMin)} ${ampm(fillMin)}: Low ${n2(own.low)} – High ${n2(own.high)} &nbsp;(${buy ? 'lowest' : 'highest'} within ±1 min: ${n2(buy ? lowNear : highNear)})</p>` : ''}
    ${f.spike ? `<p class="red">Filled at the ${buy ? 'low' : 'high'} edge of a fast minute: the exchange moved ${f.spike.rangePct.toFixed(2)}% in that minute and this ${esc(f.ot)} order filled within the outer ${Math.max(1, Math.round(f.spike.edgePct))}% of the range.</p>
    <p class="red">Exchange volume that minute: ${esc(own ? own.volume : '-')}${f.spike.volShare != null ? ` — this order alone = ${f.spike.volShare < 10 ? f.spike.volShare.toFixed(1) : Math.round(f.spike.volShare)}% of it` : ''}.</p>` : ''}
    ${!f.spike && gap > 0 ? `<p class="red">The fill price ${n2(f.price)} never traded on the exchange in this period — ${n2(gap)} ${buy ? 'below the lowest' : 'above the highest'} traded price.</p>
    <p class="red">Difference: ${n2(gap)} × ${esc(f.qty)} = ${n2(gap * Number(f.qty))}</p>` : ''}
  </div>`}</body></html>`;
}

/** Trade box for a quick profit: entry (green row) -> exit (yellow row) and the market in between. */
function quickBox(f, day) {
  const r = f.rt;
  const t = (ms) => { const d = istDate(ms); return `${hm12(ms)}:${String(d.getUTCSeconds()).padStart(2, '0')} ${ampm(ms)}`; };
  const sign = (x) => (x >= 0 ? '+' : '');
  return `<div class="box"><h2>Quick profit — ${esc(f.client)}</h2>
    <p><span style="color:#1e9e50;font-weight:700">Entry</span> ${esc(r.entrySide)} ${esc(f.qty)} ${esc(f.sym)} @ ${n2(r.entryPrice)} at ${t(r.entryAt)}</p>
    <p><span style="color:#b38f00;font-weight:700">Exit</span> ${esc(f.side)} ${esc(f.qty)} @ ${n2(f.price)} at ${t(f.at)} IST (${esc(day)}) — held ${esc(r.held)}</p>
    <p>Profit: <b>${n2(r.pnl)}</b> &nbsp;&nbsp; Trade ID: ${esc(f.id)}</p>
    ${r.movePct != null ? `<p class="red">Exchange in that window: Low ${n2(r.lo)} – High ${n2(r.hi)} (${r.movePct.toFixed(2)}% range, ${sign(r.dirPct)}${r.dirPct.toFixed(2)}% open→close)${r.volX != null ? `, volume ${r.volX.toFixed(1)}× the previous 30 minutes` : ''}.</p>` : ''}
  </div>`;
}

/** PNG buffers for several fills with one browser start. items: [{ fill, candles }] */
async function renderFillImages(items) {
  if (!items.length) return [];
  const puppeteer = require(path.join(APP, 'node_modules', 'puppeteer'));
  const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu'] });
  try {
    const out = [];
    for (const it of items) {
      const page = await browser.newPage();
      await page.setViewport({ width: 900, height: 600, deviceScaleFactor: 1 });
      await page.setContent(fillHtml(it.fill, it.candles), { waitUntil: 'load' });
      out.push(await page.screenshot({ type: 'png', fullPage: true }));
      await page.close();
    }
    return out;
  } finally {
    await browser.close();
  }
}

module.exports = { fillHtml, renderFillImages };
