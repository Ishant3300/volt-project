'use strict';

// A master may set script-quantity limits for itself, any sub-broker below
// it, and any client anywhere in its tree — previously only its direct
// clients (sub-brokers and sub-brokers' clients were always refused).

jest.mock('../src/models/User', () => ({ findById: jest.fn() }));
jest.mock('../src/models/Master', () => ({ findById: jest.fn() }));
jest.mock('../src/models/GroupedQuantity', () => ({ findOne: jest.fn() }));
jest.mock('../src/models/ScriptQuantity', () => ({ findOne: jest.fn() }));
jest.mock('../src/services/masterHierarchyService', () => ({ getAllSubMasterIds: jest.fn() }));

const User = require('../src/models/User');
const Master = require('../src/models/Master');
const GroupedQuantity = require('../src/models/GroupedQuantity');
const ScriptQuantity = require('../src/models/ScriptQuantity');
const { getAllSubMasterIds } = require('../src/services/masterHierarchyService');
const { masterScriptQtyGate } = require('../src/services/scriptQuantityGate');

// `Model.findById(id).select(...).lean()` / `Model.findOne(q).lean()` chains.
const selectLean = (v) => ({ select: () => ({ lean: () => Promise.resolve(v) }) });
const lean = (v) => ({ lean: () => Promise.resolve(v) });

// Tree: harry → sub1 → sub2; client c1 under sub2; outsider elsewhere.
beforeEach(() => {
  jest.clearAllMocks();
  getAllSubMasterIds.mockResolvedValue(['harry', 'sub1', 'sub2']);
  ScriptQuantity.findOne.mockReturnValue(lean({ max_qty: 500 }));
  GroupedQuantity.findOne.mockImplementation((q) => lean(q.lot_name === 'GOLDMIN' ? { max_qty: 300 } : null));
});

test('own row: capped by Admin global', async () => {
  await expect(masterScriptQtyGate('harry', 'harry', 'Master', 'NFO-FUT', 'NIFTY')).resolves.toEqual({ ceiling: 500 });
});

test('client under a sub-broker (not direct): allowed, capped by the client group', async () => {
  User.findById.mockReturnValue(selectLean({ master_id: 'sub2', exchanges_allowed: [{ exchange_name: 'NFO-FUT', group_name: 'GOLDMIN' }] }));
  await expect(masterScriptQtyGate('harry', 'c1', 'User', 'NFO-FUT', 'NIFTY')).resolves.toEqual({ ceiling: 300 });
});

test('client outside the tree: refused', async () => {
  User.findById.mockReturnValue(selectLean({ master_id: 'someoneElse', exchanges_allowed: [] }));
  const r = await masterScriptQtyGate('harry', 'x1', 'User', 'NFO-FUT', 'NIFTY');
  expect(r.error.status).toBe(403);
});

test('client with no group for the exchange: 400 (cap unknown)', async () => {
  User.findById.mockReturnValue(selectLean({ master_id: 'sub1', exchanges_allowed: [] }));
  const r = await masterScriptQtyGate('harry', 'c1', 'User', 'NFO-FUT', 'NIFTY');
  expect(r.error.status).toBe(400);
});

test('sub-broker with its own group: allowed, capped by that group', async () => {
  Master.findById.mockReturnValue(selectLean({ script_quantity_groups: [{ exchange_name: 'NFO-FUT', group_name: 'GOLDMIN' }] }));
  await expect(masterScriptQtyGate('harry', 'sub2', 'Master', 'nfo-fut', 'NIFTY')).resolves.toEqual({ ceiling: 300 });
});

test('sub-broker with no group: allowed, capped by Admin global', async () => {
  Master.findById.mockReturnValue(selectLean({ script_quantity_groups: [] }));
  await expect(masterScriptQtyGate('harry', 'sub1', 'Master', 'NFO-FUT', 'NIFTY')).resolves.toEqual({ ceiling: 500 });
});

test('master outside the tree (e.g. own parent / a sibling): refused', async () => {
  const r = await masterScriptQtyGate('harry', 'parentOfHarry', 'Master', 'NFO-FUT', 'NIFTY');
  expect(r.error.status).toBe(403);
  expect(Master.findById).not.toHaveBeenCalled();
});

test('unknown owner type: refused', async () => {
  const r = await masterScriptQtyGate('harry', 'a1', 'Admin', 'NFO-FUT', 'NIFTY');
  expect(r.error.status).toBe(403);
});
