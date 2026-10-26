'use strict';

// Edit-account fixes (26 Oct 2026, Admin03 editing 801351 from the app):
//  1. An inline wallet top-up the parent master can't cover used to be found
//     only AFTER the profile was saved — the app showed "insufficient" while
//     the settings had gone through. walletController.checkWalletFunding now
//     refuses the whole edit before anything is saved.
//  2. An exchange sent with an empty group failed User validation as a vague
//     500. An empty group now keeps the exchange's current group; an exchange
//     with no group at all gets a clear 400.

jest.mock('../src/models/User', () => ({ findById: jest.fn(), findOne: jest.fn() }));
jest.mock('../src/models/Master', () => ({ findById: jest.fn() }));
jest.mock('../src/services/scriptQuantityCopyService', () => ({ reseedUserScriptQuantityForExchange: jest.fn(), isGroupAllotted: jest.fn(() => true) }));
jest.mock('../src/services/walletService', () => ({
  assign: jest.fn(),
  withdraw: jest.fn(),
  getAvailable: jest.fn(),
  reconcile: jest.fn(),
  CATEGORIES: ['NSE', 'MCX', 'COMEX'],
  INSUFFICIENT_WALLET: 'INSUFFICIENT_WALLET',
}));

const User = require('../src/models/User');
const Master = require('../src/models/Master');
const walletService = require('../src/services/walletService');
const { checkWalletFunding } = require('../src/controllers/walletController');
const { updateUser } = require('../src/controllers/adminController');
const { updateUserDetails } = require('../src/controllers/masterUserController');

const lean = (value) => ({ select: () => ({ lean: async () => value }) });
// Master.findById serves both the payer-wallet read and the profit-book base read.
const masterWith = (wallet) => Master.findById.mockImplementation(() => lean({ wallet, profit_book_base_minutes: 0 }));

function userDoc(groups) {
  return {
    _id: 'u1',
    master_id: 'm1',
    active_status: true,
    exchanges_allowed: groups.map(([exchange_name, group_name]) => ({ exchange_name, turnover: true, lot: false, group_name })),
    save: jest.fn().mockResolvedValue(),
    toJSON() { return { id: 'u1' }; },
  };
}
const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };
const ex = (exchange_name, group_name) => ({ exchange_name, turnover: true, lot: false, group_name });

beforeEach(() => {
  jest.clearAllMocks();
  User.findById.mockImplementation(() => lean({ master_id: 'm1' }));
});

describe('checkWalletFunding (read-only pre-check)', () => {
  test('parent master short in a category → INSUFFICIENT_WALLET with that category, nothing moved', async () => {
    masterWith({ NSE: 1000, COMEX: 50 });
    await expect(checkWalletFunding({ req: { master: { id: 'm1' }, body: {} }, targetType: 'User', targetId: 'u1', walletMap: { NSE: 500, COMEX: 100 } }))
      .rejects.toMatchObject({ code: 'INSUFFICIENT_WALLET', category: 'COMEX' });
    expect(walletService.assign).not.toHaveBeenCalled();
  });

  test('enough in every category → passes', async () => {
    masterWith({ NSE: 1000, COMEX: 100 });
    await expect(checkWalletFunding({ req: { admin: { id: 'a1' }, body: {} }, targetType: 'User', targetId: 'u1', walletMap: { NSE: 1000, COMEX: 100 } })).resolves.toBeUndefined();
  });

  test('admin funding a master is a grant → no check', async () => {
    await checkWalletFunding({ req: { admin: { id: 'a1' }, body: {} }, targetType: 'Master', targetId: 'm2', walletMap: { NSE: 1e9 } });
    expect(Master.findById).not.toHaveBeenCalled();
  });

  test('no positive amounts → no check', async () => {
    await checkWalletFunding({ req: { master: { id: 'm1' }, body: {} }, targetType: 'User', targetId: 'u1', walletMap: { NSE: 0, MCX: -5 } });
    expect(User.findById).not.toHaveBeenCalled();
  });
});

// The admin route loads the client with `await User.findById(id)`, the master
// route with `User.findOne(query)`; the funding check reads the client's
// master with `User.findById(id).select().lean()`. loadUser serves all three.
function loadUser(u) {
  User.findOne.mockResolvedValue(u);
  User.findById.mockImplementation(() => Object.assign(Promise.resolve(u), lean({ master_id: 'm1' })));
}

describe.each([
  ['admin route (adminController.updateUser)', updateUser],
  ['master route (masterUserController.updateUserDetails)', updateUserDetails],
])('%s', (_label, handler) => {
  const edit = (body) => ({ params: { id: 'u1' }, admin: { id: 'a1' }, master: null, body });

  test('top-up the master cannot cover → 400 and the settings are NOT saved', async () => {
    const u = userDoc([['NFO-FUT', 'GOLDMIN']]);
    loadUser(u);
    masterWith({ NSE: 100 });
    const r = res();
    await handler(edit({ exchanges_allowed: [ex('NFO-FUT', 'GOLDMIN')], wallet: { NSE: 5000 } }), r);
    expect(r.status).toHaveBeenCalledWith(400);
    expect(r.json.mock.calls[0][0].message).toMatch(/Insufficient .* wallet balance/);
    expect(u.save).not.toHaveBeenCalled();
    expect(walletService.assign).not.toHaveBeenCalled();
  });

  test('empty group on an exchange that has one → keeps the current group, saves', async () => {
    const u = userDoc([['NFO-FUT', 'GOLDMIN'], ['COMEX-FUT', '10 LOT NEW']]);
    loadUser(u);
    masterWith({});
    const r = res();
    await handler(edit({ exchanges_allowed: [ex('NFO-FUT', 'GOLDMIN'), ex('COMEX-FUT', '')] }), r);
    expect(r.status).toHaveBeenCalledWith(200);
    expect(u.save).toHaveBeenCalled();
    expect(u.exchanges_allowed.find((e) => e.exchange_name === 'COMEX-FUT').group_name).toBe('10 LOT NEW');
  });

  test('new exchange with no group → clear 400, nothing saved', async () => {
    const u = userDoc([['NFO-FUT', 'GOLDMIN']]);
    loadUser(u);
    masterWith({});
    const r = res();
    await handler(edit({ exchanges_allowed: [ex('NFO-FUT', 'GOLDMIN'), ex('GLOBAL', '')] }), r);
    expect(r.status).toHaveBeenCalledWith(400);
    expect(r.json.mock.calls[0][0].message).toBe('Select a group for GLOBAL');
    expect(u.save).not.toHaveBeenCalled();
  });
});

// Min NSE FUT script price (utils/minScriptPrice.js) — saved by both edit routes.
describe.each([
  ['admin route', updateUser],
  ['master route', updateUserDetails],
])('min NSE FUT price — %s', (_label, handler) => {
  const edit = (body) => ({ params: { id: 'u1' }, admin: { id: 'a1' }, master: null, body });

  test('a value is saved (rounded to paise)', async () => {
    const u = userDoc([['NFO-FUT', 'GOLDMIN']]);
    loadUser(u);
    masterWith({});
    const r = res();
    await handler(edit({ min_nse_fut_price: '99.999' }), r);
    expect(r.status).toHaveBeenCalledWith(200);
    expect(u.min_nse_fut_price).toBe(100);
    expect(u.save).toHaveBeenCalled();
  });

  test('a negative value → 400, nothing saved', async () => {
    const u = userDoc([['NFO-FUT', 'GOLDMIN']]);
    loadUser(u);
    masterWith({});
    const r = res();
    await handler(edit({ min_nse_fut_price: -5 }), r);
    expect(r.status).toHaveBeenCalledWith(400);
    expect(u.save).not.toHaveBeenCalled();
  });

  test('not sent → left as it is', async () => {
    const u = { ...userDoc([['NFO-FUT', 'GOLDMIN']]), min_nse_fut_price: 50 };
    loadUser(u);
    masterWith({});
    await handler(edit({ note: 'x' }), res());
    expect(u.min_nse_fut_price).toBe(50);
  });
});
