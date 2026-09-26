/**
 * TOTP Service — Google Authenticator / two-factor auth, shared by any
 * account model that has `totp_enabled`/`totp_secret` fields (currently
 * Admin and Master). Generalized from the original admin-only
 * adminOtpService.js — same behavior, just parameterized by which
 * Mongoose model to operate on instead of hardcoding Admin.
 *
 * Uses speakeasy for TOTP generation/verification with authenticator apps
 * (Google Authenticator, Microsoft Authenticator, etc.)
 *
 * Flow:
 * 1. Account enables TOTP → generate secret → show QR → scans → verifies first code → activated
 * 2. On login: if totp_enabled, ask for TOTP code → verify → issue JWT
 * 3. Reset: clear secret, disable TOTP → account can re-setup
 */

const speakeasy = require('speakeasy');
const QRCode = require('qrcode');

const ISSUER = 'APEX Trading';

/**
 * Generate a new TOTP secret and QR code data URL for an account.
 * Saves the secret to DB (not yet activated — totp_enabled stays false until verify-setup).
 * @param {import('mongoose').Model} Model - Admin or Master
 */
async function generateSecret(Model, accountId) {
  const account = await Model.findById(accountId);
  if (!account) throw new Error('Account not found');

  const secret = speakeasy.generateSecret({
    name: `${ISSUER} (${account.username})`,
    issuer: ISSUER,
    length: 20,
  });

  // Save secret (not activated yet)
  account.totp_secret = secret.base32;
  await account.save();

  // Generate QR code as data URL (base64 PNG)
  const qrDataUrl = await QRCode.toDataURL(secret.otpauth_url);

  return {
    qrDataUrl,
    secret: secret.base32, // for manual entry fallback
    otpauthUrl: secret.otpauth_url,
  };
}

/**
 * Verify the first TOTP code after QR scan — activates TOTP for the account.
 */
async function verifySetup(Model, accountId, token) {
  const account = await Model.findById(accountId).select('+totp_secret');
  if (!account || !account.totp_secret) throw new Error('No TOTP secret configured');

  const verified = speakeasy.totp.verify({
    secret: account.totp_secret,
    encoding: 'base32',
    token,
    window: 1, // ±30 sec clock drift
  });

  if (!verified) return false;

  account.totp_enabled = true;
  await account.save();
  return true;
}

/**
 * Verify TOTP code during login.
 */
async function verifyLogin(Model, accountId, token) {
  const account = await Model.findById(accountId).select('+totp_secret');
  if (!account || !account.totp_secret) return false;

  return speakeasy.totp.verify({
    secret: account.totp_secret,
    encoding: 'base32',
    token,
    window: 1,
  });
}

/**
 * Reset TOTP — clears secret and disables TOTP.
 */
async function resetTotp(Model, accountId) {
  await Model.findByIdAndUpdate(accountId, {
    totp_secret: null,
    totp_enabled: false,
  });
}

/**
 * Toggle TOTP enabled/disabled for an account.
 * If disabling, also clears the secret.
 */
async function toggleTotp(Model, accountId, enabled) {
  if (!enabled) {
    await Model.findByIdAndUpdate(accountId, {
      totp_enabled: false,
      totp_secret: null,
    });
  } else {
    await Model.findByIdAndUpdate(accountId, {
      totp_enabled: true,
    });
  }
}

/**
 * Get TOTP status for an account.
 */
async function getTotpStatus(Model, accountId) {
  const account = await Model.findById(accountId).select('totp_enabled totp_secret');
  if (!account) return null;
  return {
    enabled: account.totp_enabled || false,
    configured: !!account.totp_secret,
  };
}

module.exports = { generateSecret, verifySetup, verifyLogin, resetTotp, toggleTotp, getTotpStatus };
