# Security model — B1–B5 mapping

> **UNVERIFIED REFERENCE.** This document maps each audit security fix (B1–B5,
> derived from findings F1–F9 in `reviews/FARDA_FIRMWARE_AUDIT.md`) to where it
> is implemented in this reconstruction. None of it has been validated on
> hardware. Treat as a design spec, not a certification.

## B1 — Auth / telemetry: never transmit the raw key

**Finding (F1):** the shipped firmware embedded the secret 32-byte key in every
network payload: `{"deviceId":"%s","authKey":"%s",...}`. Anyone on-path (or in
server logs) recovered a bearer credential that unlocks every privileged BLE
command.

**Fix — implemented:**
- `components/device_identity` holds a **factory-provisioned 32-byte per-device
  secret** (NVS `devKey`), loaded at boot, **never** serialized into a payload.
- `device_identity_sign()` computes **HMAC-SHA256** over
  `body || "\n" || nonce_hex || "\n" || timestamp` (SHA-256 only; no SHA-1 —
  fixes F8).
- `components/telemetry/telemetry.c` builds the event body **without an
  `authKey` field** and transmits `x-device-id` / `x-nonce` / `x-timestamp` /
  `x-signature` headers (HTTPS) or a JSON envelope (MQTTS).
- Constant-time comparison (`device_identity_ct_equal`) everywhere a secret/MAC
  is compared.
- The exact contract is frozen in `docs/WIRE_FORMAT.md` so the backend (A3)
  verifies the identical HMAC.

## B2 — BLE: secure pairing, per-command auth, replay defense

**Findings (F3, F4):** identity = guessable MAC; pairing was trust-on-first-use;
commands were plaintext, replayable GATT writes with no nonce; `ADD_ADMINKEY`
took no auth; destructive ops (UNBIND, SET_WIFI_CRED, SET_API_TARGET,
DELETE_LOG_FILE, LOCK/UNLOCK) were forgeable after one sniff.

**Fix — implemented:**
- **LE Secure Connections + MITM + bonding required** —
  `ESP_LE_AUTH_REQ_SC_MITM_BOND` and `ONLY_ACCEPT_SPECIFIED_SEC_AUTH` in
  `ble_service.c`. Privileged characteristics are marked
  `WRITE_ENC_MITM` (TODO at the attribute-table level) and the dispatcher
  re-checks `ble_auth_link_is_trusted()` — **"connected" ≠ "trusted"**.
- **Per-command HMAC auth** (`ble_auth.c`): each privileged command carries
  `[opcode][counter:4][tag:32][params]`; the tag is `HMAC-SHA256(opcode ||
  counter || params)` with the per-device secret.
- **Monotonic counter / replay rejection**: `ble_auth_verify()` rejects any
  command whose counter ≤ the last accepted counter.
- **Rate-limit / lockout**: after `BLE_AUTH_MAX_FAILS` failed privileged
  commands the link is locked out for `BLE_AUTH_LOCKOUT_MS`.
- **Proof-of-possession bind** replaces TOFU: `BIND_DEVICE` / `LOGIN_DEVICE`
  require an HMAC proof over a counter using the factory secret — only a holder
  of the provisioned secret (distributed to the legitimate owner via QR/OOB)
  can bind. No first-writer-wins.
- **`ADD_ADMINKEY` now requires auth** (classified privileged in
  `ble_auth_opcode_is_privileged`), still write-once.
- Factory key injection / eFuse handling is flagged as a **manufacturing
  decision** in `docs/PROVISIONING.md`; the firmware side (load + use the
  secret, fail closed if absent) is implemented.

## B3 — Transport: TLS-only, verified, domain-restricted

**Finding (F2):** arbitrary `scheme://host:port` targets, plaintext default, no
embedded CA, no server-cert verification → MITM-able.

**Fix — implemented (`telemetry.c`, gated by `CONFIG_SPB_REQUIRE_TLS` /
`CONFIG_SPB_RESTRICT_API_DOMAIN`):**
- `telemetry_set_api_target()` **rejects** any scheme that is not `https://` /
  `mqtts://` (fail closed).
- Host must match the **allow-list** in `board_config.h`
  (`BOARD_ALLOWED_API_DOMAIN_SUFFIXES`) — `SET_API_TARGET` cannot redirect
  telemetry to an attacker host.
- Server certificate is **verified** (`crt_bundle_attach` / pinned
  `cert_pem`); OTA refuses non-HTTPS (`ESP_HTTPS_OTA_ALLOW_HTTP=n`).
- A real CA bundle / pinned chain must be provisioned (see PROVISIONING.md); the
  placeholder is empty so an unconfigured build cannot silently trust a public
  CA.

## B4 — Secure boot / flash encryption / signed OTA

**Finding (F5):** secrets in NVS with no confirmed flash encryption; no
confirmed secure boot.

**Fix — documented + configured, gated behind sign-off:**
- `sdkconfig.defaults.prod` enables **Secure Boot v2** (image signing),
  **Flash Encryption (release mode)**, **NVS encryption**, and **signed OTA
  with anti-rollback** (`CONFIG_APP_ANTI_ROLLBACK`, secure version).
- `ota_update.c` verifies the server cert and relies on Secure Boot v2 to reject
  unsigned/downgraded images; refuses non-HTTPS URLs.
- These BURN one-way eFuses, so they are **NOT** in the dev defaults and **NOT**
  auto-run. `docs/PROVISIONING.md` gates them behind explicit maintainer
  sign-off.

## B5 — Build hygiene

**Findings (F6, F7):** `-dirty` provenance; debug commands (READ_LOG_FILE,
GATTS DB dump) shipped in production.

**Fix — implemented:**
- `CONFIG_SPB_DEBUG_BUILD` (Kconfig) gates **all** debug/log-dump commands.
  `READ_LOG_FILE 0x33` and the GATTS DB dump are `#if CONFIG_SPB_DEBUG_BUILD`
  and compiled out of release images (`sdkconfig.defaults.prod` sets it `n`).
- The top `CMakeLists.txt` embeds the **git revision** (`SPB_GIT_REV`) into the
  build and a **release build fails on a dirty tree** (`SPB_RELEASE=1`).
- Firmware version + git commit are reported via `ota_update_running_version()`
  and telemetry.

## Validator

`tools/validate_firmware.py` asserts each of the above at the source level and
is the CI gate. Run `python3 tools/validate_firmware.py`.

## Residual / out-of-scope items

- Real CA bundle, signing keys, and per-device secrets must be provisioned at
  manufacturing (PROVISIONING.md) — placeholders here are intentionally inert.
- Dose-sensing accuracy (HX711 voltage sensitivity, load-cell creep) is a
  **clinical-risk** item, not a security one, but is flagged in board_config.h
  TODOs and the README.
- All hardware constants (GPIO polarity, calibration, thresholds, BLE attribute
  table) are placeholders requiring bench validation.
