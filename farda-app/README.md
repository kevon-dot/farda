# Farda Flutter app

The consumer-v2 navy experience is mounted at `/dashboard` and implemented in `lib/consumer_v2/`.

## Main frontend areas

- `lib/consumer_v2/farda_consumer_shell.dart` — Today, Calendar, Refills, and You navigation.
- `lib/consumer_v2/design_system/` — consumer semantic colors, type, spacing, and shared presentation widgets.
- `lib/consumer_v2/screens/` — the Figma-aligned screen implementations and local preview flows.
- `lib/consumer_v2/reminders/` — pure-Dart occurrence rules and delivery intents.
- `test/consumer_v2/` — shell, widget, state, and reminder-domain coverage.

## Run and test

The repository pins Flutter 3.41.3 in `.fvmrc`. Environment files are bundled assets and must exist locally:

```bash
cp .env.example .env.development
cp .env.example .env.staging
cp .env.example .env.production
flutter pub get
flutter run --dart-define=ENV=development
```

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

The current screens use local sample state for actions that require services or native code. See the [consumer-v2 frontend handoff](../prototypes/consumer-v2/FRONTEND_HANDOFF.md) for the exact production integration boundary and remaining work.
