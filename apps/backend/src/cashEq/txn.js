'use strict';

// One MongoDB transaction for writes that must happen together (a fill = trade rows +
// the order's filled quantity + the trade counter). Swapped for a plain call in tests.

const mongoose = require('mongoose');

async function withTxn(fn) {
  const session = await mongoose.startSession();
  try {
    let out;
    await session.withTransaction(async () => { out = await fn(session); });
    return out;
  } finally {
    await session.endSession();
  }
}

module.exports = { withTxn };
