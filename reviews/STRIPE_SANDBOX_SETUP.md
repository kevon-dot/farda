# Farda Stripe sandbox setup

Verified October 16, 2026. Account: Farda. sandbox (`acct_1RBgvSCHvT1Z5GHc`). All objects below have `livemode=false`; no live charging or customer subscription was created.

| Plan | USD price | Stripe Price ID |
| --- | --- | --- |
| Plus monthly | 14.99/month | `price_1URKCxCHvT1Z5GHcyYUqvesI` |
| Plus annual | 149.99/year | `price_1URKD7CHvT1Z5GHcJNqV3KRT` |
| Family monthly | 24.99/month | `price_1URKDACHvT1Z5GHclPyJrtEC` |
| Family annual | 249.99/year | `price_1URKDKCHvT1Z5GHcmU6qijvR` |

Plus product: `prod_VSEgOWzgAEgBuU`. Family product: `prod_VSEgK4nyqrt4nf`. Products have the bootstrap script's `farda_catalog_key` metadata; each price has the matching stable `farda_*_usd` lookup key. Hardware is separate. Historical sandbox hardware products were left unchanged.

Customer portal: `bpc_1URKEiCHvT1Z5GHcc2vNtMNk` (default sandbox configuration). Allows invoice history, payment method changes, and cancellation at period end. Plan switching is disabled pending verified upgrade/downgrade billing behavior. Hosted public portal login is disabled; the app creates authenticated customer-bound sessions.

## Server configuration

These IDs are public configuration, not credentials:

```dotenv
STRIPE_BILLING_ENABLED=false
STRIPE_MODE=test
STRIPE_PRICE_PLUS_MONTHLY=price_1URKCxCHvT1Z5GHcyYUqvesI
STRIPE_PRICE_PLUS_ANNUAL=price_1URKD7CHvT1Z5GHcJNqV3KRT
STRIPE_PRICE_FAMILY_MONTHLY=price_1URKDACHvT1Z5GHclPyJrtEC
STRIPE_PRICE_FAMILY_ANNUAL=price_1URKDKCHvT1Z5GHcmU6qijvR
```

Keep billing disabled until the server has a least-privilege restricted test key, a real webhook signing secret, and the exact approved return origins. Put credentials in the server's secret store; never in Flutter assets, source control, or chat. The authenticated Stripe connector does not expose or install the runtime key.

## Remaining verification

No webhook destination was found in this sandbox. A confirmed public backend URL is required for `/api/billing/webhook`; do not register a placeholder. Register `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.paid`, `invoice.payment_failed`, `checkout.session.completed`, `checkout.session.async_payment_succeeded`, and `checkout.session.async_payment_failed`; configure its signing secret, and test purchase, delayed-payment completion/failure, cancellation, duplicate/out-of-order events, and portal return against the application database. No end-to-end payment, native purchase, or live deployment claim is made by creating this catalog. Native StoreKit/Google Play purchases and restoration remain a separate implementation.
