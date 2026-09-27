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

A4 (pumping), A9–A15 (catch system) and R1–R8 (reference comparison) need the input and catch systems (P1.2–P1.3). P1.2 results are below.

## P1.2 status — movement control

**All layers pass** (2026-09-27, cloud environment, after playtest feedback round 1; see [PLAYTEST_P1_2.md](PLAYTEST_P1_2.md)):

| Layer | Result |
|---|---|
| 1. Headless tests (`lune run tests/run.luau`) | **68 / 68** (the 40 P1.1 tests, the auto-added `Stand` scene check, 22 movement tests, 5 look tests) |
| 2. Built-place self-test (`--full`) | **68 / 68** through Roblox-style instance `require` (quick mode: 64 passed, 4 slow ones skipped) |
| 3. Client harness | **76 / 76** checks, including the slow-motion indicator (hidden at 1×, shows 0.5× / 0.25× / 0.1×): 5 scenes, every debug control including the blind A/B (hidden labels, switch by key and button, Shift+B reveal with time played per variant and switch count), and gameplay input: keyboard holds and presses, gamepad analog trigger and buttons, touch layout (two thumbs at once, touch-down Let Go), crouch-and-release jump that lands, twist through a half-twist snap with continuous part motion |
| Static analysis (luau-lsp, strict) | **0 errors** |
| Formatting (StyLua) | clean |
| 4. In-Studio self-test and look/feel | **pending** (STUDIO_VALIDATION.md §P1.2) |

(selene still can't download Roblox's API dump offline; luau-lsp covers typing.)

**P1.2 movement tests (`Movement.spec`, 22), mapped to what was asked.** The results are as of feedback round 1; the numbers first reported for P1.2 are in the notes below the table.

| Requirement | Test | Result |
|---|---|---|
| Arch changes the body the intended way | Arch, Tuck and Pike bend the body the intended way (air, bar, after a half twist) | Air: hip 8° → −29° (arch), 126° (tuck), 109° (pike); shoulder 7° → −22°. Bar: hip 6° → −28° / 127° / 111°; shoulder 4° → −22°. **Air tuck brings the arms in** (shoulder 112°, elbow 61°); **bar tuck keeps them overhead** (26°). Identical after a mirror (facing flipped). |
| Tuck rotates faster than open | Tuck spins faster; momentum conserved | 1.11 → 2.50 rev/s (**×2.24**; must be 1.4–3), **×1.44 0.1 s after pressing** (must be ≥ 1.3; P1.2 as first tested ×1.17, P1.1 ×1.48); angular momentum drift 0.008%; centre-of-mass velocity changes only by gravity (1e-6) |
| Twist changes orientation without breaking the 2D plane | Rig.mirror conserves…; Twist turns the body…; twist modes | Mirror: COM, momentum, angular momentum, kinetic energy exact to 1e-9; joints attached; anatomical angles unchanged. Twisting: ≥ 1 half twist in 0.5 s, **rendered points jump ≤ 1.3e-15 studs across the snap**, angular momentum drift 0.0007%, state finite and planar every step; releases hold the angle; both buttons hold; momentum mode taps start, reverse, stop; no twist on the bar |
| Let Go preserves momentum | Let Go keeps momentum exactly… | Release step at 5 release times: Δvx = 0 and Δvy = −g·h (1e-9); relative ΔL ≤ 4.7e-6 (bound 1e-5, see below); opt-in shaping scales exactly as specified; Let Go in the air and Grab (pre-P1.3) change nothing (bit-identical) |
| Jumping consistent across frame rates | jumping is identical at any frame rate… | Input keyed to simulation time: **bit-identical** at 30/60/144/240 fps and jittery frames. Input sampled per frame (as on a device, the release quantized to a frame): apex within 0.011 studs of 240 fps (≤ 0.7%) |
| Grounded/airborne transitions stable | ground/air transitions…; jump… | Standing 10 s: no events. 2-stud drop: exactly one `landing`, ends standing. Holding a crouch 3 s: no events. Jumps: exactly `push, takeoff, landing` |
| Movement inputs frame-rate independent | presses are never lost or doubled… | Let Go pressed on a zero-step frame in 0.25× slow motion fires at the next step, exactly once; two presses in one frame = one release; a press during pause fires after unpausing; a press before Reset never fires after it; NaN/∞ input levels sanitized |
| No NaN / invalid states | player-input soak (slow): random inputs and resets, 5 scenes × Earth/moon × 40 s | no invalid or out-of-bounds events; worst joint gap 0.021; worst limit overshoot 1.8°; floor penetration ≤ 0.19 (Wheel scene, a hard landing) |
| No new tunneling / floor penetration | jump; transitions; both soaks | lowest body surface ≥ −0.1 studs through jumps and drops; soak penetration ≤ 0.19 (P1.1 threshold 0.3) |
| P1.1 tests still pass | all 40 | pass (see below for what moved) |
| Standing | standing: holds still 10 s, recovers from shoves, stands on muscle alone | COM held over the feet to 1.5e-6 studs; ±3 studs/s shoves recover; `balanceAssist` = 0 still stands 10 s undisturbed |
| Jumping | jump: releasing Tuck from a crouch… | rise 1.52 / 1.57 studs (0.3 / 0.8 s crouch), takeoff spin ≤ 0.04 rev/s, drift 0.9 studs/s, lands, back to standing height; a 0.08 s tap does not jump |
| Back-flip takeoff (round 2) | back-flip takeoff: Arch through the push… | Arch rise 1.78 vs plain 1.69 (must be ≥ 85%). Feet only (`jumpSpinAssist` 0): 0.38 rev/s backward (≥ 0.3), 0.43 rev with a tuck. Default: 1.19 rev with a tuck held to landing (≥ 0.75), full height. A pressed 0.2 s after releasing S: 0.90 rev (≥ 0.7); A pressed 0.5 s after (mid-flight): 0.09 rev (< 0.2, no mid-air rotation). Tuck-timing grid: 8/15 back flips land on the feet (≥ 1; pure physics: 0). Plain jumps: takeoff spin < 0.2 rev/s, land standing |
| Plain-jump landings holding Arch (round 2 regression guard) | plain jumps land standing while holding Arch | pure physics, Arch from takeoff: Earth crouch 0.35 / 0.5 / 0.7 s and moon 0.86 / 1.72 s all stand (round 1 fell 3/3 on Earth). Defaults, Arch from 0.2 or 0.35 s after takeoff (after the late window): all stand, no rotation |
| Pumping (A4) | pumping: in phase builds, out of phase damps | peak swing angle after 15 s from 60°: no input 50°, **in phase 145°**, out of phase 8° |
| Pumping (A4): no drain, from nothing to a giant | pumping: held shapes don't drain the swing; from a still hang… | loss per cycle at 90°: relaxed / Tuck / Pike 2.3° / 4.1° / 5.6° (extra over relaxed must be ≤ 4° / ≤ 5°; was 3.7° / 6.8° / 10.7°). `hangStartAngle` 0 stays within 0.8°. From a still hang: 90° at 11.9 s (≤ 15), **over the top at 15.2 s** (≤ 20; P1.2 as first tested stalled at ≈ 107°) |
| Swing limits | swing limits… | the energy cap (straight body passing the bottom at `maxSwingSpeed`) holds a 6 rad/s cap to **1.08× its energy**, with `swingAssist` 2 and with pumping alone (bound 1.1); grip friction 0.2 → 7° vs 58° after 8 s |
| Moon | moon gravity… | g = 5.775 exactly; fixed-launch apex ×6.07 (expected 6.06); muscle jump (default) 2.00 studs / 1.47 s vs Earth 1.73 / 0.53; fixed strength 7.04 / 2.93 |
| **Slow motion kept** (liked feature) | slow motion keeps player movement identical… | a scripted bar routine (pump, Let Go, tuck, twist) and a ground routine (crouch, Arch jump), Earth and moon, through `Sim.advance` at 60 fps: **bit-identical** at timeScale 0.5 / 0.25 / 0.1; real time 2 / 4 / 10× (±2%). Passes on the playtested build too |
| **Moon kept** (liked feature) | moon mode keeps its feel… | half swing 1.14 → 2.80 s (×2.46 ± 0.08 required); height after 8 half swings 52.7° vs 53.1° (±3°); jump height 1.16× Earth (1.14 ± 0.12) and airtime 2.78× (2.75 ± 0.3), lands standing; defaults 0.165 / strength follows gravity; moon, slow motion and `motorHertz` survive Reset and scene changes. Playtested build: 2.81 s, 52.9°, 1.15×, 2.75× |
| Smoothness | smoothing: targets move continuously | largest per-step target change 10.0° (default) vs 36.4° without smoothing |
| Determinism | determinism: same inputs → bit-identical | pass |

**Look tests (`Look.spec`, P1.2 round 3: the drawn body's proportions):**

| Test | Result |
|---|---|
| The drawn body stays inside the physics collision shapes (standing, crouch, tuck, arch, hang, pike on the bar) | farthest outside: 0.014 studs (a foot's square corner at the rounded capsule end); bound 0.04 |
| Feet: the drawn sole is the physics sole | foot half-thickness = collision foot radius exactly; standing, lowest drawn point = lowest collision point (−0.033 / −0.033) |
| No self-intersection in depth | gaps: head–arm 0.15, torso–arm 0.04, leg–leg 0.15, arm–leg 0.10 studs, in any pose (arms and legs sit in their own depth planes); hips within the torso block's width |
| Slimmer than the collision shapes; building the look doesn't touch the simulation | the torso is one block, thinner in the plane than the collision torso; every drawn limb thinner than its collision shape; physics radii unchanged; checksum identical with and without building the look |
| Every drawn shape has a colour in the palette, written as a hex code (look pass 2) | every `Look.PALETTE` entry is `#RRGGBB`; every shape's colour role is in the palette |

**Movement is unchanged by the look pass.**
- A physics fingerprint (standing, jump, tuck, arch/backflip, twist, bar swing, release, landing, moon jump and moon swing) is bit-identical before and after.
- `tools/flip_bench.luau` output is identical.
- The client harness draws 26 body parts per scene (was 34); frame cost is 0.35 ms (was 0.48).
- Look pass 2 (one torso block, brown wood palette): fingerprint and flip bench again identical; 25 body parts per scene; frame cost 0.39 ms.

**Changed in playtest feedback round 1** (PLAYTEST_P1_2.md; all layers above re-run):
- New tests: *back-flip takeoff* and *pumping: held shapes don't drain the swing; from a still hang pumping reaches a giant*.
- Extended tests: shapes (air-tuck arms, bar-tuck arms); tuck (the 0.1 s gain, and a physical ceiling of 3×).
- **Swing limits: the cap is now checked in energy**, which is what it bounds. It used to be checked as a rate: the old cap compared the swing's energy with the current shape, which braked every tuck near the cap. Measured against the straight body, a tucked body with the capped energy correctly spins faster than the cap rate (6.7 rad/s at a 6 rad/s cap). The bound, 1.1× the cap's energy, is ≈ 1.05× in speed: tighter than before.
- **Let Go, angular momentum: the bound changed from 1e-6 to 1e-5, and now covers 5 release times instead of 1.**
  - Investigation: an ordinary air step changes angular momentum by ~1e-8 (solver joint error). The release step changes it by ~1e-6, because the arm joints suddenly stop carrying the body.
  - The playtested build already reached 2.4e-6 at a release at 1.1 s; the single 0.9 s case happened to pass.
  - With the firmer bar elbows the worst of the 5 cases is 4.7e-6. Any release shaping shows at the 1e-1 level, so 1e-5 still proves "no shaping".
- `tools/flip_bench.luau` (new) reproduces the playtest numbers: standing jumps, bar-release flips, held-shape drain, pumping from a still hang.

**What changed in the P1.1 results (all still pass, same thresholds):**
- **Stability soak (A1).** The first P1.2 run failed: *moon Tumble, default settings: limit violation 12.1° > 8°*. Investigation: the rig refactor changed initial positions by ~1e-16 (cos(π/2) is not exactly 0), and this chaotic 60 s run then hit a light foot jammed on a block corner under a violent kick. Re-running the P1.1 code over 20–40 seeds showed the 8° bound was exceeded by P1.1 too (up to 14.5°) at every solver setting (substeps 4/6/8, relax 1/2, contact stiffness), so the 8° pass was a lucky single sample. The cause is conditioning: a 0.2-mass foot or 0.45-mass forearm carrying the body's load. Giving the light segments extra rotational inertia (`limbInertiaBoost`) cut the worst case across 160 runs to 2.7° with no CPU cost, so the threshold did not need to change. Now: default settings joint ≤ 0.016, limits ≤ 1.5°, penetration ≤ 0.05.
- Pose settle times (zero g): 1.25–1.74 s → **0.75–1.12 s** (more damping).
- Hang energy loss after 20 s: 17% → 9.4% (less wobble to dissipate); energy still never increases.
- Tuck ratio (Rig test, zero g): 1.67 → 1.68.
- Throughput unchanged: ~19 µs/step (Hang), ~29 µs/step (Tumble) in Lune.

**Smoothness benchmark** (`lune run tools/smooth_bench.luau`; zero gravity, hip and knee through Tuck → Neutral → Arch → Neutral, plus the tuck gain in flight and torso jerk while pumping on the bar):

| Settings | Response (63%) | Overshoot | Wobble 0.4–1.5 s after input | Joint jerk (RMS, 60 Hz) | Tuck gain | Swing jerk |
|---|---|---|---|---|---|---|
| P1.1 exactly | 0.17 s | 22.5° | 1.4° | 213,913 °/s³ | 1.47× | 3,200 |
| **P1.2 defaults** (limb inertia, input smoothing 8/6 Hz, motor ζ 1.25, bar shoulders 18 Hz) | 0.19 s | **7.0°** | **0.9°** | **115,243** (−46%) | 1.52× | **2,022** (−37%) |
| P1.2, motor ζ 1.5 | 0.19 s | 4.1° | 0.6° | 54,789 | 1.51× | 1,482 |
| P1.2, motor 8 Hz | 0.18 s | 15.0° | 0.4° | 153,639 | **1.62×** | 3,007 |
| P1.2, motor 8 Hz ζ 1.5 | 0.18 s | 8.3° | 0.3° | 136,458 | 1.62× | 1,712 |
| P1.2 without input smoothing | 0.18 s | 7.0° | 0.8° | 148,521 | 1.49× | 3,301 |

Reading: damping removes the overshoot and lingering wobble at no response cost; input smoothing removes the target snaps (a third of the jerk while pumping); stiffer motors (8 Hz) are what bring the tuck to the reference's ≈1.6×. Motor stiffness is left at the playtested 6 Hz; 8 Hz is a candidate for the P1.2 playtest.

After feedback round 1 (the benchmark's air test now uses the arms-in air tuck):

| Settings | Response | Overshoot | Wobble | Joint jerk | Tuck gain | Swing jerk |
|---|---|---|---|---|---|---|
| P1.2 as first playtested (commit 15fdbb0) | 0.19 s | 7.0° | 0.9° | 115,243 | 1.52× | 2,022 |
| **Defaults after round 1** | 0.20 s | 23.0° | 1.6° | 195,260 | **2.13×** | 4,082 |
| … without the air squeeze (`tuckHertz` 6) | 0.20 s | 13.0° | 1.3° | 154,653 | 1.76× | 4,082 |
| … bar hips as in the air (`gripHipHertz` 6) | 0.20 s | 23.0° | 1.6° | 195,260 | 2.13× | 1,239 |
| … motor ζ 1.5 | 0.20 s | 21.2° | 1.0° | 133,874 | 2.12× | 2,699 |
| … motor 8 Hz | 0.20 s | 36.8° | 1.9° | 209,639 | 2.12× | 3,121 |
| P1.1 motor settings (current poses) | 0.19 s | 26.0° | 2.7° | 241,856 | 1.63× | 3,200 |

Reading: the tester asked for a quicker, more compact tuck and a swing that doesn't fight them. Both cost some smoothness:
- The air squeeze adds overshoot.
- The firmer bar hips make pumping livelier (torso jerk ×2). Softening them back brings the swing drain back.

Both are still within the P1.1 motor settings' range. `motorDampingRatio` 1.5 is the live knob for a calmer feel.

**Known issues and tuning items found by the P1.2 tests** (status after feedback round 1 in bold):
1. **Pumping to a giant (A4) is not met with pure physics.** A simple scripted pumper (Tuck while rising, Arch while falling) plateaus at 100–140° and never goes over the top in 40 s. `swingAssist` 0.5 goes over in ~3 swings, motor 8 Hz in ~5. **Resolved:** the plateau came from soft bar elbows and hips draining the swing; pumping now reaches a giant from a still hang in ~12–15 s with pure physics (tested).
2. **Tuck gain ×1.52 (air, fast spin)** vs the reference's ≈1.6: under a fast spin the springy hips don't reach the full tuck (~95–110° of 125°). Motor 8 Hz gives ×1.62. **Resolved:** arms-in air tuck plus squeeze: ×2.2, and ×1.44 after 0.1 s.
3. **Balance recovery relies on `balanceAssist`** for anything but a still stand (no stepping). With the assist: ±4 studs/s shoves recover; without it, ≥ 1 stud/s shoves topple.
4. **Jumps drift forward ~1.2 studs/s** (the push isn't perfectly vertical); landings still stand thanks to the landing reflex.
5. **Moon standing** tolerates ±2 studs/s shoves (±5 in Earth terms); ±3 falls. Scene `Drop` on the moon falls (its fixed initial spin tips the body 47° over the long fall); on Earth it lands and stands.
6. **Arch jump spin** (`jumpArchSpin` 0.8 rev/s target) only reaches ~0.15 rev/s: the centre of pressure saturates at the toe and the arm swing fights it. Back flips from standing need tuning (or an input design decision) before they are a feature. **Partly resolved:** the Arch takeoff keeps its height and spins at 0.38 rev/s (≈ 0.43 rev with a tuck). A full standing back tuck needs the optional `jumpSpinAssist` (1 → 0.87 rev, lands) or a real lean-back takeoff (Phase 2). The decision is open (PLAYTEST_P1_2.md).
7. **Feedback round 1 trade-off:** the tuck squeeze and firmer bar hips cost some smoothness (table above). To be judged in the next playtest.
8. **Round 2: landing a back flip is narrow, and the landing reflex is why.** It works arriving about 30–40° under-rotated with the tuck held. An upright touchdown still spinning (1–1.9 rev/s) with half-folded legs falls back. The reflex places the feet for forward speed only, not for spin or a just-finished shape change.
   - In the playtested build too, on Earth: a short mid-air tuck then open puts the feet 0.6–1.5 studs ahead of the centre of mass (the body falls back); a tuck held to touchdown rolls back; Arch pressed about 0.25 s into the flight falls.
   - Proposed next: a spin-aware landing reflex.
9. **Round 2: air-tuck arms ("T-rex").** Under a typical spin the shoulder and elbow springs settle 20–25° short of the target, so the hands ride up by the chest.
   - A target of 125° / 80° fixes the look, but the more compact tuck spins faster and standing-backflip landings drop from 21–23 to 6–18 of 81.
   - Deferred until the landing work, or until the hands actually grip the shins.

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
