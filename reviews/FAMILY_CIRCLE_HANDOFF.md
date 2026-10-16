# Family Circle handoff

Family Circle is a read-only support feature. A member can view only the routine fields the account owner explicitly shares; a member cannot record, skip, snooze, edit, dispense, or change reminders.

## API

All routes require the canonical bearer session.

- `GET /api/circle` — owner members and anonymous pending invitations.
- `POST /api/circle/invitations` — create or replace a seven-day invitation for an E.164 phone and return a one-time share code. Farda does not claim this sends a message.
- `GET /api/circle/invitations` — pending invitations for the signed-in user's verified phone.
- `POST /api/circle/invitations/:id/accept` — accept with the share code.
- `DELETE /api/circle/invitations/:id` — owner cancellation.
- `DELETE /api/circle/invitations/:id/received` — recipient decline.
- `PATCH /api/circle/members/:id` — owner changes `doseStatus` and `reminders`; both false pauses all access.
- `DELETE /api/circle/members/:id` — owner revocation.
- `GET /api/circle/shared-with-me` — accepted shares for a recipient.
- `GET /api/circle/shared-with-me/:id/routine?from=...&to=...` — scoped, read-only routine window, at most 32 days.
- `DELETE /api/circle/shared-with-me/:id` — recipient leaves.

Invitation creation requires at least one permission. An owner may later pause both. Re-inviting replaces the previous secret. Acceptance, permission changes, revocation, and leaving invalidate matching pending invitations so an old code cannot restore access.

## Data and privacy

Migration `20261016120000_circle_sharing` adds `CircleInvitation` and `CircleGrant`. Grants support multiple family members and work without a smart vial.

Phone lookup uses a domain-separated HMAC with `CIRCLE_PHONE_HASH_SECRET`, or `BETTER_AUTH_SECRET` when the dedicated value is absent. Production fails closed unless the selected secret is at least 32 characters. Rotating it invalidates pending phone-bound invitations; accepted grants remain valid.

Pending owner views show only the last four phone digits and never disclose whether an account exists. Discovery, acceptance, and decline require the intended verified phone. Shared routine responses exclude medication names, directions, Rx numbers, pharmacy/contact/address, mood, and notes. Scheduled times are plans, not proof that a notification was delivered. `not_recorded` does not mean missed. `device_observation` is separate from `self_report` and never claims a pill was swallowed.

Routine reads use an explicit absolute half-open date range, exclude cancelled occurrences and archived prescriptions, and cap results at 500. The current Flutter day picker requests the viewer's local day and labels it accordingly; each shared reminder includes the owner's schedule timezone for context. A database row lock serializes reads with permission changes and revocation.

## Deployment and validation

Apply the Prisma migration before deploying the API. The invite endpoint uses the shared database rate limiter (10 attempts per 15-minute bucket per signed-in user). There is no SMS/email provider integration; the UI copies a one-time code for the owner to share.

Local validation: TypeScript typecheck passed; 212 backend tests passed. The complete Flutter suite passed 264/264, including four focused Circle HTTP adapter/DTO contracts covering invitation codes, anonymous phone labels, shared-access mapping, routine evidence/scopes, and account-switch rejection. Flutter analyzer reported no warnings or errors; remaining messages were baseline informational diagnostics. Forty-two PostgreSQL tests were skipped because `TEST_DATABASE_URL` was unavailable, including five Circle database cases. Run the complete database suite against a disposable PostgreSQL instance before merge and verify the migration on a production-like snapshot. This implementation is locally verified and awaiting exact-head CI; it is not merged, deployed, or live.
