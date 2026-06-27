# Farda Smart Vial — Firmware Audit

**Artifacts reviewed**
- `Smart_Pill_Bottle_4.bin` — the actual firmware image (1,452,336 bytes)
- `BLE_Communication_Protocol__Smart_Vial_2.pdf` — BLE GATT + command protocol
- `Feature_Overview_2.docx` — vendor implementation summary (Bytron Electronics / "AlirezaM")
- `Flashing_Instructions_2.docx` — build target, GPIO map, flashing procedure

**Method:** binary identification + ELF/IDF app-descriptor parse + full string/section analysis of the image, cross-checked against the protocol PDF and the two vendor docs. Note: this `.bin` is the **application partition image only** (no bootloader / partition table / NVS in the file), so some on-device state (partition layout, secure-boot/flash-encryption *enablement*, stored keys) cannot be confirmed from the image alone — those are called out explicitly below.

---

## 0. What this firmware is

A **third-party-developed (Bytron Electronics) ESP32 firmware for a "Smart Pill Bottle"** — a battery-powered, BLE-connected medication vial with a solenoid lock and a load-cell scale that weighs pills to detect doses, logs timestamped adherence/tamper events to on-board flash, and syncs them to the phone app over BLE (and optionally pushes them directly to a server over Wi-Fi via HTTP or MQTT).

**Confirmed build identity (from the IDF app descriptor):**
- Framework: **ESP-IDF v5.4.1**, Xtensa toolchain
- Project name: **`Smart_Pill_Bottle`**
- Version: **`dc26b1e-dirty`** (git hash + **`-dirty`** = built from an uncommitted working tree — not a clean tagged release)
- Compiled: **Jan 22 2026 12:36:45**
- Entry: `0x400815A0`; image header `e9 06 02 20` = 6 segments, **DIO** flash mode, **4 MB / 40 MHz** — matches the flashing doc (ESP32-WROOM-32D rev v3.1).

**Custom components in the image** (vendor-written, vs. stock IDF): `MB_WiFi/wifi_manager.c`, `NVS/NVS.c`, `MAX17043/MAX17043.c` (battery fuel gauge). The load-cell driver is bit-banged on GPIO (no HX711 library string), and the BLE/MQTT/HTTP/SPIFFS stacks are stock IDF.

---

## 1. Hardware & GPIO map (from flashing doc, corroborated by image)

| Function | Pin | Notes |
|---|---|---|
| `LOCK_PIN` (solenoid) | GPIO5 | Safe/inactive at boot; does not actuate during boot |
| `SDA_PIN` | GPIO21 | I²C — battery fuel gauge (MAX17043) |
| `SCK_PIN` | GPIO22 | I²C clock |
| `BAT_ALRT` | GPIO23 | MAX17043 low-battery alert interrupt |
| `LC_DOUT_PIN` | GPIO19 | Load cell data (HX711-style 24-bit serial) |
| `LC_SCK_PIN` | GPIO18 | Load cell clock |
| `EMERGENCY_UNLOCK_PIN` | GPIO4 | Recessed push-button, **5-second hold** to trigger |

- **Battery monitoring:** Maxim **MAX17043** Li-ion fuel gauge over I²C (state-of-charge + voltage), with a hardware alert line. Drives `LOW_BATTERY_5` / `LOW_BATTERY_2` events and a "Battery: Low Voltage (<5)" log.
- **Dose sensing:** a **load cell** read as a 24-bit serial ADC (HX711 topology) on GPIO18/19. Pills are weighed; weight deltas → pill-count changes. Vendor doc explicitly notes two analog caveats they could not fully solve in software: **HX711 supply-voltage sensitivity** and **mechanical creep** (reading drifts upward over time under load).
- **Lock:** a **solenoid** on GPIO5. Watchdog: a **5-second Task Watchdog (TWDT)** is compiled in.

---

## 2. What data the firmware collects, computes, and stores

### 2.1 Event types logged (the adherence/tamper dataset)
From the image and feature doc, each event is `{N|W|T}` classed:

| Event | Class | Meaning |
|---|---|---|
| `PILL_CHANGE` | Normal | Weight change consistent with a dose taken |
| `MANY_PILLS_CHANGE` | **Tamper** | Too many pills removed at once |
| `OUTSIDE_WINDOW_CHANGE` | **Tamper** | Pill removed outside the allowed dosing window |
| `BLE_LOCK_CMD` / `BLE_UNLOCK_CMD` | Normal | Lock/unlock issued over BLE |
| `EMERGENCY_UNLOCK` | Warning | Physical emergency button (5 s hold) |
| `SAFETY_TIMEOUT` | Warning | Auto safety timeout fired |
| `VIAL_RESTARTED` | Warning | A power-on log; gap vs. previous log infers an unlogged shutdown |
| `LOW_BATTERY_5`, `LOW_BATTERY_2` | Warning | SoC crossed 5% / 2% |

### 2.2 Computed/derived values
- **Pill count** and **count change** (`chng`/`cnt`) from load-cell weight deltas (calibrated to per-pill weight).
- **Timestamps** from an RTC set via BLE `SET_TIME (0x32)` (Unix epoch, little-endian). All logs are epoch-stamped.
- **Device ID = the ESP32 base MAC address** (vendor doc + `BT_MAC`/`EFUSE MAC` handling). This is the identity used in payloads — i.e. the device identity is a non-secret, guessable/forgeable MAC.

### 2.3 Where it's stored
- **SPIFFS** flash filesystem: log cached as **`/spiffs/log.bin`** (and a **`/spiffs/log.csv`** variant). Logs persist across power loss and are deleted only after a successful sync ACK.
- **NVS (non-volatile storage)** holds configuration + secrets: **Wi-Fi SSID/password**, the **32-byte auth key**, the **admin key**, **load-cell calibration** (with a MAC integrity check — "calibration data MAC check failed"), **API target**, **comm protocol**, **MQTT broker**, **pill interval**, **safety timeout**, **refill threshold**.

### 2.4 The JSON the firmware emits (two distinct schemas)
- **BLE sync (per protocol doc):**
  `[{"ts":1234567890,"type":"Normal","evnt":"PILL_CHANGE","chng":1,"cnt":19}, {"ts":...,"type":"Tamper","evnt":"OUTSIDE_WINDOW_CHANGE"}]`
  (`chng`/`cnt` present only on Normal/Tamper). A compact internal form `{"id":%d,"ts":%ld,"c":%d,"new":%d}` also exists in the image.
- **Direct network push (found verbatim in the image):**
  `{"deviceId":"%s","authKey":"%s","eventType":"pill_change","timestamp":%ld,"currentCount":%d,"countChange":%d}`
  → **the 32-byte auth key is serialized in cleartext into the event body** (see Finding F1).

---

## 3. BLE protocol & command surface (from PDF, confirmed in image)

- **Advertised name:** `Medical Vial App`.
- **GATT layout — two services:**
  - Service A: 16-bit UUID `0x00FF`, characteristic `0xFF01`, descriptor `0x3333`; 128-bit base `5f9b349b-0080-8000-0010-0000FF000000`.
  - Service B: `0x00EE` / `0xEE01` / `0x2222`; base `…0000EE000000`.
  - (These exactly match the substring filter `00FF`/`00EE` the Flutter app scans for — confirming the app↔firmware pairing.)
- **General payload structure:** `[opcode(1)][AuthKey(32)][optional params]`. Responses echo the opcode + data, or `E:<code>,<message>` on error; success = `[opcode] ACK`. The image contains a `GATTS DATABASE DUMP` debug routine.

**Full command set:**

| Opcode | Name | Auth? | Notes |
|---|---|---|---|
| `0x10` | LOCK_CMD | key | Lock/unlock |
| `0x11` | SET_THRESHOLD | key | Refill threshold |
| `0x12` | BIND_DEVICE | — | **Establishes the 32-byte auth key (first pairing)** |
| `0x13` | UNBIND_DEVICE | key | Unpair |
| `0x14` | SET_WIFI_CRED | key | `["SSID","PASSWORD"]` → stored in NVS |
| `0x15` | SET_COMM_PROT | key | Select HTTP vs MQTT |
| `0x16` | SET_API_TARGET | key | Set server/MQTT target (`scheme://host:port/path`) |
| `0x20`/`0x21`/`0x22` | START/ADD/FINISH_CALIB | key | Single-point calibration by pill weight |
| `0x30` | REQUEST_SYNC | key | Device emits `SYNC_DATA` marker + JSON |
| `0x31` | ACK_SYNC | key | Device then **deletes** the log file |
| `0x32` | SET_TIME | key | RTC set (4-byte LE epoch) |
| `0x33` | READ_LOG_FILE | key | Debug: dump cached log |
| `0x34` | DELETE_LOG_FILE | key | Debug: delete log |
| `0xA4` | LOGIN_DEVICE | key | Re-auth on reconnect |
| `0xB4` | SET_PILL_INTERVAL | key | Dose interval (hours) |
| `0xB5` | SET_PILL_INTERVAL_START | key | Interval start hour |
| `0xB6` | SET_SAFETY_TIMEOUT | key | Safety timeout |
| `0xEF` | ADD_ADMINKEY | **none** | **Admin override key; settable once** |

**Auth model (TOFU/bind-on-first-use):** `BIND_DEVICE` sets the shared 32-byte key; thereafter every privileged opcode must carry it. The image's response strings — `Auth Key Not Included!`, `Auth Key Not Matched!`, `Key Not Matched!`, `Device Not Bound Yet`, `No additional data after auth key` — confirm a presence+equality check. `ADD_ADMINKEY (0xEF)` requires **no** auth and is **write-once** (`AdminKey Can't Be Changed`, `key can only be set once`).

---

## 4. Behavior & state machine (safety logic)

- **Solenoid safety interlocks (vendor doc + image):** lock GPIO is held inactive through boot; **cannot reopen if <1 minute since last opening**; **auto re-locks 5 s after an unlock**; `SAFETY_TIMEOUT` auto-event.
- **Emergency unlock:** physical button (GPIO4), **5-second hold** required; logged as a Warning.
- **Watchdog:** 5-second TWDT for hang recovery; a `VIAL_RESTARTED`/power-on log lets the backend infer unlogged shutdowns by timestamp gap.
- **Sync lifecycle:** App `0x30` → device streams `SYNC_DATA` + JSON → App `0x31` ACK → device deletes `/spiffs/log.bin`. (Risk: an attacker who can issue `0x31` after sniffing the key, or a failed-write app, can cause log deletion / loss — see F4.)
- **Wi-Fi:** STA mode, WPA2/WPA3-SAE with PMF, credentials persisted to NVS, auto-reconnect policy. DHCP-server strings suggest a SoftAP/provisioning path may also exist.
- **Telemetry transport:** Wi-Fi client supports **HTTP POST** and **MQTT publish/subscribe** (MQTT v5 capable), target + scheme set at runtime via `0x16`/`0x15`. URL built as `%s://%s:%d%s` (scheme user-controlled).
- **OTA:** IDF OTA machinery (`esp_ota_ops`, `esp_https_ota`, rollback, `ESP_ERR_OTA_*`) is **compiled in** — the device is OTA-capable — but whether an OTA flow is actually wired/triggered can't be confirmed from this image.

---

## 5. Security findings (firmware-specific)

### CRITICAL / HIGH

- **F1 — Auth key transmitted in cleartext in the network payload.** The image contains `{"deviceId":"%s","authKey":"%s",...}`. The device's secret 32-byte auth key is embedded in the body of every event push. Combined with F2, anyone on-path (or the server logs) sees the key, which then unlocks **every** privileged BLE command (lock/unlock, set Wi-Fi, set API target, delete logs). Treat the auth key as a bearer credential that is being broadcast.

- **F2 — Transport security is optional and likely off by default.** The firmware lets the user set an arbitrary `scheme://host:port` target (`0x16`) and select the protocol (`0x15`), and the image carries the warnings `SSL related configs set, but the URI scheme specifies a non-SSL scheme` and `No server verification option set in esp_tls_cfg_t structure`. There is **no embedded CA bundle** — only a single PEM marker from the mbedTLS parser, and **none** of the usual root-CA names (DigiCert/GlobalSign/ISRG/Amazon) are present. So even when TLS is used, server-certificate verification is almost certainly **not** anchored to a CA store → MITM-able. Default `http://`/`mqtt://` cleartext is supported and, given F1, evidently used.

- **F3 — Identity = MAC; pairing = trust-on-first-use; admin key is first-writer-wins.** Device ID is the public ESP32 MAC (forgeable/guessable). `BIND_DEVICE` has no out-of-band proof — whoever pairs first sets the key. `ADD_ADMINKEY (0xEF)` takes **no auth** and is write-once, so the first actor to reach an un-provisioned vial **permanently** claims the admin override. On a shelf/in-transit device this is a real takeover vector.

- **F4 — Plaintext, replayable BLE command channel with destructive ops.** Commands are sent in the clear over GATT writes (no evidence of bonding/encryption requirement; SMP is in the stack but the app does unauthenticated writes). A passive sniffer captures the 32-byte key once and can then **replay/forge** any command, including `UNBIND`, `SET_WIFI_CRED` (exfiltrate creds / redirect), `SET_API_TARGET` (redirect all telemetry to an attacker), `DELETE_LOG_FILE`, and **physical `LOCK/UNLOCK`** of a medication container. No nonce/sequence number is evident in the protocol.

### MEDIUM

- **F5 — Wi-Fi credentials and keys stored in NVS without confirmed flash encryption.** SSID/password, auth key, and admin key live in NVS. This `.bin` can't prove whether **flash encryption** is enabled on the shipped product; if it isn't (common on EVT/DVT builds, and this is described as an EVT/DVT build), anyone with physical flash-read access recovers Wi-Fi creds + the auth key. `spi_flash_encrypt_ll` code is linked (stock), which is **not** evidence that encryption is enabled.
- **F6 — `-dirty` build provenance.** Shipped image built from an uncommitted tree (`dc26b1e-dirty`) → not reproducible, not traceable to a commit; weak for a regulated medical device.
- **F7 — Debug log dump commands shipped in production** (`READ_LOG_FILE 0x33`, plus a `GATTS DATABASE DUMP` routine). Useful to an attacker, and the vendor labels them debug-only yet they're in the production image.
- **F8 — SHA-1 in use.** The image computes a SHA-1 sum (`Error in calculating sha1 sum`) somewhere in the custom path (likely key/ID hashing). SHA-1 is deprecated; depending on use it's weak. Key comparison method (constant-time?) can't be confirmed from strings and should be checked in source.

### Backend-integration mismatch (cross-cutting)
- **F9 — The firmware's direct-push auth doesn't match the vial backend's device auth.** Firmware embeds `deviceId`+`authKey` **in the JSON body**; the `smart-vial-backend` (`middleware/authDevice.js`) authenticates devices via a **single shared `x-api-key` header** (`DEVICE_API_KEY`), not a per-device body key. So the firmware's Wi-Fi push path and the documented backend ingestion path are **not aligned** — either the real path is BLE → phone app → backend (and the Wi-Fi push targets a different/!legacy endpoint), or device→backend auth is effectively unverified. This should be reconciled; today there are two inconsistent device-auth schemes.

---

## 6. Quality / engineering observations

- **Solid embedded fundamentals:** watchdog, safe-state GPIO at boot, persistent logging with sync-then-delete, battery fuel-gauge integration, calibration tied to device MAC (anti-transfer), structured event taxonomy with tamper detection. This is a competent firmware effort.
- **Honest analog caveats** documented (HX711 voltage sensitivity, load-cell creep) — these directly affect **dose-detection accuracy**, i.e. false `PILL_CHANGE`/`MANY_PILLS_CHANGE` under voltage sag or creep drift. For a medical-adherence claim, sensing reliability is a clinical-risk item, not just a nuisance.
- **Single-point calibration** (per-pill weight) is a deliberate simplification; reasonable for cost but sensitive to pill-weight variance across medications and to the creep/voltage issues above.
- **Provisioning UX vs. security tension:** the whole config surface (Wi-Fi, server target, keys, calibration) is exposed over an unauthenticated-until-bound, unencrypted BLE link — convenient but the root of F3/F4.

---

## 7. Recommendations (firmware)

1. **Stop sending `authKey` in payload bodies (F1).** Authenticate device→server with a per-device credential in a header/TLS client cert, never in the JSON body; rotate any key that has been transmitted this way.
2. **Enforce verified TLS (F2):** require `https://`/`mqtts://`, embed a CA bundle or pin the server cert, and reject non-TLS schemes in production builds. Remove the ability to set cleartext targets on shipped units.
3. **Harden pairing (F3/F4):** require BLE bonding + link encryption (LE Secure Connections) before accepting privileged writes; add an out-of-band bind proof (button-press/QR secret) instead of pure TOFU; gate `ADD_ADMINKEY` behind physical confirmation; add a monotonic nonce/sequence to defeat replay.
4. **Enable Secure Boot v2 + Flash Encryption** for production (F5), and confirm NVS-stored secrets are encrypted; verify on a real unit (not derivable from this image).
5. **Remove debug commands** (`0x33` log dump, GATTS DB dump) from production builds (F7); ship **clean, tagged** (non-`-dirty`) reproducible builds (F6).
6. **Reconcile device→backend auth (F9)** with the `smart-vial-backend` ingestion contract; pick one scheme (per-device key/cert) end-to-end.
7. Replace SHA-1 (F8) where it touches keys/identity; ensure constant-time key comparison.
8. Treat **dose-sensing accuracy** (creep/voltage) as a verification item with documented error bounds, given the clinical use.

---

## 8. Bottom line

The firmware is the **most mature, competently-engineered piece of the whole Farda system** — real safety interlocks, persistent tamper-aware logging, battery gauging, and a complete BLE command protocol that matches the phone app. But its **security model is built for convenience, not for a regulated medical device**: trust-on-first-use pairing over an unencrypted, replayable BLE link; a write-once admin key with no auth; the secret device key broadcast in cleartext network payloads; and optional/unverified transport with no embedded CA trust. The control surface it exposes is high-consequence — it can **physically lock/unlock a medication container** and redirect all telemetry — so these are not theoretical issues. Functionally strong; security and provenance (`-dirty`, debug commands, no confirmed secure boot) need hardening before it should ship on real patients' medication.
