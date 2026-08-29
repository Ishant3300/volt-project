/**
 * Escapes regex special characters in user-supplied search input before it's
 * used to build a Mongo $regex filter. Without this, a search string like
 * `(a+)+$` sent to any of the several endpoints that pass query input
 * straight into $regex causes catastrophic backtracking (ReDoS) on the DB,
 * and unescaped `.`/`|`/etc. produce unintended matches beyond a literal
 * substring search.
 */
function escapeRegex(input) {
  return String(input).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

module.exports = { escapeRegex };
