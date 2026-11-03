// Equity M8 — separation proof, part 1 (no database needed):
//   1. EVERY F&O route (all 11 routers + the inline ones in index.js), called with an equity
//      client and an equity master token, is refused before any handler or database runs.
//   2. The F&O action log (auditActions) records nothing for equity requests.
//   3. The F&O code never reads or writes equity data, and never sweeps all collections.
//   4. Equity only writes to its own collections (eqcash_*), and adds no field to F&O models.
// Part 2 (weekly settlement identical with and without equity data, on a real MongoDB) is
// tests/cashEqSettlement.integration.test.js.

process.env.JWT_SECRET = 'cash-eq-separation-secret';

const fs = require('fs');
const path = require('path');
const express = require('express');
const mongoose = require('mongoose');
const request = require('supertest');
const jwt = require('jsonwebtoken');

mongoose.set('bufferCommands', false); // a query that slips through fails at once instead of waiting

const SRC = path.join(__dirname, '..', 'src');
const MOUNTS = [
  ['/api/auth', 'authRoutes'], ['/api/admin', 'adminRoutes'], ['/api/super-admin', 'superAdminRoutes'],
  ['/api/users', 'userRoutes'], ['/api/kite', 'kiteRoutes'], ['/api/watchlist', 'watchlistRoutes'],
  ['/api/masters', 'masterRoutes'], ['/api/master', 'masterFlowRoutes'], ['/api/master/messages', 'messageRoutes'],
  ['/api/servers', 'serverRoutes'], ['/api/trade', 'tradeRoutes'],
];
const AUTH = new Set(['authenticateUser', 'authenticateAdmin', 'authenticateMaster', 'authenticateAny', 'authenticateAdminOrMaster', 'authenticateOptional']);

// Routes reachable without any account: logins and the like. Listed so a NEW public route
// shows up here (and gets looked at) instead of passing silently.
const PUBLIC_ROUTES = new Set([
  'POST /api/auth/user/login', 'POST /api/auth/admin/login', 'POST /api/auth/master/login', 'POST /api/auth/login',
  'POST /api/auth/client-events', // app/web error reports (watchdog) — records the token's role, nothing else
  'GET /api/auth/internal-health', // watchdog health probe
  'GET /api/kite/login', 'GET /api/kite/callback', // Kite OAuth sign-in for the price feed
  'GET /api/servers/search', 'GET /api/servers/', // server list for the login screen
]);

function collectRoutes() {
  const out = [];
  for (const [prefix, file] of MOUNTS) {
    const router = require(path.join(SRC, 'routes', file));
    // A router-level guard (router.use(authenticate…)) only covers routes declared after it.
    let routerGuarded = false;
    for (const layer of router.stack) {
      if (!layer.route) {
        if (AUTH.has(layer.name)) routerGuarded = true;
        continue;
      }
      const names = layer.route.stack.map((s) => s.name);
      for (const method of Object.keys(layer.route.methods)) {
        out.push({
          method: method.toUpperCase(),
          path: `${prefix}${layer.route.path}`,
          guarded: routerGuarded || names.some((n) => AUTH.has(n)),
        });
      }
    }
  }
  return out;
}

// ':op(confirm|unconfirm)' → 'confirm'; other params → an ObjectId.
const fillParams = (p) => p
  .replace(/:[A-Za-z_]+\(([^)|]+)[^)]*\)\??/g, '$1')
  .replace(/:([A-Za-z_]+)\??/g, '64b0000000000000000000ee')
  .replace(/\/\*$/, '/x');
const token = (role) => jwt.sign({ id: '64b0000000000000000000e1', role, investor: false }, process.env.JWT_SECRET);

describe('every F&O route refuses equity accounts', () => {
  const routes = collectRoutes();
  const app = express();
  app.use(express.json());
  app.use('/api', require(path.join(SRC, 'middlewares', 'requirePasswordChange')).requirePasswordChanged);
  app.use('/api', require(path.join(SRC, 'middlewares', 'auditActions')));
  for (const [prefix, file] of MOUNTS) app.use(prefix, require(path.join(SRC, 'routes', file)));

  test('the route list is complete and every non-login route has an F&O auth guard', () => {
    expect(routes.length).toBeGreaterThanOrEqual(235);
    const unguarded = routes.filter((r) => !r.guarded).map((r) => `${r.method} ${r.path}`);
    // A new public route fails here until it's looked at and added to PUBLIC_ROUTES.
    expect(unguarded.filter((r) => !PUBLIC_ROUTES.has(r))).toEqual([]);
  });

  for (const role of ['cash_client', 'cash_master']) {
    test(`${role}: refused on all guarded routes (401/403), no handler ran`, async () => {
      const failures = [];
      for (const r of routes.filter((x) => x.guarded)) {
        const res = await request(app)[r.method.toLowerCase()](fillParams(r.path))
          .set('Authorization', `Bearer ${token(role)}`)
          .send({});
        if (![401, 403].includes(res.status)) failures.push(`${r.method} ${r.path} → ${res.status}`);
      }
      expect(failures).toEqual([]);
    }, 120000);
  }

  test('public routes answer an equity token exactly as they answer no token (it gives no identity)', async () => {
    const differ = [];
    for (const key of PUBLIC_ROUTES) {
      if (key === 'POST /api/auth/client-events') continue; // records the role string only (see PUBLIC_ROUTES)
      const [method, p] = key.split(' ');
      const call = (withToken) => {
        const req = request(app)[method.toLowerCase()](fillParams(p));
        if (withToken) req.set('Authorization', `Bearer ${token('cash_client')}`);
        return req.send({});
      };
      const [a, b] = [await call(false), await call(true)];
      if (a.status !== b.status) differ.push(`${key}: ${a.status} without, ${b.status} with an equity token`);
    }
    expect(differ).toEqual([]);
  }, 60000);

  test('inline index.js routes are guarded', () => {
    const index = fs.readFileSync(path.join(SRC, 'index.js'), 'utf8');
    const inline = [...index.matchAll(/app\.(get|post|put|patch|delete)\('(\/api[^']*)',\s*([A-Za-z]+)/g)];
    expect(inline.length).toBeGreaterThan(0);
    for (const [, method, p, first] of inline) expect({ route: `${method} ${p}`, guard: first }).toEqual({ route: `${method} ${p}`, guard: 'authenticateAny' });
  });
});

describe('F&O action log records nothing for equity', () => {
  test('requests carrying only req.cash are skipped by auditActions', async () => {
    const AdminAction = require(path.join(SRC, 'models', 'AdminAction'));
    const spy = jest.spyOn(AdminAction, 'create').mockResolvedValue({});
    const app = express();
    app.use(express.json());
    app.use('/api', require(path.join(SRC, 'middlewares', 'auditActions')));
    app.post('/api/cash-eq/clients', (req, res) => { req.cash = { role: 'admin', id: 'x', username: 'admin' }; res.json({ success: true }); });
    await request(app).post('/api/cash-eq/clients').send({ name: 'x' }).expect(200);
    await new Promise((r) => setTimeout(r, 50));
    expect(spy).not.toHaveBeenCalled();
    spy.mockRestore();
  });
});

describe('code: F&O never touches equity data; equity only its own', () => {
  const walk = (dir, skip) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) return skip.includes(e.name) ? [] : walk(p, skip);
    return e.name.endsWith('.js') ? [p] : [];
  });
  const rel = (p) => path.relative(SRC, p).replace(/\\/g, '/');
  const fno = walk(SRC, ['cashEq']);

  test('no F&O file mentions equity collections or code (except the 2 allowed hooks)', () => {
    const hits = fno.filter((f) => /eqcash_|cashEq/.test(fs.readFileSync(f, 'utf8'))).map(rel).sort();
    expect(hits).toEqual(['controllers/authController.js', 'index.js']);
  });

  test('F&O code never lists or sweeps all collections', () => {
    const hits = fno.filter((f) => /listCollections|getCollectionNames|dropDatabase/.test(fs.readFileSync(f, 'utf8'))).map(rel);
    expect(hits).toEqual([]);
  });

  test('every equity model stores in an eqcash_* collection', () => {
    const models = require(path.join(SRC, 'cashEq', 'models'));
    const names = Object.values(models).map((m) => m.collection.collectionName);
    expect(names.length).toBeGreaterThanOrEqual(12);
    expect(names.filter((n) => !n.startsWith('eqcash_'))).toEqual([]);
  });

  test('equity code adds no field to F&O models and writes none', () => {
    const equity = walk(path.join(SRC, 'cashEq'), []);
    for (const f of equity) {
      const code = fs.readFileSync(f, 'utf8');
      expect({ f: rel(f), add: /(User|Master|Admin)\.schema\.add|\.discriminator\(/.test(code) }).toEqual({ f: rel(f), add: false });
      expect({ f: rel(f), write: /\b(Admin|Master|User|Trade|LedgerEntry|SettlementRun|Transaction|CreditTransaction|Watchlist|KiteInstrument)\.(create|insertMany|update\w*|replaceOne|delete\w*|findOneAndUpdate|findByIdAndUpdate|bulkWrite)\(/.test(code) })
        .toEqual({ f: rel(f), write: false });
    }
  });
});
