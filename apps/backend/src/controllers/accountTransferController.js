'use strict';
/**
 * Admin → Transfer Accounts (owner, 9 Nov 2026). HTTP layer only; every rule
 * lives in services/accountTransferService.js.
 *
 *   GET  /api/admin/account-transfers/preview?user_ids=a,b&to_master_id=m   checks + money effects, writes nothing
 *   POST /api/admin/account-transfers                                        do it (needs the preview token)
 *   GET  /api/admin/account-transfers                                        history
 *   GET  /api/admin/account-transfers/:id                                    one transfer + a fresh verification
 *   POST /api/admin/account-transfers/:id/undo                               put it back (until the next settlement)
 */

const Admin = require('../models/Admin');
const service = require('../services/accountTransferService');
const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

function fail(res, error) {
  const status = Number(error?.status) || 500;
  const known = error instanceof service.TransferError || (status >= 400 && status < 500);
  if (!known) console.error('[AccountTransfer]', error);
  return res.status(status).json({
    success: false,
    message: known ? error.message : sanitizeErrorMessage(error),
    data: error?.data || null,
  });
}

async function actorOf(req) {
  const admin = await Admin.findById(req.admin.id).select('username').lean();
  return { id: String(req.admin.id), username: admin?.username || null };
}

const splitIds = (v) => (Array.isArray(v) ? v : String(v || '').split(','))
  .map((s) => String(s).trim())
  .filter(Boolean);

async function preview(req, res) {
  try {
    const data = await service.buildPreview({
      userIds: splitIds(req.query.user_ids),
      toMasterId: req.query.to_master_id,
      hiddenMasterIds: await resolveHiddenMasterIds(req),
    });
    return res.json({ success: true, message: 'Preview — nothing was changed', data });
  } catch (error) {
    return fail(res, error);
  }
}

async function transfer(req, res) {
  try {
    const { user_ids, to_master_id, token, accept_warnings, raise_low_rates, confirm_username } = req.body || {};
    const result = await service.applyTransfer({
      userIds: splitIds(user_ids),
      toMasterId: to_master_id,
      token,
      acceptWarnings: accept_warnings === true,
      raiseLowRates: raise_low_rates === true,
      confirmUsername: confirm_username,
      actor: await actorOf(req),
      hiddenMasterIds: await resolveHiddenMasterIds(req),
    });
    const n = result.transfer.items.length;
    return res.json({
      success: true,
      message: `${n} client${n > 1 ? 's' : ''} moved to ${result.transfer.to_master_username}${result.verification.ok ? ' — verified' : ' — CHECK: verification found a difference'}`,
      data: result,
    });
  } catch (error) {
    return fail(res, error);
  }
}

async function list(req, res) {
  try {
    const data = await service.listTransfers({ page: req.query.page, limit: req.query.limit });
    return res.json({ success: true, message: 'Account transfers', data });
  } catch (error) {
    return fail(res, error);
  }
}

async function detail(req, res) {
  try {
    const transfer = await service.getTransfer(req.params.id);
    const verification = await service.verifyTransfer(req.params.id);
    return res.json({ success: true, message: 'Account transfer', data: { transfer, verification } });
  } catch (error) {
    return fail(res, error);
  }
}

async function undo(req, res) {
  try {
    const result = await service.undoTransfer({
      transferId: req.params.id,
      confirmUsername: (req.body || {}).confirm_username,
      actor: await actorOf(req),
      hiddenMasterIds: await resolveHiddenMasterIds(req),
    });
    return res.json({
      success: true,
      message: `Transfer undone${result.verification.ok ? ' — verified' : ' — CHECK: verification found a difference'}`,
      data: result,
    });
  } catch (error) {
    return fail(res, error);
  }
}

module.exports = { preview, transfer, list, detail, undo };
