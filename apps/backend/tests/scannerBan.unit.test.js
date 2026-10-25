'use strict';

// Secret-file scanner auto-ban (scripts/watchdog/scannerBan.js, 25 Oct 2026).

const ban = require('../scripts/watchdog/scannerBan');
const lib = require('../scripts/watchdog/lib');

test('5 probes within 10 minutes bans the IP for 7 days; slower probing does not', () => {
  const st = {};
  const t0 = 1_000_000;
  for (let i = 0; i < 4; i++) expect(ban.recordProbe(st, '185.177.72.64', t0 + i * 1000)).toBe(false);
  expect(ban.recordProbe(st, '185.177.72.64', t0 + 5000)).toBe(true);
  expect(st.bans['185.177.72.64'].until).toBe(t0 + 5000 + ban.BAN_MS);
  expect(ban.recordProbe(st, '185.177.72.64', t0 + 6000)).toBe(false); // already banned

  const slow = {};
  for (let i = 0; i < 6; i++) expect(ban.recordProbe(slow, '1.2.3.4', t0 + i * 3 * 60_000)).toBe(false); // 3 min apart
});

test('never bans the forwarder, this server, localhost, private ranges or garbage', () => {
  const st = {};
  for (const ip of ['13.207.113.128', '13.232.214.61', '127.0.0.1', '10.0.0.5', '192.168.1.9', '172.20.0.1', 'not-an-ip', '1.2.3.4;']) {
    for (let i = 0; i < 6; i++) ban.recordProbe(st, ip, 1000 + i);
  }
  expect(st.bans).toEqual({});
});

test('bans expire; the nginx file lists only current, valid IPs', () => {
  const now = 11 * 60_000; // the probe at t=1 is past the 10-minute window
  const st = { bans: { '5.6.7.8': { until: 2000 }, '9.9.9.9': { until: now + 99_999 } }, probes: { '1.1.1.1': [1] } };
  expect(ban.prune(st, now)).toBe(true);
  expect(Object.keys(st.bans)).toEqual(['9.9.9.9']);
  expect(st.probes).toEqual({}); // stale probe dropped
  const file = ban.renderDenyFile(st);
  expect(file).toContain('deny 9.9.9.9;');
  expect(file).not.toContain('5.6.7.8');
  expect(ban.prune(st, now + 1000)).toBe(false);
});

test('probe detection counts the query too (for the ban), the alert only the path', () => {
  expect(lib.isProbe('/?url=.env')).toBe(true);
  expect(lib.isSensitivePath('/?url=.env')).toBe(false);
  expect(lib.isProbe('/api/trade/report?from=2026-10-19')).toBe(false);
  expect(lib.isProbe('/wp-config.php')).toBe(true);
});
