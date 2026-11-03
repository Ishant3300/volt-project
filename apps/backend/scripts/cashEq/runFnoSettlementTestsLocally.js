'use strict';

// Runs the existing F&O settlement integration tests against a throwaway MongoDB in this
// PC's memory (127.0.0.1 only) — the equity M8 baseline. MONGO_URI is set to the local
// replica set BEFORE jest starts (dotenv never overrides an existing variable), so the
// tests can't reach the live database; they also refuse the `stocker` database themselves.
//
//   node scripts/cashEq/runFnoSettlementTestsLocally.js [test files…]

const { spawn } = require('child_process');
const path = require('path');
const { MongoMemoryReplSet } = require('mongodb-memory-server');

(async () => {
  const rs = await MongoMemoryReplSet.create({ replSet: { count: 1, storageEngine: 'wiredTiger', ip: '127.0.0.1' } });
  const uri = rs.getUri();
  const host = new URL(uri.replace(/^mongodb:\/\//, 'http://')).hostname;
  if (host !== '127.0.0.1') throw new Error(`Refusing non-local host ${host}`);
  const files = process.argv.slice(2).length ? process.argv.slice(2) : ['tests/settlement.integration.test.js'];
  console.log(`Local MongoDB ${host} — running ${files.join(', ')}`);
  const env = { ...process.env, MONGO_URI: uri, RUN_SETTLEMENT_INTEGRATION: '1' };
  for (const k of Object.keys(env)) if (/MONGO/i.test(k) && k !== 'MONGO_URI') env[k] = 'mongodb://127.0.0.1:1/never-live';
  // Not spawnSync: a blocked parent stops reading mongod's output and the database stalls.
  const status = await new Promise((resolve) => {
    spawn(process.execPath, [path.join('node_modules', 'jest', 'bin', 'jest.js'), '--runInBand', '--forceExit', ...files], {
    cwd: path.join(__dirname, '..', '..'), env, stdio: 'inherit',
  }).on('exit', (code) => resolve(code));
  });
  await rs.stop();
  process.exit(status ?? 1);
})().catch((e) => { console.error(e.message); process.exit(1); });
