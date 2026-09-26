# Movement Quality Testing

How we decide whether the movement is actually good, rather than "seems fine to me".
There are four layers, from cheapest to most important. The **prototype exit gate** is in §6.

## 1. What "good" means here

| Quality | Operational definition |
|---|---|
| Responsive | A press changes the pose on screen within the same frame. No added input latency compared with the Roblox baseline on the same phone. |
| Smooth | No hitches, pops or jitter at any frame rate or time scale, including the moment of the catch |
| In control | Players can say *why* something happened and repeat it on purpose |
| Fair catches | Misses feel like the player's fault. A catch never happens without a press. |
| Satisfying | Regrabs are rated as rewarding; players want to chain them |
| Consistent | Same inputs give the same result on a 30 fps phone and a 240 Hz PC |

## 2. Layer A — automated core tests (Lune, headless)

The core is pure Luau, so it's tested outside Roblox on every change. The tests become CI later.

| # | Test | Pass criteria |
|---|---|---|
| A1 | **Stability soak:** 10 simulated minutes of random inputs × timeScale {1, 0.25} × gravity {1, moon} × simHz {120, 240, 480} | No NaN or infinity; speeds within caps; joint angles within limits |
| A2 | **Energy:** hanging with no damping, fixed shape, released from 90° | Energy drift ≤ 0.5% over 60 s |
| A3 | **Flight conservation:** no twist input | Angular momentum constant to 1e-9 relative; center of mass follows the exact parabola |
| A4 | **Pumping is skill:** a phase-correct scripted pumper vs a random/mistimed one | Correct timing reaches a giant (swing height ≥ 100%) in 3–8 swings with default tuning. Mistimed pumping stays < 50% after 20 swings. |
| A5 | **Tuck spins faster** | For the same angular momentum, the tucked somersault rate is ≥ 2× the layout rate |
| A6 | **Frame-rate independence:** one scripted input timeline driven at 30/60/120/144/240 fps | Same state transitions and catch outcomes; final state within 1e-3 studs when input edges fall on the same step |
| A7 | **Time-scale consistency:** timeScale 1 vs 0.25 | Identical trajectory in simulation time |
| A8 | **Determinism:** the same run twice | Bit-identical |
| A9 | **Catch window curve:** a scripted release that passes the bar at a known closest-approach step; sweep the press offset from −250 to +150 ms one step at a time | Success exactly inside [−early, +late] (±1 step) when the path comes within `catchRange`. Always fails when the path misses by more than `catchRange`. |
| A10 | **No automatic catching:** hold Grab through the whole flight with no new press | Never catches (with `grabMode = press`) |
| A11 | **Anti-mash:** a press every 50 ms through the pass | Cooldown triggers after the first miss; success rate below a single well-timed press |
| A12 | **Momentum transfer** | Angular momentum about the bar is equal before and after the catch (transfer 1.0) to 1e-9; scales linearly with the transfer factor |
| A13 | **Alignment gate** | Rejected just beyond `catchAlignTolerance`, accepted just inside |
| A14 | **Swept detection:** hands crossing the bar at 100 studs/s | Caught (no tunneling) |
| A15 | **Rollback equivalence:** a late press within the grace window | Resulting state equals catching at the valid step and simulating forward |
| A16 | **Throughput (informational)** | Steps per second in Lune, recorded per commit to catch performance regressions |

Visual sanity check: the test runner can dump a trace (CSV of joint positions). A small script renders it to a PNG strip or GIF, so motion can be inspected before anyone opens Studio.

## 3. Layer B — in-game instrumentation

Part of the prototype (see PHYSICS_DESIGN §13):
- **Debug overlay:** frame and sim timing, state, energy and swing height %, catch timeline, last-catch report, and the current **preset name** (so every screenshot or recording shows which tuning was active).
- **Session log:** every Let Go, Grab press, attempt, catch, miss and ignored press, with the step, distance, alignment, timing offset, quality, rollback steps, fps and device type. **Export** produces copyable text (JSON/CSV) that testers send back.
- **Analysis:**
  - press-timing histograms relative to the closest approach
  - success rate per distance band
  - miss reasons (too far / misaligned / cooldown / out of reach)
  - early vs late tendencies per device

## 4. Layer C — device performance and latency

**Device matrix** (to be confirmed with what you own):

| Class | Example | Role |
|---|---|---|
| Low-end Android | 3–4 GB RAM, 2019–2020 chipset | Performance and latency reference; must hold ≥ 30 fps |
| Mid Android | recent mid-range | |
| iPhone (older) | iPhone 11/12 class | |
| iPhone (recent) | 120 Hz ProMotion | High-refresh interpolation check |
| Tablet | iPad | Button layout scaling |
| PC | 60 Hz and 144+ Hz monitor, keyboard + gamepad | |

**Performance:**
- Record MicroProfiler captures with our `debug.profilebegin` markers.
- Budgets: sim ≤ 0.3 ms/frame, rig ≤ 0.2 ms/frame on the low-end reference.
- 60 fps on mid phones; never below 30 fps on low-end.

**Input-to-screen latency (added latency):**
- Film the phone with another phone's 240 fps slow-mo camera, capturing the finger and the screen.
- Count the frames from touch contact to the first visible pose change. Do 10 trials per device.
- Compare against the Roblox baseline on the same device (a default character's jump in an empty baseplate).
- **Target: our pipeline adds 0 frames over baseline** (at most 1).

## 5. Layer D — playtests (the part that decides)

**Participants per round:** 5–8, on their own phones where possible:
- mostly target-age Roblox mobile players (minors only with a parent or guardian's consent)
- 1–2 people who know the original game
- 1 non-gamer

**Session (≈20 min):**
1. **Cold start (2 min):** no instructions. Observe what they discover.
2. **Briefing (1 min):** the six actions, and that you must press Grab.
3. **Timed tasks:**
   - (a) reach a giant swing
   - (b) release and regrab once
   - (c) regrab with a tuck flip
   - (d) regrab with a half twist
   - (e) 5 regrabs in a row
   Record the time to complete each task, or failure.
4. **Free play (up to 5 min):** "stop whenever you like". Record whether and how long they continue.
5. **Questionnaire (1–7 scale):**
   - Controls felt responsive.
   - I felt in control of the swing.
   - Regrabs felt satisfying.
   - When I missed, it was my fault.
   - The character never caught the bar without me pressing Grab.
   - I wanted to keep playing.
   - I'd record a clip of this.
   - Plus open questions: *What felt wrong?* and *One thing you'd change?*

**Collected per tester:** session-log export, a screen recording (send it; I review recordings frame by frame), device, fps.

**Rules:**
- Don't tell testers what changed between rounds.
- When comparing two tunings, use blind A/B presets and alternate the order between testers.

## 6. Prototype exit gate (go / no-go)

The prototype phase ends only when **all** of these hold on the device matrix:

| Metric | Target |
|---|---|
| Automated tests A1–A15 | All pass |
| Added input latency vs baseline | ≤ 1 frame, all devices |
| Frame rate / sim cost | ≥ 60 fps mid, ≥ 30 fps low-end; sim ≤ 0.3 ms |
| Median time to first giant (new players) | ≤ 3 min |
| Median time to first regrab (new players) | ≤ 6 min |
| Regrab success on a standard release, after 15 min | ≥ 60% new players, ≥ 85% experienced |
| "When I missed, it was my fault" | average ≥ 5 / 7 |
| Unintended catches reported | **0** |
| Responsive / In control / Satisfying | average ≥ 5.5 / 7 each |
| Voluntary free-play continuation | ≥ 50% play on ≥ 5 min |
| People who know the original: ours vs original | Majority say "as good or better" (if available) |

**If the gate isn't met after 3 tuning rounds:**
- Work out whether the gap is **tuning**, the **control scheme** (layout, twist mode) or the **model**. Anything that parameters can't reach counts as a model problem.
- Model problems: first try the planned extensions (secondary motion, shape load compliance, one-hand catch). If still failing, run the native-physics spike (TECHNICAL_DESIGN §3, fallback) before deciding the direction.

## 7. Tuning workflow

- Each build ships with a **named preset** in `tuning/presets/` (e.g. `2026-10-02-standard.json`) plus a one-line changelog entry.
- **Change one parameter group per round.** Keep the previous preset one tap away in the panel for A/B.
- Tester feedback always references the preset name shown in the overlay.
- The winning values are committed back to `Tuning.luau` defaults, so the repository remains the source of truth.
