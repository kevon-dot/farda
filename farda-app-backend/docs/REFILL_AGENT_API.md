# Refill agent API contract

The refill agent is a reviewed request workflow for an already trusted provider
mapping. It does not create or renew prescriptions, infer eligibility from label
capture, guarantee pharmacy fulfillment, or change the user's supply ledger.

## Workflow

1. `GET /api/refills/agent/:prescriptionId` verifies ownership, provider
   capability, the trusted mapping, and current provider eligibility.
2. An eligible response contains an expiring review token plus the exact
   provider medication, instructions, pharmacy, address, and fill count.
3. `POST /api/refills/agent/:prescriptionId/submit` accepts only that token,
   `confirmed: true`, and an idempotency key. The durable attempt is reserved
   before the single provider mutation.
4. `POST /api/refills/agent/:prescriptionId/refresh` reads or reconciles the
   recorded attempt. It never submits another order.

All responses are private (`Cache-Control: no-store`). Stable machine fields are
additive to the user-facing text:

- `reasonCode` explains why the current response was returned.
- `nextStep.action` is one of `confirm_and_submit`, `wait`, `refresh_status`,
  `contact_pharmacy`, `collect_refill`, `track_delivery`, `confirm_supply`, or
  `review_again`.
- `manualFallback` always explains the user-controlled pharmacy path. It never
  claims that a provider request was sent.
- `latestRequest.statusCode`, `reasonCode`, and `nextStep` describe a persisted
  request. `outcomeCertain: false` means the caller must not create a new order.
- `provider.capabilities` distinguishes connector support from configuration and
  per-prescription eligibility.

## Retry rules

An idempotent replay with the same key, prescription, and review returns the
recorded attempt without another provider mutation. Reusing the key or review
for a different request is rejected. Authentication or token failures known to
occur before dispatch record `failed`; the user must obtain a new review.
Timeouts, network failures, partial responses, invalid mutation responses, and
process interruption after reservation record or display `unknown`. They remain
blocked even if a bounded lookup finds no match.

Provider status follows a forward-only state machine. Known progress never
regresses to `unknown` or an earlier step. Pickup and shipping paths do not cross,
and terminal states are immutable. Inventory changes only through the separate
user-confirmed receipt endpoint.

When `FARDA_REFILL_RECONCILIATION_WORKER_ENABLED=true`, persisted `submitting`,
`unknown`, and other nonterminal requests are checked in the background. The
worker only calls Photon order lookup APIs; it never calls the order mutation.
Each record has a database lease, attempt count, and next-check timestamp so
multiple processes and restarts do not multiply work. Unchanged, missing, and
failed lookups use exponential backoff from one minute to a six-hour maximum.
Terminal states clear the schedule. A stale `submitting` record becomes
`unknown` and remains blocked from resubmission until Photon confirms an order
or an operator resolves it outside this automated path.

## Manual path and eligibility

`provider_not_configured`, `provider_submission_unsupported`,
`prescription_not_linked`, `prescription_not_eligible`,
`delivery_address_required`, and verification availability failures all return a
manual pharmacy fallback. The pharmacy remains the authority for availability,
early fills, renewals, transfers, payment, pickup, and delivery timing.

## Operational data

Structured refill events include only operation, outcome, environment,
normalized status/reason code, and a duration capped at 30 seconds. Do not add
user IDs, prescription IDs, provider IDs, medication text, addresses,
credentials, raw exceptions, or upstream response bodies.

After five checks without progress, reconciliation emits one
`reconciliation_attention_required` event for that stalled stage. Its attempt
count is bucketed and it contains no request or patient identifiers. Progress
clears the persisted alert marker so a later, separately stalled stage can
produce a new signal. Enable alerting on this event in the deployment telemetry
system; investigate through access-controlled operational tooling rather than
adding identifiers to logs.
