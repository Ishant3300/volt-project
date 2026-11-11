'use strict';

// /api/broker — the broker view (owner, 11 Nov 2026). Read-only: GET only,
// broker tokens only, and every client route checks the client is linked to
// this broker right now (controller.assertLinked).
const express = require('express');
const { requireBroker, readOnly } = require('./auth');
const ctl = require('./controller');

const router = express.Router();
router.use(requireBroker, readOnly);
router.get('/me', ctl.me);
router.get('/statement', ctl.statement);
router.get('/clients', ctl.clients);
router.get('/clients/:userId', ctl.clientMetrics);
router.get('/clients/:userId/trades', ctl.clientTrades);
router.get('/clients/:userId/bill-data', ctl.clientBillData);

module.exports = router;
