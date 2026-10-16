# Farda Figma handoff

Created and verified on October 14, 2026 (America/Los_Angeles).

[Editable Figma file](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=9-225) · [Prototype starting at Today](https://www.figma.com/proto/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-9&starting-point-node-id=2%3A9)

## Confirmed result

The MCP created the design and successfully read the newly created Today screen (`2:9`) back through `get_design_context`. The response contained a screenshot, reference code, component properties and descriptions, Outfit text styles, SVG asset references, and bound Farda variables. The design-to-code path is working.

The tool returned React/Tailwind reference code even with Flutter/Dart supplied as client metadata. Those parameters describe the client; they do not make the output production Dart. The existing Farda app remains Flutter. The reference must be adapted to its widget, theme, navigation, and state-management conventions.

## What is in the design

- 37 native, editable 390 × 844 screens, including the Calendar and prescription onboarding follow-ups. Original design counts below are historical.
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
| calendarMonth | `60:265` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=60-265) |
| calendarSaved | `60:474` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=60-474) |
| calendarEmpty | `60:683` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=60-683) |
| calendarSnoozed | `60:892` | [Open screen](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=60-892) |

## Prescription onboarding and refill assistant (October 15)

Astra added 16 editable states in [section 68:406](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=68-406), compared with actual Flutter renders. See [the implementation handoff](PRESCRIPTION_ONBOARDING_HANDOFF.md) for behavior, tests and device limits.

| Screen | Node |
| --- | --- |
| prescriptionWelcome | `68:407` |
| labelCapture | `68:432` |
| labelPhotos | `68:451` |
| labelReview | `68:475` |
| prescriptionManual | `68:501` |
| prescriptionReminders | `68:527` |
| prescriptionConfirmation | `68:548` |
| refillAssistant | `68:570` |
| refillRequest | `68:596` |
| prescriptionDirections | `69:469` |
| prescriptionPharmacy | `69:473` |
| prescriptionSaved | `69:477` |
| prescriptionNoReminders | `69:481` |
| labelIntroduction | `69:485` |
| prescriptionNoRemindersConfirmation | `71:482` |
| prescriptionNoRemindersSaved | `71:497` |

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

Flutter 3.47.7 is now available and the actual Flutter widgets have been compiled and rendered at 390px and 320px with larger text. See [VISUAL_PARITY.md](VISUAL_PARITY.md) for the screenshot evidence, final frame mappings and functional adaptations. Physical-device and production verification remain separate release work.

The raster upload endpoint rejected the original PNG uploads (HTTP 413/405). The Figma character and vial are editable vector interpretations. Original raster assets remain in the repository. A browser capture was not performed; these are native Figma mock screens based on the existing design direction.

The call screens illustrate caller identity, the reminder script, and interaction intent. Carrier calls use the operating system dialer, so full branded caller artwork is not guaranteed. Optional private voice updates need a separate identity-verification gate; the prototype routes directly to the shared check-in for design review. Caller verification, consent, opt-out, quiet hours, retries, cancellation, and duplicate-delivery handling still require implementation.

The refill station is a planning and pharmacy-contact handoff, not an order submission or eligibility confirmation. Live Activities need the native integration and lifecycle behavior. The arriving vial still needs real hardware validation.

## Build records

`FIGMA_STATE.json` is the current ID ledger. `FIGMA_FOUNDATIONS.json`, `FIGMA_APP_SCREENS.json`, `FIGMA_FLOW_SCREENS.json`, `FIGMA_PROTOTYPE.json`, and `FIGMA_VALIDATION.json` preserve build and verification details. The `figma-*.js` files are session construction scripts with fixed IDs, not idempotent deployment scripts; inspect current state before any rerun.

This package is the design and implementation handoff. Authenticated app routes and supported account services are integrated; see [FRONTEND_HANDOFF.md](FRONTEND_HANDOFF.md) for the remaining provider and device boundaries.


## Family Circle upgrade

The existing Circle home (`2:31`) now introduces real family sharing. Editable flow section `129:603` covers invitation (`129:604`), shared day (`129:665`), pending/code (`130:606`), acceptance (`130:677`), and manage sharing (`130:747`). See [Family Circle handoff](../../docs/design/family-circle-handoff.md) for implemented behavior, native Flutter render evidence, and comparison limits.
