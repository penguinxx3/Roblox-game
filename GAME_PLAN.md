# Game Plan (v2)

Status: **approved; Phase 1 in progress. P1.1 (physics foundation) done; P1.2 (movement control) built and tested headlessly, Studio validation pending.**
v2 incorporates the reference-clip study ([REFERENCE_ANALYSIS.md](REFERENCE_ANALYSIS.md)).

## 1. Vision

A Roblox physics gymnastics and freerunning sandbox, **seen from the side**: pump a swing, let go, flip and twist, and **intentionally** catch the next grip. Later, also land on blocks, hold handstands, and jump off ledges. Players use their own avatars (or a clean stickman mode).

It must feel fluid, responsive and satisfying **on a phone first**; PC and controller are also fully supported. Moments should be clip-worthy (slow-mo, moon gravity, long catch chains, replays), because short-form video is the growth channel.

## 2. Pillars (tie-breakers for every decision)

1. **Movement feel comes before features.** Nothing else gets built until swinging, flipping, releasing and regrabbing feel excellent on mobile.
2. **Skill is timing.** The release moment and the grab moment are the player's decisions. Catching is never automatic.
3. **Momentum never breaks.** Release and catch continue the motion; they don't interrupt it (reference §3.1).
4. **Mobile first.** Two thumbs, no steering: the side-view plane removes the need for a joystick.
5. **Worth clipping.** Slow-mo, moon gravity, catch chains, replays and clean recording are core, not extras. (P1.2 playtest: moon gravity and slow motion were the tester's favourites. Their behaviour is kept and guarded by tests while the movement is tuned.)
6. **Social sandbox, later.** Multiplayer is designed for from day one, built after the feel is proven.

## 3. Core loop (prototype scope)

```
hang ─► pump (Arch/Tuck timing) ─► Let Go on the upswing ─► shape the flight (Tuck / Arch / Pike, Twist)
  ▲                                                                            │
  └────────── press GRAB as the hands reach the grip ◄────────────────────────┘
                   (miss → fall → body lands physically → auto-reset)
```

A **regrab** is a successful intentional catch after a release, without touching the ground. The HUD term and styling will be our own (not the original's "Regrabs" counter; see REFERENCE §6).

## 4. Controls

### Actions

| Action | Type | Effect |
|---|---|---|
| Arch | hold | Arched shape: pumps the swing, slows spins |
| Tuck | hold | Tucked shape: pumps the swing, spins fast in the air |
| Arch + Tuck | hold both | Pike |
| Let Go | press | Release the grip (only while gripping) |
| **Grab** | **press** | **Try to catch a grip (only while not gripping).** Timed; see §5. |
| Twist Left / Right | hold | Spin around the body's long axis in the air. Both held = hold the angle. |
| Reset | press | Back to hanging still on the bar |

Grab and Let Go are never both valid at the same moment, so pressing the wrong one of the two does nothing.

*Ground (built early, in P1.2):* no extra buttons. **Tuck = crouch; releasing Tuck from a crouch pushes off and jumps physically** (a quick tap only dips). **Arch = reach** (arms up, rise); holding Arch through the push spins the body backward at full jump height (a back-flip takeoff). The feet alone give about half a back tuck; the optional `jumpSpinAssist` makes a full one (design decision open, PLAYTEST_P1_2.md). Pike on the ground crouches like Tuck. Landing on the feet is contact physics plus a landing reflex; landing on hands is Phase 2.

*As built in P1.2:* the keyboard and gamepad tables below are implemented (Grab is counted but has no effect until P1.3; Reset is on R / Y; the alternate debug keys \` and gamepad View/Select are not bound yet). Touch uses a **minimal functional Layout A** (touch-down, multi-touch, also clickable with a mouse), not the final mobile UI; Layout B, button sizing/opacity settings and the clean-recording mode come later.

### Mobile (primary; landscape)

**Layout A — dedicated buttons (default, as requested)**

```
┌───────────────────────────────────────────────────────────────────┐
│ [⚙ debug]                                              [↺ Reset] │
│                                                                   │
│                                             [◄ TWIST]  [TWIST ►]  │
│   [  ARCH  ]                                                      │
│                                             [ LET GO ]  [ GRAB  ] │
│   [  TUCK  ]                                            (largest) │
└───────────────────────────────────────────────────────────────────┘
   left thumb = body shape                  right thumb = hands + twist
```

- On the bar, the left thumb pumps while the right thumb waits to Let Go.
- In the air, the left thumb holds Tuck while the right thumb twists, then grabs.
- The two Twist buttons sit side by side, so one flat thumb can press both to hold the angle.

**Layout B — combined HANDS button (A/B test):**
- One big HANDS button: it lets go while gripping and grabs while airborne.
- Still a timed, deliberate press.

**Mobile input rules:**
- Buttons respond on **touch-down**, in the same frame.
- Full multi-touch; thumbs can slide between buttons.
- Touch areas are larger than the drawn buttons; sizing is screen-relative, and buttons respect safe areas.
- The default Roblox thumbstick, jump button and camera drag are disabled.
- **Opacity 0 hides the buttons while they stay active**, for clean recordings (the reference recording R3 shows no buttons).

### Keyboard

| Action | Primary | Alternate |
|---|---|---|
| Arch | A | ← |
| Tuck | S | ↓ |
| Let Go | W | ↑ |
| Grab | Space | J |
| Twist L / R | Q / E | — |
| Reset | R | — |
| Debug panel | F2 | ` |
| Slow-mo cycle / Moon (debug) | T / G | — |

### Gamepad

| Action | Button |
|---|---|
| Arch | LT (analog) |
| Tuck | RT (analog) |
| Grab | A / Cross |
| Let Go | B / Circle |
| Twist L / R | LB / RB |
| Reset | Y / Triangle |
| Debug panel | View / Select |

## 5. Intentional grab — player-facing rules

- You must **press Grab** to catch. Hands passing the grip never catch on their own. **Holding Grab does nothing extra.**
- The **hands must actually reach the grip**, within about half a stud, so the catch always *looks* right (hands on the bar, no snapping), as in the reference.
- The **arms must be reaching toward it**, and a twist must be nearly finished (within ≈35°).
- **Timing is forgiving:** an early press is buffered (≈100 ms) and a slightly late press still counts (≈60 ms, rewound fairly).
- **Mashing is punished:** a missed grab blocks the next one for ≈200 ms, which is shorter than a normal catch rhythm (1–1.5 s).
- **Momentum carries through the catch:** the swing keeps going in the same direction.
- **Feedback:**
  - a catch sound
  - haptics (where supported)
  - quality (Perfect / Good / Save) and the chain counter
  - deliberately **no hitstop or camera shake**; the continuous motion is the reward
- Exact rules: [PHYSICS_DESIGN.md §7](PHYSICS_DESIGN.md).

## 6. Avatars and look

- **Prototype:** a stickman in **our own style**: different proportions, materials and colors from the reference's box-torso figure.
- **Game:** the player's R15 avatar posed from the simulation. Body scale is limited to standard proportions so physics is identical for everyone. Stickman mode stays as a setting.
- **Our own art direction:** palette, skybox, equipment designs and UI. Nothing from the reference's look (REFERENCE §6).

## 7. World and multiplayer vision (built later, designed for now)

- **Side-view lanes (2.5D).** Gameplay happens in vertical planes, like the reference.
  - A sandbox map is a set of **parallel lanes or courses**, each a plane with its own equipment.
  - Players pick a lane, and can see players in neighboring lanes.
  - This is a product decision to confirm (see §10).
- **Equipment kit (Phase 2+):**
  - bars and pole-tip grips
  - stubs
  - in-plane beams and frames
  - rotating spoked wheels (our own design)
  - blocks, pillars, walls and pits for landing, handstands and vaults
- **Servers:** about 15–20 players. **No player-vs-player collision**, shared static equipment, and reactive equipment instanced per player.
- **Slow-mo policy (important):** in the reference, slow-mo slows the whole world, equipment included. That can't be shared in a public server, so:
  - slow-mo is live in **solo and private servers**
  - every server gets a **replay tool** (record at 1×, play back slowed)
  - moon gravity is per-player everywhere
- **Replays with speed control** and a vertical clip camera: early Phase 2, since the reference shows creators rely on replays.
- **Later modes** (not designed yet): trick battles, catch chains / floor-is-lava, courses.

## 8. Prototype scope

**In:**
- one character (our stickman) and one bar
- Arch, Tuck (Pike)
- Let Go, intentional Grab, regrab
- Twist left and right
- basic side camera
- Reset, and a physical fall onto the floor followed by auto-reset
- touch, keyboard and gamepad input
- debug tools: tuning panel, overlay, session log, *(proposed)* instant replay

**Out:**
- shops, lobby, progression, monetization, cosmetics, quests, game modes, maps
- avatars, multiplayer
- advanced ground movement (handstands, hand-plants, vaults); basic standing, jumping and landing were pulled into P1.2 at the owner's request
- in-plane beams, wheels, the player replay tool, scoring, any UI beyond the controls and debug tools

## 9. Design concerns and proposed alternatives

| # | Concern | Why it matters | Proposal |
|---|---|---|---|
| 1 | **6 action buttons + Reset on mobile** | Two thumbs; more buttons means more mis-presses | Layout A default + Layout B test. Let Go/Grab mis-presses are harmless. |
| 2 | **Hold-to-grab would be automatic catching in practice** | Players would just hold it | Press-only attempts + cooldown after a miss |
| 3 | **Touch latency and low fps** | Tight windows feel random on weak phones | Time windows ≥ 2 frames at 30 fps, swept test, rollback grace, per-device tests |
| 4 | **Momentum transfer / release boost above 1.0** | Infinite-energy chains | Allowed, flagged, capped by `maxSwingSpeed` |
| 5 | **Real avatars** | Unfair physics; readability | Fixed skeleton, standard R15 scaling, IK hands, stickman mode |
| 6 | **Vertical TikTok vs landscape controls** | Six buttons fit landscape better | Play in landscape; vertical clip camera and replay tool later |
| 7 | **Twist behavior** | Controllability on touch | Both modes built; playtests decide |
| 8 | **Planar (2.5D) world** *(new)* | Roblox players may expect 3D roaming | Lane-based sandbox; confirm before map production |
| 9 | **Slow-mo in multiplayer** *(new)* | Can't slow shared moving equipment for one player | Slow-mo in solo/private + replay tool; 1× in public |
| 10 | **Ground movement is a big part of the reference** *(new)* | Bars-only would feel incomplete vs the reference | Same solver supports it; scheduled for Phase 2 after the feel gate |

## 10. Open questions for you

1. **Approve the 2.5D side-view lanes** for the world design?
2. **Approve the slow-mo policy:** live in solo/private servers, plus a replay tool everywhere, and 1× in public servers?
3. Include the **debug instant replay** in the prototype? It's a tuning tool; I recommend yes.
4. Which phones and tablets do you have for testing (at least one low-end Android)?
5. Twist preference (hold vs tap), or let playtests decide?
