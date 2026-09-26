# Game Plan

Status: **Phase 0 — architecture and design. Awaiting approval before any implementation.**

## 1. Vision

A Roblox physics gymnastics sandbox built around bar swinging: pump a swing, let go, flip and twist, and **intentionally** catch the bar again. Players use their own avatars. It must feel fluid, responsive and satisfying **on a phone first**; PC and controller are also fully supported. Moments should be clip-worthy (slow motion, moon gravity, long regrab chains), because short-form video is the main growth channel.

## 2. Pillars (tie-breakers for every decision)

1. **Movement feel comes before features.** Nothing else gets built until swinging, flipping, releasing and regrabbing feel excellent on mobile.
2. **Skill is timing.** The release moment and the grab moment are the player's decisions. Catching is never automatic.
3. **Mobile first.** Controls are designed for two thumbs on a touchscreen, then mapped to keyboard and gamepad.
4. **Worth clipping.** Slow-mo, moon gravity and visible regrab chains are core features, not extras.
5. **Social sandbox, later.** Multiplayer is designed for from day one but built after the feel is proven.

## 3. Core loop (prototype scope)

```
hang ─► pump (Arch/Tuck timing) ─► Let Go at the right moment ─► shape the flight (Tuck / Arch / Pike, Twist)
  ▲                                                                              │
  └──────────── press GRAB at the right moment near the bar ◄────────────────────┘
                     (miss → fall → reset)
```

A **regrab** = a successful intentional catch after a release, without touching the floor.

## 4. Controls

### Actions

| Action | Type | Effect |
|---|---|---|
| Arch | hold | Arched shape (open shoulders and hips). Pumps the swing, slows spins. |
| Tuck | hold | Tucked shape. Pumps the swing, spins fast in the air. |
| Arch + Tuck | hold both | Pike |
| Let Go | press | Release the bar (only while hanging) |
| **Grab** | **press** | **Try to catch a bar (only while flying).** Timed; see §5. |
| Twist Left / Right | hold | Spin around the body's long axis in flight. Both held = hold the angle. |
| Reset | press | Back to hanging still on the bar |

Grab and Let Go are never both valid at the same moment: Let Go only works while hanging, Grab only while flying. Pressing the wrong one of the two is harmless. It does nothing and has no side effects.

### Mobile (primary; landscape)

**Layout A — dedicated buttons (default, as requested)**

```
┌───────────────────────────────────────────────────────────────────┐
│ [⚙ debug]                                              [↺ Reset] │
│                                                                   │
│                                                                   │
│                                             [◄ TWIST]  [TWIST ►]  │
│   [  ARCH  ]                                                      │
│                                             [ LET GO ]  [ GRAB  ] │
│   [  TUCK  ]                                            (largest) │
└───────────────────────────────────────────────────────────────────┘
   left thumb = body shape                  right thumb = hands + twist
```

Why this split:
- On the bar, the left thumb pumps (Arch/Tuck) while the right thumb waits to Let Go. Both hands work together with no conflict.
- In the air, the left thumb holds Tuck while the right thumb twists and then grabs, one after the other.
- Twist ◄ ► sit side by side, so one flat thumb can press both to hold the angle.

**Layout B — combined HANDS button (A/B test)**
- One big HANDS button replaces Let Go and Grab. It lets go while hanging and grabs while flying.
- It's still a deliberate, timed press, so nothing becomes automatic.
- Fewer buttons for thumbs to find. The risk is muscle-memory confusion. We compare A and B in playtests and switch between them in the debug panel.

**Mobile input rules (these affect feel as much as physics does):**
- Buttons respond on **touch-down** (not on release), in the same frame, with instant visual feedback.
- Full multi-touch. A thumb can **slide** from one button to another without lifting (e.g. Arch → Tuck).
- Invisible touch areas are larger than the drawn buttons (`hitPadding`). Sizes scale with the screen and have a minimum physical size. Buttons respect notches and safe areas.
- Roblox's default thumbstick, jump button and drag-to-rotate camera are disabled.
- Button size, opacity and layout are tunable live. A full layout editor comes later (Phase 4).

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
| Arch | LT (analog: partial arch) |
| Tuck | RT (analog: partial tuck) |
| Grab | A / Cross |
| Let Go | B / Circle |
| Twist L / R | LB / RB |
| Reset | Y / Triangle |
| Debug panel | View / Select |

## 5. Intentional grab — player-facing rules

- You must **press Grab** to catch. Hands passing near the bar never catch on their own.
- **Holding Grab does nothing extra.** Only the press counts, so you can't hold it down to auto-catch.
- The timing is forgiving but real:
  - press slightly early and it's buffered (≈100 ms)
  - press slightly late and it still counts (≈60 ms)
  - your hands must actually pass close to the bar (≈0.9 studs)
  - you must be roughly aligned with it (twist finished to within ≈35°)
- **Mashing is punished.** A missed grab briefly blocks the next one (≈200 ms), so one well-timed press beats spamming.
- Catch quality shows as **Perfect / Good / Save**, with a sound and a small camera kick (haptics where supported).
- All of these numbers are tuning parameters. Exact rules are in [PHYSICS_DESIGN.md §7](PHYSICS_DESIGN.md).

## 6. Avatars and look

- **Prototype:** a capsule stickman on the fixed gameplay skeleton. This keeps the feel test clean.
- **Game:** the player's own R15 avatar posed from the simulation. Body scale is limited to standard proportions so physics is the same for everyone. A "stickman mode" setting remains for clarity and clips.

## 7. Multiplayer vision (built later, designed for now)

- **Sandbox servers** of about 15–20 players with shared equipment. Players pass through each other, so there's no griefing and bars can be shared.
- Slow-mo and moon gravity are per-player in the sandbox. Others see you in slow motion. They're locked in competitive modes.
- Later modes (not designed yet): trick battles, regrab chains / floor-is-lava, courses. Modes that need precise player-vs-player physical contact are avoided, because network latency makes them feel bad in any architecture.

## 8. Prototype scope

**In:**
- one character (stickman) and one bar
- Arch, Tuck (Pike)
- Let Go, intentional Grab, regrab
- Twist left and right
- basic side camera
- Reset, with auto-reset after a fall
- touch, keyboard and gamepad input
- debug and tuning panel, debug overlay, session log

**Out:**
- shops, lobby, progression, monetization, cosmetics, quests, game modes
- maps (beyond the floor and one bar), avatars, multiplayer, landings, crash ragdoll
- replays, trick detection and scoring, any UI beyond the controls and debug tools

## 9. Design concerns and proposed alternatives

| # | Concern with the requested design | Why it matters | Proposal |
|---|---|---|---|
| 1 | **6 action buttons + Reset on mobile** (Arch, Tuck, Let Go, Grab, Twist L, Twist R) | Two thumbs; the more buttons, the more mis-presses and hunting | Keep the dedicated buttons (Layout A) as default. Also build Layout B (combined HANDS) and A/B test it. Because Let Go and Grab are never valid at the same time, mis-presses between them are harmless. |
| 2 | **Hold-to-grab would make catching automatic in practice** | If holding counted, players would hold Grab all the time | Press-only attempts plus a cooldown after a miss (§5). `hold` exists only as a debug/accessibility switch. |
| 3 | **Touch latency and low frame rates** vary by phone (input is frame-quantized, ±16 ms at 30 fps) | Tight windows feel random on weak phones | Time-based windows ≥ 2 frames at 30 fps, a swept proximity test, and late-grab rollback grace. Test per device. |
| 4 | **Momentum transfer / release boost above 1.0** (requested as tunables) | Regrab chains can gain energy forever (an exploit and broken physics) | Allowed but flagged in the panel, and always limited by an energy cap (`maxSwingSpeed`) |
| 5 | **Real avatars** have different proportions and big accessories | Unfair physics; hands not visibly on the bar; clutter | Fixed gameplay skeleton, standard R15 scaling, arm IK onto the bar, stickman mode |
| 6 | **Vertical TikTok clips vs landscape controls** | Six buttons fit landscape far better | Play in landscape. Later, add a vertical "clip camera" and recording tool instead of portrait gameplay. |
| 7 | **Twist behavior**: the original uses tap-to-spin (momentum); hold-to-spin may be easier on touch | Affects how controllable twists feel | Both are built (`twistMode`); the playtests decide |

## 10. Open questions for you

1. Which phones and tablets do you have for testing? We need at least one low-end Android as the performance reference.
2. Do you have the original game installed? Short screen recordings of a basic swing, a release and regrab, a tuck flip and a twist would be reference material for tuning.
3. Landscape for gameplay: OK?
4. Any preference between hold-style and tap-style twist, or leave it to playtests?
