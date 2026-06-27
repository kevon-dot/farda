idf_component_register(
    SRCS "device_identity.c"
    INCLUDE_DIRS "include"
    REQUIRES nvs_store
    PRIV_REQUIRES mbedtls esp_hw_support esp_common
)
