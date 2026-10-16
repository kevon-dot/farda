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

Validation uses mocked fetch responses only. Partner credentials, organization
authorization, real patient mapping, sandbox contract tests, fulfillment status
reconciliation and operational approval are required before enabling live
requests. Tests do not certify a live pharmacy connection.
