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
 *   signature = HMAC-SHA256( canonical_body || "\n" || nonce || "\n" || ts )
 * using the per-device secret key. We transmit the signature + nonce +
 * timestamp in headers, never the key. The backend (smart-vial-backend, issue
 * A3) re-derives the same HMAC from its copy of the per-device key. The exact
 * wire contract is frozen in docs/WIRE_FORMAT.md.
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
#define SPB_NONCE_LEN          16   /* random nonce per request */
#define SPB_DEVICE_ID_LEN      13   /* "aabbccddeeff" + NUL (MAC hex) */

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
 * Fill `out` (>= SPB_NONCE_LEN) with cryptographically-random bytes from the
 * hardware RNG. Used as the per-request nonce.
 */
esp_err_t device_identity_random_nonce(uint8_t *out, size_t len);

/*
 * Compute HMAC-SHA256 over the canonical signing input:
 *   body_bytes || '\n' || nonce_hex || '\n' || timestamp_decimal
 * `nonce` is the raw nonce bytes; it is hex-encoded internally to match the
 * wire format. `timestamp` is the Unix epoch seconds carried in x-timestamp.
 * Writes SPB_HMAC_LEN bytes to `out_mac`.
 */
esp_err_t device_identity_sign(const uint8_t *body, size_t body_len,
                               const uint8_t *nonce, size_t nonce_len,
                               int64_t timestamp,
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
