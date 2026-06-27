idf_component_register(
    SRCS "telemetry.c" "event_log.c"
    INCLUDE_DIRS "include"
    REQUIRES board_config device_identity nvs_store esp_http_client
             esp-tls spiffs mqtt
    PRIV_REQUIRES esp_common
)
