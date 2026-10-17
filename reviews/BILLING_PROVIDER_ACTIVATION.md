# Billing and pharmacy activation

Checked October 16, 2026. This separates implemented code from account configuration and evidence of a working service.

## Account state

| Connection | Verified state | Needed to activate |
| --- | --- | --- |
| Stripe | Farda. sandbox is connected. Four approved recurring prices and the default customer portal exist. No webhook endpoint exists. | Confirm the hosted API and application origins; install a restricted test API key in the backend secret store; register `/api/billing/webhook` and securely install its signing secret. |
| Backend hosting | No hosting connection, deployment manifest, or confirmed public backend URL was found. Runtime Stripe and Photon credentials are absent in this workspace. | Connect the existing hosting provider and identify the staging service. Do not create a replacement production deployment by guessing. |
| Native billing | RevenueCat purchase/restore and server verification are implemented behind configuration gates; no connected RevenueCat, App Store Connect, or Google Play Console account is available here. | Configure the RevenueCat project, store apps/products, server notifications, public SDK keys, secret server key, authenticated webhook, and keep-purchases-with-original-user restore policy. Store purchases must be tested with store sandbox accounts. |
| Pharmacy orders | The existing Photon adapter supports eligible linked Photon prescriptions. Official-site handoffs are available for 12 major pharmacy chains. | Obtain the organization's Neutron sandbox client ID/secret and authorized test patient/prescription/pharmacy mapping. Verify review, submission, uncertain outcomes, and status reconciliation in the sandbox before enabling production. |

## Stripe setup

Use the exact test catalog IDs in `STRIPE_SANDBOX_SETUP.md`. A connected Stripe plugin does not install a server API key. Create a restricted key in the Farda sandbox's API Keys settings and store it in the hosting provider's secret manager as `STRIPE_SECRET_KEY`; never paste it in chat or commit it.

Permissions must cover the operations used by the application: customer creation/read, Checkout session creation/read, price read, subscription read, invoice read, and customer portal session creation. The separate readiness check also reads portal configurations, product details, and webhook endpoint configuration; grant those read permissions to its operator key if needed.

Register the eight event types documented in `STRIPE_SANDBOX_SETUP.md` against the real staging URL. Install `STRIPE_WEBHOOK_SECRET` directly into the server secret store. Set exact allowed application origins and all four distinct price IDs. Runtime activation now refuses a secret key whose test/live prefix disagrees with `STRIPE_MODE`, malformed or incomplete prices, placeholder/private public URLs, duplicate return origins, or an incomplete webhook configuration. Run `pnpm runtime:readiness --remote` with secrets supplied by the hosting environment, then perform end-to-end test Checkout, delayed payment, renewal, cancellation, restore/status refresh, and duplicate/out-of-order webhook verification. A passing readiness report is not an end-to-end payment test.

## Native store setup

Configure monthly and annual Plus and Family subscription products with the approved USD prices: 14.99/149.99 and 24.99/249.99. The app displays the localized price returned by the store. Hardware is separate. Keep native billing disabled until actual public terms, privacy, and support URLs, store products, distinct entitlement mapping, authenticated webhook delivery, verified restore policy, and backend verification are configured. RevenueCat is an additional external service; no account, paid plan, or commercial agreement was created by these code changes.

Test cancellation, pending approval, restore on reinstall, account switching, expiration, refunds, and attempts to start simultaneous web/mobile subscriptions. Sandbox purchases and unsigned simulator builds do not establish App Store approval or a production release.

## Photon access

Photon provides developer sandbox access through its [getting-started guide](https://docs.photon.health/docs/getting-started) and documents server credential exchange in its [authentication guide](https://docs.photon.health/docs/authentication). Production organization access is a separate provider step. No account application, sales message, real prescription, or order was submitted in this work.

The read-only runtime check can authenticate to Photon once credentials are supplied. It does not read patient records, create prescriptions, submit an order, or prove that a pharmacy can fulfill one. A photographed pharmacy label cannot itself supply the trusted electronic-prescription linkage required by the provider.

## Completion evidence

Record the staging URL, exact deployed commit, successful test payment/order references (without patient data or credentials), webhook delivery results, and signed store-build test results before marking a connection activated. Keep production deployment, database backup/rehearsal, signed builds, and physical-device verification separate from GitHub merge status.
