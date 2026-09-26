# Roadmap (v2)

Rule: **no phase starts until the previous phase's exit criteria are met.** Features are cheap to add later; bad movement is expensive to fix later.

## Phase 0 — Architecture and design ✅

- [x] Physics approach comparison and recommendation ([TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md))
- [x] Core physics and catch-system spec with tuning parameters ([PHYSICS_DESIGN.md](PHYSICS_DESIGN.md))
- [x] Controls, prototype scope, design concerns ([GAME_PLAN.md](GAME_PLAN.md))
- [x] Movement quality test plan and exit gate ([TESTING.md](TESTING.md))
- [x] Reference clip analysis, and the resulting v2 design revision ([REFERENCE_ANALYSIS.md](REFERENCE_ANALYSIS.md))
- [x] **Approval of the v2 architecture** (2026-09-26)

**Exit:** explicit approval. ✅

## Phase 1 — Minimal physics prototype ← *current*

Scope is exactly GAME_PLAN §8: one stickman, one bar, controls, camera, reset and the debug tools.

*Renumbered at approval:* the approved P1.1 "physics foundation" merges the planned toolchain and solver-core milestones.

| Milestone | Contents | Status / what you get |
|---|---|---|
| **P1.1 Physics foundation** | Toolchain; pure 2D core (`Solver2D`, `Collide2D`, `Rig`, `Sim`, `Tuning`, `Scenarios`); fixed step + time scale + interpolation; contacts; springy torque-limited joints; kinematic moving anchors; reset and recovery; live tuning; debug overlay and controls; 4 test layers (40 headless tests, built-place self-test, client harness, in-Studio self-test) | **Built and tested headlessly.** Studio run and human look/feel pending (STUDIO_VALIDATION.md). Deliverable: `BarGym.rbxl` with the Hang / Drop / Tumble / Wheel test scenes. |
| **P1.2 First playable** | Grip on the bar from gameplay; input router (touch-down buttons Layout A, keyboard, gamepad) → Arch/Tuck/Pike shape control with close/open speeds; pumping (A4); debug tuning panel generated from `Tuning`; presets | Build 1: *"Pump to a giant. Does it respond instantly? Do the limbs feel alive?"* |
| **P1.3 Flight** | Let Go, flight, twist (both modes, target projection), fall onto the floor and auto-reset; R1–R3 measurable | — |
| **P1.4 Intentional grab** | Attempts, early and late windows, rollback grace, cooldown, reach and twist gates, swept test, momentum continuity, catch blend, feedback, session log, Layout B, debug instant replay; A9–A15 | Build 2: *"Release and regrab. Fair? Satisfying? Like the reference?"* |
| **P1.5 Tuning rounds** | Playtests (TESTING §6), reference comparison (TESTING §3), preset iterations; max 3 rounds before a diagnosis checkpoint | A new build each round |

**Exit:** the TESTING §7 gate is met. If not after 3 rounds, follow the diagnosis path (which may include the native-physics fallback spike).

**Scope guard:** these are logged and deferred during Phase 1:
- more bars, maps, ground movement, equipment
- scoring and HUD beyond the debug overlay
- avatars, menus, multiplayer

## Phase 2 — Movement depth (only after the gate)

1. **Player replay tool:** speed control, free and cinematic cameras, vertical clip framing, our own UI. The reference shows this drives clip creation.
2. **Ground movement on the same solver:**
   - standing "ready" pose with balance assist
   - physical jump from a crouch
   - landing on feet
   - hand-plants, handstands, handsprings, vaults
3. **Equipment kit** as tagged parts + world slice:
   - pole-tip and stub grips
   - in-plane beams and frames (segment grips)
   - kinematic rotating wheels
   - reactive (free-spinning) equipment, instanced per player
4. Elbows or render-only secondary motion, if tests show limbs look stiff. One-hand catch only if tests show a need.
5. Trick detection (flips, twists, shapes, releases), for testing and future scoring.

**Exit:** new mechanics pass the automated tests and a shortened playtest without hurting the Phase 1 metrics.

## Phase 3 — Avatars and multiplayer foundation

- **Avatar spike:**
  - pose R15 from the 5-body skeleton through `Motor6D.Transform`
  - layered clothing and dynamic heads
  - IK hands
  - standard scaling, stickman mode
  - performance with 20 avatars on the low-end phone
- **Networking spike:** Path A (snapshots) vs Path B (Server Authority running the core). Measure:
  - corrections and catch reversals
  - bandwidth and server CPU
  - feel at 150–250 ms simulated latency

  Pick one and record the evidence in TECHNICAL_DESIGN.
- **Lane-based sandbox server** for 15–20 players:
  - remote interpolation, no player collision
  - server plausibility checks
  - slow-mo policy (GAME_PLAN §7)

**Exit:**
- remote players smooth at 150 ms
- local feel unchanged (latency test re-run)
- low-end phone ≥ 30 fps in a 20-player server

## Phase 4 — Game layer

- Sandbox lanes and courses in our own art direction
- Game modes (to be designed then)
- Clip tools polish, record prompts, clean-recording mode
- Progression, data saving, cosmetics and monetization; economy decided by the server
- Mobile button layout editor, settings, onboarding

## Phase 5 — Launch preparation

- Performance and crash pass on the device matrix; analytics
- Icon, thumbnails, trailer clips; closed test with small short-form video creators; public launch

## Decisions log

| Date | Decision | Where |
|---|---|---|
| 2026-09-26 | Hybrid architecture (pending approval) | TECHNICAL_DESIGN §3–4 |
| 2026-09-26 | Catching is intentional: press-only, forgiving windows, anti-mash; never automatic by default | PHYSICS_DESIGN §7 |
| 2026-09-26 | Prototype uses a stickman on a fixed skeleton; avatars later on the same skeleton | TECHNICAL_DESIGN §6, §8 |
| 2026-09-26 | Networking path decided by a Phase 3 spike; the core stays compatible with both | TECHNICAL_DESIGN §7 |
| 2026-09-26 | **v2 after reference study:** planar (2.5D) core; 2D rigid-body solver with compliant motors and contacts replaces the reduced-coordinate model; foot segment added; native crash hand-off removed; smaller catch radius with timing-based forgiveness; no hitstop or shake by default | REFERENCE_ANALYSIS §5, PHYSICS_DESIGN v2 |
| 2026-09-26 | Proposed (pending approval): lane-based 2.5D world; slow-mo live in solo/private servers plus a replay tool; reactive equipment per-player | GAME_PLAN §7, TECHNICAL_DESIGN §7 |
| 2026-09-26 | Architecture approved; P1.1 = physics foundation (milestones renumbered) | This file |
| 2026-09-26 | P1.1 as built: arms split into upper arm + forearm with a strong near-straight elbow motor (6 bodies); solver defaults 240 Hz × 4 substeps, jointHertz 240 with a stiffness cap at ¼ substep rate; velocity-expanded speculative contacts | PHYSICS_DESIGN §2, §4 |
