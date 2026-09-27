# Bar Gymnastics — Roblox

A mobile-first Roblox physics gymnastics sandbox, seen from the side: pump a swing, let go, flip and twist, and **intentionally** catch the next grip.

**Current phase: Phase 1 — P1.2 movement control, after playtest feedback round 1.** P1.1 (physics foundation) is done and was playtested in Studio. P1.2 adds player control: Arch / Tuck / Pike, pumping, Let Go, Twist, standing, crouch-and-release jumping, landing, and keyboard / gamepad / touch input. The first P1.2 playtest's findings and the changes made are in [PLAYTEST_P1_2.md](PLAYTEST_P1_2.md); the next playtest checklist is [STUDIO_VALIDATION.md](STUDIO_VALIDATION.md). P1.3 (intentional grab and regrab) starts only after approval.

This repository is the source of truth for the project.

## Documents

| Document | What it answers |
|---|---|
| [GAME_PLAN.md](GAME_PLAN.md) | What we're building, controls per platform, prototype scope, design concerns |
| [REFERENCE_ANALYSIS.md](REFERENCE_ANALYSIS.md) | What the reference clips show, measured targets, and what we must not copy |
| [TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md) | Architecture (hybrid, planar custom core), code layout as built, multiplayer, avatar and anti-exploit plans, risks |
| [PHYSICS_DESIGN.md](PHYSICS_DESIGN.md) | Body model, solver as built, catch system spec, all tuning parameters |
| [TESTING.md](TESTING.md) | Test layers, P1.1 and P1.2 results, smoothness benchmark, known issues, reference comparison, playtests, exit gate |
| [STUDIO_VALIDATION.md](STUDIO_VALIDATION.md) | The checklist for Roblox Studio, including the blind motor A/B procedure |
| [PLAYTEST_P1_2.md](PLAYTEST_P1_2.md) | P1.2 playtest feedback: what was found under each point, what changed, what is still to decide |
| [ROADMAP.md](ROADMAP.md) | Milestones, status, decisions log |

## Build and run

Tools (versions in `rokit.toml`): `rokit install`, or from crates.io:
```
cargo install rojo lune selene --locked
cargo install stylua --locked --features luau
```

| Task | Command |
|---|---|
| Build the place | `rojo build -o build/BarGym.rbxl`, then open it in Roblox Studio and press Play |
| Live sync into Studio | `rojo serve`, then connect with the Rojo Studio plugin |
| Headless tests (63) | `lune run tests/run.luau` (`--quick` skips slow tests; a name filter such as `movement` is optional) |
| Built-place self-test | `lune run tools/place_selftest.luau` (after building; `--full` includes the slow soaks) |
| Headless client harness | `lune run tools/client_harness.luau` (after building) |
| Solver settings benchmark | `lune run tools/solver_bench.luau` |
| Smoothness benchmark | `lune run tools/smooth_bench.luau` |
| Flip and swing benchmark (playtest numbers) | `lune run tools/flip_bench.luau` |
| Format | `stylua src tests tools/*.luau` |
| Type-check (optional) | `rojo sourcemap default.project.json -o sourcemap.json --include-non-scripts`, then `luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions=@roblox=globalTypes.d.luau src` |

**In Studio:**
- Play: **A/←** Arch, **S/↓** Tuck (on the ground: crouch, release to jump), both = Pike, **W/↑** Let Go, **Q/E** Twist. Gamepad: LT/RT Arch/Tuck (analog), B Let Go, LB/RB Twist, Y Reset. Touch devices get a minimal button layout.
- Debug: **R** reset, **1–5** scene (Hang / Drop / Tumble / Wheel / Stand), **V** pose override, **T** slow-mo, **G** moon gravity, **P** pause, **N** single step, **C** contact markers, **B** blind A/B (Shift+B reveal), **F2** overlay. The same actions are buttons at the top right.
- Every tuning parameter is live-editable as an attribute on `ReplicatedStorage.GymTuning` (client view) during Play.

## Code layout

- `src/shared/Gym/` — the pure physics and movement core (no Roblox types; also runs headless): solver, rig, input frame, movement controller, simulation driver.
- `src/shared/GymTests/` — test specs, shared by Lune and Studio.
- `src/client/` — input routing, presentation and debug tools (never writes physics state).
- `src/server/` — the Studio self-test on Play.

Details: TECHNICAL_DESIGN §6.
