# Architecture: Service-Signal-Component

## Pattern Overview

Tormenta Imperial uses a **Service-Signal-Component** architecture native to Godot:

```
+-------------------------------------------------------------+
|                    Autoload Services (25)                    |
|  Tr - GameConfig - EventBus - InputService - GridManager     |
|  Resource / Game / Process / Production / Progression        |
|  Market / Population / Army / Combat / RandomEvent           |
|  BuildingHealth / Storm / StormSky / TechTree / CloudSave    |
|  UIManager / Tutorial / UILayout / Audio / DeviceProfile     |
+------------------------------+------------------------------+
                               | signals (EventBus)
+------------------------------v------------------------------+
|                      Scene Components                        |
|  Main.tscn (3D) or Main2D.tscn (2D): camera, island, placer, |
|  map generator + the same 23 UI panels in both               |
+-------------------------------------------------------------+
        ^
        | pure models, no nodes: scripts/combat/, scripts/storm/
```

### Core Rules
1. **State changes are announced on the EventBus.** A producer never knows its
   consumers. Direct calls between autoloads exist only as queries and commands by
   name (`CombatManager.get_garrison()`, `GameMode.storm_enabled()`, GameManager
   calling every `reset()`), never as notifications
2. **UI subscribes to EventBus** in `_ready()`, reads services and calls them
3. **Data flows one way:** Input -> Service -> EventBus -> Consumer
4. **GameConfig holds all tunable values** — no magic numbers in code
5. **Pure models** (`scripts/combat/`, `scripts/storm/StormCycle.gd`) have no nodes,
   no signals and no global RNG; they return event lists that a service publishes
6. **Views are interchangeable**: services type buildings and deposits as `Node`, not
   `Node3D`, so the 2D view (`scripts/view2d/`) runs on the same services

## Autoload Load Order (matters!)

The autoloads in `project.godot` load in this order. 26 entries: 25 game services and
the `BeckettRuntime` dev bridge.

| Order | Service | Purpose |
|-------|---------|---------|
| 1 | Tr | Translation strings (ES/EN) |
| 2 | GameConfig | All balance/tuning values, user settings, `dev_mode` |
| 3 | EventBus | Signal bus (no logic, just 107 signal declarations) |
| 4 | InputService | Keyboard/mouse/touch -> signals |
| 5 | GridManager | 40x40 cell grid, placement logic |
| 6 | ResourceManager | 4 resources in one shared pool + unlock tracking |
| 7 | GameManager | Save/load, new game, offline progression, scene/view switching |
| 8 | ProcessManager | Timed crafting/mining |
| 9 | ProductionManager | Passive production, construction, upgrades |
| 10 | ProgressionManager | Eras, milestones, the Final Audit, victory |
| 11 | MarketManager | Buy/sell with floating prices |
| 12 | PopulationManager | Pop, workers, morale |
| 13 | ArmyManager | Training, upkeep, desertion |
| 14 | CombatManager | The active encounter and expedition |
| 15 | RandomEventManager | Random events |
| 16 | BuildingHealth | Damage, ruins, repair |
| 17 | StormManager | The Imperial Storm cycle and the Tithe |
| 18 | StormSky | Sky and light during the storm (`scripts/map/StormSky.gd`) |
| 19 | TechTreeManager | Research and permanent bonuses |
| 20 | CloudSaveManager | Supabase auth + cloud save (unwired) |
| 21 | UIManager | Window stack, ESC, slot conflicts |
| 22 | TutorialManager | Prologue, guided tutorial, tips and helps seen |
| 23 | UILayoutManager | Positions panels from `UILayoutConfig` slots |
| 24 | AudioManager | Signal-driven music/SFX |
| — | BeckettRuntime | Dev bridge: `scripts/services/BeckettGate.gd`, loads `addons/beckett` only in the editor |
| 25 | DeviceProfile | PC/tablet/phone profile, UI scale, `UITheme` tokens |

`GameMode`, `UITheme`, `UILayoutConfig`, `HudRegistry`, `Objectives` and
`FloatingText` are static helpers, not autoloads.

## Scene Tree

`Main.tscn` (3D) and `Main2D.tscn` (2D) have the same UI nodes with the same names;
only the world nodes differ. The full annotated tree, with layers and the nodes
created at runtime (PrologueScreen, HelpIndexPanel, NewGameDialog, LayoutEditor), is
in `CLAUDE.md` → "Scene Tree". The 2D view is described in
[18-vista-2d.md](18-vista-2d.md).

## File Organization

```
scripts/services/    -- Autoload singletons (the "brain") + static helpers (GameMode, Objectives, FloatingText)
scripts/ui/          -- UI panel scripts (subscribe to EventBus), UITheme, UILayoutConfig, HudRegistry
scripts/buildings/   -- BuildingData, BuildingPlacer (3D), PlacementRules, PlacementAssist, status badge, mesh factory
scripts/view2d/      -- The 2D view: router, camera, island, placer, drawings
scripts/combat/      -- Pure combat models
scripts/storm/       -- Pure storm cycle model
scripts/camera/      -- 3D camera controller
scripts/grid/        -- Grid management + grid overlay
scripts/map/         -- Island + deposit generation, storm sky
data/buildings/      -- 14 .tres building definitions
scenes/main/         -- Main.tscn (entry, 3D) and Main2D.tscn
scenes/ui/           -- UI .tscn files (minimal, scripts do the work)
scenes/buildings/    -- BuildingPlacer.tscn
tests/               -- gdUnit4 suites (run with tools/run_tests.sh)
tools/               -- Probes, asset generators, test wrapper
```

## Adding New Systems

1. Create service in `scripts/services/NewManager.gd`
2. Add signals to `EventBus.gd` under a new category
3. Register as autoload in `project.godot` (order matters!)
4. Add save/load methods: `get_save_data()`, `load_save_data()` (idempotent), `reset()`
5. Wire the save key into `GameManager._write_save()` and the load path, and call
   `reset()` from **all three** fresh-game paths: `_new_game()`, `clear_save()` and
   `clear_save_and_reload_from()` (see `CLAUDE.md` → "Adding Persistent State")
6. Add translations to `Tr.gd` (both ES and EN dicts)
7. Create UI if needed in `scripts/ui/` + `scenes/ui/`
8. Add the UI node to **both** `Main.tscn` and `Main2D.tscn`, same name, same place,
   and add the name to the list in
   `tests/view2d/test_view_mode.gd::test_the_2d_scene_has_the_same_ui_as_the_3d_scene`
9. Test it with `tools/run_tests.sh`, never with `GdUnitCmdTool.gd` directly
