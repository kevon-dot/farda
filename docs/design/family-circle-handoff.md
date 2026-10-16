# Family Circle upgrade

The active consumer-v2 route is You → Your circle. It now opens `FardaCircleScreen` and uses the canonical account repository. The previous local sample-supporter invitation and sharing switches were removed. The mascot was not changed.

## Experience

- Navy family hero and a prominent invitation action, using existing Outfit, ivory, blue, scene artwork and local vector icons.
- My circle: connected people, pending invitations, per-person sharing controls, cancellation and removal.
- Shared with me: incoming invitations, acceptance with the one-time code, decline, and shared routines.
- Invite sheet: intended account phone number, separate dose-update and reminder-time opt-ins, and explicit acceptance before sharing. The code is copied manually; the interface does not claim an SMS was sent.
- Shared day: read-only recorded / skipped / snoozed / unconfirmed state, record evidence, refresh timestamp, planned reminder times, and a leave action. No confirmation is not presented as a missed dose. Device activity is not proof medication was taken.
- Loading, empty, unavailable and failed-mutation states are explicit. Session and request lifecycle handling is covered separately by the client-state tests.

## Existing Figma file

https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K

| Surface | Node |
| --- | --- |
| Existing Circle home, updated in place | `2:31` |
| Family flow section | `129:603` |
| Invitation bottom sheet | `129:604` |
| Shared day | `129:665` |
| Pending invitation / code | `130:606` |
| Acceptance | `130:677` |
| Manage sharing | `130:747` |

The designs remain native editable Figma layers, with Outfit text, existing variables and button/switch components. The flow frames contain no flattened UI screenshots. Home hero icons reuse the exact local `icon-circle`, `icon-clock`, and `icon-check` SVG artwork. Figma text reflow and transparent-row clipping issues found in the first screenshot pass were corrected and reviewed again.

## Rendered verification

`test/visual_qa/circle_screenshots_test.dart` renders the actual Flutter widget with test-only account fixtures at 390 × 844 and 320 × 844 with 1.3 text scaling. It exercises the home, invitation sheet, long invitation code, acceptance dialog with keyboard inset, and shared-day navigation. Both layouts passed, without Flutter layout exceptions. A separate device-evidence fixture asserts that observed vial activity never renders “Reported taken”. Export is gated behind `UPDATE_VISUALS`; ordinary CI runs interactions and overflow checks without platform-sensitive golden comparison.

Golden images are in `farda-app/test/visual_qa/goldens/`:

- `390-circle.png`, `390-circle-invite.png`, `390-circle-shared-day.png`
- `320-large-text-circle.png`, `320-large-text-circle-invite.png`, `320-large-text-circle-shared-day.png`
- `{390,320-large-text}-circle-code.png` and `{390,320-large-text}-circle-accept-keyboard.png`

Comparison checked navy/ivory colors, Outfit hierarchy, local SVG icons, hero height, card/chip hierarchy and sheet readability. Figma models device status/navigation chrome, while these isolated Flutter fixtures render the screen in a Scaffold. The home fixture includes a connected sample person; Figma home shows the empty state. Adaptive native switches, text fields and dialogs retain platform styling, and the invitation/pending/management designs include flow documentation beyond one captured viewport. These are not claims of pixel-identical full-screen output.

The client-state follow-up keys the scroll canvas by shared view, so a loved one's day opens at its heading instead of inheriting the previous list's scroll offset. The final golden exports were regenerated after this correction; the shared-day captures now include the heading and back action. The keyboard test also found an acceptance-controller disposal race, corrected by giving the dialog ownership of its controller.

```sh
FLUTTER_ROOT=/path/to/flutter flutter test --no-pub \
  test/visual_qa/circle_screenshots_test.dart \
  --dart-define=UPDATE_VISUALS=true --update-goldens
```
