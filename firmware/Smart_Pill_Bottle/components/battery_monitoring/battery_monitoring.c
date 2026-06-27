/*
 * battery_monitoring.c - MAX17043 fuel gauge (reconstructs MAX17043/MAX17043.c).
 * REFERENCE: I2C register access is idiomatic but the MAX17043 register math
 * and ALERT wiring MUST be confirmed on hardware.
 */
#include "battery_monitoring.h"
#include "board_config.h"
#include "event_log.h"

#include "esp_log.h"
#include "driver/i2c.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "battery_monitoring";

/* MAX17043 registers */
#define MAX17043_REG_VCELL   0x02
#define MAX17043_REG_SOC     0x04
#define MAX17043_REG_CONFIG  0x0C

static bool s_low5_fired = false;
static bool s_low2_fired = false;

static esp_err_t read_reg16(uint8_t reg, uint16_t *val)
{
    uint8_t buf[2] = {0};
    esp_err_t err = i2c_master_write_read_device(
        BOARD_I2C_PORT, BOARD_MAX17043_ADDR, &reg, 1, buf, 2,
        pdMS_TO_TICKS(100));
    if (err != ESP_OK) return err;
    *val = ((uint16_t)buf[0] << 8) | buf[1];
    return ESP_OK;
}

esp_err_t battery_monitoring_init(void)
{
    i2c_config_t conf = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = BOARD_I2C_SDA_PIN,
        .scl_io_num = BOARD_I2C_SCL_PIN,
        .sda_pullup_en = GPIO_PULLUP_ENABLE,
        .scl_pullup_en = GPIO_PULLUP_ENABLE,
        .master.clk_speed = BOARD_I2C_FREQ_HZ,
    };
    esp_err_t err = i2c_param_config(BOARD_I2C_PORT, &conf);
    if (err != ESP_OK) return err;
    err = i2c_driver_install(BOARD_I2C_PORT, I2C_MODE_MASTER, 0, 0, 0);
    if (err != ESP_OK) return err;

    /* Probe the device. */
    uint16_t v = 0;
    err = read_reg16(MAX17043_REG_VCELL, &v);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "MAX17043 FAILED");
        return err;
    }
    ESP_LOGI(TAG, "MAX17043 initialized (SDA=%d, SCL=%d, I2C Port=%d, ALERT=%d)",
             BOARD_I2C_SDA_PIN, BOARD_I2C_SCL_PIN, BOARD_I2C_PORT, BOARD_BAT_ALRT_PIN);
    ESP_LOGI(TAG, "MAX17043 OK");
    return ESP_OK;
}

esp_err_t battery_monitoring_read(battery_status_t *out)
{
    if (!out) return ESP_ERR_INVALID_ARG;
    uint16_t vcell = 0, soc = 0;
    esp_err_t err = read_reg16(MAX17043_REG_VCELL, &vcell);
    if (err != ESP_OK) return err;
    err = read_reg16(MAX17043_REG_SOC, &soc);
    if (err != ESP_OK) return err;

    /* TODO(hardware): confirm MAX17043 scaling. Datasheet: VCELL is 12-bit in
     * the upper bits, 1.25 mV/LSB; SOC high byte = integer percent. */
    out->voltage = ((float)(vcell >> 4)) * 0.00125f;
    out->soc_percent = (uint8_t)(soc >> 8);
    out->alert = false; /* TODO(hardware): wire BAT_ALRT IRQ to set this */
    return ESP_OK;
}

static void battery_task(void *arg)
{
    (void)arg;
    for (;;) {
        battery_status_t st;
        if (battery_monitoring_read(&st) == ESP_OK) {
            ESP_LOGI(TAG, "Battery Voltage: %0.2f", st.voltage);
            if (st.voltage < 3.0f) {
                ESP_LOGW(TAG, "Battery: Low Voltage (<5)");
            }
            /* Edge-triggered low-battery events. */
            if (st.soc_percent <= 2 && !s_low2_fired) {
                s_low2_fired = true;
                event_log_record(EVT_LOW_BATTERY_2, 0, 0);
            } else if (st.soc_percent <= 5 && !s_low5_fired) {
                s_low5_fired = true;
                event_log_record(EVT_LOW_BATTERY_5, 0, 0);
            }
            if (st.soc_percent > 6) {  /* re-arm with hysteresis */
                s_low5_fired = false;
                s_low2_fired = false;
            }
        }
        vTaskDelay(pdMS_TO_TICKS(30000)); /* TODO(hardware): tune cadence */
    }
}

esp_err_t battery_monitoring_start(void)
{
    if (xTaskCreate(battery_task, "battery_task", 3072, NULL, 4, NULL) != pdPASS) {
        return ESP_FAIL;
    }
    return ESP_OK;
}
