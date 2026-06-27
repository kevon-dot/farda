idf_component_register(
    SRCS "battery_monitoring.c"
    INCLUDE_DIRS "include"
    REQUIRES board_config driver telemetry
)
