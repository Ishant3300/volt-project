'use strict';

/**
 * Sends watchdog messages to a Telegram chat (TELEGRAM_BOT_TOKEN +
 * TELEGRAM_CHAT_ID in the backend .env). Without them it runs in "dry mode"
 * and appends each message to ~/watchdog/outbox.log instead, so everything
 * can be checked before the bot exists. Messages go out one at a time
 * (Telegram allows ~1/s per chat); a failed send is retried a few times.
 */
const https = require('https');
const fs = require('fs');
const path = require('path');
const os = require('os');

const OUTBOX = path.join(os.homedir(), 'watchdog', 'outbox.log');
const queue = [];
let busy = false;

const configured = () => Boolean(process.env.TELEGRAM_BOT_TOKEN && process.env.TELEGRAM_CHAT_ID);

function post(text) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ chat_id: process.env.TELEGRAM_CHAT_ID, text, parse_mode: 'HTML', disable_web_page_preview: true });
    const req = https.request({
      hostname: 'api.telegram.org',
      path: `/bot${process.env.TELEGRAM_BOT_TOKEN}/sendMessage`,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
      timeout: 15000,
    }, (res) => {
      let data = '';
      res.on('data', (c) => { data += c; });
      res.on('end', () => (res.statusCode === 200 ? resolve() : reject(new Error(`Telegram ${res.statusCode}: ${data.slice(0, 200)}`))));
    });
    req.on('timeout', () => req.destroy(new Error('Telegram timeout')));
    req.on('error', reject);
    req.end(body);
  });
}

function writeOutbox(text, note = '') {
  try {
    fs.mkdirSync(path.dirname(OUTBOX), { recursive: true });
    fs.appendFileSync(OUTBOX, `--- ${new Date().toISOString()}${note}\n${text}\n`);
  } catch (_) { /* nothing else to do */ }
}

async function drain() {
  if (busy) return;
  busy = true;
  try {
    while (queue.length) {
      const item = queue[0];
      if (!configured()) {
        writeOutbox(item.text, ' (dry mode)');
        queue.shift();
        continue;
      }
      try {
        await post(item.text);
        queue.shift();
      } catch (err) {
        item.tries = (item.tries || 0) + 1;
        if (item.tries >= 4) {
          writeOutbox(item.text, ` (send failed: ${String(err.message).replace(/bot\d+:[\w-]+/g, 'bot<token>')})`);
          queue.shift();
        } else {
          await new Promise((r) => setTimeout(r, 5000 * item.tries));
        }
      }
      await new Promise((r) => setTimeout(r, 1100));
    }
  } finally {
    busy = false;
  }
}

/** Queue a message (Telegram HTML). Resolves when the queue has been drained. */
function send(text) {
  if (queue.length > 200) queue.splice(0, queue.length - 200); // never pile up without limit
  queue.push({ text });
  return drain();
}

module.exports = { send, configured, OUTBOX };
