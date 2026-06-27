/*
 * ble_service.c - Bluedroid GATTS server + LE Secure Connections (B2 glue).
 *
 * REFERENCE reconstruction of the GATT layer. The advertised name, service /
 * characteristic / descriptor UUIDs come from board_config.h (matching the
 * image + the Flutter app's 00FF/00EE scan filter). The SMP configuration
 * REQUIRES LE Secure Connections + bonding + MITM protection, and privileged
 * characteristic writes are routed to the hardened dispatcher only after the
 * link is encrypted+authenticated.
 *
 * The full Bluedroid attribute-table wiring is extensive; this file
 * establishes the security posture and the write->dispatch path and leaves the
 * exact attribute table as a documented TODO for hardware bring-up.
 */
#include "ble_service.h"
#include "ble_auth.h"
#include "board_config.h"

#include <string.h>
#include "sdkconfig.h"
#include "esp_log.h"
#include "esp_bt.h"
#include "esp_bt_main.h"
#include "esp_gap_ble_api.h"
#include "esp_gatts_api.h"
#include "esp_gatt_common_api.h"

static const char *TAG = "ble_service";

/* Per-link auth context (single connection device). */
static ble_link_ctx_t s_link;

/* Implemented in ble_dispatch.c */
extern esp_err_t ble_dispatch_handle(ble_link_ctx_t *ctx,
                                      const uint8_t *frame, size_t frame_len,
                                      ble_response_t *out_response);

/* ---- SMP / security: require LE Secure Connections + bonding (B2) -------- */

static void configure_security(void)
{
    esp_ble_auth_req_t auth_req = ESP_LE_AUTH_REQ_SC_MITM_BOND; /* SC + MITM + bond */
    esp_ble_io_cap_t   iocap    = ESP_IO_CAP_OUT;  /* display passkey (PoP path) */
    uint8_t key_size = 16;
    uint8_t init_key = ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK;
    uint8_t rsp_key  = ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK;
    /* Reject "Just Works": require authenticated pairing. */
    uint8_t only_accept_specified_auth = 1;

    esp_ble_gap_set_security_param(ESP_BLE_SM_SET_STATIC_PASSKEY, NULL, 0);
    esp_ble_gap_set_security_param(ESP_BLE_SM_AUTHEN_REQ_MODE, &auth_req, sizeof(auth_req));
    esp_ble_gap_set_security_param(ESP_BLE_SM_IOCAP_MODE, &iocap, sizeof(iocap));
    esp_ble_gap_set_security_param(ESP_BLE_SM_MAX_KEY_SIZE, &key_size, sizeof(key_size));
    esp_ble_gap_set_security_param(ESP_BLE_SM_ONLY_ACCEPT_SPECIFIED_SEC_AUTH,
                                   &only_accept_specified_auth, sizeof(only_accept_specified_auth));
    esp_ble_gap_set_security_param(ESP_BLE_SM_SET_INIT_KEY, &init_key, sizeof(init_key));
    esp_ble_gap_set_security_param(ESP_BLE_SM_SET_RSP_KEY, &rsp_key, sizeof(rsp_key));
}

static void gap_event_handler(esp_gap_ble_cb_event_t event,
                              esp_ble_gap_cb_param_t *param)
{
    switch (event) {
    case ESP_GAP_BLE_ADV_DATA_SET_COMPLETE_EVT:
        /* Begin advertising. TODO(hardware): fill esp_ble_adv_params_t. */
        break;
    case ESP_GAP_BLE_AUTH_CMPL_EVT:
        if (param->ble_security.auth_cmpl.success) {
            ESP_LOGI(TAG, "LE Secure Connections pairing complete (bonded).");
            ble_auth_set_link_secure(&s_link, true);
        } else {
            ESP_LOGW(TAG, "Pairing FAILED (reason 0x%x); link stays untrusted.",
                     param->ble_security.auth_cmpl.fail_reason);
            ble_auth_set_link_secure(&s_link, false);
        }
        break;
    case ESP_GAP_BLE_SEC_REQ_EVT:
        /* Accept the security request -> triggers SC pairing. */
        esp_ble_gap_security_rsp(param->ble_security.ble_req.bd_addr, true);
        break;
    default:
        break;
    }
}

/* ---- GATTS: route privileged writes to the dispatcher -------------------- */

static void gatts_event_handler(esp_gatts_cb_event_t event,
                                esp_gatt_if_t gatts_if,
                                esp_ble_gatts_cb_param_t *param)
{
    switch (event) {
    case ESP_GATTS_REG_EVT:
        /* TODO(hardware): create Service A (0x00FF/0xFF01/0x3333) and
         * Service B (0x00EE/0xEE01/0x2222) attribute tables here, declaring
         * the command characteristic with ESP_GATT_PERM_WRITE_ENC_MITM so the
         * stack itself rejects writes on an unauthenticated link. */
        esp_ble_gap_set_device_name(BOARD_BLE_DEVICE_NAME);
        configure_security();
        break;

    case ESP_GATTS_CONNECT_EVT:
        ble_auth_reset_link(&s_link);
        ESP_LOGI(TAG, "ESP_GATTS_CONNECT_EVT (link untrusted until SC pairing)");
        /* Demand encryption immediately on connect. */
        esp_ble_set_encryption(param->connect.remote_bda,
                               ESP_BLE_SEC_ENCRYPT_MITM);
        break;

    case ESP_GATTS_DISCONNECT_EVT:
        ble_auth_reset_link(&s_link);
        ESP_LOGI(TAG, "ESP_GATTS_DISCONNECT_EVT");
        /* TODO(hardware): restart advertising. */
        break;

    case ESP_GATTS_WRITE_EVT: {
        /* Privileged command path. The link MUST be encrypted+authenticated;
         * the dispatcher re-checks (defense in depth) but the characteristic
         * permission (ENC_MITM) should already have blocked an untrusted
         * write at the stack layer. */
        ble_response_t resp;
        esp_err_t err = ble_dispatch_handle(&s_link, param->write.value,
                                            param->write.len, &resp);
        (void)err;
        if (param->write.need_rsp) {
            esp_ble_gatts_send_response(gatts_if, param->write.conn_id,
                                        param->write.trans_id, ESP_GATT_OK, NULL);
        }
        /* Notify the response back on the characteristic. */
        if (resp.len > 0) {
            esp_ble_gatts_send_indicate(gatts_if, param->write.conn_id,
                                        param->write.handle,
                                        resp.len, resp.data, false);
        }
        break;
    }

#if CONFIG_SPB_DEBUG_BUILD
    /* B5: GATTS DATABASE DUMP only exists in debug builds. */
    case ESP_GATTS_CREATE_EVT:
        ESP_LOGD(TAG, "================= GATTS DATABASE DUMP START =================");
        ESP_LOGD(TAG, "================= GATTS DATABASE DUMP END =================");
        break;
#endif

    default:
        break;
    }
}

esp_err_t ble_service_init(void)
{
    ble_auth_reset_link(&s_link);

    esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_bt_controller_init(&bt_cfg));
    ESP_ERROR_CHECK(esp_bt_controller_enable(ESP_BT_MODE_BLE));
    ESP_ERROR_CHECK(esp_bluedroid_init());
    ESP_ERROR_CHECK(esp_bluedroid_enable());

    ESP_ERROR_CHECK(esp_ble_gap_register_callback(gap_event_handler));
    ESP_ERROR_CHECK(esp_ble_gatts_register_callback(gatts_event_handler));
    ESP_ERROR_CHECK(esp_ble_gatts_app_register(0));
    esp_ble_gatt_set_local_mtu(247);
    return ESP_OK;
}

esp_err_t ble_service_start(void)
{
    /* Advertising is kicked from the GAP/GATTS callbacks once setup completes.
     * TODO(hardware): finalize adv data + params (the app filters on the
     * 00FF / 00EE service UUIDs). */
    ESP_LOGI(TAG, "BLE service started: \"%s\"", BOARD_BLE_DEVICE_NAME);
    return ESP_OK;
}
