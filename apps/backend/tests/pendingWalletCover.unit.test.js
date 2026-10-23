'use strict';

// Pending LIMIT / SL orders: refused at placement (and modify) when the category
// wallet cannot cover the part they would open at the order price — the same
// test the fill gate applies. Closing / reducing orders are not affected; a
// reversal counts what its closed part releases. (23 Oct 2026: a client with a
// ₹0 INDEX wallet could place a BANKNIFTY limit that could only be rejected later.)

jest.mock('../src/models/Trade', () => ({ find: jest.fn() }));
jest.mock('../src/services/walletService', () => ({ getAvailable: jest.fn() }));

const Trade = require('../src/models/Trade');
const walletService = require('../src/services/walletService');
const { _validatePendingWalletCover: check } = require('../src/controllers/tradeController')._private;

const BANKNIFTY = { segment: 'NFO-FUT', tradingsymbol: 'BANKNIFTY26OCTFUT', name: 'BANKNIFTY', raw_name: 'BANKNIFTY' };
const BHEL = { segment: 'NFO-FUT', tradingsymbol: 'BHEL26OCTFUT', name: 'BHEL', raw_name: 'BHEL' };

function history(trades) {
  const chain = { select: () => chain, sort: () => chain, session: () => chain, lean: () => Promise.resolve(trades) };
  Trade.find.mockReturnValue(chain);
}
const fill = (side, qty, price) => ({ transaction_type: side, executed_quantity: qty, executed_price: price, executed_at: new Date(), createdAt: new Date() });
const wallet = (w) => walletService.getAvailable.mockResolvedValue({ NSE: 0, INDEX: 0, NSEOPT: 0, MCX: 0, COMEX: 0, GLOBAL: 0, ...w });
const run = (inst, side, qty, price) => check('u1', 't1', side, qty, price, inst.segment, inst, inst.tradingsymbol, null);

beforeEach(() => jest.clearAllMocks());

test('₹0 INDEX wallet: a new BANKNIFTY buy limit is refused at placement (the 542805 case)', async () => {
  history([]); wallet({ INDEX: 0, NSE: 4066414.85 });
  await expect(run(BANKNIFTY, 'BUY', 25, 54150)).rejects.toMatchObject({
    status: 400,
    message: 'Insufficient INDEX wallet balance. Required ₹1353750.00, available ₹0.00 (short ₹1353750.00).',
  });
});

test('enough balance in the right wallet: allowed', async () => {
  history([]); wallet({ INDEX: 1400000 });
  await expect(run(BANKNIFTY, 'BUY', 25, 54150)).resolves.toBeUndefined();
  // Stock futures use the NSE wallet, not INDEX.
  history([]); wallet({ NSE: 200000, INDEX: 0 });
  await expect(run(BHEL, 'BUY', 500, 379.25)).resolves.toBeUndefined();
});

test('closing or reducing an open position needs no balance', async () => {
  history([fill('BUY', 50, 54000)]); wallet({ INDEX: 0 });
  await expect(run(BANKNIFTY, 'SELL', 25, 54500)).resolves.toBeUndefined();
  await expect(run(BANKNIFTY, 'SELL', 50, 54500)).resolves.toBeUndefined();
});

test('reversal: only the new opening part is checked, the closed part releases its entry value', async () => {
  // Long 25 @ 54200 → SELL 50 @ 54100: closes 25 (releases 25×54200 = 1,355,000)
  // and opens a 25 short needing 25×54100 = 1,352,500.
  history([fill('BUY', 25, 54200)]);
  wallet({ INDEX: 0 });
  await expect(run(BANKNIFTY, 'SELL', 50, 54100)).resolves.toBeUndefined();
});

test('reversal short of funds is refused', async () => {
  history([fill('BUY', 25, 50000)]); // releases 1,250,000
  wallet({ INDEX: 0 });
  await expect(run(BANKNIFTY, 'SELL', 50, 54100)).rejects.toMatchObject({ status: 400, message: expect.stringContaining('short ₹102500.00') });
});
