# Farda membership frontend

`FardaMembershipScreen` is a scrollable Outfit/navy paywall and server-driven management view. It defaults to yearly billing, spells out the full annual USD charge, supports Plus and Family, and keeps an accessible close control. You → Farda membership opens it; Circle can open Family; the refill question card offers optional Plus discovery without blocking guided refill steps.

`BillingRepository` is a separate interface implemented by `ConsumerApiRepository`, leaving the core consumer repository contract intact. It calls GET `billing/catalog`, GET `billing/status`, POST `billing/checkout`, and POST `billing/portal`. Only server capabilities establish paid access. Proposed fallback prices are non-purchasable. Checkout needs web, catalog enablement, selected price availability, and no existing membership. Redirect URLs are restricted to HTTPS checkout.stripe.com or billing.stripe.com. Native checkout and restore remain unavailable until real store configuration exists. No hidden web redirects occur on native.

The adapter provides `BillingSessionGuard`: an opaque closure checks the captured token and auth session revision. The screen rejects stale asynchronous loads and revalidates just before navigation. Auth revision changes synchronously clear visible account state; hidden/paused states clear it; resume reloads. Account changes cannot keep an old portal action live.

Proposed prices: Plus $6.99 monthly / $59.99 yearly; Family $11.99 monthly / $99.99 yearly. The $35 vial is separate. Free reminders, dose history, manual refill tracking and basic Circle remain outside the paywall. Family in-app check-ins explicitly need opt-in and are not emergency monitoring. Refill guidance is not pharmacy confirmation.

## Editable Figma

Existing file `BeSPZ5VOwOOlrwKFTpMA4K`:
- Plus yearly: `140:620`
- Family yearly: `140:621`
- Management web example: `140:622`
- Reusable plan cards: `141:620`, `141:627`

Figma uses existing Outfit fonts, semantic variables, button and companion instances; no UI screenshots/image fills. Validation counted 20/22/13 editable text nodes and 7/7/2 instances respectively. Full Family composition was visually reviewed against rendered Flutter. Screen height is scrollable; Figma presents the full content. Manage is an example state, not a claim of a real subscription.

## Validation

Membership tests pass: 320px at 1.3x text with annual totals; native purchase blocked even with enabled catalog; error/retry; server active management; session revision removes stale account state. Flutter analyzer is clean for membership, billing models and refill question card. Render test captures a 390px membership screenshot to `farda-app/test/visual_qa/goldens/390-membership-family.png` for visual QA only. Production checkout was not exercised with a real Stripe account, and native purchases remain disabled.
