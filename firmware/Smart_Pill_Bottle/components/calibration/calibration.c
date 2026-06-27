/*
 * calibration.c - Single-point load-cell calibration (reconstructs the
 * Calibration component + loadcell_calibration_task). REFERENCE implementation.
 */
#include "calibration.h"
#include "loadcell_hx711.h"
#include "nvs_store.h"

#include <string.h>
#include "esp_log.h"
#include "esp_mac.h"

static const char *TAG = "Calibration";

typedef enum {
    CAL_IDLE = 0,
    CAL_ARMED,     /* tared, waiting for pills */
    CAL_DONE,
} cal_state_t;

static cal_state_t s_state = CAL_IDLE;
static int32_t     s_tare_raw = 0;
static bool        s_valid = false;

static void get_mac(uint8_t mac[6])
{
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
}

esp_err_t calibration_init(void)
{
    /* Verify any stored calibration is bound to THIS device's MAC. */
    uint8_t stored_mac[6] = {0}, my_mac[6] = {0};
    size_t len = sizeof(stored_mac);
    get_mac(my_mac);
    if (nvs_store_get_blob(NVS_KEY_CALIB_MAC, stored_mac, &len) == ESP_OK &&
        len == 6) {
        if (memcmp(stored_mac, my_mac, 6) == 0) {
            s_valid = true;
            ESP_LOGI(TAG, "Saved Calibration Data: valid for this device.");
        } else {
            ESP_LOGE(TAG, "calibration data MAC check failed: "
                          "expected %02x:%02x:%02x:%02x:%02x:%02x",
                     my_mac[0], my_mac[1], my_mac[2],
                     my_mac[3], my_mac[4], my_mac[5]);
            s_valid = false;
        }
    } else {
        ESP_LOGW(TAG, "Loadcell Not Calibrated Yet!");
    }
    return ESP_OK;
}

bool calibration_is_valid(void)
{
    return s_valid;
}

esp_err_t calibration_start(void)
{
    ESP_LOGW(TAG, "Loadcell calibration started!");
    int32_t raw = 0;
    /* Tare empty cell. */
    if (loadcell_tare() != ESP_OK) {
        ESP_LOGE(TAG, "Loadcell taring failed");
        return ESP_FAIL;
    }
    if (loadcell_read_raw(&raw) != ESP_OK) {
        return ESP_FAIL;
    }
    s_tare_raw = raw;
    s_state = CAL_ARMED;
    ESP_LOGW(TAG, "Waiting for a placing pills to proceed calibration...");
    return ESP_OK;
}

esp_err_t calibration_add(int known_pills)
{
    if (s_state != CAL_ARMED) {
        return ESP_ERR_INVALID_STATE;
    }
    if (known_pills <= 0) {
        return ESP_ERR_INVALID_ARG;
    }
    ESP_LOGW(TAG, "Loadcell Calibrating with known numbers of %d...", known_pills);

    int32_t loaded_raw = 0;
    if (loadcell_read_raw(&loaded_raw) != ESP_OK) {
        return ESP_FAIL;
    }
    int32_t delta = loaded_raw - s_tare_raw;
    if (delta == 0) {
        ESP_LOGE(TAG, "Pill Adding Calibration Failed (no weight delta)");
        return ESP_FAIL;
    }

    /*
     * Single-point calibration: we cannot separate per-pill weight from the
     * scale with one unknown sample, so we calibrate counts-per-pill directly
     * and treat per_pill_grams as 1.0 "pill unit". This matches the vendor's
     * "calibrate directly using pill weight" decision.
     */
    loadcell_calib_t c;
    loadcell_get_calibration(&c);
    c.offset = s_tare_raw;
    c.scale = (float)delta / (float)known_pills; /* counts per pill */
    c.per_pill_grams = 1.0f;                     /* 1 unit == 1 pill */
    loadcell_set_calibration(&c);

    s_state = CAL_DONE;
    ESP_LOGI(TAG, "Calibration completed!");
    return ESP_OK;
}

esp_err_t calibration_finish(void)
{
    if (s_state != CAL_DONE) {
        ESP_LOGE(TAG, "Calibration timeout!");
        return ESP_ERR_INVALID_STATE;
    }
    loadcell_calib_t c;
    loadcell_get_calibration(&c);

    esp_err_t err = nvs_store_set_blob(NVS_KEY_CALIB_BLOB, &c, sizeof(c));
    if (err != ESP_OK) return err;

    uint8_t mac[6];
    get_mac(mac);
    err = nvs_store_set_blob(NVS_KEY_CALIB_MAC, mac, sizeof(mac));
    if (err != ESP_OK) return err;

    int32_t ver = 1;
    nvs_store_set_i32(NVS_KEY_CALIB_VER, ver);

    s_valid = true;
    s_state = CAL_IDLE;
    ESP_LOGI(TAG, "Calibration Finished Successfully");
    return ESP_OK;
}
