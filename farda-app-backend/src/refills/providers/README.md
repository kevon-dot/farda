# Refill provider boundary

`PhotonRefillsProvider` implements the documented Photon Clinical API using
server-held credentials. It is disabled unless explicitly enabled with a client
ID and secret. Sandbox uses Neutron endpoints; production uses Photon endpoints.
URLs are fixed in code and redirects are rejected. No credentials belong in the
mobile app.

Verified on 2026-10-16 against:

- https://docs.photon.health/docs/authentication
- https://docs.photon.health/docs/place-orders
- https://reference.photon.health/

This adapter supports filling an existing, active, eligible Photon prescription.
It cannot turn an OCR label or arbitrary pharmacy Rx number into an electronic
prescription. It does not write prescriptions, perform renewals, or transfer
prescriptions. It requires a trusted server-side patient/prescription/pharmacy
mapping. The Photon patient's `externalId` must equal the local user ID and the
prescription must belong to that patient. A complete address must be present on
the provider patient record. Review the provider medication, exact instructions,
pharmacy and address with the user before requesting an order.

`verifyLink` is a read-only eligibility check, not a guarantee that the pharmacy
will fill a prescription. The orchestration layer must persist consent and an
attempt before `submitOrder`, serialize competing attempts, and independently
validate ownership. All status reads must validate the returned patient,
prescription and external reference against that persisted attempt.

`externalId` is documented as a reference, **not an idempotency key**. The adapter
never retries a mutation. Once a create request could have left the server,
network errors, timeouts, partial GraphQL responses and malformed responses are
reported with `outcome: unknown`. The application must retain that uncertainty
and reconcile; creating another order is unsafe. Even a successful empty lookup
does not prove that an earlier request failed.

Recovery uses authenticated `order(id)` reads or bounded patient-filtered
`orders` pages because the documented order filter has no `externalId` field.
Duplicate correlations or incomplete pagination fail closed. Webhooks are not
accepted by this adapter; adding them requires verified signatures, replay
protection and canonical authenticated status reconciliation.

Raw order and fulfillment states are deliberately separate. A routed order or
`SENT` fulfillment is not pharmacy acceptance. `COMPLETED` alone does not mean
the user picked it up, and no provider event changes the user's inventory count.

## Orchestration contract

The API exposes connector capabilities separately from runtime availability and
prescription eligibility. A configured connector must explicitly support
eligibility verification and order submission before a review can be submitted.
Status refresh also requires order lookup; uncertain submissions additionally
require external-reference reconciliation. If a capability is absent, the API
returns a stable reason code and directs the user to contact the pharmacy.

Every order submission requires a fresh, expiring review of provider-sourced
medication, instructions, pharmacy, delivery address, and remaining fills. The
review is single-use. An idempotency key can replay only the same review and
prescription; it cannot authorize a new provider call. A definite pre-dispatch
failure permits a new review, while any uncertain outcome remains blocked and is
reconciled without resubmission.

Responses include a stable `reasonCode`, deterministic `nextStep`, a
`manualFallback`, and a normalized `latestRequest`. Terminal requests cannot be
refreshed. Provider reads pass through a forward-only state machine, so stale or
unknown reads cannot erase known progress or switch a request between pickup and
shipping paths.

Runtime telemetry contains only the operation, outcome, environment, normalized
status/reason code, and a capped duration. It never includes local or provider
identifiers, medication details, addresses, credentials, raw errors, or response
bodies.

Validation uses mocked fetch responses only. Partner credentials, organization
authorization, real patient mapping, sandbox contract tests, fulfillment status
reconciliation and operational approval are required before enabling live
requests. Tests do not certify a live pharmacy connection.
