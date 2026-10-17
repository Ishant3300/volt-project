'use strict';

// Practice sign-up: validation, the account it creates, duplicate email, rate limit.

process.env.JWT_SECRET = 'test-secret';
jest.mock('../src/models/User', () => ({ exists: jest.fn(), create: jest.fn() }));
jest.mock('../src/models/Master', () => ({ findOne: jest.fn() }));
const mockInsertOne = jest.fn();
jest.mock('mongoose', () => ({ connection: { db: { collection: () => ({ insertOne: mockInsertOne }) } } }));

const User = require('../src/models/User');
const Master = require('../src/models/Master');
const { practiceSignup } = require('../src/controllers/practiceSignupController');

const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };
let ip = 0;
const req = (body) => ({ body, headers: { 'x-forwarded-for': `10.0.0.${++ip}` }, socket: {} });
const good = { name: 'Asha', email: 'Asha@Example.com', password: 'secret1', experience: 'new', markets: ['NSE_FUT', 'MCX'], tokens: 250000 };

beforeEach(() => {
  jest.clearAllMocks();
  User.exists.mockResolvedValue(null);
  Master.findOne.mockReturnValue({ lean: () => Promise.resolve({ _id: 'm1', server_id: 's1' }) });
  User.create.mockImplementation(async (doc) => ({ ...doc, _id: 'u1', save: jest.fn(), toJSON() { return { id: 'u1', username: doc.username }; } }));
});

test('creates a practice client: email login, tokens in each chosen market, no brokerage / password prompt', async () => {
  const r = res();
  await practiceSignup(req(good), r);
  expect(r.status).toHaveBeenCalledWith(201);
  const doc = User.create.mock.calls[0][0];
  expect(doc.username).toBe('asha@example.com');
  expect(doc.master_id).toBe('m1');
  expect(doc.credits).toBe(250000);
  expect(doc.wallet).toEqual({ NSE: 250000, INDEX: 250000, NSEOPT: 0, MCX: 250000, COMEX: 0, GLOBAL: 0 });
  expect(doc.exchanges_allowed.map((e) => e.exchange_name)).toEqual(['NFO-FUT', 'MCX-FUT']);
  expect(doc.change_pass_on_first_login).toBe(false);
  expect(doc.password).not.toBe('secret1'); // hashed
  const body = r.json.mock.calls[0][0];
  expect(body.data.token).toBeTruthy();
  expect(body.data.role).toBe('USER');
  expect(body.data.practice).toBe(true);
});

test.each([
  [{ name: 'A' }, 'name'],
  [{ email: 'not-an-email' }, 'email'],
  [{ password: '123' }, 'Password'],
  [{ experience: 'expert' }, 'experience'],
  [{ markets: [] }, 'market'],
  [{ markets: ['CRYPTO'] }, 'market'],
  [{ tokens: 0 }, 'tokens'],
  [{ tokens: 5e9 }, 'tokens'],
])('rejects %j', async (patch, word) => {
  const r = res();
  await practiceSignup(req({ ...good, ...patch }), r);
  expect(r.status).toHaveBeenCalledWith(400);
  expect(r.json.mock.calls[0][0].message.toLowerCase()).toContain(word.toLowerCase());
  expect(User.create).not.toHaveBeenCalled();
});

test('existing email → 409, nothing created', async () => {
  User.exists.mockResolvedValue({ _id: 'x' });
  const r = res();
  await practiceSignup(req(good), r);
  expect(r.status).toHaveBeenCalledWith(409);
  expect(User.create).not.toHaveBeenCalled();
});

test('no PRACTICE master → 503', async () => {
  Master.findOne.mockReturnValue({ lean: () => Promise.resolve(null) });
  const r = res();
  await practiceSignup(req(good), r);
  expect(r.status).toHaveBeenCalledWith(503);
});

test('max 5 sign-ups per IP per hour', async () => {
  const same = { body: good, headers: { 'x-forwarded-for': '10.9.9.9' }, socket: {} };
  for (let i = 0; i < 5; i++) { User.exists.mockResolvedValue(null); await practiceSignup({ ...same, body: { ...good, email: `a${i}@x.com` } }, res()); }
  const r = res();
  await practiceSignup({ ...same, body: { ...good, email: 'a9@x.com' } }, r);
  expect(r.status).toHaveBeenCalledWith(429);
});
