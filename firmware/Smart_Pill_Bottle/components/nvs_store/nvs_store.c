/*
 * nvs_store.c - NVS configuration/secret store (reconstructs NVS/NVS.c).
 * REFERENCE implementation - faithful interface, real IDF NVS calls.
 */
#include "nvs_store.h"

#include <string.h>
#include "esp_log.h"
#include "nvs_flash.h"
#include "nvs.h"

static const char *TAG = "nvs_store";

esp_err_t nvs_store_init(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_LOGW(TAG, "NVS partition issue detected, erasing...");
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize NVS: %s", esp_err_to_name(err));
        return err;
    }
    ESP_LOGI(TAG, "NVS initialized successfully");
    return ESP_OK;
}

static esp_err_t open_ns(nvs_handle_t *h, nvs_open_mode_t mode)
{
    return nvs_open(NVS_NS_CONFIG, mode, h);
}

esp_err_t nvs_store_get_blob(const char *key, void *out, size_t *len)
{
    nvs_handle_t h;
    esp_err_t err = open_ns(&h, NVS_READONLY);
    if (err != ESP_OK) return err;
    err = nvs_get_blob(h, key, out, len);
    nvs_close(h);
    return err;
}

esp_err_t nvs_store_set_blob(const char *key, const void *val, size_t len)
{
    nvs_handle_t h;
    esp_err_t err = open_ns(&h, NVS_READWRITE);
    if (err != ESP_OK) return err;
    err = nvs_set_blob(h, key, val, len);
    if (err == ESP_OK) err = nvs_commit(h);
    nvs_close(h);
    return err;
}

esp_err_t nvs_store_get_str(const char *key, char *out, size_t *len)
{
    nvs_handle_t h;
    esp_err_t err = open_ns(&h, NVS_READONLY);
    if (err != ESP_OK) return err;
    err = nvs_get_str(h, key, out, len);
    nvs_close(h);
    return err;
}

esp_err_t nvs_store_set_str(const char *key, const char *val)
{
    nvs_handle_t h;
    esp_err_t err = open_ns(&h, NVS_READWRITE);
    if (err != ESP_OK) return err;
    err = nvs_set_str(h, key, val);
    if (err == ESP_OK) err = nvs_commit(h);
    nvs_close(h);
    return err;
}

esp_err_t nvs_store_get_i32(const char *key, int32_t *out)
{
    nvs_handle_t h;
    esp_err_t err = open_ns(&h, NVS_READONLY);
    if (err != ESP_OK) return err;
    err = nvs_get_i32(h, key, out);
    nvs_close(h);
    return err;
}

esp_err_t nvs_store_set_i32(const char *key, int32_t val)
{
    nvs_handle_t h;
    esp_err_t err = open_ns(&h, NVS_READWRITE);
    if (err != ESP_OK) return err;
    err = nvs_set_i32(h, key, val);
    if (err == ESP_OK) err = nvs_commit(h);
    nvs_close(h);
    return err;
}

esp_err_t nvs_store_erase_key(const char *key)
{
    nvs_handle_t h;
    esp_err_t err = open_ns(&h, NVS_READWRITE);
    if (err != ESP_OK) return err;
    err = nvs_erase_key(h, key);
    if (err == ESP_OK) err = nvs_commit(h);
    nvs_close(h);
    return err;
}

esp_err_t nvs_store_commit(void)
{
    nvs_handle_t h;
    esp_err_t err = open_ns(&h, NVS_READWRITE);
    if (err != ESP_OK) return err;
    err = nvs_commit(h);
    nvs_close(h);
    return err;
}
