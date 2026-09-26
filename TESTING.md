# Movement Quality Testing (v2)

How we decide whether the movement is actually good, rather than "seems fine to me".

There are five layers, from cheapest to most important. The **prototype exit gate** is in §7.
- v2 adds **Layer R: comparison against the reference clips** ([REFERENCE_ANALYSIS.md](REFERENCE_ANALYSIS.md)).
- v2 adapts the automated tests to the planar 2D solver.

## 1. What "good" means here

| Quality | Operational definition |
|---|---|
| Responsive | A press changes the pose on screen within the same frame. No added input latency vs the Roblox baseline on the same phone. |
| Smooth | No hitches, pops or jitter at any frame rate or time scale, *especially* through release and catch |
| Continuous | Rotation direction and speed flow through release and catch (reference §3.1) |
| Alive | Limbs hold poses but visibly give under load and settle, without wobbling uncontrollably |
| In control | Players can say *why* something happened and repeat it on purpose |
| Fair catches | Misses feel like the player's fault. A catch never happens without a press. The hands are visibly on the grip when it happens. |
| Satisfying | Regrabs are rated rewarding; players chain them |
| Consistent | Same inputs give the same result on a 30 fps phone and a 240 Hz PC |

## P1.1 status — what exists and how to run it

**Four test layers are implemented.** Run all of them before every push:

| Layer | Command | What it proves |
|---|---|---|
| 1. Headless unit/integration tests | `lune run tests/run.luau` (`--quick` skips slow tests; a name filter is optional) | Physics math: solver, contacts, joints, rig, driver, scenarios |
| 2. Built-place self-test | `rojo build -o build/BarGym.rbxl && lune run tools/place_selftest.luau` | The shipped `.rbxl` compiles, and its specs pass through Roblox-style instance `require` (not the Lune path) |
| 3. Headless client harness | `lune run tools/client_harness.luau` | The shipped client runs with engine shims: 5,000+ frames across all scenes and every debug control; checks rendered part positions, overlay effects, live tuning and clamping. Instances and properties are checked against Roblox's API reflection. |
| Static analysis | `rojo sourcemap default.project.json -o sourcemap.json --include-non-scripts` then `luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions=@roblox=<globalTypes.d.luau> src` | Strict Luau type-check of all code against the Roblox API definitions: **0 errors** at P1.1 |
| 4. In-Studio self-test | Press Play in Studio (server runs the quick suite automatically) | The same specs run inside the real Roblox engine; results go to Output and to attributes on `ReplicatedStorage.GymTests` (see STUDIO_VALIDATION.md) |

Layers 1–3 and static analysis run in the cloud environment. The headless runner first mirrors `src/shared` into `build/lune/`, rewriting only `require(script.Parent.X)` into file requires (`tools/lune_mirror.luau`), so the same code runs in both environments. **Layer 4 and everything visual or on-device need Studio** and are listed as unvalidated until run (STUDIO_VALIDATION.md).

**P1.1 automated tests (40), mapped to the plan:**

| Plan id | Implemented as (spec :: test) | P1.1 result |
|---|---|---|
| gravity | Solver :: gravity matches integrator / parabola | exact to 1e-9; parabola error 0.036 studs @ 2 s (integrator bound) |
| A1 | Sim :: stability soak (16 runs × 60 s, random poses and violent shoves, moon × 4 solver rates) | no invalid states; default settings: joint ≤ 0.024, limits ≤ 5.5°, penetration ≤ 0.08 |
| A2 | Solver :: pendulum energy 60 s; Sim :: Hang energy never increases | drift ≤ 0.25%; max gain 0.026% (noise), losses only |
| A3 | Rig :: centre of mass on ballistic path; Rig :: tuck conserves angular momentum | ≤ 1e-12 studs; L drift 0.003% |
| A5 (early) | Rig :: tuck spins faster | ratio 1.67 (reference ≈ 1.6) |
| A6 | Sim :: frame-rate independence (30/60/144/240 fps + jitter) | bit-identical state at step 600 |
| A7 | Sim :: slow motion identical steps, 4× real time | identical; ratio 4.00 |
| A8 | Sim :: determinism | bit-identical |
| A17 | Sim :: joints hold at giant-swing speed; Solver :: pin at 30 rad/s | joint 0.009, grip 0.007; pin 0.003 |
| A18 | Contacts :: circle rests; capsule lies flat (2-point manifold) | rest speed 0; penetration 0.001 |
| A19 | Solver :: motor max torque limits strength | strong 2.7° droop, weak gives way (108°) |
| A20 (early) | Solver :: kinematic body carries pin; Sim :: Wheel grip through a revolution | pin 0.0002; grip 0.004 |
| — | Contacts :: no tunneling at 300 studs/s; friction μg; restitution e²; corner; slope; collision routine | all pass |
| — | Rig :: builds straight; motors reach and settle every pose; limp limits; moon torque scaling | settle 1.6–2.7 s |
| — | Sim :: reset exactness; step cap / pause / NaN dt; invalid-state recovery; tuning clamps; 4 scenario runs; Drop lands and rests | all pass |
| A16 | Sim :: throughput | ~18 µs/step (Hang), ~28 µs/step (Tumble) in Lune |

A4 (pumping), A9–A15 (catch system) and R1–R8 (reference comparison) need the input and catch systems (P1.2–P1.4).

## 2. Layer A — automated core tests (Lune, headless)

The core is pure Luau and runs outside Roblox on every change. These tests become CI later.

**Solver integrity**

| # | Test | Pass criteria |
|---|---|---|
| A1 | **Stability soak:** 10 simulated minutes of random inputs × timeScale {1, 0.25} × gravity {1, moon} × simHz {120, 240, 480}, with floor contact | No NaN or infinity; speeds within caps; joint angles within limits (+2° tolerance) |
| A2 | **Energy (hanging):** no damping, motors holding a fixed shape, released from 90° | Energy drift ≤ 1% over 60 s |
| A3 | **Flight conservation:** no twist input, no contacts | Angular momentum drift ≤ 0.1% per second; center of mass on the ballistic parabola within 0.01 studs over 2 s |
| A17 | **Joint integrity:** a giant swing at `maxSwingSpeed` | Joint separation ≤ 0.02 studs; grip separation ≤ 0.01 studs |
| A18 | **Resting contact:** body dropped onto the floor | Comes to rest with no jitter (all speeds < 0.05 after 1.5 s) |
| A19 | **Compliance:** hang in Tuck at the bottom of a max-speed swing | Knee/hip deflection from target within the configured band (neither rigid nor collapsing) |

**Movement mechanics**

| # | Test | Pass criteria |
|---|---|---|
| A4 | **Pumping is skill:** a phase-correct scripted pumper vs a mistimed one | Correct timing reaches a giant (≥ 360° around the grip) in 3–8 swings with default tuning. Mistimed stays below horizontal after 20 swings. |
| A5 | **Tuck spins faster:** same release, open vs tight tuck | Spin-rate ratio ≥ 1.5 (reference ≈ 1.6) |
| A6 | **Frame-rate independence:** one scripted input timeline at 30/60/120/144/240 fps | Same state transitions and catch outcomes; bit-identical when input edges fall on the same steps |
| A7 | **Time-scale consistency:** timeScale 1 vs 0.25, including a kinematic wheel | Identical trajectories in simulation time |
| A8 | **Determinism:** the same run twice | Bit-identical |

**Catch system**

| # | Test | Pass criteria |
|---|---|---|
| A9 | **Catch window curve:** scripted pass by the bar at a known closest approach; sweep the press offset −250…+150 ms step by step | Success exactly inside [−early, +late] (±1 step) when the path comes within `catchRange`; always fails beyond `catchRange` |
| A10 | **No automatic catching:** Grab held through the flight with no new press | Never catches (`grabMode = press`) |
| A11 | **Anti-mash:** a press every 50 ms | Cooldown after the first miss; success below a single well-timed press |
| A12 | **Momentum continuity at catch:** transfer 1.0 | Angular momentum about the grip after the catch impulse within 1% of before; rotation direction unchanged; scales with the transfer factor |
| A13 | **Reach and twist gates** | Rejected just beyond `catchReachAngle` / `catchTwistTolerance`, accepted just inside |
| A14 | **Swept detection:** hands crossing the target at 100 studs/s | Caught (no tunneling) |
| A15 | **Rollback equivalence:** late press within grace | Same state as catching at the valid step and simulating forward |
| A20 | **Moving target:** catch on a kinematic rotating spoke | Uses relative velocity; the grip stays attached through a full revolution |

**Performance**

| # | Test | Pass criteria |
|---|---|---|
| A16 | **Throughput (informational)** | Steps per second in Lune, recorded per commit |

**Visual sanity check:** the runner can dump traces (CSV of body poses per step). A script renders them to PNG strips or GIFs, so motion can be inspected, and compared with reference frames, before anyone opens Studio.

## 3. Layer R — reference comparison (new)

Goal: our motion should **feel like** the reference (REFERENCE_ANALYSIS §3–4), measured the same way we measured the reference.

**R-numbers.** These are measured from our debug instant replay or screen recordings at 30 fps, using the same frame-counting method. The tolerance is wide on purpose, because they're feel targets, not physics constants.

| # | Quantity | Reference | Target range |
|---|---|---|---|
| R1 | Open/pike spin rate | ≈ 1.15 rev/s | 0.9–1.4 rev/s |
| R2 | Tight tuck spin rate | ≈ 1.85 rev/s | 1.5–2.3 rev/s |
| R3 | Tuck/open ratio | ≈ 1.6 | 1.4–1.9 |
| R4 | Typical same-bar release → regrab flight | pole-to-pole ≈ 0.9 s | 0.7–1.1 s |
| R5 | Catch → next release (one swing through the bottom) | ≈ 0.9–1.0 s | 0.8–1.2 s |
| R6 | Momentum retained at catch (swing height reached after catch ÷ height at catch) | ≈ full | ≥ 0.9 |
| R7 | Hand-to-grip visual offset at the catch frame | ≲ 1 hand length | ≤ 0.3 studs after blend start; no visible snap |
| R8 | Chain cadence for an experienced tester | 1 per 1–1.5 s | ≤ 1.6 s median |

**Qualitative side-by-side:**
- Put our recordings next to the reference clips, with motion only (no UI).
- Check each:
  - continuity at release and catch
  - hands leading into the catch
  - limb liveliness
  - camera calmness
  - slow-mo and moon smoothness
- Reviewed by you and 2–3 testers. Pass = "feels as good or better" on each item.

**Reference-style drills** (built from generic mechanics, not copied levels):
- pump to a giant
- release on the upswing from a pike → tuck flip → same-bar regrab
- half-twist regrab

## 4. Layer B — in-game instrumentation

Part of the prototype (PHYSICS_DESIGN §13):
- **Debug overlay:**
  - timing, derived state, joint saturation
  - spin rate, catch timeline, last-catch report
  - the active **preset name**, visible on every recording
- **Session log:** every Let Go, Grab press, attempt, catch, miss and ignored press, with step, distance, reach and twist angles, timing offset, quality, rollback, fps and device. **Export** produces copyable text.
- **Debug instant replay** (proposed): scrub the last 10 s at any speed. It's used for R-measurements and catch inspection.
- **Analysis:**
  - press-timing histograms around the closest approach
  - success rate per distance band
  - miss reasons (too far / reach / twist / cooldown)
  - early vs late tendencies per device

## 5. Layer C — device performance and latency

**Device matrix** (to be confirmed with what you own):

| Class | Example | Role |
|---|---|---|
| Low-end Android | 3–4 GB RAM, 2019–2020 chipset | Performance and latency reference; ≥ 30 fps |
| Mid Android | recent mid-range | |
| iPhone (older) | iPhone 11/12 class | |
| iPhone (recent) | 120 Hz ProMotion | Interpolation check |
| Tablet | iPad | Layout scaling |
| PC | 60 Hz and 144+ Hz, keyboard + gamepad | |

**Performance:**
- MicroProfiler captures with `debug.profilebegin` markers.
- Budgets: solver ≤ 1.0 ms/frame, rig ≤ 0.2 ms/frame on the low-end reference.
- 60 fps on mid phones; never below 30 fps on low-end.

**Added input latency:**
- Film the phone with another phone's 240 fps slow-mo camera.
- Count frames from touch contact to the first pose change. Do 10 trials per device.
- Compare against the Roblox baseline on the same device (a default character jump in an empty baseplate).
- **Target: 0 frames added (at most 1).**

## 6. Layer D — playtests (the part that decides)

**Participants per round:** 5–8, on their own phones where possible:
- mostly target-age Roblox mobile players (minors only with a parent or guardian's consent)
- 1–2 people who know the original game
- 1 non-gamer

**Session (≈20 min):**
1. **Cold start (2 min):** no instructions. Observe.
2. **Briefing (1 min):** the actions, and that you must press Grab.
3. **Timed tasks:**
   - (a) giant swing
   - (b) release + regrab once
   - (c) regrab with a tuck flip
   - (d) regrab with a half twist
   - (e) 5 regrabs in a row
4. **Free play (up to 5 min):** "stop whenever you like". Record continuation.
5. **Questionnaire (1–7):**
   - Responsive.
   - In control.
   - Regrabs satisfying.
   - Misses were my fault.
   - Never caught without me pressing.
   - Motion felt smooth when catching and letting go.
   - The body felt alive, not robotic.
   - Wanted to keep playing.
   - Would record a clip.
   - Plus open questions: *What felt wrong?* and *One thing to change?*

**Collected per tester:** session-log export, screen recording, device, fps.

**Rules:** don't tell testers what changed. A/B presets are blind and alternate in order between testers.

## 7. Prototype exit gate (go / no-go)

All must hold on the device matrix:

| Metric | Target |
|---|---|
| Automated tests A1–A20 | All pass |
| Reference numbers R1–R8 | All inside target ranges |
| Reference side-by-side | "As good or better" on every qualitative item |
| Added input latency vs baseline | ≤ 1 frame, all devices |
| Frame rate / solver cost | ≥ 60 fps mid, ≥ 30 fps low-end; solver ≤ 1.0 ms |
| Median time to first giant (new players) | ≤ 3 min |
| Median time to first regrab (new players) | ≤ 6 min |
| Regrab success on a standard release, after 15 min | ≥ 60% new, ≥ 85% experienced |
| "Misses were my fault" | ≥ 5 / 7 |
| Unintended catches reported | **0** |
| Responsive / In control / Satisfying / Smooth / Alive | ≥ 5.5 / 7 each |
| Voluntary free-play continuation | ≥ 50% play on ≥ 5 min |

**If the gate isn't met after 3 tuning rounds:**
- Classify the gap as **tuning**, **control scheme** or **model**.
- Model gaps: first try the planned options (elbows, secondary render motion, `swingAssist`). If still failing, run the native-physics spike (TECHNICAL_DESIGN §4 fallback).

## 8. Tuning workflow

- Each build ships a **named preset** in `tuning/presets/` plus a one-line changelog entry.
- **Change one parameter group per round.** Keep the previous preset one tap away for A/B.
- Tester feedback references the preset name shown in the overlay.
- Winning values are committed back to `Tuning.luau` defaults, so the repository stays the source of truth.
