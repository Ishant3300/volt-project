'use strict';

// Equity deploy gate: lists every EXISTING file changed since `base` (default: the commit
// before the first equity commit) and fails if any is outside the allowlist. New files
// under src/cashEq, scripts/cashEq and tests/ are always fine.
//
//   node scripts/cashEq/checkFnoUntouched.js [base]

const { execSync } = require('child_process');

const BASE = process.argv[2] || 'e5f5ec4~1'; // e5f5ec4 = equity M1 (first equity commit)
const PREFIX = 'apps/backend/';

// The only existing backend files equity may touch (see exports/equity-isolation-check.md).
const ALLOWED = new Set([
  'src/index.js', // mounts /api/cash-eq (one line)
  'src/controllers/authController.js', // universal login: equity accounts after no F&O match
]);
const NEW_OK = [/^src\/cashEq\//, /^scripts\/cashEq\//, /^tests\/cashEq[^/]*\.test\.js$/, /^tests\/helpers\/cashEq/, /^tests\/fixtures\/cashEq/];

const run = (cmd) => execSync(cmd, { encoding: 'utf8' }).trim();
const lines = run(`git diff --name-status ${BASE} HEAD -- ${PREFIX}`).split('\n').filter(Boolean);

const bad = [];
for (const line of lines) {
  const [status, file] = line.split('\t');
  const rel = file.slice(PREFIX.length);
  if (status === 'A' && NEW_OK.some((re) => re.test(rel))) continue;
  if (status === 'M' && ALLOWED.has(rel)) continue;
  // Changes to F&O files from other (non-equity) commits in the range are reported too:
  // check them by hand — they must not be equity work.
  bad.push(`${status} ${rel}`);
}

const touched = lines.filter((l) => l.startsWith('M\t')).map((l) => l.split('\t')[1].slice(PREFIX.length));
console.log(`Existing files changed since ${BASE}: ${touched.length ? touched.join(', ') : 'none'}`);
if (bad.length) {
  console.error(`NOT ALLOWED for an equity deploy:\n  ${bad.join('\n  ')}`);
  process.exit(1);
}
console.log('OK: only allowed existing files changed');
