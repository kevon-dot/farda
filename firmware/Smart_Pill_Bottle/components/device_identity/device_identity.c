/*
 * device_identity.c - Per-device secret + HMAC-SHA256 signing (B1).
 *
 * REFERENCE implementation. The cryptographic primitives (mbedTLS HMAC-SHA256,
 * esp_random) are real and idiomatic; the NVS key-loading / provisioning glue
 * is faithful at the interface level. Validate on hardware before shipping.
 */
#include "device_identity.h"

#include <string.h>
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_random.h"
#include "mbedtls/md.h"
#include "nvs_store.h"

static const char *TAG = "device_identity";

#define NVS_DEVICE_KEY_NAME  "devKey"

static uint8_t  s_device_key[SPB_DEVICE_KEY_LEN];
static bool     s_provisioned = false;

esp_err_t device_identity_init(void)
{
    size_t len = sizeof(s_device_key);
    /* Load the factory-provisioned per-device secret from (encrypted) NVS.
     * NEVER generate it on-device from the MAC -- that would make it
     * guessable, the exact weakness B1/B2/F3 call out. */
    esp_err_t err = nvs_store_get_blob(NVS_DEVICE_KEY_NAME, s_device_key, &len);
    if (err != ESP_OK || len != SPB_DEVICE_KEY_LEN) {
        ESP_LOGW(TAG, "No per-device secret provisioned (fail closed). "
                      "See docs/PROVISIONING.md.");
        s_provisioned = false;
        return ESP_ERR_NOT_FOUND;
    }
    s_provisioned = true;
    ESP_LOGI(TAG, "Per-device identity loaded (key length %u).", (unsigned)len);
    return ESP_OK;
}

bool device_identity_is_provisioned(void)
{
    return s_provisioned;
}

esp_err_t device_identity_get_id(char *out, size_t out_len)
{
    if (out_len < SPB_DEVICE_ID_LEN) {
        return ESP_ERR_INVALID_SIZE;
    }
    uint8_t mac[6];
    esp_err_t err = esp_read_mac(mac, ESP_MAC_WIFI_STA);
    if (err != ESP_OK) {
        return err;
    }
    device_identity_hex(mac, sizeof(mac), out, out_len);
    return ESP_OK;
}

esp_err_t device_identity_random_nonce(uint8_t *out, size_t len)
{
    if (!out || len == 0) {
        return ESP_ERR_INVALID_ARG;
    }
    /* esp_random() is the hardware RNG (TRNG when RF is active). */
    esp_fill_random(out, len);
    return ESP_OK;
}

void device_identity_hex(const uint8_t *in, size_t in_len, char *out, size_t out_len)
{
    static const char hexd[] = "0123456789abcdef";
    size_t i;
    for (i = 0; i < in_len && (2 * i + 1) < out_len; i++) {
        out[2 * i]     = hexd[(in[i] >> 4) & 0xF];
        out[2 * i + 1] = hexd[in[i] & 0xF];
    }
    if (out_len > 2 * in_len) {
        out[2 * in_len] = '\0';
    } else if (out_len > 0) {
        out[out_len - 1] = '\0';
    }
}

esp_err_t device_identity_sign(const uint8_t *body, size_t body_len,
                               const uint8_t *nonce, size_t nonce_len,
                               int64_t timestamp,
                               uint8_t out_mac[SPB_HMAC_LEN])
{
    if (!s_provisioned) {
        return ESP_ERR_INVALID_STATE; /* fail closed: never sign with no key */
    }

    const mbedtls_md_info_t *md = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    if (!md) {
        return ESP_FAIL;
    }

    mbedtls_md_context_t ctx;
    mbedtls_md_init(&ctx);
    int rc = mbedtls_md_setup(&ctx, md, 1 /* HMAC */);
    if (rc != 0) { mbedtls_md_free(&ctx); return ESP_FAIL; }

    rc = mbedtls_md_hmac_starts(&ctx, s_device_key, sizeof(s_device_key));
    if (rc != 0) { mbedtls_md_free(&ctx); return ESP_FAIL; }

    /* Canonical signing input (see docs/WIRE_FORMAT.md):
     *   body || '\n' || lowercase_hex(nonce) || '\n' || decimal(timestamp)
     * Hex-encode the nonce so the wire form and the signing form match byte
     * for byte. */
    char nonce_hex[2 * SPB_NONCE_LEN + 1];
    device_identity_hex(nonce, nonce_len, nonce_hex, sizeof(nonce_hex));

    char ts_dec[24];
    int ts_len = snprintf(ts_dec, sizeof(ts_dec), "%lld", (long long)timestamp);
    const uint8_t sep = (uint8_t)'\n';

    rc |= mbedtls_md_hmac_update(&ctx, body, body_len);
    rc |= mbedtls_md_hmac_update(&ctx, &sep, 1);
    rc |= mbedtls_md_hmac_update(&ctx, (const uint8_t *)nonce_hex, strlen(nonce_hex));
    rc |= mbedtls_md_hmac_update(&ctx, &sep, 1);
    rc |= mbedtls_md_hmac_update(&ctx, (const uint8_t *)ts_dec, (size_t)ts_len);
    if (rc != 0) { mbedtls_md_free(&ctx); return ESP_FAIL; }

    rc = mbedtls_md_hmac_finish(&ctx, out_mac);
    mbedtls_md_free(&ctx);
    return rc == 0 ? ESP_OK : ESP_FAIL;
}

bool device_identity_ct_equal(const uint8_t *a, const uint8_t *b, size_t len)
{
    /* Constant-time: never short-circuit (F8 fix). */
    uint8_t diff = 0;
    for (size_t i = 0; i < len; i++) {
        diff |= (uint8_t)(a[i] ^ b[i]);
    }
    return diff == 0;
}
