# Farda Figma handoff

Created and verified on October 14, 2026 (America/Los_Angeles).

[Editable Figma file](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=9-225) · [Prototype starting at Today](https://www.figma.com/proto/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-9&starting-point-node-id=2%3A9)

## Confirmed result

The MCP created the design and successfully read the newly created Today screen (`2:9`) back through `get_design_context`. The response contained a screenshot, reference code, component properties and descriptions, Outfit text styles, SVG asset references, and bound Farda variables. The design-to-code path is working.

The tool returned React/Tailwind reference code even with Flutter/Dart supplied as client metadata. Those parameters describe the client; they do not make the output production Dart. The existing Farda app remains Flutter. The reference must be adapted to its widget, theme, navigation, and state-management conventions.

## What is in the design

- 17 native, editable 390 × 844 screens; 456 text nodes; 96 component instances.
- 34 variables across primitive and semantic collections, plus 7 Outfit text styles.
- Button, calendar-day, switch, and companion component variants.
- 117 cross-screen navigation connections, plus On/Off switch interactions.
- Scrollable content with fixed app navigation; calendar examples for October 14 and 16.
- Today, calendar, refill station, profile, routines, reminder preferences, arriving vial, and support circle.
- 8:50 Live Activity, 9:00 active routine, 9:10 reminder call, answered-call script, shared check-in, confirmed entry, refill handoff, and snoozed reminder.
- Compact and expanded Dynamic Island studies on the components board.

Calls and Live Activities refer to the same routine occurrence. The reminder rhythm is 10 minutes before, at the routine time, and an optional call 10 minutes into the window. Snooze routes to a dedicated state. Answering a call or sensing vial movement never confirms a dose.

## Screen map

| Screen | Node | Link |
| --- | --- | --- |
| today | `2:9` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-9) |
| calendar | `2:12` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-12) |
| refills | `2:15` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-15) |
| you | `2:18` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-18) |
| routine | `2:22` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-22) |
| reminders | `2:25` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-25) |
| vial | `2:28` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-28) |
| circle | `2:31` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-31) |
| before | `2:35` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-35) |
| due | `2:38` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-38) |
| incoming | `2:41` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-41) |
| answered | `2:44` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-44) |
| checkin | `2:48` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-48) |
| confirmed | `2:51` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-51) |
| refillHandoff | `2:54` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-54) |
| calendarRefill | `2:57` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-57) |
| snoozed | `11:333` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=11-333) |

## Code proof and source mapping

- `figma-readback-reference.txt`: saved MCP readback evidence. Temporary asset URLs are redacted. This is reference output, not a runtime module.
- `flutter/farda_routine_card.dart`: a Flutter translation of the Today routine card (`4:155`), reusing the app's existing ButtonPrimary and ButtonSecondary.
- `flutter/farda-companion-wave.svg`: exported directly from the editable Figma companion (`3:173`), suitable for the app's existing flutter_svg dependency.
- Existing app components: `farda-app/lib/components/button.dart` and `text.dart`.
- Existing app theme: `farda-app/lib/theme.dart`. The navy palette should become shared theme tokens during implementation.
- Existing interaction model and full HTML prototype: `prototypes/consumer-v2/model.js`, `app.js`, and `farda-navy-mock.html`.

Use the Figma screen node and `get_design_context` for each implementation slice. Reuse the existing app components and services; translate the layout to Flutter widgets. Keep the confirmed routine record in the app/backend, and pass explicit callbacks into presentation widgets. Treat Figma navigation as a visual demonstration, not the application state model.

## Validation and limits

Visually reviewed both complete screen compositions and corrected switch sizing, calendar touch targets, calendar alignment, and home indicators. The final API audit found zero missing fonts, zero missing prototype destinations, and zero image fills in the screens: the design is composed of native text, components, and vectors. All screens are frames directly inside sections, so navigation destinations have the required hierarchy.

The prototype connections and scroll containers were checked through the API. Figma reports a flow starting point at Today (2:9). Actual prototype-player clicks and device accessibility have not been exercised. Some secondary controls are visual studies, including month changes, filter chips, prescription scanning, invitations, and pharmacy calls.

Flutter and Dart are unavailable in this workspace. The Flutter example has not been compiled, analyzed, or rendered on a device. It is not installed in production. Large-text and screen-size validation remain necessary.

The raster upload endpoint rejected the original PNG uploads (HTTP 413/405). The Figma character and vial are editable vector interpretations. Original raster assets remain in the repository. A browser capture was not performed; these are native Figma mock screens based on the existing design direction.

The call screens illustrate caller identity, the reminder script, and interaction intent. Carrier calls use the operating system dialer, so full branded caller artwork is not guaranteed. Optional private voice updates need a separate identity-verification gate; the prototype routes directly to the shared check-in for design review. Caller verification, consent, opt-out, quiet hours, retries, cancellation, and duplicate-delivery handling still require implementation.

The refill station is a planning and pharmacy-contact handoff, not an order submission or eligibility confirmation. Live Activities need the native integration and lifecycle behavior. The arriving vial still needs real hardware validation.

## Build records

`FIGMA_STATE.json` is the current ID ledger. `FIGMA_FOUNDATIONS.json`, `FIGMA_APP_SCREENS.json`, `FIGMA_FLOW_SCREENS.json`, `FIGMA_PROTOTYPE.json`, and `FIGMA_VALIDATION.json` preserve build and verification details. The `figma-*.js` files are session construction scripts with fixed IDs, not idempotent deployment scripts; inspect current state before any rerun.

This package is the design and implementation handoff. Production app routes and services remain separate implementation work.
