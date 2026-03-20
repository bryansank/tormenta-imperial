# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Tormenta Imperial** is a hybrid strategy game: persistent base management (meta-game) + RTS combat, built in Godot 4.6 .NET with Dieselpunk aesthetics.

## Tech Stack

- **Engine:** Godot 4.6 .NET Edition (Forward+ renderer)
- **Languages:** C# (unit AI, combat, resources, pathfinding) / GDScript (UI, camera, input, scene management)
- **Backend:** Supabase (PostgreSQL, Auth, Edge Functions)
- **Multiplayer:** Nakama (self-hosted Docker, for PvP and Co-op modes)

## Running the Project

1. Open the project folder in **Godot 4.6 .NET Edition**
2. Press **F5** to run
3. WASD to pan camera, scroll to zoom, middle-click to drag-pan
4. Touch: single finger drag to pan, two-finger pinch to zoom

## Architecture: Service-Signal-Component

All systems communicate through **EventBus** signals. No direct references between producers and consumers.

### Autoload Services (registered in project.godot)

| Service | File | Purpose |
|---|---|---|
| `EventBus` | `scripts/services/EventBus.gd` | Global signal bus — all inter-system communication |
| `InputService` | `scripts/services/InputService.gd` | Unified input: keyboard, mouse, touch → EventBus signals |

Planned autoloads: `GameManager`, `ResourceManager`, `NetworkManager`.

### Data Flow Pattern

```
Raw Input → InputService → EventBus.signal → Consumer (Camera, Units, UI)
```

Services emit signals on EventBus. Scene components subscribe. No service references another service directly — only through EventBus.

### Key Files

- `scripts/services/EventBus.gd` — Add new signal categories here as systems grow
- `scripts/services/InputService.gd` — All input handling (keyboard/mouse/touch)
- `scripts/camera/MonumentalCamera.gd` — Orthographic 45° RTS camera, subscribes to EventBus
- `scenes/main/Main.tscn` — Entry scene with camera, lighting, ground, placeholder house

### Three Game Layers

1. **Base Management** — persistent between sessions, grid-based building, saved to Supabase
2. **RTS Combat** — 3 modes: AI vs Player (offline), PvP (Nakama), Co-op vs AI (Nakama)
3. **Tech Tree** — 3 branches (Industrial, Military, Logistics), 15 techs

### Code Conventions

| Context | Convention |
|---|---|
| C# classes | `PascalCase` |
| C# private fields | `_camelCase` |
| GDScript vars/funcs | `snake_case` |
| Scenes | `PascalCase.tscn` |
| Sprites | `unit_<type>_<action>_<frame>.png` |
| Signals | `snake_case` |
| Resources | `snake_case.tres` |

### Key Rule: C# vs GDScript

Use **C#** for anything performance-sensitive or logic-heavy: unit AI, combat math, resource calculations, network serialization, pathfinding.

Use **GDScript** for UI, camera, input services, scene transitions, signal wiring, and audio management.

## Full Documentation

The **readme.md** contains the full project documentation: architecture diagrams, resource lists, autoload registry, naming conventions, roadmap, and getting started guide.
