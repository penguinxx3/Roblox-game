# Studio Validation — P1.2 Movement Control (+ playtest feedback round 1)

What must be checked **inside Roblox Studio**. This couldn't be done from the cloud build environment, which has no connection to Studio.

P1.1 (physics foundation) was validated in Studio by the owner. P1.2 was playtested once; the findings and the changes made in response are in [PLAYTEST_P1_2.md](PLAYTEST_P1_2.md). Everything headless is green (TESTING.md, "P1.2 status"). This list covers what only the real engine, real input devices and human eyes can confirm.

Tick items and note anything odd, ideally with a short screen recording.

## 0. Get the place into Studio

Pick one:
- **A. Open the built file:** open `BarGym.rbxl` (build it with `rojo build -o build/BarGym.rbxl`) in Studio.
- **B. Live sync:** run `rojo serve` in the repo and connect with the Rojo Studio plugin. Code edits then sync while you test.

## 1. Automatic checks on Play (≈10 s)

Press **Play** (F5). In the **Output** window you should see:

| Expect | Meaning |
|---|---|
| `[GymSelfTest] ... 59 passed, 0 failed, 4 skipped` | The physics and movement specs pass **inside the Roblox engine** (quick mode) |
| `[GymClient] P1.2 movement running. Play: A/← Arch, ...` | The client started in player control |
| `[GymClient] runtime check OK: scene=Hang steps=... avgSim=...ms ...` | The simulation is stepping and rendering after 3 s |
| No red errors, no `warn` lines from `[GymClient]` | |

Also check `ReplicatedStorage.GymTests` in Explorer (server view): `SelfTestStatus = "passed"`, `SelfTestFailed = 0`.

**Full suite** (includes the slow soaks, ~30–60 s). From the **command bar**, in Edit mode or on the server during Play:

```lua
print(require(game.ReplicatedStorage.GymTests.StudioRun)(false).failed)   -- expect 0 (63 passed)
```

## 2. Controls

**Gameplay (P1.2)** — the same actions on every device:

| Action | Keyboard | Gamepad | Touch (minimal layout) |
|---|---|---|---|
| Arch (hold) | A or ← | LT (analog) | ARCH (left) |
| Tuck (hold) — on the ground: crouch, release to jump | S or ↓ | RT (analog) | TUCK (left) |
| Arch + Tuck = Pike | both | both | both thumbs |
| Let Go | W or ↑ | B | LET GO |
| Grab *(counted, no effect until P1.3)* | Space or J | A | GRAB |
| Twist left / right (hold; both = hold the angle) | Q / E | LB / RB | ◄ / ► |
| Reset | R | Y | Reset button (top right) |

**Debug:** 1–5 scene · V pose override (holds a named pose instead of your input: Neutral → Tuck → Pike → Arch → Crouch → Limp → back to your input) · T slow-mo 1 / 0.5 / 0.25 / 0.1 · G moon gravity · P pause · N single step · C contact markers · **B blind A/B switch, Shift+B reveal (§4a)** · F2 overlay. The same actions are buttons at the top right (the A/B button switches only).

**Back flip (standing):** hold S to crouch, then press A, either while still holding S or up to about 0.3 s after letting go. Let go of S to jump, press S in the air to tuck, and let go a moment before landing. The backward spin comes from the takeoff: pressing A later in the air only opens the body, since nothing in the air can start a rotation.

**Back flip (bar):** Arch on the way down, Tuck through the bottom, let go on the way up, keep tucking, open before landing.

The overlay's `move` line shows the mode (grip / air / ground / fallen), facing, twist angle and half twists, spin rate, crouch depth, swing rate and the last event; the `input` line shows what the simulation receives.

## 3. What to check (per scene)

| Scene | Do this | Expected | Report if seen |
|---|---|---|---|
| **1 Hang** | Watch 5 s with no input | Swings from 60°, slowly loses height (as in P1.1; the shoulders are a little firmer on the bar) | Jitter; a swing that gains height without input |
| | Hold **A** (Arch), then **S** (Tuck), then both (Pike) | The body opens (hips and shoulders back), folds into a tuck, and pikes (straight legs), each smoothly within ~0.2 s. On the bar the tuck keeps the arms overhead, holding the bar | Snapping, visible wobble after the shape settles, joints separating |
| | **Pump:** Tuck as the body swings up, Arch as it swings down, for 10–15 s | The swing grows past horizontal and, kept up, goes over the top (a giant swing). Holding a shape costs a little swing, not a lot. The opposite timing kills the swing | No growth with correct timing; growth with wrong timing; **active swinging that feels like it slows you down** (note when) |
| | Set `hangStartAngle` = 0 (§4), press R, then pump | Starts from a still hang. The first swings grow slowly, then faster; ~10 s to horizontal with a steady rhythm | Can't get it started at all |
| | Pump 3–5 swings, press **W** on the front upswing (30–60° past the bottom), then hold **S** | A full flip or more before landing (≈ 1–2.5 rev) | Not enough rotation for a flip; landing always fails |
| | Press **W** at different points of the swing | Lets go instantly; the body flies along the swing with the same rotation (no pop, no slowdown) | Any jolt, speed change or delay at release |
| | After letting go, hold **S** | The arms come in (hands toward the shins) and it spins visibly faster within ~0.1–0.2 s; slower again when released | Arms flailing or swinging far past the shins; a slow, loose tuck |
| | After letting go, hold **E** (or **Q**) | The body turns about its long axis, chest toward then away from the camera, **with no jump or flicker when passing side-on** (the half-twist snap) | Any flicker, jump or limb swap you can see |
| **2 Drop** | Watch | Falls ~4 studs, **lands on its feet, bends to absorb and stands up** | Falling over; sinking into the floor; a bounce back into the air |
| **3 Tumble** | Watch, then Reset and hold **S** | Thrown up spinning; tucking spins faster; lands (on the feet if roughly upright, otherwise physically on the floor) | Passing through blocks or the ramp; exploding limbs |
| **4 Wheel** | Watch, then press **W** | Carried around by the wheel; Let Go flings the body off along the handle's motion | Hands detaching on their own; stutter |
| **5 Stand** | Watch 10 s | Stands still, balanced over the feet | Drifting, trembling, falling |
| | Tap **S** quickly | A small dip, no jump | |
| | Hold **S** ~0.5 s, release | Crouches (controlled, feet stay down), then **jumps ~1.5 studs**, lands on the feet and stands up again | Feet leaving the floor while crouching; big forward drift; falling after landing |
| | Hold **A** | Rises into a reach (arms up) and keeps balance | |
| | Jump, then **E** in the air | Twists in the air, lands square | |
| | Back flip (§2) | As high as a plain jump, clearly spinning backward; with the tuck about a full turn, landable with practice (open a moment before touchdown; landing slightly short of upright works best) | Lower than a plain jump; no rotation when A is pressed on time |
| | Jump, then press **A** well after takeoff | Only opens the body; no rotation | Any rotation from a late A |
| | Same back flip with `jumpSpinAssist` = 0 (§4) | Pure physics: only about half a turn | |

**Slow motion (T)** — repeat a jump and a release at 0.25 and 0.1: motion stays smooth, and **every press still works**, even a quick tap (presses are counted, never dropped). The speed shows at the top of the screen (`SLOW-MO 0.5×` / `0.25×` / `0.1×`) and disappears at normal speed.

**Moon (G)** — jumps and swings are the same height as on Earth but ~2.5× slower and floatier (strength follows gravity by default). For real-moon jumps (~6× higher) set `strengthGravityScaling = 0` in `GymTuning` (§4) and compare. With `jumpSpinAssist` = 1, a standing back tuck on the moon turns about twice.

**Touch** — Studio's **Device Emulator** (Test tab → Device, pick a phone): the six touch buttons appear (ARCH / TUCK left, ◄ ► LET GO GRAB right). Check that they react on **touch-down**, that ARCH + TUCK can be held together, and that you can hold TUCK while pressing LET GO. The layout is a functional placeholder, not the final mobile UI.

**Gamepad** (if you have one): RT half-pressed gives a half tuck (overlay `tuck 0.50`); B lets go; LB/RB twist; Y resets.

## 4. Live tuning

1. During Play, switch Explorer to the **client** view.
2. Select `ReplicatedStorage.GymTuning`.
3. Edit attributes in Properties. Changes apply immediately, except the ones marked "applies on Reset" in the overlay. Worth trying for P1.2 feel:
   - `motorHertz` 6 vs 8: use the blind A/B (§4a) rather than editing it
   - `jumpArchSpin` 1.0 (back-flip takeoff spin; 0.9 = gentler, 1.1 over-rotates) and `jumpSpinAssist` 1 (0 = pure physics: no standing back flips)
   - `hangStartAngle` 60 → 0, then R (start from a still hang)
   - `tuckHertz` 10 (air tuck squeeze; 6 = as first playtested, 8 = softer), `gripHipHertz` 10 (bar hips; 6 = as first playtested)
   - `motorDampingRatio` 1.25 → 0.8 (P1.1's livelier, wobblier feel) or 1.5 (calmer)
   - `shapeFreqClose` / `shapeFreqOpen` 30 (no input smoothing, like P1.1) vs 8 / 6
   - `swingAssist` 0 → 0.5 (pumping reaches a giant swing in a few swings)
   - `twistRate` (1.5 rev/s), `twistMode` 1 (tap to spin)
   - `jumpStrength` (1.5), `balanceAssist` 0 (pure muscle balance: stands still, but a shove topples it)
   - `strengthGravityScaling` 0 with moon on
4. Out-of-range values snap back to the allowed range.

## 4a. Blind A/B: motor 6 vs 8 Hz

Metrics can't settle this; it is a feel question, so it is tested blind. **The default stays 6 until this test is done.** At session start, A and B are randomly assigned `motorHertz` 6 and 8. The overlay shows only the letter. The setting survives Reset (R), scene changes, moon and slow motion, so you can move around freely.

1. Press Play. Leave `motorHertz` alone in Properties: the A/B sets it.
2. Press **B** once (overlay: `blind A/B: now A`).
3. Play the same routine on A for ~3 minutes:
   - Hang (1): pump up, let go, tuck.
   - Stand (5): crouch-jump and land; try an Arch takeoff.
   - Tumble (3): tuck and open in the air.
   - Repeat one or two of these with **moon (G)** on, and once in **slow motion (T)**, then set them back.
4. Press **B** (now B) and play the same routine on B. Switch back and forth 2–3 more times; don't try to guess the values.
5. Write down which letter felt better and why (responsiveness, smoothness, control, flips; on Earth, on the moon, in slow motion) **before** revealing.
6. Press **Shift+B** to reveal. The overlay and Output show `[GymAB] reveal: A = motorHertz …, B = … (played A x min, B y min, n switches)`. A test with under a minute on either variant is flagged as short. Send the note and the reveal line.

Best with 2–3 people, each with a fresh Play session (a new random mapping). What `motorHertz` changes after the feedback round:
- **In the air:** Arch, Neutral and the landing reflex. The tuck squeeze is 10 Hz either way.
- **On the bar:** knees and ankles. Shoulders and elbows are 18 Hz and hips at least 10 Hz either way.

## 5. Performance (needs a real device for the real answer)

- **In Studio:** the overlay line `sim X ms (N steps) render Y ms` shows the per-frame cost. MicroProfiler (Ctrl+F6) has labels `GymSim` and `GymRender`.
- **On a phone (the real target):** publish privately, open on your lowest-end phone, and read the same overlay line. The budget is sim ≤ 1.0 ms/frame and fps ≥ 30 on low-end (headless Lune: ~0.1 ms of physics per 60 fps frame; the controller adds a little). Please send the numbers for each device, and note whether touch buttons respond instantly.

## 6. Human look and feel (questions for the next playtest)

Scores out of 10 per item, as in round 1, help compare.

Round 3 (after the Arch changes; PLAYTEST_P1_2.md, round 2):

1. **Standing back flip (§2):** can you start one reliably now? With practice, can you land it? Does the backward spin feel natural, too weak or too strong?
2. **Arch:** the flip's rotation now comes from the takeoff (and, on the bar, from Arch down and Tuck up before letting go). In the air Arch opens the body. Does that make sense in play? Score it again.
3. **Bar flip (§2):** can you complete one now?
4. **Landings:** which landings fail most (after a flip, a tuck, holding Arch)? This decides the next round (a spin-aware landing reflex).
5. **Jump height:** still wanting a boost after the back-flip change?
6. **Slow-mo indicator:** clear, and not in the way?
7. **Motor A/B:** redo §4a properly blind, and send the reveal line (round 2's "preferred B" couldn't be counted).
8. **Pumping, twist, moon, slow motion, tuck:** still as good as round 2? Tests guard them, but say if anything feels different.

## 7. For a Claude session with Studio MCP on your computer

Studio MCP only works from a session running on the same computer as Studio (the Claude Desktop app, or `claude remote-control` in the project folder), where the MCP server was added with `claude mcp add ...`.

1. Sync or open the place (step 0).
2. Run in Edit mode: `print(require(game.ReplicatedStorage.GymTests.StudioRun)(false).failed)` and confirm `0`.
3. Start a playtest. Read Output for the lines in step 1, and confirm `ReplicatedStorage.GymTests:GetAttribute("SelfTestStatus") == "passed"`.
4. Report the `[GymClient] runtime check` line (fps, sim ms, render ms).
5. Stop the playtest. Leave the visual and feel checks (steps 3–6) to a human.
