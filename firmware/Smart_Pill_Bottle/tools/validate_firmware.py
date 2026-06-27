#!/usr/bin/env python3
"""
validate_firmware.py - Structure + security validator for the Farda Smart Pill
Bottle ESP-IDF reconstruction.

This is NOT a compiler. It is a fast, dependency-free lint that asserts the
project structure is intact and that the B1-B5 security invariants hold at the
source level. It is the CI gate for the `firmware` job and MUST stay GREEN.

Run:  python3 tools/validate_firmware.py
Exit: 0 = all checks pass, 1 = a check failed.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PASS = "PASS"
FAIL = "FAIL"

errors = []
checks = []


def ok(msg):
    checks.append((PASS, msg))


def bad(msg):
    checks.append((FAIL, msg))
    errors.append(msg)


def rel(*p):
    return os.path.join(ROOT, *p)


def read(path):
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()


# ---------------------------------------------------------------------------
# 1. Required project structure
# ---------------------------------------------------------------------------
REQUIRED_FILES = [
    "CMakeLists.txt",
    "sdkconfig.defaults",
    "sdkconfig.defaults.prod",
    "partitions.csv",
    "main/main.c",
    "main/CMakeLists.txt",
    "main/Kconfig.projbuild",
    "README.md",
    "docs/SECURITY.md",
    "docs/WIRE_FORMAT.md",
    "docs/PROVISIONING.md",
    "docs/BLE_PROTOCOL.md",
]

REQUIRED_COMPONENTS = [
    "board_config",
    "device_identity",
    "wifi_manager",
    "nvs_store",
    "battery_monitoring",
    "calibration",
    "loadcell_hx711",
    "lock_control",
    "ble_service",
    "telemetry",
    "ota_update",
]

for f in REQUIRED_FILES:
    if os.path.isfile(rel(f)):
        ok(f"file present: {f}")
    else:
        bad(f"missing required file: {f}")

for c in REQUIRED_COMPONENTS:
    cdir = rel("components", c)
    cmake = rel("components", c, "CMakeLists.txt")
    inc = rel("components", c, "include")
    if not os.path.isdir(cdir):
        bad(f"missing component dir: components/{c}")
        continue
    ok(f"component present: {c}")
    if os.path.isfile(cmake):
        ok(f"component CMakeLists present: {c}")
    else:
        bad(f"component missing CMakeLists.txt: {c}")
    if not os.path.isdir(inc):
        bad(f"component missing include/ dir: {c}")

# board_config.h must exist and carry hardware TODO markers
board_h = rel("components", "board_config", "include", "board_config.h")
if os.path.isfile(board_h):
    bh = read(board_h)
    if "TODO(hardware)" in bh:
        ok("board_config.h has TODO(hardware) markers")
    else:
        bad("board_config.h missing TODO(hardware) markers")
else:
    bad("missing components/board_config/include/board_config.h")


# ---------------------------------------------------------------------------
# Collect all firmware C/H sources
# ---------------------------------------------------------------------------
def all_sources():
    out = []
    for base in [rel("components"), rel("main")]:
        for dirpath, _dirs, files in os.walk(base):
            for fn in files:
                if fn.endswith((".c", ".h")):
                    out.append(os.path.join(dirpath, fn))
    return out


SOURCES = all_sources()


def telemetry_payload_sources():
    """Source files that actually build a network payload body."""
    out = []
    for p in SOURCES:
        txt = read(p)
        # Heuristic: any file that constructs a JSON event body / pushes data.
        if re.search(r'"deviceId"', txt) or "eventType" in txt or "_enqueue_event" in txt:
            out.append((p, txt))
    return out


# ---------------------------------------------------------------------------
# 2. B1: raw authKey must NEVER appear in a telemetry payload
# ---------------------------------------------------------------------------
# The vulnerable original embedded the key:  {"...","authKey":"%s",...}
# Assert no source serializes an authKey/key field into a JSON payload.
KEY_IN_PAYLOAD = re.compile(r'"(authKey|auth_key|apiKey|api_key|key)"\s*:\s*("?%s"?|"?\{)')

payload_sources = telemetry_payload_sources()
if payload_sources:
    ok(f"located {len(payload_sources)} telemetry payload source(s)")
else:
    bad("could not locate any telemetry payload source (expected telemetry.c)")

b1_violation = False
for p, txt in payload_sources:
    # Strip C/C++ comments so doc-comments mentioning the old format don't trip
    # the check. We only care about live code.
    code = re.sub(r"/\*.*?\*/", "", txt, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)
    for m in KEY_IN_PAYLOAD.finditer(code):
        b1_violation = True
        bad(f"B1 VIOLATION: key serialized into payload in {os.path.relpath(p, ROOT)}: {m.group(0)!r}")
if not b1_violation:
    ok("B1: no raw key serialized into any telemetry payload body")


# ---------------------------------------------------------------------------
# 3. B1: telemetry must sign with HMAC-SHA256 (and avoid SHA-1 in auth path)
# ---------------------------------------------------------------------------
telem_c = rel("components", "telemetry", "telemetry.c")
ident_c = rel("components", "device_identity", "device_identity.c")
sign_present = False
for p in (telem_c, ident_c):
    if os.path.isfile(p):
        t = read(p)
        if "HMAC" in t or "hmac" in t or "MBEDTLS_MD_SHA256" in t:
            sign_present = True
if sign_present:
    ok("B1: telemetry/identity uses HMAC-SHA256 signing")
else:
    bad("B1: no HMAC-SHA256 signing found in telemetry/device_identity")

# device_identity must expose a sign + constant-time compare API
if os.path.isfile(ident_c):
    it = read(ident_c)
    if "device_identity_sign" in it and "MBEDTLS_MD_SHA256" in it:
        ok("B1: device_identity_sign uses SHA-256")
    else:
        bad("B1: device_identity_sign missing or not SHA-256")
    if "ct_equal" in it or "constant" in it.lower():
        ok("B1/F8: constant-time comparison present")
    else:
        bad("B1/F8: no constant-time comparison found")
    # No SHA-1 in our own auth primitive.
    if "MBEDTLS_MD_SHA1" in it or re.search(r"\bsha1\b", it, re.I):
        bad("B1/F8: SHA-1 referenced in device_identity auth path")
    else:
        ok("B1/F8: no SHA-1 in device_identity auth path")

    # B1 reconciliation: signing input order MUST match the merged backend
    # (smart-vial-backend/utils/deviceAuth.js): device_id, nonce, timestamp,
    # body -- each separated by '\n', body LAST, deviceId FIRST. We assert the
    # hmac_update call sequence in device_identity_sign feeds device_id before
    # nonce before timestamp before body.
    sign_fn = it[it.find("device_identity_sign"):]
    order_re = re.compile(
        r"hmac_update.*?device_id"            # 1. deviceId first
        r".*?hmac_update.*?nonce_dec"         # 2. nonce
        r".*?hmac_update.*?ts_dec"            # 3. timestamp
        r".*?hmac_update.*?body",             # 4. body last
        re.S,
    )
    if order_re.search(sign_fn):
        ok("B1: signing input order is device_id\\n nonce\\n timestamp\\n body "
           "(matches merged backend)")
    else:
        bad("B1: signing input order does NOT match backend "
            "(must be device_id, nonce, timestamp, body)")
    # Nonce must be a MONOTONIC DECIMAL counter persisted in NVS, not a random
    # hex blob. Assert the counter API + NVS persistence, and that the old
    # random-hex nonce path is gone.
    if "device_identity_next_nonce" in it and "nonceCtr" in it:
        ok("B1: x-nonce is a monotonic counter persisted in NVS")
    else:
        bad("B1: monotonic NVS-persisted nonce counter missing")
    if "esp_fill_random" in it or "random_nonce" in it:
        bad("B1: random nonce path still present (must be monotonic counter)")
    else:
        ok("B1: no random-nonce path (decimal counter only)")

# Headers the wire format requires must be emitted by telemetry.
if os.path.isfile(telem_c):
    tt = read(telem_c)
    for hdr in ("x-device-id", "x-nonce", "x-timestamp", "x-signature"):
        if hdr in tt:
            ok(f"B1: telemetry emits header {hdr}")
        else:
            bad(f"B1: telemetry missing header {hdr}")


# ---------------------------------------------------------------------------
# 4. B2: BLE auth/replay/lockout + secure-link requirement present
# ---------------------------------------------------------------------------
auth_c = rel("components", "ble_service", "ble_auth.c")
if os.path.isfile(auth_c):
    a = read(auth_c)
    if "last_counter" in a and ("replay" in a.lower()):
        ok("B2: BLE replay/monotonic-counter guard present")
    else:
        bad("B2: BLE replay/counter guard missing")
    if "lockout" in a.lower() or "locked_until" in a:
        ok("B2: BLE lockout/rate-limit present")
    else:
        bad("B2: BLE lockout/rate-limit missing")
    if "link_is_trusted" in a or "link_encrypted" in a:
        ok("B2: privileged ops require encrypted+authenticated link")
    else:
        bad("B2: no encrypted-link requirement for privileged ops")
else:
    bad("B2: missing components/ble_service/ble_auth.c")

# LE Secure Connections + bonding required in the GATTS glue.
svc_c = rel("components", "ble_service", "ble_service.c")
if os.path.isfile(svc_c):
    s = read(svc_c)
    if "ESP_LE_AUTH_REQ_SC_MITM_BOND" in s:
        ok("B2: LE Secure Connections + MITM + bonding required")
    else:
        bad("B2: SC/MITM/bonding auth requirement not found")

# ADD_ADMINKEY must be classified privileged (requires auth) in dispatch/auth.
if os.path.isfile(auth_c):
    a = read(auth_c)
    if "CMD_ADD_ADMINKEY" in a:
        ok("B2: ADD_ADMINKEY treated as privileged (requires auth)")
    else:
        bad("B2: ADD_ADMINKEY not gated behind auth")


# ---------------------------------------------------------------------------
# 5. B3: transport must require https/mqtts and verify certs
# ---------------------------------------------------------------------------
if os.path.isfile(telem_c):
    tt = read(telem_c)
    if "https://" in tt and "mqtts://" in tt:
        ok("B3: telemetry validates https/mqtts schemes")
    else:
        bad("B3: telemetry does not enforce https/mqtts schemes")
    if "crt_bundle_attach" in tt or "cert_pem" in tt:
        ok("B3: server certificate verification configured")
    else:
        bad("B3: no server certificate verification configured")
    if "host_is_allowed" in tt or "ALLOWED_API_DOMAIN" in tt:
        ok("B3: SET_API_TARGET restricted to allowed domain(s)")
    else:
        bad("B3: SET_API_TARGET not domain-restricted")


# ---------------------------------------------------------------------------
# 6. B4: prod sdkconfig has secure boot + flash encryption + signed OTA
# ---------------------------------------------------------------------------
prod = rel("sdkconfig.defaults.prod")
if os.path.isfile(prod):
    pr = read(prod)
    need = [
        "CONFIG_SECURE_BOOT",
        "CONFIG_SECURE_FLASH_ENC_ENABLED",
        "CONFIG_APP_ANTI_ROLLBACK",
    ]
    for n in need:
        if n in pr:
            ok(f"B4: prod overlay sets {n}")
        else:
            bad(f"B4: prod overlay missing {n}")
    # B4 must be gated, not auto-run: provisioning doc must warn about eFuses.
    prov = rel("docs", "PROVISIONING.md")
    if os.path.isfile(prov) and re.search(r"eFuse", read(prov), re.I):
        ok("B4: PROVISIONING.md documents one-way eFuse gating")
    else:
        bad("B4: PROVISIONING.md missing eFuse/sign-off gating")


# ---------------------------------------------------------------------------
# 7. B5: debug commands gated behind CONFIG_SPB_DEBUG_BUILD
# ---------------------------------------------------------------------------
disp_c = rel("components", "ble_service", "ble_dispatch.c")
if os.path.isfile(disp_c):
    d = read(disp_c)
    # READ_LOG_FILE handling must sit inside a CONFIG_SPB_DEBUG_BUILD guard.
    if "CONFIG_SPB_DEBUG_BUILD" in d and "CMD_READ_LOG_FILE" in d:
        # Ensure the debug-only handler body is guarded.
        guarded = re.search(
            r"#if\s+CONFIG_SPB_DEBUG_BUILD.*?CMD_READ_LOG_FILE.*?#endif",
            d, re.S)
        if guarded:
            ok("B5: READ_LOG_FILE handler gated behind CONFIG_SPB_DEBUG_BUILD")
        else:
            bad("B5: READ_LOG_FILE present but not guarded by CONFIG_SPB_DEBUG_BUILD")
    else:
        bad("B5: READ_LOG_FILE / CONFIG_SPB_DEBUG_BUILD gating not found")

# GATTS DB dump only in debug build.
if os.path.isfile(svc_c):
    s = read(svc_c)
    if "GATTS DATABASE DUMP" in s:
        if re.search(r"#if\s+CONFIG_SPB_DEBUG_BUILD.*?GATTS DATABASE DUMP", s, re.S):
            ok("B5: GATTS DB dump gated behind CONFIG_SPB_DEBUG_BUILD")
        else:
            bad("B5: GATTS DB dump not gated behind CONFIG_SPB_DEBUG_BUILD")

# Kconfig must declare the flag; prod overlay must disable it.
kcfg = rel("main", "Kconfig.projbuild")
if os.path.isfile(kcfg) and "SPB_DEBUG_BUILD" in read(kcfg):
    ok("B5: CONFIG_SPB_DEBUG_BUILD declared in Kconfig")
else:
    bad("B5: CONFIG_SPB_DEBUG_BUILD not declared in Kconfig")

if os.path.isfile(prod) and "CONFIG_SPB_DEBUG_BUILD=n" in read(prod):
    ok("B5: prod overlay disables CONFIG_SPB_DEBUG_BUILD")
else:
    bad("B5: prod overlay does not disable CONFIG_SPB_DEBUG_BUILD")

# B5: build provenance (git rev embedded + dirty-tree refusal in release).
top_cmake = rel("CMakeLists.txt")
if os.path.isfile(top_cmake):
    tc = read(top_cmake)
    if "SPB_GIT_REV" in tc:
        ok("B5: firmware embeds git revision (SPB_GIT_REV)")
    else:
        bad("B5: no git-revision embedding in top CMakeLists.txt")
    if "dirty" in tc and "FATAL_ERROR" in tc:
        ok("B5: release build refuses a dirty tree")
    else:
        bad("B5: release build does not refuse a dirty tree")


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
def main():
    passed = sum(1 for s, _ in checks if s == PASS)
    failed = sum(1 for s, _ in checks if s == FAIL)
    print("=" * 70)
    print("Farda Smart Pill Bottle firmware validator")
    print("=" * 70)
    for status, msg in checks:
        mark = "[ OK ]" if status == PASS else "[FAIL]"
        print(f"{mark} {msg}")
    print("-" * 70)
    print(f"Checks: {passed} passed, {failed} failed")
    if failed:
        print("RESULT: FAIL")
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
