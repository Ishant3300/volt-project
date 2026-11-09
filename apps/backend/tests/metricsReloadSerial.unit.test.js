'use strict';

// metricsEngine.reloadRules runs one at a time (server batch 2, 9 Nov 2026):
// calls during a reload ask for ONE more pass after it, every caller's promise
// settles after that final pass, and a failing pass never rejects.

process.env.MONGO_URI = process.env.MONGO_URI || 'mongodb://127.0.0.1:1/never-live';
const engine = require('../src/services/metricsEngine');

describe('metricsEngine.reloadRules serialization', () => {
  let saved;
  beforeEach(() => {
    saved = { init: engine._initialized, once: engine._reloadRulesOnce };
    engine._initialized = true;
    engine._rulesReload = null;
  });
  afterEach(() => {
    engine._initialized = saved.init;
    engine._reloadRulesOnce = saved.once;
    engine._rulesReload = null;
  });

  test('overlapping calls never run side by side and end with one extra pass', async () => {
    let running = 0; let maxRunning = 0; let passes = 0;
    engine._reloadRulesOnce = async () => {
      running++; maxRunning = Math.max(maxRunning, running); passes++;
      await new Promise((r) => setTimeout(r, 20));
      running--;
    };
    const a = engine.reloadRules();
    const b = engine.reloadRules();
    const c = engine.reloadRules();
    await Promise.all([a, b, c]);
    expect(maxRunning).toBe(1);
    expect(passes).toBe(2); // the first + one for the calls made during it
    expect(engine._rulesReload).toBeNull();
  });

  test('a failing pass resolves (fire-and-forget callers) and the next call runs again', async () => {
    let n = 0;
    engine._reloadRulesOnce = async () => { n++; if (n === 1) throw new Error('db down'); };
    await expect(engine.reloadRules()).resolves.toBeUndefined();
    await engine.reloadRules();
    expect(n).toBe(2);
  });

  test('not initialized: nothing runs', async () => {
    engine._initialized = false;
    let n = 0;
    engine._reloadRulesOnce = async () => { n++; };
    await engine.reloadRules();
    expect(n).toBe(0);
  });
});
