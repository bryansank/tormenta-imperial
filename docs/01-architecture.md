# Architecture: Service-Signal-Component

## Pattern Overview

Tormenta Imperial uses a **Service-Signal-Component** architecture native to Godot:

```
+------------------------------------------------------+
|                  Autoload Services                    |
|  Tr - GameConfig - EventBus - InputService - Grid    |
|  ResourceMgr - GameMgr - ProcessMgr - ProductionMgr  |
|  ProgressionMgr - MarketMgr - PopulationMgr - Events |
+---------------------------+--------------------------+
                            | signals (EventBus)
+---------------------------v--------------------------+
|                  Scene Components                     |
|  Camera - BuildingPlacer - MapGenerator - UI Panels   |
+------------------------------------------------------+
```

### Core Rules
1. **Services never reference each other directly** — only through EventBus signals
2. **UI subscribes to EventBus** in `_ready()` and reacts to signals
3. **Data flows one way:** Input -> Service -> EventBus -> Consumer
4. **GameConfig holds all tunable values** — no magic numbers in code

## Autoload Load Order (matters!)

The autoloads in `project.godot` load in order. Dependencies must load before dependents:

| Order | Service | Depends On | Purpose |
|-------|---------|------------|---------|
| 1 | Tr | — | Translation strings |
| 2 | GameConfig | — | All balance/tuning constants |
| 3 | EventBus | — | Signal bus (no logic, just signal declarations) |
| 4 | InputService | EventBus | Keyboard/mouse/touch -> signals |
| 5 | GridManager | — | 25x25 cell grid, placement logic |
| 6 | ResourceManager | EventBus, GameConfig | 4 resources + unlock tracking |
| 7 | GameManager | All above | Save/load, game lifecycle |
| 8 | ProcessManager | ResourceManager, GameConfig, EventBus | Timed crafting/mining |
| 9 | ProductionManager | ResourceManager, GameConfig, EventBus, GridManager | Passive production, construction |
| 10 | ProgressionManager | EventBus, GameConfig, ResourceManager, GridManager | Eras, milestones, victory |
| 11 | MarketManager | ResourceManager, EventBus, GameConfig | Buy/sell with floating prices |
| 12 | PopulationManager | ResourceManager, EventBus, GameConfig, GridManager | Pop, workers, morale |
| 13 | RandomEventManager | ResourceManager, PopulationManager, EventBus, GameConfig | Random events |

## Scene Tree

```
Main (Node3D)
  MonumentalCamera (Camera3D) -- orthographic 45deg, WASD/scroll/touch
  DirectionalLight -- sun with shadows
  WorldEnvironment -- sky, ambient light, SSAO
  IslandGenerator (Node3D) -- procedural island (water + shore + grass)
  GridOverlay (MeshInstance3D) -- debug grid visualization (hidden)
  BuildingPlacer (Node3D) -- handles all building placement/move/demolish
  OnScreenControls (CanvasLayer) -- mobile D-pad, zoom, rotate buttons
  ResourceHUD (CanvasLayer) -- top bar showing unlocked resources
  MapGenerator (Node) -- spawns 15-25 resource deposits randomly
  ConstructionMenu (CanvasLayer) -- "BUILD" button + scrollable building list
  BuildingInfoPanel (CanvasLayer) -- right panel for selected building/deposit
  MarketPanel (CanvasLayer) -- buy/sell UI with price display
  ProgressPanel (CanvasLayer) -- milestones checklist + era display
  VictoryScreen (CanvasLayer) -- full-screen victory overlay
  NotificationPanel (CanvasLayer) -- activity log + toast notifications + status
```

## File Organization

```
scripts/services/    -- Autoload singletons (the "brain")
scripts/ui/          -- UI panel scripts (subscribe to EventBus)
scripts/buildings/   -- BuildingData resource class
scripts/camera/      -- Camera controller
scripts/grid/        -- Grid management
scripts/map/         -- Island + deposit generation
data/buildings/      -- 14 .tres building definitions
scenes/main/         -- Main.tscn entry scene
scenes/ui/           -- UI .tscn files (minimal, scripts do the work)
scenes/buildings/    -- BuildingPlacer.tscn
```

## Adding New Systems

1. Create service in `scripts/services/NewManager.gd`
2. Add signals to `EventBus.gd` under a new category
3. Register as autoload in `project.godot` (order matters!)
4. Add save/load methods: `get_save_data()`, `load_save_data()`, `reset()`
5. Wire into `GameManager._new_game()`, `_load_game()`, `clear_save()`
6. Add translations to `Tr.gd` (both ES and EN dicts)
7. Create UI if needed in `scripts/ui/` + `scenes/ui/`
8. Add to `Main.tscn` scene tree
