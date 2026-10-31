'use strict';

// Kite token check asks Kite itself (1 Nov 2026): on Sat 31 Oct Kite had
// dropped the token while the saved-expiry check still said "valid", so the
// hourly auto re-login never ran. Only Kite's own "token invalid" answer
// counts as rejected; no answer (timeout / network / 5xx) trusts the DB.

jest.mock('axios', () => ({ get: jest.fn() }));
jest.mock('../src/models/KiteConfig', () => ({ AccessToken: { findOne: jest.fn() } }));

const axios = require('axios');
const kiteService = require('../src/services/kiteService');

const httpError = (status, data) => Object.assign(new Error('http'), { response: { status, data } });

describe('kiteService.checkAccessTokenWithKite', () => {
  beforeEach(() => axios.get.mockReset());

  test('success -> valid', async () => {
    axios.get.mockResolvedValue({ data: { status: 'success', data: { user_id: 'AB1234' } } });
    expect(await kiteService.checkAccessTokenWithKite('tok')).toBe('valid');
    expect(axios.get.mock.calls[0][1].timeout).toBe(8000);
  });

  test("Kite's TokenException -> rejected", async () => {
    axios.get.mockRejectedValue(httpError(403, { status: 'error', error_type: 'TokenException', message: 'Incorrect `api_key` or `access_token`.' }));
    expect(await kiteService.checkAccessTokenWithKite('tok')).toBe('rejected');
  });

  test('timeout, network error, 5xx, other 403 types -> unknown (not a rejection)', async () => {
    axios.get.mockRejectedValueOnce(Object.assign(new Error('timeout of 8000ms exceeded'), { code: 'ECONNABORTED' }));
    expect(await kiteService.checkAccessTokenWithKite('tok')).toBe('unknown');
    axios.get.mockRejectedValueOnce(httpError(503, { status: 'error', error_type: 'NetworkException' }));
    expect(await kiteService.checkAccessTokenWithKite('tok')).toBe('unknown');
    axios.get.mockRejectedValueOnce(httpError(403, { status: 'error', error_type: 'PermissionException' }));
    expect(await kiteService.checkAccessTokenWithKite('tok')).toBe('unknown');
  });
});

describe('kiteAuthService.checkTokenStatus', () => {
  const { AccessToken } = require('../src/models/KiteConfig');
  let kiteAuthService;
  beforeAll(() => { kiteAuthService = require('../src/services/kiteAuthService'); });
  beforeEach(() => {
    axios.get.mockReset();
    kiteAuthService._liveCheckCache = null;
    jest.spyOn(kiteService, 'getStoredAccessToken').mockResolvedValue('tok-1');
    const future = new Date(Date.now() + 10 * 3600 * 1000);
    AccessToken.findOne.mockReturnValue({ sort: async () => ({ access_token: 'tok-1', expires_at: future }) });
  });

  test('Kite rejects the token -> not valid (so the auto re-login runs), reason names Kite', async () => {
    axios.get.mockRejectedValue(httpError(403, { error_type: 'TokenException' }));
    const s = await kiteAuthService.checkTokenStatus();
    expect(s.valid).toBe(false);
    expect(s.reason).toMatch(/invalid — rejected by Kite/);
  });

  test('Kite does not answer -> still valid on the saved expiry (no needless re-login)', async () => {
    axios.get.mockRejectedValue(Object.assign(new Error('ETIMEDOUT'), { code: 'ETIMEDOUT' }));
    const s = await kiteAuthService.checkTokenStatus();
    expect(s.valid).toBe(true);
    expect(s.live).toBe('unknown');
  });

  test('one Kite call per token per 5 minutes', async () => {
    axios.get.mockResolvedValue({ data: { status: 'success' } });
    await kiteAuthService.checkTokenStatus();
    await kiteAuthService.checkTokenStatus();
    expect(axios.get).toHaveBeenCalledTimes(1);
    kiteService.getStoredAccessToken.mockResolvedValue('tok-2'); // a fresh login = a fresh check
    AccessToken.findOne.mockReturnValue({ sort: async () => ({ access_token: 'tok-2', expires_at: new Date(Date.now() + 10 * 3600 * 1000) }) });
    await kiteAuthService.checkTokenStatus();
    expect(axios.get).toHaveBeenCalledTimes(2);
  });

  test('expired by the saved time -> not valid without asking Kite', async () => {
    AccessToken.findOne.mockReturnValue({ sort: async () => ({ access_token: 'tok-1', expires_at: new Date(Date.now() - 1000) }) });
    const s = await kiteAuthService.checkTokenStatus();
    expect(s.valid).toBe(false);
    expect(axios.get).not.toHaveBeenCalled();
  });
});
