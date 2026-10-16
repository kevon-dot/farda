# Refill agent: design and implementation

Astra extended the existing editable Farda Figma system in file `BeSPZ5VOwOOlrwKFTpMA4K`, page `0:1`. Board `94:476` sits at x=4700, y=0 alongside the existing flows. Existing source frames remain intact.

| State | Figma frame |
| --- | --- |
| Connection unavailable | `95:476` |
| Linked prescription ready for review | `95:511` |
| Submitting, no repeat-send action | `95:549` |
| Uncertain result, check status | `95:585` |
| Provider request sent | `95:623` |
| Provider reports pharmacy-ready | `95:661` |
| Review, consent unchecked | `98:529` |
| Review, consent checked | `99:735` |
| Manual fallback, scrolled | `99:638` |
| AI helper, explicit question opt-in | `101:601` |

## Behavior

Provider capability appears in a white card beneath the navy companion hero. Unavailable capability clearly points to pharmacy contact and manual copy. The linked-prescription review displays the medication, saved instructions when present, pharmacy, address shared with the provider, environment and consent. Only the explicit confirmed Send refill request action submits. Sandbox states say `Sandbox · no live order`.

Sending has no repeat-submit action. Unknown results say the request may have been sent and offer Check status. A provider acknowledgement is labeled Request sent and does not imply pharmacy readiness. The ready state attributes readiness to the provider and asks users to check pickup details with the pharmacy. Provider activity does not update supply counts or the user's local refill plan.

Manual review/edit/copy remains separate from sending. Phone/official-contact actions use provided contact information. The example fixture has no phone number; the manual reference therefore shows the source application's label-contact guidance rather than an invented call destination.

## Visual system and comparison

Uses existing Farda Outfit fonts, navy/cream/mint tokens, Button and Companion instances, and Hero atmosphere component. Text, controls and layout remain editable. Cards use 346px width at a 390px viewport, 18px padding, 24px corners, 18px titles, 14px body copy, and a 52px primary action. Sandbox uses a lilac pill above the state heading. The confirmation sheet uses a 358px width and explicit checkbox; the send action is disabled until checked.

Inspected actual Flutter renders in `farda-app/test/visual_qa/goldens/390-refill-agent-{eligible,unavailable,unknown,review}.png` and compared with Figma screenshots. The provider card's hierarchy, copy, width, spacing, colors and action semantics align. Eligible card vertical bounds differ by approximately two pixels (Figma top277 vs render279), inherited hero typography and navigation are not pixel-identical, and the Figma review uses editable semantic layers rather than a captured image. Remaining minor differences include outlined action width/icons and some inherited screen typography. The UI agent subsequently applied explicit navy styling to refresh, dialog title, consent checkbox and Not now after the comparison. This is scoped visual alignment, not a claim of pixel parity across every state or screen size.

Figma includes example fixed check times and fixture data; live code derives these from provider evidence. The 320px enlarged-text renders are implementation QA, not separately recreated Figma variants. Original local-planning assistant `68:570` and request modal `68:596` remain available.

## AI helper state

Frame `101:601` matches the actual `390-refill-agent-helper.png` question/answer flow with native editable text and controls. It shows an explicit opt-in to send the typed question to AI, states that medication details are not included automatically, and displays the guided pharmacist fallback with nothing submitted. Compared the actual render and verified a final Figma screenshot after correcting the floating input label. Screen geometry is close but not pixel-identical; the source retains native Material icon/field behavior. This helper cannot submit a refill or authorize a dose change.
