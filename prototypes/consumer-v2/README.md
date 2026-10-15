# Farda navy consumer concept — v2

Open **farda-navy-mock.html** in a modern browser. It embeds fonts, images, scripts and styles; no server or installation is required.

Nine views: Today, Calendar, Refills, You, Routine, Vial, Phone reminders, Live Activities and Circle. Deep navy, the original Outfit/wordmark direction, three character poses and interactive calendar navigation.

The [Figma handoff](FIGMA_HANDOFF.md) provides 17 editable Figma screens, prototype links, the screen/node map, verification evidence, and a [Flutter component example](flutter/README.md).

## Try it

1. Today → Log my dose → confirm → correct.
2. Tap the reminder timeline: **8:50 heads-up → 9:00 routine → 9:10 call**.
3. Calendar → October 12, 13 and 16 → filter Refills → move months. Arrow keys move between dates.
4. Refill station → pharmacy handoff → user status updates → receipt → confirm actual supply count.
5. Phone reminders → set up both demo checks → preview a call → answer → optional private check-in with demo PIN **2468** → explicitly confirm an entry.
6. Reset and decline a call instead. No dose is recorded.
7. Live Activities → pre-reminder countdown, compact/expanded Island, stale/off states.
8. Your space → hide/show the companion. Sidebar scenarios switch hardware state.

## Source and checks

- index.html, style.css, model.js, app.js: editable buildless source.
- assets/farda-companion.png: original transparent three-pose artwork.
- ASSET_BRIEF.md: generation method and exact prompt.
- build-standalone.mjs: embeds all dependencies.
- mock.test.mjs: 27 tests covering model behavior, rendering, assets, cadence and core contrast pairs.

From the repository root, run:

    node prototypes/consumer-v2/build-standalone.mjs
    node --test prototypes/consumer-v2/mock.test.mjs

## Honest scope

All data is synthetic and in memory; refresh resets it. No calls, OTPs, pharmacy requests, device commands, notifications or account changes occur.

The cadence timeline advances preview states, not real time. Call opt-in and PIN verification are local simulations, not security controls. The PIN is a published fixture. The OS call/Live Activity views are illustrative, not native implementations. Quiet hours and account-wide daily caps require a production scheduler.

Stock is manually reconciled; dose logs do not decrement it. Label review saves a demo draft, not a new active prescription. Setup and sharing are simulated.

27 tests, syntax and embedding checks pass. Browser/native visual QA and complete accessibility testing remain outstanding because the supported preview environment is unavailable. The separate Figma screens were visually reviewed and their MCP code readback was verified. This is a design handoff; production app routes and services are not replaced.
