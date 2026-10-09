const { isGiftSessionBreak } = require('../src/services/giftNiftyFeedService');

// NSE IX break between session 1 (closes 15:40 IST) and session 2 (opens 16:05 IST).
describe('isGiftSessionBreak', () => {
  const at = (iso) => isGiftSessionBreak(new Date(iso));
  test('weekday: blocked from 15:40 up to (not incl.) 16:05 IST', () => {
    expect(at('2026-10-09T10:09:59Z')).toBe(false); // 15:39:59
    expect(at('2026-10-09T10:10:00Z')).toBe(true);  // 15:40
    expect(at('2026-10-09T10:34:59Z')).toBe(true);  // 16:04:59
    expect(at('2026-10-09T10:35:00Z')).toBe(false); // 16:05
  });
  test('not during either session', () => {
    expect(at('2026-10-09T03:45:00Z')).toBe(false); // 09:15
    expect(at('2026-10-09T15:00:00Z')).toBe(false); // 20:30
  });
  test('no break on Saturday / Sunday', () => {
    expect(at('2026-10-10T10:15:00Z')).toBe(false);
    expect(at('2026-10-11T10:15:00Z')).toBe(false);
  });
});
