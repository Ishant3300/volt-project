'use strict';

// A master's blocked scripts (max_qty 0) carry to every client it creates or
// moves to another group (26 Oct 2026): KK20 had blocked 11 scripts, but a new
// client would have got them from the group. Only blocks carry — every other
// limit still comes from the group — and only the client's DIRECT master's.

const mockInserted = [];
let mockGroupRows = [];
let mockMasterRows = [];
jest.mock('../src/models/GroupedQuantity', () => ({ find: () => ({ lean: async () => mockGroupRows, session: () => ({ lean: async () => mockGroupRows }) }) }));
jest.mock('../src/models/User', () => ({ findById: () => { const q = { select: () => q, session: () => q, lean: async () => ({ master_id: 'kk20' }) }; return q; } }));
jest.mock('../src/models/Master', () => ({}));
jest.mock('../src/models/ScriptQuantity', () => ({
  find: (query) => {
    const rows = mockMasterRows.filter((r) => query.owner_id === 'kk20' && query.exchange_name.$in.includes(r.exchange_name) && r.max_qty === 0);
    const q = { select: () => q, session: () => q, lean: async () => rows };
    return q;
  },
  insertMany: async (docs) => { mockInserted.push(...docs); },
  updateMany: async () => ({ modifiedCount: 0 }),
}));

const { seedUserScriptQuantityFromGroups, reseedUserScriptQuantityForExchange } = require('../src/services/scriptQuantityCopyService');

const group = (raw_name, max_qty, break_qty) => ({ raw_name, max_qty, break_qty, lot_size: 1 });
const masterRow = (exchange_name, script_name, max_qty) => ({ exchange_name, script_name, max_qty, brk_qty: 0, lot_size: 1 });
const byScript = () => Object.fromEntries(mockInserted.map((d) => [`${d.exchange_name} ${d.script_name}`, `${d.max_qty}/${d.brk_qty}`]));

beforeEach(() => { mockInserted.length = 0; mockGroupRows = []; mockMasterRows = []; });

test('new client: a script the master blocked is 0, the rest come from the group', async () => {
  mockGroupRows = [group('GOLD', 5, 2), group('GOLDM', 10, 5), group('SILVER', 5, 2)];
  mockMasterRows = [masterRow('MCX-FUT', 'GOLD', 0), masterRow('MCX-FUT', 'GOLDM', 3)];
  await seedUserScriptQuantityFromGroups('u1', [{ exchange_name: 'MCX-FUT', group_name: 'GOLDMIN' }]);
  expect(byScript()).toEqual({ 'MCX-FUT GOLD': '0/0', 'MCX-FUT GOLDM': '10/5', 'MCX-FUT SILVER': '5/2' });
});

test('a script the master blocked that the group does not list still gets a 0 row (no row = no limit)', async () => {
  mockGroupRows = [group('GOLD', 5, 2)];
  mockMasterRows = [masterRow('MCX-FUT', 'ZINC', 0)];
  await seedUserScriptQuantityFromGroups('u1', [{ exchange_name: 'MCX-FUT', group_name: 'GOLDMIN' }]);
  expect(byScript()).toEqual({ 'MCX-FUT GOLD': '5/2', 'MCX-FUT ZINC': '0/0' });
});

test('blocks only apply to their own exchange', async () => {
  mockGroupRows = [group('IDEA', 5, 2)];
  mockMasterRows = [masterRow('NFO-OPT', 'IDEA', 0)];
  await seedUserScriptQuantityFromGroups('u1', [{ exchange_name: 'NFO-FUT', group_name: 'HRY 3 LOT' }]);
  expect(byScript()).toEqual({ 'NFO-FUT IDEA': '5/2' });
});

test('group change: the new group with the master blocks on top', async () => {
  mockGroupRows = [group('ANGELONE', 4, 2), group('IDEA', 4, 2)];
  mockMasterRows = [masterRow('NFO-OPT', 'IDEA', 0)];
  // A session is passed so the re-seed runs on the stubbed models (without one it opens its own
  // transaction, 9 Nov 2026 — covered against a real MongoDB in editSafety.integration.test.js).
  const result = await reseedUserScriptQuantityForExchange('u1', 'NFO-OPT', '4 LOT NEW', {});
  expect(result).toEqual({ ok: true, count: 2 });
  expect(byScript()).toEqual({ 'NFO-OPT ANGELONE': '4/2', 'NFO-OPT IDEA': '0/0' });
});

test('master blocks nothing → exactly the group, as before', async () => {
  mockGroupRows = [group('GOLD', 5, 2)];
  await seedUserScriptQuantityFromGroups('u1', [{ exchange_name: 'MCX-FUT', group_name: 'GOLDMIN' }]);
  expect(byScript()).toEqual({ 'MCX-FUT GOLD': '5/2' });
});
