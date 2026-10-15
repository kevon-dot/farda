# Navy consumer app

Native Flutter implementation of the [Farda navy Figma design](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=9-225).

The authenticated dashboard uses `ConsumerApiRepository`. `/consumer/demo`, the welcome-screen demo link, or `--dart-define=FARDA_DEMO=true` explicitly selects the in-memory sample repository. A persistent demo label and reset action distinguish sample use. Network and authentication errors never switch into fixtures.

## Included

- Outfit/navy/ivory theme, editable-vector companion asset, four primary tabs, comfortable native touch targets, large-text agenda alternative.
- Today with explicit log, skipped/unconfirmed, note-only entry, correction reason and optimistic-concurrency revision. Opening a reminder, call preview, or vial view never marks taken.
- Interactive calendar with month navigation, date selection, agenda mode, routine/refill filters and user-reported planning events.
- Manual prescription draft → label review → authenticated create with a stable save ID. A failed save leaves the form and values open. Future schedule edits use a separate versioned endpoint.
- Refill planning/contacted/ready/received states, source-labelled last supply count, stale count copy, receipt reconciliation and explicit next-refill planning. Receipt amount is not silently added to inventory.
- Reminder preferences, exact server consent wording/version, verified-number/capability gates, timezone/quiet hours, -10/due/+10 preview, and persistent call opt-out.
- Optional hardware route, honest unavailable status, private support-circle placeholder, and account-scoped logout integration.

## Integration

`ConsumerApp` accepts a repository, `onControllerReady`, an optional stream of routine IDs, and hardware/account callbacks. `ConsumerAppState.openRoutine(id)` refreshes the authenticated record and opens an explicit check-in. The native Live Activity agent owns the platform coordinator and binding; this presentation package does not simulate native delivery.

`ConsumerEntry` requires the companion auth-hardening change exposing `AuthStorage.invalidateToken`. Both transport 401 and logout invalidate only the token that initiated the operation. Logout attempts server revocation, clears the matching local session, and reports an unconfirmed remote revocation.

Adapters target `/api/prescriptions`, `/api/doses`, `/api/reminders`, `/api/refills`, `/api/inventory`, and `/api/auth/sign-out`. Requests refuse redirects, never log bodies or credentials, show approved recovery messages, and keep unknown/zero/stale separate. Backend migrations and service configuration are separate release work.

## Verification and remaining gates

Run `flutter test test/consumer/consumer_contract_test.dart test/consumer/consumer_widget_test.dart`. Tests cover explicit recording, note-only integrity, consent, inventory semantics, API ownership/auth failures, calendar navigation and a 320px handset at 200% text with the actual Outfit font.

The form draft survives a failed request while open; encrypted draft restoration after closing/restarting is not implemented. Companion visibility is a session preference. Sharing invitations, pharmacy submission, camera extraction, and self-service data export/deletion are not enabled by this UI. No real call, pharmacy order, database migration or hardware command is sent by the demo.

Real-device accessibility, iOS entitlements/APNs, consented Twilio delivery, offline delivery behavior, and physical-vial testing remain release gates. The calendar shows occurrence times in the phone timezone and explicitly labels them; saved reminder schedules retain their own IANA timezone.
