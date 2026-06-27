/*
 * loadcell_hx711.h - HX711-style 24-bit serial load-cell driver (bit-banged).
 *
 * The shipped firmware bit-bangs the HX711 protocol on GPIO18/19. Reads raw
 * 24-bit counts, applies tare offset + scale to produce grams, and converts
 * grams to a pill count using the calibrated per-pill weight.
 *
 * Analog caveats (from the vendor doc, UNSOLVED in software): HX711 supply-
 * voltage sensitivity and mechanical creep. The averaging/settle parameters in
 * board_config.h are the only mitigations and MUST be tuned on hardware.
 */
#ifndef SPB_LOADCELL_HX711_H
#define SPB_LOADCELL_HX711_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

typedef struct {
    float    scale;          /* counts per gram */
    int32_t  offset;         /* raw tare counts */
    float    per_pill_grams; /* learned during calibration */
} loadcell_calib_t;

/* Initialise GPIO + load saved calibration from NVS (if present). */
esp_err_t loadcell_init(void);

/* True once the chip responds (DOUT goes low = ready). */
bool loadcell_is_ready(void);

/* Raw averaged 24-bit reading (sign-extended). */
esp_err_t loadcell_read_raw(int32_t *out);

/* Weight in grams using current calibration. */
esp_err_t loadcell_read_grams(float *out);

/* Pill count (rounded) from grams / per_pill_grams. */
esp_err_t loadcell_read_pill_count(int32_t *out);

/* Tare: set offset to the current raw reading. Retries per board_config. */
esp_err_t loadcell_tare(void);

/* Apply a calibration struct (used by the calibration component). */
void loadcell_set_calibration(const loadcell_calib_t *c);
void loadcell_get_calibration(loadcell_calib_t *c);

#endif /* SPB_LOADCELL_HX711_H */
