# Farda membership frontend

`FardaMembershipScreen` is a scrollable Outfit/navy paywall and server-driven management view. It defaults to yearly billing, spells out the full annual USD charge, supports Plus and Family, and keeps an accessible close control. You → Farda membership opens it; Circle can open Family; the refill question card offers optional Plus discovery without blocking guided refill steps.

`BillingRepository` is a separate interface implemented by `ConsumerApiRepository`, leaving the core consumer repository contract intact. It calls GET `billing/catalog`, GET `billing/status`, POST `billing/checkout`, and POST `billing/portal`. Only server capabilities establish paid access. Approved display fallback prices are non-purchasable. Checkout needs web, catalog enablement, selected price availability, and no existing membership. Redirect URLs are restricted to HTTPS checkout.stripe.com or billing.stripe.com. Native checkout and restore remain unavailable until real store configuration exists. No hidden web redirects occur on native.

The adapter provides `BillingSessionGuard`: an opaque closure checks the captured token and auth session revision. The screen rejects stale asynchronous loads and revalidates just before navigation. Auth revision changes synchronously clear visible account state; hidden/paused states clear it; resume reloads. Account changes cannot keep an old portal action live.

Approved USD prices: Plus $14.99 monthly / $149.99 yearly; Family $24.99 monthly / $249.99 yearly. Family is priced per routine owner; invited viewers remain free. The $35 vial is separate. Free reminders, dose history, manual refill tracking and basic Circle remain outside the paywall. Family in-app check-ins explicitly need opt-in and are not emergency monitoring. Refill guidance is not pharmacy confirmation.

## Editable Figma

Existing file `BeSPZ5VOwOOlrwKFTpMA4K`:
- Plus yearly: `140:620`
- Family yearly: `140:621`
- Management web example: `140:622`
- Reusable plan cards: `141:620`, `141:627`
- Optional onboarding offer after a saved first routine: `150:671`

Figma uses existing Outfit fonts, semantic variables, button and companion instances; no UI screenshots/image fills. The onboarding frame has 22 editable text nodes and 8 component instances; annual price and value copy comes from the reusable plan cards. Full Family and onboarding compositions were visually reviewed against rendered Flutter. Screen height is scrollable; Figma presents the full content. Manage is an example state, not a claim of a real subscription.

## Validation

Eight membership tests pass: 320px at 1.3x text with all four approved prices; account-scoped once-only offer preference; Continue free dismissal without checkout; native purchase blocked even with enabled catalog; error/retry; server active management; session revision removes stale account state. Flutter analyzer is clean for membership and billing models; the consumer shell retains its pre-existing style lints. Render tests capture 390px membership and onboarding screenshots to `farda-app/test/visual_qa/goldens/390-membership-family.png` and `390-membership-onboarding.png` for visual QA only. Production checkout was not exercised with a real Stripe account, and native purchases remain disabled.

## Optional onboarding offer

`FardaConsumerShell._addPrescription` opens the offer only after a first medication has been saved and its onboarding returns success. Cancelling setup or saving an additional medication does not trigger it. The saved medication is never contingent on membership. The offer uses the existing navy/Outfit companion layout, shows the full yearly charge first, and adds an explicitly approximate monthly equivalent ($12.50 Plus / $20.83 Family); no trial, scarcity or unverified discount is implied. Continue free and the close control dismiss it.

`MembershipOfferGate` records a local, versioned preference per user ID before presenting. A captured auth revision is checked before and after storage and navigation; account changes dismiss the onboarding offer. Storage failures skip the optional offer. This is a device-local presentation preference, not a server entitlement or a cross-device promise.

### Native store implementation update

- Flutter now uses `purchases_flutter` 10.16.0 for iOS/Android offering discovery, purchase and restore. Prices are the store's localized `priceString`; the proposed USD web catalog is never displayed as a native store offer.
- The server issues an opaque store identity and product allowlist. A session-pinned `/billing/native/prepare` reservation precedes purchase; `/billing/native/sync` verifies entitlement after purchase/restore. SDK entitlement data never unlocks features locally.
- Purchase cancellation, pending approval, network failure and unconfigured store states keep the free routine accessible. Session changes clear private UI, invalidate in-flight work and serialize SDK logout. No long-lived CustomerInfo listener is installed.
- Configured public HTTPS terms, privacy, and support links are required for native purchase enablement and appear in the existing membership footer. Store subscription management opens Apple's or Google's subscription settings; native never opens Stripe checkout. Dual-source memberships retain native management access.
- iOS application minimum deployment target is now 13.0 for the RevenueCat SDK; the Live Activity extension remains 16.2.
- Editable Figma fixture states: `163:714` (native offer) and `163:735` (pending approval) in `BeSPZ5VOwOOlrwKFTpMA4K`. The euro price is explicitly a test fixture, not a configured production offer. These extend the existing navy membership design; this is not a claim of whole-app screenshot parity.
- Device store builds and real sandbox purchases/restores still require provider credentials, products, policies and store test accounts. Local widget tests use an injected adapter.
