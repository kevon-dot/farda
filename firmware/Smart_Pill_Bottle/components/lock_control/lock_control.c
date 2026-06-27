/*
 * lock_control.c - Solenoid lock state machine + safety interlocks.
 * REFERENCE implementation. Solenoid driver polarity, button wiring and timing
 * MUST be confirmed on hardware (see board_config.h TODOs).
 */
#include "lock_control.h"
#include "board_config.h"
#include "event_log.h"

#include "esp_log.h"
#include "esp_timer.h"
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"

static const char *TAG = "lock_control";

typedef struct {
    lock_state_t  desired;
    lock_source_t src;
} lock_cmd_t;

static QueueHandle_t s_queue = NULL;
static lock_state_t  s_state = LOCK_STATE_LOCKED;
static int64_t       s_last_unlock_us = 0;   /* for 1-min rate limit */
static int64_t       s_unlock_at_us = 0;      /* for 5 s auto re-lock */

static void drive_solenoid(lock_state_t st)
{
    int level = (st == LOCK_STATE_UNLOCKED) ? BOARD_LOCK_ACTIVE_LEVEL
                                            : !BOARD_LOCK_ACTIVE_LEVEL;
    gpio_set_level(BOARD_LOCK_PIN, level);
    ESP_LOGW(TAG, "Lock Status: %s",
             st == LOCK_STATE_UNLOCKED ? "Unlocked" : "Locked");
}

esp_err_t lock_control_init(void)
{
    /* Safe state at boot: locked, solenoid de-energised. Configure output and
     * drive BEFORE anything else can request a change. */
    gpio_config_t lock_io = {
        .pin_bit_mask = 1ULL << BOARD_LOCK_PIN,
        .mode = GPIO_MODE_OUTPUT,
    };
    gpio_config(&lock_io);
    s_state = LOCK_STATE_LOCKED;
    drive_solenoid(LOCK_STATE_LOCKED);

    /* Emergency button input. */
    gpio_config_t btn_io = {
        .pin_bit_mask = 1ULL << BOARD_EMERGENCY_UNLOCK_PIN,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = (BOARD_EMERGENCY_PRESSED_LEVEL == 0) ? GPIO_PULLUP_ENABLE
                                                           : GPIO_PULLUP_DISABLE,
        .pull_down_en = (BOARD_EMERGENCY_PRESSED_LEVEL == 1) ? GPIO_PULLDOWN_ENABLE
                                                             : GPIO_PULLDOWN_DISABLE,
    };
    gpio_config(&btn_io);
    return ESP_OK;
}

lock_state_t lock_control_state(void)
{
    return s_state;
}

esp_err_t lock_control_unlock(lock_source_t src)
{
    int64_t now = esp_timer_get_time();
    /* 1-minute reopen rate limit. Emergency + safety override it. */
    if (src == LOCK_SRC_BLE &&
        s_last_unlock_us != 0 &&
        (now - s_last_unlock_us) < (int64_t)BOARD_LOCK_MIN_REOPEN_INTERVAL_MS * 1000) {
        ESP_LOGE(TAG, "Solenoid Lock rate limit");
        return ESP_ERR_INVALID_STATE;
    }
    lock_cmd_t cmd = { .desired = LOCK_STATE_UNLOCKED, .src = src };
    if (!s_queue || xQueueSend(s_queue, &cmd, pdMS_TO_TICKS(100)) != pdTRUE) {
        return ESP_FAIL;
    }
    return ESP_OK;
}

esp_err_t lock_control_lock(lock_source_t src)
{
    lock_cmd_t cmd = { .desired = LOCK_STATE_LOCKED, .src = src };
    if (!s_queue || xQueueSend(s_queue, &cmd, pdMS_TO_TICKS(100)) != pdTRUE) {
        return ESP_FAIL;
    }
    return ESP_OK;
}

static void apply(const lock_cmd_t *cmd)
{
    if (cmd->desired == LOCK_STATE_UNLOCKED) {
        int64_t now = esp_timer_get_time();
        s_last_unlock_us = now;
        s_unlock_at_us = now;
        s_state = LOCK_STATE_UNLOCKED;
        drive_solenoid(LOCK_STATE_UNLOCKED);
        switch (cmd->src) {
            case LOCK_SRC_BLE:
                ESP_LOGW(TAG, "BLE Unlock Command Received!");
                event_log_record(EVT_BLE_UNLOCK_CMD, 0, 0);
                break;
            case LOCK_SRC_EMERGENCY:
                event_log_record(EVT_EMERGENCY_UNLOCK, 0, 0);
                break;
            default:
                break;
        }
    } else {
        s_state = LOCK_STATE_LOCKED;
        drive_solenoid(LOCK_STATE_LOCKED);
        if (cmd->src == LOCK_SRC_BLE) {
            ESP_LOGW(TAG, "BLE Lock Command Received!");
            event_log_record(EVT_BLE_LOCK_CMD, 0, 0);
        } else if (cmd->src == LOCK_SRC_SAFETY_TIMEOUT) {
            ESP_LOGW(TAG, "Automatically Locked Again!");
            event_log_record(EVT_SAFETY_TIMEOUT, 0, 0);
        } else if (cmd->src == LOCK_SRC_AUTO_RELOCK) {
            ESP_LOGW(TAG, "Automatically Locked Again!");
        }
    }
}

static void lock_task(void *arg)
{
    (void)arg;
    ESP_LOGI(TAG, "Lock Control Task Started!");
    for (;;) {
        lock_cmd_t cmd;
        if (xQueueReceive(s_queue, &cmd, pdMS_TO_TICKS(200)) == pdTRUE) {
            apply(&cmd);
        }
        /* 5 s auto re-lock. */
        if (s_state == LOCK_STATE_UNLOCKED) {
            int64_t now = esp_timer_get_time();
            if ((now - s_unlock_at_us) >= (int64_t)BOARD_LOCK_AUTO_RELOCK_MS * 1000) {
                lock_cmd_t relock = { .desired = LOCK_STATE_LOCKED,
                                      .src = LOCK_SRC_AUTO_RELOCK };
                apply(&relock);
            }
        }
    }
}

static void emergency_task(void *arg)
{
    (void)arg;
    int64_t press_start = 0;
    bool fired = false;
    for (;;) {
        int level = gpio_get_level(BOARD_EMERGENCY_UNLOCK_PIN);
        bool pressed = (level == BOARD_EMERGENCY_PRESSED_LEVEL);
        if (pressed) {
            int64_t now = esp_timer_get_time();
            if (press_start == 0) {
                press_start = now;
                ESP_LOGI(TAG, "Emergency Button Pressed (%lld)!", (long long)now);
            } else if (!fired &&
                       (now - press_start) >= (int64_t)BOARD_EMERGENCY_HOLD_MS * 1000) {
                fired = true;
                lock_control_unlock(LOCK_SRC_EMERGENCY);
            }
        } else {
            if (press_start != 0) {
                ESP_LOGI(TAG, "Emergency Button Released!");
            }
            press_start = 0;
            fired = false;
        }
        vTaskDelay(pdMS_TO_TICKS(BOARD_EMERGENCY_DEBOUNCE_MS));
    }
}

esp_err_t lock_control_start(void)
{
    s_queue = xQueueCreate(8, sizeof(lock_cmd_t));
    if (!s_queue) {
        ESP_LOGE(TAG, "Failed to create lock queue!");
        return ESP_FAIL;
    }
    if (xTaskCreate(lock_task, "lock_task", 4096, NULL, 6, NULL) != pdPASS) {
        return ESP_FAIL;
    }
    if (xTaskCreate(emergency_task, "emergency_task", 3072, NULL, 6, NULL) != pdPASS) {
        return ESP_FAIL;
    }
    return ESP_OK;
}
