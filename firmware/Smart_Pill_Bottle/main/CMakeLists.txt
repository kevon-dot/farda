idf_component_register(
    SRCS "main.c"
    INCLUDE_DIRS "."
    REQUIRES nvs_store device_identity telemetry lock_control loadcell_hx711
             calibration battery_monitoring wifi_manager ble_service ota_update
             esp_task_wdt
)
