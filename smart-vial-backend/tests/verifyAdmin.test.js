// ============================================
// GTM-539 — admin authorization (server-authoritative, no MongoDB)
// ============================================

const test = require("node:test");
const assert = require("node:assert");

const verifyAdmin = require("../middleware/verifyAdmin");
const { isAdminUser } = verifyAdmin;

function makeRes() {
  return {
    statusCode: null,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

test("isAdminUser: only allow-listed ids are admins; empty list denies all", () => {
  assert.strictEqual(isAdminUser("u1", ["u1", "u2"]), true);
  assert.strictEqual(isAdminUser("u3", ["u1", "u2"]), false);
  assert.strictEqual(isAdminUser("u1", []), false);
  assert.strictEqual(isAdminUser(undefined, ["u1"]), false);
  assert.strictEqual(isAdminUser({ $ne: null }, ["u1"]), false);
});

test("verifyAdmin: unauthenticated request is 401", () => {
  const res = makeRes();
  let called = false;
  verifyAdmin({}, res, () => {
    called = true;
  });
  assert.strictEqual(res.statusCode, 401);
  assert.strictEqual(called, false);
});

test("verifyAdmin: authenticated non-admin is 403 (role assertion ignored)", () => {
  const res = makeRes();
  let called = false;
  // Caller asserts an admin role — it must NOT help; allowlist is empty by default.
  verifyAdmin({ user_id: "u_not_admin", user_role: "admin" }, res, () => {
    called = true;
  });
  assert.strictEqual(res.statusCode, 403);
  assert.strictEqual(called, false);
});
