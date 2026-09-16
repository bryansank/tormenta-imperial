# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Tormenta Imperial** is a dieselpunk management + turn-based strategy game built in Godot 4.7 .NET. The player builds and manages a persistent base on a procedurally generated island, progressing through 3 economic eras while the Imperial Storm keeps coming back to collect. The management loop is complete (economy, population, market, tech tree, army training, audio). Turn-based PVE combat is live: an 8x8 tactical board, the Tithe fought instead of paid, and the Final Audit — HQ level 3 no longer wins, it summons a 3-5 wave siege you have to survive. See `docs/15-combat.md` for the pillar and `docs/13-roadmap.md` for what is left.

Detailed per-system docs live in `docs/` (see `docs/INDEX.md`).

> "On the mud of history, we shall build monuments of steel."

## Tech Stack

- **Engine:** Godot 4.7 .NET Edition (Forward+ renderer)
- **Languages:** GDScript for everything, turn-based combat included (it shipped in GDScript). There is no C# project (no `.csproj`, no `.cs` files) and none is planned for v1 — see "Key Rule" below
- **Tests:** gdUnit4 (`addons/gdUnit4`) over the pure models — `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests`
- **Backend:** Supabase (CloudSaveManager implements auth + save/load via REST, but nothing calls it yet — needs `.env` config and UI wiring)
- **Multiplayer:** Nakama (planned: self-hosted Docker, for PvP and Co-op)

## Running the Project

1. Open the project folder in **Godot 4.7 .NET Edition**
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

24 game autoloads, plus `BeckettRuntime` (the `addons/beckett` dev bridge, not a game system).

| # | Service | File | Purpose |
|---|---------|------|---------|
| 1 | `Tr` | `scripts/services/Tr.gd` | i18n translation (ES/EN) |
| 2 | `GameConfig` | `scripts/services/GameConfig.gd` | All tunable values, balance, durations |
| 3 | `EventBus` | `scripts/services/EventBus.gd` | Global signal bus (~25 signal categories) |
| 4 | `InputService` | `scripts/services/InputService.gd` | Unified input: keyboard, mouse, touch |
| 5 | `GridManager` | `scripts/grid/GridManager.gd` | 40x40 cell grid (2.0 units/cell, origin -40,-40), building/obstacle placement |
| 6 | `ResourceManager` | `scripts/services/ResourceManager.gd` | 4 resources (gold/steel/oil/wood) + unlock system |
| 7 | `GameManager` | `scripts/services/GameManager.gd` | Save/load, new game, offline progression |
| 8 | `ProcessManager` | `scripts/services/ProcessManager.gd` | Timed manual processes (manufacturing, mining) |
| 9 | `ProductionManager` | `scripts/services/ProductionManager.gd` | Passive production, construction, upgrades |
| 10 | `ProgressionManager` | `scripts/services/ProgressionManager.gd` | Era system (3 eras), 9 milestones, **and the Final Audit** (owns the `FinalAudit` model and publishes it) |
| 11 | `MarketManager` | `scripts/services/MarketManager.gd` | Buy/sell resources with floating prices |
| 12 | `PopulationManager` | `scripts/services/PopulationManager.gd` | Population, workers, morale, consumption |
| 13 | `ArmyManager` | `scripts/services/ArmyManager.gd` | Unit training at Barracks, upkeep, desertion, Military Power |
| 14 | `CombatManager` | `scripts/services/CombatManager.gd` | Owns the active `Encounter` and `Expedition`; drives the enemy turn, applies results, saves the run |
| 15 | `RandomEventManager` | `scripts/services/RandomEventManager.gd` | Random events (storms, plagues, festivals...) |
| 16 | `BuildingHealth` | `scripts/services/BuildingHealth.gd` | Building damage, ruined state that halts output, proportional repair |
| 17 | `StormManager` | `scripts/services/StormManager.gd` | Drives the Imperial Storm cycle (`scripts/storm/StormCycle.gd`), storm damage and the Tithe |
| 18 | `StormSky` | `scripts/map/StormSky.gd` | Darkens the `WorldEnvironment` and light during the storm, restores them after |
| 19 | `TechTreeManager` | `scripts/services/TechTreeManager.gd` | 15 techs in 3 branches, permanent bonuses |
| 20 | `CloudSaveManager` | `scripts/services/CloudSaveManager.gd` | Supabase auth + cloud save/load (unwired) |
| 21 | `UIManager` | `scripts/services/UIManager.gd` | Panel stacking, ESC-close, slot conflict resolution |
| 22 | `TutorialManager` | `scripts/services/TutorialManager.gd` | Paged intro on a new game + one contextual tip per event; state saved with the game |
| 23 | `UILayoutManager` | `scripts/services/UILayoutManager.gd` | Positions panels from `UILayoutConfig` slots, applies theme |
| 24 | `AudioManager` | `scripts/services/AudioManager.gd` | Signal-driven music/SFX/ambient, runtime buses |

### Scene Tree (Main.tscn)

```
Main (Node3D)
  +-- MonumentalCamera (Camera3D)
  +-- DirectionalLight
  +-- WorldEnvironment
  +-- IslandGenerator (Node3D) -- procedural island mesh: a rounded square that covers the whole 40x40 grid (shore and water start outside it)
  +-- GridOverlay (MeshInstance3D) -- faint cell grid, on by default (Settings toggle), fitted to GridManager at runtime
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
  +-- TechTreePanel (CanvasLayer) -- 3 branches x 5 tiers research UI
  +-- ObjectivePanel (CanvasLayer) -- "what to do" goals modal
  +-- ArmyPanel (CanvasLayer) -- train units, Military Power, upkeep
  +-- SettingsPanel (CanvasLayer) -- volume sliders + UI toggles (persisted)
  +-- HelperPanel (CanvasLayer) -- "?" on-screen callouts + building guide modal
  +-- SkirmishPanel (CanvasLayer) -- commit troops before a board opens; "QUE BAJEN" (Final Audit)
  +-- BattleScreen (CanvasLayer) -- the 8x8 tactical board (layer 18, outside UIManager's stack)
  +-- StormHUD (CanvasLayer) -- storm phase indicator (colour + icon, no countdown)
  +-- TutorialPanel (CanvasLayer) -- paged intro + contextual tip cards
```

UI panels are positioned by `UILayoutManager` using the slot definitions in
`scripts/ui/UILayoutConfig.gd` (11 screen slots, panel->slot map, slot conflicts).
`UIManager.open_panel()` handles stacking and closes conflicting panels.
All styling comes from the static `UITheme` class (dieselpunk metal 9-patch
textures generated by `tools/gen_ui_textures.gd`).

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
- Storage: **one shared pool for all four resources**, not a cap per resource. Base scales
  by era (600 / 800 / 1000) + 500 per warehouse (max 5, see `GameConfig.building_limits`).
  Era 1 is 600 so the opening fits: 500 starting resources, plus sawmill + gold mine (330).
  Era 3 ceiling = 1000 + 5x500 = **3500**, exactly the price of the HQ level 3 upgrade.
  Whatever does not fit is lost; `EventBus.storage_overflow` fires and the player is
  warned once per game. Loading a save that holds more than fits trims it proportionally.

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
| Nucleo (core) | 3x3 | Free | 0 | +5 pop capacity; manual processes only | - |
| House | 1x1 | 50/0/0/30 | 0 | +6 pop capacity | 1 |
| Sawmill | 2x1 | 80/0/0/50 | 2 | 6 wood/12s | 1 |
| Gold Mine | 2x2 | 120/0/0/80 | 3 | 8 gold/12s | 1 |
| Warehouse | 1x1 | 60/0/0/40 | 1 | +500 shared storage | 1 |
| Foundry | 2x1 | 200/0/0/120 | 3 | 5 steel/15s | 1->2 |
| Barracks | 2x2 | 250/100/0/80 | 3 | Trains units (ArmyManager) | 2 |
| Refinery | 2x2 | 300/150/0/100 | 4 | 4 oil/18s | 2->3 |
| Tower | 1x1 | 150/60/20/30 | 1 | Storm mitigation + an artillery crew on defensive boards (only while operational) | 2-3 |
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
| `hq_max` | **HQ Level 3 — summons the Final Audit** |

HQ upgrade costs: L2 = 800g/500s/300o/400w, L3 = 1500g/800s/500o/700w

**HQ level 3 no longer wins the game.** `ProgressionManager._complete_milestone()`
catches `hq_max` and calls `summon_final_audit()`: the Regency comes down for a
3-5 wave siege fought by whatever garrison is at home, with attrition across waves
and no retraining in between. Surviving it emits `storm_halted_forever` (the Storm
stops for good) and only then `victory_achieved`. Losing is **not** a game over —
maximum Tithe, maximum storm damage, and the siege can be summoned again once 3
units stand. Full detail in `docs/15-combat.md`.

### Army & Units (management -> combat bridge)

- **ArmyManager** trains units at Barracks. Parallel training slots = number of
  Barracks (one unit per slot at a time, no queue). Cost paid up-front.
- Capacity: `3 base + 8 per Barracks`. Owned units AND units in training count.
- Units gated by era (`ProgressionManager.current_era >= unit.era`).

| Unit | Era | Cost | Train | Upkeep | Power |
|------|-----|------|-------|--------|-------|
| Infantry | 1 | 40g + 20w | 20s | 1 gold | 10 |
| Artillery | 2 | 80g + 30s | 35s | 2 gold | 28 |
| Vehicle | 3 | 140g + 60s + 30o | 55s | 4 gold | 65 |

- **Upkeep:** every 30s, gold-only. If short, drains remaining gold to 0 and emits
  `army_upkeep_unpaid`. Sustained non-payment **deserts** units, the most expensive
  first (`ArmyManager._desert()` → `army_deserted`).
- **Military Power** = sum of unit power. Combat consumes this army for real:
  `ArmyManager` stays the source of truth and `CombatManager` only debits the dead
  (`remove_units()`), so Power never lies while a column is out.
- EventBus signals: `unit_training_started`, `unit_trained`, `army_changed`,
  `army_upkeep_unpaid`, `unit_training_cancelled`, `army_deserted`.
- ArmyPanel's sidebar button only appears once a Barracks exists.
- Combat stats for these three unit types are separate, in
  `GameConfig.combat_unit_stats` — see `docs/15-combat.md` §8.

### Combat (PVE) — full doc: `docs/15-combat.md`

Three layers, and the rule that holds them together: **the models never emit**.
Every mutating method in `scripts/combat/` returns an `Array` of event dicts; a
service drains it onto the `EventBus`; the UI only reads and calls.

- **Pure models** (`scripts/combat/`): `CombatUnit`, `CombatRules`, `Encounter`,
  `CombatAI`, `AutoResolver`, `Expedition`, `ExpeditionGenerator`, `FinalAudit`.
  No nodes, no timers, no global `randf()` — every one is headless-testable.
- **Services:** `CombatManager` owns the `Encounter` and the `Expedition`;
  `ProgressionManager` owns the `FinalAudit`.
- **UI:** `BattleScreen` (the 8x8 board) and `SkirmishPanel` (committing troops).

Three roads reach the same board: a skirmish/expedition node (player picks the
party, a win pays loot), the Tithe defence (`get_garrison()` + tower crews, a win
pays nothing but the Tithe goes uncollected), and a Final Audit wave (the siege
garrison, carried wave to wave with its damage). When the Tithe lands while a
board is already open, `AutoResolver` plays the *same* `Encounter` with the AI on
both sides — there is no second combat formula anywhere.

**Expedition caveat:** the models, `CombatManager` API, save/load and tests are all
in place, but no screen drives an expedition yet. See "Planned" below.

### Tech Tree (15 techs, 3 branches)

- **TechTreeManager** + `GameConfig.tech_definitions`. Branches: Industrial,
  Military, Logistics — 5 linear tiers each (tier N requires tier N-1).
- Research costs **resources** (not points) and takes time; only one tech at a time.
- Bonuses are permanent: production multiplier, storage, consumption reduction,
  morale recovery (Military branch), market spread / build speed (Logistics).
- Caveat: `_research_points` (+1 per HQ production tick) is saved but never spent —
  vestigial. The "requires HQ" comment in the header is NOT enforced in code.

### Game Phases (onboarding pacing)

`GameConfig.Phase` enum: FOUNDATION -> SETTLEMENT -> ECONOMY -> SURVIVAL -> EXPANSION.
`phase_triggers` gates early-game pacing (`early_consumption_interval`,
`early_morale_penalty`, `early_growth_interval`) so consumption/morale pressure
ramps up gradually instead of punishing the first minutes.

### Audio

- **AudioManager** creates Music/SFX/Ambient buses at runtime and auto-plays from
  ~18 EventBus signals (era music crossfade, build/trade/event SFX, etc.).
- Assets: 4 music tracks + 16 SFX in `assets/audio/{music,sfx}/` (ambient still empty).
  Missing files are skipped silently — audio never crashes the game.
- API: `play_sfx(key)`, `play_music_for_era(era)`, `set_*_volume(linear)`.
  Manifest of expected keys: `assets/audio/MANIFEST.md`.

### User Settings (`user://settings.cfg`)

Device-local preferences, separate from the game save. `GameConfig.load_user_settings()`
runs in its `_ready()` (before AudioManager applies volumes); anything that changes a
preference calls `GameConfig.save_user_settings()`. Currently stored: audio volumes
(master/music/sfx/ambient — sliders in SettingsPanel), `ui_grid_visible` (map grid
toggle; GridOverlayControl applies it, BuildingPlacer restores it after placement),
and `ui_helper_visible` (HelperPanel "?" callouts, on by default).

### Save/Load System

- Path: `user://save_game.json`
- Saves: resources, buildings (level, name, construction state), deposits, camera, progression, market, population, events, unlock state, tech tree, army
- Cloud: `CloudSaveManager` (Supabase REST) implements anonymous/email auth + save/load, but no game code calls it yet — local JSON is the only active path
- Auto-saves on: building placed/moved/renamed/demolished, deposit depleted
- Offline progression: calculates production earned while game closed (max 8h)

---

## Project Structure

```
tormenta-imperial/
+-- project.godot                    # Engine config, 24 autoloads (+ BeckettRuntime)
+-- CLAUDE.md                        # THIS FILE - AI guidance
+-- readme.md                        # Game overview
+-- docs/                            # Per-system deep docs (INDEX.md, 13-roadmap.md, 15-combat.md...)
+-- specs/001-combate-pve/           # Spec, plan and tasks for the combat pillar
+-- tests/                           # gdUnit4 suites: combat/, storm/, economy/, map/, ui/, audio/, tutorial/
+-- scenes/
|   +-- main/Main.tscn              # Entry scene
|   +-- buildings/BuildingPlacer.tscn
|   +-- ui/                          # One .tscn per panel (matches scripts/ui/)
+-- scripts/
|   +-- buildings/
|   |   +-- BuildingData.gd         # Resource class for building definitions
|   |   +-- BuildingPlacer.gd       # Placement/move/demolish + mesh spawning
|   |   +-- DieselpunkBuildingFactory.gd  # Procedural 3D meshes for all 14 buildings
|   +-- camera/MonumentalCamera.gd   # Orthographic 45deg RTS camera
|   +-- combat/                      # PURE models: no nodes, no signals, no global RNG
|   |   +-- CombatUnit.gd           # One unit: hp, position, draft bonuses, morale mods
|   |   +-- CombatRules.gd          # Static maths: damage, initiative, range, BFS, timeout
|   |   +-- Encounter.gd            # One board: deploy, turn order, actions, resolution
|   |   +-- CombatAI.gd             # Plans one unit's turn; drives either side
|   |   +-- AutoResolver.gd         # Plays a whole Encounter headless (AI on both sides)
|   |   +-- Expedition.gd           # One roguelike run: map, party, loot, state
|   |   +-- ExpeditionGenerator.gd  # Seeded map graph, rosters, rewards, drafts
|   |   +-- FinalAudit.gd           # The closing siege: waves, garrison, resummon
|   +-- grid/GridManager.gd          # 40x40 cell grid; the island covers every cell
|   +-- map/
|   |   +-- IslandGenerator.gd      # Procedural island mesh
|   |   +-- MapGenerator.gd         # Random deposit spawning
|   |   +-- StormSky.gd             # Autoload: sky/light during the storm
|   +-- storm/StormCycle.gd          # PURE model: the storm's four-phase clock
|   +-- services/                    # ALL autoload singletons (24, see table above)
|   |   +-- ...Manager.gd / EventBus.gd / GameConfig.gd / Tr.gd
|   |   +-- FloatingText.gd         # Static utility: animated 3D text labels
|   +-- ui/
|       +-- UITheme.gd              # Static dieselpunk theme (colors, fonts, styleboxes)
|       +-- UILayoutConfig.gd       # Screen slots, panel->slot map, conflicts
|       +-- ArmyPanel.gd, TechTreePanel.gd, ObjectivePanel.gd
|       +-- BattleScreen.gd, SkirmishPanel.gd     # The board, and committing troops
|       +-- StormHUD.gd, TutorialPanel.gd, HelperPanel.gd, SettingsPanel.gd
|       +-- BuildingInfoPanel.gd, ConstructionMenu.gd, MarketPanel.gd,
|       +-- NotificationPanel.gd, OnScreenControls.gd, ProcessActionsPanel.gd,
|       +-- ProgressPanel.gd, ResourceHUD.gd, VictoryScreen.gd
+-- data/buildings/                  # 14 .tres building definitions
+-- assets/
|   +-- audio/{music,sfx,ambient}/   # 4 tracks + 16 SFX (see MANIFEST.md)
|   +-- textures/                    # metal_plate PBR maps + ui/ 9-patch sprites
+-- tools/
    +-- gen_ui_textures.gd           # Regenerates ui/*_metal.png (godot --headless)
    +-- battle_probe.gd, audit_probe.gd, storm_probe.gd, tutorial_probe.gd  # Dev probes
    +-- blender_helper.py, generate_buildings.py, build_decorations.py  # Blender MCP model gen
```

Probes are registered **temporarily** as autoloads in `project.godot`, run with a
window (not headless), and removed again. They no-op unless `GameConfig.dev_mode`.

Note: unit and tech definitions live as inline dictionaries in `GameConfig.gd`
(`unit_types`, `tech_definitions`), NOT as .tres files.

Building 3D meshes come from **two** sources. `BuildingPlacer._create_building_mesh()`
prefers a building's `model_scene` (a GLB under `assets/models/buildings/<id>/`) and
falls back to `DieselpunkBuildingFactory` when it is unset. **12 of the 14 buildings
ship a GLB**; only `nucleo` and `road` are procedural today (road needs the factory
because its mesh is connectivity-aware).

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

### Key Rule: GDScript first (decided 2026-09-12)

- **GDScript for everything**, combat included. The whole project (19 services + all UI) is GDScript; a second language adds build times, cross-runtime debugging and marshalling for no benefit here.
- The old plan put unit AI, combat math and pathfinding in C# **for performance**. That argument does not apply at the agreed combat scale: an 8x8 board with 4–6 units per side. GDScript is orders of magnitude more than enough.
- **Migrate later, only on evidence**: if a profiled module proves too slow, port that module to C#. Do not create the .NET project speculatively.

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

### Adding Persistent State

Any state that travels in the save file has to be cleared in its service's `reset()`,
and that `reset()` has to be called from **all three** places in `GameManager` that
start a fresh game: `_new_game()`, `clear_save()` and `clear_save_and_reload_from()`.
They are three duplicated lists and it is easy to update one and forget the others —
that is exactly how `ProcessManager` shipped without a `reset()` at all.

Rules:
- `reset()` **throws away, it never cancels**. Do not reuse `cancel()` or any refund
  path: a new game must not pay out resources from the old one.
- `reset()` **never notifies the player**. A new game does not announce what it lost.
- If the state is transient and rebuilt from signals (e.g. "is ash falling"), it also has
  to be **re-derived on `game_load_completed`**, or a save made mid-event reloads blind.
- Autoloads survive scene reloads. Anything you do not clear is still there.

### Tuning Economy

All balance values live in `GameConfig.gd`:
- `starting_resources` - initial amounts
- `building_processes` - manual crafting recipes with margins
- `mining_data` - deposit yields and durations
- `market_*` - market prices, spread, volatility
- `upgrade_cost_multiplier` / `upgrade_production_multiplier`
- `hq_upgrade_costs` - capstone building costs
- `base_storage_cap_by_era` / `warehouse_storage_bonus` / `tech_storage_bonus`
- `morale_*` - morale thresholds, recovery/penalty rates
- `population_start` - initial population count
- `consumption_interval` / `growth_interval` - tick timings
- `event_interval_*` - random event timing ranges
- `resource_colors` - display colors for floating text
- `unit_types` / `army_base_capacity` / `army_capacity_per_barracks` / `army_upkeep_interval` - army
- `tech_definitions` + `tech_*` bonuses - tech tree
- `audio_*_volume` / `audio_music_fade` / `audio_sfx_voices` - audio
- `phase_triggers` / `early_*` - onboarding phase pacing
- `combat_*` - board, deploy cap, unit combat stats, enemy/risk scaling, map shape,
  drafts, rewards, morale-in-combat (table with effects in `docs/15-combat.md` §8)
- `storm_*` - storm cycle, damage, the Tithe, tower mitigation and tower crews
- `final_audit_*` - the closing siege: wave count, slots, scaling, resummon floor

### Shared Utilities

- **FloatingText** (`scripts/services/FloatingText.gd`): Static class for spawning animated 3D text labels. Use `FloatingText.spawn()` for custom text or `FloatingText.spawn_resource()` for resource gain/loss display. Colors come from `GameConfig.resource_colors`.
- **DieselpunkBuildingFactory** (`scripts/buildings/DieselpunkBuildingFactory.gd`): Static factory generating dieselpunk building meshes from primitives (rivets, pipes, brass/rust palette, shared PBR metal maps). `create(building_id, cell_size, grid_size)` and connectivity-aware `create_road(cell_size, neighbors)`. Called by BuildingPlacer and ConstructionMenu previews **as the fallback when a building has no `model_scene` GLB** — today that is only `nucleo` and `road`.
- **UITheme** (`scripts/ui/UITheme.gd`): Static theme — call its factories for any new UI instead of hand-styling controls.

### Dev Mode

`GameConfig.dev_mode = true` makes all durations 1-2 seconds for rapid testing. Set to `false` for real timings.

---

## Planned (Not Yet Implemented)

Full roadmap with milestones and dependency order: `docs/13-roadmap.md`.
Combat detail, including a verified list of gaps: `docs/15-combat.md`.

- **Expedition UI** (the one real gap in the combat pillar): `launch_expedition()`,
  `select_node()`, `apply_draft()` and `abandon_expedition()` are implemented, saved,
  loaded and tested, but **no screen calls them**. `SkirmishPanel`'s launch button
  starts a standalone skirmish. There is no map view and no draft modal, and
  `draft_offered` / `expedition_node_selected` / `expedition_resumed` have no listener
- **After-action report for `defense_auto_resolved`:** the signal is emitted but only
  `StormManager`'s own toast reads that fight today
- **Real unit icons on the board** (currently the unit name's first letter)
- **Tower behaviour beyond the storm:** towers mitigate damage and field a crew on a
  defensive board; they have no attack of their own on the base map
- **Missions/contracts:** timed delivery challenges for rewards
- **Cloud save wiring:** CloudSaveManager exists but needs `.env` + UI (settings menu)
- **Turn-based PVP:** attack another player's base with your army (Nakama, after PVE)
