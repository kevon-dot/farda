# Provisioning & manufacturing security (eFuse / Secure Boot / Flash Encryption)

> **UNVERIFIED REFERENCE.** This describes the intended factory provisioning
> flow for the reconstructed firmware. **Several steps below BURN ONE-WAY
> eFUSES and are IRREVERSIBLE.** Nothing here should be run automatically, in
> CI, or on a developer bench device without the explicit, recorded sign-off
> described in §0. The firmware build never enables these by default.

## 0. Sign-off gate (read first)

The following are **one-way, irreversible** on ESP32 and must be performed only
in manufacturing, only on production units, and only after a named maintainer
records sign-off (ticket + initials + date):

- Burning **Secure Boot v2** key digest eFuses.
- Burning **Flash Encryption** key eFuses (release mode).
- Disabling **ROM download mode** / UART download.
- Setting the **secure version** (anti-rollback) eFuse counter.

> If you are reading this on a dev box: **stop.** Use the dev defaults
> (`sdkconfig.defaults`), which enable none of the above. There is no
> "just try it" — burning these eFuses bricks the ability to reflash plaintext
> and cannot be undone.

## 1. Per-device secret injection (B1/B2)

Each unit gets a unique random **32-byte secret** stored in encrypted NVS under
key `devKey` (namespace `spb_cfg`). The firmware loads it via
`device_identity_init()` and **fails closed** (refuses to bind or report) if it
is absent.

Factory steps:
1. Generate a CSPRNG 32-byte secret on the provisioning host (HSM-backed).
2. Write it to the device NVS partition before flash encryption is enabled, or
   via a secure provisioning channel after.
3. Store the same secret server-side keyed by the device's `deviceId`
   (lowercase-hex base MAC) so the backend (A3) can verify HMACs
   (`docs/WIRE_FORMAT.md`).
4. Print/encode the secret (or a derived bind token) into a **QR / OOB sticker**
   shipped with the unit so the legitimate owner — and only they — can complete
   proof-of-possession `BIND_DEVICE`. This replaces trust-on-first-use (F3).

> **Manufacturing decision (flagged, not decided here):** whether the secret
> lives in encrypted NVS vs. a dedicated eFuse key block (e.g. HMAC-via-eFuse
> using the ESP32 Digital Signature / HMAC peripheral). eFuse storage is
> stronger (not flash-readable) but consumes a key block and is irreversible.
> Decide with the security owner; the firmware interface
> (`device_identity_*`) is agnostic to the backing store.

## 2. CA bundle / cert pinning (B3)

- Provision the real Farda / smart-vial backend certificate chain so
  `telemetry.c` verifies the server cert. Either:
  - embed a pinned PEM (`s_backend_ca_pem`) via an `EMBED_TXTFILES` asset, or
  - rely on the IDF cert bundle restricted to the backend's issuer.
- Set `BOARD_ALLOWED_API_DOMAIN_SUFFIXES` in `board_config.h` to the real
  domain(s). `SET_API_TARGET` rejects anything else.

## 3. Secure Boot v2 (B4) — **burns eFuses**

Enabled by `sdkconfig.defaults.prod` (`CONFIG_SECURE_BOOT`,
`CONFIG_SECURE_BOOT_V2_ENABLED`). Procedure (manufacturing only):

```sh
# 1. Generate an RSA-3072 signing key ONCE, store in an HSM. NEVER commit it.
espsecure.py generate_signing_key --version 2 secure_boot_signing_key.pem

# 2. Build signed binaries with the prod overlay.
idf.py -D SDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.prod" build

# 3. First boot burns the public-key digest eFuse and enables secure boot.
#    IRREVERSIBLE.
```

## 4. Flash Encryption (B4) — **burns eFuses**

Enabled by `sdkconfig.defaults.prod`
(`CONFIG_SECURE_FLASH_ENC_ENABLED`, `..._MODE_RELEASE`). Release mode disables
the UART path that could read plaintext, and `CONFIG_SECURE_DISABLE_ROM_DL_MODE`
closes ROM download mode. **IRREVERSIBLE.** Encrypts app + NVS secrets at rest,
mitigating physical flash-read recovery of the Wi-Fi creds and per-device
secret (F5).

## 5. Signed OTA + anti-rollback (B4)

- `CONFIG_BOOTLOADER_APP_ANTI_ROLLBACK` + `CONFIG_BOOTLOADER_APP_SECURE_VERSION`
  reject downgrades. Bump the secure version on each security release.
- `ota_update_perform()` refuses non-HTTPS URLs and relies on Secure Boot v2 to
  reject unsigned images; `ota_update_mark_valid()` confirms a good boot so
  anti-rollback keeps the new image.

## 6. Partition table

`partitions.csv` must be re-balanced to fit 4 MB with the secure bootloader (it
is larger than the non-secure one). Confirm headroom before burning anything.

## 7. Build provenance (B5)

Produce release images from a **clean, tagged** tree:

```sh
SPB_RELEASE=1 idf.py -D SDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.prod" build
```

`SPB_RELEASE=1` makes the build **fail on a dirty tree** (no more `-dirty`
shipped images — F6). The git revision is embedded and reported via telemetry.
