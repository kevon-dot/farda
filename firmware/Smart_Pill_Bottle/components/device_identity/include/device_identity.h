/*
 * device_identity.h - Per-device secret + HMAC-SHA256 signing (B1).
 *
 * This is the heart of the B1 fix. The shipped firmware put the raw 32-byte
 * auth key in the cleartext network payload
 *   {"deviceId":"%s","authKey":"%s",...}
 * which leaks a bearer credential that also unlocks every privileged BLE
 * command. THIS REIMPLEMENTATION NEVER PUTS THE KEY IN ANY PAYLOAD.
 *
 * Instead every network event is SIGNED:
 *   signature = HMAC-SHA256( deviceId || "\n" || nonce || "\n" || ts || "\n" || body )
 * using the per-device secret key. We transmit the signature + nonce +
 * timestamp + deviceId in headers, never the key. The backend
 * (smart-vial-backend, issue A3) re-derives the same HMAC from its copy of the
 * per-device key.
 *
 * This ordering MATCHES the MERGED backend source of truth verbatim
 * (smart-vial-backend/utils/deviceAuth.js buildSignatureMessage() and
 * docs/DEVICE_AUTH.md): deviceId, nonce, timestamp, raw body joined by '\n'.
 * The nonce is a DECIMAL monotonic per-device counter (not random); the
 * timestamp is Unix epoch SECONDS. The frozen contract is in
 * docs/WIRE_FORMAT.md -- keep both sides in sync.
 *
 * SHA-256 / HMAC-SHA256 throughout. No SHA-1 in our auth path.
 */
#ifndef SPB_DEVICE_IDENTITY_H
#define SPB_DEVICE_IDENTITY_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "esp_err.h"

#define SPB_DEVICE_KEY_LEN     32   /* 256-bit per-device secret */
#define SPB_HMAC_LEN           32   /* HMAC-SHA256 output */
#define SPB_DEVICE_ID_LEN      13   /* "aabbccddeeff" + NUL (MAC hex) */
#define SPB_NONCE_DEC_LEN      24   /* decimal counter string + NUL */

/*
 * Initialise device identity. Loads the per-device secret from NVS (key
 * "devKey"). The secret is FACTORY-PROVISIONED (see docs/PROVISIONING.md) and
 * is NEVER derived from, equal to, or transmitted alongside the public MAC.
 *
 * If no secret is provisioned, returns ESP_ERR_NOT_FOUND and the device must
 * refuse to bind / report (fail closed) rather than inventing a guessable key.
 */
esp_err_t device_identity_init(void);

/* True once a valid per-device secret is loaded. */
bool device_identity_is_provisioned(void);

/*
 * Device ID = lowercase hex of the ESP32 base MAC (public, non-secret). Kept
 * for routing/telemetry identification only -- it is NOT a credential.
 * `out` must be >= SPB_DEVICE_ID_LEN.
 */
esp_err_t device_identity_get_id(char *out, size_t out_len);

/*
 * Atomically fetch the next MONOTONIC per-device nonce counter and persist the
 * advance in NVS (key "nonceCtr"), so it keeps increasing across reboots. The
 * backend rejects any event whose nonce is <= the last one it saw, so this
 * value must strictly increase per transmitted event. Writes the decimal
 * string form (matching x-nonce on the wire) into `out` (>= SPB_NONCE_DEC_LEN)
 * and returns the numeric value via `out_val` (may be NULL).
 */
esp_err_t device_identity_next_nonce(char *out, size_t out_len, uint64_t *out_val);

/*
 * Compute HMAC-SHA256 over the canonical signing input, in the EXACT order the
 * merged backend (smart-vial-backend/utils/deviceAuth.js) uses:
 *   device_id || '\n' || nonce_dec || '\n' || timestamp_dec || '\n' || body
 * - `device_id` is the lowercase-hex MAC string (== x-device-id == body field).
 * - `nonce_dec` is the decimal counter string (== x-nonce).
 * - `timestamp` is Unix epoch SECONDS; signed as its decimal string (== x-timestamp).
 * - `body` is the exact raw JSON body bytes transmitted.
 * Writes SPB_HMAC_LEN bytes to `out_mac`.
 */
esp_err_t device_identity_sign(const char *device_id,
                               const char *nonce_dec,
                               int64_t timestamp,
                               const uint8_t *body, size_t body_len,
                               uint8_t out_mac[SPB_HMAC_LEN]);

/*
 * Constant-time comparison of two MACs / keys. Returns true if equal. Used for
 * BLE per-command auth checks so we never short-circuit on the first byte.
 */
bool device_identity_ct_equal(const uint8_t *a, const uint8_t *b, size_t len);

/* Lowercase-hex helper (used for nonce + signature headers). out_len must be
 * >= 2*in_len + 1. */
void device_identity_hex(const uint8_t *in, size_t in_len, char *out, size_t out_len);

#endif /* SPB_DEVICE_IDENTITY_H */
