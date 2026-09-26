# Technical Design (v2)

Status: **Approved.** P1.1 (physics foundation) is implemented; §6 lists what exists.

v2 incorporates the reference-clip study ([REFERENCE_ANALYSIS.md](REFERENCE_ANALYSIS.md)). The main changes from v1:
- The custom core becomes a **planar (2.5D) rigid-body solver with compliant joint motors and real contacts** instead of a reduced-coordinate model with scripted states.
- The native-ragdoll crash hand-off is removed.
- Moving equipment is part of the core.
- The multiplayer time-scale conflict is flagged.

This document covers:

1. the physics architecture decision
2. the recommended architecture
3. the prototype's code architecture
4. how multiplayer, avatars, replays and anti-exploit fit later
5. risks

Physics details and every tuning parameter are in [PHYSICS_DESIGN.md](PHYSICS_DESIGN.md). Measuring movement quality is in [TESTING.md](TESTING.md).

---

## 1. Engine facts this decision rests on

Verified September 2026 against the live Roblox API dump and the Creator Docs:

| Fact | Consequence |
|---|---|
| There is **no physics time-scale property** in the live API. `WorldRoot:StepPhysics` is plugin-only. | True slow motion with native physics means rescaling gravity, velocities and every actuator by hand. |
| `workspace.Gravity` is one global number. | Moon gravity works natively only as a global value. |
| Native physics can run at a fixed internal step (`PhysicsSteppingMethod = Fixed`, `UseFixedSimulation`). | Native physics is consistent across frame rates on its own. |
| **Server Authority** (client prediction + rollback) has been live for all creators since July 2026. It uses `RunService:BindToSimulation` (≤ 60 Hz), attributes for custom state (≤ 64 per instance) and the Input Action System, and requires `StreamingEnabled`, Deferred signals and fixed simulation. | Anti-exploit is no longer a reason to pick one approach: native physics and a custom simulation can both be server-authoritative. |
| Spatial queries (`Raycast`, `Spherecast`, `Blockcast`, `Shapecast`, `GetPartBoundsInRadius`) and `BulkMoveTo` are Simulation Access. | A custom simulation can read map geometry, even inside a server-authoritative simulation. |
| `UnreliableRemoteEvent` payloads are limited to about 900–1000 bytes. | Custom replication uses small packed snapshots (about 50 bytes). |
| The Animator only overwrites `Motor6D.Transform` while tracks are playing (between PreAnimation and PreSimulation). | Avatars can be posed from our simulation. |
| Input events arrive once per rendered frame, with no timestamp inside the frame. | Input timing is frame-quantized (±16 ms at 30 fps) under every approach. |

## 2. What the reference clips require

The architecture must deliver the following. The evidence is in REFERENCE_ANALYSIS §2–4.

1. **Planar (2.5D) motion:** a side-view plane, with twist as a 3D render layer.
2. **Unbroken momentum** through release and catch.
3. **Compliant, alive limbs:** held by springy joints that give under load.
4. **Real contacts:** landing on feet or hands, handstands, vaults, lying across edges. These are core to the original (Phase 2 for us), not crashes.
5. **Moving equipment:** rotating spoked wheels, pivoting handles.
6. **Slow motion that slows the whole world**, equipment included, plus moon gravity.
7. **Replays** at variable speed for clip creation.

## 3. The three approaches

### Approach 1 — Roblox native physics + custom controllers

About 5–10 unanchored parts with `HingeConstraint` servos (Arch/Tuck), a runtime grip constraint, and a `PlaneConstraint` to keep it planar.

**Advantages**
- Contacts, friction, landings, vaults and handstands against any geometry come for free.
- Moving and reactive equipment come for free.
- Replication and C++ performance come for free.
- The reference clearly relies on general contact physics, which is the **strongest argument for native**.

**Disadvantages**
- **Slow motion:** there's no time scale. The reference shows slow-mo slowing *everything*, character and equipment alike, uniformly and smoothly. Faking that means rescaling every force, velocity, servo and spring on every change, which is fragile and only approximate.
- **Opaque feel:** swing energy, joint softness and servo behavior come from a solver we can't see into. Servos on light limbs at high spin rates jitter or go soft.
- **Catch quality:** there's no way to rewind for fair late grabs. Snapping hands onto a grip makes a correction impulse, and smoothing it adds latency.
- **Multiplayer:** many-assembly ragdolls replicate heavily and jitter. Under Server Authority, a chaotic ragdoll is close to the worst case for mispredictions.
- **Replays:** snapshots only; no input-log verification.

### Approach 2 — Fully custom 3D character physics

A general 3D ragdoll with 3D contacts against arbitrary geometry, all in Luau.

**Advantages**
- Total control: slow-mo, determinism, rollback, tuning.

**Disadvantages**
- A full 3D physics engine project: 3D contacts against arbitrary meshes, 3D friction, stability.
- The heaviest in Luau.
- **Most of it is unnecessary**, because the reference game is planar.

### Approach 3 — Hybrid with a planar custom core (recommended)

| Responsibility | Owner |
|---|---|
| **Everything the player's body does:** swinging, shaping, release, flight, catch, landing and contact, plus moving/reactive equipment the player interacts with | **Custom 2D core:** 5 rigid bodies, compliant joint motors, contacts, grip joints, equipment bodies. Pure Luau, fixed step, in the player's motion plane. |
| Twist, and the 3D look of the body | Render layer: 2D state + twist angle → 3D pose |
| Map authoring | Normal Studio parts, tagged. The core builds a **2D world slice** from the part shapes the motion plane cuts through. |
| Rendering, avatars, UI, audio | Roblox (anchored rig via `BulkMoveTo` in the prototype; R15 avatars through `Motor6D.Transform` later) |
| Decorative props and debris | Native Roblox physics (not gameplay-relevant) |
| Networking | Custom snapshots or Server Authority running the same core (§7) |

**Advantages**
- Everything the reference shows is covered by **one set of equations**: contacts, compliant limbs, momentum continuity, equipment. There are no mode switches and no hand-offs.
- Slow-mo and moon gravity are exact and apply to the player's whole simulated world, equipment included.
- A 2D solver with 5 bodies is small: about 1 M simple operations per second at 240 Hz, measured against the budget in §10.
- Deterministic on a device, rewindable (fair late grabs, replays), and unit-testable outside Roblox.
- Planar gameplay removes steering from the controls, which is a big win for mobile.

**Disadvantages (honest)**
- **We own a 2D contact solver.** That's a real engineering component: joints, motors, contacts, friction, warm starting, roughly 1.5–2.5k lines. It's well understood (Box2D-style), and heavy automated tests (TESTING A-series) cover it, but it's more work than v1's reduced-coordinate model.
- **World-slice limits.** Gameplay collision supports primitive shapes: blocks, wedges, cylinders and balls cut by the plane, plus authored segments and points. Arbitrary meshes need simple proxy shapes. That's acceptable for this art style.
- **The planar product constraint.** Maps are built as lanes or planes (see GAME_PLAN §7). That's a product decision, not just a technical one.
- **Shared reactive equipment in multiplayer** needs a rule (§7).

**Why v1's reduced-coordinate model was dropped:** it's exact for hanging and flight, but it can't express multi-contact landings, handstands, vaults, lying on edges or reactive wheels without a growing list of special cases. The reference shows all of these, so the general 2D solver is the safer base even though the prototype only uses one bar and the floor.

## 4. Comparison against the required criteria

Ratings: ★★★ strong · ★★ workable with effort · ★ weak or risky.

| Criterion | 1 Native + controllers | 2 Fully custom 3D | 3 Hybrid, planar core |
|---|---|---|---|
| Very responsive mobile controls | ★★ Instant with local ownership; servo softness | ★★★ | ★★★ |
| Smooth swinging and momentum | ★★ Solver-dependent | ★★ Hard to get right in 3D | ★★★ Small 2D solver, tested |
| Arch / Tuck / Let Go / Twist | ★★ | ★★★ | ★★★ Twist as a designed layer |
| Intentional grab and regrab | ★ No rewind, jerky snap | ★★★ | ★★★ Windows, swept test, rollback |
| Flips and rotation | ★★★ | ★★ | ★★★ |
| Game-friendly momentum | ★ | ★★★ | ★★★ |
| Contacts (landings, handstands, vaults) | ★★★ Free | ★★ Hard in 3D | ★★★ 2D contacts |
| Slow motion (whole world) | ★ | ★★★ | ★★★ |
| Moon gravity | ★★★ | ★★★ | ★★★ |
| Multiplayer sync | ★★ Heavy ragdoll replication | ★★ | ★★★ Tiny snapshots or Server Authority |
| Device performance | ★★★ C++ | ★ Heavy | ★★★ 5 bodies in 2D |
| Network latency | ★★ The same for all: own input instant, others ~100–150 ms | ★★ | ★★ |
| Exploit resistance | ★★ Server Authority possible, but chaotic ragdolls mispredict | ★★ | ★★★ Compact state; Server Authority practical |
| Replay and recording | ★★ Snapshots only | ★★★ | ★★★ |
| Future maps and equipment | ★★★ Anything | ★ | ★★ Primitive shapes + tagged equipment; meshes need proxies |
| Development complexity | ★★ Low start, fighting the solver later | ★ Highest | ★★ Medium-high, bounded, testable |
| Precise tuning | ★ | ★★★ | ★★★ |
| Consistent across frame rates | ★★★ (slow-mo hack aside) | ★★★ | ★★★ |
| Many players per server | ★★ | ★★ | ★★★ Server relays or runs a cheap 2D solver per player |

**When Approach 1 would be right instead:** if slow-mo weren't core, or if gameplay were full 3D free roaming with physical interaction between players. Neither is the case.

**Fallback:** if the prototype fails its feel gate after the planned tuning rounds (TESTING §6), we build a 1–2 day native-physics spike of the same scene (planar-constrained ragdoll) before changing direction.

## 5. Runtime architecture

```
                         ┌──────────────────── shared (ReplicatedStorage) ─────────────────────┐
                         │  Gym core (pure Luau; no Instances inside step)                      │
                         │   Tuning · Body · Solver2D · Collide2D · WorldSlice · Equipment      │
                         │   Shape · Twist · Catch · Sim                                        │
                         │   step(state, inputFrame, dt, worldSlice) -> state, events           │
                         └────────────────────────────────▲────────────────────────────────────┘
 client ──────────────────────────────────────────────────┼──────────────────────────────────────
  Touch / Keyboard / Gamepad ─► InputRouter ─► InputFrame ┘
  RenderStep (after Input, before Camera):
    1. InputRouter.collect()
    2. SimDriver.advance(realDt)  — fixed 240 Hz steps, accumulator, timeScale, step cap
    3. RigRenderer.draw(interpolate(prev, curr, alpha), twist)   — BulkMoveTo, same frame
    4. CameraController.update()   — side view, smooth follow
    5. Feedback.handle(events)     — sound, haptics
    6. Debug overlay / panel / recorder
 server (prototype): disables default character spawning. Nothing else.
```

Key rules:
- **One-frame input pipeline:** input → simulation → rig and camera in the same render step.
- **Fixed step:** 240 Hz, with an accumulator, render interpolation and a step cap. 240 = 4 × 60, so it maps onto `BindToSimulation` later.
- **Time scale only changes how much sim time is added per frame.** Kinematic equipment moves as a function of **sim time**, so slow-mo slows it too.
- **Deterministic on a device.** Tolerance-equal across devices.
- **Inputs are data** (`InputFrame`): held shape amounts, twist, and press edges with step indices.
- **The world slice is data:** 2D shapes in plane coordinates. It's built when the plane is set and refreshed when tagged parts stream in or out.

## 6. Prototype code architecture

**As built in P1.1 (physics foundation):**

```
default.project.json            Rojo mapping (Players.CharacterAutoLoads = false)
rokit.toml                      Pinned toolchain: rojo 7.7.0, lune 0.10.5, stylua 2.5.2, selene 0.31.0
stylua.toml, selene.toml        Format / lint config
src/shared/Gym/                 PURE CORE: no Roblox types; runs in Roblox and headless (Lune)
  Tuning.luau                   Every parameter: default/min/max/unit/category/description; clamping
  Solver2D.luau                 Bodies (dynamic/kinematic/static), revolute joints + limits + torque-limited
                                spring motors, contacts + friction + restitution, warm start, substeps/relax,
                                stiffness cap, velocity-expanded speculative contacts, metrics, checksum
  Collide2D.luau                Rounded segment (capsule/circle) vs convex polygon, 1–2 point manifolds
  Rig.luau                      6-body gymnast, joints, anatomical angle mapping, poses, motor updates
  Scenarios.luau                P1.1 test scenes: Hang, Drop, Tumble, Wheel (moving anchor)
  Sim.luau                      Fixed-step driver: accumulator, time scale, step cap, reset, NaN/out-of-bounds
                                recovery, events, interpolation helpers
src/shared/GymTests/            Test specs (shared by the Lune runner and the in-Studio self-test)
  TestRunner.luau, StudioRun.luau, Solver.spec, Contacts.spec, Rig.spec, Sim.spec
src/client/                     PRESENTATION ONLY (reads simulation state, never writes physics)
  init.client.luau              Bootstrap; one render step: advance sim -> draw -> camera
  Plane.luau                    2D plane <-> 3D world mapping
  RigRenderer.luau              Stickman parts via BulkMoveTo, interpolated
  WorldRenderer.luau            Course, bar, wheel drawn from the solver's own shapes; contact markers
  CameraController.luau         Calm side view, smooth follow
  DebugOverlay.luau             Timing, energy, momentum, joint error, contacts, angles, events
  DebugControls.luau            P1.1 debug keys/buttons; live tuning attributes (ReplicatedStorage.GymTuning)
src/server/init.server.luau     Runs the quick self-test in Studio on Play; nothing else
tests/run.luau                  Headless test runner (Lune)
tools/place_selftest.luau       Runs the BUILT place's tests through Roblox-style instance requires
tools/client_harness.luau       Runs the BUILT place's client headlessly with engine shims; drives every control
tools/inspect_place.luau        Prints the built place tree
tools/solver_bench.luau         Solver settings comparison (stretch / energy / cost)
tools/lune_mirror.luau          Mirrors src/shared into build/lune for Lune (rewrites Roblox requires to file paths)
```

*Changes vs the plan:*
- `Body.luau` became `Rig.luau`.
- `Scenarios.luau` was added for test scenes.
- Math helpers are inlined (no `Math2D.luau`) for speed.
- Module loading: the core uses plain Roblox `require(script.Parent.X)`, so it's fully typed in Studio. The headless runner loads a mirrored copy with those lines rewritten to file requires.

**Later milestones** (per the plan above):
- `Shape`, input router, touch controls, tuning panel: P1.2
- `Twist`, release/flight logic: P1.3
- `Catch`, session log, feedback, instant replay: P1.4
- `WorldSlice`, `Equipment`: Phase 2

**Original plan (for reference):**

```
src/shared/Gym/   Tuning · Types · Body/Rig · Solver2D · Collide2D · WorldSlice · Equipment
                  Shape · Twist · Catch · Sim
src/client/       Input/InputRouter · Input/TouchControls · Render/RigRenderer · Render/CameraController
                  Render/Feedback · Debug/DebugPanel · Debug/DebugOverlay · Debug/DebugDraw
                  Debug/SessionLog · Debug/InstantReplay
```

**Prototype world (P1.1):**
- a floor, two blocks and a ramp
- one bar crossing the motion plane at 10 studs (point grip)
- a rotating 4-spoke wheel (kinematic moving anchor)

All of this is defined as data in `Scenarios.luau`.

**Prototype character:** a stickman in our own style (not the reference look, see REFERENCE §6), drawn on the 6-body skeleton (teal torso, white limbs, far-side limbs darker). There are no avatars, Humanoid or Roblox character yet.

**Build:** `rojo build -o build/BarGym.rbxl`. Open it in Studio and press Play. Optionally use `rojo serve` for live sync. See README for the test commands.

## 7. Multiplayer (designed for, not built in the prototype)

**Path A — client-authoritative core + snapshots**
- Each client simulates only itself: zero input latency, zero mispredictions.
- 20–30 Hz snapshots over `UnreliableRemoteEvent`, about 50 bytes each: root position, 5 body angles, twist, grip id, flags and a time.
- Remote players are drawn from about 100 ms of interpolation.
- The server relays snapshots and plausibility-checks them.
- Bandwidth: about 1.5 KB/s up and about 30 KB/s down per client at 20 players.

**Path B — Server Authority running the same core**
- `BindToSimulation` at 60 Hz with 4 × 240 Hz sub-steps.
- State in attributes on a predicted instance: 5 bodies × 6 values plus about 10 more ≈ 40 numbers, within 64.
- Inputs through the Input Action System.
- Measure first:
  - floating-point drift causing rollbacks
  - catch reversals (mitigated by the server tolerance in PHYSICS §7.8)
  - server CPU at N players
  - maturity

**Decided in a Phase 3 spike.** Constraints we honour now so both paths stay open:
- a pure core
- a fixed step
- per-step `InputFrame`
- compact state
- no clocks or randomness in `step`
- effects driven by state and events

**Product rules that shape networking:**
- **No player-vs-player collision.** Everyone shares the static equipment.
- **Moving equipment and time scale — a real conflict (flagged).** In the reference, slow-mo slows the whole world, equipment included. In a shared server, one player's slow-mo can't slow the wheel everyone else is using. Options:
  1. **(Recommended for launch)** Slow-mo in **solo and private servers** and in the **replay tool** (record at 1×, play back slowed). Public servers run at 1×. Moon gravity stays per-player, since it only affects your own body.
  2. Per-player equipment clocks: every client runs kinematic equipment on its own sim time. That's consistent for yourself, but remote players riding a wheel won't line up with the wheel as you see it.
  3. A server-wide time scale that the private-server owner controls.
- **Reactive (dynamic) equipment**, like a free-spinning wheel pushed by a player's weight, is **per-player instanced**. Each player simulates their own copy; others see it through that player's snapshot while they use it. Because players never collide, this is invisible in practice.
- Server-side systems (proximity, voice, streaming focus) follow the simulated position through an anchored root part and `ReplicationFocus`. With `StreamingEnabled`, bar and equipment models use persistent or atomic streaming, and the world slice handles parts streaming in and out.

## 8. Avatars (Phase 3, designed now)

- The game is set to R15 only, with body scale limited to standard proportions. Gameplay always uses the fixed 5-body skeleton.
- Avatar root anchored and CFramed from the simulation. Joints are posed by writing `Motor6D.Transform` in PreSimulation, with no tracks playing and the Animate script removed. Twist is applied to the root.
- Elbows stay straight, matching the skeleton. Hands are placed on grips with a small IK correction.
- A stickman mode setting stays, for clarity and clips.
- 20 posed avatars must be measured on the low-end phone.

## 9. Replays, recording and anti-exploit

- **Recording from day one:** the core emits compact per-step pose frames; a ring buffer holds about 15 s at 30 Hz (under 100 KB).
  - Prototype: a **debug instant replay** (proposed): scrub and slow-mo the last 10 s. It's a tuning tool for inspecting catches, not a player feature.
  - Phase 2: the player replay tool with speed control and free cameras (our own UI). The reference shows this is central to clip creation.
- **Anti-exploit (Path A):**
  - speed checked against an energy bound
  - map bounds
  - catches only on existing targets near the reported position
  - legal state order
  - leaderboard runs verified by server re-simulation of input logs within tolerance
- **Anti-exploit (Path B):** authority is built in.
- **Economy** is decided by the server only.

## 10. Performance budgets (reference low-end phone, 1×)

| Item | Budget |
|---|---|
| Core simulation (≈4–8 steps/frame, 5 bodies, ≤ 8 contacts) | ≤ 1.0 ms/frame |
| Prototype rig render (≈15 parts, BulkMoveTo) | ≤ 0.2 ms/frame |
| Debug overlay (when shown) | ≤ 0.3 ms/frame |
| Frame rate | 60 fps on mid phones; never below 30 fps on low-end |

Measured with `debug.profilebegin` markers + MicroProfiler on real devices. If the solver exceeds its budget, the levers are, in order:
1. `solverIterations`
2. `simHz` 240 → 120 with 2 sub-steps
3. broad-phase culling of the world slice

## 11. Technical risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| 2D solver jitter or joint stretch at giant-swing speeds | Mushy or unstable swings | Soft-step solver with warm starting, 240 Hz, joint drift and energy tests (A2, A17), iteration and Hz knobs |
| Compliance tuning: too floppy vs too stiff | Poor control or a robotic look | Per-joint max torque and frequency; reference comparison (TESTING §3) |
| Touch latency and 30 fps input quantization | Catches feel random | Time windows ≥ 2 frames at 30 fps, swept test, rollback grace, per-device tests |
| Low-fps release precision (one 30 fps frame ≈ 9° of swing) | Variable trajectories on weak phones | Accept (the reference has the same limit); measure |
| Momentum transfer or release boost > 1 | Infinite energy loops | `maxSwingSpeed` cap, panel warnings |
| Server Authority reversing catches | Worst possible feel | Tolerant server confirmation; Phase 3 spike before adopting it |
| World slice can't represent some map geometry | Missing collisions | Primitive-only gameplay geometry; proxies for meshes; slice debug drawing |
| Planar constraint vs Roblox players' 3D expectations | Product fit | Lane-based maps (GAME_PLAN §7); decided before map production |
| Per-player slow-mo vs shared moving equipment | Inconsistent multiplayer | §7 options; slow-mo in solo/private and replays for launch |
| Avatar posing edge cases | Visual glitches | Standard R15 scaling, Phase 3 spike, stickman fallback |
| Lune vs Roblox behavior differences | Tests diverge | The core uses plain numbers and its own 2D math; no engine types inside `step` |

## 12. References

- Roblox Server Authority: <https://create.roblox.com/docs/projects/server-authority> (and the Techniques page)
- Live API dump used for verification: `MaximumADHD/Roblox-Client-Tracker` `API-Dump.txt` (September 2026)
- Reference clip analysis: [REFERENCE_ANALYSIS.md](REFERENCE_ANALYSIS.md)
