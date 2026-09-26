# Physics Design — Gymnast Core

Status: **Proposed — awaiting approval.** This is the spec the prototype will implement.

Scope: the custom gameplay-physics core chosen in [TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md) §2–4. It covers hanging and swinging, Arch/Tuck, Let Go, flight, flips, twists, intentional catching, momentum transfer, time scale and gravity. It does not cover native crash ragdolls, landings or multiplayer; those come later.

Design principles:
1. **Physically based, game-tuned.** Start from real mechanics (conserved angular momentum, pumping through body-shape changes). Add explicit, named multipliers where the game needs to bend reality.
2. **Every feel-relevant number is a tuning parameter** (§12), editable live in the debug panel.
3. **Catching is always an intentional, timed player action.** The window is forgiving but never automatic.
4. **Frame-rate independent.** Fixed 240 Hz steps; rendering interpolates.

---

## 1. Units and conventions

- Length in **studs**, time in **seconds**. Angles are **degrees** in the panel and radians internally.
- Mass is normalized: total body mass = 1. Only ratios matter, because every force is gravity or inertia.
- World up is +Y. The prototype bar is horizontal along world X, 10 studs above the floor. The swing plane is therefore the world YZ plane.
- Default `gravity` = 35 studs/s². That's Earth gravity for a body this size (9.81 m/s² ÷ 0.28 m per stud). It gives a natural hanging swing period of about 2 s. This is a starting point; the final value is chosen by feel.

## 2. Body model

A fixed **gameplay skeleton**, identical for every player whatever their avatar. The left and right limbs move together.

| Segment | Size (studs) | Mass fraction | Notes |
|---|---|---|---|
| Arms (both) | 2.0 shoulder → grip | 0.10 | Always straight. Hands are 1.1 apart along the body's side-to-side axis. |
| Head | sphere r = 0.5, center 0.8 above the shoulder line | 0.08 | Rigidly attached to the trunk |
| Trunk | 2.0 shoulder line → hip joint | 0.43 | Shoulder half-width 0.75 (affects twist inertia and visuals) |
| Thighs (both) | 1.1 | 0.28 | Hip half-width 0.4 |
| Shanks + feet (both) | 1.25 | 0.11 | |

Grip to soles is about 6.35 studs, so hanging from a 10-stud bar leaves the feet about 3.6 studs off the floor. Segment inertia uses thin rods plus a radial term for the twist axis.

**Shape = 3 joint angles** in the body's side (sagittal) plane, all 0 for a straight body:

| Joint | Positive (+) | Negative (−) |
|---|---|---|
| Shoulder `θs` | arms toward the chest ("closed") | arms behind the head ("open/arched") |
| Hip `θh` | flexion (pike/tuck) | extension (arch) |
| Knee `θk` | flexion; limited to [0°, 150°] | — |

**Body frame:** x = side-to-side (the somersault axis), y = feet → head (the twist axis), z = back → chest.

## 3. State machine

```
            Reset / start
                 │
                 ▼
  ┌──────────► HANGING ──── Let Go (press) ────► FLIGHT ─────┐
  │  (two hands, 1-DOF swing)                    │   │       │
  │                                              │   │ body point below floor
  └──── valid catch (Grab press, §7) ◄───────────┘   ▼       │
                                                  FALLEN ─────┘
                                  (freeze → auto-reset after delay, or Reset)
```

- **Reset** works from any state. It puts you hanging still at the bar's center in the neutral shape.
- In HANGING, Grab and Twist do nothing. In FLIGHT, Let Go does nothing.
- (Post-prototype: LANDED, CRASHED hand-off to native ragdoll, ONE_HAND.)

## 4. Shape control (Arch / Tuck / Pike)

**Input to target shape:**
- Inputs: `tuck` ∈ [0,1] and `arch` ∈ [0,1]. Keyboard and touch give 0 or 1; gamepad triggers are analog.
- Both held means **Pike**: `p = min(tuck, arch)`, `t = tuck − p`, `a = arch − p`.
- `target = Neutral + t·(Tuck − Neutral) + a·(Arch − Neutral) + p·(Pike − Neutral)`

| Pose | θs | θh | θk |
|---|---|---|---|
| Neutral (slight hollow) | +8° | +8° | 0° |
| Arch | −20° | −25° | 0° |
| Tuck | +20° | +120° | +130° |
| Pike | +15° | +110° | 0° |

All pose angles are tuning parameters.

**Tracking:**
- Each joint follows its target with a critically-damped-ish spring: `θ̈ = ω²(θ* − θ) − 2ζω·θ̇`, integrated semi-implicitly. `|θ̇|` is clamped to `shapeMaxRate`.
- The spring frequency differs by direction: `shapeFreqClose` when moving toward flexion (tucking) and `shapeFreqOpen` when opening (kick-out). That's the equivalent of the original's "tuck speed" setting.
- The shape velocity `θ̇` matters physically: it feeds the angular-momentum coupling (§5, §6). A fast kick-out therefore really changes the swing and the spin.

## 5. Hanging dynamics (two-hand hinge)

**State:**
- `barId`, grip point `g`, bar axis `a` (unit vector)
- `facing` (±1: which way the chest faces relative to the plane's rotation direction)
- swing angle `φ` and rate `φ̇`
- shape `q = (θs, θh, θk)` and shape rate `q̇`

**Plane setup:**
- Gravity projected onto the plane: `g⊥ = g − (g·a)a`. This makes tilted bars work. A vertical pole gives no restoring torque (a free spin).
- `φ = 0` means the arms point straight "down" `g⊥` from the grip.

**Key quantities** (from forward kinematics of the 4-segment chain):
- `A(q)` — moment of inertia of the whole body about the bar axis. It depends only on shape.
- `B(q)·q̇` — angular momentum about the bar produced by shape motion alone.
- `τg = ((r_com − g) × M·g⊥) · a` — gravity torque.
- The swing's angular momentum about the bar is `L = A·φ̇ + B·q̇`.

**Per step** (`dt = 1/simHz`):
1. Update the shape (`q`, `q̇`) toward the target (§4).
2. **Pump shaping.**
   - Keeping `L` fixed, recompute `φ̇' = (L − B·q̇)/A`. This is what the physics says the shape change did.
   - Let `ΔE` = the change in kinetic energy caused by that shape update.
   - Add `(pumpGain − 1)·ΔE` if `ΔE > 0`, or `(pumpLossGain − 1)·ΔE` if `ΔE < 0`. Apply it by rescaling `φ̇` (keep its sign; clamp the energy at ≥ 0). Then recompute `L`.
   - With both gains at 1.0 this is pure physics. Higher `pumpGain` makes good timing pay off more; higher `pumpLossGain` punishes bad timing more.
3. Torques: `τ = τg − swingDamping·φ̇·A − gripFriction·sign(φ̇)`.
4. `L += τ·dt`, then `φ̇ = (L − B·q̇)/A`, then `φ += φ̇·dt` (semi-implicit Euler).
5. Soft cap: above `maxSwingSpeed`, extra damping pulls `|φ̇|` back. This is an energy cap and the guard against infinite-energy loops.
6. Floor check (§10).

**Why pumping works:** when the body closes up (smaller `A`) while `L` stays the same, it spins faster, and the shape change does work. Opening up and closing at the right moments in each swing (arch through the bottom, hollow/pike on the upswing) adds energy until a full giant swing is possible. Bad timing removes energy. This is real high-bar mechanics; the model doesn't script it.

**Energy readout (debug):** `E = KE + PE`. We also show **swing height %**: the energy needed for the center of mass to clear the top of the bar in the current shape. 100% means a giant is possible.

## 6. Release and flight

### 6.1 Release (Let Go press, HANGING → FLIGHT)

Applied on the first step after the press. There is **no delay and no buffering**, because release timing is pure skill.
1. From `φ, φ̇, q, q̇`, compute the world center of mass `p` and velocity `v`, and the angular momentum about the center of mass: `L_com = (L − M((p − g) × v)·a)·a`. It's planar, so it points along `a`.
2. Build the body orientation `R` from `a`, `facing` and the arm and trunk directions.
3. Game shaping:
   - `v *= releaseVelocityScale`
   - `v += releasePop · up`
   - `L_com *= releaseSpinScale`
4. Start `regrabLockout`: no catch tests for this long, which prevents an instant release-and-catch.

### 6.2 Flight

**State:** center of mass `p` and velocity `v`, orientation quaternion `R`, world angular momentum `L` (about the center of mass), `q`, `q̇`, twist rate `ωtw`.

**Per step:**
1. Update the shape (§4).
2. Recompute body-frame segment positions relative to the **current** center of mass (the center of mass moves inside the body as it changes shape). From them compute the inertia tensor `I(q)` (3×3) and the internal momentum `h(q, q̇)` along x.
3. Projectile motion: `p += v·dt + ½·gVec·dt²`, then `v += gVec·dt`. This is exact for a parabola. When `airDrag > 0`, also apply `v *= (1 − airDrag·dt)`.
4. Body rate: `ω_b = spinScale · I(q)⁻¹ (Rᵀ·L − h)`. Then add the twist control about the body's y axis: `ω_b.y += ωtw`.
5. `R ← normalize(R ⊗ exp(ω_b·dt))`.
6. Update the twist rate (§6.3) and the flip/twist counters (for debug and future trick detection).
7. Floor check (§10).

**What this gives for free:**
- **Tuck spins faster and opening slows the spin** (smaller `I`, same `L`).
- **Kicking out mid-air changes rotation realistically** (the `h` term).
- **Twisting while somersaulting behaves correctly**: `L` stays fixed in the world while the body turns under it.

### 6.3 Twist

Twist is a **designed control**, not emergent physics. Real twisting comes from subtle arm and hip asymmetry, which is not controllable on a phone.

| `twistMode` | Behavior |
|---|---|
| `hold` (default) | While Twist L/R is held, `ωtw` accelerates toward ±`twistRate` at `twistAccel`. Released, or both held, it decelerates to 0 at `twistStopAccel`, holding the current angle. |
| `momentum` (original-style) | A tap sets the spin going. A tap on the opposite side reverses it. Holding both stops it and holds the angle. |

Twist is only active in FLIGHT. On landing a catch, any leftover twist is resolved by the catch alignment (§7.6).

## 7. Intentional catch system

This is the most important system in the game. Goals: **never automatic, forgiving on mobile, skill decides.**

### 7.1 Definitions

- **Hand center `H`**: midpoint of both hands. Also left and right hands `H_L`, `H_R` (for alignment and the future one-hand catch).
- **Grippable span**: the bar segment shrunk by `barEndMargin` at both ends.
- **d**: distance from the hand center's **swept path this step** (`H_prev → H_now`) to the bar axis within the grippable span. The swept test means fast hands can't skip past the bar between steps.

### 7.2 Catch conditions (all must hold on a step)

1. **Proximity:** `d ≤ catchRange`.
2. **Alignment:** the angle between the body's x axis and the bar axis, folded to [0°, 90°], is `≤ catchAlignTolerance`. This decides how early you can catch while still finishing a twist (a "mid-twist regrab").
3. **Reach:** the bar is in front of the arms: `dot(armDir, unit(barPoint − shoulder)) ≥ cos(catchReachAngle)`. No catching bars behind your back or at your feet.
4. **Not locked out:** at least `regrabLockout` has passed since release.
5. *(Optional)* **Speed:** the hand speed relative to the bar is `≤ maxCatchSpeed`. Off by default.

If several bars qualify, the smallest `d` wins.

### 7.3 Grab attempt lifecycle

```
Grab PRESS (edge) at step n, state == FLIGHT:
  if n < cooldownUntil         → ignored (event: GrabIgnored)          -- anti-mash
  elif late grace finds a valid step k in (n − lateSteps, n)  → CATCH at k (rollback, §7.4)
  else                         → open attempt [n, n + earlySteps]

Each FLIGHT step while an attempt is open:
  if conditions hold (swept)   → CATCH now
  elif step > attempt end      → attempt closes; cooldownUntil = step + cooldownSteps  (event: GrabMissed)

earlySteps = catchWindowEarly·simHz, lateSteps = catchWindowLate·simHz, cooldownSteps = grabCooldown·simHz
```

- **Only the press counts.** Holding Grab does **not** keep an attempt open. If holding counted, players would just hold it all the time and catching would be automatic in practice. `grabMode = hold` exists only as a debug/accessibility switch and is off by default.
- **Early press** (buffer): pressing up to `catchWindowEarly` before the hands reach the bar still catches.
- **Late press** (grace): pressing up to `catchWindowLate` *after* the best moment still catches (§7.4).
- **Mashing loses.** A missed attempt locks out new attempts for `grabCooldown`. A mistimed press costs you the real moment.
- Grab in HANGING or FALLEN is ignored and **not** queued.

### 7.4 Late-grab grace via rollback

The core keeps a ring buffer of the last `catchWindowLate + 50 ms` of FLIGHT states and per-step inputs (≈ 30 states, trivially small).

When Grab is pressed and no attempt is open:
1. Search backwards from the newest step for the **most recent** step `k` where §7.2 held. Most recent means the smallest correction.
2. Restore state `k`, apply the catch (§7.5), then **re-simulate** steps `k+1 … n` in HANGING using the recorded inputs.
3. The renderer gets a pose-correction event and blends it out over `catchBlendTime`, so the player never sees a pop.

`lateCatchMode` = `rollback` (default) · `snap` (catch at the current state if `d ≤ catchRange·lateRangeScale`) · `off`.

Why this matters: touch latency and 30 fps input quantization make players press slightly late. That's a device problem, not a skill problem. Grace is limited to a few tens of milliseconds, so timing still decides.

### 7.5 Catch resolution and momentum transfer

At the catch step:
1. **Grip point** `g` = the closest point on the grippable span to `H`.
2. **Facing** = the sign of `dot(body x, a)`. The body can catch facing either way.
3. **Swing angle** `φ` = the shoulder → grip direction projected into the plane perpendicular to `a`. Shape `q` and `q̇` carry over unchanged.
4. **Momentum transfer** (an inelastic catch keeps angular momentum about the bar):
   - `L_bar = (L_com + M·(p − g) × v) · a`
   - `φ̇ = (catchMomentumTransfer · L_bar − B(q)·q̇) / A(q)`
   - With `catchMomentumTransfer = 1.0` this is exact physics. Values above 1 are flagged in the panel and still limited by `maxSwingSpeed`.
5. **Discarded motion** (momentum along the bar, sideways swing, leftover twist) is absorbed by the grip. `impact = KE_before − KE_after` drives the feedback strength.
6. **Snap:** the simulation state snaps exactly, so the physics stays clean. Only the visual offset (at most `catchRange` plus the alignment correction) is blended over `catchBlendTime`.
7. **Optional hitstop:** `catchHitstop` seconds of sim-time freeze. Default 0; to be tested (single-player only, see §7.8).
8. Emit a `Catch` event: bar, `d`, quality, timing, rollback steps, impact, transfer ratio.

### 7.6 Catch quality and feedback

| Quality | Condition |
|---|---|
| **Perfect** | `d ≤ perfectRange` and no rollback |
| **Good** | `d ≤ catchRange` |
| **Save** | Caught through late-grace rollback |

- Timing is reported in milliseconds: how early the press was (buffered), or how late it was (rollback).
- Prototype feedback is deliberately minimal:
  - a catch sound (pitch and volume from quality and impact)
  - a small camera kick (`camShakeOnCatch` × impact)
  - a haptic pulse where the device supports it (Roblox mobile haptics are inconsistent, so it's optional)
  - quality and timing text in the debug overlay only

### 7.7 Grab assist

All forms of assist are separate knobs, so we can test each one:

| Assist | Knob | Default |
|---|---|---|
| Proximity forgiveness | `catchRange`, `perfectRange` | 0.9 / 0.3 studs |
| Time forgiveness | `catchWindowEarly`, `catchWindowLate` | 100 / 60 ms |
| Twist forgiveness | `catchAlignTolerance` | 35° |
| Trajectory magnetism | `grabAssistPull`: while an attempt is open and the bar is within `assistRadius`, a small acceleration pulls the center of mass toward the line that would catch | 0 (off) |
| Presets | `Off` · `Standard` · `Mobile-Forgiving` (larger range and windows) · `Hardcore` | Standard |

Rough numbers: hands reach about 20–30 studs/s near a regrab. A 0.9-stud range therefore lasts about 60–90 ms, and with the early and late windows the total press window is about 220–250 ms. Whether the trajectory reaches the bar at all depends on release timing, which is where most of the skill is.

### 7.8 Multiplayer note (for later)

- The catch is a function of state and a press at step `n`, so it can run under Roblox Server Authority.
- To avoid a server correction ever **reversing** a catch the player saw, the server validates catches with a slightly larger tolerance (`serverCatchTolerance`) than the client uses.
- Hitstop, if we keep it, must be render-only in multiplayer.

### 7.9 One-hand catch (designed, deferred)

**Use:** a fallback when only one hand is in range, or the twist is outside `catchAlignTolerance` but within `oneHandAlignTolerance`. It adds forgiveness plus a skill layer: a second timed Grab press brings the other hand onto the bar.

**Cost:** a 3D spherical-pendulum hanging mode with 2 swing angles plus spin about the arm, a timer that forces a release (`oneHandHoldTime`), and a way to get back into two-hand mode.

**Decision:** not in the first prototype. Add it only if playtests show misaligned catches feel unfair, or as Phase 2 depth. `allowOneHandCatch` is reserved (false).

## 8. Time step, time scale, gravity, interpolation

- `dt = 1/simHz` (default 240).
- Each frame: `acc += min(realDt, 0.1)·timeScale`. Run `floor(acc/dt)` steps, capped at `maxStepsPerFrame` (any excess is dropped: the game slows down rather than spiraling). Render alpha = `acc/dt`.
- **Slow motion** = a smaller `timeScale`. The physics code never knows. Presets: 1, 0.5, 0.25.
- **Moon gravity** = `gravity × moonGravityScale` (default 1/6). It combines with slow-mo.
- **Interpolation:** the renderer keeps the previous and current skeleton poses and blends them by alpha (position lerp, rotation slerp). This is required for smooth slow motion and for frame rates that don't divide 240.
- **Input timing:**
  - Held inputs apply to every step in a frame.
  - Press edges apply at the frame's first step.
  - If a frame runs 0 steps (deep slow-mo), the edges wait for the next step and are never lost.
- **Windows are measured in simulation time** by default. The same spatial and temporal window at every speed means slow-mo is naturally easier, as players expect. `windowsInRealTime` switches this.

## 9. Determinism rules (for tests, replays, later networking)

- There's no randomness, no `os.clock()`, and no Instance access inside `step`.
- All state is plain numbers (angles and scalars as doubles).
- Same device + same inputs per step = same result. Tests check this bit-for-bit on one machine. Across devices we only claim agreement within tolerance.

## 10. Floor, fall, reset (prototype)

- Each step, if any skeleton point (hands, head, hips, knees, feet) is below `floorY`, the state becomes **FALLEN**. The pose freezes and the game resets after `autoResetDelay` (or immediately on Reset).
- The body passes through the bar. Body–bar collision is deliberately left out of the prototype; we decide on it in Phase 2.
- If the center of mass goes more than 500 studs away, the game resets.

## 11. Known simplifications (on purpose)

1. Left and right limbs move together. Elbows are always straight.
2. Hanging grip is fixed: no sliding along the bar and no sideways swing (two-hand hinge).
3. Twist is a designed control (§6.3).
4. Shape is driven by springs and ignores load: centrifugal force can't pull you out of a tuck. If testers find it too "robotic", add `shapeLoadCompliance`.
5. No body–bar collision, no landing, no crash ragdoll (Phase 2).
6. No render-only secondary motion yet (Phase 2 if needed, see TECHNICAL_DESIGN §11).

## 12. Tuning parameters

All of these live in `Tuning.luau` with default, min, max, unit, category and description. The debug panel is generated from it; presets are saved as JSON in `tuning/presets/`. **All defaults are starting guesses to be tuned by playtesting.** Parameters marked ⟲ take effect on Reset.

### World and time
| Param | Default | Range | Unit | Notes |
|---|---|---|---|---|
| `gravity` | 35 | 10–120 | studs/s² | Earth-scale for this body size |
| `moonGravityScale` | 0.165 | 0.05–1 | × | Applied when Moon is on |
| `timeScale` | 1.0 | 0.05–2 | × | Presets 1 / 0.5 / 0.25 |
| `simHz` ⟲ | 240 | 120 / 240 / 480 | Hz | |
| `maxStepsPerFrame` | 16 | 4–64 | steps | |
| `airDrag` | 0 | 0–1 | 1/s | |

### Body ⟲
| Param | Default | Range | Unit |
|---|---|---|---|
| `armLength` | 2.0 | 1.5–2.5 | studs |
| `trunkLength` | 2.0 | 1.5–2.5 | studs |
| `thighLength` | 1.1 | 0.8–1.5 | studs |
| `shankLength` | 1.25 | 0.9–1.6 | studs |
| `handSpacing` | 1.1 | 0.6–1.8 | studs |

(Mass fractions are fixed constants in `Body.luau`.)

### Shape
| Param | Default | Range | Unit | Notes |
|---|---|---|---|---|
| `neutralShoulder` / `neutralHip` | 8 / 8 | −30–40 | deg | |
| `archShoulder` / `archHip` | −20 / −25 | −60–0 | deg | |
| `tuckShoulder` / `tuckHip` / `tuckKnee` | 20 / 120 / 130 | 0–150 | deg | |
| `pikeShoulder` / `pikeHip` | 15 / 110 | 0–150 | deg | |
| `shapeFreqClose` | 6 | 1–20 | Hz | Tuck speed |
| `shapeFreqOpen` | 7 | 1–20 | Hz | Kick-out speed |
| `shapeDampingRatio` | 0.85 | 0.3–1.5 | ζ | < 1 gives lively overshoot |
| `shapeMaxRate` | 900 | 90–2000 | deg/s | |

### Swing (hanging)
| Param | Default | Range | Unit | Notes |
|---|---|---|---|---|
| `swingDamping` | 0.03 | 0–1 | 1/s | Viscous loss |
| `gripFriction` | 0 | 0–5 | normalized torque | Coulomb loss |
| `pumpGain` | 1.0 | 0–3 | × | Energy gained from good shape timing |
| `pumpLossGain` | 1.0 | 0–3 | × | Energy lost from bad timing |
| `maxSwingSpeed` | 12 | 4–30 | rad/s | Soft cap (anti-infinite-energy) |

### Release
| Param | Default | Range | Unit |
|---|---|---|---|
| `releaseVelocityScale` | 1.0 | 0.5–1.5 | × |
| `releaseSpinScale` | 1.0 | 0.5–1.5 | × |
| `releasePop` | 0 | 0–20 | studs/s |
| `regrabLockout` | 0.15 | 0–0.5 | s |

### Flight and twist
| Param | Default | Range | Unit | Notes |
|---|---|---|---|---|
| `spinScale` | 1.0 | 0.5–2 | × | Non-physical somersault multiplier |
| `twistMode` | hold | hold / momentum | — | |
| `twistRate` | 2.0 | 0.5–5 | rev/s | |
| `twistAccel` | 20 | 2–100 | rev/s² | |
| `twistStopAccel` | 30 | 2–100 | rev/s² | |

### Catch
| Param | Default | Range | Unit | Notes |
|---|---|---|---|---|
| `grabMode` | press | press / hold | — | `hold` = debug/accessibility only |
| `catchRange` | 0.9 | 0.2–3 | studs | Hand center to bar axis |
| `perfectRange` | 0.3 | 0–1.5 | studs | |
| `catchWindowEarly` | 0.10 | 0–0.4 | s | Press buffer |
| `catchWindowLate` | 0.06 | 0–0.2 | s | Late grace |
| `lateCatchMode` | rollback | off / snap / rollback | — | |
| `lateRangeScale` | 1.3 | 1–2 | × | `snap` mode only |
| `grabCooldown` | 0.20 | 0–0.6 | s | After a missed attempt |
| `catchAlignTolerance` | 35 | 0–90 | deg | Mid-twist catch |
| `catchReachAngle` | 75 | 30–120 | deg | |
| `maxCatchSpeed` | 0 (off) | 0–200 | studs/s | |
| `grabAssistPull` | 0 | 0–60 | studs/s² | Trajectory magnetism |
| `assistRadius` | 2.0 | 0.5–5 | studs | |
| `catchMomentumTransfer` | 1.0 | 0–1.25 | × | > 1 flagged |
| `catchBlendTime` | 0.10 | 0–0.3 | s | Visual snap smoothing |
| `catchHitstop` | 0 | 0–0.1 | s | |
| `barEndMargin` | 0.3 | 0–1 | studs | |
| `windowsInRealTime` | false | bool | — | |
| `allowOneHandCatch` | false | bool | — | Reserved, deferred (§7.9) |

### Camera
| Param | Default | Range | Unit |
|---|---|---|---|
| `camDistance` | 18 | 8–40 | studs |
| `camFov` | 55 | 30–90 | deg |
| `camYaw` | 20 | −60–60 | deg (0 = looking straight along the bar) |
| `camPitch` | −5 | −30–30 | deg |
| `camFollowFreq` | 3 | 0.5–10 | Hz |
| `camFocusBias` | 0.5 | 0–1 | bar ↔ body center of mass |
| `camZoomBySpeed` | 0.2 | 0–1 | × |
| `camShakeOnCatch` | 0.15 | 0–1 | × |

### Input and mobile
| Param | Default | Range | Notes |
|---|---|---|---|
| `touchLayout` | A | A / B | See GAME_PLAN §4 |
| `buttonScale` | 1.0 | 0.6–1.6 | |
| `hitPadding` | 12 | 0–40 px | Invisible extra touch area |
| `buttonOpacity` | 0.35 | 0.1–1 | |
| `hapticsOnCatch` | true | bool | Where supported |

### Fall and reset
| Param | Default | Range | Unit |
|---|---|---|---|
| `floorY` ⟲ | 0 | — | studs |
| `barHeight` ⟲ | 10 | 6–20 | studs |
| `autoResetDelay` | 1.0 | 0–5 | s |

## 13. Debug instrumentation (what the overlay shows)

- **Performance:** FPS, frame ms, sim steps this frame, sim cost ms, time scale, gravity.
- **State:** current state, `φ` / `φ̇`, shape angles (current vs target), energy and swing height %, flips and twists since release.
- **Catch timeline:** a strip covering the last ~0.5 s, showing the Grab press, the attempt window, the closest approach, the catch or miss, and any cooldown.
- **Last catch:** distance, quality, early/late ms, rollback steps, transfer ratio, impact.
- **Session counters:** regrabs, attempts, misses, ignored presses.
- **Optional drawings:** catch-range sphere on the hands, grippable span, and the predicted hand path if you released now (a tuning aid, not a player feature).
