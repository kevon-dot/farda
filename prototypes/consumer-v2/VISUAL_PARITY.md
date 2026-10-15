# Farda — rendered Flutter design verification

October 15, 2026. Source of truth: [editable Figma](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-9). This record supersedes the earlier statement that Flutter could not be run in this workspace.

## Design and implementation

Astra refined the existing native Figma screens with a deep navy scene, orbital glow, restrained warm highlights, cream character medallions, concise headings, soft filter chips and consistent actions. Flutter uses SVGs exported directly from the corresponding native Figma nodes. The character and background artwork is shared rather than independently redrawn.

The inspiration research informed specific decisions, without copying third-party artwork: [Finch's recurring companion](https://help.finchcare.com/hc/en-us/articles/37780000231309-Exploring-the-Finch-Home-Page) for continuity, [Headspace's expressive illustration](https://developer.apple.com/news/?id=fkfnhq8u) for warmth and clarity, and [Gentler Streak's contextual activity guidance](https://gentlerstories.com/newsroom/20250317amoreintuitivestreak) for a clear next action. Farda does not reward medication use or shame a missing entry.

The final Mobbin pass inspected the public Headspace and Duolingo screenshots on [Mobbin's public showcase](https://mobbin.com/mcp); the full searchable catalog was unavailable. Takeaways applied here: expressive artwork above quieter content, a clearly selected chip, one primary action, and an empty state with a short explanation and next step. Calendar now offers Show all entries, Back to today, or Your routines according to context. No third-party artwork was copied into Farda.

## Comparison method

The actual Flutter widgets are rendered by Flutter 3.47.7's test engine, with bundled Outfit fonts, Material icons, 48px top and 20px bottom safe areas. Authenticated-shell fixtures exercise both one and multiple routines. Captures include 390 × 844 at normal text size and 320 × 844 at 1.3× text. You flows also have 320px/1.6× interaction tests. Screenshots live under `farda-app/test/visual_qa/goldens/`.

These are rendered application widgets, not HTML facsimiles. They establish a visual comparison and layout behavior in the Flutter engine; they are not physical-device, native-delivery, or production evidence. OS status bars and home indicators are system chrome and are not drawn by the widget fixture.

| Figma reference | Flutter implementation | Comparison scope |
| --- | --- | --- |
| Today `2:9` | Today screen and routine card | Exact Wave artwork, navy scene, date rail, primary/secondary actions; one/multiple routines |
| Calendar `2:12` | Calendar screen | Expressive welcome, seven day capsules, week navigation, expandable month, primary entry and compact upcoming cards |
| Calendar month `60:265`, saved `60:474`, empty `60:683`, snoozed `60:892` | Calendar state views | State-aware hero and card tones, recorded versus snoozed distinction, contextual empty action |
| Refills `2:15` | Live and preview refill station | Exact vial and scene, supply estimate, planning action, self-managed journey |
| You `2:18` | You overview | Exact Quiet artwork; 138/244/134px reference cards; settings and preview badges |
| Routine `2:22`, Reminders `2:25`, Vial `2:28`, Circle `2:31` | You secondary pages | Rendered hierarchy, controls and small-screen reflow |
| Confirmed `2:51`, Snoozed `11:333` | Today receipts | Explicit save acknowledgement and unconfirmed snooze state |
| Check-in `2:48` | Full-screen Today check-in | Explicit confirm/snooze/cancel; failed saves remain retryable |
| Refill handoff `2:54`, Calendar refill `2:57` | Full-screen handoff and selected-day agenda | Checklist, pharmacy contact guidance, plan save and visible no-order caveat |
| Before `2:35`, Due `2:38`, Incoming `2:41`, Answered `2:44` | Native-surface previews | Character medallions, clock/card composition, explicit simulation labels, state controls below the preview |

## Functional adaptations

- Calendar defaults to the selected week; the month toggle preserves the selected date. Visible week/month arrows and Today provide direct navigation. Actual unresolved entries precede saved records in the daily agenda, with chronological order inside each group.
- Calendar distinguishes a self-reported taken entry, a self-reported skipped entry, an active snoozed reminder, and a scheduled or unconfirmed occurrence. A neutral scheduled marker means a real record exists, not that a dose was taken. Refill cards retain the visible no-order caveat.
- Snapshot reads include full Monday–Sunday weeks around month edges (at most 42 days), plus a separate short current-day window when viewing distant history. Week navigation uses local calendar-date construction across daylight-saving transitions.
- Authenticated screens preserve actual medication identity, number of routines, supply, status, capabilities and dates. Multiple routines make Today and Calendar longer than the single-record design frame; all content remains scrollable.
- An unavailable provider stays unavailable. UI fidelity never substitutes invented capability, delivery, pharmacy status or successful writes.
- The confirmed receipt appears only after an accepted save. Snoozing leaves the dose unconfirmed. A Back to today control returns to the routine list.
- The 390px reference spacing expands for larger text. The bottom navigation height follows text scaling; Calendar keeps all seven columns visible. Decorative character artwork can yield space to readable controls.
- Motion is a short arrival/pose transition, with no continuous animation. Reduced-motion preference removes it and selection transitions.
- Date-dependent captures are opt-in exports rather than brittle daily pixel assertions. Normal CI exercises layout and interactions. The fixed-date Today fixtures can be compared as deterministic goldens.
- The refill handoff uses a pushed full-screen route with an explicit return link instead of keeping the shell tab bar visible. Extra preview controls and truthful capability notices also differ from the static reference. This is reviewed design alignment, not a claim of pixel-identical screens.

## Verification results

- Full Flutter suite after the Calendar redesign: 176 tests passed.
- Flutter analysis: no errors or warnings; 47 informational lints remain in the application.
- Existing HTML prototype suite: 27 tests passed.
- Visual harness: 31 scenarios passed, plus 5 fixed-date Today goldens; 36 PNG review artifacts. Nine Calendar captures were refreshed for week/month, narrow text scaling, saved, snoozed, empty and refill states.
- Astra reviewed the final Calendar default/saved/empty/snoozed renders against the updated native frames and signed off on the visual direction. The main scene responds to the actual selected-day state; a taken entry uses mint, while snoozed/skipped entries remain distinct.
- Independent code review closed canonical receipt timestamps, preview-only privacy copy, the vial's three-step completion, visible refill caveats and accessible filter activation.
- `git diff --check` passed. Remote CI is checked separately on the published PR head.

## Reproduce

From `farda-app`, using the pinned SDK:

```bash
CI=true BOT=true FLUTTER_SUPPRESS_ANALYTICS=true flutter pub get --enforce-lockfile
CI=true BOT=true FLUTTER_SUPPRESS_ANALYTICS=true flutter test test/visual_qa --dart-define=UPDATE_VISUALS=true --update-goldens
CI=true BOT=true FLUTTER_SUPPRESS_ANALYTICS=true flutter test
CI=true BOT=true FLUTTER_SUPPRESS_ANALYTICS=true flutter analyze --no-fatal-infos
```

The CI/BOT environment also prevents the Flutter tool's automatic cloud metadata probe. Screenshot tests load real fonts, disable debug banners, and enable real shadows.

## Remaining release validation

Keep native notification/call/Live Activity delivery, BLE hardware behavior, signing and physical-device accessibility separate from this visual review. The operating system controls carrier-call presentation. Production target, provider configuration, database backup/migration rehearsal and live deployment evidence remain release work, not evidence supplied by these captures.
