/*
 * battery_monitoring.h - MAX17043 Li-ion fuel gauge over I2C.
 * Drives LOW_BATTERY_5 / LOW_BATTERY_2 events and battery telemetry.
 */
#ifndef SPB_BATTERY_MONITORING_H
#define SPB_BATTERY_MONITORING_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

typedef struct {
    float   voltage;      /* volts */
    uint8_t soc_percent;  /* state of charge 0..100 */
    bool    alert;        /* hardware low-battery alert latched */
} battery_status_t;

/* Initialise I2C + MAX17043 (SDA/SCL/ALERT from board_config). */
esp_err_t battery_monitoring_init(void);

/* Read current voltage + SoC. */
esp_err_t battery_monitoring_read(battery_status_t *out);

/*
 * Start the background monitoring task. Posts LOW_BATTERY_5 / LOW_BATTERY_2
 * events (via the lock/log event queue) when SoC crosses 5% / 2%, and feeds
 * battery readings to telemetry. Edge-triggered: each threshold fires once
 * per crossing.
 */
esp_err_t battery_monitoring_start(void);

#endif /* SPB_BATTERY_MONITORING_H */
