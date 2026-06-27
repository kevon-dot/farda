idf_component_register(
    SRCS "wifi_manager.c"
    INCLUDE_DIRS "include"
    REQUIRES nvs_store esp_wifi esp_event esp_netif
)
