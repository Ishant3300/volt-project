'use strict';

// Master sharing must stay within [highest direct sub-master, parent] (utils/sharingRange.js).
const docs = {
  P: { _id: 'P', master_id: null, name: 'YASH', pnl_sharing: 91, brokerage_sharing: 91, deleted_at: null },
  M: { _id: 'M', master_id: 'P', name: 'J25', pnl_sharing: 25, brokerage_sharing: 5, deleted_at: null },
  C1: { _id: 'C1', master_id: 'M', name: 'KK20', pnl_sharing: 20, brokerage_sharing: 5, deleted_at: null },
  C2: { _id: 'C2', master_id: 'M', name: 'X10', pnl_sharing: 10, brokerage_sharing: 2, deleted_at: null },
  T: { _id: 'T', master_id: null, name: 'TOP', pnl_sharing: 100, brokerage_sharing: 100, deleted_at: null },
};
const lean = (v) => ({ select: () => ({ lean: async () => v }) });
jest.mock('../src/models/Master', () => ({
  findOne: (q) => lean(Object.values(docs).find((d) => d._id === q._id && !d.deleted_at) || null),
  find: (q) => lean(Object.values(docs).filter((d) => d.master_id === q.master_id && !d.deleted_at)),
}));
const { sharingRangeFor, sharingRangeError } = require('../src/utils/sharingRange');

test('range = [highest sub-master, parent]', async () => {
  const r = await sharingRangeFor(docs.M);
  expect(r.pnl_sharing).toMatchObject({ min: 20, max: 91 });
  expect(r.brokerage_sharing).toMatchObject({ min: 5, max: 91 });
  const top = await sharingRangeFor(docs.T);
  expect(top.pnl_sharing).toMatchObject({ min: 0, max: 100 });
});

test('above parent / below a sub-master is refused; inside the range passes', async () => {
  expect(await sharingRangeError(docs.M, { pnl_sharing: 95 })).toMatch(/more than 91%/);
  expect(await sharingRangeError(docs.M, { pnl_sharing: 15 })).toMatch(/less than 20%.*KK20/);
  expect(await sharingRangeError(docs.M, { brokerage_sharing: 4 })).toMatch(/less than 5%/);
  expect(await sharingRangeError(docs.M, { pnl_sharing: 30, brokerage_sharing: 10 })).toBeNull();
  expect(await sharingRangeError(docs.M, { pnl_sharing: 20 })).toBeNull(); // equal to the top sub-master is fine
});

test('unchanged or absent values never block an unrelated edit', async () => {
  const broken = { ...docs.M, pnl_sharing: 95 }; // already above its parent
  expect(await sharingRangeError(broken, { pnl_sharing: 95 })).toBeNull();
  expect(await sharingRangeError(broken, {})).toBeNull();
  expect(await sharingRangeError(broken, { pnl_sharing: undefined, brokerage_sharing: null })).toBeNull();
});
