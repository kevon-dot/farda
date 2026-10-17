# Today and Calendar parity polish

October 17, 2026. Scope: Today presentation, routine card, Calendar presentation and their visual/widget checks. No data repositories or other feature flows changed.

## Rendered comparison

Compared the editable final references Today `2:9` and Calendar `2:12` with actual Flutter captures. Existing navy gradient, Outfit typography, cream companion medallions and primary-action hierarchy already aligned closely, so this pass preserves those assets and strengthens state clarity and responsive behavior.

| Editable frame | Node | Change |
| --- | --- | --- |
| Today / Parity polish / Pending / 390 × 844 | `172:750` | Deep navy status capsule; clearer secondary outlines |
| Calendar / Parity polish / Week / 390 × 844 | `172:903` | Checkmark reinforces selected filter |
| Today / Parity polish / Saving choice / 390 × 844 | `172:1113` | Visible saving label and disabled controls |

[Open editable file](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=172-750).

All three frames remain editable: 153 / 208 / 153 descendants respectively; native frames, text, vectors and existing component instances; zero image-filled nodes. Text readback confirms Outfit throughout. Screenshot review found the status capsule made the Today card taller; the scene instance was extended to fill it and checked again.

## Behavior and accessibility

- The routine card announces “Saving your choice…” while a write is pending and disables all card actions until it completes. Snooze remains unconfirmed. A failed or thrown write leaves the current view retryable and never displays a receipt.
- Status capsules and stronger action outlines separate factual record state from decorative artwork. Existing concise copy, neutral character poses and empty-state next actions remain intact.
- Action labels wrap and grow instead of shrinking through a FittedBox. At compact widths the companion is 72px; beyond 1.5× text it yields its space. The date ornament yields space above roughly 1.3× text. Main content remains scrollable.
- Calendar week height follows text scaling. At very large text sizes (above approximately 1.64×) date capsules scroll horizontally instead of squeezing the numbers. The currently selected date still has selected semantics; the unselected current day has a contrasting navy outline. Filters use both a checkmark and color.
- Selection/record transitions honor reduced motion. Today week construction uses local calendar dates across daylight-saving boundaries.
- Neither detected movement, reminder delivery nor answering a call confirms medication use. Confirmation still requires the explicit check-in and an accepted write.

## Verification

- Full Flutter suite: **305 passing**. A final responsive-only refinement was followed by all 24 focused tests, including 6 Today golden scenarios, and the targeted narrow authenticated-shell capture.
- Final focused Today/Calendar plus all Today goldens: **24 passing**.
- Actual Flutter shell captures: **12 passing**, covering Today/Calendar, single and multiple routines, 390px, 320px / 1.3×, expanded month, saved, snoozed, empty and planned-refill Calendar days.
- Today golden scenarios: **6 passing**, including new 320px / 1.6× pending state and operable snooze action. Reviewed final PNGs for clipping and awkward word breaks.
- Calendar regression: 320px / 2× text remains usable without overflow.
- Analysis: **no errors or warnings; 52 existing informational lints**. No informational lint is reported in the changed Today/Calendar source files.
- `git diff --check` passes. Tests use local non-secret environment fixtures copied from `.env.example`; fixtures are not committed.

## Parity limits

The new Figma frames represent 390px static states; Flutter supplies runtime loading, retries, scrolling, selection animation and responsive reflow. Figma uses an editable check glyph, while Flutter uses its native check icon. System status/home bars belong to the operating system and do not appear in Flutter widget captures. Live records, dates and routine counts can differ from the October 14 design fixture. The responsive layout intentionally differs at larger text sizes. These captures are Flutter-engine evidence, not physical-device accessibility or delivery validation.

## Reproduce

From `farda-app`, with `FLUTTER_ROOT` pointing at the pinned SDK and its `bin` on PATH:

```bash
CI=true BOT=true flutter test --no-pub
CI=true BOT=true flutter analyze --no-pub --no-fatal-infos
CI=true BOT=true flutter test --no-pub test/visual_qa/today_states_screenshots_test.dart --update-goldens
CI=true BOT=true flutter test --no-pub test/visual_qa/consumer_screenshots_test.dart --name 'calendar|tab [01]' --dart-define=UPDATE_VISUALS=true --update-goldens
```
