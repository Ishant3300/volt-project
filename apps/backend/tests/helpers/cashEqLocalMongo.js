'use strict';

// A throwaway MongoDB replica set in this PC's memory (mongodb-memory-server) for the equity
// real-database proofs. It can never reach the live database:
//   • every Mongo URI in the environment is replaced by a dead local address before
//     anything else loads (so even an accidental connect can't reach Atlas);
//   • the server is started here, on 127.0.0.1 only, and connected by its own URI;
//   • the connection must be 127.0.0.1 and the database name must start with cashEq_proof_
//     (never `stocker`), else the test stops before writing anything.

for (const k of Object.keys(process.env)) {
  if (/MONGO/i.test(k)) process.env[k] = 'mongodb://127.0.0.1:1/never-live';
}

const mongoose = require('mongoose');

let replSet = null;

async function startLocalMongo(dbName) {
  if (!/^cashEq_proof_[a-z0-9_]+$/.test(dbName)) throw new Error(`Unsafe test database name ${dbName}`);
  const { MongoMemoryReplSet } = require('mongodb-memory-server');
  replSet = await MongoMemoryReplSet.create({ replSet: { count: 1, storageEngine: 'wiredTiger', ip: '127.0.0.1' } });
  const uri = replSet.getUri();
  const host = new URL(uri.replace(/^mongodb:\/\//, 'http://')).hostname;
  if (host !== '127.0.0.1') throw new Error(`Refusing non-local MongoDB host ${host}`);
  await mongoose.connect(uri, { dbName, autoIndex: false, serverSelectionTimeoutMS: 10_000 });
  const c = mongoose.connection;
  if (c.host !== '127.0.0.1' || c.name !== dbName || c.name === 'stocker') {
    await mongoose.disconnect();
    throw new Error(`Refusing to test against ${c.host}/${c.name}`);
  }
  return c;
}

async function stopLocalMongo() {
  try {
    if (mongoose.connection.readyState === 1 && /^cashEq_proof_/.test(mongoose.connection.name)) await mongoose.connection.dropDatabase();
  } finally {
    await mongoose.disconnect();
    if (replSet) await replSet.stop();
    replSet = null;
  }
}

module.exports = { startLocalMongo, stopLocalMongo };
