/**
 * One-time migration: promote the existing single Admin account to Super
 * Admin. There is no API path for this deliberately — is_super_admin can
 * only ever be set here, never through superAdminController.js, since
 * there's meant to be exactly one Super Admin.
 *
 * Usage: node scripts/promoteSuperAdmin.js
 */
require('dotenv').config();
const mongoose = require('mongoose');
const Admin = require('../src/models/Admin');

const SUPER_ADMIN_USERNAME = 'Ishantapex33';

const promoteSuperAdmin = async () => {
  try {
    await mongoose.connect(process.env.MONGO_URI);
    console.log('MongoDB Connected');

    const admin = await Admin.findOne({ username: SUPER_ADMIN_USERNAME });
    if (!admin) {
      console.error(`Admin "${SUPER_ADMIN_USERNAME}" not found — nothing to promote.`);
      process.exit(1);
    }

    if (admin.is_super_admin) {
      console.log(`Admin "${SUPER_ADMIN_USERNAME}" is already Super Admin.`);
      process.exit(0);
    }

    admin.is_super_admin = true;
    await admin.save();

    console.log(`Admin "${SUPER_ADMIN_USERNAME}" promoted to Super Admin:`, admin.toJSON());
    process.exit(0);
  } catch (error) {
    console.error('Error:', error.message);
    process.exit(1);
  }
};

promoteSuperAdmin();
