/*
 * lock_control.h - Solenoid lock state machine with safety interlocks.
 *
 * Interlocks (Feature_Overview.docx + image):
 *   - GPIO held inactive through boot (solenoid never actuates at boot).
 *   - Cannot reopen if < 1 minute since last opening ("Solenoid Lock rate
 *     limit").
 *   - Auto re-locks 5 s after an unlock.
 *   - SAFETY_TIMEOUT auto-event.
 *   - Emergency physical button (GPIO4), 5-second hold.
 */
#ifndef SPB_LOCK_CONTROL_H
#define SPB_LOCK_CONTROL_H

#include <stdbool.h>
#include "esp_err.h"

typedef enum {
    LOCK_STATE_LOCKED = 0,
    LOCK_STATE_UNLOCKED,
} lock_state_t;

typedef enum {
    LOCK_SRC_BLE = 0,        /* BLE LOCK_CMD 0x10 */
    LOCK_SRC_EMERGENCY,      /* physical button */
    LOCK_SRC_SAFETY_TIMEOUT, /* auto */
    LOCK_SRC_AUTO_RELOCK,    /* 5 s auto re-lock */
} lock_source_t;

esp_err_t lock_control_init(void);

/* Start the lock task + emergency-button monitor. */
esp_err_t lock_control_start(void);

/*
 * Request unlock. Enforces the 1-minute rate limit. Returns
 * ESP_ERR_INVALID_STATE (and logs "Solenoid Lock rate limit") if blocked.
 * Logs BLE_UNLOCK_CMD / EMERGENCY_UNLOCK as appropriate.
 */
esp_err_t lock_control_unlock(lock_source_t src);

/* Request lock. Logs BLE_LOCK_CMD when src == BLE. */
esp_err_t lock_control_lock(lock_source_t src);

lock_state_t lock_control_state(void);

#endif /* SPB_LOCK_CONTROL_H */
