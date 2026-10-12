const express = require('express');
const router = express.Router();
const { validateLogin } = require('../middlewares/validate');
const { userLogin, adminLogin, masterLogin, userLogout, adminLogout, masterLogout, universalLogin, changePassword, getNotificationSettings, updateNotificationSettings, registerFcmToken, removeFcmToken } = require('../controllers/authController');
const { authenticateUser, authenticateAdmin, authenticateMaster } = require('../middlewares/auth');
const { authenticateAny } = require('../middlewares/auth');
const { rejectIfInvestor } = require('../middlewares/rejectIfInvestor');
// Failed sign-ins -> LoginAttempt (monitoring); see the middleware.
const { trackLoginAttempt } = require('../middlewares/trackLoginAttempt');
const { recordClientEvents } = require('../controllers/clientEventController');

// Login attempt limiting (10 per 15 min per IP) switched OFF on the
// business owner's request (2026-09-28). The global limiter in index.js
// (200 requests/min per IP) still applies to every route, logins included.

// User login
router.post('/user/login', trackLoginAttempt('user'), validateLogin, userLogin);

// Admin login
router.post('/admin/login', trackLoginAttempt('admin'), validateLogin, adminLogin);

// Master login
router.post('/master/login', trackLoginAttempt('master'), validateLogin, masterLogin);

// Universal login
router.post('/login', trackLoginAttempt('universal'), validateLogin, universalLogin);

// Web/app problem reports (order refused on screen, crash, failed request) —
// signed in or not; see clientEventController.js. Read by the watchdog.
router.post('/client-events', recordClientEvents);

// User logout (requires authentication)
router.post('/user/logout', authenticateUser, userLogout);

// Admin logout (requires authentication)
router.post('/admin/logout', authenticateAdmin, adminLogout);

// Master logout (requires authentication)
router.post('/master/logout', authenticateMaster, masterLogout);

// Change password (any role — blocked in investor mode)
router.post('/change-password', authenticateAny, rejectIfInvestor, changePassword);

// Notification settings (any role — read allowed, write blocked in investor mode)
router.get('/notification-settings', authenticateAny, getNotificationSettings);
router.put('/notification-settings', authenticateAny, rejectIfInvestor, updateNotificationSettings);

// FCM token management (any role — allowed in investor mode for push notifications)
router.post('/fcm-token', authenticateAny, registerFcmToken);
router.delete('/fcm-token', authenticateAny, removeFcmToken);

// Self-service account deletion is switched OFF for every role (2026-09-28):
// a client deleted their own funded account from the app, which hid it —
// wallet and all — from their master's list with no notice. Accounts are
// closed by their master/admin instead. (deleteAccount is kept in
// authController.js, unused, in case this is ever re-enabled.)
router.delete('/account', authenticateAny, (req, res) => res.status(403).json({
  success: false,
  message: 'Account deletion is not available in the app. Please contact your master or admin to close your account.',
}));

module.exports = router;
