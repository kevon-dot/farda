idf_component_register(
    SRCS "loadcell_hx711.c"
    INCLUDE_DIRS "include"
    REQUIRES board_config nvs_store driver
    PRIV_REQUIRES esp_rom
)
