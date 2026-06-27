const test = require("node:test");
const assert = require("node:assert");
const JWT = require("jsonwebtoken");
const config = require("../config/config");

// Self-contained unit tests: no MongoDB / Postgres / network required.

test("config exposes expected structure and defaults", () => {
  assert.ok(config.jwt && typeof config.jwt.secret === "string");
  assert.strictEqual(config.jwt.expiresIn, "30d");
  assert.strictEqual(config.tymeSync.toleranceSeconds, 300);
  assert.ok(Array.isArray(config.cors.origins));
  assert.strictEqual(typeof config.rateLimit.windowMs, "number");
  assert.strictEqual(typeof config.rateLimit.maxRequests, "number");
  assert.ok(typeof config.device.apiKey === "string" && config.device.apiKey.length > 0);
});

test("JWT sign/verify round-trips and preserves claims", () => {
  const secret = "unit-test-secret";
  const payload = { sub: "user_123", role: "caregiver" };
  const token = JWT.sign(payload, secret, { expiresIn: "1h" });

  const decoded = JWT.verify(token, secret);
  assert.strictEqual(decoded.sub, "user_123");
  assert.strictEqual(decoded.role, "caregiver");
  assert.ok(decoded.exp > decoded.iat);
});

test("JWT verify rejects a token signed with a different secret", () => {
  const token = JWT.sign({ sub: "x" }, "secret-a");
  assert.throws(() => JWT.verify(token, "secret-b"), /invalid signature/);
});
