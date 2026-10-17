# Native billing activation handoff

The backend and Flutter purchase path stay disabled until RevenueCat, App Store Connect, and Google Play are configured. No paid account or store product was provisioned by this change.

Set `REVENUECAT_NATIVE_BILLING_ENABLED=true` only after all of these values are present: `REVENUECAT_MODE` (`sandbox` or `live`), a private `REVENUECAT_SECRET_API_KEY` that is valid for RevenueCat REST API v1, a high-entropy `REVENUECAT_WEBHOOK_AUTH_TOKEN`, both public SDK keys, `REVENUECAT_PLUS_ENTITLEMENT_ID`, `REVENUECAT_FAMILY_ENTITLEMENT_ID`, all four platform/tier product ID lists, and real HTTPS `FARDA_TERMS_URL` and `FARDA_PRIVACY_URL`. Keep private keys on the backend. Public SDK keys are returned only to authenticated clients.

Google Play can expose different identifiers between SDK products, entitlement records, and the REST v1 subscriptions map. Capture and verify the actual sandbox contract for every configured base plan, then use the exact entitlement/SDK identifier observed in the allowlist; the backend also supports a REST subscription map keyed by the bare product. Set `REVENUECAT_ANDROID_CONTRACT_VERIFIED=true` only after those checks. Until then, Android config and purchase preparation remain disabled. Configure the products, entitlements, and offering consistently in RevenueCat and the stores.

In RevenueCat, set restore behavior to **Keep with original App User ID**. Configure the webhook URL as `/api/billing/native/webhook` and its Authorization header to exactly match `REVENUECAT_WEBHOOK_AUTH_TOKEN`. Send sandbox events only to a backend with `REVENUECAT_MODE=sandbox`; use separate production credentials and `live` mode for production.

The app calls `POST /api/billing/native/prepare` immediately before opening a store purchase. The 10-minute reservation and the web checkout reservation share a per-user database lock. The app then calls `POST /api/billing/native/sync`; the backend fetches RevenueCat's canonical subscriber record and grants only an allowlisted, matching, nonexpired entitlement/subscription. RevenueCat transfer events revoke local access and require support review.

Before release, apply `20261017010000_native_billing`, run the full suite with a migrated disposable `TEST_DATABASE_URL`, test new purchase/renewal/cancel/expiration/billing issue/restore on both store sandboxes, verify webhook retries and authorization failures, and confirm both web portal and native store management links remain visible when a provider conflict is reported.

References: [RevenueCat identifying customers](https://www.revenuecat.com/docs/customers/identifying-customers), [restore behavior](https://www.revenuecat.com/docs/projects/restore-behavior), [webhooks](https://www.revenuecat.com/docs/integrations/webhooks), and [subscriber REST API](https://www.revenuecat.com/docs/api-v1#tag/customers/operation/subscribers).
