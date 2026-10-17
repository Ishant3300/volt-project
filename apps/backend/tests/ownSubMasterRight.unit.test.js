'use strict';

// A master whose own "create sub-master" permission is off can't create a
// sub-master anywhere — not even on behalf of a downline master that has it.

jest.mock('../src/models/Master', () => ({ find: jest.fn(), exists: jest.fn(), findById: jest.fn() }));

const Master = require('../src/models/Master');
const { assertOwnSubMasterRight } = require('../src/services/masterHierarchyService');

const self = (doc) => Master.findById.mockReturnValue({ select: () => ({ lean: () => Promise.resolve(doc) }) });
const masterReq = { master: { id: 'm1' }, body: {} };

beforeEach(() => jest.clearAllMocks());

test('master without the permission: refused when acting for a downline master', async () => {
  self({ add_master: false });
  await expect(assertOwnSubMasterRight(masterReq, 'm2')).rejects.toMatchObject({ status: 403, message: 'No permission to create child masters' });
});

test('master with the permission: allowed for a downline master', async () => {
  self({ add_master: true });
  await expect(assertOwnSubMasterRight(masterReq, 'm2')).resolves.toBeUndefined();
});

test('creating under themselves: not checked here (parent check covers it)', async () => {
  await expect(assertOwnSubMasterRight(masterReq, 'm1')).resolves.toBeUndefined();
  expect(Master.findById).not.toHaveBeenCalled();
});

test('admin callers are not affected', async () => {
  await expect(assertOwnSubMasterRight({ admin: { id: 'a1' }, body: {} }, 'm2')).resolves.toBeUndefined();
  await expect(assertOwnSubMasterRight({ admin: { id: 'a1' }, body: {} }, null)).resolves.toBeUndefined();
  expect(Master.findById).not.toHaveBeenCalled();
});
