'use strict';

// The audit middleware records successful admin/master changes after the
// response, and never touches client requests, reads or failures.
const created = [];
jest.mock('../src/models/AdminAction', () => ({ create: jest.fn(async (doc) => { created.push(doc); return doc; }) }));
jest.mock('../src/models/Admin', () => ({ findById: () => ({ select: () => ({ lean: async () => ({ username: 'ishant' }) }) }) }));
jest.mock('../src/models/Master', () => ({ findById: () => ({ select: () => ({ lean: async () => ({ username: 'harry' }) }) }) }));

const express = require('express');
const request = require('supertest');
const auditActions = require('../src/middlewares/auditActions');

const USER = '6accf69e5d53b458126f6b98';
function app() {
  const a = express();
  a.use(express.json());
  a.use('/api', auditActions);
  const as = (role) => (req, res, next) => { req.admin = role === 'admin' ? { id: 'a1' } : null; req.master = role === 'master' ? { id: 'm1' } : null; next(); };
  a.post('/api/trade', as('master'), (req, res) => res.status(201).json({ success: true, data: { _id: 't1', status: 'completed' } }));
  a.put('/api/admin/users/:id', as('admin'), (req, res) => res.json({ success: true, data: { _id: req.params.id } }));
  a.post('/api/admin/fail', as('admin'), (req, res) => res.status(400).json({ success: false }));
  a.post('/api/user-only', (req, res) => res.json({ success: true }));
  a.get('/api/admin/users', as('admin'), (req, res) => res.json({ success: true }));
  return a;
}
const flush = () => new Promise((r) => setTimeout(r, 20));

beforeEach(() => { created.length = 0; });

test('an order a master places for a client is recorded with name, client and result', async () => {
  await request(app()).post('/api/trade').send({ user_id: USER, tradingsymbol: 'GOLD', quantity: 1 });
  await flush();
  expect(created).toHaveLength(1);
  expect(created[0]).toMatchObject({ actor_type: 'master', actor_username: 'harry', method: 'POST', path: '/api/trade', target_ids: [USER], result: { id: 't1', status: 'completed' } });
});

test('an admin edit of a client is recorded, password redacted', async () => {
  await request(app()).put(`/api/admin/users/${USER}`).send({ close_only: true, password: 'p@ss' });
  await flush();
  expect(created[0]).toMatchObject({ actor_type: 'admin', actor_username: 'ishant', target_ids: [USER], body: { close_only: true, password: '[changed]' } });
});

test('failed requests, reads and client (non-staff) requests are not recorded', async () => {
  const a = app();
  await request(a).post('/api/admin/fail').send({ x: 1 });
  await request(a).get('/api/admin/users');
  await request(a).post('/api/user-only').send({ x: 1 });
  await flush();
  expect(created).toHaveLength(0);
});
