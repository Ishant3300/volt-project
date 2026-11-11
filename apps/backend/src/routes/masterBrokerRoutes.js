'use strict';

// /api/master/brokers — brokers for masters an admin has allowed (11 Nov 2026).
// Tracking only; see controllers/masterBrokerController.js.
const express = require('express');
const { authenticateMaster } = require('../middlewares/auth');
const { rejectIfInvestor } = require('../middlewares/rejectIfInvestor');
const ctl = require('../controllers/masterBrokerController');

const router = express.Router();
router.use(authenticateMaster);
router.get('/access', ctl.getAccess);
router.use(ctl.requireAccess);
router.get('/', ctl.list);
router.get('/limits', ctl.getLimits);
router.post('/', rejectIfInvestor, ctl.create);
router.put('/links/:linkId/end', rejectIfInvestor, ctl.endLink);
router.put('/master-links/:linkId/end', rejectIfInvestor, ctl.endMasterLink);
router.put('/:id', rejectIfInvestor, ctl.update);
router.delete('/:id', rejectIfInvestor, ctl.remove);
router.put('/:id/login', rejectIfInvestor, ctl.setLogin);
router.post('/:id/links', rejectIfInvestor, ctl.addLink);
router.post('/:id/master-links', rejectIfInvestor, ctl.addMasterLink);
router.get('/:id/statement', ctl.getStatement);

module.exports = router;
