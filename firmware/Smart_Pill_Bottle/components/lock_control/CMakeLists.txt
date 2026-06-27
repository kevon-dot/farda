idf_component_register(
    SRCS "lock_control.c"
    INCLUDE_DIRS "include"
    REQUIRES board_config telemetry driver esp_timer
)
