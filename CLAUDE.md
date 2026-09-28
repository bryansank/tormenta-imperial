# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Tormenta Imperial** is a dieselpunk management + turn-based strategy game built in Godot 4.7 .NET. The player builds and manages a persistent base on a procedurally generated island, progressing through 3 economic eras while the Imperial Storm keeps coming back to collect. The management loop is complete (economy, population, market, tech tree, army training, audio). Turn-based PVE combat is live: an 8x8 tactical board, roguelike expeditions with their own map and drafts, the Tithe fought instead of paid, and the Final Audit — in Campaña HQ level 3 no longer wins, it summons a 3-5 wave siege you have to survive. Around that core: four game modes, a 2D top-down view next to the 3D one, a configurable UI with PC/tablet/phone profiles and touch placement, a prologue + guided tutorial + help index, and Windows and Android exports. See `docs/15-combat.md` for the combat pillar and `docs/13-roadmap.md` for what is done and what is left.

Detailed per-system docs live in `docs/` (see `docs/INDEX.md`).

> "On the mud of history, we shall build monuments of steel."

## Tech Stack

- **Engine:** Godot 4.7 .NET Edition (Forward+ renderer on PC, Mobile renderer on Android via `rendering_method.mobile`)
- **Languages:** GDScript for everything, turn-based combat included (it shipped in GDScript). There is no C# project (no `.csproj`, no `.cs` files) and none is planned for v1 — see "Key Rule" below
- **Tests:** gdUnit4 (`addons/gdUnit4`), ~1360 tests in 102 suites under `tests/` (audio, build, buildings, combat, economy, input, integration, map, modes, save, storm, tutorial, ui, view2d) — **always** through the wrapper:
  ```bash
  GODOT=/path/to/godot tools/run_tests.sh              # whole suite
  GODOT=/path/to/godot tools/run_tests.sh -a tests/combat
  ```
  (`tools\run_tests.ps1` on PowerShell; extra args go to GdUnitCmdTool). It writes a temporary `override.cfg` so the run gets its own user dir (`%APPDATA%\TormentaImperial_tests`, override with `TI_TEST_USER_DIR`; it refuses the player's dir names), runs headless with `--ignoreHeadlessMode`, and removes the file on exit. Never call `GdUnitCmdTool.gd` directly: that runs in the editor's user dir, where the player's `save_game.json` lives. As a backstop, `tests/save/save_parking.gd` refuses to park in the player's dir and the suites that write the save skip themselves there
- **Backend:** Supabase (CloudSaveManager implements auth + save/load via REST, but nothing calls it yet — needs `.env` config and UI wiring)
- **Multiplayer:** none. PvP and co-op are out of scope for v1 (constitution v2.0.0 dropped the old Nakama plan; if PvP ever happens it would sit on Supabase)

## Running the Project

1. Open the project folder in **Godot 4.7 .NET Edition**
2. Press **F5** to run. The title menu (`TitleMenu`) opens first over the loaded game
3. WASD / arrows to pan, Q/E or right-drag to rotate, scroll to zoom, middle-drag or left-drag on the ground to grab-pan, F11 fullscreen
4. Touch: one finger grabs the terrain, two-finger pinch to zoom and twist to rotate (3D only); tap to aim a building, tap the ghost / ✓ to build (docs/21 §9)
5. A fresh game: ☰ MENÚ → Menú principal → Nueva partida (mode picker). Deleting `user://save_game.json` also works
6. **2D view:** Settings → Map view, or `godot --path . -- --view=2d`. Same services, UI and save; only the world view differs (`scenes/main/Main2D.tscn`, `scripts/view2d/`). See `docs/18-vista-2d.md`
7. **User args** (after `--`): `--view=2d|3d`, `--no-title` (skip the title menu, used by probes), `--dev` / `--no-dev` (force `dev_mode`, see "Dev Mode")
8. **Your save lives in the editor's user dir** (`%APPDATA%\Godot\app_userdata\Tormenta Imperial`). Anything that plays or writes saves outside a normal play session (probes, experiments, a second agent) needs a git-ignored `override.cfg` at the project root with its own dir, deleted afterwards:
   ```ini
   [application]
   config/use_custom_user_dir=true
   config/custom_user_dir_name="TI_something"
   ```
   On Windows that dir is `%APPDATA%\TI_something`. Tests get this automatically from `tools/run_tests.sh`

---

## Architecture: Service-Signal-Component

State changes travel through **EventBus** signals: a producer never knows its consumers.

### Data Flow Pattern

```
Raw Input -> InputService -> EventBus.signal -> Consumer (Camera, Buildings, UI)
Services emit signals on EventBus. Scene components subscribe.
Notifications go only through EventBus.
```

Direct calls do exist, but only as queries and commands on an autoload by name —
`CombatManager.get_garrison()`, `ProgressionManager.begin_final_audit()`,
`GameMode.storm_enabled()`, `GameManager` calling every `reset()` — never to tell
someone that something happened. The UI reads services and calls them; it never
holds a service's state of its own.

### Autoload Services (registered in project.godot, load order matters)

26 autoloads in `project.godot`: the 25 game services below, plus `BeckettRuntime`, the `addons/beckett` dev bridge. `BeckettRuntime` loads between `AudioManager` and `DeviceProfile` (so `DeviceProfile` is last); it points at `scripts/services/BeckettGate.gd`, which loads the addon's runtime only in the editor, and it is not a game system. `GameMode`, `UITheme`, `UILayoutConfig`, `HudRegistry`, `FloatingText` and `Objectives` are static helpers (a `class_name` or a `preload`), not autoloads.

| # | Service | File | Purpose |
|---|---------|------|---------|
| 1 | `Tr` | `scripts/services/Tr.gd` | i18n translation (ES/EN) |
| 2 | `GameConfig` | `scripts/services/GameConfig.gd` | All tunable values, balance, durations |
| 3 | `EventBus` | `scripts/services/EventBus.gd` | Global signal bus: 107 signals in ~26 categories (`docs/10-signals-reference.md`) |
| 4 | `InputService` | `scripts/services/InputService.gd` | Unified input: keyboard, mouse, touch |
| 5 | `GridManager` | `scripts/grid/GridManager.gd` | 40x40 cell grid (2.0 units/cell, origin -40,-40), building/obstacle placement |
| 6 | `ResourceManager` | `scripts/services/ResourceManager.gd` | 4 resources (gold/steel/oil/wood) + unlock system |
| 7 | `GameManager` | `scripts/services/GameManager.gd` | Save/load and autosave, new game (`request_new_game()` → mode picker), offline progression, 3D↔2D switch (`switch_to_scene()`), reload on language change |
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
| 22 | `TutorialManager` | `scripts/services/TutorialManager.gd` | Prologue once per game (after the title menu, never behind it), the guided coach-mark tutorial (steps derived from what is built) and which tips/helps were seen; state saved with the game (docs/23) |
| 23 | `UILayoutManager` | `scripts/services/UILayoutManager.gd` | Positions panels from `UILayoutConfig` slots, applies theme |
| 24 | `AudioManager` | `scripts/services/AudioManager.gd` | Signal-driven music/SFX/ambient, runtime buses |
| 25 | `DeviceProfile` | `scripts/services/DeviceProfile.gd` | PC/tablet/phone detection + override, UI scale (`content_scale_factor`), applies `UITheme` tokens (palette, contrast, opacity, text size). See `docs/21-interfaz-y-dispositivos.md` |

### Scene Tree (Main.tscn and Main2D.tscn)

`Main.tscn` is the main scene. Its root carries `scripts/view2d/ViewRouter.gd`: when
the preferred view (Settings, or `-- --view=2d`) is the other one, it holds the game
start and switches to `Main2D.tscn` before anything loads. Both scenes carry **the
same UI nodes, with the same names** (today also in the same order); only the world
nodes differ. `tests/view2d/test_view_mode.gd` checks a list of those names in both
scenes — `PauseMenu` and `TitleMenu` find their siblings by name — but not the order,
and `SandboxPanel` is not on the list yet: a new UI node goes into both scenes and
into that list.

```
Main (Node3D, ViewRouter view_mode="3d")
  +-- MonumentalCamera (Camera3D) -- orthographic 45deg RTS camera
  +-- DirectionalLight
  +-- WorldEnvironment
  +-- IslandGenerator (Node3D) -- procedural island mesh: a rounded square that covers the whole 40x40 grid (shore and water start outside it)
  +-- GridOverlay (MeshInstance3D) -- faint cell grid, on by default (Settings toggle), fitted to GridManager at runtime
  +-- BuildingPlacer (Node3D, scenes/buildings/BuildingPlacer.tscn) -- placement/move/demolish, touch placement via PlacementAssist
  +-- OnScreenControls (CanvasLayer 10) -- D-pad, zoom, rotate; "auto" follows the device profile (tablet/phone yes, PC no)
  +-- ResourceHUD (CanvasLayer 10) -- top-left card: named resources + ALMACÉN COMPARTIDO bar with legend
  +-- MapGenerator (Node) -- spawns 18-28 resource deposits (`deposit_count_*`, with a minimum per type)
  +-- ConstructionMenu (CanvasLayer 12) -- big CONSTRUIR button (always visible, bottom centre) + building list
  +-- BuildingInfoPanel (CanvasLayer 10) -- right panel: selected building / deposit info
  +-- MarketPanel (CanvasLayer 11) -- buy/sell UI
  +-- ProgressPanel (CanvasLayer 11) -- milestones + era display
  +-- VictoryScreen (CanvasLayer 20) -- victory overlay
  +-- NotificationPanel (CanvasLayer 11) -- activity log + toasts + status (Habitantes / Obreros / Moral in words)
  +-- TechTreePanel (CanvasLayer 11) -- 3 branches x 5 tiers research UI
  +-- ObjectivePanel (CanvasLayer 15) -- ¿QUÉ HACER?: the next step, from Objectives.next_step()
  +-- ArmyPanel (CanvasLayer 11) -- train units, Military Power, upkeep, who is away on campaign
  +-- SettingsPanel (CanvasLayer 15) -- tabs Audio · Interfaz · Controles · Accesibilidad · Juego (persisted in settings.cfg)
  +-- HelperPanel (CanvasLayer 14) -- help callouts and tip cards (19), one at a time with ✕ + auto-close; building guide; instances HelpIndexPanel
  +-- SkirmishPanel (CanvasLayer 11) -- commit troops and launch an expedition; campaign status while a column is out; "QUE BAJEN" (Final Audit)
  +-- BattleScreen (CanvasLayer 18) -- the 8x8 board plus the expedition map, draft modal and final report (outside UIManager's stack)
  +-- StormHUD (CanvasLayer 16, 11 under modals) -- storm phase indicator (colour + icon, no countdown)
  +-- TutorialPanel (CanvasLayer 19) -- guided coach marks on the real UI; instances PrologueScreen
  +-- AuditWaveBanner (CanvasLayer 19) -- "Oleada X de N" during the Final Audit
  +-- WarReportScreen (CanvasLayer 19) -- queued war reports: blind defence (defense_auto_resolved) and the Tithe (COBRADO / REPELIDO)
  +-- AuditDefeatScreen (CanvasLayer 20) -- a lost siege: what was taken and how to resummon (or the end of a Survival run)
  +-- SandboxPanel (CanvasLayer 11) -- Sandbox mode only: the SANDBOX tab, summon a storm / the Final Audit
  +-- PauseMenu (CanvasLayer 30) -- THE game menu ("☰ MENÚ" top-right): COLONIA + PARTIDA groups, real pause; ESC / Android back
  +-- TitleMenu (CanvasLayer 30) -- main menu on launch and from ☰ MENÚ -> Menú principal

Main2D (Node2D, ViewRouter view_mode="2d") -- world nodes replaced, UI identical
  +-- Camera2D (Camera2DController) / StormTint (CanvasModulate, StormTint2D) / Island (Island2D)
  +-- GridOverlay (GridOverlay2D) / BuildingPlacer (BuildingPlacer2D) / MapGenerator (MapGenerator2D)
  +-- OnScreenControls ... TitleMenu -- the same 23 UI nodes as above

Created at runtime, not in either .tscn:
  PrologueScreen (layer 32, scenes/ui/PrologueScreen.tscn) -- child of TutorialPanel: the lore as a Regency dossier
  HelpIndexPanel (scenes/ui/HelpIndexPanel.tscn, group "help_index") -- child of HelperPanel: the AYUDA index, opened from ☰ MENÚ
  NewGameDialog (layer 40, scripts/ui/NewGameDialog.gd) -- the mode picker, created by GameManager.request_new_game()
  LayoutEditor (layer 35, scripts/ui/LayoutEditor.gd) -- EDITAR DISPOSICIÓN (Settings), created by UILayoutManager
```

UI panels are positioned by `UILayoutManager` using the slot definitions in
`scripts/ui/UILayoutConfig.gd` (20 named slots — 13 screen areas and 7 help-callout
anchors (`tip_*`) —, `NARROW_SLOTS` / `COLUMN_SLOTS` for narrow canvases, panel->slot map, slot
conflicts).
`UIManager.open_panel()` handles stacking and closes conflicting panels.
All styling comes from the static `UITheme` class (dieselpunk metal 9-patch
textures generated by `tools/gen_ui_textures.gd`). Its colours and font sizes are
**tokens** (`static var`) rewritten by `UITheme.configure()` (colour-blind
palettes, high contrast, panel opacity, text size): use `UITheme.POSITIVE` etc.,
never hand-written semantic colours. HUD elements that can be hidden or moved
register in `HudRegistry` (`scripts/ui/HudRegistry.gd`); moved panels are offsets
on top of their slot, saved per device profile and aspect (`LayoutEditor`).
Stretch is `canvas_items` + `aspect=expand` (no black bars). Full detail:
`docs/21-interfaz-y-dispositivos.md`.

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
  Era 3 ceiling without techs = 1000 + 5x500 = **3500**, exactly the price of the HQ
  level 3 upgrade. On top of that, `GameConfig.tech_storage_bonus` adds the storage
  techs: `ind_2` +200, `log_2` +300, `log_5` +500 — **+1000**, so the absolute ceiling
  is **4500** (`GameConfig.get_storage_cap()`). Sandbox ignores all of it
  (`sandbox_storage_cap`).
  Whatever does not fit is lost; `EventBus.storage_overflow` fires and the player is
  warned once per game. Loading a save that holds more than fits trims it proportionally.
- Extractors must touch their deposit (`GameConfig.building_deposit_rules`): sawmill
  next to a forest, gold mine next to a gold vein, foundry next to iron (reach 1); the
  refinery sits on an oil well (reach 0) and consumes it.

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
| House | 2x2 | 50/0/0/30 | 0 | +6 workers (room in houses) | 1 |
| Sawmill | 2x2 | 80/0/0/50 | 2 | 6 wood/12s | 1 |
| Gold Mine | 2x2 | 120/0/0/80 | 3 | 8 gold/12s | 1 |
| Warehouse | 2x2 | 60/0/0/40 | 1 | +500 shared storage | 1 |
| Foundry | 2x2 | 200/0/0/120 | 3 | 5 steel/15s | 1->2 |
| Barracks | 2x2 | 250/100/0/80 | 3 | Trains units (ArmyManager) | 2 |
| Refinery | 2x2 | 300/150/0/100 | 4 | 4 oil/18s | 2->3 |
| Tower | 2x2 | 150/60/20/30 | 1 | Storm mitigation + an artillery crew on defensive boards (only while operational) | 2-3 |
| HQ (capstone) | 2x2 | 500/300/200/200 | 5 | 10 gold/20s | 3 |
| Road | 1x1 | 1/0/0/0 | 0 | +2 morale | deco |
| Garden | 2x2 | 30/0/0/20 | 0 | +5 morale | deco |
| Fountain | 2x2 | 60/20/0/10 | 0 | +7 morale | deco |
| Statue | 2x2 | 120/40/0/0 | 0 | +10 morale | deco |

**Key constraint:** Foundry costs 0 steel (it unlocks steel). Refinery costs 0 oil (it unlocks oil).

### Materials (2026-09-28)

Four workshop materials, appended to `ResourceManager.Type`: `PLANKS` (Sawmill,
"make_planks": 20 wood → 5), `INGOTS` (Gold Mine, 30 gold → 3), `BEAMS` (Foundry, 20
steel + 10 wood → 4), `FUEL` (Refinery, 15 oil → 5) — the first process of each in
`GameConfig.building_processes`; `GameConfig.material_sources` maps material →
building. A material is unlocked when the first of its building finishes
(`ProgressionManager._unlock_material_of`). They are **outside the shared storage**
(`get_total_stored()` skips them, the Tithe does not take them) because the pool is
tuned to the exact HQ L3 price. Advanced buildings ask for them via
`BuildingData.cost_materials` (Barracks planks, Tower/Refinery beams, HQ beams +
ingots + fuel, Statue ingots) and `hq_upgrade_costs`. The HUD shows them in a TALLER
row; `Objectives.make_step_for()` turns a missing material into a `"make"` step.

**Era gates:** Foundry (era 2) needs Sawmill + Gold Mine + House + Warehouse;
Refinery (era 3) needs Foundry + Barracks (`building_prerequisites`).

**Quick guide:** `scripts/ui/QuickGuide.gd`, one screen with four blocks (resources,
extraction, buildings and roads, progress), opened by TutorialPanel once per game
after the prologue (help id `quick_guide`); the same texts are `guide_qg_*` in the
AYUDA index.

### Road network (2026-09-28)

- **Every building is at least 2x2**, except the road (1x1). GLBs made for 1x1 are
  scaled up with `BuildingData.model_scale`; `BuildingData.instantiate_model()` is the
  only way to spawn one.
- **Everything touches a road joined to the Núcleo.** `PlacementRules.is_connected_spot()`
  is part of `evaluate_placement()` (reason `"road"`, feedback `LBL_NEEDS_ROAD`); a new
  road must touch the network or the Núcleo. No Núcleo on the grid (hand-built test
  scenes) means no rule. A road whose removal would strand a building cannot be
  demolished or moved (`road_removal_strands()`).
- **The Núcleo starts with its sidewalk:** `GameManager.pave_core_ring()` lays the 16
  road cells around it in `_new_game()`. Roads cost 1 gold, are drawn as full-cell
  pavement with a curb on the unconnected sides (3D and 2D), and take no damage
  (`BuildingHealth.is_immune()`: the Núcleo and roads).
- `PlacementRules.road_route(origin, size)` gives the free cells to pave to join a
  footprint (tests and `tools/line_probe_player.gd` use it); `walk_route(node)` gives
  the road path from the Núcleo to a building.
- **Workers you can see:** `scripts/map/WorkerWalkers.gd` (child of both placers)
  sends little figures from the Núcleo along `walk_route()` when a building gets
  staffed, plus one every 25 s as a shift change. View only; staffing stays in
  PopulationManager.
- **Auto-road:** `evaluate_placement()` accepts an unconnected spot when a free route
  to the network exists and returns it as `"route"`; the placers charge building +
  route together (`Rules.cost_with_route`, 1 gold per tile) and lay it with
  `Rules.pave_route()` (emits `building_placed` per tile). Roads are instant
  (`build_time = 0`). No route → reason `"road"` (`LBL_NEEDS_ROAD`).
- **No road, no work:** `PopulationManager._recalculate_all()` sets the meta
  `connected` on every building; an unconnected one gets no workers, a house gives no
  room, ProductionManager skips it and its badge says "sin carretera" (`no_road`).
- **Save format 2:** `_write_save()` writes `"format": 2`. A save without it (or older)
  is copied to `user://save_game.v1-<date>.json` and a new game starts, with a notice
  (`MSG_SAVE_OLD_FORMAT`). A test that writes a save fixture adds `"format"`.

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

Events fire every 2-5 minutes (30-60s in dev mode: `event_interval_*_dev`). Not before
the SURVIVAL phase (first Warehouse), never in Sandbox, and Constructor gets only the positive ones.

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

**In Campaña, HQ level 3 does not win the game.** `ProgressionManager._complete_milestone()`
catches `hq_max` and, when `GameMode.audit_enabled()`, calls `summon_final_audit()`:
the Regency comes down for a 3-5 wave siege (`final_audit_waves`) fought by whatever
garrison is at home plus the tower crews, with attrition across waves and no
retraining in between. The siege is summoned pending; the player walks in with "QUE
BAJEN" in `SkirmishPanel`. Surviving it emits `storm_halted_forever` (the Storm stops
for good) and only then `victory_achieved`. Losing is **not** a game over in Campaña —
maximum Tithe, maximum storm damage, and the siege can be summoned again once
`final_audit_resummon_min_units` (3) units stand.

Per mode: **Constructor** wins directly at HQ 3 (`GameMode.capstone_wins()`, no siege);
**Supervivencia** gets one siege only — losing it emits `run_ended` and seals the save;
**Sandbox** never summons it on its own (only from the SANDBOX tab) and has no victory.
Full detail in `docs/15-combat.md` §6 and `docs/20-modos-de-juego.md`.

### Game Modes — full doc: `docs/20-modos-de-juego.md`

**Only Campaña is offered today (2026-09-28).** `GameMode.OFFERED` lists the modes
the New Game dialog shows; Constructor, Supervivencia and Sandbox are commented out
there — their cards are built but hidden, and their rules, saves and tests stay
intact (an old save in one of them still loads). Uncomment a line to bring it back.

Four modes, picked in the New Game dialog (`NewGameDialog`, opened by
`GameManager.request_new_game()` from every entry point) and fixed for the run:
**Campaña** (default; old saves load as it), **Constructor** (no Storm/Tithe/siege,
HQ 3 wins directly, only good random events), **Supervivencia** (storms x0.6 calm,
+1 severity, x1.25 damage, x1.5 Tithe, 75% start, no offline, one Final Audit —
losing ends the run and seals the save), **Sandbox** (era 3, everything unlocked,
no caps, resources refill, Storm/Audit only via the SANDBOX tools tab, no victory).
`scripts/services/GameMode.gd` (static class, not an autoload) holds the mode and
answers rule queries; the table is `GameConfig.game_mode_rules`. Services ask a
rule (`GameMode.storm_enabled()`), never compare the mode. Saved as
`"game_mode": {"mode", "result"}`; `GameMode.begin_run()` is its reset.

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
- The Ejército and Escaramuzas entries of ☰ MENÚ → COLONIA only appear once a Barracks exists.
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
- **UI:** `BattleScreen` (one overlay, four views that never share the screen: the
  8x8 board, the expedition map, the draft modal and the final report),
  `SkirmishPanel` (commit troops and launch; campaign status while a column is out;
  "QUE BAJEN"), plus the war reports: `WarReportScreen`, `AuditWaveBanner`,
  `AuditDefeatScreen`.

Three roads reach the same board: an expedition node (player picks the party in
`SkirmishPanel`, which calls `CombatManager.launch_expedition()`; a win pays loot),
the Tithe defence (`get_garrison()` + tower crews, a win pays nothing but the Tithe
goes uncollected), and a Final Audit wave (the siege garrison + tower crews, carried
wave to wave with its damage). When the Tithe lands while a board is already open,
`AutoResolver` plays the *same* `Encounter` with the AI on both sides — there is no
second combat formula anywhere — and `WarReportScreen` shows the result.

**The expedition runs end to end from the UI:** launch in `SkirmishPanel`, the node
map / draft / final report in `BattleScreen` (`select_node()`, `apply_draft()`,
`abandon_expedition()`), attrition and permadeath across nodes, units away are
locked out of the garrison, and a run in flight is saved and reopens its map on load
(`expedition_resumed`). `start_skirmish()` is no longer called from `scripts/` (only
tests use it); the dev-only test fight goes through `dev_start_encounter()`.

**Towers:** each standing tower cuts storm damage by 15% (cap 60%,
`storm_tower_mitigation*`) and fields one artillery crew on defensive boards — Tithe
and Final Audit — outside the deploy cap, in the back row (max 2,
`storm_tower_garrison_*`); crews lost during a siege are not replaced. Only while
operational (not ruined, not under construction). They have no attack of their own on
the base map.

**Unit icons:** the board paints unit silhouettes (`assets/textures/ui/units/*.png`,
generated by `tools/gen_unit_icons.gd`, read by `UITheme.unit_icon()`), tinted per
side, with the boss marked; the translated name's initial is only a fallback when a
PNG is missing.

### Tech Tree (15 techs, 3 branches)

- **TechTreeManager** + `GameConfig.tech_definitions`. Branches: Industrial,
  Military, Logistics — 5 linear tiers each (tier N requires tier N-1).
- Research costs **resources** (not points) and takes time; only one tech at a time.
- Bonuses are permanent: production multiplier, storage, consumption reduction,
  morale recovery (Military branch), market spread / build speed (Logistics).
- No HQ requirement (deliberate: the HQ is era 3). The old vestigial `_research_points`
  counter was removed; a `research_points` key in old saves is ignored.

### Game Phases (onboarding pacing)

`GameConfig.Phase` enum: FOUNDATION -> SETTLEMENT -> ECONOMY -> SURVIVAL -> EXPANSION.
`phase_triggers` gates early-game pacing (`early_consumption_interval`,
`early_morale_penalty`, `early_growth_interval`) so consumption/morale pressure
ramps up gradually instead of punishing the first minutes.

### Audio

- **AudioManager** creates Music/SFX/Ambient buses at runtime and auto-plays from
  ~26 EventBus signals (era music crossfade, build/trade/event SFX, combat, the Final
  Audit, etc.).
- Assets: 4 music tracks + 16 SFX in `assets/audio/{music,sfx}/` (`ambient/` holds only
  a `.gitkeep`). The 9 combat keys are aliases onto existing SFX and the `combat` theme
  borrows `era_3_petroleum`. Missing files are skipped silently — audio never crashes the game.
- Music can be switched off (`GameConfig.audio_music_enabled`, `set_music_enabled()` /
  `toggle_music()`, emits `music_toggled`); `play_music()` is the single guard.
- API: `play_sfx(key)`, `play_music_for_era(era)`, `set_*_volume(linear)`.
  Manifest of expected keys: `assets/audio/MANIFEST.md`.

### User Settings (`user://settings.cfg`)

Device-local preferences, separate from the game save. `GameConfig.load_user_settings()`
runs in its `_ready()` (before AudioManager applies volumes); anything that changes a
preference calls `GameConfig.save_user_settings()`. Currently stored:
- `[audio]`: `master` / `music` / `sfx` / `ambient` volumes (sliders in SettingsPanel)
  and `music_enabled`;
- `[ui]`: `grid_visible` (map grid toggle; GridOverlayControl applies it, BuildingPlacer
  restores it after placement), `helper_visible` (help callouts, on by default),
  `touch_controls` (`auto` / `always` / `never`; "auto" follows the device profile:
  tablet and phone yes, PC no — a touch on a touch laptop does not turn them on) and
  `touch_controls_opacity`, `view_mode` (`3d` / `2d`), `fullscreen`, `locale`;
- `[interfaz]`: device profile, UI scale, text size, palette, high contrast, panel
  opacity, hidden HUD elements, moved layout — docs/21.

Never put any of this in the save, and never put game state in `settings.cfg`. The
locale is `es`/`en`, applied to `Tr` at startup. The language selector lives in SettingsPanel:
`GameConfig.set_locale()` saves it and emits `EventBus.locale_changed`, and GameManager
answers by saving and reloading the scene with the same game (`reload_keeping_game()`),
so every panel is rebuilt in the new language (the in-memory notification log is lost
and Settings closes; accepted). With a board open it does not reload
(the board is not saved); the language shows everywhere on the next start.

### Save/Load System

- Path: `user://save_game.json`
- Saves (top-level keys written by `GameManager._write_save()`): `resources`, `buildings` (level, name, construction state, health), `deposits`, `camera`, `progression` (eras, milestones, played time, and the `final_audit`), `market`, `unlocked_resources`, `population`, `random_events`, `active_processes`, `tech_tree`, `army`, `expedition` (CombatManager: the run in flight), `storm`, `tutorial`, `game_mode`. Same save for the 3D and 2D views
- Cloud: `CloudSaveManager` (Supabase REST) implements anonymous/email auth + save/load, but no game code calls it yet — local JSON is the only active path
- Auto-saves on: building placed/moved/renamed/demolished, deposit depleted, tech research, and (debounced by
  `GameConfig.autosave_debounce`) trades, training, processes, upgrades, storm phases, Tithe, Final Audit, expedition
  steps and fight results; plus every `GameConfig.autosave_interval` real seconds, on window close, and on
  pause/focus-out on mobile. `GameManager.request_save()` is the entry point for new triggers
- Fights are never saved: a checkpoint is written when a board opens, and nothing is written while
  `CombatManager.is_save_safe()` is false (fight in play, or a siege-wave report not yet closed). Quitting mid-fight
  replays it from the start. A save made during the Tithe reloads with the Tithe re-demanded (defence or payment)
- The game starts only once `Main` is ready (GameManager waits for the scene root), so load signals reach the UI.
  An unreadable save is copied to `user://save_game.corrupt-<date>.json` before a new game replaces it
- Offline progression: calculates production earned while game closed (max 8h, `max_offline_seconds`; off in Supervivencia)
- A lost Survival run is written once more with `"result": "defeat"` and then **sealed**: GameManager never writes it
  again, loading it shows the end screen (only Nueva partida or Salir) and the title menu offers no "Continuar"

---

## Project Structure

```
tormenta-imperial/
+-- project.godot                    # Engine config, 26 autoloads (25 game + BeckettRuntime)
+-- export_presets.cfg               # Windows Desktop, Android, Android QA (emulador) — no secrets
+-- LICENSE, THIRD-PARTY-NOTICES.md, licenses/  # Licence, third-party notices, the engine's copyright text
+-- CLAUDE.md                        # THIS FILE - AI guidance
+-- readme.md                        # Game overview (Spanish, public)
+-- docs/                            # Per-system deep docs 01-23 (INDEX.md); media/ = screenshots
+-- specs/001-combate-pve/           # Spec, plan and tasks for the combat pillar
+-- .specify/memory/constitution.md  # Non-negotiable project rules (Spec-Driven Development)
+-- qa/maestro/                      # Maestro flows for the Android tablet emulator (QA APK, coordinates + screenshots)
|   +-- 01_...08_*.yaml              # One regression flow per tablet bug (README.md explains how to run them)
|   +-- comun/                       # Shared sub-flows: start, new game, skip lore, wait
|   +-- herramientas/                # Python helpers to collect and compare screenshots
+-- tests/                           # gdUnit4, 102 suites: audio/ build/ buildings/ combat/ economy/ input/
|                                    #   integration/ map/ modes/ save/ storm/ tutorial/ ui/ view2d/
|   +-- save/save_parking.gd         # Parks the real save during a suite; refuses the player's dir
|   +-- save/settings_parking.gd     # Same for settings.cfg and GameConfig's UI fields
+-- scenes/
|   +-- main/Main.tscn               # Entry scene (3D); ViewRouter may hand over to Main2D
|   +-- main/Main2D.tscn             # The 2D view: same UI nodes, 2D world nodes
|   +-- buildings/BuildingPlacer.tscn
|   +-- ui/                          # One .tscn per panel (25), incl. PrologueScreen and HelpIndexPanel
+-- scripts/                         # 101 .gd files, ~34.5k lines
|   +-- buildings/
|   |   +-- BuildingData.gd          # Resource class for building definitions (get_display_name())
|   |   +-- BuildingPlacer.gd        # 3D placement/move/demolish + mesh spawning
|   |   +-- PlacementRules.gd        # Shared placement rules (deposit adjacency, footprint) for 3D and 2D
|   |   +-- PlacementAssist.gd       # Touch placement (tap aims, tap ghost/✓ builds), valid-spot highlight — docs/21 §9
|   |   +-- BuildingStatusBadge.gd   # Worker pictogram / "Zzz" + why a building is stopped (3D)
|   |   +-- DieselpunkBuildingFactory.gd  # Procedural 3D meshes (fallback when there is no GLB)
|   +-- camera/MonumentalCamera.gd   # Orthographic 45deg RTS camera
|   +-- combat/                      # PURE models: no nodes, no signals, no global RNG
|   |   +-- CombatUnit.gd            # One unit: hp, position, draft bonuses, morale mods
|   |   +-- CombatRules.gd           # Static maths: damage, initiative, range, BFS, timeout
|   |   +-- Encounter.gd             # One board: deploy, turn order, actions, resolution
|   |   +-- CombatAI.gd              # Plans one unit's turn; drives either side
|   |   +-- AutoResolver.gd          # Plays a whole Encounter headless (AI on both sides)
|   |   +-- Expedition.gd            # One roguelike run: map, party, loot, state
|   |   +-- ExpeditionGenerator.gd   # Seeded map graph, rosters, rewards, drafts
|   |   +-- FinalAudit.gd            # The closing siege: waves, garrison, resummon
|   +-- grid/
|   |   +-- GridManager.gd           # 40x40 cell grid; the island covers every cell
|   |   +-- GridOverlayControl.gd    # Applies the grid toggle to the 3D overlay
|   +-- map/
|   |   +-- IslandGenerator.gd       # Procedural island mesh
|   |   +-- MapGenerator.gd          # Random deposit spawning
|   |   +-- StormSky.gd              # Autoload: sky/light during the storm
|   +-- storm/StormCycle.gd          # PURE model: the storm's phase clock
|   +-- services/                    # The 25 game autoloads (table above) + BeckettGate.gd
|   |   +-- ...Manager.gd / EventBus.gd / GameConfig.gd / Tr.gd / DeviceProfile.gd
|   |   +-- GameMode.gd              # Static: the mode of this run and its rules
|   |   +-- Objectives.gd            # Static: the next step for ¿QUÉ HACER?
|   |   +-- FloatingText.gd          # Static utility: animated 3D text labels
|   +-- ui/                          # 38 scripts: one per panel, plus
|   |   +-- UITheme.gd               # Static dieselpunk theme: tokens, fonts, styleboxes, unit icons
|   |   +-- UILayoutConfig.gd        # Screen slots, panel->slot map, conflicts
|   |   +-- HudRegistry.gd, LayoutEditor.gd        # Hideable/movable HUD elements, the layout editor
|   |   +-- ModalKit.gd              # Builds the war-report / dialog cards from UITheme pieces
|   |   +-- PauseMenu.gd, TitleMenu.gd, NewGameDialog.gd, PauseWatcher.gd
|   |   +-- BattleScreen.gd, SkirmishPanel.gd, WarReportScreen.gd, AuditWaveBanner.gd, AuditDefeatScreen.gd
|   |   +-- TutorialPanel.gd, CoachArrow.gd, PrologueScreen.gd, RegenciaSeal.gd
|   |   +-- HelperPanel.gd, HelpCallout.gd, HelpCatalog.gd, HelpTargets.gd, HelpIndexPanel.gd
|   |   +-- SandboxPanel.gd, SettingsPanel.gd, StormHUD.gd, ObjectivePanel.gd, ArmyPanel.gd, TechTreePanel.gd
|   |   +-- BuildingInfoPanel.gd, ConstructionMenu.gd, MarketPanel.gd, NotificationPanel.gd,
|   |   +-- OnScreenControls.gd, ProcessActionsPanel.gd, ProgressPanel.gd, ResourceHUD.gd, VictoryScreen.gd
|   +-- view2d/                      # The 2D view (docs/18): same services, flat world
|       +-- ViewRouter.gd, ViewMode.gd, View2D.gd  # Scene routing, the view preference, world<->pixel maths
|       +-- Camera2DController.gd, Island2D.gd, GridOverlay2D.gd, StormTint2D.gd
|       +-- BuildingPlacer2D.gd, MapGenerator2D.gd, Building2D.gd, BuildingArt2D.gd, BuildingIcon2D.gd
|       +-- Deposit2D.gd, StatusBadge2D.gd, FloatingText2D.gd
+-- data/buildings/                  # 14 .tres building definitions
+-- assets/
|   +-- audio/{music,sfx,ambient}/   # 4 tracks + 16 SFX (see MANIFEST.md); ambient/ empty
|   +-- models/buildings/<id>/       # GLB models (12 of 14 buildings)
|   +-- textures/                    # metal_plate PBR maps; ui/ 9-patch sprites, ui/icons/, ui/units/ (silhouettes)
|   +-- fonts/, branding/            # Fonts with their licences; logo, banner, key art
+-- tools/
    +-- run_tests.sh, run_tests.ps1  # THE way to run the tests (private user dir)
    +-- package_release.sh, .ps1     # Zips an exported .exe / APK with LICENSE, notices and dist/LEEME-*.txt (docs/19 §8)
    +-- gen_godot_notices.gd         # Regenerates licenses/GODOT-COPYRIGHT.txt from the engine binary
    +-- gen_ui_textures.gd, gen_resource_icons.gd, gen_unit_icons.gd  # Asset generators (headless, -s)
    +-- render_brand.gd, render_branding.gd, render_catalog.gd, showcase_shots.gd  # Branding and screenshots
    +-- *_probe.gd                   # Dev probes, see below
    +-- ui_audit.gd, ui_tour.gd      # Screenshot every panel
    +-- beckett_mcp.py               # Dev bridge helper
    +-- blender_helper.py, generate_buildings.py, build_decorations.py, blender/  # Blender MCP model gen
```

Probes come in two shapes, and **every one of them runs with a private user dir**
(the `override.cfg` of "Running the Project"), because they seed and save games:
- `extends Node` probes (`audit_probe`, `battle_probe`, `expedition_probe`,
  `storm_probe`, `tutorial_probe`, `island_probe`, `modes_probe`, `balance_probe`,
  `ui_audit`, `ui_tour`, `showcase_shots`) are registered **temporarily** as an
  autoload in `project.godot`, run (with a window, except `balance_probe`, which is
  headless) and removed again. Most no-op unless
  `GameConfig.dev_mode`. `ui_audit.gd` seeds a game and places buildings, which
  autosaves: never run it against the player's dir.
- `extends SceneTree` launchers run directly with `-s`, no `project.godot` edit:
  `godot --path . -s tools/menu_probe.gd -- --shot-size=1280x800 --profile=tablet`
  (also `interfaz_probe`, `onboarding_probe`, `view2d_probe`, each driving its
  `*_probe_runner.gd`); `line_probe.gd` (the whole campaign at real timings,
  headless, `-- --no-dev --seeds=1,2,3`, refuses to run without its own user dir,
  docs/22) and `siege_probe.gd` (siege balance, docs/17).
- Screenshots go to `docs/media/dev/` (git-ignored).

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

- **GDScript for everything**, combat included. The whole project (25 game autoloads + all UI) is GDScript; a second language adds build times, cross-runtime debugging and marshalling for no benefit here.
- The old plan put unit AI, combat math and pathfinding in C# **for performance**. That argument does not apply at the agreed combat scale: an 8x8 board with 4–6 units per side. GDScript is orders of magnitude more than enough.
- **Migrate later, only on evidence**: if a profiled module proves too slow, port that module to C#. Do not create the .NET project speculatively.

### Adding a New Building

1. Create `data/buildings/my_building.tres` with BuildingData fields
2. Add limit in `GameConfig.building_limits`
3. Add prerequisites in `GameConfig.building_prerequisites` (if any)
4. Add processes in `GameConfig.building_processes` (if any), and a row in `GameConfig.building_deposit_rules` if it must touch a deposit
5. Give it a look in both views: a GLB in `model_scene` (or a case in `DieselpunkBuildingFactory`) for 3D, and a drawing in `scripts/view2d/BuildingArt2D.gd` for 2D (map, ghost and menu icon share it)
6. Add translations in `Tr.gd` (both ES and EN), including `BLD_<ID>_NAME` and `BLD_<ID>_DESC`. UI shows buildings through `BuildingData.get_display_name()` / `get_description()`, never the raw `.tres` fields
7. Building auto-appears in ConstructionMenu (loads all .tres from data/buildings/)

### Adding a New Signal

1. Add to `EventBus.gd` under the appropriate category
2. Emit from the producing service
3. Connect from consuming service/UI in `_ready()`

### Adding Persistent State

Any state that travels in the save file has to be cleared in its service's `reset()`,
and that `reset()` has to be called from **all three** places in `GameManager` that
start a fresh game: `_new_game()`, `clear_save()` and `clear_save_and_reload_from()`.
They are three duplicated lists and it is easy to update one and forget the others —
that is exactly how `ProcessManager` shipped without a `reset()` at all. Each of the
three starts with `GameMode.begin_run()` (or `GameMode.load_save_data()` when
reloading a save) **before** the resets, because the resets read the mode's rules.

Checklist:
1. `get_save_data()` / `load_save_data()` on the owning service, and its key in
   `GameManager._write_save()` and the load path.
2. `reset()` in the service, called from the three places above.
3. `load_save_data()` must be **idempotent**: derive from what was saved, never add on
   top of what is already there (loading twice without a `reset()` used to double the
   tech bonuses).
4. Old saves: a missing key means the default, an unknown key is ignored.
5. A test that writes `user://save_game.json` parks the player's save with
   `tests/save/save_parking.gd` (`park()` in `before_test()`, `restore()` in
   `after_test()`) and skips itself in the player's dir: `func before(do_skip := Parking.in_player_dir(),
   skip_reason := ...)`. A test that writes `settings.cfg` uses
   `tests/save/settings_parking.gd` (byte-for-byte copy and restore). `save_parking`
   refuses to touch the player's dirs (`player_dirs()`: the editor's
   `Godot/app_userdata/Tormenta Imperial` and the export's `TormentaImperial`);
   `settings_parking` has no such guard, so it relies on the wrapper's own user dir.
6. Run the suite only through `tools/run_tests.sh` / `.ps1`, which gives it its own
   user dir. Never write to `user://` from a probe, tool or experiment without an
   `override.cfg` of your own (see "Running the Project"); delete it afterwards.

Rules:
- `reset()` **throws away, it never cancels**. Do not reuse `cancel()` or any refund
  path: a new game must not pay out resources from the old one.
- `reset()` **never notifies the player**. A new game does not announce what it lost.
- If the state is transient and rebuilt from signals (e.g. "is ash falling"), it also has
  to be **re-derived on `game_load_completed`**, or a save made mid-event reloads blind.
- Autoloads survive scene reloads. Anything you do not clear is still there.
- Device preferences go to `settings.cfg` (`GameConfig.save_user_settings()`), never
  into the save; game state never goes into `settings.cfg`.

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
- `building_deposit_rules` - which extractor must touch which deposit
- `game_mode_rules` / `sandbox_*` - per-mode rules and multipliers on top of the base
  values (modes apply factors; the balance line changes the base values — docs/20, docs/22)
- `population_floor` / `population_regrow_floor` - the ruin floor
- `autosave_interval` / `autosave_debounce` / `max_offline_seconds` - saving and offline

### Shared Utilities

- **FloatingText** (`scripts/services/FloatingText.gd`): Static class for spawning animated 3D text labels. Use `FloatingText.spawn()` for custom text or `FloatingText.spawn_resource()` for resource gain/loss display (`spawn_on()` / `spawn_resource_on()` work on any node, 2D included; the 2D view draws them with `FloatingText2D`). Colors come from `GameConfig.resource_colors`.
- **DieselpunkBuildingFactory** (`scripts/buildings/DieselpunkBuildingFactory.gd`): Static factory generating dieselpunk building meshes from primitives (rivets, pipes, brass/rust palette, shared PBR metal maps). `create(building_id, cell_size, grid_size)` and connectivity-aware `create_road(cell_size, neighbors)`. Called by BuildingPlacer and ConstructionMenu previews **as the fallback when a building has no `model_scene` GLB** — today that is only `nucleo` and `road`.
- **UITheme** (`scripts/ui/UITheme.gd`): Static theme — call its factories for any new UI instead of hand-styling controls.

### Dev Mode

`GameConfig.dev_mode` multiplies every duration by `dev_time_scale` (0.2, i.e. five
times faster — not "1-2 seconds") and shows the dev buttons (clear save in
ResourceHUD, test fight in SkirmishPanel). It is **never hand-set**: it is decided by
feature tag in `GameConfig._resolve_dev_mode()` — `true` when running from the editor
binary (F5, tests, probes: feature `editor`), `false` in every export, release or
debug. Force it with user args after `--`: `-- --dev` / `-- --no-dev` (the balance
probes use `--no-dev` for real timings). On Android there are no user args, so an APK
is always `dev_mode=false`.

### Exporting

`export_presets.cfg` (versioned, no secrets, no absolute paths) has three presets —
full guide in `docs/19-exportar.md`:
- **Windows Desktop**: one `build/windows/TormentaImperial.exe` with the PCK embedded
  (`build/` is untracked). Forward+, needs Vulkan, no .NET needed by the player.
- **Android**: debug APK `build/android/TormentaImperial-debug.apk` (arm64-v8a, sensor
  landscape, immersive fullscreen, no permissions, prebuilt templates, package
  `com.bryankey.tormentaimperial`); Mobile renderer through `rendering_method.mobile`.
  Release signing only from `GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}`.
- **Android QA (emulador)**: x86_64 APK with `--rendering-method gl_compatibility
  --rendering-driver opengl3` (the emulator's Vulkan presents black), package
  `...tormentaimperial.qa`, used by the Maestro flows in `qa/maestro/`.

All three share one `exclude_filter`: `tests/`, `tools/`, `docs/`, `specs/`,
`reports/`, `addons/gdUnit4`, `addons/beckett`, `.claude/`, `.specify/`, `.beckett/`,
`.cursor/`, `.vscode/`, `.mcp.json`, `secret.json`, `.env*`, `override.cfg`,
`estrategia/`, `ui_tour/`, `build/` and `*.md`. `tests/build/test_export_guards.gd`
checks the exclusions, the Beckett gate, `dev_mode` and that no signing secret is in
a preset. The `BeckettRuntime`
autoload points at `scripts/services/BeckettGate.gd`, which loads the addon's runtime
only in the editor and frees itself in an export. Exported Windows builds save to
`%APPDATA%\TormentaImperial\` (`config/use_custom_user_dir.template`), not the
editor's user dir; Android saves inside the app's internal storage. To hand a build to
testers, `tools/package_release.sh` (or `.ps1`) zips the exported `.exe` / APK with
`LICENSE`, `THIRD-PARTY-NOTICES.md`, `licenses/` and a `LEEME` into the git-ignored
`dist/`; it exports nothing itself.

---

## Planned (Not Yet Implemented)

Full roadmap, what is done and the backlog: `docs/13-roadmap.md`.
Combat detail, including a verified list of gaps: `docs/15-combat.md` §10.

Everything the old list held as missing has landed: the expedition UI (map, draft,
final report), the after-action report for the blind defence (`WarReportScreen`),
unit silhouettes on the board, the 2D view, game modes, the configurable UI, touch
placement, the prologue/tutorial/help index, and the Windows and Android exports.
What is still not there:

- **Cloud save wiring:** `CloudSaveManager` exists but needs credentials (the export
  excludes `.env`, so they would have to come from `user://` or the build) and a UI
- **Missions/contracts:** timed delivery challenges for rewards
- **Tower behaviour beyond the boards:** towers mitigate storm damage and field crews
  on defensive boards; they have no attack of their own on the base map
- **Dedicated combat audio and an ambient track** (today aliases and an empty `ambient/`)
- **Open balance decisions** listed in `docs/22-linea-jugable.md` §7 and
  `docs/13-roadmap.md` (a "resolve alone" Tithe, the era-3 storage squeeze, a scripted
  era-1 storm, the length of era 1)
- **Distribution:** Windows code signing (SmartScreen), Android release keystore, AAB
  and store listing
- **Out of scope for v1:** PvP and co-op
