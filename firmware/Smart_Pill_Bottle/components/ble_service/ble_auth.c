/*
 * ble_auth.c - BLE command auth + replay protection + lockout (B2).
 * REFERENCE implementation. The HMAC verification reuses device_identity so a
 * single per-device secret backs both BLE auth and network signing.
 */
#include "ble_auth.h"
#include "ble_service.h"
#include "device_identity.h"

#include <string.h>
#include <stdio.h>
#include "esp_log.h"
#include "esp_timer.h"

static const char *TAG = "ble_auth";

void ble_auth_reset_link(ble_link_ctx_t *ctx)
{
    memset(ctx, 0, sizeof(*ctx));
}

void ble_auth_set_link_secure(ble_link_ctx_t *ctx, bool secure)
{
    ctx->link_encrypted = secure;
    ctx->link_authenticated = secure;
}

bool ble_auth_link_is_trusted(const ble_link_ctx_t *ctx)
{
    return ctx->link_encrypted && ctx->link_authenticated;
}

bool ble_auth_is_locked_out(const ble_link_ctx_t *ctx)
{
    return esp_timer_get_time() < ctx->locked_until_us;
}

bool ble_auth_opcode_is_privileged(uint8_t opcode)
{
    switch (opcode) {
        /* BIND uses proof-of-possession, handled separately; everything that
         * changes state or reads sensitive data is privileged. */
        case CMD_LOCK_CMD:
        case CMD_SET_THRESHOLD:
        case CMD_UNBIND_DEVICE:
        case CMD_SET_WIFI_CRED:
        case CMD_SET_COMM_PROT:
        case CMD_SET_API_TARGET:
        case CMD_START_CALIB:
        case CMD_ADD_CALIB:
        case CMD_FINISH_CALIB:
        case CMD_REQUEST_SYNC:
        case CMD_ACK_SYNC:
        case CMD_SET_TIME:
        case CMD_READ_LOG_FILE:
        case CMD_DELETE_LOG_FILE:
        case CMD_SET_PILL_INTERVAL:
        case CMD_SET_PILL_INTERVAL_START:
        case CMD_SET_SAFETY_TIMEOUT:
        case CMD_ADD_ADMINKEY:   /* B2: ADD_ADMINKEY now REQUIRES auth */
            return true;
        default:
            return false;
    }
}

static void register_failure(ble_link_ctx_t *ctx)
{
    ctx->fail_count++;
    if (ctx->fail_count >= BLE_AUTH_MAX_FAILS) {
        ctx->locked_until_us = esp_timer_get_time() +
                               (int64_t)BLE_AUTH_LOCKOUT_MS * 1000;
        ESP_LOGW(TAG, "Privileged command lockout engaged (%u fails).",
                 (unsigned)ctx->fail_count);
        ctx->fail_count = 0;
    }
}

esp_err_t ble_auth_verify(ble_link_ctx_t *ctx,
                          uint8_t opcode,
                          uint32_t counter,
                          const uint8_t *params, size_t params_len,
                          const uint8_t tag[BLE_AUTH_TAG_LEN])
{
    /* 1. Link must be encrypted + authenticated (LE Secure Connections). */
    if (!ble_auth_link_is_trusted(ctx)) {
        ESP_LOGW(TAG, "Rejected: link not trusted (need encrypted+bonded).");
        return ESP_ERR_INVALID_STATE;
    }
    /* 2. Lockout. */
    if (ble_auth_is_locked_out(ctx)) {
        ESP_LOGW(TAG, "Rejected: link in lockout.");
        return ESP_ERR_INVALID_STATE;
    }
    /* 3. Replay guard: counter must strictly advance. */
    if (counter <= ctx->last_counter) {
        ESP_LOGW(TAG, "Rejected: replay/stale counter (%u <= %u).",
                 (unsigned)counter, (unsigned)ctx->last_counter);
        register_failure(ctx);
        return ESP_ERR_INVALID_STATE;
    }
    if (!device_identity_is_provisioned()) {
        return ESP_ERR_INVALID_STATE; /* fail closed */
    }

    /* 4. HMAC over opcode || params, with the link command counter as the
     * (decimal) nonce. This is the LOCAL BLE command-auth tag -- distinct from
     * the network wire format -- but it reuses the same per-device secret and
     * the same device_identity_sign() primitive. A fixed domain-separation
     * label ("ble-cmd") as the device_id prevents any cross-protocol tag reuse
     * with the network telemetry path. */
    uint8_t buf[1 + 256];
    if (params_len > sizeof(buf) - 1) {
        return ESP_ERR_INVALID_SIZE;
    }
    buf[0] = opcode;
    if (params_len) memcpy(buf + 1, params, params_len);

    char counter_dec[24];
    snprintf(counter_dec, sizeof(counter_dec), "%u", (unsigned)counter);

    uint8_t expected[BLE_AUTH_TAG_LEN];
    if (device_identity_sign("ble-cmd", counter_dec, 0,
                             buf, 1 + params_len, expected) != ESP_OK) {
        return ESP_FAIL;
    }

    if (!device_identity_ct_equal(expected, tag, BLE_AUTH_TAG_LEN)) {
        ESP_LOGW(TAG, "Rejected: command HMAC mismatch.");
        register_failure(ctx);
        return ESP_ERR_INVALID_RESPONSE;
    }

    /* Success: advance replay counter, clear failures. */
    ctx->last_counter = counter;
    ctx->fail_count = 0;
    return ESP_OK;
}
