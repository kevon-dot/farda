/*
 * wifi_manager.h - STA Wi-Fi with NVS-persisted credentials (reconstructs
 * MB_WiFi/wifi_manager.c). WPA2/WPA3-SAE with PMF, auto-reconnect.
 *
 * SECURITY NOTE (B3/F5): credentials are stored in (encrypted) NVS and MUST
 * NOT be logged. The original firmware logged "Saved WiFi Password: %s" -- this
 * reimplementation never logs the password.
 */
#ifndef SPB_WIFI_MANAGER_H
#define SPB_WIFI_MANAGER_H

#include <stdbool.h>
#include "esp_err.h"

typedef void (*wifi_status_cb_t)(bool connected);

esp_err_t wifi_manager_init(void);

/* Persist new credentials (BLE SET_WIFI_CRED 0x14) and (re)connect. */
esp_err_t wifi_manager_set_credentials(const char *ssid, const char *password);

/* Start the Wi-Fi task using saved credentials (if any). */
esp_err_t wifi_manager_start(void);

bool wifi_manager_is_connected(void);

/* Register a callback fired on connect/disconnect (used to push Wi-Fi status
 * back to the app over BLE). */
void wifi_manager_register_status_cb(wifi_status_cb_t cb);

#endif /* SPB_WIFI_MANAGER_H */
