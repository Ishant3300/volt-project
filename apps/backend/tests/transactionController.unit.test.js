'use strict';

// Regression coverage for GET /api/master/transactions (transactionController.getTransactionHistory).
//
// This endpoint always returns exactly ONE target_id/target_model's ledger — there is
// no "give me my whole hierarchy's transactions" bulk mode. Its authorization,
// though, IS meant to cover a caller's entire downline at any depth (via
// getAllSubMasterIds), not just direct children — this file exists because that
// exact deep-hierarchy claim had no test coverage before (found during an audit of
// whether Ledger & Payouts / Weekly Admin Report hold up for 3+ level trees; see
// apex-web-portal's MasterLedger.tsx for the frontend-side fix that was made
// alongside this — masterData.tsx previously always passed the caller's OWN id as
// target_id, so the "Client credit & debit history" panel could never actually
// reach this authorization logic for any other account).
//
// Transaction, User, getAllSubMasterIds and resolveHiddenMasterIds are all mocked —
// no DB. req/res follow the same chainable-res fake used by walletController.unit.test.js.

jest.mock('../src/models/Transaction', () => ({
  find: jest.fn(),
  countDocuments: jest.fn(),
}));
jest.mock('../src/models/User', () => ({ findById: jest.fn() }));
jest.mock('../src/services/masterHierarchyService', () => ({
  getAllSubMasterIds: jest.fn(),
}));
jest.mock('../src/utils/adminVisibility', () => ({
  resolveHiddenMasterIds: jest.fn(),
}));

const Transaction = require('../src/models/Transaction');
const User = require('../src/models/User');
const { getAllSubMasterIds } = require('../src/services/masterHierarchyService');
const { resolveHiddenMasterIds } = require('../src/utils/adminVisibility');
const { getTransactionHistory } = require('../src/controllers/transactionController');

function makeRes() {
  const res = {};
  res.status = jest.fn(() => res);
  res.json = jest.fn(() => res);
  return res;
}

// `Transaction.find(filter).sort().skip().limit().lean()` chain.
function findChain(rows) {
  const chain = {};
  chain.sort = jest.fn(() => chain);
  chain.skip = jest.fn(() => chain);
  chain.limit = jest.fn(() => chain);
  chain.lean = jest.fn(() => Promise.resolve(rows));
  return chain;
}

// `User.findById(id).select('master_id').lean()` chain.
function findByIdChain(result) {
  const chain = {};
  chain.select = jest.fn(() => chain);
  chain.lean = jest.fn(() => Promise.resolve(result));
  return chain;
}

const VALID_OID = '507f1f77bcf86cd799439011';
const GRANDCHILD_OID = '507f1f77bcf86cd799439022';
const MASTER_A_OID = '507f1f77bcf86cd799439033';

const MASTER_REQ = (query, masterId = 'masterA') => ({
  master: { id: masterId, role: 'master' },
  admin: null,
  query,
});
const ADMIN_REQ = (query) => ({ master: null, admin: { id: 'admin1', role: 'admin' }, query });

beforeEach(() => {
  jest.clearAllMocks();
  Transaction.find.mockReturnValue(findChain([]));
  Transaction.countDocuments.mockResolvedValue(0);
});

describe('target_id is required', () => {
  test('missing target_id returns 400 before touching the DB', async () => {
    const res = makeRes();
    await getTransactionHistory(MASTER_REQ({}), res);
    expect(res.status).toHaveBeenCalledWith(400);
    expect(Transaction.find).not.toHaveBeenCalled();
  });
});

describe('master caller — subtree authorization (any depth)', () => {
  test('master may never target target_model=Admin', async () => {
    const res = makeRes();
    await getTransactionHistory(MASTER_REQ({ target_id: VALID_OID, target_model: 'Admin' }), res);
    expect(res.status).toHaveBeenCalledWith(403);
    expect(Transaction.find).not.toHaveBeenCalled();
  });

  test('target_model=Master: a DEEP (3+ level) grandchild master in the caller subtree is authorized', async () => {
    // getAllSubMasterIds is the whole-subtree resolver — simulate it returning a
    // grandchild several tiers below the caller, proving this isn't limited to
    // direct children.
    getAllSubMasterIds.mockResolvedValue(['masterA', 'childM', 'grandchildM', GRANDCHILD_OID]);
    const rows = [{ _id: 't1', type: 'CREDIT', amount: 100, createdAt: new Date() }];
    Transaction.find.mockReturnValue(findChain(rows));
    Transaction.countDocuments.mockResolvedValue(1);

    const res = makeRes();
    await getTransactionHistory(
      MASTER_REQ({ target_id: GRANDCHILD_OID, target_model: 'Master' }),
      res,
    );

    expect(res.status).toHaveBeenCalledWith(200);
    const body = res.json.mock.calls[0][0];
    expect(body.data.transactions).toHaveLength(1);
    expect(Transaction.find).toHaveBeenCalledWith(
      expect.objectContaining({ userModel: 'Master' }),
    );
  });

  test('target_model=Master: a master OUTSIDE the caller subtree is rejected regardless of depth', async () => {
    getAllSubMasterIds.mockResolvedValue(['masterA', 'childM']);
    const res = makeRes();
    await getTransactionHistory(
      MASTER_REQ({ target_id: 'someOtherBranchMaster', target_model: 'Master' }),
      res,
    );
    expect(res.status).toHaveBeenCalledWith(403);
    expect(Transaction.find).not.toHaveBeenCalled();
  });

  test('target_model=User (default): a client whose master is a DEEP descendant is authorized', async () => {
    getAllSubMasterIds.mockResolvedValue(['masterA', 'childM', 'grandchildM']);
    User.findById.mockReturnValue(findByIdChain({ _id: VALID_OID, master_id: 'grandchildM' }));
    Transaction.countDocuments.mockResolvedValue(0);

    const res = makeRes();
    await getTransactionHistory(MASTER_REQ({ target_id: VALID_OID }), res);

    expect(res.status).toHaveBeenCalledWith(200);
  });

  test('target_model=User: a client whose master is outside the caller subtree is rejected', async () => {
    getAllSubMasterIds.mockResolvedValue(['masterA', 'childM']);
    User.findById.mockReturnValue(findByIdChain({ _id: VALID_OID, master_id: 'unrelatedMaster' }));

    const res = makeRes();
    await getTransactionHistory(MASTER_REQ({ target_id: VALID_OID }), res);

    expect(res.status).toHaveBeenCalledWith(403);
    expect(Transaction.find).not.toHaveBeenCalled();
  });

  test('target_model=User: a target user that does not exist is rejected, not silently passed through', async () => {
    getAllSubMasterIds.mockResolvedValue(['masterA']);
    User.findById.mockReturnValue(findByIdChain(null));

    const res = makeRes();
    await getTransactionHistory(MASTER_REQ({ target_id: VALID_OID }), res);

    expect(res.status).toHaveBeenCalledWith(403);
  });
});

describe('admin caller', () => {
  test('unrestricted admin (no hidden masters) can target any master directly', async () => {
    resolveHiddenMasterIds.mockResolvedValue(null);
    Transaction.countDocuments.mockResolvedValue(0);

    const res = makeRes();
    await getTransactionHistory(ADMIN_REQ({ target_id: VALID_OID, target_model: 'Master' }), res);

    expect(res.status).toHaveBeenCalledWith(200);
    expect(getAllSubMasterIds).not.toHaveBeenCalled();
  });

  test('admin with a hidden-masters restriction cannot target a hidden master', async () => {
    resolveHiddenMasterIds.mockResolvedValue(new Set([VALID_OID]));

    const res = makeRes();
    await getTransactionHistory(ADMIN_REQ({ target_id: VALID_OID, target_model: 'Master' }), res);

    expect(res.status).toHaveBeenCalledWith(404);
    expect(Transaction.find).not.toHaveBeenCalled();
  });

  test('admin with a hidden-masters restriction cannot target a user under a hidden master', async () => {
    resolveHiddenMasterIds.mockResolvedValue(new Set(['hiddenMaster']));
    User.findById.mockReturnValue(findByIdChain({ _id: VALID_OID, master_id: 'hiddenMaster' }));

    const res = makeRes();
    await getTransactionHistory(ADMIN_REQ({ target_id: VALID_OID }), res);

    expect(res.status).toHaveBeenCalledWith(404);
    expect(Transaction.find).not.toHaveBeenCalled();
  });

  test('admin may target target_model=Admin (only masters are blocked from that)', async () => {
    Transaction.countDocuments.mockResolvedValue(0);
    const res = makeRes();
    await getTransactionHistory(ADMIN_REQ({ target_id: VALID_OID, target_model: 'Admin' }), res);
    expect(res.status).toHaveBeenCalledWith(200);
    expect(resolveHiddenMasterIds).not.toHaveBeenCalled();
  });
});

describe('response shape', () => {
  test('exactly ONE account\'s transactions are returned — never a hierarchy-wide merge', async () => {
    getAllSubMasterIds.mockResolvedValue(['masterA', MASTER_A_OID]);
    const rows = [
      { _id: 't1', type: 'CREDIT', amount: 500, balanceBefore: 0, balanceAfter: 500, userId: MASTER_A_OID, userModel: 'Master', createdAt: new Date('2026-01-01') },
    ];
    Transaction.find.mockReturnValue(findChain(rows));
    Transaction.countDocuments.mockResolvedValue(1);

    const res = makeRes();
    await getTransactionHistory(MASTER_REQ({ target_id: MASTER_A_OID, target_model: 'Master' }), res);

    expect(Transaction.find).toHaveBeenCalledWith(
      expect.objectContaining({ userModel: 'Master', status: 'SUCCESS' }),
    );
    const body = res.json.mock.calls[0][0];
    expect(body.data.transactions).toHaveLength(1);
    // Both snake_case and camelCase fields must be present (mobile reads
    // camelCase directly; web reads snake_case) — see the controller's own
    // comment on why neither was dropped in favor of the other.
    expect(body.data.transactions[0]).toMatchObject({
      balance_after: 500,
      balanceAfter: 500,
      created_at: rows[0].createdAt,
    });
  });
});
