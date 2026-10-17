'use strict';

// Practice mode: any outbound axios request not to this machine is refused before it leaves.

const axios = require('axios');
const { install } = require('../src/services/practice/outboundGuard');

beforeAll(() => install());

test.each(['https://api.kite.trade/quote', 'https://www.nseindia.com/api/x', 'https://kite.zerodha.com/api/login', 'https://api.massive.com/v1'])('blocks %s', async (url) => {
  await expect(axios.get(url)).rejects.toMatchObject({ code: 'PRACTICE_OUTBOUND_BLOCKED' });
});

test('allows localhost (request reaches the network layer, not blocked by the guard)', async () => {
  const err = await axios.get('http://127.0.0.1:1/never-listening').catch((e) => e);
  expect(err.code).not.toBe('PRACTICE_OUTBOUND_BLOCKED');
});
