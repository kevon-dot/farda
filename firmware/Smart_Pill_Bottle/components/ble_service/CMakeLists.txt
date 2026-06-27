idf_component_register(
    SRCS "ble_service.c" "ble_dispatch.c" "ble_auth.c"
    INCLUDE_DIRS "include"
    REQUIRES board_config device_identity nvs_store
             lock_control calibration wifi_manager telemetry bt
    PRIV_REQUIRES esp_timer
)
