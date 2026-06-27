# Farda — Enterprise Code Review

**Reviewed:** uploaded archive `2026/` → three components (Flutter app, TypeScript/Prisma "main" API, JavaScript/Mongo "vial" API) plus root `API_DOCUMENTATION.md`.
**Method:** four parallel deep-scan agents (one per component + one cross-cutting security/HIPAA audit), plus direct verification of the integration seams (shared DBs, proxy targets, env config).
**Date:** 2026-06-26.

---

## 0. Executive summary

Farda is a **smart medical-vial / medication-adherence platform**: a Flutter phone app for patients (and caregivers), a Bluetooth-connected "smart vial" that logs when medication is taken, a main backend that handles auth + prescriptions + OCR of pharmacy labels, and a second backend that ingests device telemetry/events and powers caregiver monitoring.

**The idea is coherent and the happy-path is partially wired end-to-end.** But as a codebase this is an **early prototype / proof-of-concept stitched together from scaffolds**, not an enterprise-grade system. The headline problems:

- **Live secrets are committed** to the repo — Twilio master auth token, OpenAI key, Stripe key, and a **live MongoDB Atlas username/password** for the PHI store. None of the `.env` files are gitignored. Treat the device/event database as already compromised.
- **The main API leaves almost every PHI endpoint unauthenticated** (auth middleware is applied to exactly one route of dozens), and the few that exist are **IDOR-able** (you pass any `userId`/`doseId` and read/write that patient's data).
- **The "smart vial" hardware feature cannot run as shipped** — the Flutter app declares **no Bluetooth permissions** (Android) and **no usage strings** (iOS), so scanning/connecting throws on a real device, and the App Store would reject the build.
- **Device ingestion is spoofable** — one shared placeholder API key (`your-strong-device-api-key`, with a hardcoded fallback) gates all device event ingestion, with no replay protection, so anyone can fabricate medication-adherence events for any device.
- **Two backends, two databases, three different auth notions, and a dead proxy layer** between them — the architecture is half-built and internally inconsistent. Documentation describes a system that doesn't match the code.
- **Large swaths are mock/stub/dead code:** hardcoded "Terry Roberts"/"Tom Cruse" patient data, a "Work Ongoing" Plan tab, dead social-login buttons, an abandoned bloc/freezed/DI architecture shipped alongside the live one, broken tests, and an entirely unimplemented Stripe billing flow.

**HIPAA verdict: not compliant; do not put real patient data through this in its current state.** Multiple independently-disqualifying issues (unauthenticated PHI, plaintext transport, no encryption at rest, no audit logging, committed credentials, PHI sent to OpenAI/Twilio with no evident BAAs).

**Maturity rating: ~2/10 (working demo).** The product vision and UI are real; the engineering is not production-ready and the security posture is unsafe for medical data.

---

## 1. System architecture

### 1.1 The three tiers

| Component | Folder | Stack | Role |
|---|---|---|---|
| **Farda app** | `farda-app/farda-master` | Flutter / Dart, Provider state mgmt, `flutter_blue_plus` BLE, raw `http` | Patient + caregiver mobile client |
| **Main API ("farda-app-backend")** | `farda_api/farda-app-backend` | Express 5, **Prisma 7 + Postgres**, better-auth, Twilio Verify, OpenAI GPT-4o, Stripe (declared only), multer | Auth, users, prescriptions, OCR, dose scheduling; *proxy* to vial API |
| **Vial API ("smart-vial-backend")** | `farda-vial-api/farda-vial-api` | Express 5, **Mongoose + MongoDB Atlas**, better-auth (against Postgres), `pg` | IoT device ingestion, events, device claiming, caregiver monitoring |

### 1.2 How they actually connect (verified from configs)

```
                 ┌─────────────────────────────┐
                 │   Flutter app (patient)     │
                 │  BASE_API_URL → :8100 (main)│
                 │  VIAL_API_URL → :5000  ← DEFINED BUT NEVER READ
                 └───────────────┬─────────────┘
                                 │  http (cleartext), Bearer = session token
                                 ▼
        ┌────────────────────────────────────────────┐
        │  Main API (:8100)  Express + Prisma         │
        │  better-auth host  ─────────────┐           │
        │  Prescriptions, Doses (Postgres)│           │
        │  Device/Caregiver routes = PROXY│           │
        │    → env.FARDA_API_URL  ← UNSET (resolves to│
        │      "undefined/api/...")  ⇒ DEAD LAYER     │
        └───────────────┬─────────────────┴───────────┘
                        │ Postgres  postgresql://postgres:root@localhost:5432/farda
                        ▼
        ┌──────────────────────────┐         ┌──────────────────────────────┐
        │  Postgres "farda"        │◄────────│  Vial API (:5000)            │
        │  better-auth: User/      │ same DB │  verifyUserToken =           │
        │  Session/Account +       │ + same  │   better-auth.getSession()   │
        │  Prescription/Dose       │ BETTER_ │  Devices/Events (Mongo Atlas)│
        └──────────────────────────┘ AUTH_URL└───────────────┬──────────────┘
                                      :8100                   │ MongoDB Atlas (remote)
                                                              ▼
                                                  ┌────────────────────────┐
                                                  │ Mongo: User/Device/Event│
                                                  │  (PHI: adherence events)│
                                                  └────────────────────────┘
                          ▲
        Physical vial ────┘  POST /api/ingest/*  with X-API-Key = "your-strong-device-api-key"
```

**Key cross-cutting facts I verified directly:**

1. **Shared identity store.** Both backends point at the *same* Postgres (`postgresql://postgres:root@localhost:5432/farda`) and the *same* `BETTER_AUTH_URL=http://0.0.0.0:8100`. The vial API spins up its own better-auth instance against that Postgres and validates sessions with `auth.api.getSession`. So **a session token from the main API is valid on the vial API** — single identity, but enforced inconsistently.
2. **Dual data stores.** Identity + prescriptions + doses live in **Postgres**; devices + events + a *second* `User` collection live in **Mongo Atlas**. User records are therefore **duplicated** across both DBs, and roles are tracked separately in Mongo (a real problem — see Security H2).
3. **The intended main→vial proxy is dead.** Main API device/caregiver routes proxy to `env.FARDA_API_URL`, which **is set in no env file**, so every proxied route builds `undefined/api/...`. Meanwhile the vial API implements those same concepts (claim device, caregiver, events) natively. The two implementations overlap and neither is wired to the other in the committed config.
4. **The app talks to both backends directly in dev** (:8100 and :5000) but the `VIAL_API_URL` is never read in Dart code, and staging/production point at placeholder domains (`prod.api.com`) over plaintext `http://`.

**Net:** the architecture is a half-finished migration. It looks like the team started with one main API that would proxy device calls to the vial service, then began having the app and vial service share Postgres/better-auth directly — and left both designs in place, neither fully connected.

---

## 2. Product & feature inventory

### 2.1 What the product is

A medication-adherence system for patients who need to take pills on schedule, with optional **caregiver** oversight. The differentiator is a **Bluetooth "smart vial"** that detects and logs dose events, plus **OCR of pharmacy prescription labels** (snap a photo, GPT-4o extracts medication name, dosage instructions, refills, dates) to auto-build a dose schedule. Patients also log **mood** per dose and keep a journal/notes. There's a **subscription paywall** ($7.99/mo or $68/yr).

### 2.2 Feature status (what's real vs. fake)

| Feature | Status | Notes |
|---|---|---|
| Phone OTP login (Twilio Verify) | ✅ Wired end-to-end | send-otp / verify-otp work via better-auth + Twilio |
| Google / Apple social login | ❌ Dead | Buttons have empty `onClick: () {}`; `google_sign_in` dep never imported; backend social handler not mounted |
| Prescription OCR (photo → fields) | ⚠️ Works but lossy | GPT-4o extraction wired; but only **medicine #1** is saved and only **one prescription per user** (schema limit) |
| Dose schedule / calendar | ⚠️ Partial | Calendar renders from API; lots of placeholder/commented code; emoji shown is placeholder |
| Mood check-in / journal | ⚠️ Partial/broken | Mood save wired; note body is **hardcoded `"dsfasd"`** (discards user input); dialog save is a `// TODO` |
| Home dashboard | ❌ Mock | Fully static — hardcoded "Terry Roberts", pill counts 480/740/1000/1220; `HomeProvider`/`HomeRepo` are empty classes |
| Plan tab | ❌ Stub | `Text("Screen Plan Work Ongoing")` |
| Smart-vial BLE connect | ❌ Non-functional | No Bluetooth permissions (Android) / usage strings (iOS); sync routine defined but never called |
| Vial calibration | ❌ UI-only | No BLE interaction; "4 days until calibration" hardcoded; route unreachable |
| Caregiver monitoring | ⚠️ Backend-only | Real in vial API (claim, summary, events); **no caregiver UI in the app at all** |
| Device claim/unclaim | ⚠️ Backend-only | Real in vial API; app has the endpoints in a dead constants file but no screens |
| Subscription / billing | ❌ Vaporware | Paywall UI exists but CTAs are no-ops; **no IAP/Stripe code**; Stripe keys in env but no `stripe` dependency and zero usages |

### 2.3 End-to-end flows that actually work

**Login:** Onboard → enter phone → `POST /api/auth/send-otp` (Twilio sends SMS) → enter 6-digit code → `POST /api/auth/verify-otp` → session token stored (in plaintext SharedPreferences) → routed to dashboard. The only auth gate in the app is `ScreenOnboard.initState` checking `prefs.getString('id')`; the router-level guard is commented out.

**Prescription via OCR:** More tab → Add Prescription → pick camera/gallery → `POST /api/prescriptions/ocr/extract` (multipart, up to 10 images) → GPT-4o returns structured JSON → fields populate → Save → `POST /api/prescriptions/ocr/save` → main API upserts a Prescription and generates a Dose schedule (`doses_per_day` × `duration_days`).

**Device ingestion (server side only):** physical vial → `POST /api/ingest/telemetry` (battery/firmware) and `POST /api/ingest/event` (dose events, deduped by `idempotency_key`) → Mongo. Caregiver endpoints then read those events. **No app screens drive or display this yet.**

---

## 3. Component deep-dives (engineering)

### 3.1 Flutter app (`farda-app/farda-master`, ~65 Dart files)

**State / architecture:** Runtime uses **Provider/ChangeNotifier** (5 providers registered in `main.dart`). But the repo also ships a fully **abandoned bloc + freezed + get_it architecture**: `lib/di/di.dart` is entirely commented out, `lib/screens/_screens.dart` + `_screens.freezed.dart` are 100% commented out, and `bloc_presentation`/`flutter_bloc`/`freezed` are dead weight. Dependency injection is never initialized — repos are `new`-ed inline on every call.

**Routing:** Both `auto_route` and `go_router` are declared; only **go_router** is live (`lib/routes/routes.dart`). There are **two competing navigation models** for the dashboard — a `ShellRoute` and a stateful index-switching shell — plus mixed `context.go` / `context.push` / raw `Navigator.push` usage throughout.

**Networking:** Hand-rolled wrapper over `package:http` (`lib/utilities/api_service.dart`). `retrofit`/`dio` are in pubspec but **unused**. No generated code anywhere despite `json_serializable`/`retrofit_generator`/`freezed` in dev-deps — all models are hand-written `fromJson/toJson`.

**Token storage (a real bug):** the JWT is written to `flutter_secure_storage` under key `token` **but nothing ever reads it back**. Every authenticated request instead reads the **plaintext** SharedPreferences key `access` (`api_service.dart:19-22`). So the secure-storage copy is write-only dead code and the token effectively lives in cleartext. No refresh-token flow (`refresh` always saved as `''`).

**BLE (`screens/connect_onboard/screen_setup_vial.dart`):** Scans for name `"Medical Vial App"`, connects, requests MTU 512, discovers services whose UUID contains `00FF`/`00EE`, defines a `SYNC_DATA[...]` framing protocol with opcodes `0x30`/`0x31` and a 32-byte auth key — but **`triggerLogSync`/`sendAckCommand` are never called**, and parsed logs are only `debugPrint`-ed, never uploaded. **Critically, no platform permissions are declared** (Android manifest has only CAMERA/INTERNET/STORAGE; iOS Info.plist has no Bluetooth/Camera/Photo usage strings), so the feature throws on device and would fail App Store review.

**Quality red flags:** 7 raw `print()` calls including ones that log PHI and the full request body + Bearer token; hardcoded patient identities rendered over real fetched data ("Tom Cruse"); a stray second `void main()` + demo widget shipped inside `screen_calendar.dart` (lines 552-602); ~115 lines of commented-out old implementation at the top of the same file; typos in class names (`ScreenPlanHope`) and UI copy ("Joumal"). The only test is the **unmodified Flutter counter template** (`test/widget_test.dart`) which would *fail* if run. Effective test coverage: **0%**.

### 3.2 Main API (`farda_api/farda-app-backend`, ~36 TS files)

**Server (`src/server.ts`):** Express 5. **No CORS** anywhere. **Helmet effectively never runs** — it's gated on `NODE_ENV==='production' && !DISABLE_HELMET`, but `config/.env.production` sets `DISABLE_HELMET=TRUE`. The **global error handler is broken**: it only responds for `RouteError` instances and then calls `next(err)` unconditionally (double-send / falls through to Express's default HTML stack-trace page for everything else). `cookie-parser`, `jsonfile`, `module-alias`, `jet-paths`, `dayjs` are declared but unused. The `/` and `/users` HTML admin pages are leftover `express-generator-typescript` scaffold.

**Auth (`src/auth.ts`, `middleware/isAuthenticated.ts`):** better-auth with Prisma adapter + phoneNumber plugin + social providers. Problems: **no `BETTER_AUTH_SECRET`** set (sessions can't be reliably signed across restarts/instances); **the better-auth request handler is never mounted** (`toNodeHandler`/`auth.handler` appears nowhere), so the standard better-auth endpoints — session refresh, sign-out, social OAuth callbacks — don't exist; social provider secrets are `undefined` in the committed env. `isAuthenticated` bypasses better-auth and does a raw `prisma.session.findUnique({where:{token}})` on a bearer token, but the bearer plugin isn't enabled, so it likely never authenticates a real session. `sendOTP` swallows Twilio errors (returns success even when no SMS was sent).

**Routes:** All under `/api`. The biggest issue — **`isAuthenticated` is applied to exactly one route** (`POST /prescriptions`). Everything else (`GET /users/all` dumping all users, `POST/PUT/DELETE` user admin, all OCR/dose routes, all device/caregiver proxies) is **wide open**. See Security §5.

**Services:**
- `OcrService.ts` — GPT-4o vision, `temperature 0.5`, `max_tokens 2000`. Two nearly-identical ~90-line functions (files vs URLs) that should be one. No `response_format: json_object` — relies on fragile markdown-stripping before `JSON.parse`. No validation of model output against a schema before persisting. Reads up to 10×10MB images fully into memory and base64-inlines them.
- `DeviceTrackingService.ts` — proxy to `env.FARDA_API_URL` (**unset** → all proxy routes non-functional). Forwards client body/query/params to downstream unvalidated.
- `twilioService.ts` — Twilio Verify v2. `sendSmsOTP` ignores the `code` arg (Verify generates its own), so better-auth's stored OTP code is dead; works only because verification is also delegated to Twilio. Fragile coupling.

**Data model drift (will crash at runtime):** the entire `models/User.model.ts` + `models/common/types.ts` layer assumes a **numeric** `id`, but Prisma `User.id` is a `String @default(cuid())`. So `POST /users/add` / `update` pass the wrong shape and would error. The `tests/users.test.ts` calls methods (`deleteAllUsers`, `insertMultiple`, `User.new`) that **don't exist** — the suite can't compile. The `build` script runs `npm run lint`, which **isn't defined**, so the build fails.

**Migration drift:** `prisma/schema.prisma` defines a `Dose` model and the code uses `prisma.dose` extensively, but the committed migration `20260312031911_init/migration.sql` **never creates a Dose table** — so all dose operations fail against a DB migrated from this repo.

### 3.3 Vial API (`farda-vial-api/farda-vial-api`, ~17 JS files)

**Server (`Server.js`, 23 lines):** Only `express.json()` + three routers (`/api/ingest`, `/api/caregiver`, `/api/user`). **No CORS, no helmet, no rate limiting, no error middleware, no graceful shutdown** — despite all of those being defined in `config/config.js` and `.env`. Connects Mongo with a bare `mongoose.connect`; the robust `config/databaseConfig.js` is dead code (and has a bug where `process.exit(1)` runs before the retry `setTimeout` fires). `package.json` `main: index.js` points at a nonexistent file.

**Auth — the doc/code mismatch:** Every doc (`AUTHENTICATION.md`, `ARCHITECTURE.md`, README) describes a **JWT** flow with `jwt.verify()`. **The code does not do that.** `middleware/verifyUserToken.js` uses **better-auth + a Postgres pool** (`auth.api.getSession`). `jsonwebtoken` is imported in exactly one place — `utils/generateTestToken.js`, a shipped utility that forges user/caregiver tokens and **prints the JWT secret to stdout**. `bcryptjs` is installed but never used. On any auth exception it returns **500 instead of 401**.

**Models:** `Device` is the join entity (`user_id` = owner, single `caregiver_id` = one caregiver per device). `Event` correctly uses a `unique + sparse idempotency_key` for dedup. `Event.payload` is `Mixed` with **no validation** (data-poisoning / stored-XSS surface). Several declared niceties (`User.addRole/removeRole`, `Event.getRecentEvents`, `Event.processed`, `Device.claimed_at`) are never used. Index declarations on array elements are mis-authored.

**Device ingestion:** `middleware/authDevice.js` compares `X-API-Key` to one global key with `!==` (non-constant-time). `device_id` is never bound to the key, so any key-holder writes events for any device. `TYME_SYNC_TOLERANCE_SECONDS` is configured but **never used** → no replay/staleness protection. `time_drift_seconds` is computed and stored but never validated. Telemetry has a field bug: controller reads `battery` but clients/docs send `battery_percent`, so battery never updates.

**Ownership checks are present** on the user/caregiver routes (queries are scoped to `{device_id, user_id: req.user_id}` / `{device_id, caregiver_id}`) — so the vial API is actually **better than the main API** on IDOR. But role assignment is self-asserted (see Security H2), and `unclaim` doesn't clear the caregiver link (desync bug). Find-or-create user logic is **copy-pasted into 4 caregiver handlers** because the reusable `ensureUserExists` middleware was abandoned (commented out).

---

## 4. Data model

**Postgres (Prisma):** `User (cuid) → Prescription → Dose`, plus better-auth `Account`/`Session`/`Verification`. Two design constraints that are real product limits:
- `Prescription.userId @unique` → **one prescription per user**. A patient on multiple medications cannot be represented; saving a second prescription overwrites the first (and deletes future doses). This is fundamentally at odds with the product.
- OCR extracts a `medicines_names[]` array but only **index [0]** is persisted — additional medications are silently dropped.

**Mongo (Mongoose):** `User` (duplicate of the Postgres user, keyed by better-auth id, with `user_roles[]`), `Device`, `Event`. Relations are by string id with no refs/populate; the denormalized `claim_device_ids`/`caregiving_device_ids` arrays on the Mongo User are maintained by hand and can drift.

**The duplication is the core data-model smell:** identity exists in Postgres (better-auth) AND Mongo, with roles authoritative in Mongo — so the system has no single source of truth for "who is this user and what can they do."

---

## 5. Security & compliance (the critical section)

### CRITICAL

- **C1 — Live secrets committed, no `.gitignore` coverage.**
  - Main API `.env` (and identical `.env.development`): `TWILIO_AUTH_TOKEN` (master Twilio credential — toll fraud, read all OTP logs, hijack the Verify service), `TWILIO_ACCOUNT_SID`, `OPENAI_API_KEY` (`sk-proj-…`, unbounded billing), `STRIPE_SECRET_KEY` (`sk_test_…`).
  - Vial `.env`: **`MONGO_URI` with live Atlas username + password** → full read/write/drop of the device + adherence-event PHI store from anywhere. **Treat as already compromised.** Also `JWT_SECRET=dev-secret-change-in-production-test-3`, `DEVICE_API_KEY=your-strong-device-api-key`.
  - No component gitignores `.env*`; the vial folder has **no `.gitignore` at all**.
  - → **Rotate everything now** (Twilio token + Mongo password first), purge git history, move to a secret manager.

- **C2 — Main API: PHI endpoints unauthenticated.** `isAuthenticated` is on **one** route. `GET /users/all` dumps every user; user create/update/delete is open; all OCR/dose routes (read prescriptions, doses, moods; write doses) are open. Unauthenticated total PHI exposure.

- **C3 — IDOR on all medical data.** `GET /ocr/user/:userId`, `/doses`, `POST /ocr/save` (userId **in body**), `POST /ocr/doses/:doseId/record` all act on client-supplied ids with no ownership check. Read or overwrite any patient's prescription, dose history, mood, and adherence records by guessing/knowing a cuid.

- **C4 — Device ingestion spoofable; no replay protection.** One shared placeholder API key (with a guessable hardcoded fallback) gates ingestion; `device_id` comes from the body and isn't bound to the key; `/ingest/telemetry` auto-creates devices. Anyone with the key can **fabricate medication-adherence events for any device** — corrupting the exact data caregivers rely on for safety decisions. `TYME_SYNC_TOLERANCE_SECONDS` exists but is never enforced; replays with a fresh `event_id` are accepted.

### HIGH

- **H1 — Weak JWT secret + shipped token forger** (`utils/generateTestToken.js` prints the secret). Remove both.
- **H2 — Two identity stores, roles self-asserted.** Caregiver endpoints create the Mongo user from `req.user_role` and then check `hasRole('caregiver')` against the record they just created — effectively **self-granted caregiver access** to another person's medication data.
- **H3 — One token, two backends, inconsistent enforcement.** A main-API session works on the vial API (shared Postgres), but the main API doesn't enforce auth on its own copies of those routes.
- **H4 — `FARDA_API_URL` unset** → proxy layer broken (and a config-injection risk if ever set from untrusted input).
- **H5 — SSRF via `/ocr/extract-from-urls`.** Unauthenticated; `image_urls[]` validated only as URLs and fetched server-side by OpenAI — an open, OpenAI-billed fetch relay. Add auth + host allowlist + private-range block.
- **H6 — No CORS / helmet / rate limiting on the main API.** Helmet disabled in prod by env; OTP send/verify unthrottled (SMS-bombing + Twilio cost).
- **H7 — Vial API ships security middleware configured but unwired** (cors/helmet/rate-limit/bcrypt all present, none used).

### MEDIUM

- **M1 — Cleartext HTTP everywhere** (Flutter prod/staging URLs, `BETTER_AUTH_URL`) → tokens + PHI interceptable.
- **M2 — Token cached in plaintext SharedPreferences** on device (secure-storage copy is never read).
- **M3 — better-auth unhardened** (no secret/baseURL/trustedOrigins/expiry config, no server-side logout/revocation, no refresh rotation).
- **M4 — NoSQL operator injection surface** in the Mongo backend (req.body/query fields flow into Mongoose filters unsanitized; no `express-mongo-sanitize`).
- **M5 — PHI/identifiers in logs**, no access audit trail (HIPAA §164.312(b) gap).
- **M6 — Prompt injection via OCR images** persisted and shown as medical guidance; OCR prompt even instructs the model to *infer* dosing "using medical knowledge" → fabricated PHI.

### LOW

- Generated Prisma client committed; Postman fixtures committed; weak multer filter (MIME **or** extension, allows `application/octet-stream`); freeform license field; dead/commented middleware.

### HIPAA readiness — blunt

**Not compliant.** Access control broken (C2/C3/C4/H2), no audit logging (M5), plaintext transport (M1), **no encryption at rest** (Postgres + Mongo store prescriptions/doses/moods/events in plaintext), data-minimization violated (model fabricates dosing data), committed credentials are themselves a reportable-exposure-class event, and there are **no evident BAAs** with OpenAI (receives prescription images = PHI), Twilio, Stripe, or MongoDB Atlas.

---

## 6. Code quality & tech debt (cross-cutting)

- **Abandoned-architecture sediment.** Every tier ships a dead alternate design alongside the live one: Flutter (bloc/freezed/get_it/dio/retrofit dead, Provider/http live); main API (numeric-id model layer, HTML admin scaffold, commented prescription routes); vial API (dead `databaseConfig.js`, `ensureUserExists.js`, `events.controller`, JWT path).
- **Documentation describes a different system than the code** — most acutely in the vial API (JWT vs better-auth, "rate limiting active" vs none, "MongoDB only" vs dual-DB). The root `API_DOCUMENTATION.md` lists a `role` field that doesn't exist and implies auth on routes that have none.
- **Tests are effectively zero and broken** in all three tiers (Flutter counter template, non-compiling backend suite, vial `test` script that just errors). No CI config anywhere.
- **Build is broken** in the main API (`build` → undefined `lint`).
- **Inconsistent everything:** two error-handling paradigms, two validation approaches (zod vs manual vs none), mixed navigation idioms, mixed package managers (pnpm-lock + npm references), placeholder data rendered over real data.
- **Secrets, PHI, and tokens leak into logs** on both the client and servers.

---

## 7. What's missing / what's fake (consolidated)

**Missing for a real product:**
1. Authentication/authorization on the main API (currently 1 protected route).
2. Working BLE (permissions + actually calling the sync routine + persisting/uploading events).
3. A real multi-medication / multi-prescription data model.
4. Billing (no Stripe/IAP code despite the paywall and committed keys).
5. Caregiver UI in the app (backend exists, no screens).
6. Per-device credentials + replay protection for ingestion.
7. HTTPS/TLS, encryption at rest, audit logging, rate limiting, CORS, helmet.
8. Real tests + CI; reconciled DB migrations (missing Dose table); a single identity source of truth.
9. Social login (front and back).
10. Real staging/production API hosts (currently placeholder domains).

**Fake / mock / stub:** Home dashboard, Plan tab, calibration, mood chips, subscription CTAs, social-login buttons, "Call Instead", hardcoded patient identities, the note body (`"dsfasd"`), the main→vial proxy, the JWT auth story in the docs.

---

## 8. Prioritized remediation roadmap

**P0 — Stop the bleeding (days):**
1. Rotate all committed secrets (Twilio, Mongo, OpenAI, Stripe, JWT, device key); add `.env*` to every `.gitignore`; purge history; move to a secret manager.
2. Apply `isAuthenticated` at the router level on the main API; derive `userId` from the session, not the body/params; add ownership checks on `doseId`/`userId`/`deviceId`.
3. Replace the shared device key with per-device credentials (HMAC/mTLS), bind events to the claiming user, enforce the time-tolerance window + a server nonce/replay cache, and lock down telemetry auto-provisioning.

**P1 — Make it safe & coherent (weeks):**
4. HTTPS end-to-end; enable helmet in all envs; strict CORS allowlist; rate-limit OTP + PHI routes; wire helmet/cors/rate-limit into the vial server.
5. One identity source of truth (Postgres/better-auth); make roles server-authoritative; mount the better-auth handler; set `BETTER_AUTH_SECRET`; add logout/refresh.
6. Decide the architecture: either the app talks to both services directly, or fix the main→vial proxy (`FARDA_API_URL`) — don't ship both half-built. Remove the dead one.
7. Fix the data model: multi-prescription/multi-medication; reconcile schema ↔ migrations (add the Dose table).
8. Encryption at rest + PHI access audit logging; stop logging tokens/PHI; sign BAAs (OpenAI/Twilio/Stripe/Atlas) or self-host OCR.

**P2 — Make it shippable (weeks–months):**
9. BLE: declare permissions, request them at runtime, actually call the sync routine, persist/upload events; finish calibration.
10. Replace mock screens (Home, Plan) with real data; build caregiver UI; implement billing or remove the paywall.
11. Delete the abandoned architectures (bloc/freezed/get_it/dio/retrofit on the app; numeric-id model layer + scaffold on the main API; dead files on the vial API).
12. Real test suites + CI; reconcile docs with code; standardize tooling (one linter, one package manager), secure storage on the client.

---

## 9. Bottom line

The **product concept is sound and substantially prototyped** — phone-OTP auth, OCR-driven prescription capture, dose scheduling, mood logging, and a device-ingestion + caregiver backend all exist in some form, and the login→OCR→dose happy path runs. But this is a **demo, not a product**: the flagship hardware feature can't run, roughly **every patient-data endpoint on the main API is unauthenticated and IDOR-able**, **live credentials (including the PHI database password) are committed**, device events can be spoofed, and a large fraction of the UI is mock data. For a system handling medication and health data, the security and compliance posture is **unsafe and not HIPAA-ready**. The path forward is clear and front-loaded: rotate secrets, lock down auth/authz, fix device trust, then resolve the half-finished two-backend architecture before adding any more features.
