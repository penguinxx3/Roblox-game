# Bar Gymnastics — Roblox

A mobile-first Roblox physics gymnastics sandbox, seen from the side: pump a swing, let go, flip and twist, and **intentionally** catch the next grip.

**Current phase: Phase 0 — architecture and design (v2, revised after the reference-clip study), awaiting approval.** No game code yet.

This repository is the source of truth for the project.

| Document | What it answers |
|---|---|
| [GAME_PLAN.md](GAME_PLAN.md) | What we're building, controls per platform, prototype scope, design concerns, open questions |
| [REFERENCE_ANALYSIS.md](REFERENCE_ANALYSIS.md) | What the reference clips show (swing, momentum, catches, camera, modifiers), measured targets, and what we must not copy |
| [TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md) | Native vs custom vs hybrid comparison, the recommended planar-core architecture, prototype code layout, multiplayer, avatar and anti-exploit plans, risks |
| [PHYSICS_DESIGN.md](PHYSICS_DESIGN.md) | 5-body planar model, compliant motors, the solver, release and flight, twist, the intentional catch system, time scale and gravity, all tuning parameters |
| [TESTING.md](TESTING.md) | How we measure whether the movement is actually good (automated, reference comparison, devices, playtests) and the exit gate |
| [ROADMAP.md](ROADMAP.md) | Phases, milestones, exit criteria, decisions log |

How to build and run will be added with the prototype (Phase 1): a Rojo project that builds a `.rbxl` you open in Roblox Studio.
