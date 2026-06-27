// ============================================
// GTM-539 — Minimal semantic-version parsing + comparison
// ============================================
// The fleet reports firmware versions like "1.4.2" (optionally a leading "v"
// and/or a trailing build/pre-release suffix such as "1.4.2-rc1" or
// "1.4.2+abc123"). OTA resolution and anti-rollback (min-version) need a total
// order over these. We only depend on MAJOR.MINOR.PATCH; any pre-release/build
// metadata is parsed off but does NOT affect ordering here (a deliberate
// simplification — the firmware's own secure-version eFuse is the hard
// anti-rollback gate, this is the orchestration-side ordering).
//
// Everything here is PURE (no DB, no Express) so it is unit-testable.

/**
 * Parse a version string into { major, minor, patch } numbers.
 * Tolerant of a leading "v" and a trailing "-pre"/"+build" suffix.
 *
 * @param {*} version
 * @returns {{ major: number, minor: number, patch: number }|null} null if unparseable
 */
function parseSemver(version) {
  if (typeof version !== "string") return null;
  const cleaned = version.trim().replace(/^v/i, "");
  // Capture the leading numeric core; ignore any -prerelease / +build suffix.
  const m = /^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/.exec(cleaned);
  if (!m) return null;
  const major = Number(m[1]);
  const minor = Number(m[2]);
  const patch = Number(m[3]);
  if (![major, minor, patch].every(Number.isSafeInteger)) return null;
  return { major, minor, patch };
}

/**
 * True if the string is a parseable MAJOR.MINOR.PATCH version.
 * @param {*} version
 * @returns {boolean}
 */
function isValidSemver(version) {
  return parseSemver(version) !== null;
}

/**
 * Compare two version strings.
 *   returns < 0 if a <  b
 *   returns   0 if a == b
 *   returns > 0 if a >  b
 * Unparseable inputs sort BELOW any valid version (and equal to each other) so
 * a garbage/legacy version never masquerades as "newer".
 *
 * @param {string} a
 * @param {string} b
 * @returns {number}
 */
function compareSemver(a, b) {
  const pa = parseSemver(a);
  const pb = parseSemver(b);
  if (!pa && !pb) return 0;
  if (!pa) return -1;
  if (!pb) return 1;
  if (pa.major !== pb.major) return pa.major - pb.major;
  if (pa.minor !== pb.minor) return pa.minor - pb.minor;
  return pa.patch - pb.patch;
}

/** a > b */
function isNewer(a, b) {
  return compareSemver(a, b) > 0;
}

/** a >= b */
function gte(a, b) {
  return compareSemver(a, b) >= 0;
}

module.exports = {
  parseSemver,
  isValidSemver,
  compareSemver,
  isNewer,
  gte,
};
