idf_component_register(
    SRCS "ota_update.c"
    INCLUDE_DIRS "include"
    REQUIRES app_update esp_https_ota esp_http_client esp-tls
)
