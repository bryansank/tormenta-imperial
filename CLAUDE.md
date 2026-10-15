# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Tormenta Imperial** is a dieselpunk management + turn-based strategy game built in Godot 4.7 .NET. The player builds and manages a persistent base on a procedurally generated island (an irregular coast with bays and capes on a 60-74 x 60-74 grid rolled per game, the sea inside the grid, 3-6 deposits of each type), where every building is joined to the Núcleo by roads and staffed by workers you can see walking, progressing through 3 economic eras while the Imperial Storm keeps coming back to collect. The management loop is complete (economy with workshop materials, population, market and laboratory as buildings, tech tree, army training, audio). Turn-based PVE combat is live: an 8x8 tactical board, roguelike expeditions with their own map and drafts, the Tithe fought instead of paid, and the Final Audit — in Campaña HQ level 3 no longer wins, it summons a 3-5 wave siege you have to survive. Around that core: four game modes (only Campaña is offered today; the other three are set aside, not deleted), a 2D top-down view next to the 3D one, a configurable UI with PC/tablet/phone profiles and touch placement, a prologue + guided tutorial + help index, and Windows and Android exports. See `docs/15-combat.md` for the combat pillar and `docs/13-roadmap.md` for what is done and what is left.

Detailed per-system docs live in `docs/` (see `docs/INDEX.md`).

> "On the mud of history, we shall build monuments of steel."

## Tech Stack

- **Engine:** Godot 4.7 .NET Edition (Forward+ renderer on PC, Mobile renderer on Android via `rendering_method.mobile`)
- **Languages:** GDScript for everything, turn-based combat included (it shipped in GDScript). There is no C# project (no `.csproj`, no `.cs` files) and none is planned for v1 — see "Key Rule" below
- **Tests:** gdUnit4 (`addons/gdUnit4`), ~1850 tests in 141 suites under `tests/` (audio, build, buildings, combat, economy, input, integration, map, modes, save, storm, support, tutorial, ui, view2d) — **always** through the wrapper:
  ```bash
  GODOT=/path/to/godot tools/run_tests.sh              # whole suite
  GODOT=/path/to/godot tools/run_tests.sh -a tests/combat
  ```
  (`tools\run_tests.ps1` on PowerShell; extra args go to GdUnitCmdTool). It writes a temporary `override.cfg` so the run gets its own user dir (`%APPDATA%\TormentaImperial_tests`, override with `TI_TEST_USER_DIR`; it refuses the player's dir names), runs headless with `--ignoreHeadlessMode`, and removes the file on exit. Never call `GdUnitCmdTool.gd` directly: that runs in the editor's user dir, where the player's `save_game.json` lives. As a backstop, `tests/save/save_parking.gd` refuses to park in the player's dir and the suites that write the save skip themselves there. Two traps in a **fresh worktree**: `addons/gdUnit4/bin/` (where `GdUnitCmdTool.gd` lives) is caught by the `bin/` rule of `.gitignore`, so it has to be copied from a checkout that has it; and there is no `.godot/` yet, so run one headless `--import` first (with its own `override.cfg`)
- **Backend:** Supabase (CloudSaveManager implements auth + save/load via REST, but nothing calls it yet — needs `.env` config and UI wiring)
- **Multiplayer:** none. PvP and co-op are out of scope for v1 (constitution v2.0.0 dropped the old Nakama plan; if PvP ever happens it would sit on Supabase)

## Running the Project

1. Open the project folder in **Godot 4.7 .NET Edition**
2. Press **F5** to run. The title menu (`TitleMenu`) opens first over the loaded game
3. WASD / arrows to pan, Q/E or right-drag to rotate, scroll to zoom, middle-drag or left-drag on the ground to grab-pan, F11 fullscreen
4. Touch: one finger grabs the terrain, two-finger pinch to zoom and twist to rotate (3D only); tap to aim a building, tap the ghost / ✓ to build (docs/21 §9)
5. A fresh game: ☰ MENÚ → Menú principal → Nueva partida (mode picker; today it only offers Campaña). It never deletes the current game: it goes to a new slot (up to 5, see "Save/Load System"). Deleting `user://partidas/` starts from scratch
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

28 autoloads in `project.godot`: the 27 game services below, plus `BeckettRuntime`, the `addons/beckett` dev bridge. `BeckettRuntime` loads between `AudioManager` and `DeviceProfile`, and `RankManager` goes after `DeviceProfile` (last); it points at `scripts/services/BeckettGate.gd`, which loads the addon's runtime only in the editor, and it is not a game system. `GameMode`, `UITheme`, `UILayoutConfig`, `HudRegistry`, `FloatingText` and `Objectives` are static helpers (a `class_name` or a `preload`), not autoloads.

| # | Service | File | Purpose |
|---|---------|------|---------|
| 1 | `Tr` | `scripts/services/Tr.gd` | i18n translation (ES/EN) |
| 2 | `GameConfig` | `scripts/services/GameConfig.gd` | All tunable values, balance, durations |
| 3 | `EventBus` | `scripts/services/EventBus.gd` | Global signal bus: 118 signals in ~30 categories (`docs/10-signals-reference.md`) |
| 4 | `InputService` | `scripts/services/InputService.gd` | Unified input: keyboard, mouse, touch. Its child `TouchTooltip` (`scripts/ui/TouchTooltip.gd`, layer 50) is "hold to read": on touch, a finger held still 0.5 s on a Control shows its tooltip in a bubble without pressing it (docs/21 §9) |
| 5 | `GridManager` | `scripts/grid/GridManager.gd` | Cell grid rolled per game (width and height apart, 60-74, even, `grid_width_*` / `grid_height_*`; 2.0 units/cell, centred on the world origin; saved as `"grid"`, a save without it is 40x40) plus the island seed and the **land mask** (`is_land_cell()`, from `IslandShape`; water is never free), building/obstacle placement; emits `grid_resized` |
| 6 | `ResourceManager` | `scripts/services/ResourceManager.gd` | 4 resources (gold/steel/oil/wood) + unlock system |
| 7 | `GameManager` | `scripts/services/GameManager.gd` | Save/load and autosave of up to 5 saved games (`SaveSlots`, `save_path()`, `open_saves_list()`), new game (`request_new_game()` → mode picker, never deletes), offline progression, 3D↔2D switch (`switch_to_scene()`), reload on language change |
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
| 18 | `DayClock` | `scripts/services/DayClock.gd` | Day/night clock: ticks the pure `scripts/storm/DayCycle.gd` (dawn, day, dusk, night; 16 min, night 3 min), emits `day_phase_changed`, answers `is_night()` / `light_weight()`; the hour travels in the save (`day`). Visual only today (docs/21 §12) |
| 19 | `StormSky` | `scripts/map/StormSky.gd` | Paints the `WorldEnvironment`, sun and island: the time of day from `DayClock` (refreshed every few seconds) with the storm's ash blended on top; also the shared window-glow material |
| 20 | `TechTreeManager` | `scripts/services/TechTreeManager.gd` | 15 techs in 3 branches, permanent bonuses |
| 21 | `CloudSaveManager` | `scripts/services/CloudSaveManager.gd` | Supabase auth + cloud save/load (unwired) |
| 22 | `UIManager` | `scripts/services/UIManager.gd` | Panel stacking, ESC-close, slot conflict resolution |
| 23 | `TutorialManager` | `scripts/services/TutorialManager.gd` | Prologue once per game (after the title menu, never behind it), the guided coach-mark tutorial (steps derived from what is built) and which tips/helps were seen; state saved with the game (docs/23) |
| 24 | `UILayoutManager` | `scripts/services/UILayoutManager.gd` | Positions panels from `UILayoutConfig` slots, applies theme |
| 25 | `AudioManager` | `scripts/services/AudioManager.gd` | Signal-driven music/SFX/ambient, runtime buses |
| 26 | `DeviceProfile` | `scripts/services/DeviceProfile.gd` | PC/tablet/phone detection + override, UI scale (`content_scale_factor`), applies `UITheme` tokens (palette, contrast, opacity, text size), the FPS cap, the non-world part of the graphics quality and the first-launch quality detection. See `docs/21-interfaz-y-dispositivos.md` |
| 27 | `RankManager` | `scripts/services/RankManager.gd` | Governor rank: XP from EventBus signals, rank derived from XP, rank rewards (decoration unlocks, extra slots, small production/storage bonuses, flag pieces) and the player's country: name + flag recipe (`set_colony()`, `queue_colony_for_new_game()`). See `docs/06-progression-victory.md` §Governor rank |

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
  +-- IslandGenerator (Node3D) -- procedural island mesh: the irregular coast of the land mask (`IslandShape.coast_polygon`: grass, cliff, sand and foam along it; the sea shades from a distance texture); an old square-island save keeps the rounded square that covers the grid. Rebuilds on `grid_resized`
  +-- GridOverlay (MeshInstance3D) -- faint cell grid (Settings toggle), fitted to GridManager at runtime, drawn on land only (a land-mask texture in the shader)
  +-- BuildingPlacer (Node3D, scenes/buildings/BuildingPlacer.tscn) -- placement/move/demolish, touch placement via PlacementAssist
  +-- OnScreenControls (CanvasLayer 10) -- D-pad, zoom, rotate; "auto" follows the device profile (tablet/phone yes, PC no)
  +-- ResourceHUD (CanvasLayer 10) -- top-left card: one row of [icon] number chips (resources, free workers, morale once the Storm is armed; names and meaning in tooltips, a tap unfolds them) + shared storage bar with used/cap + materials row (once one is unlocked)
  +-- MapGenerator (Node) -- spawns 3-6 deposits of EACH type (`deposit_per_type_*`), on land only, none on the Núcleo sidewalk or the shore band (land next to the water), each with room and a road path for its extractor; `shore_cells()` is the hook for future sea/shore resources
  +-- ConstructionMenu (CanvasLayer 12) -- big CONSTRUIR button (always visible, bottom centre) + building list
  +-- BuildingInfoPanel (CanvasLayer 10) -- right panel: selected building / deposit info; RETIRAR / PONER TRABAJADORES; ABRIR MERCADO / INVESTIGAR on the Market / Laboratory (`SCREENS`)
  +-- MarketPanel (CanvasLayer 11) -- buy/sell UI, opened from a Market building (not from the menu)
  +-- ProgressPanel (CanvasLayer 11) -- milestones + era display
  +-- VictoryScreen (CanvasLayer 20) -- victory overlay
  +-- NotificationPanel (CanvasLayer 11) -- toasts (only warning, danger and notice) + the activity log, opened from ☰ MENÚ → REGISTRO (the old workers/morale status card is gone: those are ResourceHUD chips; the objective strip at the top centre is gone too, 2026-10-05: the next step lives in ¿QUÉ HACER?)
  +-- TechTreePanel (CanvasLayer 11) -- 3 branches x 5 tiers research UI, opened from a Laboratory building (not from the menu)
  +-- ObjectivePanel (CanvasLayer 15) -- ¿QUÉ HACER?: the next step, from Objectives.next_step()
  +-- ArmyPanel (CanvasLayer 11) -- train units, Military Power, upkeep, who is away on campaign
  +-- SettingsPanel (CanvasLayer 15) -- tabs Audio · Interfaz · Controles · Accesibilidad · Juego (persisted in settings.cfg)
  +-- HelperPanel (CanvasLayer 14) -- help callouts and tip cards (19), one at a time with ✕ + auto-close; building guide; instances HelpIndexPanel
  +-- SkirmishPanel (CanvasLayer 11) -- commit troops and launch an expedition; campaign status while a column is out; "QUE BAJEN" (Final Audit)
  +-- BattleScreen (CanvasLayer 18) -- the 8x8 board (a 3D diorama in a SubViewport, scenes/combat/Board3D.tscn; the classic 2D grid in the 2D view and headless) plus the expedition map, draft modal and final report (outside UIManager's stack)
  +-- StormHUD (CanvasLayer 16, 11 under modals) -- storm phase indicator (colour + icon, no countdown)
  +-- TutorialPanel (CanvasLayer 19) -- guided coach marks on the real UI; instances PrologueScreen
  +-- AuditWaveBanner (CanvasLayer 19) -- "Oleada X de N" during the Final Audit
  +-- WarReportScreen (CanvasLayer 19) -- queued war reports: blind defence (defense_auto_resolved) and the Tithe (COBRADO / REPELIDO)
  +-- AuditDefeatScreen (CanvasLayer 20) -- a lost siege: what was taken and how to resummon (or the end of a Survival run)
  +-- SandboxPanel (CanvasLayer 11) -- Sandbox mode only: the SANDBOX tab, summon a storm / the Final Audit
  +-- RankPanel (CanvasLayer 11) -- governor rank badge (flag, number, country name, XP bar) left of ☰ MENÚ, rank-up toast, the COLONIA card (country, rank, BANDERA Y NOMBRE → ColonyIdentityPanel)
  +-- PauseMenu (CanvasLayer 30) -- THE game menu ("☰ MENÚ" top-right): COLONIA + PARTIDA groups, real pause; ESC / Android back; adds the GameSpeedButton sibling (x1 / x2, layer 10)
  +-- TitleMenu (CanvasLayer 30) -- main menu on launch and from ☰ MENÚ -> Menú principal

Main2D (Node2D, ViewRouter view_mode="2d") -- world nodes replaced, UI identical
  +-- Camera2D (Camera2DController) / StormTint (CanvasModulate, StormTint2D) / Island (Island2D)
  +-- GridOverlay (GridOverlay2D) / BuildingPlacer (BuildingPlacer2D) / MapGenerator (MapGenerator2D)
  +-- OnScreenControls ... TitleMenu -- the same 24 UI nodes as above

Created at runtime, not in either .tscn:
  PrologueScreen (layer 32, scenes/ui/PrologueScreen.tscn) -- child of TutorialPanel: the lore, three folios in plain language
  QuickGuide (layer 33, scripts/ui/QuickGuide.gd, group "quick_guide") -- child of TutorialPanel: one screen with four blocks; no longer opens by itself (2026-10-14), texts in AYUDA
  WorkerWalkers (scripts/map/WorkerWalkers.gd) -- child of both placers: workers and citizens walking the roads (view only, docs/04)
  HelpIndexPanel (scenes/ui/HelpIndexPanel.tscn, group "help_index") -- child of HelperPanel: the AYUDA index, opened from ☰ MENÚ
  NewGameDialog (layer 40, scripts/ui/NewGameDialog.gd) -- the mode picker, created by GameManager.request_new_game()
  SavesPanel (layer 40, scripts/ui/SavesPanel.gd) -- PARTIDAS, the saved-games list, created by GameManager.open_saves_list()
  LayoutEditor (layer 35, scripts/ui/LayoutEditor.gd) -- EDITAR DISPOSICIÓN (Settings), created by UILayoutManager
```

UI panels are positioned by `UILayoutManager` using the slot definitions in
`scripts/ui/UILayoutConfig.gd` (19 named slots — 13 screen areas and 6 help-callout
anchors (`tip_*`) —, `NARROW_SLOTS` / `COLUMN_SLOTS` for narrow canvases, panel->slot map, slot
conflicts).
`UIManager.open_panel()` handles stacking and closes conflicting panels.
All styling comes from the static `UITheme` class. Panels and buttons are plain
boxes since 2026-09-28 (`UITheme.METAL_TEXTURES = false`; the metal 9-patch
textures generated by `tools/gen_ui_textures.gd` stay in `assets/` in case they
come back), and every `ScrollContainer` drags with finger or mouse
(`scripts/ui/DragScroll.gd`, hooked by UIManager). Its colours and font sizes are
**tokens** (`static var`) rewritten by `UITheme.configure()` (colour-blind
palettes, high contrast, panel opacity, text size): use `UITheme.POSITIVE` etc.,
never hand-written colours. Every token comes from one 10-colour palette
(`UITheme._BASE`, derived in `_derive()`; `docs/24-paleta.md`): a new tone is a
`darkened()` / `lightened()` of a palette colour, not a new `Color(...)`. HUD elements that can be hidden or moved
register in `HudRegistry` (`scripts/ui/HudRegistry.gd`); moved panels are offsets
on top of their slot, saved per device profile and aspect (`LayoutEditor`).
Stretch is `canvas_items` + `aspect=expand` (no black bars). Full detail:
`docs/21-interfaz-y-dispositivos.md`.

---

## Game Systems

### Economy: 3-Era Progression

| Era | Name | Resources | Unlocked by |
|-----|------|-----------|-------------|
| 1 | Frontier | Gold, Wood, Food | Game start |
| 2 | Industrial | + Steel | Build first Foundry |
| 3 | Petroleum | + Oil | Build first Refinery |

- Starting resources: 300 gold, 200 wood, 80 food
- Deposits visible from start but locked until era unlocks the resource
- Storage: **one shared pool for the five resources** (food included), not a cap per resource. Base scales
  by era (600 / 800 / 1000) + 500 per warehouse (max 5, see `GameConfig.building_limits`).
  Era 1 is 600 so the opening fits: 580 starting resources, plus sawmill + gold mine (330).
  Era 3 ceiling without techs = 1000 + 5x500 = **3500**, exactly the price of the HQ
  level 3 upgrade. On top of that, `GameConfig.tech_storage_bonus` adds the storage
  techs: `ind_2` +200, `log_2` +300, `log_5` +500 — **+1000**, so the absolute ceiling
  is **4500** (`GameConfig.get_storage_cap()`). Sandbox ignores all of it
  (`sandbox_storage_cap`).
  Production never overflows: it waits in the buildings (below) and they stop when full.
  What enters the bag directly (hand mining, purchases, loot, refunds, events) and does
  not fit is lost; `EventBus.storage_overflow` fires and the player is
  warned once per game. Loading a save that holds more than fits trims it proportionally.
- **Production that is collected (2026-10-04):** every producer keeps what it makes in
  the building (`ProductionManager._stock`) up to `GameConfig.get_stock_cap(id, level)`
  (`building_stock_caps`: ~6 min of base output; sawmill 180, mine 240, foundry 120,
  refinery 80, HQ 180, farm 800; x level multiplier). Full, it **stops** (badge "lleno:
  recógelo"). One tap on the building or on its floating icon (`StockIcon3D` /
  `StockIcon2D`, named "StockIcon"; also RECOGER in its panel, `HarvestSection`) calls
  `ProductionManager.collect()`: what fits goes to the bag, **the rest stays in the
  building** (nothing is thrown away). Workshop processes leave what does not fit in
  their building too (`keep_in_building`). After `spoil_after_seconds` (2 h) uncollected,
  `spoil_ratio` (50%) goes bad — **only if `GameMode.spoilage_enabled()`** (rule
  `spoilage` of `GameConfig.game_tier_rules`: off in Colono, on in Gobernador). Offline, production
  accumulates in the buildings with their caps and the absence report lists what is
  waiting. Saved under `stockpiles`.
- Extractors must touch their deposit (`GameConfig.building_deposit_rules`): sawmill
  next to a forest, gold mine next to a gold vein, foundry next to iron (reach 1); the
  refinery sits on an oil well (reach 0) and consumes it.
- Hand mining (`mining_data`, 2 workers, needs a road to the deposit) yields per worker
  no more than the matching extractor: gold 12 per 30 s, wood 10 per 20 s (iron and oil
  unchanged). Era 1 measures 8.6-10.2 min with the default probe player (docs/22 §5.5).
- **Trial storm (era 1):** around minute 5 of play (`storm_trial_at` = 300 s of played
  time, through `get_duration()`), a scripted gentle storm runs Warning → Ash → Storm →
  calm with the usual tips, but **no Tithe**, no building or queue damage, production
  at 75% and a quarter of the morale bite. Once per game (saved as `trial_done` /
  `trial_storm` in the storm save), on its own `StormCycle` (`create_trial()`), so it
  never arms the real clock (that still comes with the Foundry); skipped if the
  Foundry comes first, and off in Constructor/Sandbox (`GameMode.storm_trial_enabled()`).

### Resources

| Resource | Role | Starting | Unlock |
|----------|------|----------|--------|
| Gold | Universal currency, troop wages | 300 | Era 1 |
| Wood | Construction | 200 | Era 1 |
| Food | What people eat (Farm, Market); in the pool; `Type.FOOD` after the materials | 80 | Era 1 |
| Steel | Advanced construction | 0 | Era 2 (Foundry) |
| Oil | Late-game construction | 0 | Era 3 (Refinery) |

### Buildings (17 total, `data/buildings/*.tres`)

| Building | Size | Cost (G/S/O/W + materials) | Workers | Production | Era |
|----------|------|-----------------|---------|------------|-----|
| Nucleo (core) | 3x3 | Free | 0 | +5 worker room; manual processes only: its own, every unlocked workshop recipe and hand mining, 1.5x slower | - |
| House | 2x2 | 50/0/0/30 | 0 | +6 workers (room in houses; 9 / 12 at levels 2 / 3) | 1 |
| Sawmill | 2x2 | 80/0/0/50 | 2 | 6 wood/12s; makes planks | 1 |
| Farm | 2x2 | 40/0/0/30 | 2 | Food by crop: 20 / 125 / 600 per 1 / 5 / 20 min; anywhere with a road; max 6 | 1 |
| Gold Mine | 2x2 | 120/0/0/80 | 3 | 8 gold/12s; makes ingots | 1 |
| Warehouse | 2x2 | 60/0/0/40 | 1 | +500 shared storage (+250 per level above 1) | 1 |
| Market | 2x2 | 100/0/0/60 | 1 | Opens the market (ABRIR MERCADO); needs a Gold Mine; max 1 | 1 |
| Laboratory | 2x2 | 150/0/0/100 | 2 | Opens the tech tree (INVESTIGAR); needs a House; max 1 | 1 |
| Foundry | 2x2 | 200/0/0/120 | 3 | 5 steel/15s; makes beams | 1->2 |
| Barracks | 2x2 | 250/100/0/80 + 10 planks | 3 | Trains units (ArmyManager) | 2 |
| Refinery | 2x2 | 300/150/0/100 + 6 beams | 4 | 4 oil/18s; makes fuel | 2->3 |
| Tower | 2x2 | 150/60/20/30 + 4 beams | 1 | Storm mitigation + an artillery crew on defensive boards (only while operational) | 2-3 |
| HQ (capstone) | 2x2 | 500/300/200/200 + 20 beams, 10 ingots, 10 fuel | 5 | 10 gold/20s | 3 |
| Road | 1x1 | 1/0/0/0 | 0 | +2 morale; instant; joins everything to the Núcleo | deco |
| Garden | 2x2 | 30/0/0/20 | 0 | +5 morale | deco |
| Fountain | 2x2 | 60/20/0/10 | 0 | +7 morale | deco |
| Statue | 2x2 | 120/40/0/0 + 3 ingots | 0 | +10 morale | deco |

**Key constraint:** Foundry costs 0 steel (it unlocks steel). Refinery costs 0 oil (it unlocks oil).

**Farm (2026-10-04):** the crop is picked in its panel (CULTIVO, `GameConfig.farm_crops`:
`crop_short` 1 min / 20, `crop_medium` 5 min / 125, `crop_long` 20 min / 600 — longer
gives more per minute) and repeats by itself (`ProductionManager.plant_crop()` /
`get_crop()`; changing restarts the crop). It is the Farm's production cycle, not a
`ProcessManager` process. Baked toy model (`assets/models/toy/farm.tscn`: windpump,
shed, fence) plus its beds as a separate mesh (`Crops`, `FarmCrops3D`): the three crops
and the windpump rotor grow, ripen, sway and turn in the shared shader
`toy_crops.gdshader` through per-instance parameters; 2D drawing `BuildingArt2D._farm()`
grows and ripens too.

**Market and Laboratory (2026-09-28):** trade and research are no longer entries of
☰ MENÚ. Each opens by tapping its building (`BuildingInfoPanel.SCREENS`: ABRIR
MERCADO / INVESTIGAR, disabled while the building has no road); ¿QUÉ HACER? asks for
the Laboratory before research and does not suggest trading without a Market.

**Upgrades** only exist where they give something (`PlacementRules.upgrade_does_something()`):
producers (x1.6 / x2.5), houses (room x1.5 / x2), the warehouse (+250 per level),
decorations with morale (x1.5 / x2) and the HQ (its level 3 summons the Audit). The
Barracks, Tower, Road and Núcleo offer no upgrade. The panel lists what the next level
gives with real numbers (`upgrade_effect_lines()`), and in 3D the building grows and
carries a II / III plate.

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
ingots + fuel, Statue ingots) and `hq_upgrade_costs`. The HUD shows them in a materials
row; `Objectives.make_step_for()` turns a missing material into a `"make"` step.

**Era gates:** Foundry (era 2) needs Sawmill + Gold Mine + House + Warehouse;
Refinery (era 3) needs Foundry + Barracks (`building_prerequisites`).

**Quick guide:** `scripts/ui/QuickGuide.gd`, one screen with four blocks (resources,
extraction, buildings and roads, progress). Since 2026-10-14 it **no longer opens by
itself** after the prologue (the owner found the "Cómo funciona Tormenta Imperial"
window too much at the start); the same texts are `guide_qg_*` in the AYUDA index. A
`quick_guide` id in an old save's `helps_seen` loads and changes nothing.

**Batches and the Núcleo as every workshop (2026-10-14):** every process and hand
mining can be ordered ×1 / ×5 / MÁX from its card (`scripts/ui/ProcessCard.gd`, built by
`ProcessActionsPanel`): paid up front, run one cycle after another in the same place
(`ProcessManager.start_process(node, proc, count)` / `start_mining(node, dep, count)`;
entry fields `count`, `total`, `workers`, saved in `active_processes`, old entries load
as one cycle). MÁX = `ProcessManager.max_batch()`: resources, free shared storage, the
deposit's uses left, cap `process_batch_max` (20). Cancel refunds the usual rate on
everything paid and not delivered; the Storm takes the whole batch. The Núcleo also
offers every workshop recipe and hand mining of each deposit type
(`GameConfig.get_core_extra_processes()`, through `ProcessManager.get_processes_for("nucleo")`)
as soon as all their resources/materials are unlocked, with the same output and
`core_process_time_mult` (1.5x) the time, so the dedicated building stays worth it;
hand mining there holds `mining_workers`, needs no road and spends no deposit use (id
`core_mine_*`). Detail: docs/02 "Lotes" and "El Núcleo, taller de todo".

### Road network (2026-09-28)

- **Every building is at least 2x2**, except the road (1x1). GLBs made for 1x1 are
  scaled up with `BuildingData.model_scale`; `BuildingData.instantiate_model()` is the
  only way to spawn one.
- **Everything touches a road joined to the Núcleo.** `PlacementRules.is_connected_spot()`
  is part of `evaluate_placement()` (reason `"road"`, feedback `LBL_NEEDS_ROAD`); a new
  road must touch the network or the Núcleo. No Núcleo on the grid (hand-built test
  scenes) means no rule.
- **Removing a road: move the buildings first.** Demolishing or moving a road tile is
  refused when `PlacementRules.road_removal_stranded(road, new_cells)` is not empty:
  the buildings (under construction included; not the Núcleo, decorations or roads,
  nor ones already loose) that would lose their link to the Núcleo. Both placers
  show `LBL_MOVE_FIRST` ("Primero mueve: Aserradero") and `flash_buildings()` them in
  red for `GameConfig.road_block_highlight_seconds`; a tap selects one (panel with
  MOVER). Tests: `tests/map/test_road_removal.gd`.
- **Access ring:** the first extractor next to a deposit (not the refinery's oil
  well) lays a free road ring `extractor size + 1` cells around it
  (`PlacementRules.pave_access_ring()`), leaving the touching band free for more
  extractors; only pieces joined to the network are laid, the deposit keeps an
  `access_ring` mark in its save entry. Tests: `tests/map/test_access_ring.gd`.
- **The Núcleo starts with its sidewalk:** `GameManager.pave_core_ring()` lays the 16
  road cells around it in `_new_game()`. Roads cost 1 gold, are drawn as full-cell
  pavement with a curb on the unconnected sides (3D and 2D), and take no damage
  (`BuildingHealth.is_immune()`: the Núcleo and roads).
- `PlacementRules.road_route(origin, size)` gives the free cells to pave to join a
  footprint (tests and `tools/line_probe_player.gd` use it); `walk_route(node)` gives
  the road path from the Núcleo to a building.
- **Life in the streets:** `scripts/map/WorkerWalkers.gd` (child of both placers).
  Workers live in a house and commute along the road network to a building that is
  really staffed (PopulationManager's `staffed` meta: withdrawn, "sin carretera" and
  vein-less buildings get nobody), go in through its door, stay, come out and go
  home; citizens (the unemployed) stroll, stop at decorations and shop at the
  Market. One figure per `life_people_per_figure` people, capped per device profile
  (`life_figure_cap`); they hurry in the Warning and stay indoors through Ash, Storm
  and Tithe; `set_presence()` is the night hook. Figures are data (`WalkerActor.gd`)
  drawn by one node: `WalkerFigures3D` (a MultiMesh per silhouette) or
  `WalkerFigures2D` (one `_draw`). View only, never saved; staffing stays in
  PopulationManager. Detail in docs/04.
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

- **PopulationManager** tracks: population, max capacity, used workers, morale. The UI
  calls the people **trabajadores** everywhere ("Trabajadores: 12 de 17", "En su
  puesto: 8 · libres: 4")
- Nucleo provides 5 starting room. Houses provide 6 each
- Each production building requires workers (see table above), first built = first served
- **Retirar / poner trabajadores:** `PopulationManager.set_workers_off(node, off)` (button
  in BuildingInfoPanel) frees a building's workers for others and stops it; saved per
  building as `workers_off`. Badge: "sin trabajadores (retirados)"
- **No vein, no work:** a Sawmill, Gold Mine or Foundry whose deposit was mined out by
  hand stops (`PlacementRules.has_its_deposit()`, meta `has_vein`, badge "sin veta")
- **Manual mining takes workers:** mining a deposit by hand holds
  `GameConfig.mining_workers` (2) while it lasts and needs the deposit to touch a road
  joined to the Núcleo (`ProcessManager.mining_blocker()`: `MINE_NEEDS_ROAD` /
  `MINE_NEEDS_WORKERS`)
- Population grows +1 per tick (20s) if morale > 30 and housing available
- **Consumption:** Each pop eats `food_per_pop` (1) **food** per 30s tick (60 s early;
  `PopulationManager.food_due()`). Wood and gold are no longer eaten (2026-10-04)
- If can't pay: morale drops -8/tick, and after two unpaid ticks people starve. If paid: morale recovers +3/tick

### Morale (0-100)

- Starts at 75. Affects production speed: `0.5x at 0 morale, 1.0x at 50, 1.2x at 100`
- Decorations add passive morale recovery (+1 per 10 bonus points per tick)
- Below 30 morale: population stops growing
- Below 20 morale: danger notification

### Market (Imperial Exchange)

- Opened by tapping a Market building (ABRIR MERCADO); there is no menu entry any more
- Gold is the currency. Buy/sell food, wood, steel, oil for gold
- Floating prices with 30% spread (buy higher, sell lower)
- Price base: food=2, wood=3, steel=8, oil=12 gold/unit
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
retraining in between. The garrison and its morale are read when the gate opens
("QUE BAJEN", `FinalAudit.begin(home, morale)`), not at the summons. The siege is summoned pending; the player walks in with "QUE
BAJEN" in `SkirmishPanel`. Surviving it emits `storm_halted_forever` (the Storm stops
for good) and only then `victory_achieved`. Losing is **not** a game over in Campaña —
maximum Tithe, maximum storm damage, and the siege can be summoned again once
`final_audit_resummon_min_units` (3) units stand.

Per mode: **Constructor** wins directly at HQ 3 (`GameMode.capstone_wins()`, no siege);
**Supervivencia** gets one siege only — losing it emits `run_ended` and seals the save;
**Sandbox** never summons it on its own (only from the SANDBOX tab) and has no victory.
Full detail in `docs/15-combat.md` §6 and `docs/20-modos-de-juego.md`.

### Governor Rank — full doc: `docs/06-progression-victory.md` §Governor rank

A third axis next to eras and milestones: XP inside the run (owner's decision,
2026-10-04). `RankManager` adds XP from EventBus signals (`GameConfig.rank_xp_sources`:
build 15, upgrade 25, production cycle 1, process/mining 5, trade 5, unit 10, fight won
40, expedition won 80, storm 30 + 10/severity, milestone 100) and **derives** the rank
from it (`rank_xp_thresholds`, 18 ranks, step `100 + 60*(n-1)`, ~9860 XP for the last;
not yet measured with the line probe). Titles `RANK_TITLE_<n>` (Colono, Capataz … Cónsul
… Archigobernador). `rank_rewards` gives decorations (Garden 2, Fountain 5, Statue 8),
extra building slots (`rank_limit_bonus`), small bonuses (`rank_production_bonus`
+7 % and `rank_storage_bonus` +8 % at rank 18, **assigned**, never added, so loading
twice is safe) and flag pieces (`patterns`, `emblems`, `colors`).

**The player's country (2026-10-12):** a name (max `COLONY_NAME_MAX` = 26, "Al azar"
names like "Liga de Vaporia" in ES/EN, a short ES/EN word filter in
`scripts/services/ColonyIdentity.gd`) and a flag built from pieces: a recipe
`{"pattern", "emblem", "colors": [field 1, field 2, emblem]}` drawn by code in
`scripts/ui/ColonyFlag.gd` (14 patterns, 12 emblems + none, 13 colours from
`colony_colors` / ToyPalette; `fix_spec()` keeps it readable, cached textures,
`draw_spec()` for lists). Rank 1 opens 5 patterns, 4 emblems and 6 colours; the
showier ones come by rank (`rank_rewards`). Picked in the editor
`scripts/ui/ColonyIdentityPanel.gd` (`open("new"|"edit")`, signals `confirmed` /
`cancelled`), opened from ☰ MENÚ → COLONIA (RankPanel) and meant for the New Game step
(`RankManager.queue_colony_for_new_game()` before the reset). Flies on the Nucleo and
the HQ (`ColonyFlag3D`: small plane + vertex-shader wave, off in low quality; hangs
from the model's `FlagAnchor` marker when it has one; `ColonyFlag2D`), signs the war
reports, the audit defeat, the victory and the board header (`ColonyByline`), and its
first colour fills our board tokens' round mark. Signal `colony_identity_changed`. The basic
buildings keep their era unlocks. Locks go through `PlacementRules.check_rank()`; the
CONSTRUIR card shows a padlock and "Rango N". UI: `RankPanel` (badge in slot
`rank_badge`, rank-up toast with SFX `rank_up`, the COLONIA card). Saved as `"rank": {"xp", "colony": {"name", "flag"}}`;
a save without it is rank 1 with a country rolled from `GridManager.island_seed`; an old
`"flag"`/`"color"` pair is translated to pieces. Sandbox has every rank unlock open.

### Game Modes — full doc: `docs/20-modos-de-juego.md`

**Only Campaña is offered today (2026-09-28).** `GameMode.OFFERED` lists the modes
the New Game dialog shows; Constructor, Supervivencia and Sandbox are commented out
there — their cards are built but hidden, and their rules, saves and tests stay
intact (an old save in one of them still loads, and its Nueva partida opens the
picker on Campaña). Uncomment a line to bring it back.

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
`"game_mode": {"mode", "result", "tier"}`; `GameMode.begin_run(mode, tier)` is its reset.

**Colono / Gobernador** (docs/20 §1b) are two *tiers* of the Campaign, not modes:
Colono is today's game; Gobernador (provisional name) adds the Storm-calendar market
with visible spread (docs/05), spoilage (`spoilage_enabled()`: what waits uncollected
2 h loses half, `ProductionManager._tick_spoilage()`) and a harder enemy (`expedition_enemy_mult` 1.05,
`tithe_force_mult` 1.34, `audit_enemy_mult` 1.06; same `CombatRules`). Rules in
`GameConfig.game_tier_rules`, queried through `GameMode.market_dynamic()`,
`combat_hard()`, etc. It **unlocks per profile** — `settings.cfg [perfil]`, written by
`GameConfig.record_run_finished()` when a run reaches its end (victory, a lost Final
Audit in Campaña, a sealed Survival) — and is always open in `dev_mode`. The tier is
fixed for the run; saves without `tier` load as Colono.

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
- **The 3D board (view only, 2026-10-12):** `scripts/combat_view/` +
  `scenes/combat/Board3D.tscn`, never inside `scripts/combat/`. `BattleScreen` puts a
  `BoardViewport3D` (SubViewport with its own world) behind its header and buttons
  and forwards the same signals to `Board3D.push()`; the diorama **tells** what the
  model already did, one event after another (deploy drop, hop-by-hop BFS route,
  wind-up + shell / bayonet / tracer, hit shake + damage number + HP bar, fall,
  guard ring), then reconciles with the `Encounter` and emits `idle`. While it
  animates (`BattleScreen._board_busy()`) the board takes no input and the
  report / draft / final report wait (`_after_board_animations()`). Toy units are
  baked with `tools/build_toy_models.gd -- --units` (recipes in
  `tools/toy_recipes/units/`, output `assets/models/toy/units/<id>_player|_regency`,
  410-570 tris; player pieces carry a grey `team` surface painted with
  `RankManager.get_color()`, one shared material per colour; the Regency is baked in
  purple; round stand ours, diamond stand theirs; boss standard; tower-crew sandbag
  nest). The map's 3D is switched off (`Viewport.disable_3d`) while the 3D board
  covers it, so the board costs less GPU than the map. `pick_board_style()`: 3D
  everywhere (minimal quality = simplified: no shadows, no dust, no sway, 0.7 res),
  2D grid in the 2D map view and headless (tests); `force_board_style()` for tests
  and probes. Rules, AI, `CombatManager` and audio untouched. Full detail and FPS:
  `docs/15-combat.md` §3 "El tablero 3D".
- **`domain`:** every `combat_unit_stats` row carries `"domain": "land"`;
  `CombatUnit.domain()` exposes it, no rule reads it; the 3D view places a piece by
  domain (`BoardLayout3D.DOMAIN_HEIGHT`: sea / air / space ready). Design for sea and
  air units: `docs/15-combat.md` §11.
- **Type advantage (rule, 2026-10-13):** artillery > vehicle > infantry > artillery,
  x1.5 / x0.75 on net damage (`GameConfig.combat_type_advantage`, `beats` +
  multipliers) inside `CombatRules.damage()`, so player, `CombatAI` and
  `AutoResolver` share it; `CombatRules.type_matchup()` gives +1/-1/0 and the AI uses
  it as its 2nd target criterion. Siege impact and the pending
  `final_audit_artillery_share` 3 -> 4 proposal: docs/17. The board shows a yellow HP
  plate per piece, a blue ring on the acting unit, a red ring + crosshair on targets
  and "¡Buen objetivo!" / "Mal objetivo"; decorative scenes land / beach / forest
  (`BoardTerrain3D.SCENES`); its own x1/x2 button (animations follow
  `GameConfig.combat_pace`).
- **Two combat views (2026-10-14), same 8x8 underneath:** "front" (default: both
  sides face to face, low side camera, no grid; cells drawn as jittered "free
  spots" `BoardLayout3D.spot_offset`, moves lit as ground blobs, bigger pieces, a
  dividing creek / tide line / hedge per scene; tap an enemy = close in and fire via
  `scripts/combat_view/FrontOrders.gd`, plus AVANZAR) and "board" (the 3D 8x8).
  Device preference `GameConfig.ui_combat_view` in `settings.cfg [interfaz]
  combat_view`, chosen in Settings → Interfaz or with the `BoardViewToggle` header
  button mid-fight (`Board3D.set_style`, applied once the animation queue is
  empty). Minimal quality forces "board" (cheapest measured). Models, AI and
  AutoResolver never know which view is on.
- **Colony notices wait for the fight:** while `CombatManager.is_board_open()`,
  NotificationPanel holds its toasts (log at once; category `combat` still shows),
  ProgressPanel/RankPanel hold their toasts and HelperPanel goes quiet (except the
  `encounter` tip); all resume on `EventBus.encounter_closed` (end of
  `CombatManager.end_encounter()`).

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
operational (not ruined, not under construction). A crew that falls on any defensive
board leaves its tower **damaged** (`storm_tower_crew_loss_damage`, 40% of max health,
never ruined) until it is repaired; the war reports say how many. They have no attack of their own on
the base map.

**Unit icons:** the 2D board and the initiative strip paint unit silhouettes (`assets/textures/ui/units/*.png`,
generated by `tools/gen_unit_icons.gd`, read by `UITheme.unit_icon()`), tinted per
side, with the boss marked; the translated name's initial is only a fallback when a
PNG is missing.

### Tech Tree (15 techs, 3 branches)

- **TechTreeManager** + `GameConfig.tech_definitions`. Branches: Industrial,
  Military, Logistics — 5 linear tiers each (tier N requires tier N-1).
- Research costs **resources** (not points) and takes time; only one tech at a time.
- Bonuses are permanent: production multiplier, storage, consumption reduction,
  morale recovery (Military branch), market spread / build speed (Logistics).
- The panel opens from a Laboratory building (INVESTIGAR), not from the menu, and explains
  what the tree is, what each branch does and each tech's gain with its numbers and lore.
- No HQ requirement (deliberate: the HQ is era 3). The old vestigial `_research_points`
  counter was removed; a `research_points` key in old saves is ignored.

### Game Phases (onboarding pacing)

`GameConfig.Phase` enum: FOUNDATION -> SETTLEMENT -> ECONOMY -> SURVIVAL -> EXPANSION.
`phase_triggers` gates early-game pacing (`early_consumption_interval`,
`early_morale_penalty`, `early_growth_interval`) so consumption/morale pressure
ramps up gradually instead of punishing the first minutes.

### Day and night (2026-10-12) — full doc: `docs/21-interfaz-y-dispositivos.md` §12

- **Visual only, ready for rules.** `scripts/storm/DayCycle.gd` is a pure model like
  `StormCycle` (`tick(delta)` returns events; hour 0-1, phase DAWN/DAY/DUSK/NIGHT,
  `light_weight()`, `warm_weight()`, `sun_arc()`, `is_night()`). `DayClock` (autoload)
  ticks it, emits `day_phase_changed` and is what a future rule asks (`DayClock.is_night()`).
- Lengths in `GameConfig.day_cycle_*`: 90 s dawn, 600 s day, 90 s dusk, 180 s night
  (16 min); `day_cycle_enabled = false` means always day. Paused with the real pause.
- **The storm rules over the night:** StormSky computes the light of the moment every
  `day_cycle_refresh` s (2) and blends the ash on top, toward the same targets as by
  day. The island gets `night_weight` (storm_grade.gdshaderinc); windows/lanterns get a
  gain on the shared `ToyPalette.glow_material()`. 2D: `StormTint2D` does the same with
  its CanvasModulate. Night is bluish but never really dark (10-15 year olds).
- Saved as `"day": {"hour"}`; a save without it starts in daylight. **Offline the clock
  does not move** (like the storm, docs/09).

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
  opacity, hidden HUD elements, moved layout, `fps_cap` (`auto` / `30`…`120` /
  `unlimited`: the FPS cap, 30 while paused and 10 without focus; "auto" is 30 on a
  PC in Minimal) — docs/21 §10; `graphics_quality` (`auto` / `high` / `low` /
  `minimal`) plus `quality_detected` / `quality_detected_reason` (the first-launch
  detection, once) — docs/21 §12, docs/26 §7;
- `user://renderer_override.cfg` (not settings.cfg): written only when a PC picks
  Minimal quality; `project.godot` names it in
  `application/config/project_settings_override`, so the next launch runs the
  Mobile renderer. Any other quality deletes it. Only `GraphicsQuality.set_quality()`
  touches it;
- `[perfil]`: `runs_finished`, `campaigns_won` — the player profile that unlocks
  Gobernador (docs/20 §1b). Of the player on this device, never of the run.

Never put any of this in the save, and never put game state in `settings.cfg`. The
locale is `es`/`en`, applied to `Tr` at startup. The language selector lives in SettingsPanel:
`GameConfig.set_locale()` saves it and emits `EventBus.locale_changed`, and GameManager
answers by saving and reloading the scene with the same game (`reload_keeping_game()`),
so every panel is rebuilt in the new language (the in-memory notification log is lost
and Settings closes; accepted). With a board open it does not reload
(the board is not saved); the language shows everywhere on the next start.

### Game speed x1 / x2 and bug reports (docs/21 §13, docs/19 §7)

- **Speed:** `GameConfig.game_speed` (1.0 / 2.0), changed with the small `x1`/`x2`
  button (`scripts/ui/GameSpeedButton.gd`, added by `PauseMenu` as its sibling, slot
  `speed_button`, in `HudRegistry`) or the **F** key; emits
  `EventBus.game_speed_changed(speed)`. It is **not** `Engine.time_scale` (that would
  speed up UI tweens, camera, toasts and the real-seconds autosave too): each service
  that ticks the simulation does `delta = GameConfig.sim_delta(delta)` at the top of
  its `_process` (Production, Process, Population, Army, TechTree, Storm, DayClock,
  RandomEvent, Market). Combat waits go through `GameConfig.combat_pace(seconds)`
  (`get_combat_ai_step_delay()` already does). A new ticking service uses `sim_delta`;
  UI cooldowns and real-time clocks do not. Never saved (not in the save, not in
  `settings.cfg`): every launch starts at x1. Offline progression is unchanged.
- **Local error log:** `scripts/services/ErrorLog.gd`, a `Logger` hooked by
  `GameConfig._ready()` via `OS.add_logger()`. Writes `user://logs/registro.txt` in
  blocks every 3 s (and on close / background), 200 KB cap, 2 rotations, repeated
  lines counted. Never leaves the device.
- **Report:** ☰ MENÚ → PARTIDA → Informar de un fallo copies `BugReport.build()`
  (version, OS, GPU/renderer, profile, quality, view, locale, mode/tier, era, speed,
  last 40 log lines) to the clipboard. `BugReport.sanitize()` turns home-dir paths
  into `~` and the colony name into `<colonia>`.

### Save/Load System

- **Up to 5 saved games** (2026-10-12): one file each, `user://partidas/partida_<id>.json`, plus a small index
  `user://partidas/indice.json` (id, colony name, flag spec, colour, mode, tier, era, played time, `saved_at`, sealed)
  so the list paints without opening each game. `scripts/services/SaveSlots.gd` (static, `preload`) owns the folder;
  the index is a cache that `list()` reconciles with the files. The **active** game is a device preference,
  `settings.cfg` `[partidas] activa` (`GameConfig.saves_active_slot`); `GameManager.save_path()` is its file — never
  hard-code a path. On start: a legacy `user://save_game.json` is migrated into a new slot (copied, verified byte for
  byte, then deleted) and opened; otherwise the active one; if it is gone, the most recent; if there are none, a new game
- **Nueva partida never deletes**: `start_new_game()` saves the current game and starts the new one in a new slot. With
  five, `request_new_game()` opens the list (`SavesPanel`, `make_room`) to delete one first. A fresh island that was born
  by itself and never built on (`is_current_disposable()`) is reused instead of taking a place. The list
  (`GameManager.open_saves_list()`, from the title menu "PARTIDAS n/5" and from ☰ MENÚ → PARTIDA) has Load and Delete
  (confirmed); `load_slot()`, `delete_slot()`, `leave_deleted_slot()` (the in-memory game was deleted: open the most
  recent or a new one). `clear_save()` discards only the active slot (the reused fresh island, tests)
- Saves (top-level keys written by `GameManager._write_save()`): `resources`, `buildings` (level, name, construction state, health), `deposits`, `camera`, `progression` (eras, milestones, played time, and the `final_audit`), `market`, `unlocked_resources`, `population`, `random_events`, `active_processes`, `stockpiles` (what waits in each building, Farm crops, production clocks), `tech_tree`, `army`, `expedition` (CombatManager: the run in flight), `storm`, `tutorial`, `day` (DayClock: the hour, 0-1; frozen while the game is closed), `rank` (RankManager: XP and the country, `colony`: name + flag recipe), `game_mode`, `grid` (width, height, island seed; restored before anything is placed). Same save for the 3D and 2D views
- Cloud: `CloudSaveManager` (Supabase REST) implements anonymous/email auth + save/load, but no game code calls it yet — local JSON is the only active path
- Auto-saves on: building placed/moved/renamed/demolished, deposit depleted, tech research, and (debounced by
  `GameConfig.autosave_debounce`) trades, training, processes, upgrades, storm phases, Tithe, Final Audit, expedition
  steps and fight results; plus every `GameConfig.autosave_interval` real seconds, on window close, and on
  pause/focus-out on mobile. `GameManager.request_save()` is the entry point for new triggers
- Fights are never saved: a checkpoint is written when a board opens, and nothing is written while
  `CombatManager.is_save_safe()` is false (fight in play, or a siege-wave report not yet closed). Quitting mid-fight
  replays it from the start. A save made during the Tithe reloads with the Tithe re-demanded (defence or payment)
- The game starts only once `Main` is ready (GameManager waits for the scene root), so load signals reach the UI.
  An unreadable save is copied to `user://partidas/partida_<id>.corrupt-<date>.json` (an old-format one to
  `.v1-<date>.json`) before a new game replaces it in the same slot
- Offline progression: production earned while the game was closed waits in the buildings (max 8h,
  `max_offline_seconds`; off in Supervivencia). There is **no report and no notice** (the "Mientras estuviste fuera"
  window is gone, 2026-10-12). Internal reloads — the 3D↔2D switch (`switch_to_scene()`) and the language reload
  (`reload_keeping_game()`) — are not an absence: they set `_skip_offline_once` and apply nothing
- A lost Survival run is written once more with `"result": "defeat"` and then **sealed** — per game: GameManager never
  writes that slot again, loading it shows the end screen (only Nueva partida or Salir), the title menu offers no
  "Continuar" and the list shows it as TERMINADA with Load disabled. The other games are not affected
- The profile that unlocks Gobernador (`profile_runs_finished`, `profile_campaigns_won` in `settings.cfg`) is global,
  not per game

---

## Project Structure

```
tormenta-imperial/
+-- project.godot                    # Engine config, 28 autoloads (27 game + BeckettRuntime)
+-- export_presets.cfg               # Windows Desktop, Android, Android QA (emulador) — no secrets
+-- LICENSE, THIRD-PARTY-NOTICES.md, licenses/  # Licence, third-party notices, the engine's copyright text
+-- CLAUDE.md                        # THIS FILE - AI guidance
+-- readme.md                        # Game overview (Spanish, public)
+-- docs/                            # Per-system deep docs 01-24 (INDEX.md); media/ = screenshots
+-- specs/001-combate-pve/           # Spec, plan and tasks for the combat pillar
+-- .specify/memory/constitution.md  # Non-negotiable project rules (Spec-Driven Development)
+-- qa/maestro/                      # Maestro flows for the Android tablet emulator (QA APK, coordinates + screenshots)
|   +-- 01_...08_*.yaml              # One regression flow per tablet bug (README.md explains how to run them)
|   +-- comun/                       # Shared sub-flows: start, new game, skip lore, wait
|   +-- herramientas/                # Python helpers to collect and compare screenshots
+-- tests/                           # gdUnit4, 141 suites: audio/ build/ buildings/ combat/ economy/ input/
|                                    #   integration/ map/ modes/ save/ storm/ support/ tutorial/ ui/ view2d/
|   +-- save/save_parking.gd         # Parks the real save during a suite; refuses the player's dir
|   +-- save/settings_parking.gd     # Same for settings.cfg and GameConfig's UI fields
+-- scenes/
|   +-- main/Main.tscn               # Entry scene (3D); ViewRouter may hand over to Main2D
|   +-- main/Main2D.tscn             # The 2D view: same UI nodes, 2D world nodes
|   +-- buildings/BuildingPlacer.tscn
|   +-- combat/Board3D.tscn          # The 3D combat diorama (camera, sun, terrain, marks, units, fx)
|   +-- ui/                          # One .tscn per panel (26), incl. PrologueScreen and HelpIndexPanel
+-- scripts/                         # 127 .gd files, ~48k lines
|   +-- buildings/
|   |   +-- BuildingData.gd          # Resource class for building definitions (get_display_name())
|   |   +-- BuildingPlacer.gd        # 3D placement/move/demolish + mesh spawning
|   |   +-- PlacementRules.gd        # Shared placement rules for 3D and 2D: deposit adjacency, footprint, road network and auto-road, upgrade effects
|   |   +-- PlacementAssist.gd       # Touch placement (tap aims, tap ghost/✓ builds), valid-spot highlight — docs/21 §9
|   |   +-- BuildingStatusBadge.gd   # Worker pictogram / "Zzz" + why a building is stopped (3D)
|   |   +-- ColonyFlag3D.gd          # The country flag on the Nucleo and HQ masts (shader wave, FlagAnchor)
|   |   +-- BuildingLook.gd          # Rule (both views): construction phase / upgrade / ruin / active / idle; site style per type + seeded layout per instance
|   |   +-- BuildingLookVisual.gd    # Applies it in 3D (child "LookVisual"); BuildingPlacer syncs it with one map-wide clock
|   |   +-- BuildingFx.gd            # Generated smoke/dust/glow/sparks sprite sheets (8 frames, 4x2) + TIME shaders, 3D and 2D
|   |   +-- SiteFx.gd                # Construction-site animation by shader (crane swing, hook, pennant), 3D and 2D
|   |   +-- DieselpunkBuildingFactory.gd  # Procedural 3D meshes (fallback when there is no GLB)
|   |   +-- LotPlan.gd, BuildingLot.gd, LotMesh.gd  # The lot: rule (both views), 3D node, one-mesh builder
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
|   +-- combat_view/                 # VIEW of the board in 3D (docs/15 §3): never rules
|   |   +-- Board3D.gd               # The diorama + the animation queue (push / is_busy / idle / event_played)
|   |   +-- BoardViewport3D.gd       # SubViewportContainer: own world, tap/click -> cell, wheel/pinch zoom, tooltip
|   |   +-- UnitToy3D.gd             # One toy piece: model, HP bar, rings, tweened animations
|   |   +-- CombatFx3D.gd, BoardTerrain3D.gd, BoardLayout3D.gd, UnitModels3D.gd, board_marks.gdshader
|   |   +-- FrontOrders.gd           # Front view orders (approach cell, reachable targets, AVANZAR) -> the same move/attack calls
|   +-- grid/
|   |   +-- GridManager.gd           # Cell grid (size per game, saved); the island covers every cell
|   |   +-- GridOverlayControl.gd    # Applies the grid toggle to the 3D overlay
|   +-- map/
|   |   +-- IslandGenerator.gd       # Procedural island mesh
|   |   +-- MapGenerator.gd          # Random deposits: 3-6 per type, room and a road path for each extractor
|   |   +-- WorkerWalkers.gd         # Workers and citizens walking the road network (view only, 3D and 2D)
|   |   +-- WalkerActor.gd, WalkerFigures3D.gd  # One figure's data; the 3D MultiMesh drawer (2D: view2d/WalkerFigures2D.gd)
|   |   +-- StormSky.gd              # Autoload: sky/light of the time of day and the storm
|   +-- storm/StormCycle.gd          # PURE model: the storm's phase clock
|   +-- storm/DayCycle.gd            # PURE model: the day/night clock (DayClock ticks it)
|   +-- services/                    # The 27 game autoloads (table above) + BeckettGate.gd
|   |   +-- ...Manager.gd / EventBus.gd / GameConfig.gd / Tr.gd / DeviceProfile.gd
|   |   +-- GameMode.gd              # Static: the mode of this run and its rules
|   |   +-- Objectives.gd            # Static: the next step for ¿QUÉ HACER?
|   |   +-- GraphicsQuality.gd       # Static (preload): set_quality(), what Minimal turns off outside WorldLook, renderer override, detection rules
|   |   +-- ColonyIdentity.gd        # Static: country flag pieces by rank, random names/flags, word filter
|   |   +-- FloatingText.gd          # Static utility: animated 3D text labels
|   |   +-- ErrorLog.gd, BugReport.gd  # Local error log (Logger, rotated) and the "Informar de un fallo" text
|   +-- ui/                          # 45 scripts: one per panel, plus
|   |   +-- UITheme.gd               # Static dieselpunk theme: tokens, fonts, styleboxes, unit icons
|   |   +-- UILayoutConfig.gd        # Screen slots, panel->slot map, conflicts
|   |   +-- HudRegistry.gd, LayoutEditor.gd        # Hideable/movable HUD elements, the layout editor
|   |   +-- ModalKit.gd              # Builds the war-report / dialog cards from UITheme pieces
|   |   +-- PauseMenu.gd, TitleMenu.gd, NewGameDialog.gd, PauseWatcher.gd
|   |   +-- BattleScreen.gd, SkirmishPanel.gd, WarReportScreen.gd, AuditWaveBanner.gd, AuditDefeatScreen.gd
|   |   +-- TutorialPanel.gd, CoachArrow.gd, PrologueScreen.gd, RegenciaSeal.gd, QuickGuide.gd, DragScroll.gd, TouchTooltip.gd
|   |   +-- HelperPanel.gd, HelpCallout.gd, HelpCatalog.gd, HelpTargets.gd, HelpIndexPanel.gd
|   |   +-- RankPanel.gd, ColonyFlag.gd  # Governor rank badge/toast/COLONIA card; the flag drawn from pieces
|   |   +-- ColonyIdentityPanel.gd, ColonyByline.gd  # Country name + flag editor; flag + name line on reports
|   |   +-- SandboxPanel.gd, SettingsPanel.gd, StormHUD.gd, ObjectivePanel.gd, ArmyPanel.gd, TechTreePanel.gd
|   |   +-- BuildingInfoPanel.gd, ConstructionMenu.gd, MarketPanel.gd, NotificationPanel.gd,
|   |   +-- OnScreenControls.gd, ProcessActionsPanel.gd (+ ProcessCard.gd), ProgressPanel.gd, ResourceHUD.gd, VictoryScreen.gd
|   +-- view2d/                      # The 2D view (docs/18): same services, flat world
|       +-- ViewRouter.gd, ViewMode.gd, View2D.gd  # Scene routing, the view preference, world<->pixel maths
|       +-- Camera2DController.gd, Island2D.gd, GridOverlay2D.gd, StormTint2D.gd
|       +-- BuildingPlacer2D.gd, MapGenerator2D.gd, Building2D.gd, BuildingArt2D.gd, BuildingIcon2D.gd
|       +-- Deposit2D.gd, StatusBadge2D.gd, FloatingText2D.gd, ColonyFlag2D.gd, StockIcon2D.gd
+-- data/buildings/                  # 17 .tres building definitions
+-- assets/
|   +-- audio/{music,sfx,ambient}/   # 4 tracks + 16 SFX (see MANIFEST.md); ambient/ empty
|   +-- models/toy/units/            # Baked combat toys (<id>_player / <id>_regency, boss_mark, crew_nest)
|   +-- models/buildings/<id>/       # GLB models (11 of the 17 buildings use one; sawmill's is kept, unused)
|   +-- textures/                    # metal_plate PBR maps; ui/ 9-patch sprites, ui/icons/, ui/units/ (silhouettes)
|   +-- fonts/, branding/            # Fonts with their licences; logo, banner, key art
+-- tools/
    +-- run_tests.sh, run_tests.ps1  # THE way to run the tests (private user dir)
    +-- package_release.sh, .ps1     # Zips an exported .exe / APK with LICENSE, notices and dist/LEEME-*.txt (docs/19 §8)
    +-- gen_godot_notices.gd         # Regenerates licenses/GODOT-COPYRIGHT.txt from the engine binary
    +-- gen_ui_textures.gd, gen_resource_icons.gd, gen_unit_icons.gd  # Asset generators (headless, -s); icons also at 24/42/60/96 (`<id>_<px>.png`, `UITheme.icon_texture(id, px)`)
    +-- look_probe.gd, look_probe_runner.gd  # Screenshots of every building look (construction phases, ruin, active) and a site row per phase, 3D and 2D
    +-- life_probe.gd, life_probe_runner.gd  # Seeded town: street life in 3D/2D, the empty Ash, CPU cost with 60+ figures
    +-- render_brand.gd, render_branding.gd, render_catalog.gd, showcase_shots.gd  # Branding and screenshots
    +-- build_toy_models.gd, toy_recipes/  # Bakes the toy buildings; `-- --units` the combat toys (toy_recipes/units/)
    +-- unit_toy_probe.gd            # Photo of the baked unit toys in a row (-s, docs/media/dev/unit_toys.png)
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
  docs/22), `siege_probe.gd` (siege balance, docs/17) and `life_probe.gd` (street
  life and its cost, `-- --no-title --no-dev`, docs/04).
- Screenshots go to `docs/media/dev/` (git-ignored).

Note: unit and tech definitions live as inline dictionaries in `GameConfig.gd`
(`unit_types`, `tech_definitions`), NOT as .tres files.

Building 3D meshes come from **two** sources. `BuildingPlacer._create_building_mesh()`
prefers a building's `model_scene` (a GLB under `assets/models/buildings/<id>/`) and
falls back to `DieselpunkBuildingFactory` when it is unset:

| Source | Buildings |
|---|---|
| GLB (`model_scene`) | `barracks`, `foundry`, `fountain`, `garden`, `gold_mine`, `headquarters`, `house`, `refinery`, `statue`, `tower`, `warehouse` (11) |
| Procedural (`DieselpunkBuildingFactory`) | `nucleo`, `road` (connectivity-aware), `market`, `laboratory`, `sawmill` (5) |

The Market and the Laboratory have no model yet; the Farm is now the baked toy model with its growing beds (`FarmCrops3D`, docs/03). The sawmill went procedural on
2026-10-04 (an open shed with the big saw in view, docs/03); its old GLB stays in
`assets/models/buildings/sawmill/`, unused. GLBs made for 1x1 or 2x1 fill their 2x2
plot through `model_scale` / `model_stretch`.

Every building but the road sits on its **lot** (child `Lot`,
`scripts/buildings/BuildingLot.gd`): ground, contact shadow, trim, props and, where the
model lacks one, the exaggerated element (the foundry chimney, the warehouse crane, the
HQ emblem...), decided by `LotPlan.gd` from `GameConfig.building_lot_style` and drawn
the same in 2D. The model is shrunk in plan to leave the yard free
(`BuildingLot.fit_model`). See docs/03 "Parcela y atrezo" and the building style guide.

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

- **GDScript for everything**, combat included. The whole project (27 game autoloads + all UI) is GDScript; a second language adds build times, cross-runtime debugging and marshalling for no benefit here.
- The old plan put unit AI, combat math and pathfinding in C# **for performance**. That argument does not apply at the agreed combat scale: an 8x8 board with 4–6 units per side. GDScript is orders of magnitude more than enough.
- **Migrate later, only on evidence**: if a profiled module proves too slow, port that module to C#. Do not create the .NET project speculatively.

### Adding a New Building

1. Create `data/buildings/my_building.tres` with BuildingData fields (at least 2x2: only the
   road is 1x1; materials go in `cost_materials`). It will need a road to the Núcleo like
   everything else
2. Add limit in `GameConfig.building_limits`
3. Add prerequisites in `GameConfig.building_prerequisites` (if any)
4. Add processes in `GameConfig.building_processes` (if any), and a row in `GameConfig.building_deposit_rules` if it must touch a deposit
5. Give it a look in both views: a GLB in `model_scene` (or a case in `DieselpunkBuildingFactory`) for 3D, and a drawing in `scripts/view2d/BuildingArt2D.gd` for 2D (map, ghost and menu icon share it); and a row in `GameConfig.construction_style` so its construction site has its own materials, fence, tarp and phase-2 silhouette (docs/03, "Obra por edificio y por instancia"; without one it uses `construction_style_default`). Give it a lot in `GameConfig.building_lot_style` (ground, trim, yard, props and a `signature` if the model lacks an exaggerated element) — docs/03 "Parcela y atrezo"
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
three starts with `GameMode.begin_run(GameMode.current, GameMode.tier)` (or `GameMode.load_save_data()` when
reloading a save) **before** the resets, because the resets read the mode's rules.

Checklist:
1. `get_save_data()` / `load_save_data()` on the owning service, and its key in
   `GameManager._write_save()` and the load path.
2. `reset()` in the service, called from the three places above.
3. `load_save_data()` must be **idempotent**: derive from what was saved, never add on
   top of what is already there (loading twice without a `reset()` used to double the
   tech bonuses).
4. Old saves: a missing key means the default, an unknown key is ignored.
5. A test that writes a save (`GameManager.save_path()`, the active slot) parks the player's games with
   `tests/save/save_parking.gd` (the whole `user://partidas/`, the active slot id and a legacy `save_game.json`) (`park()` in `before_test()`, `restore()` in
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
- `food_per_pop` / `farm_crops` / `farm_default_crop` - what people eat and the Farm's crops
- `building_stock_caps` / `building_stock_cap_default` - what each producer holds before it stops
- `spoil_after_seconds` / `spoil_ratio` - spoilage (only with `GameMode.spoilage_enabled()`, i.e. Gobernador); `legacy_save_food`
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
- `rank_xp_sources` / `rank_xp_thresholds` / `rank_rewards` / `colony_colors` / `COLONY_PATTERNS` / `COLONY_EMBLEMS` - governor rank (XP, curve, unlocks, bonuses, flag pieces)
- `audio_*_volume` / `audio_music_fade` / `audio_sfx_voices` - audio
- `phase_triggers` / `early_*` - onboarding phase pacing
- `combat_*` - board, deploy cap, unit combat stats, enemy/risk scaling, map shape,
  drafts, rewards, morale-in-combat (table with effects in `docs/15-combat.md` §8)
- `day_cycle_*` - day and night: on/off switch (`day_cycle_enabled`), the four phase lengths, the light refresh interval (docs/21 §12)
- `storm_*` - storm cycle, damage, the Tithe, tower mitigation and tower crews (and the
  damage a lost crew leaves), the era-1 trial storm (`storm_trial_*`)
- `final_audit_*` - the closing siege: wave count, slots, scaling, resummon floor
- `building_deposit_rules` - which extractor must touch which deposit
- `construction_phase_thresholds` / `construction_style*` / `construction_crane_*` / `building_active_fx` / `building_fx_*` / `ruin_*` /
  `building_look_sync_interval` - how buildings look on the map (docs/03, "Aspecto en el mapa")
- `deposit_per_type_min/max` / `deposit_core_gap` / `map_shore_band` / `deposit_sizes` - the random map's deposits
- `grid_width_min/max` / `grid_height_min/max` - the grid rolled per game (even, saved in the `grid` key)
- `island_coast` - the irregular coast (`scripts/map/IslandShape.gd`, docs/02 "The irregular island"): land area, lobes, noise, bays, capes, clean-up radii, sea border and the land kept around the Núcleo. Copied into each new game's save: retuning it only changes new islands
- `game_mode_rules` / `sandbox_*` - per-mode rules and multipliers on top of the base
  values (modes apply factors; the balance line changes the base values — docs/20, docs/22)
- `population_floor` / `population_regrow_floor` - the ruin floor
- `autosave_interval` / `autosave_debounce` / `max_offline_seconds` - saving and offline

### Shared Utilities

- **FloatingText** (`scripts/services/FloatingText.gd`): Static class for spawning animated 3D text labels. Use `FloatingText.spawn()` for custom text or `FloatingText.spawn_resource()` for resource gain/loss display (`spawn_on()` / `spawn_resource_on()` work on any node, 2D included; the 2D view draws them with `FloatingText2D`). Colors come from `GameConfig.resource_colors`.
- **DieselpunkBuildingFactory** (`scripts/buildings/DieselpunkBuildingFactory.gd`): Static factory generating dieselpunk building meshes from primitives (rivets, pipes, brass/rust palette, shared PBR metal maps). `create(building_id, cell_size, grid_size)` and connectivity-aware `create_road(cell_size, neighbors)`. Called by BuildingPlacer and ConstructionMenu previews **as the fallback when a building has no `model_scene` GLB** — today that is `nucleo`, `road`, `market`, `laboratory`, `sawmill` and `farm`.
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
  `docs/13-roadmap.md` (a "resolve alone" Tithe, the era-3 storage squeeze; the era-1
  trial storm and the hand-mining cut landed 2026-10-04, but the Núcleo/sawmill
  processes still reach the Foundry by minute 4.6-4.9 for a player who chains them)
- **Distribution:** Windows code signing (SmartScreen), Android release keystore, AAB
  and store listing
- **Out of scope for v1:** PvP and co-op
