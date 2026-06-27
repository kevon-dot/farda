// ============================================
// GTM-539 — registry / OTA / fleet controller (models stubbed, no MongoDB)
// ============================================
// Stubs Device + FirmwareRelease via the require cache, like
// caregiverController.test.js, so the HTTP handlers are exercised without a live
// DB. Proves: registry list/filter, credential rotate/revoke delegation, OTA
// pin + device-facing resolution, and fleet-health endpoints.

const test = require("node:test");
const assert = require("node:assert");
const Module = require("module");

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

// Build a stub device doc with the real-ish methods the controller calls.
function makeDeviceDoc(seed) {
  const doc = {
    device_id: seed.device_id,
    device_name: seed.device_name || "Vial",
    user_id: seed.user_id || null,
    caregiver_id: seed.caregiver_id || null,
    claimed: seed.claimed || false,
    isActive: seed.isActive !== false,
    revoked: seed.revoked || false,
    revoked_at: seed.revoked_at || null,
    battery_percent: seed.battery_percent != null ? seed.battery_percent : 100,
    firmware_version: seed.firmware_version || "1.0.0",
    cohort: seed.cohort || null,
    pinned_release_version: seed.pinned_release_version || null,
    calibration: seed.calibration || null,
    credential: seed.credential || null,
    last_seen: seed.last_seen || new Date(),
    last_sync_at: seed.last_sync_at || null,
    createdAt: seed.createdAt || new Date(),
    updatedAt: seed.updatedAt || new Date(),
    _saved: 0,
    isOnline() {
      return true;
    },
    async save() {
      this._saved += 1;
      return this;
    },
    toRegistry() {
      return {
        device_id: this.device_id,
        firmware_version: this.firmware_version,
        cohort: this.cohort,
        is_online: this.isOnline(),
        pinned_release_version: this.pinned_release_version,
        revoked: this.revoked,
        isActive: this.isActive,
        claimed: this.claimed,
        credential_version: this.credential ? this.credential.version : null,
      };
    },
    issueCredential() {
      this.credential = { version: (this.credential ? this.credential.version : 0) + 1, issued_at: new Date() };
      this.revoked = false;
      return "PLAINTEXT_SECRET_HEX";
    },
    rotateCredential() {
      return this.issueCredential();
    },
    revokeCredential() {
      this.credential = null;
      this.revoked = true;
      this.revoked_at = new Date();
    },
  };
  return doc;
}

// Load registry controller with Device + FirmwareRelease stubbed.
function withStubbedController(seed, run) {
  const devicePath = require.resolve("../models/Device");
  const releasePath = require.resolve("../models/FirmwareRelease");
  const ctrlPath = require.resolve("../controllers/registry.controller");

  const paths = [devicePath, releasePath, ctrlPath];
  const saved = {};
  for (const p of paths) saved[p] = require.cache[p];

  const devices = (seed.devices || []).map(makeDeviceDoc);
  const releases = (seed.releases || []).slice();

  function stub(path, exports) {
    const m = new Module(path, module);
    m.exports = exports;
    m.loaded = true;
    require.cache[path] = m;
  }

  // Chainable query for Device.find(...).sort().skip().limit()
  function deviceFind(query) {
    let list = devices.filter((d) => {
      if (query.isActive !== undefined && d.isActive !== query.isActive) return false;
      if (query.revoked !== undefined && d.revoked !== query.revoked) return false;
      if (query.claimed !== undefined && d.claimed !== query.claimed) return false;
      if (query.firmware_version !== undefined && d.firmware_version !== query.firmware_version) return false;
      if (query.cohort !== undefined && d.cohort !== query.cohort) return false;
      return true;
    });
    const chain = {
      sort() {
        return chain;
      },
      skip() {
        return chain;
      },
      limit() {
        return chain;
      },
      then(resolve, reject) {
        return Promise.resolve(list).then(resolve, reject);
      },
    };
    // Also allow direct await without sort/skip/limit (getFleetHealth).
    chain[Symbol.toStringTag] = "Promise";
    return chain;
  }

  const DeviceStub = {
    // Returns a thenable that ALSO supports .select('+credential'), so the
    // handler can either `await Device.findOne(q)` or
    // `await Device.findOne(q).select('+credential')`.
    findOne: (q) => {
      const found = devices.find((d) => d.device_id === q.device_id) || null;
      const promise = Promise.resolve(found);
      promise.select = () => Promise.resolve(found);
      return promise;
    },
    find: deviceFind,
  };

  const ReleaseStub = {
    findOne: async (q) => releases.find((r) => r.version === q.version) || null,
    find: async () => releases.slice(),
  };

  stub(devicePath, DeviceStub);
  stub(releasePath, ReleaseStub);

  delete require.cache[ctrlPath];
  const controller = require(ctrlPath);

  return Promise.resolve(run({ controller, devices, releases })).finally(() => {
    for (const p of paths) {
      if (saved[p]) require.cache[p] = saved[p];
      else delete require.cache[p];
    }
    delete require.cache[ctrlPath];
  });
}

// ---------------------------------------------------------------------------
// Registry list / filter
// ---------------------------------------------------------------------------

test("listDevices: filters by state=revoked", async () => {
  await withStubbedController(
    {
      devices: [
        { device_id: "D1", revoked: true },
        { device_id: "D2", revoked: false },
      ],
    },
    async ({ controller }) => {
      const res = makeRes();
      await controller.listDevices({ query: { state: "revoked" } }, res);
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.body.count, 1);
      assert.strictEqual(res.body.devices[0].device_id, "D1");
    }
  );
});

test("listDevices: filters by firmware version", async () => {
  await withStubbedController(
    {
      devices: [
        { device_id: "D1", firmware_version: "1.0.0" },
        { device_id: "D2", firmware_version: "2.0.0" },
      ],
    },
    async ({ controller }) => {
      const res = makeRes();
      await controller.listDevices({ query: { firmware: "2.0.0" } }, res);
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.body.count, 1);
      assert.strictEqual(res.body.devices[0].device_id, "D2");
    }
  );
});

test("listDevices: rejects an unknown state filter (400)", async () => {
  await withStubbedController({ devices: [] }, async ({ controller }) => {
    const res = makeRes();
    await controller.listDevices({ query: { state: "bogus" } }, res);
    assert.strictEqual(res.statusCode, 400);
  });
});

test("getDevice: 404 for unknown device", async () => {
  await withStubbedController({ devices: [] }, async ({ controller }) => {
    const res = makeRes();
    await controller.getDevice({ params: { device_id: "NOPE" } }, res);
    assert.strictEqual(res.statusCode, 404);
  });
});

// ---------------------------------------------------------------------------
// Credential lifecycle
// ---------------------------------------------------------------------------

test("rotateCredential: returns the new secret ONCE and persists", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", credential: { version: 1 } }] },
    async ({ controller, devices }) => {
      const res = makeRes();
      await controller.rotateCredential({ params: { device_id: "D1" } }, res);
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.body.secret, "PLAINTEXT_SECRET_HEX");
      assert.strictEqual(res.body.credential_version, 2);
      assert.ok(devices[0]._saved >= 1);
    }
  );
});

test("revokeCredential: flips revoked and clears credential", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", credential: { version: 3 }, revoked: false }] },
    async ({ controller, devices }) => {
      const res = makeRes();
      await controller.revokeCredential({ params: { device_id: "D1" } }, res);
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.body.revoked, true);
      assert.strictEqual(devices[0].revoked, true);
      assert.strictEqual(devices[0].credential, null);
    }
  );
});

test("issueCredential: 404 for unknown device", async () => {
  await withStubbedController({ devices: [] }, async ({ controller }) => {
    const res = makeRes();
    await controller.issueCredential({ params: { device_id: "NOPE" } }, res);
    assert.strictEqual(res.statusCode, 404);
  });
});

// ---------------------------------------------------------------------------
// OTA pin + device-facing check
// ---------------------------------------------------------------------------

test("setDevicePin: pins to an existing release", async () => {
  await withStubbedController(
    {
      devices: [{ device_id: "D1" }],
      releases: [{ version: "1.5.0" }],
    },
    async ({ controller, devices }) => {
      const res = makeRes();
      await controller.setDevicePin(
        { params: { device_id: "D1" }, body: { version: "1.5.0" } },
        res
      );
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(devices[0].pinned_release_version, "1.5.0");
    }
  );
});

test("setDevicePin: clearing the pin with null version", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", pinned_release_version: "1.5.0" }] },
    async ({ controller, devices }) => {
      const res = makeRes();
      await controller.setDevicePin(
        { params: { device_id: "D1" }, body: { version: null } },
        res
      );
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(devices[0].pinned_release_version, null);
    }
  );
});

test("setDevicePin: pinning to a non-existent release is 404", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1" }], releases: [] },
    async ({ controller }) => {
      const res = makeRes();
      await controller.setDevicePin(
        { params: { device_id: "D1" }, body: { version: "9.9.9" } },
        res
      );
      assert.strictEqual(res.statusCode, 404);
    }
  );
});

test("checkForUpdate: device behind an active release is offered the signed ref", async () => {
  await withStubbedController(
    {
      releases: [
        {
          version: "1.2.0",
          image_url: "https://cdn.example.com/fw/1.2.0.bin",
          image_ref: "fw/1.2.0",
          image_sha256: null,
          min_version: null,
          rollout_state: "active",
          target_device_ids: [],
          target_cohorts: [],
          createdAt: new Date(),
        },
      ],
    },
    async ({ controller }) => {
      const res = makeRes();
      const req = {
        device: { device_id: "D1", firmware_version: "1.0.0", cohort: null, pinned_release_version: null },
        body: {},
      };
      await controller.checkForUpdate(req, res);
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.body.update_available, true);
      assert.strictEqual(res.body.version, "1.2.0");
      assert.ok(/^https:\/\//.test(res.body.image_url));
    }
  );
});

test("checkForUpdate: device-reported firmware_version in body is honored", async () => {
  await withStubbedController(
    {
      releases: [
        {
          version: "1.2.0",
          image_url: "https://cdn.example.com/fw/1.2.0.bin",
          rollout_state: "active",
          target_device_ids: [],
          target_cohorts: [],
          createdAt: new Date(),
        },
      ],
    },
    async ({ controller }) => {
      const res = makeRes();
      // Stored is 1.0.0 but device reports it already upgraded to 1.2.0.
      const req = {
        device: { device_id: "D1", firmware_version: "1.0.0", cohort: null, pinned_release_version: null },
        body: { firmware_version: "1.2.0" },
      };
      await controller.checkForUpdate(req, res);
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.body.update_available, false);
    }
  );
});

// ---------------------------------------------------------------------------
// Fleet health
// ---------------------------------------------------------------------------

test("getFleetHealth: returns unhealthy devices + summary", async () => {
  const old = new Date(Date.now() - 60 * 60 * 1000); // 1h ago -> offline+stale
  const fresh = new Date();
  await withStubbedController(
    {
      devices: [
        { device_id: "OK", battery_percent: 90, last_seen: fresh, last_sync_at: fresh, isActive: true },
        { device_id: "BAD", battery_percent: 90, last_seen: old, last_sync_at: old, isActive: true },
      ],
    },
    async ({ controller }) => {
      const res = makeRes();
      await controller.getFleetHealth({ query: {} }, res);
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.body.total, 2);
      assert.strictEqual(res.body.summary.unhealthy, 1);
      assert.strictEqual(res.body.unhealthy[0].device_id, "BAD");
      assert.ok(res.body.thresholds);
    }
  );
});

test("getDeviceHealth: 404 for unknown device", async () => {
  await withStubbedController({ devices: [] }, async ({ controller }) => {
    const res = makeRes();
    await controller.getDeviceHealth({ params: { device_id: "NOPE" } }, res);
    assert.strictEqual(res.statusCode, 404);
  });
});
