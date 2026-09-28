'use strict';

/**
 * SENSEX (the only BSE derivative this platform lists) is traded under NFO:
 * its contracts carry the NFO segments so NFO permissions, the NSE wallet,
 * NFO search tabs and the NFO expiry rules apply. Their `exchange` stays
 * 'BFO' — Kite quotes/margins and BSE's official settlement file are keyed
 * by exchange, not segment. Applied by every instrument sync so a refresh
 * from Kite never moves them back.
 */
const SEGMENT_ALIASES = Object.freeze({ 'BFO-FUT': 'NFO-FUT', 'BFO-OPT': 'NFO-OPT' });

function platformSegment(segment) {
  return SEGMENT_ALIASES[segment] || segment;
}

module.exports = { platformSegment, SEGMENT_ALIASES };
