#!/usr/bin/env node
'use strict';

/**
 * One-off messages from shell scripts:
 *   node notify.js --audit <report.txt>   the daily health audit, shortened to
 *                                          its header, FAIL/WARN lines and result
 *   node notify.js --text "message"        plain text
 * Reads the backend .env from the current directory (run from the app dir).
 */
require('dotenv').config();
const fs = require('fs');
const { send } = require('./telegram');
const { escapeHtml } = require('./lib');

function auditMessage(file) {
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  const header = (lines.find((l) => l.startsWith('== ')) || 'Daily health audit').replace(/^==\s*/, '');
  const result = (lines.reverse().find((l) => l.startsWith('RESULT:')) || '').replace(/^RESULT:\s*/, '');
  lines.reverse();
  const problems = [];
  for (let i = 0; i < lines.length; i++) {
    if (/^(FAIL|WARN)/.test(lines[i])) {
      problems.push(lines[i].trim());
      // indented detail lines that follow a WARN (e.g. most frequent errors)
      while (lines[i + 1] && /^\s{4,}/.test(lines[i + 1]) && problems.length < 25) problems.push(`   ${lines[++i].trim()}`);
    }
  }
  const icon = problems.some((p) => p.startsWith('FAIL')) ? '🔴' : problems.length ? '🟠' : '🟢';
  return `${icon} <b>${escapeHtml(header)}</b>\n${escapeHtml(result)}${problems.length ? `\n\n${escapeHtml(problems.join('\n'))}` : ''}`.slice(0, 3900);
}

(async () => {
  const [flag, value] = process.argv.slice(2);
  if (flag === '--audit' && value) await send(auditMessage(value));
  else if (flag === '--text' && value) await send(escapeHtml(value));
  else {
    console.error('usage: notify.js --audit <file> | --text "message"');
    process.exit(2);
  }
})().catch((e) => {
  console.error('notify failed:', e.message);
  process.exit(1);
});
