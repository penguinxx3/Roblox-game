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
| **P1.1 Physics foundation** ✅ | Toolchain; pure 2D core (`Solver2D`, `Collide2D`, `Rig`, `Sim`, `Tuning`, `Scenarios`); fixed step + time scale + interpolation; contacts; springy torque-limited joints; kinematic moving anchors; reset and recovery; live tuning; debug overlay and controls; 4 test layers | **Done.** Tested headlessly (40 tests) and playtested in Studio by the owner: "articulated and believable, stays together, landings good, slow-mo good, camera excellent; could be a little smoother". |
| **P1.2 Movement control** ← *current* | Device-independent input (`Input`) and client router (keyboard, gamepad, minimal touch Layout A); movement `Controller`: Arch / Tuck / Pike with input smoothing, pumping (physical), Let Go with optional release shaping, Twist (hold + momentum modes; render rotation with a mirror snap), standing with balance, crouch-and-release jump, landing absorption and a landing reflex, ground/air/fallen states; smoothness tuning; moon-gravity analysis; `Stand` scene | **Built, playtested once, feedback round 1 done** (PLAYTEST_P1_2.md: tuck, jump, pumping, arch; blind motor A/B). 62 headless tests incl. 21 movement tests (2 guard the liked moon and slow-motion features); built-place self-test 62/62; client harness 71/71. Motor default stays 6 until the blind A/B. Next: second playtest (STUDIO_VALIDATION.md §6). |
| **P1.3 Intentional grab** | Grab attempts, early and late windows, rollback grace, cooldown, reach and twist gates, swept test, momentum continuity, catch blend, feedback, regrab, session log, Layout B, fall + auto-reset loop, debug tuning panel generated from `Tuning`, presets, debug instant replay; A9–A15 | Build 2: *"Release and regrab. Fair? Satisfying? Like the reference?"* |
| **P1.4 Tuning rounds** | Playtests (TESTING §6), reference comparison (TESTING §3), preset iterations; max 3 rounds before a diagnosis checkpoint | A new build each round |

*Renumbered twice:* at approval (P1.1 = physics foundation) and at the start of P1.2, when the owner defined P1.2 as movement control (shape, twist, release, standing, jumping, landing, input) and moved grab/regrab to P1.3. Basic ground movement (stand, jump, land) was pulled forward from Phase 2 at the owner's request.

**Exit:** the TESTING §7 gate is met. If not after 3 rounds, follow the diagnosis path (which may include the native-physics fallback spike).

**Scope guard:** these are logged and deferred during Phase 1:
- more bars, maps, advanced ground movement (hand-plants, handstands, vaults), equipment
- scoring and HUD beyond the debug overlay
- avatars, menus, multiplayer

## Phase 2 — Movement depth (only after the gate)

1. **Player replay tool:** speed control, free and cinematic cameras, vertical clip framing, our own UI. The reference shows this drives clip creation.
2. **Ground movement on the same solver** (standing with balance, physical jump from a crouch and landing on the feet were built early, in P1.2):
   - hand-plants, handstands, handsprings, vaults
   - stepping (foot placement) for bigger shoves and landings
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
| 2026-09-26 | P1.1 Studio playtest passed; P1.2 redefined as movement control; grab/regrab → P1.3 | This file |
| 2026-09-26 | P1.2: light distal segments get extra rotational inertia (`limbInertiaBoost`, mass unchanged): the P1.1 soak's worst joint-limit overshoot was a chaotic 8–15° outlier at every solver setting; with the boost it is < 3° at no CPU cost | PHYSICS_DESIGN §2, TESTING P1.2 |
| 2026-09-26 | P1.2: smoother motion by tuning, not rewrite: motor damping 0.8 → 1.25, input smoothing 8/6 Hz, bar shoulders 18 Hz (they turn the whole hanging body) | PHYSICS_DESIGN §3, TESTING P1.2 |
| 2026-09-26 | P1.2: twist = render rotation about the long axis + an exact in-plane mirror at 90° (conserves momentum and energy), only when the mirrored body is clear of the world; replaces "projected targets" | PHYSICS_DESIGN §6.3 |
| 2026-09-26 | P1.2: foot gets a heel (0.15 studs behind the ankle) and the shank's rounded end stops short of the ankle, so the feet can balance the body | PHYSICS_DESIGN §2 |
| 2026-09-26 | P1.2: standing uses muscle torques (gravity compensation + centre-of-mass balance through the ankles) plus an optional, capped, ground-only `balanceAssist` (on by default: a planar pair of feet can't step) | PHYSICS_DESIGN §6.4 |
| 2026-09-26 | P1.2: moon gravity 0.165 × g confirmed physically consistent; muscle strength keeps following gravity by default (moon plays like Earth in slow motion, matching the reference's ~1.5 s jump airtime); `strengthGravityScaling = 0` gives real-moon strength (≈6× jump height) | PHYSICS_DESIGN §9 |
| 2026-09-27 | P1.2 playtest round 1: fix causes, not symptoms. Air tuck brings the arms in and squeezes (`tuckHertz` 10); bar elbows at the shoulders' 18 Hz and bar hips at 10 Hz (soft ones drained the swing); the swing energy cap is measured against the straight body (it braked tucks); the Arch takeoff keeps the centre of pressure off the toe edge and drops drift damping (it lost a third of the height). Jump height stays realistic (more height barely helps a flip). Standing back flips: optional `jumpSpinAssist`, default off, decision open. Motor 6 vs 8 goes to a blind A/B. | PLAYTEST_P1_2.md, PHYSICS_DESIGN §3, §6.4, §8 |
| 2026-09-27 | Moon gravity and slow motion were the playtester's favourites: their behaviour is kept while the movement is tuned, changed only for a concrete technical issue, and guarded by two tests (slow-motion invariance; moon swing and jump ratios, defaults, persistence). Audit: round 1 left both unchanged (moon half swing 2.81 → 2.80 s, jump ratios 1.15 / 2.75 → 1.16 / 2.78). | PHYSICS_DESIGN §9, PLAYTEST_P1_2.md |
| 2026-09-27 | `motorHertz` default stays 6 until a proper blind A/B of 6 vs 8 is done (STUDIO_VALIDATION §4a); not chosen from automated metrics | STUDIO_VALIDATION §4a |
