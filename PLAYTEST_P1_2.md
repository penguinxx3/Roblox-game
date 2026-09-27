# P1.2 Playtest — Findings and Changes (feedback round 1)

A friend playtested the P1.2 build in Roblox Studio. This file records what they reported, what the investigation found underneath each point, what changed, and what is left to decide. The rule for this round: take every complaint seriously as player evidence, but fix the cause, not the symptom. A complaint is not automatically a request for a buff.

Numbers come from `lune run tools/flip_bench.luau`, `lune run tools/smooth_bench.luau` and the `Movement.spec` tests (TESTING.md). "Before" is the build that was playtested (commit 15fdbb0).

## What the tester liked: keep it

**Moon gravity** (G) and **slow motion** (T) both felt cool and enjoyable. Rule from here on: movement tuning must not remove or substantially change them, unless a concrete technical issue is found.

**Audit of round 1.** The playtested build (15fdbb0) and the round-1 build (3578c37) were measured with the same script. Neither feature changed:

| | Playtested | Round 1 |
|---|---|---|
| Slow motion 0.5 / 0.25 / 0.1, bar and ground, Earth and moon | identical movement in simulation time, 2 / 4 / 10× real time | same |
| Moon half swing (Earth 1.14 s) | 2.81 s | 2.80 s |
| Moon swing height after 8 half swings (Earth ≈ 53°) | 52.9° | 53.1° |
| Moon jump height / airtime vs Earth | 1.15× / 2.75× | 1.16× / 2.78× |
| Moon, strength follows gravity (default) | on | on |

The movement fixes of round 1 (arch takeoff, tuck, pumping) act the same way on the moon as on Earth. The moon Arch jump now keeps its height too, and the moon tuck spins up faster. Slow motion only changes how fast simulation time plays, and that code was not touched.

**Guarded from now on.** Two tests in `Movement.spec` fail if a future change alters either feature:
- *Slow motion keeps player movement identical:* a scripted routine on the bar and on the ground, Earth and moon, at 0.5 / 0.25 / 0.1. It must replay bit-identically and take 2 / 4 / 10× the real time.
- *Moon mode keeps its feel:*
  - the moon swing period is ×2.46 Earth's, with the same swing decay;
  - the moon jump is 1.14× as high (±0.12) and ≈ 2.75× as long (±0.3), and lands standing;
  - the defaults stay 0.165 with strength following gravity;
  - moon, slow motion and the A/B's motor setting survive Reset and scene changes.

Both tests pass on the playtested build and on the current one.

## Summary

| Item | Score | What it was | Changed |
|---|---|---|---|
| Arch | 5/10 | **Purpose not visible** (no gameplay loop yet), plus one real bug: an Arch jump lost a third of its height | Arch jump keeps its height and now spins backward (0.38 rev/s). Its three jobs are documented. |
| Tuck | 4/10 | **Implementation + tuning.** In the air the arms stayed overhead (the bar pose), and P1.2's smoothing had made the first 0.1 s slower than P1.1 | Arms-in air tuck, active squeeze. Spin after 0.1 s ×1.17 → ×1.44; full tuck ×1.5 → ×2.2 |
| Twist | 7/10 | Works | Nothing (as asked) |
| Jump | 3/10 | **Not airtime.** The height is realistic and more height barely helps. The takeoff made almost no rotation, and an Arch takeoff cost height | Arch takeoff fixed (full height, backward spin). Optional `jumpSpinAssist` for standing back flips (default off; your call) |
| Pumping | 7/10 | **Two joints fighting the swing** (soft bar elbows and hips), a cap that braked tucks, and the scene's 60° head start | Firmer bar elbows and hips, a corrected energy cap, `hangStartAngle` to start from a still hang |
| Motor 6 vs 8 | — | No comparison yet | Blind A/B built in (B / Shift+B). Procedure in STUDIO_VALIDATION.md §4a |
| Overall | 3/10 | Mostly flips: bar releases gave ~0.5–1.1 rev, standing jumps ~0.1 | Bar releases now give ~1.2 rev with no pumping and ~2–2.6 rev after 4 s of pumping |

## Arch — 5/10

**Tester:** can't judge it yet without the full loop; fine if its purpose is moving the arms back and changing body position.

**Finding.** That reading is correct, and it is most of the story. Arch has three jobs:

1. **On the bar:** the downswing shape of pumping (Arch falling, Tuck rising).
2. **In the air:** opening the body to slow the spin before landing or a catch.
3. **On the ground:** the back-flip takeoff (hold Tuck to crouch, press Arch, release Tuck).

The first two only make sense once there is something to swing to and catch (P1.3). The third had a real bug. With Arch held, the controller asked the feet for more spin than they can give, so the centre of pressure stayed pinned at the toe. The ankles then tipped the body onto its toes, the knees stopped extending (100° → 77° instead of straight), and the jump lost a third of its height. The horizontal drift damping also cancelled most of the spin.

**Changed.**
- The centre of pressure stays in the middle 60% of the foot during the push.
- Arch turns off the drift damping (a back flip doesn't try to stay over its feet).

| Arch takeoff, then Tuck | Before | Now |
|---|---|---|
| Rise | 1.35 studs | 1.78 studs (plain jump 1.73) |
| Backward takeoff spin | 0.14 rev/s | 0.38 rev/s |
| Rotation before landing | 0.09 rev | 0.43 rev |

## Tuck — 4/10

**Tester:** can't tuck fast enough to flip consistently; the arms don't tuck in compactly. Asked us to check airtime before buffing tuck strength.

**Findings.**
- **The arms really didn't tuck.** The single Tuck pose was built for the bar (arms overhead, holding on) and was used in the air too. So the tuck only folded the legs, and the spin gain was ×1.5.
- **The first 0.1 s had become slower.** P1.2 added input smoothing and more motor damping for smoothness. In the air that cut the early spin-up: ×1.48 at 0.1 s in P1.1, ×1.17 in P1.2.
- **Airtime does contribute, for standing jumps** (see Jump). For bar releases, the ~0.75–0.95 s of air was enough; the missing piece was release spin (see Pumping).

**Changed.**
- **AirTuck pose:** off the bar the arms come down in front and the forearms fold toward the shins. On the bar the Tuck still holds the bar overhead.
- **Squeeze:** while tucking or piking off the bar, the shoulders, elbows, hips and knees run at `tuckHertz` (10 Hz) instead of `motorHertz` (6 Hz). The input smoothing is unchanged, because it also shapes the bar.

| Tuck in flight | Before | Now |
|---|---|---|
| Spin 0.1 s after pressing | ×1.17 | ×1.44 |
| Full tuck | ×1.5 | ×2.2 |
| Rotation in 0.5 s of tucking | 0.77 rev | 1.03 rev |

A real tight tuck from a straight body spins 2.5–3.5× faster. The reference clips showed ≈1.6×, with partial tucks. A half-pressed trigger still gives a partial tuck.

**Cost (a trade-off to watch).**
- The arms swing a little past the target and settle forward, hands by the knees: the spin pulls them outward.
- In the zero-gravity shape test, the hip/knee overshoot rose from 7° to 23° (P1.1's motor settings: 26°) and the wobble from 0.9° to 1.6°.
- If it looks floppy, try `tuckHertz` 8 or `motorDampingRatio` 1.5.

## Twist — 7/10

Unchanged, as asked. It shares nothing with the changes above: the twist code, rate and modes are untouched, and the twist tests pass unchanged.

## Jump — 3/10

**Tester:** not enough usable airtime or height for tucks and aerial moves. Asked us to look at launch velocity, jump mechanics, gravity/strength scaling and airtime, and not to raise the jump height blindly.

**Findings.**
- **Height and airtime are realistic.** A plain jump rises 1.73 studs, about 0.48 m at this scale (35 studs/s² = 9.8 m/s²), with about 0.55–0.65 s of air. A real standing back tuck has about the same airtime.
- **The missing piece is takeoff rotation.** A real back tuck leaves the ground at ≈ 0.7–0.8 rev/s. It gets there with a backward lean that puts the centre of mass behind the toes. This push controller keeps the centre of mass over the feet. Its takeoff spin was 0.09 rev/s (plain) and 0.14 rev/s (Arch).
- **More height is a poor fix:**
  - `jumpStrength` 1.5 → 3.5 raises the rise only 1.73 → 2.38 studs (airtime 0.63 → 0.75 s), because the push ends when the knees straighten.
  - Plain jumps then land fallen.
  - Much bigger jumps would change the game's feel everywhere, not just for flips.
- **Gravity/strength scaling** is as designed. Moon with strength following gravity gives the same kind of jump, ~2.5× slower (rise 2.08, 1.53 s of air). `strengthGravityScaling = 0` gives real-moon jumps.

**Changed.**
- The Arch takeoff fix (see Arch): full height, backward spin.
- **`jumpSpinAssist` (new, default 0 = pure physics):** after an Arch push, this share of the spin still missing to `jumpArchSpin` (0.8 rev/s) is added as a torque over the first 0.1 s of flight. It acts after takeoff: during the push it tipped the body back while the legs were still extending and cut the rise to 0.56 studs.

| Standing back tuck | Rotation | Landing |
|---|---|---|
| Pure physics (default) | 0.43 rev | fallen |
| `jumpSpinAssist` 1 | 0.87 rev, full height | on the feet |
| Moon, pure physics | 0.40 rev | fallen |
| Moon, `jumpSpinAssist` 1 | 1.92 rev, 1.56 s of air | on the feet |

The moon result is close to the reference's moon clip (≈1.5 s of air, over two somersaults). The assist leaves plain jumps alone.

**Decision needed.** Should standing back flips be a feature?
- **Option 1:** turn on `jumpSpinAssist` (≈ 0.7–1): simple and transparent, but not muscle.
- **Option 2:** build a real lean-back takeoff in Phase 2: physical, but a bigger controller job.
- **Option 3:** keep flips a bar-release skill.

My recommendation: try `jumpSpinAssist` 1 in the next playtest, and decide after P1.3 when the loop exists.

## Pumping — 7/10

**Tester:** likes it. But the initial boost makes building momentum easier than starting from neutral, and actively swinging sometimes feels like it slows the body down. Asked us to check whether legs, posture, joint forces or energy transfer fight the swing.

**Findings: yes, three things fought the swing.**

1. **Soft elbows on the bar.** The bar's pull runs through the elbows, and the shoulders (18 Hz on the bar) push through them. At 6 Hz the elbows flexed under the load, and their damping drained the swing. Pumping stalled at ≈ 107°, and a relaxed swing lost 3.7° per cycle at 90°.
2. **Soft hips on the bar.** The hips hold the legs against the swing's pull. While a shape was held, the legs sagged out at the bottom of each swing, where the pull is strongest, and sprang back in at the top. That is exactly the reverse of pumping, so holding Tuck or Pike drained the swing.
3. **The swing cap braked tucks.** The cap compared the swing's energy with the current shape's inertia. Tucking lowered the cap at the same moment it sped the swing up, so near the cap every tuck was braked. It barely mattered at P1.2, when swings stalled far below the cap, but after the two fixes above, pumping reaches giants and the cap.

**The "initial boost"** is the Hang scene: it starts every reset at 60°, released from rest. From a still hang, the first swings grow slowly, because a shape change can only pump a swing in proportion to its size. That part is physical and roughly human: a gymnast from a dead hang also needs a few swings. But the 60° start hides it.

**Timing** was also checked, on the current build:
- At 60–90° swings, tucking up to 30° early or late changes the gain by at most about a quarter.
- A tuck 10–20° after the bottom works best, like a real tap swing.
- At small swings timing matters more: ±20° still pumps well, but 30° late stops pumping.
- Wrong timing (Tuck while falling) removes energy, as it should.

So correct pumping is forgiving, and early misses at small swings are mostly learning.

**Changed.**
- **Elbows** use `gripShoulderHertz` (18 Hz) while gripping.
- **Hips** use `gripHipHertz` (10 Hz, new) while gripping.
- **Energy cap:** measured against the straight body, so a tuck near the cap spins faster instead of being braked. The brake is stronger (4 Mg·stud at 40/s), and `swingAssist` can't overshoot the cap.
- **`hangStartAngle`** (new, default 60; 0 = a still hang, applies on Reset). The default stays 60 because the physics tests use it; set 0 to practise from nothing.

| | Before | Now |
|---|---|---|
| Swing lost per cycle from 90°, relaxed | 3.7° | 2.3° |
| … holding Tuck | 6.8° | 4.1° |
| … holding Pike | 10.7° | 5.6° |
| Pumping from a still hang, time to 60° (steady rhythm) | ≈ 8 s | ≈ 8–10 s (early growth about the same) |
| … best result | stalls at ≈ 107° | 90° by ≈ 10–12 s, over the top by ≈ 12–15 s |
| Peak after 15 s of pumping from 60° | 121° | 145° |
| Bar release at 50°, no pumping, then tuck | 0.62 rev/s → 0.54 rev | 1.05 rev/s → 1.20 rev |
| Same after 4 s of pumping | 1.03 rev/s → 1.10 rev | 1.61 rev/s → 2.59 rev |

The last two rows are what the overall 3/10 was mostly about: flips from the bar are now there. The reference's open-body spin rate is ≈ 1.15 rev/s, and its pole-to-pole flights last ≈ 0.9 s.

**Cost.** Pumping looks livelier: torso jerk while pumping 2022 → 4082 (P1.1 motor settings: 3200). Extra damping on the bar hip would calm it, but it brings the drain back (ζ 2: Pike 7.1° per cycle), so it wasn't added.

## Motor 6 vs 8

The tester now understands what the setting does. The default stays **6 until a proper blind A/B is done**: automated metrics can't decide this, it is a feel question. Both values stay available, and a **blind A/B** is built in:
- **B** switches between two hidden variants, A and B. At session start they are randomly assigned `motorHertz` 6 and 8.
- **Shift+B** reveals which was which, in the overlay and in Output. The reveal also reports how long each variant was played and how many times you switched. It flags a test that was too short to count.

The procedure is in STUDIO_VALIDATION.md §4a. It includes a moon pass and a slow-motion pass, since those are the modes the tester enjoys most.

What `motorHertz` still changes after this round:
- **In the air:** Arch, Neutral and the landing reflex. The tuck squeeze is 10 Hz either way.
- **On the bar:** knees and ankles. Shoulders and elbows are 18 Hz and hips at least 10 Hz either way.
- **In the smoothness benchmark:** 8 Hz overshoots more (37° vs 23°) with a similar wobble.

## Overall — 3/10

**Tester:** the build doesn't yet feel capable of satisfying aerial flips; some of it may be learning.

**Finding.** Mostly not learning. Three implementation problems and one open design choice were behind it:
- **Implementation:** swing energy drained through soft bar joints, so releases lacked spin.
- **Implementation:** the tuck was not compact in the air, and was slower to start than in P1.1.
- **Implementation:** the Arch takeoff lost height.
- **Design choice:** a standing back flip isn't reachable by the feet alone.

**Learning** is a real factor in one place: pumping timing, which is forgiving but must be in phase.

## Next playtest

See STUDIO_VALIDATION.md. The questions that matter most this round:

1. **Flips from the bar:** pump 3–5 swings, let go on the front upswing, Tuck. Does a full flip, and then more than one, feel reachable and controllable?
2. **The air tuck:** is it visibly compact and quick now? Do the arms look right, or floppy?
3. **Pumping:** does it still feel good? Does active swinging still ever feel like it slows you down? Try `hangStartAngle` 0 (then R) for a start from nothing.
4. **Standing back tuck:** crouch (S), press A, release S, then press S in the air. Try it with `jumpSpinAssist` 0 and 1: keep, change or drop?
5. **Motor A/B:** follow §4a and record the preference before revealing.
