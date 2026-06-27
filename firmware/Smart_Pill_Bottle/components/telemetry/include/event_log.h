/*
 * event_log.h - Adherence/tamper event taxonomy + offline SPIFFS log + sync.
 *
 * Reconstructs the structured event dataset from the audit/feature doc. Events
 * are cached to /spiffs/log.bin (and a /spiffs/log.csv mirror) so they survive
 * power loss, and are deleted only after a successful sync ACK.
 */
#ifndef SPB_EVENT_LOG_H
#define SPB_EVENT_LOG_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "esp_err.h"

/* Event taxonomy (image + Feature_Overview.docx). */
typedef enum {
    EVT_VIAL_RESTARTED = 0,      /* Warning: power-on log */
    EVT_PILL_CHANGE,             /* Normal: dose taken */
    EVT_BLE_LOCK_CMD,            /* Normal */
    EVT_BLE_UNLOCK_CMD,          /* Normal */
    EVT_EMERGENCY_UNLOCK,        /* Warning: 5 s physical button */
    EVT_SAFETY_TIMEOUT,          /* Warning: auto safety timeout */
    EVT_MANY_PILLS_CHANGE,       /* Tamper: too many pills removed */
    EVT_OUTSIDE_WINDOW_CHANGE,   /* Tamper: removed outside dosing window */
    EVT_LOW_BATTERY_5,           /* Warning: SoC <= 5% */
    EVT_LOW_BATTERY_2,           /* Warning: SoC <= 2% */
    EVT_MAX
} event_type_t;

/* Event class. */
typedef enum {
    EVT_CLASS_NORMAL = 0,
    EVT_CLASS_TAMPER,
    EVT_CLASS_WARNING,
} event_class_t;

typedef struct {
    int64_t      ts;       /* Unix epoch seconds (RTC set via SET_TIME) */
    event_type_t type;
    int32_t      change;   /* count change (Normal/Tamper only) */
    int32_t      count;    /* current pill count (Normal/Tamper only) */
} event_record_t;

const char  *event_type_name(event_type_t t);
event_class_t event_type_class(event_type_t t);
const char  *event_class_name(event_class_t c);  /* "Normal"/"Tamper"/"Warning" */

/* Initialise SPIFFS + the offline log. */
esp_err_t event_log_init(void);

/*
 * Append an event. Stamps it with the current epoch time, writes it to the
 * SPIFFS log, and -- if Wi-Fi telemetry is configured -- enqueues a signed
 * push (telemetry_enqueue_event). `change`/`count` are ignored for Warning
 * events.
 */
esp_err_t event_log_record(event_type_t type, int32_t change, int32_t count);

/*
 * Serialize the cached log to the BLE SYNC_DATA JSON array form:
 *   [{"ts":..,"type":"Normal","evnt":"PILL_CHANGE","chng":1,"cnt":19}, ...]
 * Caller owns the returned heap buffer (free with event_log_free).
 */
char *event_log_to_sync_json(size_t *out_len);
void  event_log_free(char *buf);

/* Read raw cached log (debug, behind CONFIG_SPB_DEBUG_BUILD). */
esp_err_t event_log_read_raw(char **out, size_t *out_len);

/* Delete the cached log file (after ACK_SYNC, or DELETE_LOG_FILE debug cmd). */
esp_err_t event_log_delete(void);

#endif /* SPB_EVENT_LOG_H */
