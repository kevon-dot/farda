# Farda consumer UX audit — October 15, 2026

This review compares the editable [Figma experience](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=9-225) with the Flutter consumer-v2 screens. It focuses on the first 390 × 844 viewport and the authenticated flow. Visual recommendations are design direction, not a claim that a device study has happened.

## What is working

- Navy and warm ivory give Farda a recognizable tone. The Outfit type and soft cards feel calmer than a clinical dashboard.
- The companion has a memorable shape and can become the through-line across the four tabs. The repository already includes a three-pose original character asset; the Figma file uses an editable vector interpretation.
- Explicit dose confirmation, self-reported refill status, and neutral language support trust. Keep these constraints while reducing repeated explanations.

## Highest-impact changes

| Surface | Current friction | Better behavior |
| --- | --- | --- |
| [Today](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-9) | Greeting, date strip, routine card, reminder rhythm, and supporting cards compete in the same scroll. Safety explanations repeat. | Lead with the next routine and one clear action. Use a short status line and reveal the full explanation only when confirming, snoozing, or opening details. Keep other routines in compact selectable rows. |
| [Calendar](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-12) | The month grid occupies most of the first viewport; the selected day's useful detail begins below it. Color dots need a legend. | Show a compact day summary immediately after selection and let a small companion react to empty, routine, and refill days. Keep text labels and accessible semantics so color is never the only status cue. |
| [Refills](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-15) | The large introduction and estimate push the next action down. Unknown counts can make the view feel empty. | Put the prescription, last verified count, and next user action together. Use a one-line freshness cue. Show the pharmacy and reconciliation explanation in the action dialog. Never imply an order was placed. |
| [You](https://www.figma.com/design/BeSPZ5VOwOOlrwKFTpMA4K?node-id=2-18) | Every row has a descriptive subtitle and multiple preview caveats. The character sits apart from the controls. | Group Routine and Reminders as everyday controls, and label Vial/Circle previews plainly. Let the companion acknowledge a saved preference, not a local toggle. Keep privacy and consent details near the affected setting. |

## Character behavior

The character should communicate the **interface state**, never judge adherence. Pending is attentive; snoozed is resting; a server-confirmed entry gets a brief calm acknowledgment; skipped stays neutral; save failure stays supportive. Animate once on a state change, roughly 200–450 ms, and honor reduced-motion settings. Opening a notification, answering a call, or moving a vial must never trigger a “taken” pose. The same states should appear in Today, Calendar, and small contextual moments across Refills and You.

## Copy and interaction rules

1. Lead each screen with the answer to “What can I do now?” Use short verbs: **Log dose**, **Remind me later**, **Review day**, **Update count**.
2. Keep one primary action per card. Put correction, details, and secondary actions behind a clear secondary affordance.
3. Put consequential explanations in confirmation dialogs and helper details. Keep the immediate status visible: **Not confirmed**, **Snoozed until 9:15**, **Saved**, **Counted Oct 15**.
4. Do not use streaks, grades, guilt, automatic adherence claims, or a celebratory animation before the API confirms a write.
5. Check 320–390 px widths, large text, VoiceOver/TalkBack, 44–48 px targets, focus order, and reduced motion in simulator and device passes. The current Figma frames alone do not establish these behaviors.

## Implementation status

The authenticated four-tab data slice is merged in PR #108. This follow-up branch routes signed-in sessions to the four-tab experience, shortens the Today/Calendar copy, gives the companion distinct neutral states, and makes the next action more prominent. The shared theme keeps navy as the anchor with warm ivory and restrained peach/lilac/mint accents. Calendar, Refills, and You now use clearer chip, button, and card hierarchy. Refills and You use authenticated repository actions where supported; local native/Circle/vial previews remain labeled previews. These changes need Flutter CI and simulator visual review before they are called complete. Native notification delivery, APNs background Live Activities, BLE, provider delivery, and physical device validation are separate integration and release work.
