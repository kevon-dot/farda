# Membership and family check-ins

Build-stage implementation, October 16, 2026. No production deployment or live charging is included.

## Approved launch offer

| Plan | Monthly USD | Annual USD | Scope |
| --- | ---: | ---: | --- |
| Essentials | Free | Free | Core reminders, dose history, manual refill planning, existing basic Circle sharing |
| Plus | 14.99 | 149.99 | Optional AI refill navigation when its provider is configured |
| Family | 24.99 | 249.99 | Plus and consent-based in-app Circle check-ins |

The user supplied a $35 hardware price; this is treated as a separate selling price, not verified manufacturing cost. No hardware price, shipping policy, tax configuration, trial, or live payment link has been created. Family is purchased by the routine owner; invited viewers do not each need a paid subscription. It is not a bundled subscription for multiple independently paid routine owners.

The user approved these prices on October 16, 2026. Customer willingness to pay and actual service costs still need validation; this is not a margin guarantee. Medisafe's January 7, 2026 help article lists USD 4.99/month and 39.99/year outside the US: https://help-center.medisafe.com/en/articles/13052285-medisafe-is-now-a-fully-paid-app-for-users-outside-the-u-s . Farda's premium should be justified by actual coordination and reliable integrations. Current AI classifies refill navigation intent; it does not provide clinical advice or autonomously order prescriptions. No paid marketing should imply more.

## Implemented

- Server-authoritative membership catalog/status and entitlements.
- Stripe-hosted web Checkout and customer portal, allowlisted prices and return origins, validated USD amount/recurrence/mode, durable checkout reservations, signed raw-body subscription webhooks and reconciliation.
- Separate Plus/Family paywall in the active app and the former `/subscription` route. An optional offer appears after the first medication is saved; Continue free and close controls preserve the routine. A local, account-scoped preference avoids repeated onboarding offers. Removed stale trial/pricing and unsupported outcome claims from that route.
- Core care remains accessible after closing the paywall or losing paid access. Optional AI gating is separately controlled by `FARDA_AI_REFILL_PAYWALL_ENABLED`.
- Family check-ins require the owner's Family entitlement, explicit owner enablement and recipient consent. Grace period and timezone-aware quiet hours apply. An inbox entry says confirmation is absent; it does not say a medication was missed or swallowed.
- Revocation, permission withdrawal, resolved/cancelled/snoozed/archived occurrences and expired entitlement suppress alerts. Reminder timestamps are omitted when reminder-time sharing is off.
- Bounded worker batches use durable fairness bookkeeping. The existing worker lifecycle now materializes Circle inbox entries. This is an in-app inbox, not push/SMS delivery.
- Account/session revisions clear membership and Circle private state and invalidate stale asynchronous results.
- CI packages the unsigned iOS simulator app for review as well as the existing Android demo APK.

## Payment setup and remaining boundaries

`STRIPE_BILLING_ENABLED=false` is the default. Never put Stripe or Photon secrets in Flutter assets. Configure server-side Stripe test credentials, the webhook signing secret, four Price IDs, and exact `FARDA_BILLING_RETURN_ORIGINS`. The repeatable `stripe:bootstrap:test` script refuses live credentials and creates/reuses the proposed test catalog. The matching sandbox catalog was created through the authenticated Stripe connection on October 16, 2026; the bootstrap script has not been executed against an account.

Raw endpoint: `POST /api/billing/webhook`, mounted before the general JSON parser. Configure subscription lifecycle events and test creation, renewal, cancellation, payment failure, delayed/replayed delivery and portal return. Live charging must wait for an actual provider test and verified benefits. Family checkout also requires the worker to be enabled. The optional AI provider must be ready before either paid plan is sold.

Stripe authentication is verified for Farda. sandbox (`acct_1RBgvSCHvT1Z5GHc`, test mode). Two membership products, four recurring USD prices, and a customer portal configuration were created and read back. See `reviews/STRIPE_SANDBOX_SETUP.md` for IDs. The account has no webhook endpoints yet. Runtime restricted test key, webhook signing secret, and confirmed application/backend origins are still required; account connection alone does not configure the server or verify an end-to-end purchase.

Mobile digital purchases and restoration are not implemented with StoreKit/Google Play billing. The native paywall truthfully disables purchase/restore; it does not silently redirect to Stripe. Storefront eligibility or native billing configuration must be completed before mobile monetization. Web checkout integration is not a claim of App Store approval. Current policy references: https://developer.apple.com/app-store/review/guidelines/ and https://support.google.com/googleplay/android-developer/answer/9858738 .

Invitation code sharing remains the fallback. Universal/app links and background family push delivery remain work, not completed claims.

Photon sandbox credentials, verified synthetic patient/prescription/pharmacy fixtures, signing assets, application identifiers and store access remain prerequisites for live integration and signed beta distribution. See `reviews/REFILL_BETA_HANDOFF.md`.

## Design and validation

Existing Figma file: https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K

- Membership: Plus `140:620`, Family `140:621`, manage `140:622`.
- Circle: owner settings `141:736`, recipient consent `141:754`, inbox `141:766`.

Astra owns editable Figma/frontend; 5.6 Sol owns backend and independent security review. Screens were rendered at compact sizes and large text. See `docs/design/membership-handoff.md` and test artifacts for scoped visual evidence; no whole-app pixel-identical claim.

Final local/CI results are recorded in the pull request. Apply both billing and Circle-alert migrations before enabling these features in a build environment. Production backup/rehearsal and device validation remain separate release gates.
