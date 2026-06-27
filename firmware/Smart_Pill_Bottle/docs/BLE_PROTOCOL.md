# BLE protocol — reconstructed command table

> **UNVERIFIED REFERENCE.** Reconstructed from
> `reviews/FARDA_FIRMWARE_AUDIT.md`, the BLE protocol PDF, and strings mined
> from `Smart_Pill_Bottle.bin`. The **hardened** frame format (B2) differs from
> the original plaintext `[opcode][32-byte key][params]` scheme; both are shown
> so the mobile app team can migrate.

## GATT layout

- **Advertised name:** `Medical Vial App`
- **Service A:** 16-bit UUID `0x00FF`, characteristic `0xFF01`, descriptor
  `0x3333`; 128-bit base `5f9b349b-0080-8000-0010-0000FF000000`.
- **Service B:** `0x00EE` / `0xEE01` / `0x2222`; base `…0000EE000000`.
- The Flutter app scans on the `00FF` / `00EE` substrings.
- TODO(hardware): confirm exact attribute-table handle layout
  (`BOARD_BLE_NUM_HANDLES`) and 128-bit UUID byte order on a real sniff.

## Link security (B2)

- Pairing **requires LE Secure Connections + MITM + bonding**
  (`ESP_LE_AUTH_REQ_SC_MITM_BOND`). "Just Works" is rejected.
- Privileged characteristics require `WRITE_ENC_MITM` — an unauthenticated link
  cannot even write them. The dispatcher re-checks (defense in depth).

## Original (legacy) frame — DO NOT USE

```
[opcode:1][authKey:32][params...]        # key in cleartext, replayable (F4)
success:  [opcode] ACK
error:    E:<code>,<message>
```

## Hardened frame (this firmware, B2)

```
privileged:  [opcode:1][counter:4 LE][tag:32][params...]
  tag = HMAC-SHA256(per_device_secret, opcode || counter(LE) || params)
  counter MUST strictly increase per link (replay rejected)

bind/login:  [opcode:1][counter:4 LE][tag:32]
  proof-of-possession over the counter using the factory secret

success:  [opcode] ACK
error:    E:<code>,<message>
sync:     SYNC_DATA + JSON array (see §events)
```

## Command table

| Opcode | Name | Auth (hardened) | Notes |
|---|---|---|---|
| `0x10` | LOCK_CMD | HMAC + secure link | `params[0]`: 1=unlock, 0=lock. Unlock honors the 1-min solenoid rate limit. |
| `0x11` | SET_THRESHOLD | HMAC | refill threshold |
| `0x12` | BIND_DEVICE | **PoP** (was none/TOFU) | establishes the bond via factory-secret proof, not first-writer-wins |
| `0x13` | UNBIND_DEVICE | HMAC | unpair |
| `0x14` | SET_WIFI_CRED | HMAC | params = JSON `["SSID","PASSWORD"]`; stored in NVS, never logged |
| `0x15` | SET_COMM_PROT | HMAC | `params[0]`: 0=HTTPS, 1=MQTTS |
| `0x16` | SET_API_TARGET | HMAC | **rejects non-https/mqtts and foreign domains (B3)** |
| `0x20` | START_CALIB | HMAC | tare empty cell, arm |
| `0x21` | ADD_CALIB | HMAC | `params[0]` = known pill count placed |
| `0x22` | FINISH_CALIB | HMAC | persist calibration (MAC-bound) |
| `0x30` | REQUEST_SYNC | HMAC | device returns `SYNC_DATA` + JSON array |
| `0x31` | ACK_SYNC | HMAC | device deletes `/spiffs/log.bin` |
| `0x32` | SET_TIME | HMAC | 4-byte LE Unix epoch |
| `0x33` | READ_LOG_FILE | HMAC + **debug build only** | compiled out unless `CONFIG_SPB_DEBUG_BUILD` (B5) |
| `0x34` | DELETE_LOG_FILE | HMAC | privileged |
| `0xA4` | LOGIN_DEVICE | **PoP** | re-auth on reconnect |
| `0xB4` | SET_PILL_INTERVAL | HMAC | hours, range-checked |
| `0xB5` | SET_PILL_INTERVAL_START | HMAC | interval start hour |
| `0xB6` | SET_SAFETY_TIMEOUT | HMAC | hours, range-checked |
| `0xEF` | ADD_ADMINKEY | **HMAC (was none)** | now requires auth (B2); still write-once (`AdminKey Can't Be Changed`) |

## Events (`SYNC_DATA` JSON array)

Per the feature doc, each record is classed `Normal` / `Tamper` / `Warning`:

```json
[
  {"ts":1769073375,"type":"Normal","evnt":"PILL_CHANGE","chng":1,"cnt":19},
  {"ts":1769073400,"type":"Tamper","evnt":"OUTSIDE_WINDOW_CHANGE","chng":1,"cnt":6},
  {"ts":1769073500,"type":"Warning","evnt":"LOW_BATTERY_5"}
]
```

`chng` / `cnt` are present only on Normal & Tamper events.

| Event | Class |
|---|---|
| VIAL_RESTARTED | Warning |
| PILL_CHANGE | Normal |
| BLE_LOCK_CMD | Normal |
| BLE_UNLOCK_CMD | Normal |
| EMERGENCY_UNLOCK | Warning |
| SAFETY_TIMEOUT | Warning |
| MANY_PILLS_CHANGE | Tamper |
| OUTSIDE_WINDOW_CHANGE | Tamper |
| LOW_BATTERY_5 | Warning |
| LOW_BATTERY_2 | Warning |

## Error codes

Errors use the `E:<code>,<message>` form (image string `E:%d,%s`). Messages
include `Not Authenticated`, `Solenoid Lock rate limit`,
`AdminKey Can't Be Changed`, `Target Rejected (require https/mqtts, allowed
domain)`, `Pill interval not in range`, `Bind PoP Failed`.
