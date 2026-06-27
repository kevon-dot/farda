/*
 * wifi_manager.c - STA Wi-Fi manager (reconstructs MB_WiFi/wifi_manager.c).
 * REFERENCE implementation.
 */
#include "wifi_manager.h"
#include "nvs_store.h"

#include <string.h>
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"

static const char *TAG = "WiFiManager";

#define WIFI_CONNECTED_BIT BIT0

static EventGroupHandle_t s_wifi_events;
static bool s_connected = false;
static wifi_status_cb_t s_status_cb = NULL;

static void event_handler(void *arg, esp_event_base_t base,
                          int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        s_connected = false;
        ESP_LOGW(TAG, ">>> WiFi disconnected!");
        if (s_status_cb) s_status_cb(false);
        esp_wifi_connect(); /* auto-reconnect */
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        s_connected = true;
        ESP_LOGI(TAG, ">>> WiFi connected!");
        xEventGroupSetBits(s_wifi_events, WIFI_CONNECTED_BIT);
        if (s_status_cb) s_status_cb(true);
    }
}

esp_err_t wifi_manager_init(void)
{
    s_wifi_events = xEventGroupCreate();
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        WIFI_EVENT, ESP_EVENT_ANY_ID, &event_handler, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        IP_EVENT, IP_EVENT_STA_GOT_IP, &event_handler, NULL, NULL));

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    return ESP_OK;
}

static esp_err_t apply_config(const char *ssid, const char *password)
{
    wifi_config_t wifi_config = { 0 };
    strncpy((char *)wifi_config.sta.ssid, ssid, sizeof(wifi_config.sta.ssid) - 1);
    strncpy((char *)wifi_config.sta.password, password,
            sizeof(wifi_config.sta.password) - 1);
    /* WPA2/WPA3-SAE with PMF (audit). */
    wifi_config.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;
    wifi_config.sta.pmf_cfg.capable = true;
    wifi_config.sta.pmf_cfg.required = false;
    return esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
}

esp_err_t wifi_manager_set_credentials(const char *ssid, const char *password)
{
    if (!ssid || !password) return ESP_ERR_INVALID_ARG;

    esp_err_t err = nvs_store_set_str(NVS_KEY_WIFI_SSID, ssid);
    if (err == ESP_OK) err = nvs_store_set_str(NVS_KEY_WIFI_PASS, password);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to save WiFi credentials: %s", esp_err_to_name(err));
        return err;
    }
    /* SECURITY: never log the password (B3/F5). */
    ESP_LOGI(TAG, ">>> WiFi credentials saved successfully!");

    apply_config(ssid, password);
    esp_wifi_disconnect();
    esp_wifi_connect();
    return ESP_OK;
}

esp_err_t wifi_manager_start(void)
{
    char ssid[33] = {0}, pass[65] = {0};
    size_t sl = sizeof(ssid), pl = sizeof(pass);
    if (nvs_store_get_str(NVS_KEY_WIFI_SSID, ssid, &sl) != ESP_OK) {
        ESP_LOGW(TAG, " ->  WiFi has No saved config!");
        return ESP_ERR_NOT_FOUND;
    }
    nvs_store_get_str(NVS_KEY_WIFI_PASS, pass, &pl);
    ESP_LOGI(TAG, "Saved WiFi SSID: %s", ssid); /* SSID ok to log; password NOT */
    apply_config(ssid, pass);
    ESP_ERROR_CHECK(esp_wifi_start());
    return ESP_OK;
}

bool wifi_manager_is_connected(void)
{
    return s_connected;
}

void wifi_manager_register_status_cb(wifi_status_cb_t cb)
{
    s_status_cb = cb;
}
