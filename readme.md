# Tormenta Imperial

**Tormenta Imperial** is a hybrid strategy title developed in **Godot 4.6 .NET**. It combines heroic realism and *Dieselpunk* aesthetics with real-time strategy (RTS) gameplay and a persistent monumental base management system.

> "On the mud of history, we shall build monuments of steel."

---

## Project Pillars

### 1. Aesthetics: Heroic Realism & Vintage Futurist
* **Monumentalism:** Massive neoclassical architecture symbolizing power and stability.
* **Iconography:** Deep use of imperial symbols (eagles, gears, iron laurels).
* **Environment:** Sharp contrast between the "Mud" (battlefield) and the "Steel" (technological stronghold).

### 2. Base Management (Meta-Game)
* **Persistent Growth:** Your base evolves outside of matches. Upgrades unlock new units for combat.
* **War Economy:** 12 resources in 4 categories:
  * **Production:** Iron, Fuel, Coal/Wood, Steel
  * **Human:** Population, Recruits, Engineers
  * **Strategic:** Ammunition, Mech Parts, Blueprints
  * **Territory:** Controlled Territories, Supply Points
* **Research Tree:** 3 branches (Industrial, Military, Logistics), 15 techs, gated by Command Center tier.

### 3. RTS Combat (Competitive)
* **3 Game Modes:** AI vs Player (offline), Player vs Player (Nakama), Players vs AI co-op (Nakama).
* **Tactical Strategy:** Micro and macro unit management on 3D maps with orthographic camera.
* **Smart AI:** Enemies utilize cover, flanking maneuvers, and tactical retreats.
* **Ranking System:** Competitive matchmaking based on faction power and player skill.

---

## Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| Engine | Godot 4.6 .NET Edition | Game engine (Forward+ renderer) |
| Logic | C# | Unit AI, combat, resources, pathfinding |
| Scripting | GDScript | UI, camera, input, scene management |
| Backend | Supabase | PostgreSQL, Auth, Edge Functions |
| Multiplayer | Nakama (Docker) | PvP and Co-op sessions |
| IDE | VS Code + C# Dev Kit | Development environment |

### Required Tools
* **Godot 4.6 .NET Edition**
* **.NET SDK 8.0+**
* **Docker** (for Nakama multiplayer — optional for solo development)

---

## Architecture: Service-Signal-Component

The project uses a **Service-Signal-Component** pattern native to Godot:

```
┌─────────────────────────────────────────────────────┐
│                   Autoload Services                  │
│  EventBus · InputService · GameManager · ResourceMgr │
└──────────────────────┬──────────────────────────────┘
                       │ signals (EventBus)
┌──────────────────────▼──────────────────────────────┐
│                   Scene Components                   │
│  MonumentalCamera · Units · Buildings · UI Panels    │
└─────────────────────────────────────────────────────┘
```

### Core Patterns

| Pattern | Where | Why |
|---|---|---|
| **Autoload Singletons** | `scripts/services/` | Global services accessible from any scene |
| **EventBus (Signal Bus)** | `EventBus.gd` | Decoupled communication — emitters don't know subscribers |
| **Scene Composition** | `scenes/` | Complex behaviors built from simple node components |
| **State Machines** | Game states, unit AI | Menu → Base → Combat → Results transitions |

### Data Flow Example: Input → Camera

```
[Keyboard/Mouse/Touch]
        │
   InputService.gd        ← reads raw input, normalizes it
        │
   EventBus.camera_*      ← emits abstract signals (pan, zoom, drag)
        │
   MonumentalCamera.gd    ← subscribes and moves camera
```

**Key rule:** Input producers (InputService) never reference consumers (Camera). Communication flows only through EventBus signals.

### Language Split: C# vs GDScript

| Use C# for | Use GDScript for |
|---|---|
| Unit AI & behavior trees | UI scenes & menus |
| Combat math & damage calc | Camera & input services |
| Resource calculations | Scene transitions |
| Network serialization | Signal wiring & glue code |
| Pathfinding algorithms | Audio management |

---

## Project Structure

```
tormenta-imperial/
├── project.godot              # Engine config (autoloads, display, rendering)
├── scenes/
│   ├── main/Main.tscn         # Entry scene: 3D world, camera, lighting
│   ├── base/                  # Base management scenes
│   ├── combat/                # RTS combat scenes
│   └── ui/                    # UI overlay scenes
├── scripts/
│   ├── services/              # Autoload singletons (GDScript)
│   │   ├── EventBus.gd        # Global signal bus
│   │   └── InputService.gd    # Unified input: keyboard/mouse/touch
│   └── camera/
│       └── MonumentalCamera.gd # Orthographic 45° RTS camera
├── src/
│   ├── core/                  # C# performance-critical systems
│   └── ui/                    # C# UI controllers (if needed)
└── assets/
    ├── sprites/               # unit_<type>_<action>_<frame>.png
    ├── audio/                 # SFX and music
    └── fonts/                 # UI typefaces
```

### Naming Conventions

| Context | Convention | Example |
|---|---|---|
| C# classes | `PascalCase` | `UnitController.cs` |
| C# private fields | `_camelCase` | `_targetZoom` |
| GDScript vars/funcs | `snake_case` | `_handle_keyboard()` |
| Scenes | `PascalCase.tscn` | `Main.tscn` |
| Sprites | `unit_<type>_<action>_<frame>.png` | `unit_tank_idle_01.png` |
| Signals | `snake_case` | `camera_pan_requested` |
| Resources | `snake_case.tres` | `iron_config.tres` |

---

## Autoload Services (Registered in project.godot)

| Service | File | Status | Responsibility |
|---|---|---|---|
| `EventBus` | `scripts/services/EventBus.gd` | Active | Global signal hub for decoupled communication |
| `InputService` | `scripts/services/InputService.gd` | Active | Keyboard, mouse, and touch input abstraction |
| `GameManager` | — | Planned | State machine: Menu → Base → Combat → Results |
| `ResourceManager` | — | Planned | 12 resources, production rates, storage limits |
| `NetworkManager` | — | Planned | Supabase auth + Nakama multiplayer sessions |

---

## Current Input Controls

| Action | PC | Mobile |
|---|---|---|
| Pan camera | WASD / Arrow keys | Single finger drag |
| Pan camera (alt) | Middle mouse drag | — |
| Zoom in/out | Scroll wheel | Two-finger pinch |

---

## Roadmap (Phase 1: Foundations)

### Week 1: Infrastructure
- [x] Repository setup and project configuration
- [x] **Monumental Camera:** Orthographic 45° view with zoom, pan, boundary limits
- [x] **Input System:** Unified keyboard/mouse/touch via Service-Signal architecture
- [ ] Initial **Supabase** auth integration

### Week 2: Combat Basics
- [ ] Rectangle drag-selection system
- [ ] Unit pathfinding (NavigationAgent3D)
- [ ] Initial assets: "Imperial Eagle" icon and "Light Tank" prototype

### Week 3: Base Operations
- [ ] Grid-based building placement system
- [ ] "Vintage Military" UI construction menu
- [ ] State persistence (cloud-saving base configuration via Supabase)

---

## Getting Started

1. **Install Prerequisites:** Godot 4.6 .NET Edition + .NET SDK 8.0+
2. **Clone:** `git clone <repo-url>`
3. **Environment:** Create `.env` in root with Supabase keys (template coming soon)
4. **Run:** Open in Godot → press `F5`
5. **Controls:** WASD to pan, scroll to zoom, middle-click drag to pan

---

## License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

---

*Multiplayer features (Nakama/Docker) are in the research phase.*
