/*
 * event_log.c - Event taxonomy + SPIFFS offline log + sync serialization.
 * REFERENCE implementation.
 */
#include "event_log.h"
#include "telemetry.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <inttypes.h>
#include "esp_log.h"
#include "esp_spiffs.h"

static const char *TAG = "event_log";

#define LOG_BIN_PATH  "/spiffs/log.bin"
#define LOG_CSV_PATH  "/spiffs/log.csv"

static const char *kNames[EVT_MAX] = {
    [EVT_VIAL_RESTARTED]      = "VIAL_RESTARTED",
    [EVT_PILL_CHANGE]         = "PILL_CHANGE",
    [EVT_BLE_LOCK_CMD]        = "BLE_LOCK_CMD",
    [EVT_BLE_UNLOCK_CMD]      = "BLE_UNLOCK_CMD",
    [EVT_EMERGENCY_UNLOCK]    = "EMERGENCY_UNLOCK",
    [EVT_SAFETY_TIMEOUT]      = "SAFETY_TIMEOUT",
    [EVT_MANY_PILLS_CHANGE]   = "MANY_PILLS_CHANGE",
    [EVT_OUTSIDE_WINDOW_CHANGE]= "OUTSIDE_WINDOW_CHANGE",
    [EVT_LOW_BATTERY_5]       = "LOW_BATTERY_5",
    [EVT_LOW_BATTERY_2]       = "LOW_BATTERY_2",
};

const char *event_type_name(event_type_t t)
{
    return (t < EVT_MAX && kNames[t]) ? kNames[t] : "UNKNOWN";
}

event_class_t event_type_class(event_type_t t)
{
    switch (t) {
        case EVT_PILL_CHANGE:
        case EVT_BLE_LOCK_CMD:
        case EVT_BLE_UNLOCK_CMD:
            return EVT_CLASS_NORMAL;
        case EVT_MANY_PILLS_CHANGE:
        case EVT_OUTSIDE_WINDOW_CHANGE:
            return EVT_CLASS_TAMPER;
        default:
            return EVT_CLASS_WARNING;
    }
}

const char *event_class_name(event_class_t c)
{
    switch (c) {
        case EVT_CLASS_NORMAL:  return "Normal";
        case EVT_CLASS_TAMPER:  return "Tamper";
        default:                return "Warning";
    }
}

esp_err_t event_log_init(void)
{
    ESP_LOGI(TAG, "Initializing SPIFFS...");
    esp_vfs_spiffs_conf_t conf = {
        .base_path = "/spiffs",
        .partition_label = NULL,
        .max_files = 5,
        .format_if_mount_failed = true,
    };
    esp_err_t err = esp_vfs_spiffs_register(&conf);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize SPIFFS (%s)", esp_err_to_name(err));
        return err;
    }
    size_t total = 0, used = 0;
    if (esp_spiffs_info(NULL, &total, &used) == ESP_OK) {
        ESP_LOGI(TAG, "SPIFFS total: %d bytes, used: %d bytes", (int)total, (int)used);
    }
    return ESP_OK;
}

esp_err_t event_log_record(event_type_t type, int32_t change, int32_t count)
{
    event_record_t rec = {
        .ts = (int64_t)time(NULL),
        .type = type,
        .change = change,
        .count = count,
    };

    /* Append binary record to the persistent log. */
    FILE *f = fopen(LOG_BIN_PATH, "ab");
    if (f) {
        fwrite(&rec, sizeof(rec), 1, f);
        fclose(f);
    } else {
        ESP_LOGE(TAG, "Failed to open %s", LOG_BIN_PATH);
    }

    /* Mirror to CSV for human inspection. */
    FILE *c = fopen(LOG_CSV_PATH, "a");
    if (c) {
        event_class_t cls = event_type_class(type);
        fprintf(c, "%" PRId64 ",%s,%s,%" PRId32 ",%" PRId32 "\n",
                rec.ts, event_class_name(cls), event_type_name(type),
                rec.change, rec.count);
        fclose(c);
    }

    ESP_LOGI(TAG, "Event Type:   %s", event_type_name(type));

    /* Best-effort signed network push (offline-tolerant: the SPIFFS copy
     * above is the durable record; this enqueue is fire-and-forget). */
    (void)telemetry_enqueue_event(&rec);
    return ESP_OK;
}

char *event_log_to_sync_json(size_t *out_len)
{
    FILE *f = fopen(LOG_BIN_PATH, "rb");
    if (!f) {
        ESP_LOGW(TAG, "No log.bin found.");
        char *empty = strdup("[]");
        if (out_len) *out_len = empty ? 2 : 0;
        return empty;
    }

    /* Bounded buffer; grow as needed. */
    size_t cap = 1024, len = 0;
    char *buf = malloc(cap);
    if (!buf) { fclose(f); return NULL; }
    buf[len++] = '[';

    event_record_t rec;
    bool first = true;
    while (fread(&rec, sizeof(rec), 1, f) == 1) {
        char item[192];
        event_class_t cls = event_type_class(rec.type);
        int n;
        if (cls == EVT_CLASS_WARNING) {
            n = snprintf(item, sizeof(item),
                "%s{\"ts\":%" PRId64 ",\"type\":\"%s\",\"evnt\":\"%s\"}",
                first ? "" : ",", rec.ts, event_class_name(cls),
                event_type_name(rec.type));
        } else {
            n = snprintf(item, sizeof(item),
                "%s{\"ts\":%" PRId64 ",\"type\":\"%s\",\"evnt\":\"%s\","
                "\"chng\":%" PRId32 ",\"cnt\":%" PRId32 "}",
                first ? "" : ",", rec.ts, event_class_name(cls),
                event_type_name(rec.type), rec.change, rec.count);
        }
        if (n < 0) continue;
        if (len + (size_t)n + 2 > cap) {
            cap = (len + n + 2) * 2;
            char *nb = realloc(buf, cap);
            if (!nb) { free(buf); fclose(f); return NULL; }
            buf = nb;
        }
        memcpy(buf + len, item, n);
        len += n;
        first = false;
    }
    fclose(f);
    buf[len++] = ']';
    buf[len] = '\0';
    if (out_len) *out_len = len;
    return buf;
}

void event_log_free(char *buf)
{
    free(buf);
}

esp_err_t event_log_read_raw(char **out, size_t *out_len)
{
    FILE *f = fopen(LOG_CSV_PATH, "r");
    if (!f) {
        ESP_LOGW(TAG, "No log.csv found.");
        return ESP_ERR_NOT_FOUND;
    }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz < 0) { fclose(f); return ESP_FAIL; }
    char *buf = malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return ESP_ERR_NO_MEM; }
    size_t rd = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    buf[rd] = '\0';
    *out = buf;
    if (out_len) *out_len = rd;
    return ESP_OK;
}

esp_err_t event_log_delete(void)
{
    int r1 = remove(LOG_BIN_PATH);
    int r2 = remove(LOG_CSV_PATH);
    if (r1 != 0 && r2 != 0) {
        ESP_LOGW(TAG, "Can't delete log file");
    }
    return ESP_OK;
}
