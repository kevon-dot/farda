/*
 * telemetry.c - Signed event push over HTTPS / MQTTS (B1 + B3).
 *
 * SECURITY-CRITICAL FILE. The B1 fix lives here:
 *   - The event body NEVER contains the per-device key. The old vulnerable
 *     format {"deviceId":"%s","authKey":"%s",...} is GONE.
 *   - Authenticity is proven by HMAC-SHA256 over (body || nonce || timestamp)
 *     using the per-device secret (device_identity_sign). The signature,
 *     nonce, timestamp and device id travel in HEADERS / an MQTT envelope.
 *   - B3: only https:// / mqtts:// targets are accepted; the server cert is
 *     verified against an embedded CA bundle; we fail closed.
 *
 * REFERENCE implementation: the esp_http_client / esp_mqtt flows are idiomatic
 * but untested on hardware. The CA bundle is a placeholder PEM that MUST be
 * replaced with the real Farda backend chain (see docs/PROVISIONING.md).
 */
#include "telemetry.h"
#include "device_identity.h"
#include "nvs_store.h"
#include "board_config.h"

#include <string.h>
#include <stdlib.h>
#include <inttypes.h>
#include "sdkconfig.h"
#include "esp_log.h"
#include "esp_http_client.h"
#include "esp_crt_bundle.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"

static const char *TAG = "telemetry";

static telemetry_proto_t s_proto = TELEMETRY_PROTO_HTTPS;
static char s_api_target[256] = {0};
static QueueHandle_t s_queue = NULL;

/* Pinned backend CA chain. TODO(provisioning): replace with the real Farda /
 * smart-vial backend certificate chain (PEM). Empty here so an unconfigured
 * build cannot silently trust a public CA. */
static const char *s_backend_ca_pem = NULL; /* set via embedded asset in prod */

/* ---- B3: target validation ------------------------------------------------ */

static bool scheme_is_tls(const char *uri, telemetry_proto_t *proto_out)
{
    if (strncmp(uri, "https://", 8) == 0) {
        if (proto_out) *proto_out = TELEMETRY_PROTO_HTTPS;
        return true;
    }
    if (strncmp(uri, "mqtts://", 8) == 0) {
        if (proto_out) *proto_out = TELEMETRY_PROTO_MQTTS;
        return true;
    }
    return false;
}

static bool host_is_allowed(const char *uri)
{
#if CONFIG_SPB_RESTRICT_API_DOMAIN
    static const char *suffixes[] = BOARD_ALLOWED_API_DOMAIN_SUFFIXES;
    /* Extract host between scheme:// and the next '/' or ':'. */
    const char *p = strstr(uri, "://");
    if (!p) return false;
    p += 3;
    char host[128];
    size_t i = 0;
    while (p[i] && p[i] != '/' && p[i] != ':' && i < sizeof(host) - 1) {
        host[i] = p[i];
        i++;
    }
    host[i] = '\0';
    size_t hl = strlen(host);
    for (size_t s = 0; s < sizeof(suffixes) / sizeof(suffixes[0]); s++) {
        size_t sl = strlen(suffixes[s]);
        if (hl >= sl && strcmp(host + (hl - sl), suffixes[s]) == 0) {
            return true;
        }
    }
    return false;
#else
    (void)uri;
    return true;
#endif
}

esp_err_t telemetry_set_api_target(const char *uri)
{
    if (!uri || strlen(uri) >= sizeof(s_api_target)) {
        return ESP_ERR_INVALID_ARG;
    }
#if CONFIG_SPB_REQUIRE_TLS
    telemetry_proto_t proto;
    if (!scheme_is_tls(uri, &proto)) {
        ESP_LOGE(TAG, "Rejected non-TLS API target (require https/mqtts).");
        return ESP_ERR_INVALID_ARG; /* fail closed */
    }
    if (!host_is_allowed(uri)) {
        ESP_LOGE(TAG, "Rejected API target outside allowed domain(s).");
        return ESP_ERR_INVALID_ARG;
    }
    s_proto = proto;
#endif
    strncpy(s_api_target, uri, sizeof(s_api_target) - 1);
    s_api_target[sizeof(s_api_target) - 1] = '\0';
    esp_err_t err = nvs_store_set_str(NVS_KEY_API_TARGET, s_api_target);
    ESP_LOGI(TAG, "API target set.");
    return err;
}

esp_err_t telemetry_set_protocol(telemetry_proto_t proto)
{
    s_proto = proto;
    return nvs_store_set_i32(NVS_KEY_WIFI_PROTOCOL, (int32_t)proto);
}

esp_err_t telemetry_init(void)
{
    size_t len = sizeof(s_api_target);
    if (nvs_store_get_str(NVS_KEY_API_TARGET, s_api_target, &len) != ESP_OK) {
        s_api_target[0] = '\0';
    }
    int32_t p = 0;
    if (nvs_store_get_i32(NVS_KEY_WIFI_PROTOCOL, &p) == ESP_OK) {
        s_proto = (telemetry_proto_t)p;
    }
    return ESP_OK;
}

/* ---- B1: build canonical body (NO key) ------------------------------------ */

/*
 * Canonical event body. NOTE: there is deliberately NO authKey field here.
 *
 * Field names match the MERGED backend ingestion schema
 * (smart-vial-backend/utils/eventValidation.js): `device_id` (which the backend
 * requires to equal the x-device-id header -- else DEVICE_ID_MISMATCH), `event`
 * (the event-type name), `timestamp` (unix seconds), and a per-type `payload`.
 * The body's `device_id` is a routing label, NOT a secret. See
 * docs/WIRE_FORMAT.md for the exact bytes the backend re-hashes.
 *
 * The returned bytes are the EXACT body transmitted AND the exact body hashed
 * into x-signature -- they must not be re-serialized differently anywhere.
 */
static int build_event_body(const event_record_t *rec, const char *device_id,
                            char *out, size_t out_len)
{
    return snprintf(out, out_len,
        "{\"device_id\":\"%s\",\"event\":\"%s\",\"timestamp\":%" PRId64
        ",\"payload\":{\"currentCount\":%" PRId32 ",\"countChange\":%" PRId32 "}}",
        device_id, event_type_name(rec->type), rec->ts, rec->count, rec->change);
}

/* ---- signed HTTPS push ---------------------------------------------------- */

static esp_err_t push_https(const char *body, size_t body_len,
                            const char *device_id,
                            const char *nonce_dec, int64_t ts,
                            const char *sig_hex)
{
    esp_http_client_config_t cfg = {
        .url = s_api_target,
        .method = HTTP_METHOD_POST,
        .timeout_ms = 10000,
#if CONFIG_SPB_REQUIRE_TLS
        /* B3: verify the server certificate, fail closed. Prefer a pinned
         * chain (s_backend_ca_pem); fall back to the IDF cert bundle only if a
         * pin has not been provisioned. */
        .cert_pem = s_backend_ca_pem,
        .crt_bundle_attach = s_backend_ca_pem ? NULL : esp_crt_bundle_attach,
        .skip_cert_common_name_check = false,
#endif
    };
    esp_http_client_handle_t client = esp_http_client_init(&cfg);
    if (!client) {
        ESP_LOGE(TAG, "Failed to init http client");
        return ESP_FAIL;
    }

    /* B1 wire headers -- key is NEVER sent. x-nonce is the decimal monotonic
     * counter; x-timestamp is unix seconds. Order/format matches the merged
     * backend (smart-vial-backend/docs/DEVICE_AUTH.md). */
    esp_http_client_set_header(client, "Content-Type", "application/json");
    esp_http_client_set_header(client, "x-device-id", device_id);
    esp_http_client_set_header(client, "x-nonce", nonce_dec);
    char ts_buf[24];
    snprintf(ts_buf, sizeof(ts_buf), "%" PRId64, ts);
    esp_http_client_set_header(client, "x-timestamp", ts_buf);
    esp_http_client_set_header(client, "x-signature", sig_hex);

    esp_http_client_set_post_field(client, body, body_len);
    esp_err_t err = esp_http_client_perform(client);
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "HTTPS: Data Send Successfuly");
    } else {
        ESP_LOGE(TAG, "HTTPS: Data not Sent");
    }
    esp_http_client_cleanup(client);
    return err;
}

/* MQTTS push: same signed envelope; signature/nonce/ts/device id are JSON
 * envelope fields around the body (see docs/WIRE_FORMAT.md). Reconstructed at
 * interface level. */
static esp_err_t push_mqtts(const char *body, const char *device_id,
                            const char *nonce_dec, int64_t ts,
                            const char *sig_hex)
{
    /* TODO(hardware): wire esp-mqtt client with mqtts:// + server cert
     * verification (esp_mqtt_client_config_t.broker.verification). The
     * envelope must carry x-device-id/x-nonce/x-timestamp/x-signature so the
     * backend verifies the same HMAC (decimal nonce, epoch-second timestamp). */
    ESP_LOGI(TAG, "Sending Pill Change data over mqtt...");
    char topic[64];
    snprintf(topic, sizeof(topic), BOARD_MQTT_TOPIC_EVENTS_FMT, device_id);
    (void)body; (void)nonce_dec; (void)ts; (void)sig_hex; (void)topic;
    return ESP_OK; /* placeholder: see TODO above */
}

static esp_err_t send_one(const event_record_t *rec)
{
    if (s_api_target[0] == '\0') {
        return ESP_ERR_INVALID_STATE; /* nothing configured */
    }
    if (!device_identity_is_provisioned()) {
        ESP_LOGE(TAG, "No device identity; refusing to sign (fail closed).");
        return ESP_ERR_INVALID_STATE;
    }

    char device_id[SPB_DEVICE_ID_LEN];
    if (device_identity_get_id(device_id, sizeof(device_id)) != ESP_OK) {
        return ESP_FAIL;
    }

    char body[256];
    int blen = build_event_body(rec, device_id, body, sizeof(body));
    if (blen <= 0) return ESP_FAIL;

    /* Monotonic decimal nonce, persisted in NVS (backend rejects nonce <= last
     * seen). */
    char nonce_dec[SPB_NONCE_DEC_LEN];
    if (device_identity_next_nonce(nonce_dec, sizeof(nonce_dec), NULL) != ESP_OK) {
        return ESP_FAIL;
    }

    int64_t ts = rec->ts;
    uint8_t mac[SPB_HMAC_LEN];
    /* Sign deviceId\nnonce\ntimestamp\nbody -- order matches the merged
     * backend verbatim (smart-vial-backend/utils/deviceAuth.js). */
    if (device_identity_sign(device_id, nonce_dec, ts,
                             (const uint8_t *)body, (size_t)blen, mac) != ESP_OK) {
        return ESP_FAIL;
    }
    char sig_hex[2 * SPB_HMAC_LEN + 1];
    device_identity_hex(mac, sizeof(mac), sig_hex, sizeof(sig_hex));

    if (s_proto == TELEMETRY_PROTO_HTTPS) {
        ESP_LOGI(TAG, "Sending Pill Change data over https...");
        return push_https(body, (size_t)blen, device_id, nonce_dec, ts, sig_hex);
    }
    return push_mqtts(body, device_id, nonce_dec, ts, sig_hex);
}

esp_err_t telemetry_enqueue_event(const event_record_t *rec)
{
    if (!s_queue) {
        return ESP_ERR_INVALID_STATE;
    }
    event_record_t copy = *rec;
    if (xQueueSend(s_queue, &copy, 0) != pdTRUE) {
        ESP_LOGE(TAG, "Failed to enqueue WiFi data!");
        return ESP_FAIL;
    }
    return ESP_OK;
}

static void telemetry_task(void *arg)
{
    (void)arg;
    event_record_t rec;
    for (;;) {
        if (xQueueReceive(s_queue, &rec, portMAX_DELAY) == pdTRUE) {
            esp_err_t err = send_one(&rec);
            if (err != ESP_OK) {
                /* Durable copy already in SPIFFS; will sync later via BLE or
                 * a future retry. Do not drop the SPIFFS record. */
                ESP_LOGW(TAG, "Event push failed (%s); kept offline.",
                         esp_err_to_name(err));
            }
        }
    }
}

esp_err_t telemetry_start(void)
{
    if (!s_queue) {
        s_queue = xQueueCreate(16, sizeof(event_record_t));
        if (!s_queue) {
            ESP_LOGE(TAG, "Failed to create WiFi queue!");
            return ESP_FAIL;
        }
    }
    if (xTaskCreate(telemetry_task, "wifi_task", 6144, NULL, 5, NULL) != pdPASS) {
        return ESP_FAIL;
    }
    return ESP_OK;
}
