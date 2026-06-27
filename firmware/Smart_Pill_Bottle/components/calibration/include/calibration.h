/*
 * calibration.h - Single-point load-cell calibration by pill weight.
 *
 * Flow (BLE 0x20/0x21/0x22 START/ADD/FINISH_CALIB):
 *   1. START: tare the empty cell, arm the calibration task.
 *   2. ADD:   user places a known number of pills; capture the delta and
 *             derive counts-per-gram + per-pill weight.
 *   3. FINISH: persist calibration to NVS, bound to the device MAC (anti-
 *             transfer integrity check -- "calibration data MAC check failed").
 *
 * Single-point is deliberate (the vendor verified the cell is linear enough).
 */
#ifndef SPB_CALIBRATION_H
#define SPB_CALIBRATION_H

#include <stdint.h>
#include "esp_err.h"

esp_err_t calibration_init(void);

/* 0x20 START_CALIB: tare + arm. */
esp_err_t calibration_start(void);

/* 0x21 ADD_CALIB: `known_pills` are now on the cell; compute scale. */
esp_err_t calibration_add(int known_pills);

/* 0x22 FINISH_CALIB: persist (MAC-bound) to NVS. */
esp_err_t calibration_finish(void);

/* True if a valid, MAC-matched calibration is loaded. */
bool calibration_is_valid(void);

#endif /* SPB_CALIBRATION_H */
