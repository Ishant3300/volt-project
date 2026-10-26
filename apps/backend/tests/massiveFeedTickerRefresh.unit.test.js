'use strict';

// Contracts added while the server runs (the weekly seedGlobalFutures.js run)
// must start streaming without a restart. Until 26 Oct 2026 the feed loaded
// its contract list once at start-up, so COMEX December (GCZ6…) never got a
// price until the next restart.

jest.mock('../src/models/KiteInstrument', () => ({ find: jest.fn() }));

const WebSocket = require('ws');
const KiteInstrument = require('../src/models/KiteInstrument');
const feed = require('../src/services/massiveFuturesFeedService');

const rows = (list) => ({ select: () => ({ lean: async () => list.map(([tradingsymbol, instrument_token]) => ({ tradingsymbol, instrument_token })) }) });

beforeEach(() => {
  jest.clearAllMocks();
  feed.tickerToToken = new Map([['GCX6', '9000600202611']]);
  feed.ws = { readyState: WebSocket.OPEN, send: jest.fn() };
  feed._authenticated = true;
});

test('new contracts → loaded and only they are subscribed', async () => {
  KiteInstrument.find.mockReturnValue(rows([['GCX6', '9000600202611'], ['GCZ6', '9000600202612']]));
  await feed._refreshTickers();
  expect(feed.tickerToToken.get('GCZ6')).toBe('9000600202612');
  expect(feed.ws.send).toHaveBeenCalledTimes(1);
  expect(JSON.parse(feed.ws.send.mock.calls[0][0])).toEqual({ action: 'subscribe', params: 'Q.GCZ6,T.GCZ6' });
});

test('nothing new → no subscribe', async () => {
  KiteInstrument.find.mockReturnValue(rows([['GCX6', '9000600202611']]));
  await feed._refreshTickers();
  expect(feed.ws.send).not.toHaveBeenCalled();
});

test('socket not authenticated → loaded but not sent (the reconnect subscribes every ticker)', async () => {
  feed._authenticated = false;
  KiteInstrument.find.mockReturnValue(rows([['GCX6', '9000600202611'], ['SIZ6', '9000700202612']]));
  await feed._refreshTickers();
  expect(feed.tickerToToken.has('SIZ6')).toBe(true);
  expect(feed.ws.send).not.toHaveBeenCalled();
});
