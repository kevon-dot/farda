/*
 * ota_update.h - Signed, verified OTA over HTTPS (B4).
 *
 * Uses esp_https_ota with image-signature verification and anti-rollback.
 * Requirements (enforced in prod via sdkconfig.defaults.prod):
 *   - HTTPS only (CONFIG_ESP_HTTPS_OTA_ALLOW_HTTP=n)
 *   - server cert verified against the embedded/pinned CA
 *   - app image signature verified (Secure Boot v2 signing)
 *   - secure-version / anti-rollback rejects downgrades + unsigned images
 * Reports the running firmware version + git commit (B5) before/after update.
 */
#ifndef SPB_OTA_UPDATE_H
#define SPB_OTA_UPDATE_H

#include "esp_err.h"

/* Returns the running firmware version string "vX.Y.Z (gitrev)". */
const char *ota_update_running_version(void);

/* Mark the freshly-booted image valid (cancel pending rollback) after self
 * checks pass. Call once early boot validation succeeds. */
esp_err_t ota_update_mark_valid(void);

/*
 * Kick a signed OTA from `https_url`. Rejects non-https URLs and any image
 * that fails signature / anti-rollback verification (fail closed). Reboots on
 * success. Reconstructed at interface level.
 */
esp_err_t ota_update_perform(const char *https_url);

#endif /* SPB_OTA_UPDATE_H */
