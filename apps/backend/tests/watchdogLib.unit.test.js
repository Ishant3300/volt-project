const lib = require('../scripts/watchdog/lib');
const { trackLoginAttempt } = require('../src/middlewares/trackLoginAttempt');
const { _test: ce } = require('../src/controllers/clientEventController');

describe('watchdog lib', () => {
  test('classifyLogLine: database errors are critical', () => {
    const c = lib.classifyLogLine('2026-10-12T10:00:00: MongoServerSelectionError: connection timed out', true);
    expect(c).toMatchObject({ severity: 'critical', key: 'db-error' });
  });

  test('classifyLogLine: known noise is ignored, other errors grouped by signature', () => {
    expect(lib.classifyLogLine('2026-10-12T10:00:00: ⚠️  [GiftNiftyFeed] NSEIX tick stale (12s old) — skipping.', true)).toBeNull();
    expect(lib.classifyLogLine('2026-10-12T10:00:00: [MarketCalendar] MCX refresh failed', true)).toBeNull();
    const a = lib.classifyLogLine('2026-10-12T10:00:00: [BSE] ⚠️ Download failed: Parse Error at 123', true);
    const b = lib.classifyLogLine('2026-10-12T11:00:00: [BSE] ⚠️ Download failed: Parse Error at 456', true);
    expect(a.generic).toBe(true);
    expect(a.key).toBe(b.key);
    expect(lib.classifyLogLine('2026-10-12T10:00:00: all good', true)).toBeNull();
    expect(lib.classifyLogLine('2026-10-12T10:00:00: Error in something', false)).toBeNull(); // out log: only known rules
  });

  test('classifyLogLine: Kite feed problems', () => {
    expect(lib.classifyLogLine('2026-10-12T10:00:00: ⚠️ Kite WebSocket closed (1006)', false)).toMatchObject({ key: 'kite-feed' });
  });

  test('signature hides ids, numbers, quotes and tokens', () => {
    expect(lib.signature('User 6abdec4724b6774d9f7d00c2 failed 3 times "x"'))
      .toBe(lib.signature('User 6aba0094025e6bfff5ea4da1 failed 12 times "yy"'));
    expect(lib.signature('token eyJhbGciOi.eyJpZCI6.abc123')).toBe('token <token>');
  });

  test('parseNginxLine', () => {
    const l = lib.parseNginxLine('1.2.3.4 - - [12/Oct/2026:16:32:00 +0000] "GET /api/watchlist HTTP/1.1" 502 157 "-" "Dart/3.13"');
    expect(l).toEqual({ ip: '1.2.3.4', time: '12/Oct/2026:16:32:00 +0000', method: 'GET', path: '/api/watchlist', status: 502 });
    expect(lib.SENSITIVE_PATH.test('/app/.env')).toBe(true);
    expect(lib.SENSITIVE_PATH.test('/api/trade')).toBe(false);
  });

  test('shouldSend cooldowns', () => {
    const sent = {};
    expect(lib.shouldSend(sent, 'k', 'warning', 0)).toBe(true);
    expect(lib.shouldSend(sent, 'k', 'warning', 10 * 60_000)).toBe(false);
    expect(lib.shouldSend(sent, 'k', 'warning', 16 * 60_000)).toBe(true);
    expect(lib.shouldSend(sent, 'c', 'critical', 0)).toBe(true);
    expect(lib.shouldSend(sent, 'c', 'critical', 5 * 60_000)).toBe(true);
  });

  test('market windows (IST)', () => {
    // Mon 12 Oct 2026 10:00 IST
    expect(lib.inMarketHours(Date.parse('2026-10-12T04:30:00Z'))).toEqual({ nse: true, mcx: true });
    // Mon 22:00 IST: MCX only
    expect(lib.inMarketHours(Date.parse('2026-10-12T16:30:00Z'))).toEqual({ nse: false, mcx: true });
    // Sat
    expect(lib.inMarketHours(Date.parse('2026-10-17T04:30:00Z'))).toEqual({ nse: false, mcx: false });
    expect(lib.inGiftSession(Date.parse('2026-10-12T22:00:00Z'))).toBe(false); // 03:30 IST
  });

  test('formatAlert escapes HTML', () => {
    expect(lib.formatAlert('warning', 'A <b>', ['x & y'])).toBe('🟠 <b>A &lt;b&gt;</b>\nx &amp; y');
  });

  test('isRuleRefusal', () => {
    expect(lib.isRuleRefusal('Insufficient NSE OPT wallet balance. Required ₹3334.50')).toBe(true);
    expect(lib.isRuleRefusal('Maximum allowed quantity is 10 for this instrument.')).toBe(true);
    expect(lib.isRuleRefusal('Cannot read properties of undefined')).toBe(false);
  });
});

describe('trackLoginAttempt', () => {
  test('records a failed login without the password, never a success', async () => {
    const eventLog = require('../src/utils/eventLog');
    const spy = jest.spyOn(eventLog, 'recordLoginFailure').mockImplementation(() => {});
    // re-require so the middleware picks up the spied function
    jest.resetModules();
    jest.doMock('../src/utils/eventLog', () => ({ ...eventLog, recordLoginFailure: spy }));
    const { trackLoginAttempt: track } = require('../src/middlewares/trackLoginAttempt');
    const mk = (status) => {
      const res = { statusCode: status, json: jest.fn() };
      return res;
    };
    const req = { body: { username: 'abc', password: 'secret' }, headers: { 'x-forwarded-for': '9.9.9.9, 1.1.1.1', 'user-agent': 'UA' } };
    const bad = mk(401);
    track('universal')(req, bad, () => {});
    bad.json({ success: false, message: 'Invalid credentials' });
    expect(spy).toHaveBeenCalledWith(expect.objectContaining({ route: 'universal', username: 'abc', status: 401, reason: 'Invalid credentials', ip: '9.9.9.9' }));
    expect(JSON.stringify(spy.mock.calls)).not.toContain('secret');
    spy.mockClear();
    const ok = mk(200);
    track('universal')(req, ok, () => {});
    ok.json({ success: true });
    expect(spy).not.toHaveBeenCalled();
    jest.dontMock('../src/utils/eventLog');
  });

  test('exported factory exists', () => {
    expect(typeof trackLoginAttempt('user')).toBe('function');
  });
});

describe('client events', () => {
  test('cleanContext keeps short scalars only', () => {
    expect(ce.cleanContext({ symbol: 'CRUDEOIL', qty: 1, ok: true, nested: { a: 1 }, 'bad.key$': 'x' }))
      .toEqual({ symbol: 'CRUDEOIL', qty: 1, ok: true, bad_key_: 'x' });
    expect(ce.cleanContext(null)).toEqual({});
  });

  test('rate limit: 60 per minute per key', () => {
    ce.buckets.clear();
    expect(ce.allow('k', 50)).toBe(50);
    expect(ce.allow('k', 20)).toBe(10);
    expect(ce.allow('k', 5)).toBe(0);
  });
});

describe('multi-line error dumps', () => {
  test('only the first line of a dumped error counts', () => {
    const l = require('../scripts/watchdog/lib');
    const lines = [
      ['2026-10-13T10:58:57: ❌ Error fetching historical data: AxiosError: Request failed with status code 400', true],
      ['2026-10-13T10:58:57:   isAxiosError: true,', false],
      ['2026-10-13T10:58:57: _hadError: false,', false],
      ['2026-10-13T10:58:57:     at settle (/x/axios.cjs:1:1)', false],
      ['2026-10-13T10:58:57: }', false],
      ['2026-10-13T10:58:57:   "message": "invalid token",', false],
      ['2026-10-13T10:58:57: [BSE] ⚠️ Download failed: Parse Error', true],
    ];
    for (const [line, alert] of lines) expect(Boolean(l.classifyLogLine(line, true))).toBe(alert);
  });
});
