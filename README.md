# Bar Gymnastics — Roblox

A mobile-first Roblox physics gymnastics sandbox, seen from the side: pump a swing, let go, flip and twist, and **intentionally** catch the next grip.

**Current phase: Phase 1 — P1.1 physics foundation built and tested headlessly.** Studio validation and human look-and-feel checks are pending ([STUDIO_VALIDATION.md](STUDIO_VALIDATION.md)). P1.2 starts only after approval.

This repository is the source of truth for the project.

## Documents

| Document | What it answers |
|---|---|
| [GAME_PLAN.md](GAME_PLAN.md) | What we're building, controls per platform, prototype scope, design concerns |
| [REFERENCE_ANALYSIS.md](REFERENCE_ANALYSIS.md) | What the reference clips show, measured targets, and what we must not copy |
| [TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md) | Architecture (hybrid, planar custom core), code layout as built, multiplayer, avatar and anti-exploit plans, risks |
| [PHYSICS_DESIGN.md](PHYSICS_DESIGN.md) | Body model, solver as built, catch system spec, all tuning parameters |
| [TESTING.md](TESTING.md) | Test layers, P1.1 results, reference comparison, playtests, exit gate |
| [STUDIO_VALIDATION.md](STUDIO_VALIDATION.md) | The checklist for Roblox Studio |
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
| Headless tests (40) | `lune run tests/run.luau` (`--quick` skips slow tests; a name filter is optional) |
| Built-place self-test | `lune run tools/place_selftest.luau` (after building) |
| Headless client harness | `lune run tools/client_harness.luau` (after building) |
| Solver settings benchmark | `lune run tools/solver_bench.luau` |
| Format | `stylua src tests tools/*.luau` |
| Type-check (optional) | `rojo sourcemap default.project.json -o sourcemap.json --include-non-scripts`, then `luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions=@roblox=globalTypes.d.luau src` |

**In Studio:**
- Keys: **R** reset, **1–4** scene (Hang / Drop / Tumble / Wheel), **V** pose, **T** slow-mo, **G** moon gravity, **P** pause, **N** single step, **C** contact markers, **F2** overlay. The same actions are buttons at the top right.
- Physics constants are live-editable as attributes on `ReplicatedStorage.GymTuning` (client view) during Play.

## Code layout

- `src/shared/Gym/` — the pure physics core (no Roblox types; also runs headless).
- `src/shared/GymTests/` — test specs, shared by Lune and Studio.
- `src/client/` — presentation and debug tools only.
- `src/server/` — the Studio self-test on Play.

Details: TECHNICAL_DESIGN §6.
