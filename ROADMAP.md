# Roadmap

Rule: **no phase starts until the previous phase's exit criteria are met.** Features are cheap to add later; bad movement is expensive to fix later.

## Phase 0 — Architecture and design ← *current*

- [x] Physics approach comparison and recommendation ([TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md))
- [x] Core physics and catch-system spec with all tuning parameters ([PHYSICS_DESIGN.md](PHYSICS_DESIGN.md))
- [x] Controls, prototype scope, design concerns ([GAME_PLAN.md](GAME_PLAN.md))
- [x] Movement quality test plan and exit gate ([TESTING.md](TESTING.md))
- [ ] **Your approval of the architecture** (and answers to GAME_PLAN §10 where possible)

**Exit:** explicit approval. Implementation doesn't start before it.

## Phase 1 — Minimal physics prototype

Scope is exactly GAME_PLAN §8: one stickman, one bar, controls, camera, reset and the debug tools. Nothing else.

| Milestone | Contents | What you get |
|---|---|---|
| **P1.1 Toolchain** | Rojo project, pinned tools (Rokit), Lune test runner, `Tuning.luau` skeleton, lint/format, place builds | Nothing to test yet |
| **P1.2 Hanging swing** | Body model, forward kinematics, center of mass, inertia; hanging dynamics without input; tests A1–A3, A7–A8 | — |
| **P1.3 First playable** | Shape control (Arch/Tuck/Pike) and pumping (A4); stickman renderer with interpolation; side camera; touch (Layout A), keyboard and gamepad input; debug panel v1 and overlay | **Build 1** (`.rbxl`): *"Can you pump up to a giant? Does it respond instantly?"* |
| **P1.4 Flight** | Let Go, flight dynamics, twist (both modes), floor/fall, reset; tests A5–A6 | — |
| **P1.5 Intentional grab** | Attempts, early and late windows, rollback grace, cooldown, alignment and reach, swept test, momentum transfer, catch blend, feedback (sound, camera kick, haptics), session log and export, Layout B; tests A9–A15 | **Build 2**: *"Release and regrab. Does catching feel fair and satisfying?"* |
| **P1.6 Tuning rounds** | Playtests (TESTING §5), preset iterations, fixes; max 3 rounds before a diagnosis checkpoint | A new build each round |

**Exit:** the TESTING.md §6 gate is met. If it's still unmet after 3 rounds, follow the diagnosis path in TESTING.md §6, which may include the native-physics fallback spike.

**Scope guard:** these requests are logged and deferred during Phase 1:
- more bars or maps
- scoring, trick names, regrab counters as player-facing UI
- avatars, cosmetics, sounds beyond catch feedback, menus
- multiplayer

## Phase 2 — Movement depth (only after the gate)

- Several bars and an equipment kit: tagged parts with attributes (height, radius, tilt); tilted bars and vertical poles
- One-hand catch, if playtests show a need (PHYSICS_DESIGN §7.9)
- Landings; crash hand-off to native Roblox ragdoll; body–bar collision decision
- Render-only secondary motion, if limbs look stiff
- Replay ring buffer and slow-mo replay, the base of the future clip tool
- Trick detection (flips, twists, shapes, releases) used only for testing at this stage

**Exit:** new mechanics pass the same automated tests and a shortened playtest without hurting the Phase 1 metrics.

## Phase 3 — Avatars and multiplayer foundation

- **Avatar spike:** pose R15 avatars from the core through `Motor6D.Transform`; check layered clothing and dynamic heads; add arm IK to the bar; enforce standard scaling; add stickman mode. Measure 20 avatars on the low-end phone.
- **Networking spike:** Path A (client-authoritative + snapshots) vs Path B (Roblox Server Authority running the core). Measure mispredictions and corrections, catch reversals, bandwidth, server CPU and feel under 150–250 ms of simulated latency. Pick one, with the evidence written into TECHNICAL_DESIGN.md.
- Sandbox server for 15–20 players: remote-player interpolation, no player collision, server plausibility checks.

**Exit:**
- remote players look smooth at 150 ms latency
- local feel is unchanged from Phase 1 (latency test re-run)
- the low-end phone holds 30 fps in a 20-player server

## Phase 4 — Game layer

- Sandbox map(s) with equipment variety
- Game modes (to be designed then)
- Clip tools: vertical camera, slow-mo replay, record prompt
- Progression, data saving, cosmetics shop and monetization; server-side economy only
- Mobile button layout editor, settings menu, onboarding

## Phase 5 — Launch preparation

- Performance and crash pass on the device matrix; analytics funnels
- Icon, thumbnails, trailer clips; closed test with small short-form video creators; public launch

## Decisions log

| Date | Decision | Where |
|---|---|---|
| 2026-09-26 | Hybrid architecture: custom gameplay-physics core + native Roblox for world queries, crashes and props (pending approval) | TECHNICAL_DESIGN §2–3 |
| 2026-09-26 | Catching is intentional: press-only attempts, forgiving windows, anti-mash cooldown; never automatic by default | PHYSICS_DESIGN §7 |
| 2026-09-26 | Prototype uses a stickman on a fixed skeleton; avatars later on the same skeleton | TECHNICAL_DESIGN §5, §7 |
| 2026-09-26 | Networking path (custom snapshots vs Server Authority) decided by a Phase 3 spike; the core stays compatible with both | TECHNICAL_DESIGN §6 |
