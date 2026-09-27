# Physics Design — Gymnast Core (v2)

Status: **approved; P1.1 (physics foundation) and P1.2 (movement control) implemented.** Sections 1–6, 8–11 and the tuning tables in §12 describe the code as built (`src/shared/Gym/`). §7 (intentional catch) is the P1.3 spec.

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

**Drawn body vs physics body (P1.2 round 3).** The collision shapes below (`Rig.RADIUS`) are for physics only. The drawn body has its own proportions (`Look.luau`, read only by the renderer and tests), and every drawn shape stays inside the collision shapes; only the foot's square corners pass the rounded ends, by ≤ 0.014 studs.
- A chest block (0.8 × 1.0) and a pelvis block (0.72 × 0.82) replace the drawn round torso capsule.
- The head is smaller (radius 0.36 vs 0.45), its top at the collision head's top, on a neck.
- The limbs are slimmer (arms 0.12 / 0.105, legs 0.165 / 0.12 vs 0.17 / 0.15 / 0.23 / 0.18).
- The feet are blocks whose sole is the collision sole.
- Arms are drawn at depth ±0.64 and legs at ±0.24 (was ±0.32 for both), so arms can't pass through the head or chest.

*Change at implementation (per the P1.1 direction):* arms are **upper arm + forearm with an elbow**. The elbow motor is strong and targets nearly straight, so arms look straight like the reference but give a little under load.

| Body | 2D collider | Length (studs) | Mass fraction | Notes |
|---|---|---|---|---|
| Torso + head | capsule r 0.42 (trunk) + circle r 0.45 (head, 0.7 above the shoulder line) | 2.0 (hip → shoulder) | 0.43 + 0.08 | Rigid; no spine bend (as in the reference) |
| Upper arms (pair) | capsule r 0.17 | 1.0 (shoulder → elbow) | 0.055 | |
| Forearms (pair) | capsule r 0.15 | 1.0 (elbow → grip point) | 0.045 | Hand friction uses `handFriction` |
| Thighs (pair) | capsule r 0.23 | 1.1 | 0.28 | |
| Shanks (pair) | capsule r 0.18 | 1.1 | 0.09 | |
| Feet (pair) | capsule r 0.12 | 0.85: heel 0.15 behind the ankle, toe 0.7 ahead | 0.02 | Standing, balancing and landing |

Grip to sole is about 6.3 studs. Inertias come from uniform rods with radius, plus the head as a disc offset by the parallel-axis rule.

*P1.2 changes (body):*
- **Heel.** The foot capsule reaches `FOOT_HEEL` = 0.15 behind the ankle, and the shank's rounded lower end stops `SHANK_TRIM` = 0.1 short of the ankle (collision and drawing). Before, the shank's end propped a flat foot's heel off the floor and there was nothing behind the ankle, so the feet physically could not push the body forward: standing was impossible without it.
- **Limb inertia boost** (`limbInertiaBoost`, default 1; `Rig.INERTIA_SCALE`: upper arm ×2, forearm ×4, shank ×2, foot ×8; mass and length unchanged). Solver conditioning for the light segments that carry the whole body's load (a 0.2-mass foot on landing, a 0.45-mass forearm on the bar). Across 160 soak runs the worst joint-limit overshoot fell from 14.5° to under 3° at no cost; whole-body inertia changes by ~1%, so spin rates are unaffected (TESTING, P1.2).

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
- Torque unit is **Mg·stud**: total body mass × gravity × 1 stud. With `strengthGravityScaling` = 1 (default) the gravity is the current one, so strength follows moon gravity; 0 keeps Earth strength (§9).
- A saturated motor exerts its maximum torque and no extra damping, so an overloaded limb swings around its equilibrium instead of settling. That's physically plausible; worth watching in feel tests.
- *Learned in P1.2:* the spring's stiffness is relative to the two segments it joins, not to the load it carries. A joint that turns much more than its own segments (the shoulders on the bar turn the whole hanging body; the hips during a fast spin hold the legs against centrifugal pull) therefore gives a lot under load. That's why the bar has its own shoulder stiffness (§8) and why standing uses muscle torques (§6.4).
- `Rig.drive` lets the controller override frequency, damping and strength per joint each step; the P1.1 named-pose path (`Rig.applyMotors`) is unchanged.

## 3. Shape control (Arch / Tuck / Pike) — implemented in `Controller.luau`

- Inputs: `tuck` and `arch` in [0, 1]. Keyboard and touch give 0 or 1; gamepad triggers are analog. Both held means **Pike**: `p = min(tuck, arch)`, `t = tuck − p`, `a = arch − p`.
- `target = Neutral + t·(Tuck − Neutral) + a·(Arch − Neutral) + p·(Pike − Neutral)` (on the bar and in the air).
- **Input smoothing (P1.2):** the targets the motors see move through a critically damped second-order filter at `shapeFreqClose` (8 Hz) when closing (the target angle increases: tucking, piking) and `shapeFreqOpen` (6 Hz) when opening. It removes the step in target that made the motors slam to full torque; it adds ~0.01–0.02 s of response.
- Motor damping is 1.25 (P1.1: 0.8). Measured with `tools/smooth_bench.luau` (zero gravity, hip and knee, vs exactly P1.1): overshoot 22.5° → 7.0°, lingering wobble 1.4° → 0.9°, joint jerk −46%, torso jerk while pumping −37%, response 0.17 → 0.19 s, tuck spin gain 1.47× → 1.52×. Pose settle time (Rig tests) 1.25–1.74 s → 0.75–1.12 s.
- **Air tuck (P1.2 feedback round, PLAYTEST_P1_2.md):** off the bar (in the air, or fallen) Tuck uses **AirTuck**: the arms come down in front and the forearms fold toward the shins. On the bar the Tuck keeps the arms overhead, holding the bar. While tucking or piking off the bar, the shoulders, elbows, hips and knees also **squeeze**: their springs run at `tuckHertz` (10 Hz, blended by how far Tuck/Pike is pressed) instead of `motorHertz`.
  - Measured (Tumble launch, no air damping): spin 0.1 s after pressing ×1.44 (P1.2 as first tested ×1.17, P1.1 ×1.48); full tuck ×2.2 (was ×1.5); rotation in 0.5 s of tuck 1.03 rev (was 0.77).
  - The input smoothing stays at 8 / 6 Hz, because it also shapes the bar. Raising `shapeFreqClose` to 16 gives ×1.74 at 0.1 s.
  - Cost, zero-gravity shape test: hip/knee overshoot 7° → 23° (P1.1 motor settings: 26°), wobble 0.9° → 1.6°. Without the squeeze: 13° / 1.3°. The spin pulls the arms outward, so they settle at shoulder ≈ 85–100° (hands by the knees). The arm target 110° / 60° peaks at 129°; 135° / 45° swung the arms past the shins, to 169°.

| Pose | Shoulder | Elbow | Hip | Knee | Ankle |
|---|---|---|---|---|---|
| Neutral (air/bar: arms overhead, slight hollow) | +8° | +5° | +8° | +5° | 90° |
| Arch | −25° | 0° | −30° | 0° | 100° |
| Tuck (on the bar: arms overhead) | +25° | +20° | +125° | +135° | 90° |
| AirTuck (Tuck off the bar: arms in, hands toward the shins; under a spin the arms settle 20–25° short, up by the chest, see PLAYTEST_P1_2.md round 2) | +110° | +60° | +125° | +135° | 90° |
| Pike | +15° | +5° | +115° | 0° | 100° |
| GroundStand | +150° | +15° | +8° | +10° | 95° |
| GroundCrouch (Tuck or Pike on the ground; balanced: centre of mass over the feet) | +70° | +15° | +107° | +100° | 118° |
| GroundReach (Arch on the ground; jump push arms) | −10° | 0° | −8° | 0° | 62° |
| Crouch / Limp *(P1.1 debug poses)* | +90° / off | +10° | +70° | +90° | 70° |

Ankle > 90° = the shank leans forward over a flat foot. On the ground the ankle is not driven by the pose table: balance and a foot-flat spring drive it (§6.4).

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

**Not yet built:** world slice built from Roblox map parts. The course is defined as data in `Scenarios.luau` and rendered from the solver's own shapes. The grip used by the test scenes is a plain pin joint; the intentional catch system is P1.3.

**P1.2 additions:** per-step external force and torque on bodies (`Solver2D.applyForce` / `applyTorque`, cleared after each step) for muscle torques and assists; joint friction (`frictionTorque`, a torque-limited velocity constraint) for grip friction.

## 5. Movement states — implemented in `Controller.luau`

Derived every fixed step from the grip joint and the previous step's contacts; the solver doesn't know about them.

```
grip    : grip joint active                 → Arch/Tuck/Pike shape the swing, Let Go releases
air     : no grip, no support               → Arch/Tuck/Pike shape the flight, Twist spins
ground  : feet (or the heel end of the shank) touch with an upward normal, nothing else touches,
          trunk within fallTiltAngle (75°) of upright
                                            → stand / crouch / reach, balance, jump, landing
fallen  : anything but the feet touches, or on the feet but tipped over
                                            → shape control only; the body stays physical
```

- `ground → air` needs `groundGrace` (0.06 s) without foot contact, so bumps don't flicker. `fallen → air` when nothing touches.
- Events (for the overlay, tests and later feedback): `release`, `halfTwist`, `push`, `takeoff`, `landing` (with impact speed), `fall`.
- Reset works from any state. There is no auto-reset yet (the fall-and-reset loop comes with the catch, P1.3).

## 6. Release, flight, twist

### 6.1 Release (Let Go press while GRIPPING)
Applied on the first step after the press. There's **no delay and no buffering**, because release timing is skill.
1. Remove the grip joint. The bodies keep their velocities, so momentum is continuous by construction. That matches the reference: rotation direction and speed flow straight through (REFERENCE §2.5).
2. Game shaping, about the center of mass:
   - velocity × `releaseVelocityScale`
   - `+ releasePop` upward
   - rotation relative to the center of mass × `releaseSpinScale`

   Defaults are 1 / 0 / 1 (pure physics).
3. *(P1.3)* Start `regrabLockout`.

As built (P1.2): exactly this. With the default shaping the release step changes linear momentum only by gravity and leaves angular momentum untouched (tested to 1e-9). A Let Go press while not gripping, and a Grab press (until P1.3), do nothing.

### 6.2 Flight
- Just the solver with no grip and no contacts.
- The spin rate follows body shape through conserved angular momentum. A full arms-in tuck spins ≈ 2.2× faster than the open body. A real tight tuck from a straight body gives about 2.5–3.5×; the reference clips showed 1.4–1.9× (TESTING R1), with partial tucks. A half-pressed trigger gives a partial tuck.
- Air drag defaults to 0.

### 6.3 Twist (2.5D layer) — as built

Twist is a controlled rotation `ψ` about the body's long axis (the line through the centre of mass along the torso).

- **Render:** the whole drawn body is rotated by `ψ` about that axis (`Pose3D.twist`, the same math in the renderer and the tests), so the chest and limbs turn toward and away from the camera.
- **Dynamics: a mirror snap.** The planar body keeps its full shape in the plane. When `|ψ|` passes 90°, the body is mirrored in the plane across the long axis (`Rig.mirror`) and `ψ` jumps by 180°.
  - The mirror conserves **exactly** the centre of mass, linear momentum, angular momentum and kinetic energy; joints stay attached; anatomical angles keep their meaning (the rig's `facing` flips).
  - On screen it is continuous: a mirrored body turned by `ψ − 180°` lands every point where the unmirrored body turned by `ψ` would be, except that the left and right copies of paired limbs swap, which is invisible (tested on the rendered points: largest jump 1e-15 studs).
  - A half twist therefore turns a back flip into a front-facing one, as in the reference.
  - **Clearance:** mirroring moves limbs across the axis; close to the floor or a block that could put them inside it. The snap only happens when the mirrored body is at least 0.05 studs clear of the world (`Rig.mirrorClear`); otherwise the twist holds side-on at 90° until it is. (Found by the randomized input soak: a near-horizontal body just above the floor had its feet mirrored 0.58 studs into it.)
- *Why not "projected targets" (the earlier spec):* at `ψ` = 90° the in-plane projection of every flexion is zero, so the 3D pose can't be recovered for drawing, and the motors would have to drive limbs through straight and back while spinning. The mirror is exact, cheap and needs no reconstruction.

| `twistMode` | Behavior |
|---|---|
| `0` hold (default) | While Twist L/R is held, `ψ̇` accelerates toward ±`twistRate` (1.5 rev/s) at `twistAccel`. Released, or both held, it stops at `twistStopAccel` and holds the angle. |
| `1` momentum | A tap starts the spin; a tap on the opposite side reverses it; holding both stops it and holds the angle. |

Twist is active only in the air. Landing or gripping settles an unfinished `ψ` back to square over `twistSettleTime` (0.12 s; visual only, the planar body is already square). The catch rule (P1.3) is unchanged: `ψ` must be within `catchTwistTolerance`.

### 6.4 Ground: standing, crouch, jump, landing — as built

Pulled forward from Phase 2 at the owner's request. All of it is muscle torques (equal and opposite on the two bodies of a joint) or pose springs, except `balanceAssist`.

**Standing** (`ground`, not pushing):
- Pose springs toward GroundStand / Crouch / Reach, smoothed at `groundShapeHertz` (2 Hz: a body can't crouch faster than it can fall; faster crouching lifted the feet off the floor), legs at `groundLegHertz` (8 Hz, ζ `groundLegDampingRatio` 1).
- **Gravity compensation:** each leg joint carries the weight of everything above it (`gravityCompensation` = 1), so the springs only correct posture instead of sagging.
- **Balance through the ankles:** a horizontal "virtual force" at the centre of mass steers it over the middle of the feet like a critically damped spring at `balanceHertz` (1.5 Hz); the ankle torque is capped by leg strength and, physically, by the foot's length (the ground can only push within the foot).
- A soft ankle spring (`footFlatHertz`) keeps the foot flat, so a heel- or toe-first contact rolls onto the whole foot.
- **`balanceAssist`** (1 Mg·stud of body weight, on by default, ground only, never in flight): a capped correction that turns the whole body about its feet back over them. It stands in for the small foot adjustments a person makes; a planar pair of feet can't step. Without it the body still stands indefinitely when undisturbed (tested), but even a 1 stud/s shove topples it; with it, shoves of ±4 studs/s recover.

**Crouch and jump** (GAME_PLAN §4: crouching is Tuck; releasing Tuck from a crouch jumps):
- Crouch depth is measured from the actual knee angle. Releasing Tuck at depth ≥ `jumpMinCrouch` (0.25) starts the **push**.
- The push chooses the **ground reaction force**: the body's weight plus `jumpStrength` (1.5) body weights upward, applied right under the centre of mass. Each leg joint produces the torque that force needs about it, `τ_j = −((c − p_j) × F)`, capped at `jumpLegStrength` × strength. Where the force acts under the foot (the centre of pressure `c`) sets the moment about the centre of mass, the only thing that changes the body's spin: it steers the spin to zero at `jumpSpinHertz`, or toward `jumpArchSpin` (1.0 rev/s) backward while Arch is held (a back-flip takeoff), within what the foot can physically do.
- The hips bring the trunk from the crouch's lean to upright (`jumpTorsoHertz`), internally.
- The push stops when the knees pass `jumpLockKnee` (10°) or the feet leave the ground: an uncontrolled toe-off added spin and drift.
- **Centre of pressure range (P1.2 feedback round):** during an Arch push the centre of pressure stays within the middle 60% of the foot (`PUSH_COP_RANGE`, blended in by how much Arch is held). Before, a back-flip takeoff pinned it at the toe edge. The ankles then tipped the body onto its toes and the knees stopped extending (100° → 77°), so the Arch jump lost a third of its height (1.35 vs 1.69 studs).
  - A plain push keeps the whole foot. Round 1 had applied the narrower range to every jump; plain takeoffs then changed subtly, and landings with Arch held fell 3 of 3 times (round 2 fix: plain jumps are exactly as first playtested again).
- **Back-flip takeoff:** while Arch is held, the push also drops the horizontal drift damping. It pushed the feet forward under a body rotating back, and its moment cancelled the spin (0.08 rev/s with it, 0.38 without).
- Measured: plain jumps rise 1.4–1.8 studs (≈ 0.45 m at this scale) with ~0.5–0.65 s of air. They take off with ≤ 0.1 rev/s spin and ≤ 1.3 studs/s drift, and land back on the feet.
- An Arch takeoff rises 1.78 studs (plain 1.73) with 0.38 rev/s backward spin. Tucking right away turns ≈ 0.43 rev before landing: **the feet alone can't make a standing back flip** at this height.
  - A real standing back tuck leaves the ground at ≈ 0.7–0.8 rev/s with a similar airtime. It gets there with a backward lean that puts the centre of mass behind the toes, which this push controller doesn't do.
  - More height doesn't solve it: `jumpStrength` 1.5 → 3.5 raises the rise only 1.73 → 2.38 studs (airtime 0.63 → 0.75 s), because the push ends at knee lock (and the leg torque cap binds). Jumps that tuck until touchdown then land fallen (round 2 correction: plain jumps land fine).
- **Takeoff spin (`jumpSpinAssist`, default 1 since P1.2 round 2; 0 = pure physics):** after a jump with Arch, this share of the spin still missing to `jumpArchSpin` is added as a torque about the centre of mass over the first 0.1 s of flight. It isn't muscle.
  - It acts after takeoff because adding it during the push tipped the body back while the legs were still extending (rise 1.78 → 0.56 studs).
  - **Why it's on:** in the air Arch can't create rotation, because angular momentum is conserved (holding Arch from rest turns the torso back 7° while the legs swing 31° the other way). So a standing back flip has to get its spin at takeoff, and the feet alone give 0.38 rev/s.
  - **Why 1.0 rev/s:** across 81 timings (A early / on time / late, tuck 0.05–0.15 s after takeoff for 0.3–0.7 s), landed back flips were 0 at 0.8 rev/s, 10 at 0.9, 21–23 at 1.0, and 2 at 1.1 (over-rotation). A real back tuck leaves at 0.7–0.8 rev/s with ~0.65 s of air; this body's flight is ~0.55 s.
- **Late Arch window:** A pressed up to 0.12 s after takeoff (about 0.3 s after releasing S) still makes the jump a back flip (`ARCH_LATE_WINDOW`, scaled like the other ground timers on the moon). Before round 2, A had to be held at the moment S was released: 0.06 s late gave 0.30 rev/s, 0.2 s late nothing. Later than the window, Arch is only a shape change.
- Result: an Arch takeoff leaves at ≈ 1.05 rev/s backward (A on time or 0.2 s late), full height (1.78 studs). With a tuck it turns 0.87–1.2 rev, depending on when you open. Plain jumps are unaffected.
- **Landing a back flip is the next limit.** It works when arriving about 30–40° under-rotated with the tuck held. An upright touchdown still spins at 1–1.9 rev/s with the legs half-folded and falls back.
  - The landing reflex places the feet for forward speed, not for spin or a just-finished shape change. After a short mid-air tuck on Earth it puts the feet 0.6–1.5 studs ahead of the centre of mass, and the body falls back; that happens in the playtested build too.
  - A spin-aware landing reflex is the proposed next step (PLAYTEST_P1_2.md, round 2).

**Landing:**
- **Landing reflex** (air, no shape input, trunk within `landingReflexTilt`, falling): the hips swing the legs so the middle of the feet lands under the centre of mass plus half the pendulum capture-point lead (two-link leg geometry with soft knees), and the ankles level the feet. Internal motion only. It fades out mid-flip.
- **Yield, then recover:** at touchdown the knees and ankles give way (their targets follow the body, so their motors act as dampers at `landingHertz`/`landingDampingRatio`) until the fall has stopped or `landingAbsorbTime` passes; then the legs rise smoothly from wherever they are. The hips keep holding the trunk throughout. (A fixed "landing bend" target compressed less than the impact did, and the springs then threw the body back off the ground.)

**Gravity scaling:** a body can't crouch faster than it can fall and balance works on a pendulum's time scale (√(length/g)), so all ground rates (crouch smoothing, balance, standing springs, push spin/trunk steering) scale by √(g/g₀) and all ground timers by its inverse. On the moon, standing plays out ~2.5× slower, like everything else gravity-driven.

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

## 8. Swing shaping (hanging) — as built

- **Pumping is physical:** the motors do work as the shape changes. Measured from a 60° start over 15 s (peak angle in the last 4 s): no input 50° (decays), Tuck while rising / Arch while falling 145° (P1.2 as first tested: 121°), the opposite timing 8° (damps).
- **From a still hang** (`hangStartAngle` 0), with the rhythm judged by the swing's angle and direction: 90° at ≈ 10–12 s and over the top (a giant) at ≈ 12–15 s. Early growth is unchanged from P1.2 as first tested, which stalled at ≈ 107°. The first few swings are slow because the shape changes can only pump a swing in proportion to its size.
  - The Hang scene's default 60° start skips that phase: the "initial boost" in the playtest.
- **Bar shoulders:** while gripping, the shoulder motor runs at `gripShoulderHertz` (18 Hz; P1.1 behaviour is 6). The shoulders turn the whole hanging body, and at 6 Hz Arch and Tuck barely moved them (Neutral / Arch / Tuck gave −3° / −4° / −10° against targets 8 / −25 / 25). At 18 Hz: 6° / −21° / 20°, and pumping works as above.
- **Bar elbows and hips (P1.2 feedback round):** the playtester felt that swinging actively sometimes slowed the body down. Two joints were fighting the swing:
  - **Elbows** now use `gripShoulderHertz` too. The bar's pull runs through them, and at 6 Hz they flexed under the swing's load and their damping drained it. Pumping stalled at ≈ 107°; the relaxed swing lost 3.7° per cycle at 90° (now 2.3–2.5°).
  - **Hips** use `gripHipHertz` (10 Hz). They hold the legs against the swing's pull; at 6 Hz a held Tuck or Pike sagged at the bottom of each swing and sprang back at the top, the reverse of pumping. Per cycle at 90°, holding Pike lost 10.7° (now 5.6°) and Tuck 6.8° (now 4.1°), against 2.3° relaxed.
  - The price is a livelier pumping motion: torso jerk while pumping 2022 → 4082 (P1.1 motor settings: 3200). Extra damping on the bar hip brings it back down, but ζ 2 undoes much of the fix (Pike loss 7.1°).
- **Assists and limits:**

| Knob | Effect |
|---|---|
| `gripFriction` | Friction torque at the grip (joint friction), in Mg·stud (0.02 default); energy lost per swing |
| `angularDamping` | Air-like loss |
| `swingAssist` | Optional extra torque about the grip, applied only when the shape change is **in phase** (the inertia about the grip is decreasing while the centre of mass rises) and only below the energy cap. Default 0. |
| `maxSwingSpeed` | **Energy cap:** the swing may carry at most the energy of the **straight** body passing the bottom at this rotation rate (12 rad/s). Any excess is braked away smoothly: removed at 40/s, at most 4 Mg·stud. It holds against pumping into giants and against `swingAssist` = 2: a 6 rad/s cap keeps the swing energy within 1.09× the cap. A tucked body with the capped energy spins faster than the cap rate, as physics says. Before the feedback round the cap was measured against the current shape, so tucking lowered it as it sped the swing up, and near the cap every tuck was braked. |

Torques about the grip are applied as a whole-body rotation (the same angular acceleration for every body), so they never bend the body. `swingAssist` never adds more energy in a step than the cap leaves room for.

## 9. Time step, time scale, gravity, interpolation

- `dt = 1/simHz` (240). Each frame: `acc += min(realDt, 0.1)·timeScale`. Run `floor(acc/dt)` steps, capped at `maxStepsPerFrame` (excess is dropped). Render alpha = `acc/dt`.
- **Slow motion = a smaller `timeScale`.** It applies to **the player's whole simulated world**, including kinematic equipment, whose motion is a deterministic function of the player's sim time. That matches the reference (the wheels slow down too). While slowed, the client shows the speed at the top of the screen (`SLOW-MO 0.25×`; `SpeedIndicator.luau`, display only).
- **Moon gravity** = `gravity × moonGravityScale` (0.165, so 35 → 5.775 studs/s²). It combines with slow-mo. Analysis (P1.2), all measured headlessly:
  - **Physically consistent.** A fixed launch (the Tumble scene) reaches `1/0.165` = 6.06× the Earth height (measured 6.07×) and stays up 6.06× as long.
  - **Muscle-driven motion depends on `strengthGravityScaling`.** At the default 1 (P1.1 behaviour) strength follows gravity: every gravity-driven motion keeps its shape and is √6.06 ≈ 2.46× slower. A standing jump rises the same (1.95 vs 1.69 studs) with 2.7× the airtime (1.40 vs 0.52 s); the reference's moon jump shows ~1.5 s of airtime. At 0, Earth strength on the moon: real-moon physics, a 7.0-stud jump with 2.9 s of airtime.
  - Holding a tuck: with spins that come from gravity-driven swings (release from the bar), the default holds the tuck exactly as well as fixed strength (spin gain ×1.99 vs ×2.00), because spin rates shrink with √g too. Only a launch spin that is *not* gravity-scaled (the Tumble test scene's fixed 7 rad/s) overpowers the weaker moon muscles.
  - Decision: the multiplier is correct and is left as is; strength keeps following gravity by default (matches the reference's timing, and the moon plays like Earth in slow motion); `strengthGravityScaling` is the knob if you want real-moon jumps.
- **Player-validated (P1.2 playtest): moon gravity and slow motion are liked features; keep their behaviour.** Movement tuning must not change them unless a concrete technical issue is found. Two `Movement.spec` tests guard them:
  - Slow motion replays bar and ground movement, on Earth and on the moon, bit-identically in simulation time at 0.5 / 0.25 / 0.1, taking exactly 2 / 4 / 10× the real time.
  - Moon mode keeps its feel: swing period ×2.46, the same swing decay, jump height 1.14× and airtime ≈ 2.7× Earth. The defaults are fixed (0.165, strength follows gravity), and the settings survive Reset.
  - Both tests pass on the playtested build and the current one (PLAYTEST_P1_2.md).
- **Interpolation:** the renderer blends the previous and current body poses by alpha.
- **Input** (as built, `Input.luau`): the client sends one device-independent frame per render frame (`Sim.setInput`).
  - held inputs (arch, tuck, twist left/right) apply to every step in a frame
  - presses are cumulative **counters**; the controller acts on every increase at its next step, so a press on a frame that runs 0 steps (slow motion, high frame rates, pause) waits instead of being lost, and several presses in one frame count once
  - a press made before a Reset never fires after it; non-finite levels are sanitized
- **Windows use simulation time by default**, so slow-mo is naturally easier. `windowsInRealTime` switches this.

## 10. Determinism

- There's no randomness, no clock reads and no Instance access inside `step`.
- The world slice and equipment are plain data. Solver iteration order is fixed.
- Same device + same inputs = bit-identical result (tested). Across devices we only claim agreement within tolerance.

## 11. Known simplifications (on purpose)

1. Paired limbs, no spine bend (as in the reference). Elbows exist but the elbow motor holds the arms nearly straight.
2. Planar dynamics. Twist is a controlled render rotation plus an exact in-plane mirror, not emergent 3D rotation (no twisting somersault coupling).
3. No self-collision.
4. One planar pair of feet: no stepping. Balance recovery beyond the feet uses `balanceAssist`. Hand-plants, handstands and vaults are Phase 2, on the same solver.
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
| `motorHertz` / `motorDampingRatio` | 6 / 1.25 | 0.5–30 / 0–3 | Hz / ζ | Pose springs (P1.1 damping was 0.8) |
| `shoulderMaxTorque` / `elbowMaxTorque` / `hipMaxTorque` / `kneeMaxTorque` / `ankleMaxTorque` | 3.0 / 2.0 / 2.0 / 1.0 / 0.3 | 0–20 | Mg·stud | Lower = floppier |
| `strengthGravityScaling` | 1 | 0–1 | × | 1 = strength follows gravity (P1.1); 0 = Earth strength everywhere (§9) |

**Body ⟲**

| Param | Default | Range | Unit |
|---|---|---|---|
| `bodyMass` | 10 | 1–100 | mass |
| `upperArmLength` / `forearmLength` | 1.0 / 1.0 | 0.5–1.5 | studs |
| `trunkLength` | 2.0 | 1.5–2.5 | studs |
| `thighLength` / `shankLength` / `footLength` | 1.1 / 1.1 / 0.7 | 0.4–1.6 | studs |
| `limbInertiaBoost` | 1 | 0–1 | × (0 = uniform capsules as in P1.1) |

Mass fractions, radii, the heel (`FOOT_HEEL`), shank trim and the inertia profile are constants in `Rig.luau`.

### P1.2 parameters (implemented, live-editable)

**Shape** — `shapeFreqClose` / `shapeFreqOpen` 8 / 6 Hz (1–30; 30 ≈ no smoothing). `tuckHertz` 10 Hz (1–30): the squeeze while tucking or piking off the bar (≤ `motorHertz` = none).

**Swing**

| Param | Default | Range | Unit | Notes |
|---|---|---|---|---|
| `gripShoulderHertz` | 18 | 1–60 | Hz | Shoulder and elbow springs while gripping (6 = P1.1) |
| `gripHipHertz` | 10 | 1–60 | Hz | Hip springs while gripping (at least `motorHertz`; 6 = P1.2 as first tested) |
| `hangStartAngle` | 60 | 0–170 | ° | Hang scene start (applies on Reset); 0 = a still hang |
| `gripFriction` | 0.02 | 0–1 | Mg·stud | |
| `swingAssist` | 0 | 0–2 | × | Only in phase, only below the cap |
| `maxSwingSpeed` | 12 | 4–30 | rad/s | Energy cap |

**Release** — `releaseVelocityScale` / `releaseSpinScale` 1 / 1 (0.5–1.5 ×), `releasePop` 0 (0–20 studs/s). Defaults = pure physics.

**Twist** — `twistMode` 0 (0 hold / 1 momentum), `twistRate` 1.5 rev/s (0.5–5), `twistAccel` / `twistStopAccel` 20 / 30 rev/s² (2–100), `twistSettleTime` 0.12 s (0–1).

**Ground**

| Param | Default | Range | Unit | Notes |
|---|---|---|---|---|
| `groundShapeHertz` | 2 | 0.5–30 | Hz | Crouch / rise / reach speed |
| `groundLegHertz` / `groundLegDampingRatio` | 8 / 1 | 2–60 / 0–3 | Hz / ζ | Standing leg springs |
| `groundLegStrength` | 1.5 | 0.5–5 | × | Leg strength while standing |
| `footFlatHertz` | 4 | 0.5–30 | Hz | Keeps the foot flat |
| `gravityCompensation` | 1 | 0–1.5 | × | Share of the weight the leg muscles carry |
| `balanceHertz` / `balanceDampingRatio` | 1.5 / 1 | 0–6 / 0–3 | Hz / ζ | Ankle balance |
| `balanceAssist` | 1 | 0–5 | Mg·stud (weight) | Ground-only assist; 0 = pure muscle |
| `jumpStrength` | 1.5 | 0–6 | body weights | Push; rise ≈ this × crouch depth in studs |
| `jumpLegStrength` | 3 | 0.5–8 | × | Leg torque cap during the push |
| `jumpMinCrouch` / `jumpPushTime` / `jumpLockKnee` | 0.25 / 0.3 / 10 | 0–1 / 0.05–1 s / 0–60° | | |
| `jumpSpinHertz` / `jumpArchSpin` | 4 / 1.0 | 0–20 Hz / 0–3 rev/s | | Spin control; back-flip takeoff spin with Arch |
| `jumpSpinAssist` | 1 | 0–1 | × | Takeoff spin after an Arch takeoff (1 = reach `jumpArchSpin`; 0 = pure physics) |
| `jumpTorsoHertz` / `jumpHertz` | 3 / 12 | 0–12 / 2–60 | Hz | Trunk steering / arm swing during the push |
| `landingReflex` / `landingReflexTilt` | 1 / 45 | 0–1 / 5–90° | | Legs under the body before landing |
| `landingHertz` / `landingDampingRatio` / `landingAbsorbTime` | 3 / 2.5 / 0.5 | | Hz / ζ / s | Landing damper |
| `groundGrace` / `fallTiltAngle` | 0.06 / 75 | 0–0.3 s / 20–90° | | State thresholds |

### Later milestones (specified, not yet in `Tuning.luau`)

Everything below is added when its milestone is built (P1.3 onward).

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
