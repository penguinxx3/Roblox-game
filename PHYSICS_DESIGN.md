# Physics Design — Gymnast Core (v2)

Status: **approved; P1.1 (physics foundation) implemented.** Sections 1, 2, 4, 9, 10 and the P1.1 tuning tables in §12 describe the code as built (`src/shared/Gym/`). The other sections are specs for later milestones.

**v2 changes** after studying the reference clips ([REFERENCE_ANALYSIS.md](REFERENCE_ANALYSIS.md)):
- Motion is **planar (2.5D)**.
- Joints are **compliant spring motors**, not prescribed shapes.
- The body has **real contacts** with the world.
- A **foot** segment is added.
- Grip targets are **points and segments in the plane**, including moving equipment.
- Smaller catch radius, with forgiveness coming from timing.
- No hitstop or camera shake by default.

Scope: the custom gameplay-physics core from [TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md) §2–5.

Design principles:
1. **Physically based, game-tuned.** Real mechanics (angular momentum, pumping through shape changes, compliant muscles, contact), plus a few explicit, named assists.
2. **Every feel-relevant number is a tuning parameter** (§12), editable live.
3. **Catching is always an intentional, timed player action**, forgiving in time and tight in space.
4. **Frame-rate independent**: fixed 240 Hz steps with interpolated rendering.

---

## 1. Units and conventions

- Studs, seconds. Degrees in the panel and radians internally. Total body mass = `bodyMass` (10 by default; only ratios matter).
- **Motion plane:** a vertical plane with horizontal axis `u`, up axis `v` and normal `n`. As built, u = world X, v = world Y and depth = world Z, so the camera looks along −Z. All dynamics are 2D in (u, v); rotation angles are about `n`.
- `gravity` = 35 studs/s² by default (Earth-scale for this body). A check against the reference: a 0.9 s pole-to-pole flight needs a release speed of about 16 studs/s ≈ 4.4 m/s, which is a realistic gymnast release speed.

## 2. Body model (6 rigid bodies, planar) — implemented in `Rig.luau`

Left and right limbs are always paired, as in the reference, so each pair is one 2D body. Rendering draws two limbs with a sideways offset.

*Change at implementation (per the P1.1 direction):* arms are **upper arm + forearm with an elbow**. The elbow motor is strong and targets nearly straight, so arms look straight like the reference but give a little under load.

| Body | 2D collider | Length (studs) | Mass fraction | Notes |
|---|---|---|---|---|
| Torso + head | capsule r 0.42 (trunk) + circle r 0.45 (head, 0.7 above the shoulder line) | 2.0 (hip → shoulder) | 0.43 + 0.08 | Rigid; no spine bend (as in the reference) |
| Upper arms (pair) | capsule r 0.17 | 1.0 (shoulder → elbow) | 0.055 | |
| Forearms (pair) | capsule r 0.15 | 1.0 (elbow → grip point) | 0.045 | Hand friction uses `handFriction` |
| Thighs (pair) | capsule r 0.23 | 1.1 | 0.28 | |
| Shanks (pair) | capsule r 0.18 | 1.1 | 0.09 | |
| Feet (pair) | capsule r 0.12 | 0.7 (ankle → toe) | 0.02 | Standing and landing (Phase 2); dangling in the air |

Grip to sole is about 6.3 studs. Inertias come from uniform rods with radius, plus the head as a disc offset by the parallel-axis rule.

**Joints** are revolute (2D pins) with limits and a **spring motor** toward a target angle. All anatomical angles are 0 for a straight body with arms overhead; positive means flexion toward the front.

| Joint | Limits | Meaning of + |
|---|---|---|
| Shoulder (torso–upper arms) | −45° … +180° | arms toward the chest (0 = overhead, 90 = forward, 180 = down by the sides) |
| Elbow (upper arms–forearms) | −5° … +150° | forearm bends toward the front |
| Hip (torso–thighs) | −40° … +150° | flexion (pike/tuck) |
| Knee (thighs–shanks) | −2° … +150° | flexion |
| Ankle (shanks–feet) | 60° … 120° | foot angle (90 = square) |

The solver works in relative body angles; each joint maps anatomical ↔ relative with `anatomical = sign·(θB − θA) + offset`, defined in `Rig.luau`.

**Motor model (as built):** a soft angular constraint `θ → θ*` with frequency `motorHertz`, damping `motorDampingRatio` and a **per-joint maximum torque**.
- It's implicit (stable at any stiffness) and strength-limited, so loads (centrifugal pull, landings) bend joints: the "alive but controlled" behavior.
- Torque unit is **Mg·stud**: total body mass × current gravity × 1 stud, so strength scales with moon gravity.
- A saturated motor exerts its maximum torque and no extra damping, so an overloaded limb swings around its equilibrium instead of settling. That's physically plausible; worth watching in feel tests.

## 3. Shape control (Arch / Tuck / Pike)

- Inputs: `tuck` and `arch` in [0, 1]. Keyboard and touch give 0 or 1; gamepad triggers are analog. Both held means **Pike**: `p = min(tuck, arch)`, `t = tuck − p`, `a = arch − p`.
- `target = Neutral + t·(Tuck − Neutral) + a·(Arch − Neutral) + p·(Pike − Neutral)`
- The motor frequency switches between `shapeFreqClose` when moving toward flexion (tucking) and `shapeFreqOpen` when opening (kick-out).

| Pose | Shoulder | Elbow | Hip | Knee | Ankle |
|---|---|---|---|---|---|
| Neutral (air/bar: arms overhead, slight hollow) | +8° | +5° | +8° | +5° | 90° |
| Arch | −25° | 0° | −30° | 0° | 100° |
| Tuck | +25° | +20° | +125° | +135° | 90° |
| Pike | +15° | +5° | +115° | 0° | 100° |
| Crouch *(P1.1 debug/landing test)* | +90° | +10° | +70° | +90° | 70° |
| Limp *(P1.1 debug)* | motors off | | | | |

P1.1 status:
- The pose tables live in `Rig.POSES`; the debug controls switch poses to exercise the motors. There's no gameplay input yet.
- Input-driven Arch/Tuck/Pike blending and the separate close/open frequencies are P1.2.
- Measured in zero gravity from a straight start: every joint settles within 3° of its target in 1.6–2.7 s. The coupled springs wobble noticeably first (Pike: shoulder overshoots to ~59° before settling at 15°). Damping and frequency are tuning items for P1.2 feel work.

## 4. Solver — implemented in `Solver2D.luau` + `Collide2D.luau`

A small **2D rigid-body solver** written for this game: soft-step sequential impulses with warm starting, in the style of Box2D v3. The dynamics of every state (hanging, flying, touching the world) are the **same equations**; nothing switches between separate models, so momentum is continuous through release, catch and contact by construction.

**Per fixed step** (`dt = 1/simHz`, default 240 Hz), as built:
1. **Collide once per step.**
   - Rounded segments (capsules/circles) on the body against convex polygons on static or kinematic bodies.
   - Up to 2 points per pair (face clipping), with feature ids for warm starting.
   - The **speculative margin is `speculativeDistance` + the distance both shapes can travel this step** (linear speed plus spin × extent). Fast bodies therefore can't tunnel: 300 studs/s into the floor stops at the surface.
2. **Prepare** contact masses and restitution velocities, and joint masses and motor softness.
3. **Substeps** (`substeps`, default **4**, so the solver runs at 960 Hz):
   - integrate velocities (gravity, damping, speed clamps)
   - warm-start joints and contacts
   - solve **with** position bias: per joint, spring motor → lower/upper limits → point constraint; then contacts with friction
   - integrate positions
   - `relaxIterations` passes **without** bias (removes correction velocity)
4. **Restitution** pass (only above `restitutionThreshold`). Impulses are kept for the next step's warm start.

**Stability rule (as built):** soft constraint stiffness is capped at a quarter of the substep rate (h·ω ≤ π/2), the same rule Box2D v3 uses. Settings above that are clamped instead of going unstable. The defaults sit exactly at the cap: `jointHertz = 240` with 4 × 240 Hz substeps.

**Measured (headless, default settings):**

| Measurement | Result |
|---|---|
| Joint stretch, giant swing (~9 rad/s) | ≤ 0.009 studs |
| Joint stretch, landings | ≤ 0.022 studs |
| Grip stretch | ≤ 0.007 studs |
| Pendulum energy drift over 60 s | ≤ 0.25%, always a loss, never a gain |
| Flight angular momentum drift | ≤ 0.003% |
| Centre of mass vs the integrator's own free-fall path | ≤ 1e-12 studs |
| Cost (Lune) | ~18–28 µs per step, i.e. ~0.1 ms per 60 fps frame |

(`tools/solver_bench.luau` reproduces the settings comparison.)

**Why this solver:**
- Robust contact and friction.
- Soft constraints make motors stable and compliant.
- Warm starting gives smooth resting contacts.
- Proven structure for ragdolls.
- Internal joint impulses are equal and opposite, so momentum is conserved in free flight.

**Alternatives considered:**
- XPBD: simpler, but friction, restitution and motor semantics are less direct.
- The v1 reduced-coordinate model: exact, but can't handle multi-contact landings, handstands, vaults or reactive equipment without many special cases.

**Not in P1.1:** world slice built from Roblox map parts. The P1.1 course is defined as data in `Scenarios.luau` and rendered from the solver's own shapes. The grip used by the test scenes is a plain pin joint; the intentional catch system is P1.4.

## 5. Derived states (game logic only; the solver doesn't care)

```
GRIPPING  : grip joint active           → Let Go allowed; Grab ignored
AIRBORNE  : no grip, no world contacts  → Grab attempts allowed
CONTACT   : touching world, no grip     → prototype: if torso/head touches, or the body rests
                                          on the floor for 0.3 s → FALLEN
FALLEN    : prototype run over          → body stays physical (crumples); auto-reset after delay
```

- Reset works from any state and puts the body hanging still from the bar in the Neutral pose.
- Phase 2 adds STANDING, LANDED and HAND-PLANT logic on top of the same contacts (balance assist, jump from crouch) without changing the solver.

## 6. Release, flight, twist

### 6.1 Release (Let Go press while GRIPPING)
Applied on the first step after the press. There's **no delay and no buffering**, because release timing is skill.
1. Remove the grip joint. The bodies keep their velocities, so momentum is continuous by construction. That matches the reference: rotation direction and speed flow straight through (REFERENCE §2.5).
2. Game shaping, about the center of mass:
   - velocity × `releaseVelocityScale`
   - `+ releasePop` upward
   - rotation relative to the center of mass × `releaseSpinScale`

   Defaults are 1 / 0 / 1 (pure physics).
3. Start `regrabLockout`.

### 6.2 Flight
- Just the solver with no grip and no contacts.
- The spin rate follows body shape through conserved angular momentum. Target from the reference: tight tuck ≈ 1.6× the open or pike spin rate (TESTING R1).
- Air drag defaults to 0.

### 6.3 Twist (2.5D layer)

Twist is a controlled rotation `ψ` about the body's long axis. In a planar model this does two things:

- **Render:** the whole body is rotated by `ψ` about the torso's long axis, so the torso face and limbs turn toward and away from the camera, as in the reference.
- **Dynamics (projected targets):** body-frame motor targets are projected into the plane: `θplane = atan2(sin θ · cos ψ, cos θ)`.
  - A tuck seen from the side flattens as the body turns through 90° and mirrors after a half twist.
  - A half twist therefore swaps front and back (a back flip becomes front-facing).
  - The renderer rebuilds 3D limb poses from the body-frame angles plus `ψ`.

| `twistMode` | Behavior |
|---|---|
| `hold` (default) | While Twist L/R is held, `ψ̇` accelerates toward ±`twistRate` at `twistAccel`. Released, or both held, it stops at `twistStopAccel` and holds the angle. |
| `momentum` | A tap starts the spin; a tap on the opposite side reverses it; holding both stops it and holds the angle. |

Twist is active only while AIRBORNE. On a catch, `ψ` snaps to the nearest 0°/180° (a visual blend), within `catchTwistTolerance` (§7.2).

## 7. Intentional catch system

Goals: **never automatic**, forgiving on mobile, and skill decides. Per the reference, the grip must land **where the hands are**, with no visible snap. So the default is a small radius, with forgiveness coming from time windows and rollback.

### 7.1 Grip targets (2D, in the plane)

- **Points:** a bar crossing the plane, a pole tip, a stub tip. The prototype has one bar.
- **Segments:** rods lying in the plane, such as beams, frames and spokes (Phase 2), with `gripEndMargin` at their ends.
- Targets can belong to **equipment bodies** (static, kinematic or dynamic). The anchor then moves with the equipment, and the catch uses the **relative** hand-to-anchor velocity.
- **Hand point** `H`: the grip end of the arms body (both hands together, as in the reference).
- **d**: distance from the hand point's **swept path this step** (`H_prev → H_now`) to the target. This stops fast hands skipping past it between steps.

### 7.2 Catch conditions (all on one step)

1. **Proximity:** `d ≤ catchRange`.
2. **Reach:** the arms point at the target: `angle(armDir, target − shoulder) ≤ catchReachAngle`. In the reference the hands always lead into the catch.
3. **Twist:** `ψ` is within `catchTwistTolerance` of 0° or 180°. This is the mid-twist regrab tolerance.
4. **Not locked out:** at least `regrabLockout` since release.
5. *(Optional)* **Relative speed:** `≤ maxCatchSpeed`. Off by default.

If several targets qualify, the smallest `d` wins.

### 7.3 Grab attempt lifecycle

```
Grab PRESS (edge) at step n, state == AIRBORNE (or CONTACT in Phase 2):
  if n < cooldownUntil                               → ignored (event GrabIgnored)   -- anti-mash
  elif late grace finds a valid step k in (n − lateSteps, n) → CATCH at k (rollback, §7.4)
  else                                               → open attempt [n, n + earlySteps]

Each step while an attempt is open:
  if conditions hold (swept)  → CATCH now
  elif step > attempt end     → close; cooldownUntil = step + cooldownSteps (event GrabMissed)
```

- **Only the press counts.** Holding Grab never catches. `grabMode = hold` is a debug/accessibility switch and off by default.
- **Early press** is buffered up to `catchWindowEarly`. **Late press** still counts up to `catchWindowLate`.
- **Mashing loses:** a missed attempt blocks new ones for `grabCooldown`.
- The default cooldown is shorter than the reference's typical catch interval of 1–1.5 s, so it never blocks the next legitimate catch in a chain.
- Grab while GRIPPING or FALLEN is ignored and never queued.

### 7.4 Late-grab grace via rollback

- The core keeps a ring buffer of the last `catchWindowLate + 50 ms` of solver states (all body states plus warm-start impulses) and per-step inputs.
- On a press with no open attempt: find the **most recent** valid step `k`, restore it, catch there (§7.5), then re-simulate `k+1 … n` with the recorded inputs. The renderer blends the pose correction over `catchBlendTime`.
- `lateCatchMode`: `rollback` (default) · `snap` (catch at the current state if `d ≤ catchRange·lateRangeScale`) · `off`.
- Why: touch latency and 30 fps input quantization make players slightly late. That's a device problem, not a skill problem.

### 7.5 Catch resolution and momentum transfer

1. **Anchor** = the closest point on the target to `H`.
2. **Position:** translate the whole body by `δ = anchor − H` (`|δ| ≤ catchRange`, so it's small). Velocities are unchanged. The renderer blends `δ` out over `catchBlendTime`, so nothing snaps on screen.
3. **Twist:** `ψ` snaps to 0°/180° (visual blend). Joint targets re-project.
4. Create the **grip pin joint** (hand point ↔ anchor). On the next solve, its impulse makes the hand velocity match the anchor velocity. That's an inelastic catch which **conserves the body's angular momentum about the grip**, exactly the continuity seen in the reference.
5. **Transfer factor** (`catchMomentumTransfer`, default 1.0 = pure physics, matching the reference). If it isn't 1, velocities relative to the anchor are scaled after the catch impulse: `v ← v_anchor + k·(v − v_anchor)`, `ω ← k·ω`. Values above 1 are flagged and still capped by `maxSwingSpeed`.
6. `impact` = kinetic energy lost to the catch impulse. It drives the sound and haptic strength.
7. Emit `Catch` {target, d, quality, timing ms, rollback steps, impact, transfer}.

### 7.6 Quality and feedback

| Quality | Condition |
|---|---|
| Perfect | `d ≤ perfectRange` and no rollback |
| Good | `d ≤ catchRange` |
| Save | Caught through rollback |

- Prototype feedback: catch sound (pitch and volume from quality and impact), a haptic pulse where supported, the chain counter, and details in the debug overlay.
- **No hitstop and no camera shake by default.** The reference gets its satisfaction from uninterrupted motion. Both stay as tunables for testing.

### 7.7 Assists (separate knobs)

| Assist | Knob | Default |
|---|---|---|
| Spatial | `catchRange` / `perfectRange` | 0.45 / 0.15 studs |
| Temporal | `catchWindowEarly` / `catchWindowLate` | 100 / 60 ms |
| Twist | `catchTwistTolerance` | 35° |
| Reach | `catchReachAngle` | 60° |
| Trajectory magnetism | `grabAssistPull` (a small pull toward a catching line while an attempt is open and within `assistRadius`) | 0 |
| Presets | `Off` · `Standard` · `Mobile-Forgiving` · `Hardcore` | Standard |

At typical catch speeds (hands at 20–30 studs/s), a 0.45 stud radius is about 30–45 ms of "in range" time. With the early and late windows the total press window is about 190–210 ms. The skill is mostly in **release timing** (reaching the target at all) and in **pressing on the beat**.

### 7.8 Multiplayer note

- The catch is a function of state and a press at step `n`, so it can run under Server Authority.
- The server validates catches with a slightly larger tolerance (`serverCatchTolerance`) so a correction never reverses a catch the player saw.
- Any hitstop must be render-only in multiplayer.

### 7.9 One-hand catch

The reference never shows one-hand catches; hands always grip together. This stays **deferred, low priority**: only if playtests show a need.

## 8. Swing shaping (hanging)

- **Pumping is physical:** the motors do work as the shape changes (closing on the upswing, opening through the bottom). Timing adds or removes energy.
- **Assists and limits:**

| Knob | Effect |
|---|---|
| `gripFriction` | Torque opposing rotation at the grip (energy loss per swing) |
| `angularDamping` | Air-like loss |
| `swingAssist` | Optional extra torque about the grip, applied only when the player's shape change is **in phase** (the body's inertia about the grip is decreasing while swinging upward). It makes good timing pay off more without rewarding bad timing. Default 0. |
| `maxSwingSpeed` | Soft cap on angular speed about the grip. The energy cap and the anti-infinite-loop guard. |

## 9. Time step, time scale, gravity, interpolation

- `dt = 1/simHz` (240). Each frame: `acc += min(realDt, 0.1)·timeScale`. Run `floor(acc/dt)` steps, capped at `maxStepsPerFrame` (excess is dropped). Render alpha = `acc/dt`.
- **Slow motion = a smaller `timeScale`.** It applies to **the player's whole simulated world**, including kinematic equipment, whose motion is a deterministic function of the player's sim time. That matches the reference (the wheels slow down too).
- **Moon gravity** = `gravity × moonGravityScale` (default 1/6). It combines with slow-mo.
- **Interpolation:** the renderer blends the previous and current body poses by alpha.
- **Input:**
  - held inputs apply to every step in a frame
  - press edges apply at the frame's first step
  - if a frame runs 0 steps, edges wait for the next step (never lost)
- **Windows use simulation time by default**, so slow-mo is naturally easier. `windowsInRealTime` switches this.

## 10. Determinism

- There's no randomness, no clock reads and no Instance access inside `step`.
- The world slice and equipment are plain data. Solver iteration order is fixed.
- Same device + same inputs = bit-identical result (tested). Across devices we only claim agreement within tolerance.

## 11. Known simplifications (on purpose)

1. Paired limbs, no spine bend (as in the reference). Elbows exist but the elbow motor holds the arms nearly straight.
2. Planar dynamics. Twist is a controlled render and target-projection layer, not emergent 3D rotation.
3. No self-collision.
4. Prototype has no standing or balance logic: landing is physical, then auto-reset. Standing, jumping and hand-plants are Phase 2, built on the same solver.
5. There's no crash ragdoll hand-off anymore. The core itself collapses physically on the floor.

## 12. Tuning parameters

Defined in `Tuning.luau` (default, min, max, unit, category, description). The debug panel is generated from it; presets are saved in `tuning/presets/`. **All defaults are starting points**, calibrated against REFERENCE_ANALYSIS §4 during tuning. ⟲ means the value takes effect on Reset.

### P1.1 parameters (implemented in `Tuning.luau`, live-editable)

In Studio during Play, these are editable as attributes on `ReplicatedStorage.GymTuning` (client view).

**World and time**

| Param | Default | Range | Unit | Notes |
|---|---|---|---|---|
| `gravity` | 35 | 5–150 | studs/s² | |
| `moonGravity` / `moonGravityScale` | 0 / 0.165 | 0–1 / 0.05–1 | bool / × | |
| `timeScale` | 1 | 0–2 | × | Slow-mo; debug presets 1 / 0.5 / 0.25 / 0.1 |
| `linearDamping` / `angularDamping` | 0 / 0.02 | 0–2 | 1/s | |

**Solver**

| Param | Default | Range | Unit | Notes |
|---|---|---|---|---|
| `simHz` ⟲ | 240 | 60–480 | Hz | Fixed step (collision/input/events rate) |
| `substeps` | 4 | 1–8 | count | Solver substeps per step |
| `relaxIterations` | 1 | 1–4 | count | |
| `maxStepsPerFrame` / `maxFrameDt` | 16 / 0.1 | 1–64 / 0.02–0.5 | steps / s | Hitch protection |
| `maxLinearSpeed` / `maxAngularSpeed` | 400 / 120 | — | studs/s / rad/s | Safety clamps |

**Contacts**

| Param | Default | Range | Unit | Notes |
|---|---|---|---|---|
| `contactHertz` / `contactDampingRatio` | 30 / 10 | 5–120 / 0–20 | Hz / ζ | Overlap push-out softness |
| `contactPushSpeed` | 10 | 0.5–50 | studs/s | Max push-out speed |
| `speculativeDistance` | 0.12 | 0–1 | studs | Plus per-step motion (anti-tunneling) |
| `friction` / `handFriction` | 0.8 / 1.0 | 0–2 | μ | |
| `restitution` / `restitutionThreshold` | 0.05 / 3 | 0–0.9 / 0–20 | e / studs/s | |

**Joints**

| Param | Default | Range | Unit | Notes |
|---|---|---|---|---|
| `jointHertz` / `jointDampingRatio` | 240 / 2 | 5–480 / 0–10 | Hz / ζ | Joint anchor stiffness (capped at ¼ substep rate) |
| `motorHertz` / `motorDampingRatio` | 6 / 0.8 | 0.5–30 / 0–3 | Hz / ζ | Pose springs |
| `shoulderMaxTorque` / `elbowMaxTorque` / `hipMaxTorque` / `kneeMaxTorque` / `ankleMaxTorque` | 3.0 / 2.0 / 2.0 / 1.0 / 0.3 | 0–20 | Mg·stud | Lower = floppier |

**Body ⟲**

| Param | Default | Range | Unit |
|---|---|---|---|
| `bodyMass` | 10 | 1–100 | mass |
| `upperArmLength` / `forearmLength` | 1.0 / 1.0 | 0.5–1.5 | studs |
| `trunkLength` | 2.0 | 1.5–2.5 | studs |
| `thighLength` / `shankLength` / `footLength` | 1.1 / 1.1 / 0.7 | 0.4–1.6 | studs |

Mass fractions and radii are constants in `Rig.luau`.

### Later milestones (specified, not yet in `Tuning.luau`)

`shapeFreqClose` / `shapeFreqOpen` (P1.2, input-driven shape control) and everything below are added when their milestone is built.

### Swing
| Param | Default | Range | Unit |
|---|---|---|---|
| `gripFriction` | 0.02 | 0–1 | × M·g·L |
| `swingAssist` | 0 | 0–2 | × |
| `maxSwingSpeed` | 12 | 4–30 | rad/s |

### Release
| Param | Default | Range | Unit |
|---|---|---|---|
| `releaseVelocityScale` / `releaseSpinScale` | 1.0 / 1.0 | 0.5–1.5 | × |
| `releasePop` | 0 | 0–20 | studs/s |
| `regrabLockout` | 0.15 | 0–0.5 | s |

### Twist
| Param | Default | Range |
|---|---|---|
| `twistMode` | hold | hold / momentum |
| `twistRate` | 1.5 | 0.5–5 rev/s |
| `twistAccel` / `twistStopAccel` | 20 / 30 | 2–100 rev/s² |

### Catch
| Param | Default | Range | Unit |
|---|---|---|---|
| `grabMode` | press | press / hold | — |
| `catchRange` / `perfectRange` | 0.45 / 0.15 | 0.1–3 / 0–1 | studs |
| `catchWindowEarly` / `catchWindowLate` | 0.10 / 0.06 | 0–0.4 / 0–0.2 | s |
| `lateCatchMode` / `lateRangeScale` | rollback / 1.3 | off / snap / rollback; 1–2 | — |
| `grabCooldown` | 0.20 | 0–0.6 | s |
| `catchReachAngle` | 60 | 20–120 | deg |
| `catchTwistTolerance` | 35 | 0–90 | deg |
| `maxCatchSpeed` | 0 (off) | 0–200 | studs/s |
| `grabAssistPull` / `assistRadius` | 0 / 1.5 | 0–60 / 0.5–5 | studs/s², studs |
| `catchMomentumTransfer` | 1.0 | 0–1.25 | × (> 1 flagged) |
| `catchBlendTime` | 0.08 | 0–0.3 | s |
| `catchHitstop` | 0 | 0–0.1 | s |
| `gripEndMargin` | 0.2 | 0–1 | studs |
| `windowsInRealTime` | false | bool | — |
| `allowOneHandCatch` | false | bool | Reserved |

### Camera (reference: straight side view, smooth follow, no shake)
| Param | Default | Range |
|---|---|---|
| `camDistance` | 22 | 8–50 studs |
| `camFov` | 50 | 30–90 deg |
| `camYaw` / `camPitch` | 0 / −3 | −60–60 / −30–30 deg |
| `camFollowFreq` | 2.5 | 0.5–10 Hz |
| `camLookAhead` | 0.15 | 0–0.5 s of velocity |
| `camZoomBySpeed` | 0.1 | 0–1 |
| `camShakeOnCatch` | 0 | 0–1 |

### Input and mobile
| Param | Default | Range |
|---|---|---|
| `touchLayout` | A | A / B |
| `buttonScale` / `hitPadding` | 1.0 / 12 px | 0.6–1.6 / 0–40 |
| `buttonOpacity` | 0.35 | 0–1 (0 = hidden but active: "clean recording") |
| `hapticsOnCatch` | true | bool |

### Fall and reset
| Param | Default | Range |
|---|---|---|
| `floorY` ⟲ / `barHeight` ⟲ | 0 / 10 | —, 6–20 studs |
| `fallRestTime` | 0.3 | 0–2 s |
| `autoResetDelay` | 1.2 | 0–5 s |

## 13. Debug instrumentation

- **Performance:** FPS, frame ms, steps this frame, solver ms, contact count, time scale, gravity.
- **State:** derived state, grip angle and rate, joint angles vs targets (motor saturation highlighted), energy, spin rate (rev/s), twist `ψ`, flips and twists since release.
- **Catch timeline:** press, attempt window, closest approach, catch or miss, cooldown.
- **Last catch:** `d`, quality, early/late ms, rollback steps, transfer, impact.
- **Session counters** and the preset name.
- **Optional drawings:** catch radius at the hands, grip targets, contact points, and the predicted hand path if you released now.
- **Debug instant replay** (proposed, TECHNICAL_DESIGN §9): scrub the last 10 s at any speed to inspect catches frame by frame.
