# Technical Design

Status: **Proposed — awaiting approval.** Nothing in here is implemented yet.

This document covers:

1. the physics architecture decision (three approaches compared)
2. the recommended architecture
3. the prototype's code architecture
4. how later systems (multiplayer, avatars, replays, anti-exploit) fit without a rewrite
5. technical risks

Physics math, state machine and every tuning parameter live in [PHYSICS_DESIGN.md](PHYSICS_DESIGN.md).
How we judge "is the movement good" lives in [TESTING.md](TESTING.md).

---

## 1. Engine facts this decision rests on

Verified in September 2026 against the live Roblox API dump and the Creator Docs, not from memory:

| Fact | Consequence |
|---|---|
| There is **no physics time-scale property** in the live API. `WorldRoot:StepPhysics` is plugin-only. | True slow motion with native physics is only possible by rescaling gravity, velocities and every actuator by hand. |
| `workspace.Gravity` is a single global number. | Moon gravity works natively, but only as a global value. You can't give just one body its own gravity without extra forces. |
| Native physics can run at a fixed internal step (`PhysicsSteppingMethod = Fixed`, `UseFixedSimulation`). | Native physics is consistent across frame rates on its own. |
| **Server Authority** (client prediction + rollback) has been live for all creators since July 2026. Custom logic runs in `RunService:BindToSimulation` (at most 60 Hz). Custom state syncs through attributes (max 64 per instance). Inputs come through the Input Action System. It requires `StreamingEnabled`, Deferred signals and fixed simulation. | Anti-exploit is no longer a reason to pick one approach over another. Both native physics and a custom simulation can run server-authoritative. |
| `Raycast` / `Spherecast` / `Blockcast` / `Shapecast` / `GetPartBoundsInRadius` / `BulkMoveTo` are marked Simulation Access. | A custom simulation can use the engine's collision queries, even inside a server-authoritative simulation. |
| `UnreliableRemoteEvent` payload limit is about 900–1000 bytes. | Custom pose replication must use small, packed snapshots. That's easy: about 50 bytes each. |
| The Animator overwrites `Motor6D.Transform` between PreAnimation and PreSimulation, but only while animation tracks are playing. `Motor6D.Transform` is Simulation Access. | Real avatars can be posed from our simulation by writing joint transforms in `PreSimulation` with no tracks playing. |
| Input events are delivered once per rendered frame, with no timestamp inside the frame. | Input timing precision is limited by frame rate (±16 ms at 30 fps). Catch and release windows must be designed around this whichever approach we pick. |

---

## 2. The three approaches

### Approach 1 — Roblox native physics + custom controllers

The body is about 10 unanchored parts joined by `BallSocketConstraint` / `HingeConstraint`:
- Arch and Tuck drive servo target angles.
- Grabbing creates a constraint between hands and bar (`CylindricalConstraint` or `BallSocketConstraint`). Letting go disables it.
- Twist is applied as a torque.
- The client owns its body (network ownership) or it runs under Server Authority prediction.

**Advantages**
- Fastest route to *something* swinging.
- Collision with any geometry (meshes, terrain, moving parts) for free. Physical equipment (swinging trapeze, ropes, props) for free.
- Movement replication for free.
- C++ solver: very fast, runs at a fixed internal step.
- Realistic tumbling and crashes emerge on their own.

**Disadvantages**
- **Slow motion is the deal-breaker.** There is no time scale. Faking it means scaling gravity by s², every velocity by s, and every servo torque, servo speed, spring and damper by s² or s. Every future force source has to be re-scaled too, both entering and leaving slow-mo. Community libraries (e.g. "MoonScale") do this broadly, which shows it is possible but approximate. Slow-mo and moon gravity together are exactly the settings in the viral clips, so they can't be approximate.
- **The swing feel comes from a solver we can't see into.**
  - Pumping efficiency, energy loss per swing and joint softness depend on how the solver treats joint stiffness, mass ratios and iteration counts.
  - Servos on light limbs at high angular speed tend to jitter or go soft.
  - When a swing "feels wrong" there's no single number to change.
- **No rewinding.** We can't rewind engine physics to grant a slightly-late grab, and we can't check a catch using the hands' swept path within one step.
- **Snapping the hands to the bar is jerky.** Creating a constraint while the hands are 0.5 studs away produces a large correction impulse. Smoothing it (AlignPosition ramps) adds latency and mushiness to the most important moment in the game.
- **Other players' bodies.** A ragdoll made of many constraint-connected assemblies replicates as many separate objects. Other players' limbs can stretch or jitter under packet loss. Under Server Authority, a chaotic multi-body ragdoll is close to the worst case for mispredictions.
- **Replays.** Engine physics isn't deterministic, so replays must be recorded pose snapshots. That part is fine, but there are no input-log replays or re-simulation checks.

### Approach 2 — Fully custom character physics

Everything is written in Luau:
- a general articulated ragdoll (e.g. position-based dynamics), collision against the world, contacts, and friction
- a fixed-step loop, rendering by moving anchored parts, and our own networking

**Advantages**
- Total control: time scale, gravity, catch rules, momentum and determinism are all ours.
- Frame-rate independent, with a fixed step and render interpolation.
- Rewind and re-simulate is possible (for late-grab grace, replays and input-log checks).
- Tiny network footprint; the server only relays small snapshots.

**Disadvantages**
- **Largest build and maintenance cost by far.**
  - A robust general ragdoll with world contact and friction in Luau is a physics-engine project.
  - Every future map feature (slopes, meshes, moving platforms, physical equipment) needs custom collision and response.
- **Luau cost.** A general ragdoll with contacts at 240 Hz fits one player on a low-end phone, but not with much headroom. Contact-heavy moments (landings, tumbles) are the expensive ones.
- **It re-builds what the engine already does well.** Uncontrolled tumbling and crashing looks as good or better with native physics.
- **More code, more bugs.** Stability issues (explosions, jitter, drift) become ours to find and fix.

### Approach 3 — Hybrid (recommended)

Split by what each system is good at:

| Responsibility | Owner |
|---|---|
| **Controlled movement** — hanging and swinging, Arch/Tuck/Pike shaping, Let Go, flight, flips, twists, intentional catch, momentum transfer | **Custom gameplay-physics core** (small, reduced-coordinate model, pure Luau, fixed step) |
| Collision *detection* against the map (floor, walls, obstacles) | Engine spatial queries (`Spherecast`/`Shapecast`/`Raycast`) |
| **Uncontrolled movement** — crash and ragdoll after a failed landing, props, decoration (post-prototype) | **Native Roblox physics** (hand-off from the core) |
| Bars and equipment | Regular Studio parts tagged `Bar` with attributes. The core reads their geometry. |
| Rendering | Anchored rig moved with `BulkMoveTo` (prototype), later the player's R15 avatar posed through `Motor6D.Transform` |
| Networking (post-prototype) | Either custom snapshot replication or Roblox Server Authority running the same core in `BindToSimulation` (see §6) |

The core is **not** a general ragdoll. It's a purpose-built model of a gymnast:
- a chain of 4 rigid segments (arms, trunk with head, thighs, shanks)
- whose shape is driven by the player's Arch/Tuck input
- simulated exactly in two modes:
  - **Hanging:** 1 free swing angle around the bar
  - **Flight:** a projectile center of mass, plus rotation that conserves angular momentum while the body shape changes its inertia
- plus a designed catch system

This is how real gymnastics biomechanics models work. It's also why tucking spins you faster and good Arch/Tuck timing pumps the swing; neither has to be faked. Details in [PHYSICS_DESIGN.md](PHYSICS_DESIGN.md).

**Advantages**
- Everything that decides whether the game *feels* good is ours: exact, tunable, time-scalable, rewindable.
- The model is tiny: a few hundred math operations per step. Cost is negligible even at 240 Hz on low-end phones, and the server can afford to run it for every player (Server Authority path).
- The rest stays native: arbitrary map geometry for collision checks, native ragdoll for crashes, normal Studio map building.
- The core is a pure module with no Instances. It is unit-testable outside Roblox (Lune) and portable into `BindToSimulation` later.

**Disadvantages (honest)**
- **Two physics worlds.** The hand-off between the core and native ragdoll (crash) must convert state carefully. It's done in one place, one way per crash.
- **Rich contact during controlled movement isn't free.** If the body brushes a wall mid-swing, the core has to decide what happens: crash, slide, or later a wall-kick mechanic. We accept this. In controlled states, touching the world is a designed event, not general contact.
- **Reactive equipment is our job.** A trapeze or rings that swing because of the player's weight must be modeled as extra links in the core. That's more work than native, but still bounded.
- **Crash ragdolls don't slow down.** The native ragdoll can't be put in slow motion. Options: keep crashes short, or add a simple custom tumble for slow-mo sessions. Decided in Phase 2.
- **We own the numerics.** This is mitigated by automated tests: energy, stability, frame-rate independence (see [TESTING.md](TESTING.md)).

---

## 3. Comparison against the required criteria

Ratings: ★★★ strong · ★★ workable with effort · ★ weak or risky.

| Criterion | 1 Native + controllers | 2 Fully custom | 3 Hybrid |
|---|---|---|---|
| Very responsive mobile controls | ★★ Local ownership gives instant response, but servo lag and softness make Arch/Tuck feel mushy | ★★★ We define every response curve | ★★★ Same as 2 |
| Smooth swinging and momentum | ★★ Works, but energy behavior comes from the solver; pumping consistency is hard | ★★★ If built well (big if) | ★★★ Exact reduced-coordinate model, no drift or jitter |
| Arch / Tuck / Let Go / Twist | ★★ Arch/Tuck OK through servos; twist torques fight the solver | ★★★ | ★★★ |
| Intentional grab and regrab | ★ No rewind, no swept test, jerky snap | ★★★ | ★★★ Windows, swept test, rollback for late grabs, exact momentum transfer |
| Flips and body rotation | ★★★ Emergent and realistic | ★★ Depends on solver quality | ★★★ Momentum conserved, tuck-speeds-up-spin is exact |
| Realistic but game-friendly momentum | ★ Bending engine physics needs hacky extra forces | ★★★ | ★★★ Pump gain, transfer and boost are single numbers |
| Slow motion | ★ No time scale; manual rescaling is fragile | ★★★ | ★★★ (crash ragdoll excepted, see above) |
| Moon gravity | ★★★ | ★★★ | ★★★ |
| Multiplayer sync | ★★ Free, but many-assembly ragdolls replicate heavily and jitter | ★★ We must build it (moderate) | ★★★ Tiny snapshots, or Server Authority running the same core |
| Performance across devices | ★★★ C++ | ★★ General ragdoll plus contacts in Luau is heavy | ★★★ Tiny model |
| Network latency | ★★ Same for everyone: your own input is instant, others are seen ~100–150 ms late | ★★ | ★★ |
| Exploit resistance | ★★ Client-owned by default; Server Authority fixes it, but chaotic ragdolls mispredict | ★★ Client-authoritative unless re-simulated | ★★★ Compact state makes plausibility checks easy, and running the core under Server Authority is realistic |
| Replay and recording | ★★ Snapshots only | ★★★ Snapshots and input logs | ★★★ |
| Future maps and equipment | ★★★ Anything | ★ Custom collision for everything | ★★ Map collision via engine queries; reactive equipment is modeled per type |
| Development complexity | ★★ Low start, high cost fighting the solver later | ★ Highest | ★★ Medium, with clear boundaries |
| Precise tuning | ★ | ★★★ | ★★★ |
| Consistent across frame rates | ★★★ Fixed internal step (slow-mo hack aside) | ★★★ Fixed step + interpolation | ★★★ |
| Many players per server | ★★ | ★★★ Server only relays | ★★★ |

**When Approach 1 would be the right call instead:**
- if the game were mainly about chaotic physical interaction (knocking each other over, pushing objects)
- if slow motion weren't a core feature
- if we needed something in days rather than quality

None of those apply here.

**Hybrid variants considered and rejected**
- *Native body + custom slow-mo and grab layers.* Slow-mo is still the fragile rescale hack, and catch snapping is still jerky.
- *Custom core driving a native "puppet" through `AlignPosition`/`AlignOrientation`* (so the body pushes world objects). This adds lag and jitter to the controlled movement. It may come back later for cosmetic secondary motion only.

**Fallback plan:** if the hybrid prototype fails its feel gate after the planned tuning rounds (see [ROADMAP.md](ROADMAP.md)), we build a 1–2 day native-physics spike of the same scene. That gives us evidence, not opinion, before changing direction.

---

## 4. Recommended runtime architecture

```
                         ┌───────────────── shared (ReplicatedStorage) ─────────────────┐
                         │  Gym core (pure Luau, no Instances inside step)                │
                         │   Tuning · Body · Shape · Hang · Flight · Catch · Sim          │
                         │   step(state, inputFrame, dt, world) -> state, events          │
                         └───────────────────────────────▲──────────────────────────────┘
                                                         │
 client ─────────────────────────────────────────────────┼─────────────────────────────────
  Touch / Keyboard / Gamepad ─► InputRouter ─► InputFrame┘
                                                         │
  RenderStep (priority: after Input, before Camera):     │
    1. InputRouter.collect()                             │
    2. SimDriver.advance(realDt)  ── fixed 240 Hz steps ─┘  (accumulator, timeScale, max steps)
    3. RigRenderer.draw(interpolate(prev, curr, alpha))     (BulkMoveTo, same frame)
    4. CameraController.update()
    5. Feedback.handle(events)  (sound, camera kick, haptics)
    6. DebugOverlay / DebugPanel

 server (prototype): disables default character spawning. Nothing else.
```

Key rules:
- **One-frame input pipeline.** Input arrives → the simulation advances → the rig and camera move, all inside the same render step. There's no waiting on the network or on physics.
- **Fixed step, 240 Hz by default.** Tunable 120/240/480. An accumulator drives it, render interpolation smooths between steps, and the step count per frame is capped so a slow frame can't snowball. 240 is a multiple of 60, so the same code can later run as 4 sub-steps per 60 Hz `BindToSimulation` tick.
- **Time scale only changes how much sim time we add per frame.** Physics code never sees it. Slow-mo is therefore exact.
- **The core is deterministic on a given device.** Same inputs per step give the same result. Across devices it matches to within tolerance (floating-point library differences). We never promise bit-exact results across platforms.
- **The core never touches Instances inside `step`.** The world (bars, floor, colliders) is passed in as plain data. Collision queries go through a small interface, which is the engine in the game and a stub in tests.
- **Inputs are data.** The core only consumes an `InputFrame` of held states, an analog amount, and press edges with their step index. Touch, keyboard, gamepad, Input Action System and replays all produce the same structure.

---

## 5. Prototype code architecture

Only what the prototype needs. Rojo project; the files are the source of truth.

```
default.project.json            Rojo mapping. Players.CharacterAutoLoads = false; test world (floor + 1 bar)
rokit.toml                      Pinned toolchain: rojo, lune, stylua, selene
selene.toml, stylua.toml        Lint / format config
src/shared/Gym/
  Tuning.luau                   Every parameter: default, min, max, unit, category, description
                                (drives the debug panel and the tests)
  Types.luau                    State / InputFrame / Event types
  MathUtil.luau                 Small vector and quaternion helpers (pure Luau)
  Body.luau                     Segment lengths and masses, forward kinematics, center of mass, inertia tensor
  Shape.luau                    Arch/Tuck/Pike targets, per-joint spring tracking
  Hang.luau                     Two-hand swing about the bar (1 free angle + shape)
  Flight.luau                   Projectile center of mass, angular momentum, twist control
  Catch.luau                    Grab attempts, windows, swept proximity, rollback grace, momentum transfer
  Sim.luau                      State machine, fixed-step driver API, history ring buffer, events
src/client/
  init.client.luau              Bootstrap, render-step binding, disables default controls
  Input/InputRouter.luau        Touch/keyboard/gamepad → InputFrame; edge queue
  Input/TouchControls.luau      On-screen buttons: press-on-touch-down, multi-touch, slide-between,
                                enlarged hit zones, layouts A/B
  Render/RigRenderer.luau       Capsule stickman rig (anchored parts, BulkMoveTo), interpolation, catch blend
  Render/CameraController.luau  Side-on follow camera
  Render/Feedback.luau          Catch sound, camera kick, haptics where supported
  Debug/DebugPanel.luau         Auto-generated from Tuning: categories, sliders, numeric entry, presets,
                                import/export
  Debug/DebugOverlay.luau       FPS, steps/frame, sim cost, state, energy, catch timeline, last catch report
  Debug/DebugDraw.luau          Catch-range sphere, grippable span, predicted hand path (toggle)
  Debug/SessionLog.luau         Every grab attempt/catch/release logged; export as text for analysis
src/server/init.server.luau     Minimal (nothing gameplay-related)
tests/                          Lune specs: stability, energy, pumping, frame-rate independence,
                                catch windows, momentum transfer
tuning/presets/*.json           Saved tuning presets (committed = shared source of truth)
```

**Prototype world:** a flat floor and one horizontal bar about 10 studs high (real high-bar height at our scale), tagged `Bar`. The player starts hanging still.

**Prototype character:** a capsule stickman on the fixed gameplay skeleton. There's no Humanoid, avatar or Roblox character. Avatars come in Phase 3 (see §7). Testing feel on the bare skeleton first keeps avatar problems out of the movement evaluation.

**Build and run:** `rojo build -o build/GymProto.rbxl`. Open it in Studio and press Play; nothing to install. Optionally, `rojo serve` + the Rojo plugin gives live sync. Rojo, Lune, StyLua and Selene can all be installed from crates.io; in this cloud environment crates.io is reachable and GitHub release downloads are not.

---

## 6. Multiplayer — designed-for, not built in the prototype

The prototype is single-player. The core is written so that either of two networking paths stays open. We choose between them with a spike in Phase 3.

**Path A — client-authoritative core + custom snapshot replication**
- Each client simulates only its own gymnast: zero input latency, zero mispredictions.
- 20–30 Hz packed pose snapshots over `UnreliableRemoteEvent`, about 50 bytes each: root position, orientation quaternion, 3 shape angles, state flags, bar id and a timestamp.
- The server relays snapshots and plausibility-checks them (see §8). Remote players are drawn from an interpolation buffer about 100 ms behind.
- Bandwidth at 20 players: about 1.5 KB/s upload and about 30 KB/s download per client. Server CPU is a relay only.

**Path B — Roblox Server Authority running the same core**
- The core runs in `BindToSimulation` at 60 Hz (4 × 240 Hz sub-steps) on client and server.
- State lives in attributes on a predicted instance. The core needs about 25–35 numbers, within the 64-attribute limit.
- Inputs come through the Input Action System.
- Cheat-resistant by construction.
- Risks to measure in the spike:
  - cross-platform floating-point differences causing frequent small rollbacks
  - a catch near the edge of its window being reversed by a server correction. That would be terrible feel; the design must make catch outcomes tolerant (see PHYSICS_DESIGN §7.8).
  - the required settings (StreamingEnabled, Deferred signals, Input Action System)
  - maturity: the feature is only a few months old

Design constraints we honour **now** so both paths stay possible:
- the core is pure
- it has a fixed step
- inputs arrive per step as an `InputFrame`
- state serializes into fewer than 40 numbers
- no `os.clock()` or randomness inside `step`
- rendering and effects are driven from state and events, never from inside the step

Settled product rules that shape networking:
- Players never collide with each other. Bars are shared.
- Slow-mo and moon gravity are per-player in the sandbox (others see you in slow motion). They're locked in competitive modes.
- Server-side systems (proximity, voice, streaming focus) follow the simulated position: the server keeps an anchored root part near the reported position and sets `ReplicationFocus`.
- With `StreamingEnabled`, bars must be streamed in before they can be caught. Bar models use persistent or atomic streaming, and the bar registry tolerates bars appearing and disappearing.

---

## 7. Avatars (Phase 3, designed now)

- The game is set to R15 only, with body scale limited to standard proportions in Avatar settings. Gameplay always uses the **fixed skeleton**, so physics and leaderboards are identical for everyone.
- Each avatar rig gets an anchored `HumanoidRootPart` CFramed from the simulation. Joints are posed by writing `Motor6D.Transform` in `PreSimulation`, with no animation tracks playing and the default Animate script removed. Layered clothing, dynamic heads and accessories follow the joints. This must be verified in the Phase 3 spike.
- Hands are placed on the bar with 2-bone arm IK so small proportion differences don't show.
- There will be a "stickman mode" option: the clean silhouette reads best in clips and costs almost nothing to render.
- Performance: 20 posed avatars on low-end phones must be measured. Distant players update at a lower rate.

---

## 8. Exploit resistance plan (post-prototype)

- **Path A:**
  - The server checks every snapshot: speed against an energy bound (`v² ≤ v_max_release² + 2·g·Δh` plus margin), map bounds, "caught bar X" only when X exists near the reported position, and state transitions in a legal order.
  - Violations invalidate scores. We don't auto-kick on a single anomaly.
  - Leaderboard runs upload their compact input log, and the server re-simulates within tolerance.
- **Path B:** authority is built in, and the same checks become assertions.
- **Economy:** anything worth Robux, currency or rank is decided by the server, never by the client.

## 9. Replays and clips (post-prototype)

- A ring buffer of render poses at 30 Hz holds about 15 s, well under 100 KB.
- Playback drives the same renderer, so slow motion and free cameras come from interpolation. This works regardless of determinism.
- Input-log replays are optional and used for leaderboard verification.

---

## 10. Performance budgets (reference low-end phone, 1× speed)

| Item | Budget |
|---|---|
| Core simulation (≈4–8 steps/frame) | ≤ 0.3 ms/frame |
| Prototype rig render (≈15 parts via BulkMoveTo) | ≤ 0.2 ms/frame |
| Debug overlay (when shown) | ≤ 0.3 ms/frame |
| Frame rate | 60 fps on mid-range phones; never below 30 fps on low-end |

Measured with `debug.profilebegin` markers + MicroProfiler on real devices (see TESTING.md).

---

## 11. Technical risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| The reduced model looks stiff or robotic compared with a floppy ragdoll | Clips look less alive | Tune shape springs for overshoot. Add a render-only secondary-motion layer (limbs lag under g-force) that never affects gameplay. |
| Touch latency and 30 fps input quantization make windows feel unfair on weak phones | Catches feel random | Windows are sized in time (≥ 2 frames at 30 fps), plus a swept proximity test, late-grab rollback grace and per-device testing |
| Release precision at low fps (one 30 fps frame ≈ 9° of swing at high speed) | Trajectories vary on weak devices | Accept (the original has the same limit); measure; optional release-direction smoothing only if tests demand it |
| Tunable momentum transfer or release boost > 1 creates infinite energy loops | Broken regrab chains, exploits | Energy cap (`maxSwingSpeed`) and panel warnings for values > 1 |
| Server Authority corrections reverse a catch | Worst possible feel | Tolerance-based catch confirmation; measured in the Phase 3 spike before adopting Path B |
| Avatar posing edge cases (layered clothing, Rthro) | Visual glitches | Standardized R15 scaling, spike in Phase 3, stickman fallback |
| Lune/Roblox vector-type differences | Tests diverge from game | The core uses plain numbers and a small shared math module; the same code runs in both |
| StreamingEnabled (if Path B) hides bars | Missed catches | Persistent bar streaming; the registry handles bars streaming in and out |

## 12. References

- Roblox Server Authority: <https://create.roblox.com/docs/projects/server-authority> and the Techniques page next to it
- Live API dump used for verification: `MaximumADHD/Roblox-Client-Tracker` (`API-Dump.txt`), September 2026
