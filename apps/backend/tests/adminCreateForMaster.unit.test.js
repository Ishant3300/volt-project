'use strict';

// Admin may create a sub-master or client under ANY master (for_master_id),
// exactly as if that master created it — gated by MASTER_EDIT_ANY, not
// watch-only, not a master hidden from this admin. Master callers unchanged.

jest.mock('../src/models/Master', () => ({ find: jest.fn(), exists: jest.fn() }));

const Master = require('../src/models/Master');
const { resolveCreateParentId } = require('../src/services/masterHierarchyService');

const X = '64b000000000000000000001';
const HIDDEN = '64b000000000000000000002';
const lean = (v) => ({ lean: () => Promise.resolve(v) });

beforeEach(() => {
  jest.clearAllMocks();
  Master.exists.mockResolvedValue(true);
  Master.find.mockReturnValue(lean([])); // no children below any master
});

const adminReq = (admin, body) => ({ admin: { id: 'a1', isSuperAdmin: false, watchOnly: false, permissions: ['MASTER_EDIT_ANY'], hiddenMasterIds: [], ...admin }, body });

test('admin without for_master_id: top level (null) for a master, 400 for a client', async () => {
  await expect(resolveCreateParentId(adminReq({}, {}))).resolves.toBeNull();
  await expect(resolveCreateParentId(adminReq({}, {}), { requireForAdmin: true })).rejects.toMatchObject({ status: 400 });
});

test('admin with MASTER_EDIT_ANY: any master', async () => {
  await expect(resolveCreateParentId(adminReq({}, { for_master_id: X }))).resolves.toBe(X);
});

test('admin without MASTER_EDIT_ANY: refused', async () => {
  await expect(resolveCreateParentId(adminReq({ permissions: [] }, { for_master_id: X }))).rejects.toMatchObject({ status: 403 });
});

test('watch-only admin: refused', async () => {
  await expect(resolveCreateParentId(adminReq({ watchOnly: true }, { for_master_id: X }))).rejects.toMatchObject({ status: 403 });
});

test('master hidden from this admin: refused', async () => {
  await expect(resolveCreateParentId(adminReq({ hiddenMasterIds: [HIDDEN] }, { for_master_id: HIDDEN }))).rejects.toMatchObject({ status: 403 });
});

test('super admin: no permission needed, hidden list ignored', async () => {
  await expect(resolveCreateParentId(adminReq({ isSuperAdmin: true, permissions: [], hiddenMasterIds: [X] }, { for_master_id: X }))).resolves.toBe(X);
});

test('unknown / deleted / malformed master: 404', async () => {
  Master.exists.mockResolvedValue(null);
  await expect(resolveCreateParentId(adminReq({}, { for_master_id: X }))).rejects.toMatchObject({ status: 404 });
  await expect(resolveCreateParentId(adminReq({}, { for_master_id: 'not-an-id' }))).rejects.toMatchObject({ status: 404 });
});

test('master caller unchanged: self by default, downline only', async () => {
  await expect(resolveCreateParentId({ master: { id: 'm1' }, body: {} })).resolves.toBe('m1');
  await expect(resolveCreateParentId({ master: { id: 'm1' }, body: { for_master_id: 'other' } })).rejects.toMatchObject({ status: 403 });
});
