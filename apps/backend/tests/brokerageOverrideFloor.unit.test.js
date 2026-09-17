'use strict';

// Regression coverage for a real gap: masterChildController.js's sub-master
// creation flow could set a new sub-master's brokerage rate BELOW the
// creating master's own rate, with no rejection anywhere. Under the
// rate-gap brokerage-sharing model (weeklyAdminController.js), a master's
// own markup is (their child's rate - their own rate) — if the child's
// rate is ever lower than the parent's, that markup goes negative, which
// breaks the whole revenue-sharing reconciliation. The standalone
// brokerage-settings CRUD endpoints (adminController.js) already enforce
// this via validateBrokerageFloor; applyBrokerageOverrides (the function
// that actually writes creation-time rate overrides) never did, until now.
//
// enforceFloor is only true when a real parent master exists — admin
// creating a top-level master directly has no parent to violate against,
// matching the existing pnl_sharing/brokerage_sharing % floor check in
// masterChildController.js, which skips the same way for that case.

jest.mock('../src/models/BrokerageSettings', () => ({
  findOne: jest.fn(),
  bulkWrite: jest.fn().mockResolvedValue({}),
}));
jest.mock('../src/models/KiteInstrument', () => ({ find: jest.fn() }));

const BrokerageSettings = require('../src/models/BrokerageSettings');
const { applyBrokerageOverrides } = require('../src/services/brokerageCopyService');

// `BrokerageSettings.findOne(filter).session(s).lean()` chain.
function findOneChain(result) {
  const chain = {};
  chain.session = jest.fn(() => chain);
  chain.lean = jest.fn(() => Promise.resolve(result));
  return chain;
}

beforeEach(() => {
  jest.clearAllMocks();
});

describe('applyBrokerageOverrides — floor check only when enforceFloor is true', () => {
  const CHILD = 'child1';
  const override = [{ exchange_name: 'MCX-FUT', type: 'LOT WISE', brk_value: 200, script_name: 'GOLDM' }];

  test('enforceFloor=true, override BELOW the copied parent baseline: rejected', async () => {
    BrokerageSettings.findOne.mockReturnValue(findOneChain({ brk_value: 300 })); // parent's own rate, already copied
    await expect(applyBrokerageOverrides(CHILD, override, null, true))
      .rejects.toThrow(/cannot be less than your own rate \(300\)/);
    expect(BrokerageSettings.bulkWrite).not.toHaveBeenCalled();
  });

  test('enforceFloor=true, override EQUAL to the parent baseline: allowed', async () => {
    BrokerageSettings.findOne.mockReturnValue(findOneChain({ brk_value: 200 }));
    await expect(applyBrokerageOverrides(CHILD, override, null, true)).resolves.toBeUndefined();
    expect(BrokerageSettings.bulkWrite).toHaveBeenCalledTimes(1);
  });

  test('enforceFloor=true, override ABOVE the parent baseline: allowed', async () => {
    BrokerageSettings.findOne.mockReturnValue(findOneChain({ brk_value: 100 }));
    const higherOverride = [{ exchange_name: 'MCX-FUT', type: 'LOT WISE', brk_value: 400, script_name: 'GOLDM' }];
    await expect(applyBrokerageOverrides(CHILD, higherOverride, null, true)).resolves.toBeUndefined();
    expect(BrokerageSettings.bulkWrite).toHaveBeenCalledTimes(1);
  });

  test('enforceFloor=true but no baseline was ever copied for this script: allowed (nothing to compare against)', async () => {
    BrokerageSettings.findOne.mockReturnValue(findOneChain(null));
    await expect(applyBrokerageOverrides(CHILD, override, null, true)).resolves.toBeUndefined();
    expect(BrokerageSettings.bulkWrite).toHaveBeenCalledTimes(1);
  });

  test('enforceFloor=false (default, e.g. admin creating a top-level master with no parent): never rejected, even below "current"', async () => {
    BrokerageSettings.findOne.mockReturnValue(findOneChain({ brk_value: 999999 }));
    await expect(applyBrokerageOverrides(CHILD, override)).resolves.toBeUndefined();
    // The floor lookup itself is skipped entirely when enforceFloor is false —
    // not just its rejection — so findOne should never even be called.
    expect(BrokerageSettings.findOne).not.toHaveBeenCalled();
    expect(BrokerageSettings.bulkWrite).toHaveBeenCalledTimes(1);
  });
});
