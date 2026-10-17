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

## Companion and permission-aware support — October 2026

The shared day now includes `CircleRoutineSummary`, using the existing quiet companion, navy type, soft evidence chips and wrapping content. It counts only shared self-reported taken/skipped/snoozed records. Device observations and missing records remain unconfirmed; no absent log is described as a missed dose. Reminder-only sharing has no dose counts, and paused sharing shows no routine items. Reminder timestamps are also guarded in the widget, even if a stale payload includes a time that is no longer permitted.

Invitation review now explains exactly which information is visible, that joining does not share the recipient’s own routine, and when the code expires. Empty and expired codes cannot be submitted. Pending invitations and code dialogs show expiry; the manage sheet explains saving and pausing. Account changes invalidate invitation, code, acceptance, cancellation, management and nested revocation overlays, and replace the unusable retry action with Back to You. The existing alert panel is included in the same overlay boundary.

The acceptance copy uses the product’s body type scale so the code field remains usable with a narrow viewport and keyboard. Loading has a spoken progress label and visible message. Summary chips wrap at 320 pixels with double-size text, and the existing companion respects reduced-motion settings.

### Editable Figma handoff

File: https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K

Distinct section: **Companion & Family · Permission-aware support · Oct 2026** (`172:1267`). The source component set sits below the section, outside the review frames. These are content-level state compositions, not claims of pixel-identical OS dialogs or screen chrome.

| Surface | Node |
| --- | --- |
| Shared day and companion evidence summary | `174:863` |
| Invitation acceptance and permission review | `174:899` |
| Reminder-only shared day | `174:911` |
| Paused sharing | `174:931` |
| Account changed | `174:949` |
| Circle routine summary component variants | `174:862` |

Read-back verified 92 descendants: 16 frames, 49 editable text nodes, 12 component instances and 15 vectors. There are no image-filled nodes, and every text segment uses Outfit. Existing companion and button components and local semantic variables are reused. A visual pass found companion instance scaling and chip-container height issues; both were corrected and the final composition was reviewed again.

### Verification

- Full Flutter suite: **309 passed**.
- Final focused state, summary and visual-flow run: **16 passed**, including expiry/empty-code and consent-copy coverage. The unchanged alert-panel suite also passed its **9 tests**.
- The final focused run verifies the acceptance typography adjustment and regenerates the eight changed Circle screenshots at 390 pixels and 320 pixels / 1.3 text scale.
- Focused analysis of both implementation files and both state/summary test files: **no issues found**.
- Full `flutter analyze --no-pub`: **52 informational findings**, no errors or warnings; none in the changed implementation or state/summary tests. Existing application-wide findings are outside this change.
- `git diff --check` passed.

No backend or sharing-contract changes are included. The API remains authoritative for invitation validity and access; local time-based expiry is a presentation guard. There are no production account mutations or claims of live-account verification in this handoff.
