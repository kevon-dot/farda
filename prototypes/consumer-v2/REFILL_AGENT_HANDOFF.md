# Refill agent build handoff

October 16, 2026. Build target: `claude/enterprise-code-review-s359w1`.

## Delivered behavior

The existing manual refill assistant remains available. The new connection card adds a separately tracked provider request: review the linked prescription, pharmacy and address; explicitly confirm; send once; refresh verified provider status. Sandbox requests are visibly labeled and never presented as live fills. Provider updates do not alter the user's supply ledger or self-reported refill journey.

The first connector implements Photon's documented clinical GraphQL API. It is **disabled by default**. It needs a partner account, server credentials, an eligible prescription already held by Photon, a provider patient address and a trusted mapping to the Farda account. This does not connect arbitrary photographed labels to every pharmacy. Renewals, transfers, eligibility exceptions, prices and insurance remain pharmacy/prescriber workflows.

## AI and performance

- Optional “Ask about this refill” classifies a consented question into a small set of navigation hints. Only the question is sent; prescription data is not attached automatically. Replies are fixed safe guidance, not free-form treatment advice. No model tool can submit an order. Unavailable, refused or malformed model responses fall back to guided help.
- AI is off by default, bounded to eight seconds with no retry, has a small output budget and uses strict schema validation. API request storage is disabled with `store: false`; this is not a claim of zero provider retention. Questions are not stored in Farda's database or application logs.
- Inventory is returned in the existing refill snapshot to remove the per-prescription HTTP waterfall. Independent reads run together. Optional capability failures remain visible instead of implying a working connection.
- Provider access tokens are cached with expiry skew and concurrent refresh requests share one token exchange. Responses and deadlines are bounded. Status refreshes are throttled; no background mobile polling drains battery.

## Request reliability

The backend reserves a durable request before making a network mutation. Account-scoped idempotency keys and single-use expiring reviews prevent replay. Server-side mappings, ownership, local revision and freshly read provider details are verified before submission. An uncertain transport result remains unresolved and cannot authorize another send. Reconciliation queries the provider; a missing match is not proof that an order was never placed.

The integration uses authenticated status polling. No public pharmacy webhook endpoint is exposed. Webhook automation, pharmacy rerouting support, partner-specific eligibility and operational recovery of unresolved requests are follow-up integration work. External identifiers are references; they are not assumed to make Photon mutations idempotent.

## Operator setup

1. Apply the additive Prisma migration to a disposable database and complete the sandbox contract tests before configuring a real environment.
2. Configure server-only `FARDA_REFILL_PROVIDER_ENABLED`, `FARDA_REFILL_PROVIDER_ENVIRONMENT`, `PHOTON_CLIENT_ID` and `PHOTON_CLIENT_SECRET`. Keep production disabled until the partner integration and release review are complete.
3. Verify the patient's identity and prescription match through the trusted clinical workflow. Photon patient `externalId` must equal the Farda user ID; the provider prescription must belong to that patient. Farda does not create a prescription or infer this link from OCR/name similarity.
4. Supply private JSON to the operator command below. Start without `--apply` to verify only. The command never places an order and prints no patient or medication details.

```sh
# Run from farda-app-backend. Keep the input outside the repository.
npx tsx scripts/provision-refill-link.ts < /private/path/refill-link.json
npx tsx scripts/provision-refill-link.ts --apply < /private/path/refill-link.json
```

Input shape (synthetic placeholders):

```json
{
  "userId": "farda-user-id",
  "prescriptionId": "farda-prescription-id",
  "patientId": "photon-patient-id",
  "providerPrescriptionId": "photon-prescription-id",
  "pharmacyId": "photon-pharmacy-id",
  "environment": "sandbox",
  "reviewedMedicationMatch": true
}
```

Production input additionally requires `--confirm-production`; this is an explicit environment safeguard, not a substitute for release approval. Optional AI requires `FARDA_REFILL_AI_ENABLED=true`, `OPENAI_API_KEY` and an available `FARDA_REFILL_AI_MODEL` (default `gpt-4o-mini`). Its privacy/provider configuration must be reviewed before enabling it for real users.

## API surface

| Route | Behavior |
| --- | --- |
| `GET /api/refills` | Existing refill ledger plus batched inventory |
| `GET /api/refills/agent/:prescriptionId` | Capability, latest provider request and an expiring review when eligible |
| `POST /api/refills/agent/:prescriptionId/submit` | Explicit `confirmed: true`, `reviewToken`, `idempotencyKey`; durable one-time send |
| `POST /api/refills/agent/:prescriptionId/refresh` | Authenticated status reconciliation; never automatically resends |
| `POST /api/refills/agent/:prescriptionId/assist` | Bounded question and explicit consent; navigation-only answer |

## Verification and remaining gates

Local backend validation: TypeScript passes, 204 tests pass, and 37 database-dependent tests await CI's disposable PostgreSQL service. These include seven new native concurrency/reconciliation tests. Mock provider tests establish payload/error behavior; they do not establish partner acceptance. Flutter validation: 252 tests pass; analyzer reports no errors or warnings (49 pre-existing informational lints). Sixteen rendered captures cover 390px and 320px enlarged text. Native CI evidence is recorded with the PR. Astra's [editable state board](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=94-476) and [design comparison](REFILL_AGENT_DESIGN.md) cover the matching interface.

Actual partner sandbox requests, live provider credentials, deployment/migration rehearsal, signed builds, physical-device checks and production evidence remain separate gates. No live refill was submitted during development.

Sources checked for the connector: [Photon authentication](https://docs.photon.health/docs/authentication), [place orders](https://docs.photon.health/docs/place-orders), [clinical schema](https://reference.photon.health/), [order events](https://docs.photon.health/docs/order-events). AI schema follows [OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=chat).
