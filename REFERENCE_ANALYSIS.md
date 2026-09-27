# Reference Clip Analysis

Purpose: extract **movement and physics behavior** from gameplay clips of the original mobile game, so that our own implementation can reach the same (or better) feel. These clips are references only. No assets, artwork, UI, names or level designs are copied (see §6).

Method:
- Frames extracted at 2 fps for overviews, then 10–30 fps around every release and catch.
- Full-resolution stills were used for hand, body and equipment details.
- The camera in gameplay footage doesn't rotate, so rotation rates are measured directly from body orientation per frame. Translation measurements are rough, because the camera follows the player.

Confidence tags: **[O]** observed directly · **[I]** inferred from motion · **[?]** can't be determined from video.

## 1. Clips

| ID | File (upload) | Length | Content |
|---|---|---|---|
| R0 | `5ef3c7f1-…mp4` | 18 s | Pole and stub regrab chain; "Slow Mo + Moon Gravity" modifiers active |
| R1 | `71477c88-ssstik…` | 18 s | Long regrab chain: poles, stubs, a scaffold frame; ends standing on a ledge |
| R2 | `8929a79d-…mp4` | 22 s | Pole-top regrabs with flips and twists, clearest catch footage; ends landing by a wall |
| R3 | `5131d24e-snaptik…mp4` | 10.5 s | Raw 20:9 landscape phone recording, "Slow Mo": regrabs on **rotating spoked wheels** |
| R4 | `b94ede2e-…mp4` | 27 s | Played back in the original's **replay viewer** (speed, pause, restart, save, timeline); angled beams, handstand on a pillar |
| R5 | `c3f7f991-…mp4` | 12 s | "Moon Gravity": **ground movement**: standing jump, flips, handspring, landing on and jumping off blocks |

## 2. Findings by topic

### 2.1 The game is planar (2.5D)
- **[O]** Every gameplay-camera shot is a fixed side view with no camera roll. Equipment and blocks line up in one plane, and the character never moves toward or away from the camera.
- **[I]** The center of mass and the swing stay in a single vertical plane. The world and the character are rendered in 3D, and **twist** is visibly a 3D rotation around the body's long axis: in R2 at 0.67–1.07 s and 2.60–2.97 s the flat face of the torso turns toward the camera.
- Consequence: gameplay is a **2D physics problem with a 3D twist and render layer**, not full 3D flight.

### 2.2 Body
- **[O]** Box-shaped rigid torso with a sphere head, capsule limbs, and L-shaped feet. Left and right limbs always move together as pairs.
- **[O]** The arms stay straight in nearly every frame. Elbows are either absent or never visibly bend.
- **[O]** The knees bend a lot (tuck), and the ankles hold the feet at about 90°.
- **[O]** The spine never bends. Arch comes entirely from the shoulders and hips (R5 5.1–5.3 s: a "banana" layout made from shoulder and hip extension).
- **[O]** The limbs are **compliant**: legs dangle and flex slightly under swing loads (R2 1.93 s, R3 2.4–2.6 s), and limbs lag and settle after quick shape changes. They are not rigid prescribed poses.

### 2.3 Swinging and momentum
- **[O] Grip points are mostly points, not long bars:**
  - tops of vertical poles
  - short stubs sticking out of poles
  - ends of angled beams (R4)
  - rods of a scaffold frame (R1 6.5–9.5 s)
  - spoke tips of rotating wheels (R3)
- **[O]** The body swings freely through 360° around the grip point, including full giants over the top of pole tips (R2 0.0–0.6 s).
- **[O]** Grips at pole tops show a **swivel handle** that turns with the hands and stays where it was left after release (R2 2.47→2.50 s). It's a visual identity element (§6); physically it behaves like a point pivot at the hands.
- **[O] Measured (R2 1.47–2.48 s):**
  - catch with the body horizontal on one side
  - hanging straight down after ~0.36–0.46 s
  - past horizontal on the far side after ~0.8 s
  - release ~0.9 s after the catch
- **[I]** Very little energy is lost per swing. The swing after a catch reaches about the height it was caught at.

### 2.4 Arch, Tuck, Pike
- **[O] Tuck:** knees to chest (hips and knees flexed), a compact "box" silhouette.
- **[O] Pike:** hips folded with the legs straight (R2 2.40 s, often just before release).
- **[O] Arch:** shoulders and hips extended (R5 5.1–5.3 s).
- **[O] Spin rate follows body shape** (R2, same flight): open/pike ≈ half a turn in 0.43 s (**≈1.15 rev/s**); tight tuck ≈ half a turn in 0.27 s (**≈1.85 rev/s**). The ratio is ≈1.6×, which is consistent with conserved angular momentum.
- **[I]** On the bar, shape changes pump or keep the swing going: catches are followed by full swings without visible loss.

### 2.5 Release and transition to flight
- **[O]** Typical release is on the upswing, past horizontal, often from a pike (R2 2.40–2.48 s).
- **[O]** At release the hands simply open. There's **no pose pop and no speed jump**: the body continues in the same rotation direction (clockwise before and after in R2) and flies off along the tangent.
- **[O]** After release the player reshapes the body (pike → tuck) to speed up the spin.

### 2.6 Regrab timing, hand positioning, forgiveness
- **[O]** In every catch the **arms are extended toward the grip point before contact**: the hands lead, reaching overhead or forward (R2 1.20–1.47 s).
- **[O]** The catch happens when the hands **arrive at** the grip point. The last frame before attachment has the hands within about a hand's length of it, and there's **no visible snap or teleport** (R2 1.43→1.47 s).
- **[O]** Both hands always grip together at one point. There's no one-hand catch anywhere.
- **[O]** Catches happen mid-twist and mid-rotation (R2, R1). The body just needs its arms pointing at the grip.
- **[O]** Chain cadence: about **1 regrab per 1–1.5 s** at normal speed (R1: 1,262 @2.5 s → 1,263 @3.0 → 1,264 @4.0). In slow-mo it's about 2.6 s (R3). Pole-to-pole flight is **≈0.9 s** (R2 0.60 → 1.47 s).
- **[?]** The clips can't show whether a button was pressed at the catch. Both "catch unless holding Let Go" and "press to catch" are consistent with the footage. The spatial tolerance clearly looks **small** (hands visibly on the grip); forgiveness, if any, must come from timing, not from a large radius.

### 2.7 Momentum retained after a regrab
- **[O]** The rotation continues in the same direction through the catch, with no visible drop in angular speed (R2 1.43 → 1.67 s).
- **[I]** Close to full angular-momentum retention about the grip point: roughly ≥ 90%, judged from the swing height reached afterwards.

### 2.8 Successful vs failed catches
- **[O] Successful:** the arms lock onto the grip, and the body carries on around it with the limbs lagging slightly from compliance. There's **no hitstop, no camera shake and no flash**; the counter increments.
- **[?] Failed catches** don't appear (these are highlight edits). What the clips do show of ground contact is physical: falls, hand landings and foot landings (§2.10).

### 2.9 Camera
- **[O] Gameplay camera:**
  - side-on, perpendicular to the motion plane, with mild perspective
  - smooth follow in both axes with slight lag, keeping the character near the center
  - roughly constant zoom: character height ≈ 20–30% of screen height
  - no roll, no shake
- **[O] Replay camera (R4):** low oblique angles, rotated views, motion blur. It's cinematic and only used in replays.

### 2.10 Ground and surface interaction (not in our current plan)
- **[O] Standing "ready" pose:** crouched, arms forward (R0 6–8 s, R1 11.5 s, R5 0.0 s).
- **[O] Standing jump** into multiple flips: the arms swing up and the body extends (R5 0.2–0.5 s).
- **[O] Landing on feet** onto the floor and block tops, back into the ready pose (R5 2.9 s and 4.8 s, R4 12.0 s).
- **[O] Landing on hands:** handstand balance on a pillar top (R4 11.1–11.6 s), a handspring off the floor (R5 2.2–2.4 s), hands planted on a block top in a vault (R5 2.7 s).
- **[O] Body–world contact** is physical (resting across a block edge, R5 7.5 s). It isn't a scripted animation.
- The regrab counter doesn't count these contacts (R5 stays at 9).

### 2.11 Equipment
- **[O]**
  - static poles with pivot handles
  - stubs
  - angled beams
  - scaffold frames
  - **rotating wheels with spokes** that carry the player around and launch them on release (R3). Wheels also spin while empty, so they are driven or free-spinning.
  - blocks, pillars, walls, pits

### 2.12 Slow motion and gravity
- **[O]** The active modifiers are shown as a label ("Slow Mo", "Moon Gravity").
- **[O]** Slow Mo slows **the whole world uniformly**: the character *and* the wheels (R3).
- **[O]** Moon Gravity gives long, floaty flights: about 1.5 s of airtime from a standing jump with more than 2 somersaults (R5).

### 2.13 Replays and recording
- **[O]** The original has a **replay viewer** with speed control, pause, restart, save and a timeline (R4). Creators use it for clips.
- **[O]** The raw phone recording (R3) shows **no on-screen control buttons**, so buttons can be hidden or made invisible for clean recordings.

## 3. Why it feels fluid and satisfying (the targets)

1. **Unbroken momentum.** Release and catch never interrupt the motion. Rotation direction and speed flow straight through.
2. **Readable cause and effect.** Tuck spins visibly faster than an open body; a pike before release sets up the flip.
3. **Alive but controlled limbs.** Poses are held by springy joints that give a little under load.
4. **Hands lead the catch.** The arms reach for the target, and the grip lands exactly where the hands are.
5. **Fast rhythm.** A catch about every 1–1.5 s, and each one immediately becomes the next swing.
6. **Calm camera.** Steady side view, smooth follow, no shake. The motion itself is the spectacle.
7. **Modifiers change the whole world** (slow-mo, moon), which makes clips look cinematic.

## 4. Numbers to calibrate against (normal speed, normal gravity)

| Quantity | Reference | Source |
|---|---|---|
| Open/pike somersault rate | ≈ 1.1–1.2 rev/s | R2 2.67–3.10 s |
| Tight tuck somersault rate | ≈ 1.8–1.9 rev/s | R2 3.10–3.37 s |
| Tuck/open spin ratio | ≈ 1.6× | same |
| Pole-to-pole flight time | ≈ 0.85–0.95 s | R2 0.60–1.47 s |
| Catch → release (one swing through the bottom) | ≈ 0.9–1.0 s | R2 1.47–2.48 s |
| Catch at horizontal → hanging straight down | ≈ 0.35–0.45 s | R2 1.57–1.93 s |
| Regrab chain cadence | 1 per ≈ 1–1.5 s | R1, R2 counters |
| Momentum retained at catch | ≈ full (≥ 90%) | R2 1.43–2.40 s |
| Hand-to-grip distance on the last frame before attachment | ≲ 1 hand length | R2 1.43 s |

These are estimates from 30 fps video. They're good for "feels like", not for exact physics constants.

## 5. What this means for our design

Summarized here; each change is applied in the other documents.

| Finding | Impact on our design |
|---|---|
| Gameplay is planar (2.5D) | The core becomes **2D dynamics in a motion plane** plus a twist/render layer. Simpler, matches the reference, and needs no steering on mobile. |
| Limbs are compliant | Joint shapes are driven by **torque-limited spring motors**, not prescribed |
| Ground, hand-plant and contact interactions are core | The core needs **real contacts** with the world: land, stand, handstand, vault, jump. Contact is no longer "crash → hand off to native ragdoll". |
| Grip targets are points and in-plane rods, some moving | The catch system targets **points and segments in the plane**, including moving and rotating equipment |
| Feet matter (standing, landing) | Add a **foot** segment |
| No one-hand catches; arms always straight | Keep arms as one straight segment; one-hand catch stays deferred (low priority) |
| Catches look spatially tight and there's no snap | Smaller default `catchRange`; forgiveness comes from **time** windows + rollback, not a big radius |
| No hitstop or camera shake | Defaults: `catchHitstop = 0`, `camShakeOnCatch = 0`; feedback is sound, haptics and the chain counter |
| Slow-mo slows the whole world, equipment included | Equipment motion must be a deterministic function of sim time. Per-player slow-mo **conflicts with shared moving equipment in multiplayer** (flagged in TECHNICAL_DESIGN §6). |
| Replays with speed control drive clip creation | Record state from day one; replay tool moves to the top of Phase 2 |
| Clean recordings | A "hide controls" option (button opacity 0 with touch still active) |

## 6. What we must NOT copy

The mechanics shown (bar swinging, arch/tuck/pike, release, regrab, twist, slow-mo, low gravity, replays, rotating equipment) are generic gameplay ideas and fair to implement our own way. We will **not** reproduce the original's identity or implementation:

- **Name and wording:** the game's name, and the "Regrabs" counter label and its styling. We use our own term and HUD design. No modifier label text or placement cloned ("Slow Mo - Moon Gravity" at the bottom).
- **Character look:** the brown/grey stick figure with a box torso, ball head, capsule limbs and L-feet. We use Roblox avatars, and our own stylized "stickman mode" with different proportions and materials.
  - *P1.2 round 3, owner's decision:* the prototype figure moved toward the generic physics-dummy language the owner pointed to (block torso, ball head, slim limbs, block feet), because the drawn collision capsules looked clunky.
  - What stays ours: the teal / white / slate palette and SmoothPlastic look, a two-part chest and pelvis, a neck, capsule limbs with joint balls and hands, and our proportions.
  - What is not used: the reference's colours, its ellipsoid limb shapes, and its art direction.
- **Art direction:** the blue-gradient sky with those clouds, red floor, and grey blocks with dark sides. We build our own palette, materials and skybox.
- **Signature equipment designs:** white poles with grey swivel handles, red scaffold frames, and the red/grey cross-planked spoke wheels. Our equipment serves the same functions with our own look.
- **UI:** the replay viewer layout (speed selector, icons, timeline), the button layout and editor, menus, sounds and music.
- **Level layouts:** no recreated maps or sequences from the clips.
- **Code, data and tuning:** no decompiling, asset extraction or copying of constants from the app. Our values come from our own tuning against the targets in §4.
