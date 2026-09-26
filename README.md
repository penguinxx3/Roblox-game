# Bar Gymnastics — Roblox

A mobile-first Roblox physics gymnastics sandbox: pump a swing, let go, flip and twist, and **intentionally** catch the bar again.

**Current phase: Phase 0 — architecture and design, awaiting approval.** No game code yet.

This repository is the source of truth for the project.

| Document | What it answers |
|---|---|
| [GAME_PLAN.md](GAME_PLAN.md) | What we're building, controls per platform, prototype scope, design concerns, open questions |
| [TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md) | Native vs custom vs hybrid physics comparison, the recommended architecture, prototype code layout, multiplayer, avatar and anti-exploit plans, risks |
| [PHYSICS_DESIGN.md](PHYSICS_DESIGN.md) | Body model, hanging and flight dynamics, twist, the intentional catch system, time scale and gravity, every tuning parameter |
| [TESTING.md](TESTING.md) | How we measure whether the movement is actually good, and the prototype exit gate |
| [ROADMAP.md](ROADMAP.md) | Phases, milestones, exit criteria, decisions log |

How to build and run will be added with the prototype (Phase 1): a Rojo project that builds a `.rbxl` you open in Roblox Studio.
