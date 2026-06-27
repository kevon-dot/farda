/*
 * ble_service.h - BLE GATT server + hardened command dispatcher (B2).
 *
 * Reconstructs the documented command table (opcodes 0x10-0xEF) but replaces
 * the original trust-on-first-use / plaintext / replayable model with the B2
 * fixes:
 *   - LE Secure Connections + bonding REQUIRED; privileged characteristics
 *     reject writes on an unencrypted/unauthenticated link ("connected" !=
 *     "trusted").
 *   - Every state-changing command carries a monotonic counter/nonce; replays
 *     (counter <= last seen) are rejected.
 *   - Per-command auth for UNLOCK / SET_API_TARGET / SET_WIFI_CRED /
 *     DELETE_LOG_FILE / admin, proven by an HMAC tag over the command, not a
 *     bare key echo.
 *   - Rate-limit / lockout after repeated failed privileged commands.
 *   - BIND replaces TOFU with proof-of-possession (factory secret / OOB).
 *   - ADD_ADMINKEY requires auth.
 *   - Debug commands (READ_LOG_FILE 0x33, GATTS DB dump) compiled out unless
 *     CONFIG_SPB_DEBUG_BUILD.
 */
#ifndef SPB_BLE_SERVICE_H
#define SPB_BLE_SERVICE_H

#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

/* Response the dispatcher fills and the GATT layer notifies back to the app.
 * Either an ACK string, an "E:<code>,<msg>" error, or a SYNC_DATA payload. */
typedef struct {
    uint8_t data[256];
    size_t  len;
} ble_response_t;

/* Command opcodes (audit + image). */
typedef enum {
    CMD_LOCK_CMD            = 0x10,
    CMD_SET_THRESHOLD       = 0x11,
    CMD_BIND_DEVICE         = 0x12,
    CMD_UNBIND_DEVICE       = 0x13,
    CMD_SET_WIFI_CRED       = 0x14,
    CMD_SET_COMM_PROT       = 0x15,
    CMD_SET_API_TARGET      = 0x16,
    CMD_START_CALIB         = 0x20,
    CMD_ADD_CALIB           = 0x21,
    CMD_FINISH_CALIB        = 0x22,
    CMD_REQUEST_SYNC        = 0x30,
    CMD_ACK_SYNC            = 0x31,
    CMD_SET_TIME            = 0x32,
    CMD_READ_LOG_FILE       = 0x33,  /* debug */
    CMD_DELETE_LOG_FILE     = 0x34,  /* debug-ish; privileged */
    CMD_LOGIN_DEVICE        = 0xA4,
    CMD_SET_PILL_INTERVAL   = 0xB4,
    CMD_SET_PILL_INTERVAL_START = 0xB5,
    CMD_SET_SAFETY_TIMEOUT  = 0xB6,
    CMD_ADD_ADMINKEY        = 0xEF,
} ble_opcode_t;

esp_err_t ble_service_init(void);
esp_err_t ble_service_start(void);

#endif /* SPB_BLE_SERVICE_H */
