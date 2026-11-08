const express = require('express');
const router = express.Router();
const { authenticateAny } = require('../middlewares/auth');
const {
  getWatchlist,
  addToWatchlist,
  removeFromWatchlist,
} = require('../controllers/watchlistController');

// All routes require user or admin authentication
router.use(authenticateAny);

// Investor mode (owner, 9 Nov 2026) may keep its own watchlist — add and
// remove scripts. It changes nothing else: every order action stays blocked
// in investor mode (tradeRoutes.js rejectIfInvestor on place / cancel /
// modify / delete / rollover).
router.get('/', getWatchlist);
router.post('/', addToWatchlist);
router.delete('/:id', removeFromWatchlist);

module.exports = router;
