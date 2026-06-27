/*
 * ota_update.c - Signed, verified OTA (B4). REFERENCE implementation.
 */
#include "ota_update.h"

#include <string.h>
#include "sdkconfig.h"
#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_app_desc.h"
#include "esp_https_ota.h"
#include "esp_http_client.h"
#include "esp_crt_bundle.h"

static const char *TAG = "ota_update";
static char s_version[64] = {0};

const char *ota_update_running_version(void)
{
    if (s_version[0] == '\0') {
        const esp_app_desc_t *desc = esp_app_get_description();
#ifdef SPB_GIT_REV
        snprintf(s_version, sizeof(s_version), "%s (%s)", desc->version, SPB_GIT_REV);
#else
        snprintf(s_version, sizeof(s_version), "%s", desc->version);
#endif
    }
    return s_version;
}

esp_err_t ota_update_mark_valid(void)
{
    /* Confirm the running image so anti-rollback does not revert it. */
    esp_ota_img_states_t state;
    const esp_partition_t *running = esp_ota_get_running_partition();
    if (esp_ota_get_state_partition(running, &state) == ESP_OK &&
        state == ESP_OTA_IMG_PENDING_VERIFY) {
        return esp_ota_mark_app_valid_cancel_rollback();
    }
    return ESP_OK;
}

esp_err_t ota_update_perform(const char *https_url)
{
    if (!https_url || strncmp(https_url, "https://", 8) != 0) {
        ESP_LOGE(TAG, "Refusing non-HTTPS OTA URL (fail closed).");
        return ESP_ERR_INVALID_ARG; /* B3/B4 */
    }

    esp_http_client_config_t http_cfg = {
        .url = https_url,
        .timeout_ms = 30000,
        .crt_bundle_attach = esp_crt_bundle_attach, /* verify server cert */
        .keep_alive_enable = true,
    };

    esp_https_ota_config_t ota_cfg = {
        .http_config = &http_cfg,
        /* Image signature + anti-rollback are enforced by Secure Boot v2 +
         * CONFIG_APP_ANTI_ROLLBACK; esp_https_ota validates the app
         * descriptor / secure version before swapping the boot partition. */
    };

    ESP_LOGI(TAG, "Starting signed OTA from %s (running %s)",
             https_url, ota_update_running_version());
    esp_err_t err = esp_https_ota(&ota_cfg);
    if (err == ESP_OK) {
        ESP_LOGW(TAG, "OTA succeeded; rebooting into new image.");
        esp_restart();
    }
    ESP_LOGE(TAG, "OTA failed: %s", esp_err_to_name(err));
    return err;
}
