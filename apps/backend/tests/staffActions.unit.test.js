'use strict';

// Admin/master change alerts: who changed what on a client (Telegram watchdog)
// and the backend record behind them (middlewares/auditActions.js).
const { _test: audit } = require('../src/middlewares/auditActions');
const { _test: w } = require('../scripts/watchdog/extra');

const ID = '6accf69e5d53b458126f6b98';

test('the audit record never keeps passwords, PINs or codes', () => {
  const body = audit.clean({ name: 'Ramesh', password: 'secret1', investor_password: 'x', totp_code: '123456', exchanges_allowed: [{ exchange_name: 'MCX-FUT', lot: true }] });
  expect(body).toEqual({ name: 'Ramesh', password: '[changed]', investor_password: '[changed]', totp_code: '[changed]', exchanges_allowed: [{ exchange_name: 'MCX-FUT', lot: true }] });
});

test('the accounts an action touched come from the path and the body', () => {
  expect(audit.targetIds(`/api/master/users/${ID}/details`, {})).toEqual([ID]);
  expect(audit.targetIds('/api/trade', { user_id: ID, quantity: 1 })).toEqual([ID]);
});

test('a group / lot-mode / new-exchange change reads as old → new', () => {
  const before = [{ exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: 'GOLDMIN' }];
  const after = [{ exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: 'HRY 3 LOT' }, { exchange_name: 'MCX-FUT', turnover: false, lot: true, group_name: 'Default' }];
  expect(w.exchangeDiff(before, after)).toEqual(['NFO-FUT: group name GOLDMIN → HRY 3 LOT', 'exchange MCX-FUT added (lot, group Default)']);
  expect(w.exchangeDiff(after, before)).toContain('exchange MCX-FUT removed');
});

test('on/off settings and object settings read plainly', () => {
  const who = (id) => `acct ${id}`;
  expect(w.fieldDiff('close_only', false, true, who)).toEqual(['close only off → on']);
  expect(w.fieldDiff('report_permissions', { ledger: true, pnl: false }, { ledger: true, pnl: true }, who)).toEqual(['report permissions pnl off → on']);
  expect(w.fieldDiff('master_id', 'a', 'b', who)).toEqual(['moved from acct a to acct b']);
  expect(w.fieldDiff('deleted_at', null, true, who)).toEqual(['deleted']);
});

test('which actions are reported by the specific alerts (no double messages)', () => {
  expect(w.COVERED_MONEY.test(`/api/admin/users/${ID}/credit`)).toBe(true);
  expect(w.COVERED_MONEY.test('/api/master/wallet/assign')).toBe(true);
  expect(w.COVERED_ACCOUNT.test(`/api/master/users/${ID}/details`)).toBe(true);
  expect(w.COVERED_ACCOUNT.test(`/api/admin/users/${ID}`)).toBe(true);
  expect(w.COVERED_ACCOUNT.test(`/api/masters/${ID}/permissions`)).toBe(true);
  expect(w.COVERED_ACCOUNT.test('/api/admin/brokerage-settings/bulk-update')).toBe(false);
  expect(`/api/trade/${ID}/modify`.match(w.TRADE_EDIT)[2]).toBe('modify');
});

test('a bulk brokerage edit is summarised, not dumped', () => {
  const s = w.summarizeBody({ user_id: ID, settings: Array.from({ length: 40 }, (_, i) => ({ exchange_name: 'NFO-FUT', script_name: `S${i}`, brk_value: 5 })) });
  expect(s).toBe('settings: 40 items (e.g. exchange_name=NFO-FUT script_name=S0 brk_value=5)');
});

test("a master's exchanges (plain names) read as added/removed", () => {
  expect(w.exchangeDiff(['NFO-FUT'], ['NFO-FUT', 'GLOBAL'])).toEqual(['exchange GLOBAL added']);
  expect(w.exchangeDiff(['NFO-FUT', 'MCX-FUT'], ['NFO-FUT'])).toEqual(['exchange MCX-FUT removed']);
});

test('account-creation requests are recognised (one summary instead of three messages)', () => {
  for (const p of ['/api/admin/users', '/api/master/users', '/api/master/masters', '/api/masters']) expect(w.CREATE_PATH.test(p)).toBe(true);
  expect(w.CREATE_PATH.test('/api/master/users/6accf69e5d53b458126f6b98/details')).toBe(false);
});

test("a client's first-login password change reads plainly", () => {
  const who = (id) => id;
  expect(w.fieldDiff('change_pass_on_first_login', true, false, who)).toEqual(['set their own password (first login)']);
  expect(w.fieldDiff('change_pass_on_first_login', false, true, who)).toEqual(['must set a new password at next login']);
});

test('a brokerage edit reads as account · segment · scripts: old → new; a re-save at the same rate says nothing', async () => {
  const { ObjectId } = require('mongoose').mongo;
  const born = Math.floor(Date.now() / 1000) - 3600; // rows created an hour ago
  const id1 = ObjectId.createFromTime(born); const id2 = ObjectId.createFromTime(born + 1);
  let current = 100;
  const rows = () => [{ _id: id1, user_id: 'm1', exchange_name: 'MCX-FUT', script_name: 'GOLD', brk_value: current, type: 'LOT WISE' },
    { _id: id2, user_id: 'm1', exchange_name: 'MCX-FUT', script_name: 'SILVER', brk_value: current, type: 'LOT WISE' }];
  const cur = (list) => ({ project() { return this; }, sort() { return this; }, limit() { return this; }, toArray: async () => list });
  const d = { collection: () => ({ find: () => cur(rows()), findOne: async () => null }) };
  const c = { d, who: () => 'master 833704 JNL' };
  const act = (v) => ({ path: '/api/admin/brokerage-settings/bulk-update', method: 'PUT', created_at: new Date(), body: { ids: [String(id1), String(id2)], brk_value: v, type: 'LOT WISE' } });
  await w.brokerageChanges(c, { path: '/x', body: {} }); // not brokerage
  const snapWarm = await w.brokerageChanges(c, act(100)); // first sight loads the snapshot (rates 100)
  expect(await w.brokerageChangeLines(c, snapWarm.map((g) => ({ by: 'admin S', g })))).toEqual([]); // 100 → 100: nothing
  current = 150;
  const changed = await w.brokerageChanges(c, act(150));
  expect(await w.brokerageChangeLines(c, changed.map((g) => ({ by: 'admin S', g })))).toEqual(['master 833704 JNL · MCX-FUT · 2 scripts: 100 per lot → 150 per lot · by admin S']);
});

test("a client's first-login password change reads plainly", () => {
  const who = (id) => id;
  expect(w.fieldDiff('change_pass_on_first_login', true, false, who)).toEqual(['set their own password (first login)']);
  expect(w.fieldDiff('change_pass_on_first_login', false, true, who)).toEqual(['must set a new password at next login']);
});
