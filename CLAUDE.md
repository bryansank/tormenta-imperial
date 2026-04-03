# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Tormenta Imperial** is a dieselpunk management + turn-based strategy game built in Godot 4.6 .NET. The player builds and manages a persistent base on a procedurally generated island, progressing through 3 economic eras toward Imperial Victory. Combat (PVE/PVP turn-based) is planned but not yet implemented.

> "On the mud of history, we shall build monuments of steel."

## Tech Stack

- **Engine:** Godot 4.6 .NET Edition (Forward+ renderer)
- **Languages:** GDScript (UI, camera, input, services, scene management) / C# (planned: unit AI, combat, pathfinding)
- **Backend:** Supabase (planned: PostgreSQL, Auth, Edge Functions)
- **Multiplayer:** Nakama (planned: self-hosted Docker, for PvP and Co-op)

## Running the Project

1. Open the project folder in **Godot 4.6 .NET Edition**
2. Press **F5** to run
3. WASD to pan camera, scroll to zoom, middle-click to drag-pan
4. Touch: single finger drag to pan, two-finger pinch to zoom
5. **Important:** Delete save file to test fresh economy: `user://save_game.json`

---

## Architecture: Service-Signal-Component

All systems communicate through **EventBus** signals. No direct references between producers and consumers.

### Data Flow Pattern

```
Raw Input -> InputService -> EventBus.signal -> Consumer (Camera, Buildings, UI)
Services emit signals on EventBus. Scene components subscribe.
No service references another directly -- only through EventBus.
```

### Autoload Services (registered in project.godot, load order matters)

| # | Service | File | Purpose |
|---|---------|------|---------|
| 1 | `Tr` | `scripts/services/Tr.gd` | i18n translation (ES/EN) |
| 2 | `GameConfig` | `scripts/services/GameConfig.gd` | All tunable values, balance, durations |
| 3 | `EventBus` | `scripts/services/EventBus.gd` | Global signal bus (~25 signal categories) |
| 4 | `InputService` | `scripts/services/InputService.gd` | Unified input: keyboard, mouse, touch |
| 5 | `GridManager` | `scripts/grid/GridManager.gd` | 25x25 cell grid, building/obstacle placement |
| 6 | `ResourceManager` | `scripts/services/ResourceManager.gd` | 4 resources (gold/steel/oil/wood) + unlock system |
| 7 | `GameManager` | `scripts/services/GameManager.gd` | Save/load, new game, offline progression |
| 8 | `ProcessManager` | `scripts/services/ProcessManager.gd` | Timed manual processes (manufacturing, mining) |
| 9 | `ProductionManager` | `scripts/services/ProductionManager.gd` | Passive production, construction, upgrades |
| 10 | `ProgressionManager` | `scripts/services/ProgressionManager.gd` | Era system (3 eras), 9 milestones, victory |
| 11 | `MarketManager` | `scripts/services/MarketManager.gd` | Buy/sell resources with floating prices |
| 12 | `PopulationManager` | `scripts/services/PopulationManager.gd` | Population, workers, morale, consumption |
| 13 | `RandomEventManager` | `scripts/services/RandomEventManager.gd` | Random events (storms, plagues, festivals...) |

### Scene Tree (Main.tscn)

```
Main (Node3D)
  +-- MonumentalCamera (Camera3D)
  +-- DirectionalLight
  +-- WorldEnvironment
  +-- IslandGenerator (Node3D) -- procedural island mesh
  +-- GridOverlay (MeshInstance3D) -- debug grid (hidden)
  +-- BuildingPlacer (Node3D) -- handles placement/move/demolish
  +-- OnScreenControls (CanvasLayer) -- mobile D-pad, zoom, rotate
  +-- ResourceHUD (CanvasLayer) -- top bar: gold/steel/oil/wood
  +-- MapGenerator (Node) -- spawns 15-25 resource deposits
  +-- ConstructionMenu (CanvasLayer) -- build button + building list
  +-- BuildingInfoPanel (CanvasLayer) -- right panel: selected building info
  +-- MarketPanel (CanvasLayer) -- buy/sell UI
  +-- ProgressPanel (CanvasLayer) -- milestones + era display
  +-- VictoryScreen (CanvasLayer) -- victory overlay
  +-- NotificationPanel (CanvasLayer) -- activity log + toasts + status
```

---

## Game Systems

### Economy: 3-Era Progression

| Era | Name | Resources | Unlocked by |
|-----|------|-----------|-------------|
| 1 | Frontier | Gold, Wood | Game start |
| 2 | Industrial | + Steel | Build first Foundry |
| 3 | Petroleum | + Oil | Build first Refinery |

- Starting resources: 300 gold, 200 wood
- Deposits visible from start but locked until era unlocks the resource
- Storage: 800 base + 400/warehouse (max 3 warehouses)

### Resources

| Resource | Role | Starting | Unlock |
|----------|------|----------|--------|
| Gold | Universal currency, wages | 300 | Era 1 |
| Wood | Construction, heating | 200 | Era 1 |
| Steel | Advanced construction | 0 | Era 2 (Foundry) |
| Oil | Late-game construction | 0 | Era 3 (Refinery) |

### Buildings (14 total)

| Building | Size | Cost (G/S/O/W) | Workers | Production | Era |
|----------|------|-----------------|---------|------------|-----|
| Nucleo (core) | 3x3 | Free | 0 | 3 gold/20s | - |
| House | 1x1 | 50/0/0/30 | 0 | +6 pop capacity | 1 |
| Sawmill | 2x1 | 80/0/0/50 | 2 | 6 wood/12s | 1 |
| Gold Mine | 2x2 | 120/0/0/80 | 3 | 8 gold/12s | 1 |
| Warehouse | 1x1 | 60/0/0/40 | 1 | +400 storage | 1 |
| Foundry | 2x1 | 200/0/0/120 | 3 | 5 steel/15s | 1->2 |
| Barracks | 2x2 | 250/100/0/80 | 3 | (planned) | 2 |
| Refinery | 2x2 | 300/150/0/100 | 4 | 4 oil/18s | 2->3 |
| Tower | 1x1 | 150/60/20/30 | 1 | (planned) | 2-3 |
| HQ (capstone) | 2x2 | 500/300/200/200 | 5 | 10 gold/20s | 3 |
| Road | 1x1 | 10/0/0/5 | 0 | +2 morale | deco |
| Garden | 1x1 | 30/0/0/20 | 0 | +5 morale | deco |
| Fountain | 1x1 | 60/20/0/10 | 0 | +7 morale | deco |
| Statue | 1x1 | 120/40/0/0 | 0 | +10 morale | deco |

**Key constraint:** Foundry costs 0 steel (it unlocks steel). Refinery costs 0 oil (it unlocks oil).

### Population & Workers

- **PopulationManager** tracks: population, max capacity, used workers, morale
- Nucleo provides 5 starting pop capacity. Houses provide 6 each
- Each production building requires workers (see table above)
- Population grows +1 per tick (20s) if morale > 30 and housing available
- **Consumption:** Each pop consumes 1 wood + 1 gold per 30s tick
- If can't pay: morale drops -8/tick. If paid: morale recovers +3/tick

### Morale (0-100)

- Starts at 75. Affects production speed: `0.5x at 0 morale, 1.0x at 50, 1.2x at 100`
- Decorations add passive morale recovery (+1 per 10 bonus points per tick)
- Below 30 morale: population stops growing
- Below 20 morale: danger notification

### Market (Imperial Exchange)

- Gold is the currency. Buy/sell wood, steel, oil for gold
- Floating prices with 30% spread (buy higher, sell lower)
- Price base: wood=3, steel=8, oil=12 gold/unit
- Buying raises price, selling lowers it, mean-reversion over time
- Price range: 0.5x to 2.5x base

### Random Events (8 types)

| Event | Type | Effect |
|-------|------|--------|
| Storm | Danger | Lose 20-50 wood |
| Resource Find | Positive | Gain 30-80 random resource |
| Mining Accident | Danger | Lose 1 pop, -15 morale |
| Trade Caravan | Positive | Gain 50-120 gold |
| Festival | Positive | +20 morale |
| Plague | Danger | -25 morale, lasts 60s |
| Good Harvest | Positive | Gain 40-80 wood |
| Bandit Raid | Danger | Lose 30-80 gold, -10 morale |

Events fire every 2-5 minutes (15-30s in dev mode).

### Victory Conditions (9 milestones)

| Milestone | Condition |
|-----------|-----------|
| Pioneer | Build Sawmill |
| Prospector | Build Gold Mine |
| Stockpiler | Build Warehouse |
| Industrialist | Build Foundry (Era 2) |
| Oil Baron | Build Refinery (Era 3) |
| Merchant | Complete 10 market trades |
| Commander | Build Barracks + 2 Towers |
| General | Build Headquarters |
| **Imperial Victory** | **HQ Level 3** |

HQ upgrade costs: L2 = 800g/500s/300o/400w, L3 = 1500g/800s/500o/700w

### Save/Load System

- Path: `user://save_game.json`
- Saves: resources, buildings (level, name, construction state), deposits, camera, progression, market, population, events, unlock state
- Auto-saves on: building placed/moved/renamed/demolished, deposit depleted
- Offline progression: calculates production earned while game closed (max 8h)

---

## Project Structure

```
tormenta-imperial/
+-- project.godot                    # Engine config, 13 autoloads
+-- CLAUDE.md                        # THIS FILE - AI guidance
+-- readme.md                        # Full game documentation
+-- scenes/
|   +-- main/Main.tscn              # Entry scene
|   +-- buildings/BuildingPlacer.tscn
|   +-- ui/
|       +-- BuildingInfoPanel.tscn
|       +-- ConstructionMenu.tscn
|       +-- MarketPanel.tscn
|       +-- NotificationPanel.tscn
|       +-- OnScreenControls.tscn
|       +-- ProgressPanel.tscn
|       +-- ResourceHUD.tscn
|       +-- VictoryScreen.tscn
+-- scripts/
|   +-- buildings/BuildingData.gd    # Resource class for building definitions
|   +-- camera/MonumentalCamera.gd   # Orthographic 45deg RTS camera
|   +-- grid/GridManager.gd          # 25x25 cell grid
|   +-- map/
|   |   +-- IslandGenerator.gd      # Procedural island mesh
|   |   +-- MapGenerator.gd         # Random deposit spawning
|   +-- services/                    # ALL autoload singletons
|   |   +-- EventBus.gd             # ~25 signal categories
|   |   +-- GameConfig.gd           # All balance/tuning values
|   |   +-- GameManager.gd          # Save/load/lifecycle
|   |   +-- InputService.gd         # Input abstraction
|   |   +-- MarketManager.gd        # Buy/sell with floating prices
|   |   +-- PopulationManager.gd    # Pop, workers, morale, consumption
|   |   +-- ProcessManager.gd       # Timed processes (crafting, mining)
|   |   +-- ProductionManager.gd    # Passive production, construction
|   |   +-- ProgressionManager.gd   # Eras, milestones, victory
|   |   +-- RandomEventManager.gd   # Random events system
|   |   +-- ResourceManager.gd      # 4 resources + unlock tracking
|   |   +-- Tr.gd                   # i18n (ES/EN)
|   |   +-- FloatingText.gd         # Static utility: animated 3D text labels
|   +-- ui/
|       +-- BuildingInfoPanel.gd
|       +-- ConstructionMenu.gd
|       +-- MarketPanel.gd
|       +-- NotificationPanel.gd
|       +-- OnScreenControls.gd
|       +-- ProcessActionsPanel.gd
|       +-- ProgressPanel.gd
|       +-- ResourceHUD.gd
|       +-- VictoryScreen.gd
+-- data/buildings/                  # 14 .tres building definitions
|   +-- nucleo.tres, house.tres, sawmill.tres, gold_mine.tres,
|   +-- warehouse.tres, foundry.tres, barracks.tres, refinery.tres,
|   +-- tower.tres, headquarters.tres, road.tres, garden.tres,
|   +-- fountain.tres, statue.tres
+-- assets/models/buildings/         # 3D models (nucleo has one)
```

---

## Code Conventions

| Context | Convention | Example |
|---------|-----------|---------|
| GDScript vars/funcs | `snake_case` | `_handle_keyboard()` |
| C# classes | `PascalCase` | `UnitController.cs` |
| C# private fields | `_camelCase` | `_targetZoom` |
| Scenes | `PascalCase.tscn` | `Main.tscn` |
| Signals | `snake_case` | `camera_pan_requested` |
| Resources | `snake_case.tres` | `gold_mine.tres` |
| Translation keys | `UPPER_SNAKE` | `LBL_MORALE`, `EVENT_STORM` |

### Key Rule: C# vs GDScript

- **C#** for performance-sensitive: unit AI, combat math, pathfinding, network serialization
- **GDScript** for everything else: UI, camera, input, services, scene management, signal wiring

### Adding a New Building

1. Create `data/buildings/my_building.tres` with BuildingData fields
2. Add limit in `GameConfig.building_limits`
3. Add prerequisites in `GameConfig.building_prerequisites` (if any)
4. Add processes in `GameConfig.building_processes` (if any)
5. Add translations in `Tr.gd` (both ES and EN)
6. Building auto-appears in ConstructionMenu (loads all .tres from data/buildings/)

### Adding a New Signal

1. Add to `EventBus.gd` under the appropriate category
2. Emit from the producing service
3. Connect from consuming service/UI in `_ready()`

### Tuning Economy

All balance values live in `GameConfig.gd`:
- `starting_resources` - initial amounts
- `building_processes` - manual crafting recipes with margins
- `mining_data` - deposit yields and durations
- `market_*` - market prices, spread, volatility
- `upgrade_cost_multiplier` / `upgrade_production_multiplier`
- `hq_upgrade_costs` - capstone building costs
- `base_storage_cap` / `warehouse_storage_bonus`
- `morale_*` - morale thresholds, recovery/penalty rates
- `population_start` - initial population count
- `consumption_interval` / `growth_interval` - tick timings
- `event_interval_*` - random event timing ranges
- `resource_colors` - display colors for floating text

### Shared Utilities

- **FloatingText** (`scripts/services/FloatingText.gd`): Static class for spawning animated 3D text labels. Use `FloatingText.spawn()` for custom text or `FloatingText.spawn_resource()` for resource gain/loss display. Colors come from `GameConfig.resource_colors`.

### Dev Mode

`GameConfig.dev_mode = true` makes all durations 1-2 seconds for rapid testing. Set to `false` for real timings.

---

## Planned (Not Yet Implemented)

- **Turn-based combat PVE:** Tactical grid, units from barracks, attack/defend/move
- **Turn-based PVP:** Attack other player's base with your army (Nakama)
- **Tech tree:** 3 branches (Industrial, Military, Logistics), 15 techs
- **Supabase integration:** Cloud saves, authentication
- **Unit system:** Infantry, artillery, vehicles produced from barracks
- **Missions/contracts:** Timed delivery challenges for rewards
