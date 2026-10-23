'use strict';

/**
 * Practice backend only — mounted by authRoutes when PRACTICE_MODE=1.
 *
 * A practice account can delete itself from the app: App Store guideline
 * 5.1.1(v) requires in-app deletion for any app with in-app sign-up (the iOS
 * app is practice-only, 23 Oct 2026). Live accounts are still closed by their
 * master/admin only (authRoutes).
 *
 * Soft delete, like authController.deleteAccount, but with no open-position
 * check (simulated tokens, nothing to settle). Pending orders are cancelled and
 * leave the order book, and the email is freed so the person can sign up again.
 */
const User = require('../models/User');
const Trade = require('../models/Trade');
const orderBookService = require('../services/orderBookService');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

const deletePracticeAccount = async (req, res) => {
  try {
    // Practice accounts are clients; there are no practice masters/admins to self-delete.
    if (!req.user?.id) {
      return res.status(403).json({ success: false, message: 'Only practice accounts can be deleted here.' });
    }
    const user = await User.findOne({ _id: req.user.id, deleted_at: null });
    if (!user) return res.status(404).json({ success: false, message: 'Account not found' });

    const pending = await Trade.find({ user_id: user._id, status: 'pending', deleted_at: null });
    for (const trade of pending) {
      trade.status = 'cancelled';
      await trade.save();
      await orderBookService.removeOrder(
        trade._id.toString(),
        trade.instrument_token,
        trade.transaction_type,
        trade.order_type,
        trade.trigger_direction
      );
    }

    const now = new Date();
    await User.updateOne(
      { _id: user._id },
      {
        $set: {
          deleted_at: now,
          active_status: false,
          // username is unique — renamed so the email can sign up again.
          username: `${user.username}#deleted-${now.getTime()}`,
        },
      }
    );

    res.status(200).json({ success: true, message: 'Account deleted successfully' });
  } catch (error) {
    console.error('❌ Practice delete account error:', error);
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

module.exports = { deletePracticeAccount };
