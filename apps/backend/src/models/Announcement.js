const mongoose = require('mongoose');

const announcementSchema = new mongoose.Schema({
  message: { type: String, required: true },
  is_active: { type: Boolean, default: true },
  created_by: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin' },
  // The banner is one scrolling line made of sections (services/
  // announcementBoard.js): an admin's own message, each day's "NEW CONTRACT
  // Open" notice, the NSE F&O ban list. Each source replaces only its own
  // section. Rows from before sections existed count as 'manual'.
  source: { type: String, enum: ['manual', 'expiry', 'ban'], default: 'manual' },
  ref: { type: String, default: null }, // expiry: the open day 'YYYY-MM-DD'
  expires_at: { type: Date, default: null }, // dropped from the banner after this
}, { timestamps: true });

announcementSchema.set('toJSON', {
  transform: (doc, ret) => {
    ret.id = ret._id;
    delete ret._id;
    delete ret.__v;
    ret.created_at = ret.createdAt;
    ret.updated_at = ret.updatedAt;
    delete ret.createdAt;
    delete ret.updatedAt;
    return ret;
  }
});

// ─── NEW: Active announcement lookup ───
announcementSchema.index({ is_active: 1, createdAt: -1 });

module.exports = mongoose.model('Announcement', announcementSchema);
