# Farda Smart Pill Bottle — firmware (ESP-IDF v5.4.1)

> # ⚠️ UNVERIFIED REFERENCE REIMPLEMENTATION ⚠️
>
> This is a **fresh, security-hardened reconstruction** of the Smart Pill Bottle
> firmware, rebuilt from the compiled image `firmware/Smart_Pill_Bottle.bin`,
> the firmware docs, and `reviews/FARDA_FIRMWARE_AUDIT.md`.
>
> **It is NOT binary-equivalent to the shipped firmware. It has NOT been
> compiled against a real ESP-IDF toolchain here, NOT run, and NOT validated on
> hardware.** Every hardware constant (GPIO polarity, HX711 calibration, dose
> thresholds, timers, BLE attribute table) is a **placeholder** that WILL be
> wrong on a real unit. **Do NOT flash this to any real device** without full
> hardware bring-up and bench validation. For a medical-adherence product,
> dose-sensing accuracy and lock behaviour are clinical-risk items.

## What this is

A faithful, **interface-level** reconstruction of the documented behaviour with
the audit's **B1–B5 security fixes baked in from the start** — not a
line-for-line clone. Hardware-tuning internals are stubbed with loud
`TODO(hardware)` markers.

## How it maps to the original

| Original (from the image / docs) | Here |
|---|---|
| `MB_WiFi/wifi_manager.c` | `components/wifi_manager` |
| `NVS/NVS.c` | `components/nvs_store` |
| `MAX17043/MAX17043.c` battery fuel gauge | `components/battery_monitoring` |
| `Calibration` single-point calib | `components/calibration` |
| bit-banged HX711 load cell | `components/loadcell_hx711` |
| solenoid lock + rate limit + emergency button | `components/lock_control` |
| Bluedroid GATT + command dispatcher (0x10–0xEF) | `components/ble_service` (`ble_service.c` + `ble_dispatch.c` + `ble_auth.c`) |
| HTTP/MQTT push + SPIFFS log + sync | `components/telemetry` (`telemetry.c` + `event_log.c`) |
| `esp_ota_ops` / `esp_https_ota` | `components/ota_update` |
| device identity = MAC + 32-byte key | `components/device_identity` (per-device secret + HMAC) |
| GPIO map, calibration, BLE handles, thresholds | `components/board_config/include/board_config.h` |

## Security (B1–B5)

Fully mapped in [`docs/SECURITY.md`](docs/SECURITY.md). Headlines:

- **B1** — the raw key is **never** in any payload; events are signed with
  HMAC-SHA256 (`docs/WIRE_FORMAT.md`).
- **B2** — BLE requires LE Secure Connections + bonding, per-command HMAC auth,
  monotonic-counter replay rejection, lockout, proof-of-possession bind;
  `ADD_ADMINKEY` now needs auth.
- **B3** — `https`/`mqtts` only, server cert verified, `SET_API_TARGET`
  domain-restricted.
- **B4** — Secure Boot v2 + flash encryption + signed/anti-rollback OTA in
  `sdkconfig.defaults.prod`, gated behind sign-off (`docs/PROVISIONING.md`).
- **B5** — debug commands behind `CONFIG_SPB_DEBUG_BUILD`, git revision
  embedded, release build fails on a dirty tree.

## Hardware constants you MUST fill before flashing

All live in `components/board_config/include/board_config.h`. The pin map (from
the flashing doc) is higher-confidence; the rest are placeholders:

- **Solenoid polarity** (`BOARD_LOCK_ACTIVE_LEVEL`) and **emergency button
  level** (`BOARD_EMERGENCY_PRESSED_LEVEL`) — wrong = inverted lock.
- **HX711 scale/offset/per-pill weight** (`BOARD_HX711_DEFAULT_*`,
  `BOARD_MIN_PILL_WEIGHT_G`) — must be measured; affects dose detection.
- **Load-cell averaging / creep guard** (`BOARD_LC_*`) — tune against the
  documented HX711 voltage sensitivity + mechanical creep.
- **Dose-window / interval ranges**, **MAX17043 scaling**, **BLE attribute
  handle layout**, **allowed backend domain(s)**, **CA bundle / signing keys**.

## Build (requires ESP-IDF v5.4.1 toolchain — not installed here)

```sh
# Development build (debug surface on, no eFuse burning):
idf.py set-target esp32
idf.py build

# Production build (clean tree required, applies hardening overlay):
SPB_RELEASE=1 idf.py -D SDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.prod" build
```

> Production hardening burns one-way eFuses — read `docs/PROVISIONING.md` first.

## Validate (no toolchain needed)

```sh
python3 tools/validate_firmware.py
```

Structure + security lint; the CI `firmware` job runs exactly this and must stay
green.

## Docs

- [`docs/SECURITY.md`](docs/SECURITY.md) — B1–B5 mapping
- [`docs/WIRE_FORMAT.md`](docs/WIRE_FORMAT.md) — HMAC contract for the backend (A3)
- [`docs/PROVISIONING.md`](docs/PROVISIONING.md) — factory keys, eFuse, secure boot (gated)
- [`docs/BLE_PROTOCOL.md`](docs/BLE_PROTOCOL.md) — reconstructed command table
