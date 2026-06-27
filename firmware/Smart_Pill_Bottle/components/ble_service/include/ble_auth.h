/*
 * ble_auth.h - BLE command authentication, replay protection, lockout (B2).
 *
 * This module is the security heart of the BLE surface and is intentionally
 * transport-agnostic so it can be reasoned about independently of Bluedroid.
 *
 * Replacement for the original "[opcode][32-byte key][params]" scheme:
 *   - The raw key is NEVER carried in the clear. A privileged command is
 *     authenticated by an HMAC tag computed over
 *       opcode || counter || params
 *     with the per-device secret; we recompute and compare in constant time.
 *   - `counter` is a monotonic per-link command counter. Any command whose
 *     counter is <= the last accepted counter is rejected as a replay.
 *   - After N consecutive failed privileged commands the link is locked out
 *     for a cool-down window.
 */
#ifndef SPB_BLE_AUTH_H
#define SPB_BLE_AUTH_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "esp_err.h"

#define BLE_AUTH_TAG_LEN          32     /* HMAC-SHA256 */
#define BLE_AUTH_MAX_FAILS        5      /* lockout threshold */
#define BLE_AUTH_LOCKOUT_MS       60000  /* cool-down after lockout */

/* Per-connection auth state. */
typedef struct {
    bool     link_encrypted;   /* set true only after LE Secure Conn + bonding */
    bool     link_authenticated;
    uint32_t last_counter;     /* monotonic replay guard */
    uint32_t fail_count;
    int64_t  locked_until_us;
    bool     logged_in;        /* LOGIN_DEVICE succeeded this session */
} ble_link_ctx_t;

void ble_auth_reset_link(ble_link_ctx_t *ctx);

/* Mark the link encrypted+authenticated (called from the SMP/security
 * callback once LE Secure Connections + bonding complete). */
void ble_auth_set_link_secure(ble_link_ctx_t *ctx, bool secure);

/* True if the link currently meets the bar for privileged ops. */
bool ble_auth_link_is_trusted(const ble_link_ctx_t *ctx);

/* True if the link is in lockout right now. */
bool ble_auth_is_locked_out(const ble_link_ctx_t *ctx);

/*
 * Verify a privileged command. Checks (in order, fail closed):
 *   1. link trusted (encrypted + authenticated),
 *   2. not in lockout,
 *   3. counter strictly greater than last accepted (replay guard),
 *   4. HMAC tag matches HMAC(opcode||counter||params).
 * On success advances last_counter and clears fail_count. On failure bumps
 * fail_count and may enter lockout. Returns ESP_OK only when all pass.
 */
esp_err_t ble_auth_verify(ble_link_ctx_t *ctx,
                          uint8_t opcode,
                          uint32_t counter,
                          const uint8_t *params, size_t params_len,
                          const uint8_t tag[BLE_AUTH_TAG_LEN]);

/* True if an opcode is privileged (requires ble_auth_verify). */
bool ble_auth_opcode_is_privileged(uint8_t opcode);

#endif /* SPB_BLE_AUTH_H */
