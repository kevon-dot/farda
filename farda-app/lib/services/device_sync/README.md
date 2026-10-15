# Device sync and mobile session boundary

This is a tested software boundary for the upcoming hardware integration. It does not establish a verified pairing or a reliable hardware delivery contract.

## Session and API behavior

- `AuthStorage.saveSession(access: token, id: userId)` writes one protected platform record. `getToken`, `getSession` and `readSession` all read that record. Credentials are never duplicated into preferences.
- Legacy plaintext tokens are removed and require a new login. `saveToken` only renews an existing complete session; new login must save the token and user ID together.
- `AuthStorage.clear()` blocks further local authorization, persists a revocation marker, and purges `farda.private.*` records. Cleanup failures propagate. Do not present a successful logout if protected storage fails.
- `AuthStorage.invalidateToken(token)` atomically rejects only the still-current failed token. A delayed 401 from an earlier account cannot sign out a newer one.
- Same-user token renewal preserves queued observations. Account switching, explicit logout and current-session revocation clear private local observations; device copies are retained because this implementation never sends deletion ACKs. Pending manual-only drafts need an explicit consumer warning before voluntary logout if the new UI stores them locally.
- Configure HTTPS roots ending in `/api` using `BASE_API_URL` and `VIAL_API_URL` dart defines. Optional dotenv values use the same validation. No private-IP fallback or credentials in URLs.
- API diagnostics allow only fixed event codes, method and numeric status. Request/response bodies, user/device paths, query values, tokens and exception strings are excluded. Release logging is disabled at this boundary.

## Integration points

```dart
final outbox = DeviceOutbox(AuthStorage.sessionStore);
final uploader = HttpObservationUploader(
  client: httpClient,
  apiRoot: vialBaseUrl,
  sessions: AuthStorage.sessionStore,
);
final sync = DeviceOutboxSync(outbox, uploader);
await sync.flush(authenticatedUserId);
```

Use an authenticated account ID, not a device-supplied identity. Close the injected HTTP client when the application service is disposed. A retry worker may call `flush` at app resume, after connectivity recovery or an explicit sync; callers must expose offline/error status and must not infer that an arbitrary mobile background loop will continue indefinitely.

The phone endpoint is `POST /api/user/devices/:device_id/observations`. A raw observation requires `event_id`, `ownership_epoch`, `boot_id`, integer `sequence`, `event`, integer Unix-second `timestamp`, and bounded `payload`. Device ID is part of the local record and URL. Queue admission rejects clocks more than 300 seconds in the future. BLE receive also requires the verified claim time and rejects observations predating that ownership period. Stored timestamps are never rewritten when the phone clock changes. The server authenticates ownership and labels the evidence `phone_ble`/`vial_observation`; a phone upload does not authenticate the physical sensor.

Receipt removal requires `status: stored|duplicate`, `evidence_type: vial_observation`, and a `receipt` with `committed: true` and matching event ID, device ID, ownership epoch, boot ID and sequence. A 2xx response alone is insufficient.

The outbox is account-scoped, serialized with account changes and protected by platform secure storage. It holds at most 256 observations/512 KiB; it rejects overflow and corrupt state rather than evicting evidence. Payloads are at most 4 KiB. Retrying after a crash between server commit and local receipt removal is safe only if the server preserves its stable identity/duplicate-content contract. This is not a claim of exactly-once device delivery.

## Hardware gate

`BleSyncCodec` consumes the documented `SYNC_DATA` + JSON-array framing. It buffers bytes through UTF-8 fragmentation, scans incrementally, bounds frame size/event count/nesting, and rejects malformed or trailing content. `BleSyncService` owns notification subscription, timeout and cleanup outside widgets. `GattBleTransport` requires an exact service/write/notify UUID mapping and acknowledged writes; it never chooses a characteristic by substring or arbitrary properties.

The current firmware PDF only supplies legacy `ts/type/evnt/chng/cnt` records and says `0x31` deletes the entire log file. It does not define stable event IDs, boot/ownership epochs, a deletion range or concurrent-event safety. Consequently:

1. Legacy observations without stable identity are rejected and retained on the vial.
2. No code path in this service emits `0x31`, even after server commit.
3. No binding key is generated, guessed or shared by the app; `receive` requires a provisioned 32-byte key supplied by a verified enrollment service.
4. The legacy setup screen offers a manual-app continuation. It cannot claim a vial from a typed ID or a platform BLE address.

Enable real pairing/sync only after vendor source/provisioning and an exact GATT role map are supplied; implement authenticated physical proof; agree on versioned stable identities and scoped deletion; then validate interrupted sync, duplicate/reordered batches, events created during ACK, account transfer, low battery and restart on real units. None of these hardware tests has run here.

## Verification

Run `flutter test test/infrastructure/device_sync_test.dart`. Tests use synthetic frames, an in-memory secure-store adapter and mocked HTTP; no device or real API is contacted. They exercise account switching/revocation races, queue persistence/replay, capacity/corruption/write failures, exact receipts, zero battery, fragmented UTF-8, bounds/timeouts, wrong-device rejection, notification cleanup, and absence of destructive ACKs. Platform encryption durability, app kill/restart on phones and real server persistence remain integration gates.
