'use strict';

// /api/cash-eq — equity (NSE cash) routes. Mounted once in index.js; nothing else in the
// F&O app routes here. Every route checks the on/off switch first (auth.requireCash).

const express = require('express');
const { requireCash, noWatchOnly } = require('./auth');
const c = require('./controller');

const router = express.Router();

const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch((err) => {
  console.log(`❌ [cashEq] ${req.method} ${req.originalUrl}: ${err.message}`);
  if (!res.headersSent) res.status(500).json({ success: false, message: 'Something went wrong', data: null });
});

const anyone = requireCash('admin', 'cash_master', 'cash_client');
const managers = requireCash('admin', 'cash_master');

router.get('/me', anyone, wrap(c.me));
router.post('/me/password', requireCash('cash_master', 'cash_client'), wrap(c.changeOwnPassword));

router.get('/username/generate', managers, wrap(c.generateUsername));

router.get('/masters', managers, wrap(c.listMasters));
router.post('/masters', managers, noWatchOnly, wrap(c.createMaster));
router.get('/masters/:id', managers, wrap(c.getMaster));
router.patch('/masters/:id', managers, noWatchOnly, wrap(c.updateMaster));
router.delete('/masters/:id', managers, noWatchOnly, wrap(c.deleteMaster));

router.get('/clients', managers, wrap(c.listClients));
router.post('/clients', managers, noWatchOnly, wrap(c.createClient));
router.get('/clients/:id', managers, wrap(c.getClient));
router.patch('/clients/:id', managers, noWatchOnly, wrap(c.updateClient));
router.delete('/clients/:id', managers, noWatchOnly, wrap(c.deleteClient));

router.get('/ledger', requireCash('cash_client'), wrap(c.listLedger)); // client's own entries
router.get('/clients/:id/ledger', managers, wrap(c.listLedger));
router.post('/clients/:id/ledger', managers, noWatchOnly, wrap(c.addLedger));
router.delete('/clients/:id/ledger/:entryId', managers, noWatchOnly, wrap(c.deleteLedger));

module.exports = router;
