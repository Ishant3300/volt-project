const { computeBrokerEarnings, brokerShare, weekStartIST, normSegment } = require('../src/services/brokerEarnings');

describe('brokerShare', () => {
  test('TURNOVER WISE: 1 paisa per ₹100 of turnover', () => {
    // ₹1 crore turnover at 1 -> ₹1,000
    expect(brokerShare({ type: 'TURNOVER WISE', value: 1, price: 1000, quantity: 10000, brokerage: 3000 }))
      .toEqual({ turnover: 1e7, lots: 0, amount: 1000, capped: false });
  });

  test('LOT WISE: ₹ per lot', () => {
    expect(brokerShare({ type: 'LOT WISE', value: 50, price: 6000, quantity: 300, lotSize: 100, brokerage: 600 }))
      .toEqual({ turnover: 1800000, lots: 3, amount: 150, capped: false });
  });

  test('never more than the brokerage the client paid', () => {
    expect(brokerShare({ type: 'TURNOVER WISE', value: 5, price: 1000, quantity: 1000, brokerage: 200 }))
      .toMatchObject({ amount: 200, capped: true });
  });

  test('0 on a brokerage-exempt fill or a zero rate', () => {
    expect(brokerShare({ type: 'TURNOVER WISE', value: 1, price: 1000, quantity: 10, brokerage: 0, exempt: true }).amount).toBe(0);
    expect(brokerShare({ type: 'TURNOVER WISE', value: 0, price: 1000, quantity: 10, brokerage: 5 }).amount).toBe(0);
  });
});

describe('weekStartIST', () => {
  test('Monday 00:00 IST of the week', () => {
    // Wed 14 Oct 2026 10:00 IST -> Mon 12 Oct 00:00 IST = Sun 11 Oct 18:30 UTC
    expect(weekStartIST(new Date('2026-10-14T04:30:00Z')).toISOString()).toBe('2026-10-11T18:30:00.000Z');
    // Sun 18 Oct 23:00 IST still belongs to the week of Mon 12 Oct
    expect(weekStartIST(new Date('2026-10-18T17:30:00Z')).toISOString()).toBe('2026-10-11T18:30:00.000Z');
    // Mon 19 Oct 00:30 IST starts the next week
    expect(weekStartIST(new Date('2026-10-18T19:00:00Z')).toISOString()).toBe('2026-10-18T18:30:00.000Z');
  });
});

describe('computeBrokerEarnings', () => {
  const instruments = new Map([
    ['1', { segment: 'NFO-FUT', lot_size: 75 }],
    ['2', { segment: 'MCX-FUT', lot_size: 100 }],
    ['3', { segment: 'GLOBAL', lot_size: 1 }],
  ]);
  const link = (over) => ({ _id: 'L1', broker_id: 'B1', user_id: 'U1', from: new Date('2026-10-12T03:00:00Z'), to: null,
    rates: [{ segment: 'NFO-FUT', type: 'TURNOVER WISE', value: 1 }, { segment: 'INDICES', type: 'TURNOVER WISE', value: 2 }], ...over });
  const fill = (over) => ({ user_id: 'U1', instrument_token: 1, executed_price: 1000, executed_quantity: 1000, brokerage: 300,
    executed_at: new Date('2026-10-12T05:00:00Z'), ...over });

  test('sums fills per link, segment and week', () => {
    const rows = computeBrokerEarnings({ links: [link()], trades: [fill(), fill({ executed_price: 2000 })], instruments });
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ broker_id: 'B1', user_id: 'U1', segment: 'NFO-FUT', fills: 2, turnover: 3000000, amount: 300 });
  });

  test('only fills inside the link period and the asked range count', () => {
    const before = fill({ executed_at: new Date('2026-10-12T02:00:00Z') });
    const ended = link({ to: new Date('2026-10-12T06:00:00Z') });
    const after = fill({ executed_at: new Date('2026-10-12T07:00:00Z') });
    expect(computeBrokerEarnings({ links: [ended], trades: [before, fill(), after], instruments })[0].fills).toBe(1);
    expect(computeBrokerEarnings({ links: [link()], trades: [fill()], instruments, from: new Date('2026-10-13T00:00:00Z') })).toHaveLength(0);
  });

  test('segments without a broker share are ignored; GLOBAL counts as INDICES', () => {
    const rows = computeBrokerEarnings({ links: [link()], trades: [fill({ instrument_token: 2 }), fill({ instrument_token: 3, executed_price: 50000, executed_quantity: 2 })], instruments });
    expect(rows.map((r) => r.segment)).toEqual(['INDICES']);
    expect(rows[0].amount).toBe(20); // 1,00,000 × 2/10000
  });

  test('a rate change (new link) keeps each period at its own rate', () => {
    const old = link({ to: new Date('2026-10-12T06:00:00Z') });
    const neu = link({ _id: 'L2', from: new Date('2026-10-12T06:00:00Z'), rates: [{ segment: 'NFO-FUT', type: 'TURNOVER WISE', value: 2 }] });
    const rows = computeBrokerEarnings({ links: [old, neu], trades: [fill(), fill({ executed_at: new Date('2026-10-12T08:00:00Z') })], instruments });
    expect(rows.map((r) => [r.link_id, r.amount])).toEqual([['L1', 100], ['L2', 200]]);
  });

  test('other clients\' fills are not counted', () => {
    expect(computeBrokerEarnings({ links: [link()], trades: [fill({ user_id: 'U2' })], instruments })).toHaveLength(0);
  });

  test('normSegment', () => {
    expect(normSegment(' global ')).toBe('INDICES');
    expect(normSegment('nfo-fut')).toBe('NFO-FUT');
  });
});
