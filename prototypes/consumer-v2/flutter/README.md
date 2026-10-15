# Flutter handoff example

`farda_routine_card.dart` translates the Figma Today routine card (node `4:155`) into Flutter and reuses the existing `ButtonPrimary` and `ButtonSecondary` components. It is an isolated example, not an installed production feature.

The matching vector in `farda-companion-wave.svg` was exported directly from Figma node `3:173`. No temporary Figma URL is needed at runtime. The existing app already depends on `flutter_svg` and registers the Outfit font.

To integrate: move the widget into the app's feature/component structure, copy the SVG into `assets/images/`, and provide `SvgPicture.asset('assets/images/farda-companion-wave.svg')` as `companion`. Keep the app's existing Theme extensions and ScreenUtil initialization. Move the example's navy values into the shared theme when rolling out the new design.

Wire `onOpenLog` to explicit confirmation for the selected routine occurrence. Wire `onSnooze` to that occurrence's reminder controller, including cancellation/rescheduling of pending escalation. Wire `onMoreOptions` to the routine actions sheet. Neither calls nor vial motion should invoke a taken mutation directly.

The secondary actions stack on narrow layouts or larger text scales. Full device accessibility and overflow validation are still needed. Flutter and Dart are absent from this workspace, so this example has not been compiled, analyzed, or rendered on a device.
