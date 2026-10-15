const Announcement = require('../models/Announcement');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

/** Admin: create/update the active announcement */
const setAnnouncement = async (req, res) => {
  try {
    const { message } = req.body;
    if (!message || !message.trim()) {
      return res.status(400).json({ success: false, message: 'Message is required' });
    }
    // Replaces only the admin's own section; the ban list and new-contract
    // notices keep scrolling alongside it (services/announcementBoard.js).
    const announcement = await require('../services/announcementBoard').postSection('manual', message, { createdBy: req.admin?.id });
    res.status(201).json({ success: true, message: 'Announcement set', data: announcement });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/** Admin: clear the active announcement */
const clearAnnouncement = async (req, res) => {
  try {
    await Announcement.updateMany({ is_active: true }, { $set: { is_active: false } });
    res.status(200).json({ success: true, message: 'Announcement cleared' });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/** Any role: get the current active announcement */
const getActiveAnnouncement = async (req, res) => {
  try {
    // Every live section joined into the one scrolling line.
    const data = await require('../services/announcementBoard').activeBanner();
    res.status(200).json({ success: true, data });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

module.exports = { setAnnouncement, clearAnnouncement, getActiveAnnouncement };
