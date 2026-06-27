/*
 * nvs_store.h - Non-volatile configuration + secret storage (reconstructs
 * NVS/NVS.c). Holds: Wi-Fi SSID/password, the per-device secret ("devKey"),
 * the admin key, load-cell calibration (scale/offset + MAC integrity),
 * API target, comm protocol, MQTT broker, pill interval, safety timeout,
 * refill threshold, persisted pill count.
 *
 * SECURITY NOTE (B4/F5): on production units this NVS partition is encrypted
 * (CONFIG_NVS_ENCRYPTION) and protected by flash encryption. Secrets must
 * never be logged. The original firmware logged the saved Wi-Fi password
 * ("Saved WiFi Password: %s") -- this reimplementation MUST NOT.
 */
#ifndef SPB_NVS_STORE_H
#define SPB_NVS_STORE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "esp_err.h"

/* NVS namespace + canonical key names (from the image strings). */
#define NVS_NS_CONFIG          "spb_cfg"
#define NVS_KEY_ADMIN          "ADMIN_KEY"      /* admin override key, write-once */
#define NVS_KEY_AUTH           "savedAuthKey"   /* legacy bind key (kept for migration) */
#define NVS_KEY_WIFI_SSID      "wifi_ssid"
#define NVS_KEY_WIFI_PASS      "wifi_pass"
#define NVS_KEY_API_TARGET     "api_target"
#define NVS_KEY_WIFI_PROTOCOL  "wifi_protocol"  /* "HTTPS" | "MQTT" */
#define NVS_KEY_MQTT_BROKER    "mqtt_broker"
#define NVS_KEY_PILL_INTERVAL  "pill_intv"
#define NVS_KEY_INTERVAL_START "pill_start"
#define NVS_KEY_SAFETY_TIMEOUT "safety_to"
#define NVS_KEY_THRESHOLD      "threshold"
#define NVS_KEY_PILL_COUNT     "pill_count"
#define NVS_KEY_CALIB_BLOB     "calib"          /* scale+offset+per-pill weight */
#define NVS_KEY_CALIB_MAC      "calib_mac"      /* anti-transfer MAC binding */
#define NVS_KEY_CALIB_VER      "calib_ver"

esp_err_t nvs_store_init(void);

/* Blob helpers (out length in/out). */
esp_err_t nvs_store_get_blob(const char *key, void *out, size_t *len);
esp_err_t nvs_store_set_blob(const char *key, const void *val, size_t len);

/* String helpers. */
esp_err_t nvs_store_get_str(const char *key, char *out, size_t *len);
esp_err_t nvs_store_set_str(const char *key, const char *val);

/* Scalar helpers. */
esp_err_t nvs_store_get_i32(const char *key, int32_t *out);
esp_err_t nvs_store_set_i32(const char *key, int32_t val);

esp_err_t nvs_store_erase_key(const char *key);
esp_err_t nvs_store_commit(void);

#endif /* SPB_NVS_STORE_H */
