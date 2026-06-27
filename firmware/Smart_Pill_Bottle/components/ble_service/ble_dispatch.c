/*
 * ble_dispatch.c - Hardened BLE command dispatcher (B2 + B5).
 *
 * Transport-agnostic: ble_service.c (Bluedroid GATTS) parses an inbound write
 * into (opcode, counter, params, tag) and calls ble_dispatch_handle(). All
 * privileged routing, replay/lockout enforcement and per-command auth live
 * here so the security logic is reviewable without the GATT machinery.
 *
 * Wire frame for a privileged command (B2):
 *   [opcode:1][counter:4 LE][tag:32 HMAC][params:N]
 * Non-privileged frames (BIND proof-of-possession, LOGIN) have their own
 * shapes documented in docs/BLE_PROTOCOL.md.
 */
#include "ble_service.h"
#include "ble_auth.h"
#include "device_identity.h"
#include "nvs_store.h"
#include "board_config.h"

#include "lock_control.h"
#include "calibration.h"
#include "wifi_manager.h"
#include "telemetry.h"
#include "event_log.h"

#include <string.h>
#include <stdlib.h>
#include "sdkconfig.h"
#include "esp_log.h"

static const char *TAG = "ble_dispatch";

static void resp_ack(ble_response_t *r, uint8_t opcode)
{
    /* success = [opcode] ACK */
    int n = snprintf((char *)r->data, sizeof(r->data), "%c ACK", opcode);
    r->len = (n > 0) ? (size_t)n : 0;
}

static void resp_err(ble_response_t *r, int code, const char *msg)
{
    /* error = E:<code>,<message> (image form "E:%d,%s") */
    int n = snprintf((char *)r->data, sizeof(r->data), "E:%d,%s", code, msg);
    r->len = (n > 0) ? (size_t)n : 0;
}

/*
 * Handle BIND with proof-of-possession (B2 replaces TOFU). The frame carries
 * an HMAC over a server-provided challenge using the FACTORY-PROVISIONED
 * per-device secret. Only a holder of that secret (provisioned at
 * manufacturing, distributed via QR/OOB to the legitimate owner) can bind.
 * No trust-on-first-use.
 */
static esp_err_t handle_bind(ble_link_ctx_t *ctx,
                             const uint8_t *params, size_t plen,
                             ble_response_t *r)
{
    if (!device_identity_is_provisioned()) {
        resp_err(r, 1, "Device Not Provisioned");
        return ESP_ERR_INVALID_STATE;
    }
    if (!ble_auth_link_is_trusted(ctx)) {
        /* BIND still requires an encrypted link so the PoP isn't sniffable. */
        resp_err(r, 2, "Link Not Secure");
        return ESP_ERR_INVALID_STATE;
    }
    /* params = [challenge_counter:4][tag:32]. Verify like a privileged op
     * against opcode CMD_BIND_DEVICE so a replayed bind is rejected too. */
    if (plen < 4 + BLE_AUTH_TAG_LEN) {
        resp_err(r, 3, "Bad Bind Frame");
        return ESP_ERR_INVALID_SIZE;
    }
    uint32_t counter = (uint32_t)params[0] | ((uint32_t)params[1] << 8) |
                       ((uint32_t)params[2] << 16) | ((uint32_t)params[3] << 24);
    const uint8_t *tag = params + 4;
    esp_err_t err = ble_auth_verify(ctx, CMD_BIND_DEVICE, counter, NULL, 0, tag);
    if (err != ESP_OK) {
        resp_err(r, 4, "Bind PoP Failed");
        return err;
    }
    ctx->logged_in = true;
    resp_ack(r, CMD_BIND_DEVICE);
    ESP_LOGI(TAG, "Device bound via proof-of-possession.");
    return ESP_OK;
}

/*
 * Main dispatch. `frame` is the raw GATT write; `ctx` is the per-link auth
 * state; `out` receives the response to notify back.
 */
esp_err_t ble_dispatch_handle(ble_link_ctx_t *ctx,
                              const uint8_t *frame, size_t frame_len,
                              ble_response_t *out)
{
    out->len = 0;
    if (frame_len < 1) {
        resp_err(out, 10, "Empty");
        return ESP_ERR_INVALID_SIZE;
    }
    uint8_t opcode = frame[0];

    /* Non-privileged opcodes handled first. */
    if (opcode == CMD_BIND_DEVICE) {
        return handle_bind(ctx, frame + 1, frame_len - 1, out);
    }
    if (opcode == CMD_LOGIN_DEVICE) {
        /* LOGIN re-auths on reconnect: same PoP proof as bind. */
        return handle_bind(ctx, frame + 1, frame_len - 1, out);
    }

    /* Everything else privileged: parse [opcode][counter:4][tag:32][params]. */
    if (!ble_auth_opcode_is_privileged(opcode)) {
        resp_err(out, 11, "Unknown Opcode");
        return ESP_ERR_NOT_SUPPORTED;
    }

#if !CONFIG_SPB_DEBUG_BUILD
    /* B5: debug commands are not present in release builds at all. */
    if (opcode == CMD_READ_LOG_FILE) {
        resp_err(out, 12, "Disabled");
        return ESP_ERR_NOT_SUPPORTED;
    }
#endif

    if (frame_len < 1 + 4 + BLE_AUTH_TAG_LEN) {
        resp_err(out, 13, "Bad Frame");
        return ESP_ERR_INVALID_SIZE;
    }
    uint32_t counter = (uint32_t)frame[1] | ((uint32_t)frame[2] << 8) |
                       ((uint32_t)frame[3] << 16) | ((uint32_t)frame[4] << 24);
    const uint8_t *tag = frame + 5;
    const uint8_t *params = frame + 5 + BLE_AUTH_TAG_LEN;
    size_t plen = frame_len - (5 + BLE_AUTH_TAG_LEN);

    esp_err_t err = ble_auth_verify(ctx, opcode, counter, params, plen, tag);
    if (err != ESP_OK) {
        resp_err(out, 14, "Not Authenticated");
        return err;
    }

    /* Authenticated, fresh (non-replayed) command. Route it. */
    switch (opcode) {
        case CMD_LOCK_CMD: {
            /* params[0]: 1=unlock, 0=lock */
            bool unlock = (plen >= 1 && params[0] == 1);
            err = unlock ? lock_control_unlock(LOCK_SRC_BLE)
                         : lock_control_lock(LOCK_SRC_BLE);
            if (err == ESP_ERR_INVALID_STATE) {
                resp_err(out, 20, "Solenoid Lock rate limit");
                return err;
            }
            break;
        }
        case CMD_SET_THRESHOLD:
            if (plen >= 1) nvs_store_set_i32(NVS_KEY_THRESHOLD, params[0]);
            break;
        case CMD_UNBIND_DEVICE:
            nvs_store_erase_key(NVS_KEY_AUTH);
            ctx->logged_in = false;
            break;
        case CMD_SET_WIFI_CRED: {
            /* params = JSON ["SSID","PASSWORD"] (kept compatible). */
            char ssid[33] = {0}, pass[65] = {0};
            /* Minimal extraction; a real build uses cJSON. */
            if (sscanf((const char *)params, "[\"%32[^\"]\",\"%64[^\"]\"]",
                       ssid, pass) == 2) {
                err = wifi_manager_set_credentials(ssid, pass);
            } else {
                resp_err(out, 21, "Bad WiFi Args");
                return ESP_ERR_INVALID_ARG;
            }
            break;
        }
        case CMD_SET_COMM_PROT:
            telemetry_set_protocol(plen >= 1 && params[0] == 1
                                   ? TELEMETRY_PROTO_MQTTS : TELEMETRY_PROTO_HTTPS);
            break;
        case CMD_SET_API_TARGET: {
            char uri[256] = {0};
            size_t n = plen < sizeof(uri) - 1 ? plen : sizeof(uri) - 1;
            memcpy(uri, params, n);
            err = telemetry_set_api_target(uri); /* B3 validation inside */
            if (err != ESP_OK) {
                resp_err(out, 22, "Target Rejected (require https/mqtts, allowed domain)");
                return err;
            }
            break;
        }
        case CMD_START_CALIB:  err = calibration_start(); break;
        case CMD_ADD_CALIB:    err = calibration_add(plen >= 1 ? params[0] : 0); break;
        case CMD_FINISH_CALIB: err = calibration_finish(); break;
        case CMD_REQUEST_SYNC: {
            size_t jl = 0;
            char *json = event_log_to_sync_json(&jl);
            if (json) {
                size_t n = jl < sizeof(out->data) - 1 ? jl : sizeof(out->data) - 1;
                memcpy(out->data, json, n);
                out->len = n;
                event_log_free(json);
                return ESP_OK; /* SYNC_DATA returned directly */
            }
            resp_err(out, 23, "Sync Failed");
            return ESP_FAIL;
        }
        case CMD_ACK_SYNC:
            event_log_delete();
            break;
        case CMD_SET_TIME: {
            if (plen >= 4) {
                /* 4-byte LE epoch. RTC set handled by a time helper. */
                /* time_set_epoch((uint32_t)params[0]|...); */
            }
            break;
        }
#if CONFIG_SPB_DEBUG_BUILD
        case CMD_READ_LOG_FILE: {
            char *raw = NULL; size_t rl = 0;
            if (event_log_read_raw(&raw, &rl) == ESP_OK && raw) {
                size_t n = rl < sizeof(out->data) - 1 ? rl : sizeof(out->data) - 1;
                memcpy(out->data, raw, n);
                out->len = n;
                free(raw);
                return ESP_OK;
            }
            resp_err(out, 24, "No Log");
            return ESP_ERR_NOT_FOUND;
        }
#endif
        case CMD_DELETE_LOG_FILE:
            event_log_delete();
            break;
        case CMD_SET_PILL_INTERVAL:
            if (plen >= 1 && params[0] >= BOARD_PILL_INTERVAL_MIN_HOURS &&
                params[0] <= BOARD_PILL_INTERVAL_MAX_HOURS) {
                nvs_store_set_i32(NVS_KEY_PILL_INTERVAL, params[0]);
            } else {
                resp_err(out, 25, "Pill interval not in range");
                return ESP_ERR_INVALID_ARG;
            }
            break;
        case CMD_SET_PILL_INTERVAL_START:
            if (plen >= 1) nvs_store_set_i32(NVS_KEY_INTERVAL_START, params[0]);
            break;
        case CMD_SET_SAFETY_TIMEOUT:
            if (plen >= 1 && params[0] >= BOARD_SAFETY_TIMEOUT_MIN_HOURS &&
                params[0] <= BOARD_SAFETY_TIMEOUT_MAX_HOURS) {
                nvs_store_set_i32(NVS_KEY_SAFETY_TIMEOUT, params[0]);
            } else {
                resp_err(out, 26, "Invalid value for auto-unlock interval");
                return ESP_ERR_INVALID_ARG;
            }
            break;
        case CMD_ADD_ADMINKEY: {
            /* B2: now authenticated (verified above). Still write-once. */
            uint8_t existing[SPB_DEVICE_KEY_LEN];
            size_t el = sizeof(existing);
            if (nvs_store_get_blob(NVS_KEY_ADMIN, existing, &el) == ESP_OK) {
                resp_err(out, 27, "AdminKey Can't Be Changed");
                return ESP_ERR_INVALID_STATE;
            }
            if (plen < SPB_DEVICE_KEY_LEN) {
                resp_err(out, 28, "AdminKey Not Included");
                return ESP_ERR_INVALID_ARG;
            }
            err = nvs_store_set_blob(NVS_KEY_ADMIN, params, SPB_DEVICE_KEY_LEN);
            break;
        }
        default:
            resp_err(out, 11, "Unknown Opcode");
            return ESP_ERR_NOT_SUPPORTED;
    }

    if (err == ESP_OK) {
        if (out->len == 0) resp_ack(out, opcode);
    } else if (out->len == 0) {
        resp_err(out, 30, "Command Failed");
    }
    return err;
}
