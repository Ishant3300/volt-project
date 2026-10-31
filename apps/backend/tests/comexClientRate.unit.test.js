'use strict';

// COMEX rate per account (1 Nov 2026): a master or client may have their own
// dollar rate + spread (set where COMEX is ticked); without one an account
// inherits the nearest master above with one, else admin's default. A master
// can't give an account below him a lower rate or spread than the master
// directly above it. The settlement converts each client at the client's rate.

jest.mock('../src/models/SettlementRun', () => ({ findOne: jest.fn() }));
jest.mock('../src/models/ComexRate', () => ({ find: jest.fn(), findOne: jest.fn(), findOneAndUpdate: jest.fn() }));
jest.mock('../src/models/User', () => ({ findOne: jest.fn(), find: jest.fn() }));
jest.mock('../src/models/Master', () => ({ findOne: jest.fn(), find: jest.fn() }));
jest.mock('../src/services/masterHierarchyService', () => ({ getAllSubMasterIds: jest.fn() }));
jest.mock('../src/utils/adminVisibility', () => ({ resolveHiddenMasterIds: jest.fn(async () => null) }));

const SettlementRun = require('../src/models/SettlementRun');
const ComexRate = require('../src/models/ComexRate');
const User = require('../src/models/User');
const Master = require('../src/models/Master');
const { getAllSubMasterIds } = require('../src/services/masterHierarchyService');
const fx = require('../src/utils/comexFx');
const ctl = require('../src/controllers/comexRateController');

const chain = (v) => { const c = {}; c.select = jest.fn(() => c); c.session = jest.fn(() => c); c.lean = jest.fn(async () => v); return c; };
const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };
const snap = (user, exchange, total, brk) => ({ user_id: user, exchange, realized_pnl: total, settlement_pnl: 0, total_pnl: total, brokerage: brk, net_pnl: total - brk });

// Tree: TOP (own 88.5 ± 1.5) → SUB (no own rate) → clients A (own 90 ± 2), B (none)
//       OTHER (no rate) → client C (none)          admin default 88 ± 1
const TOP = '64a000000000000000000001';
const SUB = '64a000000000000000000002';
const OTHER = '64a000000000000000000003';
const A = '64b000000000000000000001';
const B = '64b000000000000000000002';
const C = '64b000000000000000000003';
const MASTERS = [{ _id: TOP, master_id: null }, { _id: SUB, master_id: TOP }, { _id: OTHER, master_id: null }];
const USERS = [{ _id: A, master_id: SUB }, { _id: B, master_id: SUB }, { _id: C, master_id: OTHER }];
const DOCS = [
  { key: 'comex', base: 88, spread: 1 },
  { key: `master:${TOP}`, base: 88.5, spread: 1.5, active: true },
  { key: `user:${A}`, base: 90, spread: 2, active: true },
  { key: `user:${B}`, base: 70, spread: 5, active: false }, // removed → inherits
];
const withDocs = (docs) => ComexRate.find.mockImplementation((q) => chain(docs.filter((d) => q.key.$in.includes(d.key))));

beforeEach(() => {
  jest.clearAllMocks();
  withDocs(DOCS);
  Master.find.mockReturnValue(chain(MASTERS));
  User.find.mockImplementation((q) => chain(USERS.filter((u) => q._id.$in.includes(u._id))));
  SettlementRun.findOne.mockReturnValue(chain(null));
});

test('lookup: own → nearest master above → admin default; removed own rate inherits', async () => {
  const fxFor = await fx.loadComexFxResolver([A, B, C], null, { masterIds: [SUB, OTHER] });
  expect(fxFor(A)).toEqual({ base: 90, spread: 2, source: 'client' });
  expect(fxFor(B)).toEqual({ base: 88.5, spread: 1.5, source: 'master', master_id: TOP });
  expect(fxFor(C)).toEqual({ base: 88, spread: 1, source: 'default' });
  expect(fxFor.forMaster(SUB)).toMatchObject({ base: 88.5, source: 'master' });
  expect(fxFor.forMaster(OTHER)).toMatchObject({ base: 88, source: 'default' });
  expect(await fx.loadComexFx()).toEqual({ base: 88, spread: 1, source: 'default' });
  expect(await fx.loadMasterComexFx(SUB)).toMatchObject({ base: 88.5, spread: 1.5 });
  withDocs([]);
  expect((await fx.loadComexFxResolver([C]))(C)).toBeNull();
});

test('settlement: each client at their own / inherited rate, debit/credit by their own COMEX net', async () => {
  const a = [snap(A, 'COMEX', -10000, 0)]; // own 90 ± 2, debit → 92
  const b = [snap(B, 'COMEX', 10000, 0)]; // TOP 88.5 ± 1.5, credit → 87
  const c = [snap(C, 'COMEX', -10000, 0)]; // default 88 ± 1, debit → 89
  const nfo = snap(A, 'NFO', 5000, 100);
  const all = [...a, ...b, ...c, nfo];
  const out = fx.convertComexSnapshots(all, await fx.loadComexFxResolver([A, B, C]));
  expect(out.rates).toEqual({ [A]: 92, [B]: 87, [C]: 89 });
  expect(a[0]).toMatchObject({ net_pnl: -920000, usd_net_pnl: -10000, fx_rate: 92, fx_base: 90, fx_spread: 2 });
  expect(b[0]).toMatchObject({ net_pnl: 870000, fx_rate: 87, fx_base: 88.5, fx_spread: 1.5 });
  expect(c[0]).toMatchObject({ net_pnl: -890000, fx_rate: 89, fx_base: 88 });
  expect(nfo).toEqual(snap(A, 'NFO', 5000, 100));
});

test('settlement: COMEX amounts and no rate anywhere still stops the run', async () => {
  withDocs([{ key: `user:${A}`, base: 90, spread: 2 }]);
  const fxFor = await fx.loadComexFxResolver([A, C]);
  expect(() => fx.convertComexSnapshots([snap(A, 'COMEX', 100, 0), snap(C, 'COMEX', 100, 0)], fxFor)).toThrow(/rate is not set/);
});

test('combined view: same rate for all = that rate; different = default flagged mixed', async () => {
  expect(await fx.loadComexFxForUsers([B])).toMatchObject({ base: 88.5, source: 'master' });
  expect(await fx.loadComexFxForUsers([A, C])).toEqual({ base: 88, spread: 1, source: 'default', mixed: true });
  expect(await fx.loadComexFxForReport({ user_id: A }, [], [])).toMatchObject({ base: 90 });
  const block = fx.comexBillBlock([{ exchange: 'COMEX', pnl: -1000, brokerage: 0 }], [], await fx.loadComexFx(null, A));
  expect(block.fx).toMatchObject({ base: 90, spread: 2, debit_rate: 92, credit_rate: 88, source: 'client', mixed: false });
  expect(block.estimate).toMatchObject({ fx_rate: 92, inr_net: -92000 });
});

test('limit: neither dollar rate nor spread below the master above', () => {
  const floor = { base: 88.5, spread: 1.5 };
  expect(fx.belowFloorMessage({ base: 88.5, spread: 1.5 }, floor)).toBeNull();
  expect(fx.belowFloorMessage({ base: 89, spread: 2 }, floor)).toBeNull();
  expect(fx.belowFloorMessage({ base: 88.4, spread: 2 }, floor)).toMatch(/at least 88.5/);
  expect(fx.belowFloorMessage({ base: 90, spread: 1 }, floor)).toMatch(/spread at least 1.5/);
  expect(fx.belowFloorMessage({ base: 1, spread: 0 }, null)).toBeNull();
});

describe('endpoints', () => {
  const clientB = { _id: B, username: '700002', name: 'Client B', master_id: SUB };
  const saved = (extra) => chain({ base: 89, spread: 2, active: true, history: [{ base: 89, spread: 2, by: 'TOPM' }], ...extra });
  beforeEach(() => {
    getAllSubMasterIds.mockResolvedValue([TOP, SUB]);
    User.findOne.mockReturnValue(chain(clientB));
    ComexRate.findOne.mockReturnValue(chain(null));
    ComexRate.findOneAndUpdate.mockReturnValue(saved());
  });

  test('a master sets a client below him at or above the limit — validated, logged', async () => {
    let r = res();
    await ctl.setClientComexRate({ params: { id: B }, body: { base: 88, spread: 2 }, master: { id: TOP, username: 'TOPM' } }, r);
    expect(r.status).toHaveBeenCalledWith(400); // 88 < SUB's inherited 88.5
    expect(r.json.mock.calls[0][0].message).toMatch(/at least 88.5/);
    expect(ComexRate.findOneAndUpdate).not.toHaveBeenCalled();
    r = res();
    await ctl.setClientComexRate({ params: { id: B }, body: { base: '89', spread: '2' }, master: { id: TOP, username: 'TOPM' } }, r);
    expect(r.status).toHaveBeenCalledWith(200);
    const [filter, update, opts] = ComexRate.findOneAndUpdate.mock.calls[0];
    expect(filter).toEqual({ key: `user:${B}` });
    expect(update.$set).toMatchObject({ user_id: B, active: true, base: 89, spread: 2, updated_by: 'TOPM' });
    expect(update.$push.history.$each[0]).toMatchObject({ base: 89, spread: 2, by: 'TOPM' });
    expect(opts.upsert).toBe(true);
    const data = r.json.mock.calls[0][0].data;
    expect(data.own).toMatchObject({ debit_rate: 91, credit_rate: 87 });
    expect(data.floor).toMatchObject({ base: 88.5, spread: 1.5 });
  });

  test('admin is not limited', async () => {
    const r = res();
    await ctl.setClientComexRate({ params: { id: B }, body: { base: 80, spread: 0.5 }, admin: { username: 'admin' } }, r);
    expect(r.status).toHaveBeenCalledWith(200);
  });

  test("a master can't touch accounts outside his tree, nor change his own rate", async () => {
    User.findOne.mockReturnValue(chain({ _id: C, master_id: OTHER }));
    let r = res();
    await ctl.setClientComexRate({ params: { id: C }, body: { base: 90, spread: 2 }, master: { id: TOP } }, r);
    expect(r.status).toHaveBeenCalledWith(403);
    Master.findOne.mockReturnValue(chain({ _id: TOP, master_id: null }));
    r = res();
    await ctl.setMasterComexRate({ params: { id: TOP }, body: { base: 90, spread: 2 }, master: { id: TOP } }, r);
    expect(r.status).toHaveBeenCalledWith(403);
    r = res();
    await ctl.getMasterComexRate({ params: { id: TOP }, master: { id: TOP } }, r); // reading his own is fine
    expect(r.status).toHaveBeenCalledWith(200);
    expect(ComexRate.findOneAndUpdate).not.toHaveBeenCalled();
  });

  test('a master sets his sub-master, limited by his own rate', async () => {
    Master.findOne.mockReturnValue(chain({ _id: SUB, username: 'SUBM', master_id: TOP }));
    let r = res();
    await ctl.setMasterComexRate({ params: { id: SUB }, body: { base: 88.5, spread: 1 }, master: { id: TOP } }, r);
    expect(r.status).toHaveBeenCalledWith(400); // spread 1 < 1.5
    r = res();
    await ctl.setMasterComexRate({ params: { id: SUB }, body: { base: 88.5, spread: 1.5 }, master: { id: TOP } }, r);
    expect(r.status).toHaveBeenCalledWith(200);
    expect(ComexRate.findOneAndUpdate.mock.calls[0][1].$set).toMatchObject({ master_id: SUB });
  });

  test('refused while a settlement runs', async () => {
    SettlementRun.findOne.mockReturnValue(chain({ _id: 'run' }));
    const r = res();
    await ctl.setClientComexRate({ params: { id: B }, body: { base: 89, spread: 2 }, admin: { username: 'admin' } }, r);
    expect(r.status).toHaveBeenCalledWith(409);
    const r2 = res();
    await ctl.clearClientComexRate({ params: { id: B }, admin: { username: 'admin' } }, r2);
    expect(r2.status).toHaveBeenCalledWith(409);
    expect(ComexRate.findOneAndUpdate).not.toHaveBeenCalled();
  });

  test('removing an own rate marks it inactive and logs it', async () => {
    ComexRate.findOne.mockReturnValue(chain({ key: `user:${B}`, base: 89, spread: 2, active: true, history: [] }));
    ComexRate.findOneAndUpdate.mockReturnValue(saved({ active: false }));
    const r = res();
    await ctl.clearClientComexRate({ params: { id: B }, admin: { username: 'admin' } }, r);
    expect(r.status).toHaveBeenCalledWith(200);
    const [, update] = ComexRate.findOneAndUpdate.mock.calls[0];
    expect(update.$set).toMatchObject({ active: false, updated_by: 'admin' });
    expect(update.$push.history.$each[0]).toMatchObject({ cleared: true, base: 89, spread: 2 });
    const data = r.json.mock.calls[0][0].data;
    expect(data.own).toBeNull();
    expect(data.effective).toMatchObject({ base: 88.5, source: 'master' }); // inherits from TOP
  });
});
