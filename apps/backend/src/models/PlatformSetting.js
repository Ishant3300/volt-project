const mongoose = require('mongoose');

/**
 * Platform-wide settings an admin can change from the app/web, one document
 * per key (e.g. 'profit_book_min_minutes'). Read through the small cached
 * getters in utils/ (e.g. utils/profitBookTime.js), never ad hoc.
 */
const platformSettingSchema = new mongoose.Schema({
  key: { type: String, required: true, unique: true, trim: true },
  value: { type: mongoose.Schema.Types.Mixed, required: true },
  updated_by: {
    type: { type: String, enum: ['Admin', 'System'], default: 'System' },
    id: { type: mongoose.Schema.Types.ObjectId, default: null },
  },
}, { timestamps: true });

module.exports = mongoose.model('PlatformSetting', platformSettingSchema);
