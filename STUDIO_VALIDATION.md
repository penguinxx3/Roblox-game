# Studio Validation — P1.1 Physics Foundation

What must be checked **inside Roblox Studio**. This couldn't be done from the cloud build environment, which has no connection to Studio.

Everything headless is already green (TESTING.md, "P1.1 status"). This list covers what only the real engine and human eyes can confirm.

Tick items and note anything odd, ideally with a short screen recording.

## 0. Get the place into Studio

Pick one:
- **A. Open the built file:** open `BarGym.rbxl` (build it with `rojo build -o build/BarGym.rbxl`) in Studio.
- **B. Live sync:** run `rojo serve` in the repo and connect with the Rojo Studio plugin. Code edits then sync while you test.

## 1. Automatic checks on Play (≈10 s)

Press **Play** (F5). In the **Output** window you should see:

| Expect | Meaning |
|---|---|
| `[GymSelfTest] ... 37 passed, 0 failed, 3 skipped` | The physics specs pass **inside the Roblox engine** (quick mode) |
| `[GymClient] P1.1 physics foundation running. ...` | The client viewer started |
| `[GymClient] runtime check OK: scene=Hang steps=... avgSim=...ms ...` | The simulation is stepping and rendering after 3 s |
| No red errors, no `warn` lines from `[GymClient]` | |

Also check `ReplicatedStorage.GymTests` in Explorer (server view): its attributes should read `SelfTestStatus = "passed"`, `SelfTestFailed = 0`.

**Full suite** (includes slow tests, ~5–20 s). Run it from the **command bar**, either in Edit mode or on the server during Play:

```lua
print(require(game.ReplicatedStorage.GymTests.StudioRun)(false).failed)   -- expect 0 (40 passed)
```

## 2. What you should see (per scene)

Switch scenes with keys **1–4** or the **Scene** button.

| Scene | Expected | Watch for (report if seen) |
|---|---|---|
| **1 Hang** | Hangs from the steel bar, released 60° to the side, swings back and forth and slowly loses height. Arms nearly straight; hips, knees and feet flex a little with the swing. | Joints visibly separating; jitter; a swing that *gains* height; limbs flailing wildly |
| **2 Drop** | Falls from about 4 studs beside a block, lands, folds up, comes to rest on the floor. | Sinking into the floor; bouncing; shaking while at rest; limbs bending past natural angles |
| **3 Tumble** | Thrown up with a backward spin in a tuck, flies about 4–5 studs high, lands messily near the blocks or ramp, settles. | Passing through blocks or the ramp; exploding limbs; never coming to rest |
| **4 Wheel** | Hangs from one handle of a slowly rotating steel star (amber hub). It's carried around the circle and swings under it. | Hands detaching from the handle; stutter as the wheel turns |

## 3. Controls (debug-only, P1.1)

| Key | Button | Check |
|---|---|---|
| R | Reset | Restarts the current scene exactly as at the start |
| 1–4 | Scene | Switches scenes (the view rebuilds) |
| V | Pose | Cycles Neutral → Tuck → Pike → Arch → Crouch → Limp. The body springs into each shape (Limp = ragdoll). |
| T | Slow | 1 → 0.5 → 0.25 → 0.1 time scale. **Motion must stay smooth (no stutter) at 0.1.** |
| G | Moon | Moon gravity on/off: floatier falls and swings |
| P | Pause | Freezes |
| N | Step | While paused, advances exactly one 1/240 s step |
| C | — | Red dots at the contact points (e.g. feet and body on the floor in Drop) |
| F2 | Info | Hides/shows the overlay |

## 4. Live tuning

1. During Play, switch Explorer to the **client** view.
2. Select `ReplicatedStorage.GymTuning`.
3. Edit attributes in Properties. Changes apply immediately, except the ones marked "applies on Reset" in the overlay (`simHz` and body sizes). Try:
   - `motorHertz` (3 = softer and slower poses, 12 = snappier)
   - `hipMaxTorque` (0.3 = legs sag under load)
   - `gravity`
   - `restitution` (0.5 = bouncy landings)
   - `substeps` (1 = cheaper but stretchier joints)
4. Out-of-range values snap back to the allowed range.

## 5. Performance (needs a real device for the real answer)

- **In Studio:** the overlay line `sim X ms (N steps) render Y ms` shows the per-frame cost. MicroProfiler (Ctrl+F6) has labels `GymSim` and `GymRender`.
- **On a phone (the real target):** publish privately, open on your lowest-end phone, and read the same overlay line. The budget is sim ≤ 1.0 ms/frame and fps ≥ 30 on low-end (headless Lune measured ~0.1 ms/frame on a desktop CPU). Please send the numbers for each device.

## 6. Human look and feel (P1.1 questions)

This is only the foundation; gameplay controls come in P1.2. Still worth telling me:
1. Does the body look **springy and alive**, too **wobbly**, or too **stiff**? The pose change in **V** is the clearest place to judge.
2. Is the Hang swing believable (speed, arc, slow decay)?
3. Do landings in Drop and Tumble look physical rather than canned?
4. Anything that looks wrong at joints, contacts, or in slow motion?

## 7. For a Claude session with Studio MCP on your computer

Studio MCP only works from a session running on the same computer as Studio (the Claude Desktop app, or `claude remote-control` in the project folder).

1. Sync or open the place (step 0).
2. Run in Edit mode: `print(require(game.ReplicatedStorage.GymTests.StudioRun)(false).failed)` and confirm `0`.
3. Start a playtest. Read Output for the lines in step 1, and confirm `ReplicatedStorage.GymTests:GetAttribute("SelfTestStatus") == "passed"`.
4. Report the `[GymClient] runtime check` line (fps, sim ms, render ms).
5. Stop the playtest. Leave the visual checks (steps 2–6) to a human.
