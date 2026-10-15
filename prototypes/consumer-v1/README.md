# Farda consumer experience concept

Open **farda-consumer-mock.html** directly in a browser. It embeds the existing product render and Outfit fonts and needs no server, account, packages, or internet connection.

This is a separate concept, not a replacement for the Flutter implementation. No production code, firmware, API, deployment, or GitHub branch was changed.

## What to explore

- Today: one clear routine, explicit self-report confirmation, snooze, skip, and undo.
- My routine: editable reminder with label-review confirmation; unreadable sample OCR cannot activate a plan.
- History: sources distinguish self-reports from vial signals; unknown does not mean missed.
- My vial: connection freshness, battery, estimated count, setup, calibration/refill/access explanations.
- Trusted circle: proposed permission preview, simulated acceptance, and immediate sample revocation.

Use the scenario controls to switch between connected, no hardware, offline, uncertain reading, and low battery. On narrow screens they appear below the app. The initials button opens Trusted circle on mobile. Everything is clearly simulated; the demo day, entries, counts, reminder times, and supporter are fictional. Reloading or Reset demo discards changes.

## Design direction

Retain Farda’s Outfit typography and existing vial image. Introduce warm ivory, forest green, soft sage, generous type, and one primary action. Keep counts secondary to a useful next step. Core reminders, manual logging, data access, and medication access must not become paywall dependencies.

The setup walkthrough is a proposed interaction, not an assertion that the current firmware supports secure QR pairing. The calibration sequence is provisional until hardware validation. No screen makes a dosing recommendation, proves ingestion, places a pharmacy order, sends an invitation, schedules a notification, or controls a lock.

## Source and checks

Edit `index.html`, then rebuild the portable file:

```bash
node prototypes/consumer-v1/build-standalone.mjs
node --test prototypes/consumer-v1/mock.test.mjs
```

The tests execute the inline JavaScript in a minimal DOM stub and exercise rendering strings and state transitions. They are **not browser, layout, accessibility, Flutter, or BLE integration tests**. Browser-level visual inspection could not be run in this environment because the required browser-control capability was unavailable. Inspect narrow layouts, large text, keyboard navigation, screen readers, and modal focus behavior in a real browser before implementing the design.

The generated standalone file is tracked as a handoff artifact; its source is `index.html` plus existing repository assets. No external images, fonts, analytics, or network services are loaded.
