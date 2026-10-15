# Prescription onboarding and refill assistant

Implemented October 15, 2026. Build-stage work; no production deployment claim.

## User flow

Today (empty account), Refills (empty account), and Your routine → Add medication open the same onboarding. Existing medications retain their edit path. Scan and Enter manually are equally visible. Back preserves the draft; scanning fills blank fields without replacing corrections. A human review checkbox is required before saving.

A dedicated camera viewfinder uses the rear camera when available, disables audio and flash, and guides a sequence of up to four overlapping photographs of one long/curved label. The outline is only a guide: the full photograph is retained. Existing photos may also be selected. Review supports enlargement/pinch zoom, retake and removal. Changing a photo resets the coverage checkbox. No upload occurs until the user confirms readability and taps Review label details. Camera denial, unsupported files, scan failure and timeout expose manual entry without fabricating extracted values.

The AI transcribes all views together, with visible-overlap requirements. Missing, conflicting, cut-off or ambiguous instructions remain null. Distinct prescriptions remain separate; the client accepts one medication per batch rather than silently choosing the first. Full directions are preserved. Invalid or over-limit output is rejected rather than truncated. The user reviews name/printed strength, exact directions, optional pharmacy/Rx, and reminder choice in simple steps.

Daily reminders require explicit user-selected times. No daily reminders saves the reviewed prescription without a schedule; as-needed or varying prescriptions are not forced into a daily model. This does not add clinical PRN dosing logic. Saving is idempotent across unchanged retries. The saved screen points to Refills for a separate explicit inventory count; a scanned printed quantity is not assumed to be current inventory.

Refill assistance prepares an editable request using saved label details. Only Copy request writes to the clipboard. Copying does not contact a pharmacy, change refill status or imply eligibility. Save plan remains a separate server-confirmed action. Existing plans can reopen drafting without resetting progress. Contacted/ready/received remain user-reported; receipt reconciliation retains explicit count handling.

## Figma and rendered evidence

Astra added a connected, native editable flow in section `68:406` of file `BeSPZ5VOwOOlrwKFTpMA4K`. The ledger in FIGMA_STATE.json maps each step. Cream surfaces, navy typography, Outfit, mint actions and existing companion vectors are retained. Actual Flutter renders at 390px and 320px/1.3 text informed refinements to the Figma flow, including separate manual steps and the refill draft modal.

New screenshots are under `farda-app/test/visual_qa/goldens/`:
- `onboarding-*`: sixteen welcome, entry, reminder-choice, review and saved frames.
- `label-*`: six capture-introduction/photo/coverage frames, with a clearly marked synthetic label fixture.
- `390-refill-*` and `320-large-text-refill-*`: six assistant/action/request frames.

Workflow and visual structure were compared. Native widgets and Figma controls have rendering/spacing differences; this is not a pixel-identical claim. Camera pixels in Figma are illustrative. Rendered UI tests do not establish physical-camera or OCR accuracy.

## Verification and remaining gates

Focused tests cover multipart bounds/authentication/account changes, upload timeout, invalidator failures, malformed/mixed OCR results, intact long directions, manual fallback, coverage reset, save retries, record-only prescriptions, direct app entry points, clipboard failures and narrow/large-text rendering. Backend OCR tests mock the provider, not real prescription images.

Before a pilot: verify camera permission and lifecycle behavior on supported physical iOS/Android devices; assess focus, glare, curved/long labels and accessibility with real images and configured OCR; verify configured authenticated API connectivity; confirm image/provider retention and consent policy. Photos are kept in capture memory, image-cache entries are evicted on replacement/removal/exit, and camera-owned temporary files are deleted best-effort. Selected library originals are never deleted. The upload service uses memory storage. No claim is made about an external provider's retention configuration.

Direct pharmacy submission, verified pharmacy callbacks, prescribing/renewals, insurance and delivery integration remain separate partner work. No pharmacy API, phone number, URL, acceptance or pickup date is invented by this feature. Signed release builds, real-device validation and production deployment evidence remain separate.
