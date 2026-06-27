/*
 * telemetry.h - Signed network push over HTTPS / MQTTS (B1 + B3).
 *
 * B1: NEVER serialize the per-device key into the payload. Each event body is
 * signed with HMAC-SHA256 over (canonical_body || nonce || timestamp) using
 * the per-device secret, and the signature + nonce + timestamp + device id are
 * sent in HEADERS (HTTPS) or an envelope (MQTTS). The frozen contract lives in
 * docs/WIRE_FORMAT.md; the smart-vial-backend (A3) verifies the same HMAC.
 *
 * B3: require https:// / mqtts:// only; reject plaintext; verify the server
 * certificate against an embedded CA bundle / pinned cert; fail closed.
 */
#ifndef SPB_TELEMETRY_H
#define SPB_TELEMETRY_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "esp_err.h"
#include "event_log.h"

typedef enum {
    TELEMETRY_PROTO_HTTPS = 0,
    TELEMETRY_PROTO_MQTTS,
} telemetry_proto_t;

/* Initialise telemetry (loads API target + protocol from NVS). Does NOT start
 * Wi-Fi; the wifi_manager owns the link. */
esp_err_t telemetry_init(void);

/*
 * Validate + persist an API target (called by BLE SET_API_TARGET 0x16).
 * B3 enforcement:
 *   - scheme MUST be https:// or mqtts:// (reject http/mqtt/ws/anything)
 *   - host MUST match the board_config allow-list (when restriction enabled)
 * Returns ESP_ERR_INVALID_ARG on a rejected target (fail closed).
 */
esp_err_t telemetry_set_api_target(const char *uri);

/* Select protocol (BLE SET_COMM_PROT 0x15). */
esp_err_t telemetry_set_protocol(telemetry_proto_t proto);

/*
 * Build the canonical event body (NO key inside) and enqueue a signed push.
 * Used by event_log_record. The body schema is the B1-safe replacement for the
 * vulnerable {"deviceId","authKey",...} form:
 *   {"deviceId":"<mac>","eventType":"pill_change","timestamp":<ts>,
 *    "currentCount":<n>,"countChange":<d>}
 * authKey is DELIBERATELY ABSENT; authenticity comes from the HMAC header.
 */
esp_err_t telemetry_enqueue_event(const event_record_t *rec);

/* Start the background sender task. */
esp_err_t telemetry_start(void);

#endif /* SPB_TELEMETRY_H */
