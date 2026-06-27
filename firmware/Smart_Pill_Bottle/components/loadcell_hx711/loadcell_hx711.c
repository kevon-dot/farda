/*
 * loadcell_hx711.c - Bit-banged HX711 24-bit load-cell driver.
 * REFERENCE: the HX711 protocol below is standard, but timing, gain pulses,
 * scale/offset and noise handling MUST be validated on the real load cell.
 */
#include "loadcell_hx711.h"
#include "board_config.h"
#include "nvs_store.h"

#include <string.h>
#include <math.h>
#include "esp_log.h"
#include "esp_rom_sys.h"   /* esp_rom_delay_us */
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "loadcell";

static loadcell_calib_t s_calib = {
    .scale = BOARD_HX711_DEFAULT_SCALE,
    .offset = BOARD_HX711_DEFAULT_OFFSET,
    .per_pill_grams = BOARD_MIN_PILL_WEIGHT_G,
};

/* Number of extra clock pulses selects gain/channel:
 *   25 -> ch A gain 128, 26 -> ch B gain 32, 27 -> ch A gain 64. */
static int gain_pulses(void)
{
    switch (BOARD_HX711_GAIN) {
        case 64:  return 27;
        case 32:  return 26;
        default:  return 25; /* 128 */
    }
}

esp_err_t loadcell_init(void)
{
    gpio_config_t sck = {
        .pin_bit_mask = 1ULL << BOARD_LC_SCK_PIN,
        .mode = GPIO_MODE_OUTPUT,
    };
    gpio_config_t dout = {
        .pin_bit_mask = 1ULL << BOARD_LC_DOUT_PIN,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    gpio_config(&sck);
    gpio_config(&dout);
    gpio_set_level(BOARD_LC_SCK_PIN, 0);

    /* Load saved calibration if present (anti-transfer MAC check done in the
     * calibration component). */
    loadcell_calib_t saved;
    size_t len = sizeof(saved);
    if (nvs_store_get_blob(NVS_KEY_CALIB_BLOB, &saved, &len) == ESP_OK &&
        len == sizeof(saved)) {
        s_calib = saved;
        ESP_LOGI(TAG, "Saved Calibration Data loaded.");
    } else {
        ESP_LOGW(TAG, "Loadcell Not Calibrated Yet!");
    }

    if (!loadcell_is_ready()) {
        /* Give the chip a moment to power up. */
        vTaskDelay(pdMS_TO_TICKS(50));
    }
    if (!loadcell_is_ready()) {
        ESP_LOGE(TAG, "HX711 init failed: not ready");
        ESP_LOGE(TAG, "Loadcell FAILED");
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "HX711 initialized (DOUT=%d, SCK=%d, GAIN=%d)",
             BOARD_LC_DOUT_PIN, BOARD_LC_SCK_PIN, BOARD_HX711_GAIN);
    ESP_LOGI(TAG, "Loadcell OK");
    return ESP_OK;
}

bool loadcell_is_ready(void)
{
    return gpio_get_level(BOARD_LC_DOUT_PIN) == 0;
}

static int32_t read_once(void)
{
    /* Wait for ready (DOUT low). */
    int guard = 0;
    while (!loadcell_is_ready() && guard++ < 1000) {
        esp_rom_delay_us(100);
    }

    uint32_t value = 0;
    portDISABLE_INTERRUPTS();
    for (int i = 0; i < 24; i++) {
        gpio_set_level(BOARD_LC_SCK_PIN, 1);
        esp_rom_delay_us(1);
        value = (value << 1) | (uint32_t)gpio_get_level(BOARD_LC_DOUT_PIN);
        gpio_set_level(BOARD_LC_SCK_PIN, 0);
        esp_rom_delay_us(1);
    }
    /* Gain/channel selection pulses. */
    int extra = gain_pulses() - 24;
    for (int i = 0; i < extra; i++) {
        gpio_set_level(BOARD_LC_SCK_PIN, 1);
        esp_rom_delay_us(1);
        gpio_set_level(BOARD_LC_SCK_PIN, 0);
        esp_rom_delay_us(1);
    }
    portENABLE_INTERRUPTS();

    /* Sign-extend 24-bit two's complement. */
    if (value & 0x800000) {
        value |= 0xFF000000;
    }
    return (int32_t)value;
}

esp_err_t loadcell_read_raw(int32_t *out)
{
    if (!out) return ESP_ERR_INVALID_ARG;
    /* Average BOARD_LC_SAMPLE_COUNT readings to fight noise/creep. */
    int64_t acc = 0;
    for (int i = 0; i < BOARD_LC_SAMPLE_COUNT; i++) {
        acc += read_once();
    }
    *out = (int32_t)(acc / BOARD_LC_SAMPLE_COUNT);
    return ESP_OK;
}

esp_err_t loadcell_read_grams(float *out)
{
    if (!out) return ESP_ERR_INVALID_ARG;
    int32_t raw = 0;
    esp_err_t err = loadcell_read_raw(&raw);
    if (err != ESP_OK) return err;
    if (s_calib.scale == 0.0f) return ESP_ERR_INVALID_STATE;
    *out = ((float)(raw - s_calib.offset)) / s_calib.scale;
    return ESP_OK;
}

esp_err_t loadcell_read_pill_count(int32_t *out)
{
    if (!out) return ESP_ERR_INVALID_ARG;
    float grams = 0.0f;
    esp_err_t err = loadcell_read_grams(&grams);
    if (err != ESP_OK) return err;
    if (s_calib.per_pill_grams <= 0.0f) return ESP_ERR_INVALID_STATE;
    int32_t count = (int32_t)lroundf(grams / s_calib.per_pill_grams);
    if (count < 0) count = 0;
    *out = count;
    return ESP_OK;
}

esp_err_t loadcell_tare(void)
{
    ESP_LOGI(TAG, "Trying to tare Loadcell");
    for (int attempt = 0; attempt < BOARD_LC_TARE_RETRIES; attempt++) {
        int32_t raw = 0;
        if (loadcell_read_raw(&raw) == ESP_OK) {
            s_calib.offset = raw;
            return ESP_OK;
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    ESP_LOGE(TAG, "Loadcell taring failed after retries");
    return ESP_FAIL;
}

void loadcell_set_calibration(const loadcell_calib_t *c)
{
    if (c) s_calib = *c;
}

void loadcell_get_calibration(loadcell_calib_t *c)
{
    if (c) *c = s_calib;
}
