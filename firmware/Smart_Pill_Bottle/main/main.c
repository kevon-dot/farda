/*
 * main.c - Farda Smart Pill Bottle application entry (REFERENCE).
 *
 * UNVERIFIED reconstruction. Boots the subsystems in a safe order:
 *   NVS -> device identity -> SPIFFS/event log -> lock (safe state first!) ->
 *   loadcell/calibration -> battery -> telemetry -> Wi-Fi -> BLE.
 *
 * The solenoid is driven to the LOCKED/safe state as early as possible so it
 * never actuates during boot (Feature_Overview / Flashing_Instructions).
 */
#include "esp_log.h"
#include "esp_task_wdt.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "nvs_store.h"
#include "device_identity.h"
#include "event_log.h"
#include "telemetry.h"
#include "lock_control.h"
#include "loadcell_hx711.h"
#include "calibration.h"
#include "battery_monitoring.h"
#include "wifi_manager.h"
#include "ble_service.h"
#include "ota_update.h"

static const char *TAG = "spb_main";

static void wifi_status_to_ble(bool connected)
{
    ESP_LOGI(TAG, "WiFi %s", connected ? "connected" : "disconnected");
    /* TODO: notify the app over the BLE WiFi-status characteristic. */
}

void app_main(void)
{
    ESP_LOGW(TAG, "=== Farda Smart Pill Bottle (REFERENCE, UNVERIFIED) ===");
    ESP_LOGI(TAG, "Firmware: %s", ota_update_running_version());

    /* 5-second Task Watchdog (feature doc). */
    esp_task_wdt_config_t wdt = {
        .timeout_ms = 5000,
        .idle_core_mask = (1 << 0),
        .trigger_panic = true,
    };
    esp_task_wdt_init(&wdt);

    ESP_ERROR_CHECK(nvs_store_init());

    /* Identity must load before anything signs/binds; fail closed if not
     * provisioned (the device refuses network reporting + binding). */
    if (device_identity_init() != ESP_OK) {
        ESP_LOGE(TAG, "Device not provisioned -- network + bind disabled. "
                      "See docs/PROVISIONING.md.");
    }

    /* Lock to safe state IMMEDIATELY. */
    ESP_ERROR_CHECK(lock_control_init());

    ESP_ERROR_CHECK(event_log_init());
    telemetry_init();

    /* Sensors. */
    if (loadcell_init() != ESP_OK) {
        ESP_LOGE(TAG, "Loadcell FAILED");
    }
    calibration_init();
    if (battery_monitoring_init() != ESP_OK) {
        ESP_LOGE(TAG, "MAX17043 FAILED");
    }

    /* Networking. */
    wifi_manager_init();
    wifi_manager_register_status_cb(wifi_status_to_ble);
    wifi_manager_start();            /* uses saved creds if present */

    /* BLE control surface. */
    ESP_ERROR_CHECK(ble_service_init());
    ESP_ERROR_CHECK(ble_service_start());

    /* Background tasks. */
    ESP_ERROR_CHECK(lock_control_start());
    ESP_ERROR_CHECK(telemetry_start());
    battery_monitoring_start();

    /* Confirm this OTA image so anti-rollback keeps it (after init succeeds). */
    ota_update_mark_valid();

    /* Power-on / restart marker (lets the backend infer unlogged shutdowns). */
    event_log_record(EVT_VIAL_RESTARTED, 0, 0);

    ESP_LOGI(TAG, "Boot complete.");
}
