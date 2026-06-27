const test = require("node:test");
const assert = require("node:assert");
const Module = require("module");

const {
  computeUnclaimDeviceState,
  removeDeviceId,
} = require("../utils/deviceClaim");

// Self-contained: no MongoDB / Postgres / network required. Model-dependent
// tests stub `../models/User` via the require cache before loading the helper.

// ============================================
// #51 — Unclaim leaves no stale caregiver link (pure state transition)
// ============================================

test("computeUnclaimDeviceState clears owner AND caregiver", () => {
  const device = { user_id: "owner_1", claimed: true, caregiver_id: "cg_1" };
  const next = computeUnclaimDeviceState(device);

  assert.strictEqual(next.user_id, null);
  assert.strictEqual(next.claimed, false);
  assert.strictEqual(next.caregiver_id, null);
  // The previous caregiver is surfaced so their caregiving_device_ids can be cleaned.
  assert.strictEqual(next.previousCaregiverId, "cg_1");
});

test("computeUnclaimDeviceState reports no caregiver when none assigned", () => {
  const next = computeUnclaimDeviceState({
    user_id: "owner_1",
    claimed: true,
    caregiver_id: null,
  });
  assert.strictEqual(next.previousCaregiverId, null);
  assert.strictEqual(next.caregiver_id, null);
});

test("removeDeviceId removes the id without mutating the input", () => {
  const ids = ["d1", "d2", "d3"];
  const out = removeDeviceId(ids, "d2");

  assert.deepStrictEqual(out, ["d1", "d3"]);
  // Original array untouched (no in-place splice).
  assert.deepStrictEqual(ids, ["d1", "d2", "d3"]);
});

test("removeDeviceId is a no-op when the id is absent and tolerates non-arrays", () => {
  assert.deepStrictEqual(removeDeviceId(["d1"], "x"), ["d1"]);
  assert.deepStrictEqual(removeDeviceId(undefined, "x"), []);
});

// ============================================
// #51 — Shared find-or-create helper behaviour
// ============================================

// Minimal in-memory stub of the Mongoose User model so the helper can be
// exercised without a database. Reproduces the find/new/save surface it uses.
function withStubbedUserModel(run) {
  const userPath = require.resolve("../models/User");
  const provPath = require.resolve("../utils/userProvisioning");
  const savedReal = require.cache[userPath];
  delete require.cache[provPath];

  const store = new Map(); // user_id -> record
  const created = [];

  class StubUser {
    constructor(doc) {
      Object.assign(this, doc);
      this._saves = 0;
    }
    async save() {
      this._saves += 1;
      store.set(this.user_id, this);
      return this;
    }
    static async findOne(query) {
      return store.get(query.user_id) || null;
    }
    static seed(record) {
      store.set(record.user_id, Object.assign(new StubUser(record), record));
    }
  }
  // Track every newly constructed-and-saved doc.
  const origSave = StubUser.prototype.save;
  StubUser.prototype.save = async function save() {
    if (!store.has(this.user_id)) created.push(this);
    return origSave.call(this);
  };

  require.cache[userPath] = new Module(userPath, module);
  require.cache[userPath].exports = StubUser;
  require.cache[userPath].loaded = true;

  const { findOrCreateUser } = require(provPath);

  return Promise.resolve(run({ findOrCreateUser, StubUser, store }))
    .finally(() => {
      // Restore the real model + a fresh helper for other test files.
      if (savedReal) require.cache[userPath] = savedReal;
      else delete require.cache[userPath];
      delete require.cache[provPath];
    });
}

test("findOrCreateUser creates a persisted user with the given role", async () => {
  await withStubbedUserModel(async ({ findOrCreateUser, store }) => {
    const user = await findOrCreateUser("new_user", "caregiver");

    assert.strictEqual(user.user_id, "new_user");
    assert.deepStrictEqual(user.user_roles, ["caregiver"]);
    assert.deepStrictEqual(user.claim_device_ids, []);
    assert.deepStrictEqual(user.caregiving_device_ids, []);
    // Persisted.
    assert.ok(store.has("new_user"));
  });
});

test("findOrCreateUser adds a missing role to an existing user", async () => {
  await withStubbedUserModel(async ({ findOrCreateUser, StubUser }) => {
    StubUser.seed({
      user_id: "existing",
      user_roles: ["user"],
      claim_device_ids: [],
      caregiving_device_ids: [],
    });

    const user = await findOrCreateUser("existing", "caregiver");
    assert.deepStrictEqual(user.user_roles, ["user", "caregiver"]);
  });
});

test("findOrCreateUser leaves roles untouched when already present", async () => {
  await withStubbedUserModel(async ({ findOrCreateUser, StubUser }) => {
    StubUser.seed({
      user_id: "existing2",
      user_roles: ["caregiver"],
      claim_device_ids: [],
      caregiving_device_ids: [],
    });

    const user = await findOrCreateUser("existing2", "caregiver");
    assert.deepStrictEqual(user.user_roles, ["caregiver"]);
  });
});

// ============================================
// #51 — verifyUserToken returns 401 (not 500) on missing/invalid token
// ============================================

// Stub better-auth so no Postgres connection is attempted. The factory returns
// an `auth` whose getSession behaviour is driven per-test.
function loadVerifyTokenWith(getSessionImpl) {
  const baPath = require.resolve("better-auth");
  const baNodePath = require.resolve("better-auth/node");
  const mwPath = require.resolve("../middleware/verifyUserToken");
  const pgPath = require.resolve("pg");

  const saved = {
    [baPath]: require.cache[baPath],
    [baNodePath]: require.cache[baNodePath],
    [mwPath]: require.cache[mwPath],
    [pgPath]: require.cache[pgPath],
  };

  function stub(path, exports) {
    const m = new Module(path, module);
    m.exports = exports;
    m.loaded = true;
    require.cache[path] = m;
  }

  stub(baPath, { betterAuth: () => ({ api: { getSession: getSessionImpl } }) });
  stub(baNodePath, { fromNodeHeaders: (h) => h });
  stub(pgPath, { Pool: class { constructor() {} } });
  delete require.cache[mwPath];

  const verifyToken = require(mwPath);

  const restore = () => {
    for (const [p, mod] of Object.entries(saved)) {
      if (mod) require.cache[p] = mod;
      else delete require.cache[p];
    }
    delete require.cache[mwPath];
  };
  return { verifyToken, restore };
}

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

test("verifyUserToken returns 401 when getSession returns no session", async () => {
  const { verifyToken, restore } = loadVerifyTokenWith(async () => null);
  try {
    const res = makeRes();
    let nextCalled = false;
    await verifyToken({ headers: {} }, res, () => {
      nextCalled = true;
    });
    assert.strictEqual(nextCalled, false);
    assert.strictEqual(res.statusCode, 401);
  } finally {
    restore();
  }
});

test("verifyUserToken returns 401 (not 500) when getSession throws", async () => {
  const { verifyToken, restore } = loadVerifyTokenWith(async () => {
    throw new Error("invalid token");
  });
  try {
    const res = makeRes();
    let nextCalled = false;
    await verifyToken({ headers: { authorization: "Bearer bad" } }, res, () => {
      nextCalled = true;
    });
    assert.strictEqual(nextCalled, false);
    assert.strictEqual(res.statusCode, 401);
  } finally {
    restore();
  }
});

test("verifyUserToken honours a 4xx status on the thrown error", async () => {
  const { verifyToken, restore } = loadVerifyTokenWith(async () => {
    const err = new Error("forbidden");
    err.status = 403;
    throw err;
  });
  try {
    const res = makeRes();
    await verifyToken({ headers: {} }, res, () => {});
    assert.strictEqual(res.statusCode, 403);
  } finally {
    restore();
  }
});

test("verifyUserToken calls next and attaches user on a valid session", async () => {
  const { verifyToken, restore } = loadVerifyTokenWith(async () => ({
    user: { id: "user_9", role: "caregiver" },
    session: { id: "sess_1" },
  }));
  try {
    const req = { headers: {} };
    const res = makeRes();
    let nextCalled = false;
    await verifyToken(req, res, () => {
      nextCalled = true;
    });
    assert.strictEqual(nextCalled, true);
    assert.strictEqual(req.user_id, "user_9");
    assert.strictEqual(req.user_role, "caregiver");
  } finally {
    restore();
  }
});
