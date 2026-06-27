// ============================================
// NoSQL operator-injection protection (#37)
// ============================================
// Strips keys that start with "$" (Mongo operators like $ne, $gt, $where)
// or contain "." (dotted-path operators) from any incoming object. This stops
// attackers from sending bodies like { device_id: { $ne: null } } that would
// otherwise reach Mongoose query/document construction.
//
// Express 5 makes `req.query` a read-only getter, so a library that mutates it
// in place throws. We instead build sanitized copies with a pure helper and
// assign them only where the property is writable (falling back to mutating in
// place when it is not).

/**
 * Returns true when a key is a Mongo operator-injection vector.
 * @param {string} key
 * @returns {boolean}
 */
function isDangerousKey(key) {
  return typeof key === "string" && (key.startsWith("$") || key.includes("."));
}

/**
 * Pure helper: returns a NEW value with all dangerous keys removed, recursively.
 * Does not mutate its input. Arrays are mapped, plain objects are rebuilt.
 * Primitives (and Date/Buffer/etc.) are returned as-is.
 *
 * @param {*} value
 * @returns {*}
 */
function deepSanitize(value) {
  if (Array.isArray(value)) {
    return value.map((item) => deepSanitize(item));
  }

  // Only treat plain objects as key/value maps. Leave class instances
  // (Date, Buffer, etc.) untouched so we don't corrupt non-attack payloads.
  if (value !== null && typeof value === "object" && isPlainObject(value)) {
    const clean = {};
    for (const key of Object.keys(value)) {
      if (isDangerousKey(key)) continue;
      clean[key] = deepSanitize(value[key]);
    }
    return clean;
  }

  return value;
}

/**
 * @param {*} value
 * @returns {boolean}
 */
function isPlainObject(value) {
  if (value === null || typeof value !== "object") return false;
  const proto = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null;
}

/**
 * Express middleware that sanitizes body, query, and params.
 * Assigns the sanitized copy where the property is writable; otherwise mutates
 * the existing object in place (needed for Express 5 read-only req.query).
 */
function sanitizeRequest(req, _res, next) {
  for (const prop of ["body", "query", "params"]) {
    const original = req[prop];
    if (!original || typeof original !== "object") continue;

    const sanitized = deepSanitize(original);

    if (trySetProperty(req, prop, sanitized)) continue;

    // Read-only getter (Express 5 req.query): mutate the existing object so the
    // reference the rest of the stack reads from is cleaned.
    mutateInPlace(original, sanitized);
  }
  next();
}

/**
 * Attempts to assign req[prop] = value. Returns true on success.
 * @returns {boolean}
 */
function trySetProperty(req, prop, value) {
  try {
    req[prop] = value;
    return req[prop] === value;
  } catch {
    return false;
  }
}

/**
 * Replaces the contents of `target` with the keys of `replacement` in place.
 * Used when the container itself cannot be reassigned.
 */
function mutateInPlace(target, replacement) {
  if (Array.isArray(target)) {
    target.length = 0;
    for (const item of replacement) target.push(item);
    return;
  }
  for (const key of Object.keys(target)) {
    delete target[key];
  }
  Object.assign(target, replacement);
}

module.exports = {
  sanitizeRequest,
  deepSanitize,
  isDangerousKey,
  isPlainObject,
};
