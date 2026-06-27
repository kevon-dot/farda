idf_component_register(
    SRCS "calibration.c"
    INCLUDE_DIRS "include"
    REQUIRES loadcell_hx711 nvs_store
    PRIV_REQUIRES esp_hw_support
)
