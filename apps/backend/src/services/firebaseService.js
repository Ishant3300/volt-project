/**
 * Firebase Cloud Messaging Service
 * 
 * Initializes Firebase Admin SDK and provides notification sending utilities.
 * Checks user's notification_settings before sending.
 * 
 * Requires GOOGLE_APPLICATION_CREDENTIALS env var pointing to service account JSON,
 * OR a firebase-service-account.json file in the project root.
 */

const admin = require('firebase-admin');
const User = require('../models/User');
const Master = require('../models/Master');
const Admin = require('../models/Admin');

let _initialized = false;

/**
 * Initialize Firebase Admin SDK.
 * Call once at server startup.
 */
const init = () => {
  if (_initialized) return;

  try {
    const path = require('path');
    const fs = require('fs');

    // Priority 1: full service-account JSON in an env var (FIREBASE_SERVICE_ACCOUNT).
    // Keeps the secret in .env (already gitignored + rsync-excluded) so there's
    // only one secret file to manage — no separate key file on disk.
    const saEnv = process.env.FIREBASE_SERVICE_ACCOUNT;
    if (saEnv && saEnv.trim()) {
      const serviceAccount = _parseServiceAccountEnv(saEnv);
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      console.log('🔥 [Firebase] Initialized from FIREBASE_SERVICE_ACCOUNT env var');
    } else {
      // Priority 2: service-account file on disk (legacy).
      const saPath = path.resolve(__dirname, '../firebase/firebase-service-account.json');
      if (fs.existsSync(saPath)) {
        const serviceAccount = require(saPath);
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount),
        });
        console.log('🔥 [Firebase] Initialized with service account file');
      } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
        // Priority 3: Google's standard env var pointing to a file path.
        admin.initializeApp({
          credential: admin.credential.applicationDefault(),
        });
        console.log('🔥 [Firebase] Initialized with GOOGLE_APPLICATION_CREDENTIALS');
      } else {
        console.log('⚠️  [Firebase] No service account found. Push notifications disabled.');
        console.log('   Set FIREBASE_SERVICE_ACCOUNT env var (JSON string)');
        console.log('   OR place firebase-service-account.json in src/firebase/');
        console.log('   OR set GOOGLE_APPLICATION_CREDENTIALS to a file path');
        return;
      }
    }

    _initialized = true;
  } catch (err) {
    console.error('❌ [Firebase] Init error:', err.message);
  }
};

/**
 * Parse the FIREBASE_SERVICE_ACCOUNT env var into a service-account object.
 *
 * Accepts either:
 *   • raw JSON string (the whole service-account file on one line), or
 *   • base64-encoded JSON (recommended for .env — avoids newline/quote issues).
 *
 * Also normalizes the private_key: values stored in .env commonly have the PEM
 * line breaks written as the two-character sequence backslash-n; the Firebase
 * SDK needs real newline characters, so we convert them.
 */
const _parseServiceAccountEnv = (raw) => {
  let jsonStr = raw.trim();

  // If it doesn't look like JSON, assume it's base64-encoded.
  if (!jsonStr.startsWith('{')) {
    jsonStr = Buffer.from(jsonStr, 'base64').toString('utf8');
  }

  const sa = JSON.parse(jsonStr);

  if (sa.private_key && sa.private_key.includes('\\n')) {
    sa.private_key = sa.private_key.replace(/\\n/g, '\n');
  }

  return sa;
};

const isAvailable = () => _initialized;

/**
 * Find the correct model for a userId by checking all three collections.
 */
const _findAccount = async (userId) => {
  let account = await User.findById(userId);
  if (account) return { account, model: 'User' };

  account = await Master.findById(userId);
  if (account) return { account, model: 'Master' };

  account = await Admin.findById(userId);
  if (account) return { account, model: 'Admin' };

  return null;
};

/**
 * Send a push notification to a user.
 * Checks notification_settings before sending.
 * 
 * @param {string} userId - Target user's MongoDB _id
 * @param {string} notificationType - One of: market_order, pending_order, admin_order_execution, admin_order_deletion
 * @param {object} payload - { title, body, data }
 */
const sendNotification = async (userId, notificationType, { title, body, data = {} }) => {
  if (!_initialized) return;

  try {
    const result = await _findAccount(userId);
    if (!result) {
      console.log(`⚠️  [Firebase] User ${userId} not found, skipping notification`);
      return;
    }

    const { account } = result;

    // Check if user has this notification type enabled
    const settings = account.notification_settings || {};
    if (settings[notificationType] === false) {
      console.log(`ℹ️  [Firebase] ${notificationType} disabled for user ${userId}, skipping`);
      return;
    }

    const tokens = account.fcm_tokens || [];
    if (tokens.length === 0) {
      console.log(`ℹ️  [Firebase] No FCM tokens for user ${userId}, skipping`);
      return;
    }

    const message = {
      notification: { title, body },
      android: {
        notification: {
          channelId: 'stocker_trades',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        },
      },
      apns: {
        payload: { aps: { sound: 'default', badge: 1 } },
      },
      data: {
        ...data,
        notification_type: notificationType,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      tokens,
    };

    const response = await admin.messaging().sendEachForMulticast(message);

    // Clean up invalid tokens
    const invalidTokens = [];
    response.responses.forEach((resp, idx) => {
      if (!resp.success) {
        const errCode = resp.error?.code;
        if (errCode === 'messaging/invalid-registration-token' ||
            errCode === 'messaging/registration-token-not-registered') {
          invalidTokens.push(tokens[idx]);
        }
      }
    });

    if (invalidTokens.length > 0) {
      // One atomic $pull, not a document save: two notifications to the same
      // account at once used to clash on the document version ("No matching
      // document found ... modifiedPaths fcm_tokens") and drop the cleanup.
      await account.constructor.updateOne({ _id: account._id }, { $pull: { fcm_tokens: { $in: invalidTokens } } });
      console.log(`🧹 [Firebase] Removed ${invalidTokens.length} invalid token(s) for user ${userId}`);
    }

    const successCount = response.responses.filter(r => r.success).length;
    if (successCount > 0) {
      console.log(`📲 [Firebase] Sent ${notificationType} to ${userId} (${successCount}/${tokens.length} devices)`);
    }
  } catch (err) {
    console.error(`❌ [Firebase] sendNotification error for ${userId}:`, err.message);
  }
};

/**
 * Send a raw push notification to a specific FCM token (no user lookup).
 */
const sendRawNotification = async (fcmToken, { title, body, data = {} }) => {
  if (!_initialized || !fcmToken) return;
  try {
    await admin.messaging().send({
      token: fcmToken,
      notification: { title, body },
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
    });
  } catch (err) {
    console.error(`❌ [Firebase] sendRawNotification error:`, err.message);
  }
};

module.exports = { init, isAvailable, sendNotification, sendRawNotification };
