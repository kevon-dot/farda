# Farda — Front-End (Flutter) Code Review

**Scope:** the Flutter client only (`farda-app/farda-master`, ~65 Dart files). Focus: what screens exist, what reusable components exist, what's actually created, and whether it's all **wired properly** (navigation reachability, data binding, form inputs, state management).
**Method:** two parallel deep-scan agents — one screen/navigation/data-wiring, one component-library/theme/assets — cross-checked against `lib/routes/routes.dart` and `lib/main.dart`.

---

## 0. Headline

The app is **mid-refactor and only partially wired**. It migrated from `auto_route + flutter_bloc + freezed + get_it` toward `go_router + Provider`, but **left both systems in the tree** — so there's a dual navigation system, ~1,000+ lines of dead scaffolding, a well-built design system that's bypassed 30–40% of the time, and a layer of screens/components that are *built but never reached*.

Three things are true at once:
1. **The auth + OCR happy path is genuinely wired** (login → OTP → prescription scan/save → calendar).
2. **The dashboard is mostly mock UI** — Home is hardcoded ("Terry Roberts", fake pill counts, a fake chart), Plan is a stub, and patient identity ("Tom Cruse") is hardcoded over real data.
3. **Whole flows are orphaned** — Subscription, Calibration, and the standalone Mood check-in are registered as routes but **nothing navigates to them**.

Wiring scorecard: of the live screens, ~5 are properly wired to data, ~4 are wired-but-buggy, and ~5 are static mock or stub. Several form fields silently discard user input.

---

## 1. Screen inventory & reachability

14 screen widgets exist. The critical question — *is each one actually reachable, and how* — breaks down as:

| Screen | Path registered | How it's reached | Wiring verdict |
|---|---|---|---|
| `ScreenOnboard` | `/onboard` (initial) | Entry point; **the only auth gate** (`initState` reads `prefs['id']`) | ✅ reachable |
| `ScreenLogin` | `/login` | `Navigator.push` from onboard (**bypasses router**) + 401 redirect | ✅ reachable (but not via its route) |
| `ScreenOtpVerify` | `/otp-verify` | `Navigator.push` from login controller (**bypasses router**) | ✅ reachable (not via route) |
| `ScreenDashboardShell` | `/dashboard` **+** ShellRoute | `context.go('/dashboard')` after OTP/onboard | ✅ reachable |
| `ScreenHome` | ShellRoute `home` | rendered as `children[0]` index, **not** its route | ⚠️ reachable via index |
| `ScreenPlanHope` | ShellRoute `plan` | `children[1]` | ⚠️ **stub** ("Work Ongoing") |
| `ScreenCalendar` | ShellRoute `/calendar` | `children[2]` index | ⚠️ reachable via index |
| `ScreenMore` | ShellRoute `more` | `children[3]` index | ⚠️ reachable via index |
| `ScreenPrescription` | `/prescription` | `context.push` from More | ✅ reachable |
| `ScreenConnectOnboard` (BLE) | `/screen-connect-onboard` | `context.push` from More & Prescription | ✅ reachable (but return value ignored — see §4) |
| `ScreenEmoji` | nested `/calendar/emoji` (top-level route commented out) | `context.go('/calendar/emoji')` from Calendar | ⚠️ reachable but fragile (lands in a *different* calendar instance) |
| `ScreenMoodCheckIn` | `/mood` | **nothing navigates here** | ❌ **ORPHANED** |
| `ScreenCalibration` | `/calibration` | **nothing navigates here** | ❌ **ORPHANED** |
| `ScreenSubscription` | `/subscription` | **nothing navigates here** (CTAs commented out) | ❌ **ORPHANED** |

**Note:** file/class name mismatch — `screen_setup_vial.dart` defines `ScreenConnectOnboard`. And there's literal **dead demo code inside screen files**: a second top-level `main()` + `StraightContainerWithCircles` at `screen_calendar.dart:552-602`, and an unused `_prescription(...)` builder at `screen_emoji.dart:146-328`.

### The navigation mess (core wiring problem)

`/dashboard` is registered **twice, conflictingly**:
- a top-level `GoRoute` → `ScreenDashboardShell()` (what `context.go('/dashboard')` actually hits), which switches tabs via **internal `setState` index** (`dashboard_shell.dart:30-35`), driven by a custom `BottomNavBar.onSelect` callback — *the tabs are array indices, not routes*; and
- a `ShellRoute` with real child routes (`home`/`plan`/`/calendar`/`more` + nested `/calendar/emoji`) that **nothing ever navigates to** → the entire ShellRoute branch is dead.

On top of that, the app **mixes three navigation primitives**: `context.go`, `context.push`, and raw `Navigator.push(MaterialPageRoute)` that bypasses GoRouter entirely (onboard→login, login→OTP, prescription-save→dashboard). This breaks back-stack consistency and defeats the (already commented-out) router redirect guard at `routes.dart:102-120`. **There is no router-level auth** — any deep link to `/dashboard`, `/prescription`, etc. is reachable unauthenticated.

**Recommendation:** pick ONE dashboard mechanism (delete either the top-level `/dashboard` route or the ShellRoute), route tabs consistently, replace all `Navigator.push` with `context.push/go`, and re-enable the redirect guard.

---

## 2. Component / widget library

The reusable library lives in `lib/components/`, stitched as one Dart library via `part`/`part of` through the barrel `_components.dart` (9 parts). Two components (`note_dialog.dart`, `custom_snackbar.dart`) are **not** in the barrel and are imported directly — so the barrel is incomplete.

**Components that exist and are used (the real, working set):**

| Component | File | Used by |
|---|---|---|
| `ExtendedScaffold` | core.dart | ~6 screens (the base scaffold) |
| `TextMedium` | text.dart | 9 files (base text widget) |
| `ButtonPrimary/Secondary/Tertiary` | button.dart | 7 / 4 / 3 screens |
| `PhoneNumberInput` | input.dart | login |
| `CustomAppBar` | app_bar.dart | 5 screens |
| `BottomNavBar` | app_bar.dart | dashboard shell |
| `CustomTabSelector` | tab_bar.dart | home |
| `PricingCard` | utilities.dart | subscription |
| `WeekCalendar` | utilities.dart | more |
| `PrescriptionView` | utilities.dart | prescription, more |
| `PillProgressSection` | utilities.dart | home |
| `CustomSnackbar` | custom_snackbar.dart | 4 controllers (the one solid feedback widget) |
| `AnimatedChart` | chart.dart | home (but it's mock — §5) |
| `ThoughtDialog` / `showThoughtsDialog` | dialogs.dart / note_dialog.dart | mood / emoji |

**Components/utilities that are ORPHANED (built but never reached in live code):**
- **An entire custom calendar engine (~530 lines)** in `utilities.dart`: `CustomCalendarView`, `CalendarController`, `CalendarStyle`, `CalendarEvent`, `CalendarEventFrom`, `DateHolder`, plus the `mapIndex` extension — referenced only in commented-out code. (The live calendar was hand-rebuilt in `screen_calendar.dart` instead.)
- **The entire `bloc_presentation` layer** — `PresentationCubit`, `BlocPresentationProvider` (`bloc_extension.dart`) — never instantiated. The app uses Provider/ChangeNotifier.
- `showErrorToast` / `showInfoToast` (`helpers.dart`) — a second, unused notification system parallel to `CustomSnackbar`.
- `app_text.dart` strings (`submitPrescription`, `failedPrescriptionSubmit`) — unused (controllers use string literals).
- `app_urls.dart:10-48` — a whole users/auth/caregiver/device REST surface defined ahead of implementation, zero references.
- `HalfCircularProgressBar`, `MenuItem`, `Country` — only used internally by other components.

**Dead deps this implies:** `flutter_bloc`, `bloc_presentation`, `freezed`, `auto_route`, `get_it`, `dio`, `retrofit` are all declared in `pubspec.yaml` with **no live usage** (DI in `di/di.dart` is 100% commented; `_screens.dart`/`_screens.freezed.dart` fully commented; commented `auto_route` import in `_components.dart:3`).

---

## 3. Design system — exists but bypassed

`lib/theme.dart` is genuinely well-built: a `FardaColors` ThemeExtension (slate 50–950, success/warning/error swatches, base black/white/blue), a `Spacing` extension (xs–xl), and a full `AppTypo` TextTheme in the Outfit font. This is the strongest part of the front-end.

But adherence is only ~60–70%:
- **36 hardcoded `Colors.black/white/grey/red`** in components (worst: `dialogs.dart`, `note_dialog.dart`, `FeelingChip`).
- **7 inline `Color(0x…)` literals** in screens — one (`screen_calendar.dart:513` `0xff2D9CDB`) literally **duplicates `FardaColors.blue`**.
- **`fontFamily:'Outfit'` hardcoded ~20×** instead of relying on the themed TextTheme.
- The `Spacing` extension is **almost never used** — screens use ad-hoc `EdgeInsets.all(16)` / `SizedBox(height:16)`.
- Deprecated `withOpacity` still in 5 spots (rest of app migrated to `withValues`) — inconsistent mid-migration.
- `flutter_screenutil` axis misuse: square widgets sized with `.h` for **width** (`button.dart:159`, `PricingCard:406`, `PillProgressSection:439`) → distorts on wide screens.
- Minor bug: `FardaColors.copyWith` (theme.dart:88) omits `blue`, so it can't be overridden.

---

## 4. Form / input wiring — several fields silently discard input

| Screen | Field | Wired? |
|---|---|---|
| Login | phone + country | ✅ read on submit |
| OTP | 6-digit code, paste | ✅ read on submit |
| Prescription | Rx#, store#, pill qty | ⚠️ have controllers **but never read back into the model on Save** — `toSubmit()` serializes only OCR data, so **manual edits are dropped** |
| Prescription | **DOB** | ❌ `TextField` has **no controller at all** — input lost |
| Vial setup (BLE) | vial ID (scanned/typed) | ⚠️ collected and `Navigator.pop`'d back, but **every caller ignores the return value** → `prescriptionModel.deviceId` stays null; vial is never linked to the prescription |
| Notes dialog | note text | ⚠️ `note_dialog.dart` reads it — but the repo **hardcodes the body to `"dsfasd"`** (`calender_repo.dart:76`), so every saved note is literally "dsfasd" |
| Mood check-in (`ThoughtDialog`) | note text | ❌ `TextField` has no controller **and** Save is a `// TODO` no-op |

**Dead no-op buttons on real UI:** Apple sign-in, Google sign-in (`screen_login.dart:71/77`), and "Call Instead" (`screen_otp_verify.dart:158`) all have `onClick: () {}`.

---

## 5. Data wiring per screen (live vs mock)

- **Wired & working:** Login, OTP (→ better-auth/Twilio), Calendar (`GET dosetime/` via `CalenderProvider`), More's prescription card (`GET my-prescriptions/`).
- **Wired but buggy:** Prescription (edits dropped, "Tom Cruse" hardcoded, vial ID lost), Emoji/notes (note payload hardcoded), Calendar (emoji shown is a single global mood, not per-dose).
- **Pure static mock:** **Home** (watches `CalenderProvider` but never reads it — name "Terry Roberts", pill counts 480/740/1000/1220, dose times, and both "analytics" charts are hardcoded), **Subscription** (prices hardcoded, CTAs no-op), **Mood check-in** (chips + count "4" hardcoded), **Calibration** ("4 days", stepper hardcoded).
- **Stub:** Plan ("Screen Plan Work Ongoing").

**The chart is fake:** `AnimatedChart` has no data parameter — `ChartPainter` draws a hardcoded 4-point curve. Home's "Pill Left Trend" and "Pill Taking Trend" cards render the **same fabricated curve**, mirrored, green vs red. Presented as "Insights & Analytics."

**State-management note:** `CalenderProvider` and `PrescriptionProvider` are **eagerly initialized in `main.dart`** (`..getCallAllApi()` / `..getMyPrescriptionApi()`), so the app fires authenticated endpoints (`dosetime/`, `mood/`, `my-prescriptions/`) **with an empty bearer token at launch, before login**. `HomeProvider`/`HomeRepo`/`NotesRepo` are empty shells.

---

## 6. Dialogs, snackbars, assets

- **Duplicate note dialogs:** `ThoughtDialog` (TODO save, no controller) and `showThoughtsDialog` (real save) are near-identical — consolidate. The working one has a **double-pop nav bug** (`Navigator.pop()` then `context.pop()` at `note_dialog.dart:105/107`) and a leftover `print`.
- **Two notification systems** coexist: `CustomSnackbar` (used) and toastification `showInfo/ErrorToast` + `ToastificationWrapper` (unused).
- **Assets:** unused-but-shipped — `camera.svg`, `facebook.svg`, `calibration_hero.png`, `farda_white.png`; plus a stray undeclared **`flutter_01.png` (453 KB) at the project root** (leftover screenshot). No missing-but-referenced assets — every referenced path resolves.

---

## 7. Prioritized front-end fixes

**Correctness / wiring (do first):**
1. Read the prescription form controllers into the model before save; add a DOB controller (currently 4 fields' edits are silently dropped).
2. Fix `submitNote` to send the real note text instead of `"dsfasd"` (`calender_repo.dart:76`).
3. Consume the vial ID returned from `ScreenConnectOnboard` (await the push result) and set `deviceId` — today the BLE pairing result is thrown away.
4. Implement or remove the `ThoughtDialog` TODO save (and give it a controller).
5. Gate the eager provider calls behind auth, or pass the token — stop firing authenticated endpoints pre-login.

**Navigation:**
6. Collapse the dual dashboard (one mechanism), route bottom-nav tabs consistently, replace `Navigator.push` with GoRouter, re-enable the redirect/auth guard.
7. Wire or delete the orphaned `ScreenSubscription` / `ScreenCalibration` / `ScreenMoodCheckIn`, and finish the `ScreenPlanHope` stub.

**Cleanup / quality:**
8. Delete dead code: the ~530-line custom-calendar engine, the `bloc_presentation` layer, `_screens.dart`/`di.dart` (commented), `app_text.dart`, the `app_urls.dart` backend block, the stray `main()`/demo widget in `screen_calendar.dart`, and the unused `flutter_bloc/freezed/auto_route/get_it/dio/retrofit` deps.
9. Replace mock screens (Home, the fake chart, Subscription prices, mood chips) with real data, or clearly mark them as placeholders.
10. Enforce the design system: remove the 36 `Colors.*` + 7 inline `Color(0x…)` literals and 20 hardcoded `'Outfit'` references, use the `Spacing` tokens, fix the `.h`-for-width ScreenUtil misuse and `withOpacity` deprecations.
11. Remove unused assets + the root `flutter_01.png`.

---

## 8. Bottom line

The front-end has **good bones** — a real design system, a reasonable component set, and a working auth/OCR path — wrapped in a **half-finished refactor**. The defining problems are *wiring*, not visuals: a dual navigation system where bottom-nav tabs aren't routes, three orphaned flows, several forms that throw away what the user types, a flagship "analytics" chart that's fake, a dashboard that's mostly hardcoded mock data, and ~1,000+ lines of dead alternate-architecture code shipped alongside the live one. None of it is hard to fix, but in its current state the UI **looks** more complete than it actually is — a demo skin over a partially-connected app.
