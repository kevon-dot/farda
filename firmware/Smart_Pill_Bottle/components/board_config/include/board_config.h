/*
 * board_config.h - Farda Smart Pill Bottle hardware abstraction (REFERENCE).
 *
 * SINGLE SOURCE OF TRUTH for every hardware-specific unknown in this
 * reconstruction: GPIO pin map, HX711 scale/offset calibration, dose-weight
 * thresholds, debounce/timers, BLE handle/UUID layout, backend domain
 * allow-list.
 *
 * !!! UNVERIFIED !!! Every value tagged `TODO(hardware): confirm on real unit`
 * is a SAFE PLACEHOLDER reconstructed from the audit + vendor docs, NOT a
 * measured value. They MUST be confirmed/tuned on a real device during
 * hardware bring-up before flashing. Pin assignments come from the flashing
 * doc (ESP32-WROOM-32D rev v3.1) and are higher-confidence; calibration and
 * weight thresholds are placeholders and WILL be wrong on real hardware.
 */
#ifndef SPB_BOARD_CONFIG_H
#define SPB_BOARD_CONFIG_H

#include "driver/gpio.h"
#include "driver/i2c.h"

/* ----------------------------------------------------------------------------
 * GPIO pin map  (from Flashing_Instructions.docx, corroborated by image)
 * ------------------------------------------------------------------------- */
#define BOARD_LOCK_PIN            GPIO_NUM_5   /* Solenoid lock; safe/inactive at boot */
#define BOARD_I2C_SDA_PIN         GPIO_NUM_21  /* MAX17043 fuel gauge SDA */
#define BOARD_I2C_SCL_PIN         GPIO_NUM_22  /* MAX17043 fuel gauge SCL */
#define BOARD_BAT_ALRT_PIN        GPIO_NUM_23  /* MAX17043 low-battery alert IRQ */
#define BOARD_LC_DOUT_PIN         GPIO_NUM_19  /* HX711-style load-cell data */
#define BOARD_LC_SCK_PIN          GPIO_NUM_18  /* HX711-style load-cell clock */
#define BOARD_EMERGENCY_UNLOCK_PIN GPIO_NUM_4  /* Recessed button, 5 s hold */

/* I2C bus for the battery fuel gauge */
#define BOARD_I2C_PORT            I2C_NUM_0
#define BOARD_I2C_FREQ_HZ         100000       /* TODO(hardware): confirm; 100 kHz is safe default */
#define BOARD_MAX17043_ADDR       0x36         /* MAX17043 7-bit I2C address */

/* ----------------------------------------------------------------------------
 * Solenoid lock safety timing  (from Feature_Overview.docx)
 * ------------------------------------------------------------------------- */
/* Cannot reopen if <1 minute since the last opening (rate limit / "Solenoid
 * Lock rate limit"). */
#define BOARD_LOCK_MIN_REOPEN_INTERVAL_MS   (60 * 1000)
/* Auto re-lock 5 s after an unlock. */
#define BOARD_LOCK_AUTO_RELOCK_MS           (5 * 1000)
/* Active level that energises the solenoid to UNLOCK.
 * TODO(hardware): confirm driver polarity on the real board. Wrong value =
 * lock behaves inverted. Placeholder assumes active-high = unlocked. */
#define BOARD_LOCK_ACTIVE_LEVEL             1

/* Emergency button: held LOW or HIGH when pressed?
 * TODO(hardware): confirm button wiring (pull-up vs pull-down). Placeholder
 * assumes active-low (pressed == 0) with internal pull-up. */
#define BOARD_EMERGENCY_PRESSED_LEVEL       0
#define BOARD_EMERGENCY_HOLD_MS             (5 * 1000)
#define BOARD_EMERGENCY_DEBOUNCE_MS         50   /* TODO(hardware): confirm */

/* ----------------------------------------------------------------------------
 * HX711 load-cell calibration + dose detection  (ALL PLACEHOLDERS)
 * ------------------------------------------------------------------------- */
/* HX711 gain channel-A=128 (typical). TODO(hardware): confirm wiring/channel. */
#define BOARD_HX711_GAIN                    128

/* Single-point calibration: scale (counts per gram) + tare offset (raw counts).
 * The shipped firmware calibrates directly by pill weight (Feature_Overview).
 * These two values are loaded from NVS after a calibration run; the defaults
 * below are ONLY used before the first calibration and are intentionally
 * obviously-wrong sentinels.
 * TODO(hardware): determine on a real load cell. */
#define BOARD_HX711_DEFAULT_SCALE           1.0f    /* counts per gram - PLACEHOLDER */
#define BOARD_HX711_DEFAULT_OFFSET          0L      /* raw tare - PLACEHOLDER */

/* Per-pill weight (grams) is learned during calibration. This is the floor
 * used to reject noise. TODO(hardware): set from the target medication. */
#define BOARD_MIN_PILL_WEIGHT_G             0.05f   /* PLACEHOLDER */

/* Weight delta (in "pill units") above which a removal is flagged as a
 * MANY_PILLS_CHANGE tamper event. TODO(hardware): tune. */
#define BOARD_MANY_PILLS_THRESHOLD          3

/* Settle/averaging for a reading, to fight HX711 voltage sensitivity and
 * mechanical creep (both called out as unsolved analog caveats in the vendor
 * doc). TODO(hardware): tune sample count + settle window empirically. */
#define BOARD_LC_SAMPLE_COUNT               16
#define BOARD_LC_SETTLE_MS                  400
#define BOARD_LC_CREEP_GUARD_MS             2000  /* ignore upward drift within this window */

/* Taring retry budget ("Loadcell taring failed after retries"). */
#define BOARD_LC_TARE_RETRIES               5

/* ----------------------------------------------------------------------------
 * Dose window / config defaults  (overridable via BLE, persisted in NVS)
 * ------------------------------------------------------------------------- */
#define BOARD_DEFAULT_PILL_INTERVAL_HOURS       8    /* SET_PILL_INTERVAL 0xB4 */
#define BOARD_PILL_INTERVAL_MIN_HOURS           1
#define BOARD_PILL_INTERVAL_MAX_HOURS           24   /* TODO(hardware): confirm range */
#define BOARD_DEFAULT_SAFETY_TIMEOUT_HOURS      12   /* SET_SAFETY_TIMEOUT 0xB6 */
#define BOARD_SAFETY_TIMEOUT_MIN_HOURS          1
#define BOARD_SAFETY_TIMEOUT_MAX_HOURS          72   /* TODO(hardware): confirm range */
#define BOARD_DEFAULT_REFILL_THRESHOLD          5    /* SET_THRESHOLD 0x11 */

/* ----------------------------------------------------------------------------
 * BLE GATT layout  (from BLE_Communication_Protocol.pdf + image)
 * ------------------------------------------------------------------------- */
#define BOARD_BLE_DEVICE_NAME      "Medical Vial App"

/* Service A */
#define BOARD_BLE_SVC_A_UUID16     0x00FF
#define BOARD_BLE_CHR_A_UUID16     0xFF01
#define BOARD_BLE_DSC_A_UUID16     0x3333
/* Service B */
#define BOARD_BLE_SVC_B_UUID16     0x00EE
#define BOARD_BLE_CHR_B_UUID16     0xEE01
#define BOARD_BLE_DSC_B_UUID16     0x2222
/* 128-bit base UUIDs (audit). TODO(hardware): confirm exact byte order on a
 * sniffed advertisement; the app filters on the 00FF / 00EE substrings. */
/* 5f9b349b-0080-8000-0010-0000FF000000 (service A base) */
/* 5f9b349b-0080-8000-0010-0000EE000000 (service B base) */

/* Number of GATT handles to reserve per service. TODO(hardware): confirm
 * against the real attribute table layout. */
#define BOARD_BLE_NUM_HANDLES      8

/* ----------------------------------------------------------------------------
 * Backend domain allow-list  (B3: restrict SET_API_TARGET to our own domains)
 * ------------------------------------------------------------------------- */
/* Only hosts ending in one of these suffixes are accepted by SET_API_TARGET
 * when CONFIG_SPB_RESTRICT_API_DOMAIN is set. TODO(deployment): set to the
 * real Farda / smart-vial backend domain(s). */
#define BOARD_ALLOWED_API_DOMAIN_SUFFIXES { ".tryfarda.com", ".farda.health" }

/* MQTT topic templates (from image): publish events, subscribe commands. */
#define BOARD_MQTT_TOPIC_EVENTS_FMT    "vials/%s/events/up"
#define BOARD_MQTT_TOPIC_COMMANDS_FMT  "vials/%s/commands/down"

#endif /* SPB_BOARD_CONFIG_H */
