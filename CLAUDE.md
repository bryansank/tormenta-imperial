# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Tormenta Imperial** is a dieselpunk management + turn-based strategy game built in Godot 4.7 .NET, version **1.0.0** in progress (`project.godot` `config/version`; the 1.0 is assembled on the `integracion/arte-v1` branch). The player builds and manages a persistent base on a procedurally generated island (an irregular coast with bays and capes on a grid rolled per game, 60-74 cells a side, with the sea inside the grid and 3-6 deposits of each type on land), where every building is joined to the Núcleo by roads and staffed by workers you can see walking, progressing through 3 economic eras while the Imperial Storm keeps coming back to collect. The management loop: five resources in one shared pool (food included, grown on Farms and eaten by the people), four workshop materials, production that waits in each building until it is collected with a tap, manual processes in batches (the Núcleo can run every workshop recipe, slower), population and morale, market and laboratory as buildings, tech tree, army training. Turn-based PVE combat: an 8x8 board shown by default as a "front" view (both sides face to face, no grid in sight; the 3D 8x8 board and a flat 2D grid are the alternatives), rock-paper-scissors type advantage, roguelike expeditions with their own map and drafts, the Tithe fought instead of paid (only one Tax in three on the board, "la Visita"; the rest by automatic report), three separate mission campaigns (Land, Sea, Air: each a chain of missions in a single domain with a boss at the end; each boss hands over a piece of HQ level 3), and the Final Audit — in Campaña HQ level 3 (which asks for the three pieces) summons a 3-5 wave siege you have to survive; winning it no longer ends the game: "Volverse el Imperio" (1.2) turns you into the one who collects, with an archipelago of six neighbouring islands to conquer (short land/sea/air mission chains) that then pay you tribute. Colono plays in three chapters (the three acts of the lore) and lasts 3-4 h; Gobernador, 6-8 h. Around that core: a "toy diorama" look (buildings and units baked from CC0 pieces into one vertex-coloured mesh each; a building "pops" when it finishes and collected goods fly to the HUD), 27 building types (10 of them new cheap decorations, with no cap), building limits that rise with the era, a day/night cycle, ambient sound for day, night and Storm, up to five saved games, x1/x2 game speed, graphics quality down to "Mínima" with an FPS cap, four game modes (only Campaña is offered today; the other three are set aside, not deleted), a 2D top-down view next to the 3D one, a configurable UI with PC/tablet/phone profiles and touch placement, a prologue + guided tutorial + help index, and Windows and Android exports. See `docs/15-combat.md` for the combat pillar and `docs/13-roadmap.md` for what is done, what is left and the redesign in progress.

Detailed per-system docs live in `docs/` (see `docs/INDEX.md`).

> "On the mud of history, we shall build monuments of steel."

## Tech Stack

- **Engine:** Godot 4.7 .NET Edition (Forward+ renderer on PC, Mobile renderer on Android via `rendering_method.mobile`)
- **Languages:** GDScript for everything, turn-based combat included (it shipped in GDScript). There is no C# project (no `.csproj`, no `.cs` files) and none is planned for v1 — see "Key Rule" below
- **Tests:** gdUnit4 (`addons/gdUnit4`), ~3180 tests (`func test_`, ~3180 cases) in 239 suites under `tests/` (audio, build, buildings, combat, economy, input, integration, map, modes, save, storm, support, tutorial, ui, view2d) — **always** through the wrapper:
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
5. A fresh game: ☰ → SALIR (main menu) → Nueva partida (mode picker; today it only offers Campaña). It never deletes the current game: it goes to a new slot (up to 5, see "Save/Load System"). Deleting `user://partidas/` starts from scratch
6. **2D view:** Settings → Map view, or `godot --path . -- --view=2d`. Same services, UI and save; only the world view differs (`scenes/main/Main2D.tscn`, `scripts/view2d/`). See `docs/18-vista-2d.md`
7. **User args** (after `--`): `--view=2d|3d`, `--no-title` (skip the title menu, used by probes), `--multi` (allow a second copy, see 9), `--dev` / `--no-dev` (force `dev_mode`, see "Dev Mode")
8. **Your save lives in the editor's user dir** (`%APPDATA%\Godot\app_userdata\Tormenta Imperial`). Anything that plays or writes saves outside a normal play session (probes, experiments, a second agent) needs a git-ignored `override.cfg` at the project root with its own dir, deleted afterwards:
   ```ini
   [application]
   config/use_custom_user_dir=true
   config/custom_user_dir_name="TI_something"
   ```
   On Windows that dir is `%APPDATA%\TI_something`. Tests get this automatically from `tools/run_tests.sh`
9. **One copy at a time (exports only):** an exported desktop build refuses a second copy over the same user dir (`scripts/services/InstanceGuard.gd`, called from `GameManager._ready()` before anything loads). It keeps `user://instancia.lock` (PID, version, exe, time) and checks the PID with `tasklist`: same version open → short notice and quit; another version open → asks to close it (`OS.kill`) and carry on. Not applied in the editor, headless, with `-- --no-title` / `-- --multi`, or on Android/web (Android is single-instance already). Detail in `docs/19-exportar.md` §7

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

32 autoloads in `project.godot`: the 31 game services below, plus `BeckettRuntime`, the `addons/beckett` dev bridge. `BeckettRuntime` loads between `AudioManager` and `DeviceProfile`, then `RankManager`, `ContractManager`, `EconomyManager`, `ThreatManager` and `EmpireManager` (last); it points at `scripts/services/BeckettGate.gd`, which loads the addon's runtime only in the editor, and it is not a game system. `GameMode`, `UITheme`, `UILayoutConfig`, `HudRegistry`, `FloatingText`, `Objectives`, `GraphicsQuality` (graphics quality outside the 3D world, renderer override, first-launch detection rules), `SaveSlots` (the saved-games folder and its index), `ColonyIdentity` (country flag pieces, random names, word filter), `ErrorLog` and `BugReport` are static helpers (a `class_name` or a `preload`), not autoloads. `WorldLook` (`scripts/map/WorldLook.gd`) is the script of the 3D scene's `WorldEnvironment`, not an autoload either.

| # | Service | File | Purpose |
|---|---------|------|---------|
| 1 | `Tr` | `scripts/services/Tr.gd` | i18n translation (ES/EN) |
| 2 | `GameConfig` | `scripts/services/GameConfig.gd` | All tunable values, balance, durations |
| 3 | `EventBus` | `scripts/services/EventBus.gd` | Global signal bus: 166 signals in 36 categories (`docs/10-signals-reference.md`) |
| 4 | `InputService` | `scripts/services/InputService.gd` | Unified input: keyboard, mouse, touch. Its child `TouchTooltip` (`scripts/ui/TouchTooltip.gd`, layer 50) is "hold to read": on touch, a finger held still 0.5 s on a Control shows its tooltip in a bubble without pressing it (docs/21 §9) |
| 5 | `GridManager` | `scripts/grid/GridManager.gd` | Cell grid rolled per game (width and height apart, 60-74, even, `grid_width_*` / `grid_height_*`; 2.0 units/cell, centred on the world origin; saved as `"grid"`, a save without it is 40x40) plus the island seed and the **land mask** (`is_land_cell()`, from `IslandShape`; water is never free), building/obstacle placement; emits `grid_resized` |
| 6 | `ResourceManager` | `scripts/services/ResourceManager.gd` | 5 resources in the shared pool (gold, wood, food, steel, oil) + 4 workshop materials outside it (`Type` enum: `GOLD, STEEL, OIL, WOOD, PLANKS, INGOTS, BEAMS, FUEL, FOOD`) + unlock system |
| 7 | `GameManager` | `scripts/services/GameManager.gd` | Save/load and autosave of up to 5 saved games (`SaveSlots`, `save_path()`, `open_saves_list()`), new game (`request_new_game()` → mode picker, never deletes), offline progression, 3D↔2D switch (`switch_to_scene()`), reload on language change |
| 8 | `ProcessManager` | `scripts/services/ProcessManager.gd` | Timed manual processes (manufacturing, mining), in batches of ×1 / ×5 / MÁX |
| 9 | `ProductionManager` | `scripts/services/ProductionManager.gd` | Passive production that waits in each building until collected, Farm crops, spoilage (Gobernador), construction, upgrades; advances by 0.1 s simulation ticks (`TICK_SECONDS`), not per frame (2026-10-26, `fix/tablet-y-rendimiento`, docs/26); HQ level 3 also asks for the three campaign pieces |
| 10 | `ProgressionManager` | `scripts/services/ProgressionManager.gd` | Era system (3 eras), 9 milestones, **and the Final Audit** (owns the `FinalAudit` model and publishes it) |
| 11 | `MarketManager` | `scripts/services/MarketManager.gd` | Buy/sell resources with floating prices |
| 12 | `PopulationManager` | `scripts/services/PopulationManager.gd` | Population, workers, morale, consumption |
| 13 | `ArmyManager` | `scripts/services/ArmyManager.gd` | Unit training at Barracks, upkeep, desertion, Military Power |
| 14 | `CombatManager` | `scripts/services/CombatManager.gd` | Owns the active `Encounter` and `Expedition`; drives the enemy turn, applies results, saves the run |
| 15 | `RandomEventManager` | `scripts/services/RandomEventManager.gd` | Random events (storms, plagues, festivals...) |
| 16 | `BuildingHealth` | `scripts/services/BuildingHealth.gd` | Building damage, ruined state that halts output, proportional repair |
| 17 | `StormManager` | `scripts/services/StormManager.gd` | Drives the Imperial Storm cycle (`scripts/storm/StormCycle.gd`), storm damage and the Tithe |
| 18 | `DayClock` | `scripts/services/DayClock.gd` | Day/night clock: ticks the pure `scripts/storm/DayCycle.gd` (dawn, day, dusk, night; 16 min, night 3 min), emits `day_phase_changed`, answers `is_night()` / `light_weight()`; the hour travels in the save (`day`). No game rule reads it yet: it drives the light (StormSky), people going home at night (WorkerWalkers) and the night ambience (AudioManager) — docs/21 §12 |
| 19 | `StormSky` | `scripts/map/StormSky.gd` | Paints the `WorldEnvironment`, sun and island: the time of day from `DayClock` (refreshed every few seconds) with the storm's ash blended on top; also the shared window-glow material |
| 20 | `TechTreeManager` | `scripts/services/TechTreeManager.gd` | 15 techs in 3 branches, permanent bonuses |
| 21 | `CloudSaveManager` | `scripts/services/CloudSaveManager.gd` | Supabase auth + cloud save/load (unwired) |
| 22 | `UIManager` | `scripts/services/UIManager.gd` | Panel stacking, ESC-close, slot conflict resolution |
| 23 | `TutorialManager` | `scripts/services/TutorialManager.gd` | Prologue once per game (after the title menu, never behind it), the short guided coach-mark tutorial (2026-10-24: "De qué va" screen, 2-folio lore, then resources card, sawmill, gold mine, barracks, first soldier and first battle; tutorial buildings free; steps derived from what is built; it opens and closes with the game's goal, explains every starting building with its numbers and teaches rotate/move/demolish; it cannot be skipped or closed, docs/23 §2.5), a one-off repair lesson the first time a building is damaged (docs/23 §2.6), the guided first fights on the board (combat lessons, docs/23 §2.4, no Skip either) and which tips/helps were seen; state saved with the game (docs/23) |
| 24 | `UILayoutManager` | `scripts/services/UILayoutManager.gd` | Positions panels from `UILayoutConfig` slots, applies theme |
| 25 | `AudioManager` | `scripts/services/AudioManager.gd` | Signal-driven music/SFX/ambience (day, night and Storm loops), runtime buses |
| 26 | `DeviceProfile` | `scripts/services/DeviceProfile.gd` | PC/tablet/phone detection + override, UI scale (`content_scale_factor`; the phone canvas follows the real dp, 360-540 tall in landscape, `phone_content_scale_for`, and turns `CartoonTheme.phone` on), applies `UITheme` tokens (palette, contrast, opacity, text size), the FPS cap, the non-world part of the graphics quality and the first-launch quality detection. See `docs/21-interfaz-y-dispositivos.md` |
| 27 | `RankManager` | `scripts/services/RankManager.gd` | Governor rank: XP from EventBus signals, rank derived from XP, rank rewards (decoration unlocks, extra slots, small production/storage bonuses, flag pieces) and the player's country: name + flag recipe (`set_colony()`). See `docs/06-progression-victory.md` §Governor rank |
| 28 | `ContractManager` | `scripts/services/ContractManager.gd` | The contract board (ENCARGOS): ticks the pure `scripts/economy/ContractBoard.gd` (3 slots: Regency, neighbours, smuggler; ticked every 0.5 s since 2026-10-26), charges what is asked and pays the reward (resources, morale, colonists if `PopulationManager.add_colonists` exists, Tithe discount through `StormManager.add_tithe_discount` if it exists, else gold), emits `contract_*`; saved as `contracts`; off in Sandbox (`GameMode.contracts_enabled()`). See `docs/27-encargos.md` |
| 29 | `EconomyManager` | `scripts/services/EconomyManager.gd` | The 1.2 economy buildings (`feat/edificios-economia`): the smuggler's ship of the Trade port (pure `scripts/economy/SmugglerShip.gd`: clock, 3 offers, deals through `take_offer()`), minor blueprints bought from it (`has_plan()`, read by `RankManager.is_building_unlocked`), the Diesel plants' fuel (`burn_fuel()`) and the Exchange's Governor interest; emits `smuggler_*`, `diesel_plant_fuel_changed`, `exchange_interest_paid`, `economy_changed`; saved as `economy`. See `docs/03-buildings.md` "Economía de la 1.2" |
| 30 | `ThreatManager` | `scripts/services/ThreatManager.gd` | Coastal threats (1.2, optional loot only): ticks the pure `scripts/combat/ThreatBoard.gd` on a 5 s Timer, finds free shore cells only when a mark is due, launches the 1-fight pure-domain raid through `CombatManager.launch_threat_offer()`, closes it on `expedition_ended`, sends workers to wrecks (`busy_workers()`, read by PopulationManager) and pays them; emits `threat_*`; saved as `threats`. See `docs/15-combat.md` §14 |
| 31 | `EmpireManager` | `scripts/services/EmpireManager.gd` | The **ending with a choice** and Volverse el Imperio (1.2): after the Final Audit is **won** (Campaña/Supervivencia, rule `empire_phase`) the Tax book waits on the table (`choice_pending()`); `choose_ending("sign"|"burn")` stores the choice once (`ending`, in the `empire` key, emits `ending_chosen`): signing opens the archipelago phase (`is_active()`), burning frees the island (`is_free()`: no phase, title `END_BURN_TITLE`, the Sun flag emblem). For the phase it owns the pure `scripts/empire/Archipelago.gd` (6 neighbouring islands, conquest progress, tribute clock), launches conquest missions through `CombatManager.launch_conquest_mission()`, records them on `expedition_ended`, pays the periodic tribute and grants the unique rewards; emits `empire_*`, `conquest_mission_won`, `island_conquered`; saved as `empire`. See `docs/06-progression-victory.md` §Volverse el Imperio |

### Scene Tree (Main.tscn and Main2D.tscn)

The project's main scene is `scenes/main/Boot.tscn` (one node, `scripts/boot/Boot.gd`): it puts the
startup loading screen (`scripts/boot/LoadingScreen.gd`, CanvasLayer 90, outside the scene so it survives the
change) on the root, which loads the scene of the preferred view by threads with a real progress bar, then
mounts it and stays up until GameManager has placed the game and the first 3D frame is drawn (docs/19 §14).
Opening `Main.tscn` / `Main2D.tscn` directly (F6, tests, `-s` probes) skips it; `-- --boot-trace` logs where
the startup time goes (`scripts/boot/BootTrace.gd`, also in an export).

`Main.tscn` is the game scene. Its root carries `scripts/view2d/ViewRouter.gd`: when
the preferred view (Settings, or `-- --view=2d`) is the other one, it holds the game
start and switches to `Main2D.tscn` before anything loads. Both scenes carry **the
same UI nodes, with the same names** (today also in the same order); only the world
nodes differ. `tests/view2d/test_view_mode.gd` checks a list of those names in both
scenes — `PauseMenu` and `TitleMenu` find their siblings by name — but not the order,
and `SandboxPanel` is not on the list yet: a new UI node goes into both scenes and
into that list.

```
Main (Node3D, ViewRouter view_mode="3d")
  +-- MonumentalCamera (Camera3D) -- orthographic RTS camera; a new game starts closer (distance 24) and the view tilts from -52 to -38 degrees as it zooms in (derived from the distance, nothing saved)
  +-- DirectionalLight
  +-- WorldEnvironment (WorldLook.gd) -- sky, tonemapping; WorldLook only decides what costs GPU per quality (SSAO, glow, shadow cascades, MSAA, 3D resolution, simple island)
  +-- IslandGenerator (Node3D) -- procedural island mesh: the irregular coast of the land mask (`IslandShape.coast_polygon`: grass, cliff, sand and foam along it; the sea shades from a distance texture); an old square-island save keeps the rounded square that covers the grid. Rebuilds on `grid_resized`
  +-- GridOverlay (MeshInstance3D) -- faint cell grid (Settings toggle, off by default: it shows while placing), fitted to GridManager at runtime, drawn on land only (a land-mask texture in the shader)
  +-- BuildingPlacer (Node3D, scenes/buildings/BuildingPlacer.tscn) -- placement/move/demolish, touch placement via PlacementAssist; every road drawn by one RoadBatch3D child (a MultiMesh per neighbour mask, at most 16 draw calls)
  +-- OnScreenControls (CanvasLayer 10) -- D-pad, zoom, rotate; "auto" = tablet only (`GameConfig.onscreen_controls_visible()`); a phone gets only rotate-building + CANCEL while placing
  +-- ResourceHUD (CanvasLayer 10) -- top-left dark thin bar: [icon] number chips (resources, free workers, morale once the Storm is armed; small name under it on PC, meaning in tooltips, a tap unfolds the detail) + 8 px storage bar (PC; the number on hold) + materials row; phone: 3 resources + free workers, the rest on tap
  +-- MapGenerator (Node) -- spawns 3-6 deposits of EACH type (`deposit_per_type_*`), on land only, none on the Núcleo sidewalk or the shore band (land next to the water), each with room and a road path for its extractor; then 3-5 schools of fish out at sea, 1-3 water cells off the coast (`SHORE_DEPOSIT_IDS`, for the Fishing dock); `shore_cells()` is the hook for more sea/shore resources
  +-- ConstructionMenu (CanvasLayer 12) -- big CONSTRUIR button (always visible, bottom centre) + the CONSTRUIR window (CartoonTheme, docs/21 §15): category rail on the left, one-line rows (thumbnail, name, cost chips with what is missing in red, hammer that builds), lock + short why, "Al máximo" + MEJORAR; detail column on PC, full screen on phone
  +-- BuildingInfoPanel (CanvasLayer 10) -- right side panel (CartoonTheme, no veil): level N of 3 with bar, what it does in number chips, REPARAR / MEJORAR with cost and why, processes; bottom row by intent: ABRIR MERCADO / INVESTIGAR on the Market / Laboratory (`SCREENS`), workers on/off, MOVER, GIRAR, demolish (red icon)
  +-- MarketPanel (CanvasLayer 11) -- MERCADO window (CartoonTheme): one row per resource, buy/sell prices, [−] n [+], COMPRAR / VENDER; opened from a Market building or `open()`
  +-- ProgressPanel (CanvasLayer 11) -- milestones + era display
  +-- VictoryScreen (CanvasLayer 20) -- victory overlay
  +-- NotificationPanel (CanvasLayer 11) -- THE single place for alerts (warning, danger, notice, combat and achievement = milestone/era/rank-up; docs/21 §14): one column top-left under the resources, max 2 (1 on phone), the rest queued and repeats grouped "×3" (`AlertQueue`), icon + one sentence + ✕, no animations; with a window, the board or the tutorial card over it they wait (one small danger only) + the activity log, opened from ☰ MENÚ → REGISTRO (the old workers/morale status card is gone: those are ResourceHUD chips; the objective strip at the top centre is gone too, 2026-10-05: the next step lives in ¿QUÉ HACER?)
  +-- ObjectivePanel (CanvasLayer 15) -- ¿QUÉ HACER?: the next step, from Objectives.next_step(); on the map, a foldable line with the Captain's face, bottom-left (own layer 10, slot `next_step`); tapping the text opens the panel
  +-- TechTreePanel (CanvasLayer 11) -- INVESTIGAR window (CartoonTheme): 3 branches x 5 tiers of two-line cards + the detail with INVESTIGAR (branch rail on phone); opened from a Laboratory building or `open()`
  +-- ArmyPanel (CanvasLayer 11) -- EJÉRCITO: Tierra/Mar/Aire tabs, train with + (cost in icons), Military Power, troops/queue, upkeep, who is away on campaign; (?) opens each unit's card (UnitCard). Cartoon window since UI phase 2 (docs/28 §15) Since 2026-10-19 training happens in the military building's card (BuildingInfoPanel + `scripts/ui/TrainingSection.gd`, the same rows ArmyPanel uses); the bar's Ejército button goes to the Barracks, and ArmyPanel is the summary ("Ver ejército")
  +-- SettingsPanel (CanvasLayer 15) -- cream window, icon tab rail: Sonido · Pantalla (colours/contrast/layout folded under "Más opciones") · Controles · Juego (persisted in settings.cfg; docs/21 §2)
  +-- HelperPanel (CanvasLayer 14) -- help callouts and tip cards (19), one at a time with ✕ + auto-close, one sentence + "Más" (cream bubble pointing at the instructor); building guide; instances HelpIndexPanel
  +-- SkirmishPanel (CanvasLayer 11) -- MISIONES: Tierra/Mar/Aire/Ataques rápidos tabs, Final Assault checklist, mission card (track, enemies, loot, odds) beside the troop picker (− n +), ¡AL ATAQUE! fixed at the bottom; campaign status while a column is out; "QUE BAJEN" (Final Audit)
  +-- BattleScreen (CanvasLayer 18) -- the 8x8 board (a 3D diorama in a SubViewport, scenes/combat/Board3D.tscn, in its "front" or "board" view; the classic 2D grid in the 2D view and headless) plus the expedition map, draft modal and final report (outside UIManager's stack)
  +-- StormHUD (CanvasLayer 16, 11 under modals) -- storm phase indicator: since the redesign ONE round icon under ☰ (sun / storm cloud, ring in the phase colour, no pulse; phase and margin on hold, slot `storm_icon`); in calm the barometer ("3–5 min", a shifted margin, never the exact minute) and, on tap, the Regency Order card (docs/06 §Orden de la Regencia)
  +-- TutorialPanel (CanvasLayer 19) -- guided coach marks on the real UI, also over the combat board (combat lessons); the card is a speech bubble next to the instructor bust (one sentence, no animation); instances PrologueScreen
  +-- AuditWaveBanner (CanvasLayer 19) -- "Oleada X de N" during the Final Audit (a red ribbon, no fade: it just disappears)
  +-- WarReportScreen (CanvasLayer 19) -- queued war reports: blind defence (defense_auto_resolved) and the Tithe (COBRADO / REPELIDO)
  +-- AuditDefeatScreen (CanvasLayer 20) -- a lost siege: what was taken and how to resummon (or the end of a Survival run)
  +-- SandboxPanel (CanvasLayer 11) -- Sandbox mode only: the SANDBOX tab, summon a storm / the Final Audit
  +-- RankPanel (CanvasLayer 11) -- compact governor rank badge (flag, ★ number, country name, XP bar; phone without the name) left of ☰, rank-up toast, the COLONIA card (country, rank, BANDERA Y NOMBRE → ColonyIdentityPanel, and the `ColonyHub` row: Progreso, Encargos, Registro, Sandbox)
  +-- SkirmishButton (CanvasLayer 10) -- the old MISIONES button next to CONSTRUIR; still in the scene but hidden by BottomBar (its Misiones button replaces it)
  +-- ContractPanel (CanvasLayer 11) -- ENCARGOS: one card per source (clock, what they want with the missing part in red, the reward in icons, ENTREGAR / No, gracias), opened from the COLONIA card (tap the rank) (docs/27)
  +-- BottomBar (CanvasLayer 10) -- the bottom bar (docs/28 §12): Ejército, Misiones (red dot) | CONSTRUIR's gap | Mercado, Investigar, Ayuda; round blue buttons, name under them on PC/tablet, icon only on a phone; grey + lock + reason on hold when not available (slot `bottom_bar`)
  +-- PauseMenu (CanvasLayer 30) -- THE game menu (round ☰ top-right): AJUSTES · PARTIDAS · SALIR + speed x1/x2 inside (Historia / Informar fallo small at the foot), real pause; ESC / Android back; still adds the GameSpeedButton sibling (hidden, it carries the F shortcut)
  +-- TitleMenu (CanvasLayer 30) -- main menu on launch and from ☰ → SALIR

Main2D (Node2D, ViewRouter view_mode="2d") -- world nodes replaced, UI identical
  +-- Camera2D (Camera2DController) / StormTint (CanvasModulate, StormTint2D) / Island (Island2D)
  +-- GridOverlay (GridOverlay2D) / BuildingPlacer (BuildingPlacer2D) / MapGenerator (MapGenerator2D)
  +-- OnScreenControls ... TitleMenu -- the same 26 UI nodes as above (BottomBar included)

Created at runtime, not in either .tscn:
  AboutScreen (layer 33, scripts/ui/AboutScreen.gd, group "about_screen") -- child of TutorialPanel: "De qué va", the first screen of a new game (what the game is and the goal, three icons, ¡VAMOS!); centred at 760 wide and its content's height on PC/tablet, `place_window` on phone (docs/23 §2)
  PrologueScreen (layer 32, scenes/ui/PrologueScreen.tscn) -- child of TutorialPanel: the lore, two folios in plain language since the short tutorial (2026-10-24; "Historia" from the menu shows the same)
  QuickGuide (layer 33, scripts/ui/QuickGuide.gd, group "quick_guide") -- child of TutorialPanel: one screen with four blocks; no longer opens by itself (2026-10-14), texts in AYUDA
  WorkerWalkers (scripts/map/WorkerWalkers.gd) -- child of both placers: workers and citizens walking the roads (view only, docs/04)
  HelpIndexPanel (scenes/ui/HelpIndexPanel.tscn, group "help_index") -- child of HelperPanel: the AYUDA index, opened from the bottom bar (Ayuda)
  NewGameDialog (layer 40, scripts/ui/NewGameDialog.gd) -- the mode picker (step 1) and the country name + flag (step 2), created by GameManager.request_new_game()
  ColonyIdentityPanel (layer 41, scripts/ui/ColonyIdentityPanel.gd) -- the country name + flag editor: open("new") from NewGameDialog, open("edit") from RankPanel's COLONIA card
  SavesPanel (layer 40, scripts/ui/SavesPanel.gd) -- PARTIDAS, the saved-games list, created by GameManager.open_saves_list()
  LayoutEditor (layer 35, scripts/ui/LayoutEditor.gd) -- EDITAR DISPOSICIÓN (Settings), created by UILayoutManager
```

UI panels are positioned by `UILayoutManager` using the slot definitions in
`scripts/ui/UILayoutConfig.gd` (19 named slots — 13 screen areas and 6 help-callout
anchors (`tip_*`) —, `NARROW_SLOTS` / `COLUMN_SLOTS` for narrow canvases, panel->slot map, slot
conflicts).
`UIManager.open_panel()` handles stacking and closes conflicting panels.
All styling comes from the static `UITheme` class (the redesigned screens build from `CartoonTheme`; the army/missions/combat/report pieces live in its `# --- EJÉRCITO` section: `modal_window`/`fit_window`/`fit_card`, `style_pill`, `unit_disc`, `cost_row`, `campaign_track`). Since the phase-2 redesign
(`feat/ui2-hud`, 2026-10-18) the **default style is the "maqueta" one**
(`UITheme.STYLE_DEFAULT = "cartoon"`: `CartoonTheme`, `scripts/ui/CartoonIcon.gd`,
guide in `docs/28-guia-ui.md`). **Since 2026-10-25 `CartoonTheme` (historical name)
paints the dieselpunk skin "D · Mezcla sobria"**: slate bunker panels with brass
edges, Big Shoulders Display headings + IBM Plex Sans Condensed text and figures,
near-square corners, five button intents (brass primary with a pilot light, steel
open, amber warn, red destroy, dimmed + padlock unavailable), dark windows by
default (`window_theme` "light" = sober paper) — `docs/21-interfaz-y-dispositivos.md`
§17 and `docs/24-paleta.md`; `"classic"` stays as an internal fallback
(`-- --ui-style=classic`), and the mockups come from `tools/ui_mockup_probe.gd`.
The polish (`feat/piel-dieselpunk-pulido`) adds line icons (`CartoonIcon`, PNGs from
`tools/gen_resource_icons.gd`), upper-case button text through
`scripts/ui/CapsTranslation.gd`, a neutral ✕, corners from tokens (`CT.RADIUS_*`) and
stamps on the victory and rank-up cards; the Regency Order card folds while a
tutorial card (group `tutorial_card`) is on screen. Text on a title plate uses
`CT.ribbon_text()`, never `CT.on_fill()`; every screen (1.2 ones and "De qué va"
included) builds from tokens and factories, no hand-written cream colours.
Overflow check: `tools/desborde_probe.gd` (+ `tests/ui/test_desbordes.gd`, scanner
`tests/ui/overflow_scan.gd`); cost chips wrap with `CT.cost_flow()`.
On a phone canvas (< 450 short side, `CartoonTheme.phone`, set by DeviceProfile)
`UILayoutConfig.PHONE_SLOTS` is merged in `UILayoutManager.get_slot()` before
`NARROW_SLOTS`. Under the old style, panels and buttons are plain
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
- **The island (2026-10-12), docs/02 "The irregular island":** the grid is rolled per game
  (width and height apart, 60-74, even) and only part of it is land: an irregular coast
  with 2-4 bays and 1-3 capes from `IslandShape` and `GameConfig.island_coast`
  (1550-2300 land cells, about the old 40x40-48x48 all-land map; 3 cells of sea on the
  grid edge; land guaranteed around the Núcleo). Water cells are never free
  (`GridManager.is_land_cell()`). The coast parameters are copied into each new game's
  save, so retuning them only changes new islands; an old save without them keeps its
  square all-land island.
- Deposits visible from start but locked until era unlocks the resource. In 3D each
  deposit is one baked toy mesh (forest, gold vein, iron, oil well) that changes with its
  depletion stage (`DepositMesh.gd`); the 2D view bakes the same idea (docs/02)
- Storage: **one shared pool for the five resources** (food included), not a cap per resource. Base scales
  by era (600 / 800 / 1000) + 500 per warehouse (max 5 in every era: the warehouse cap does not rise, see below).
  Era 1 is 600 so the opening fits: 580 starting resources, plus sawmill + gold mine (330).
  Era 3 ceiling without techs = 1000 + 5x500 = **3500**, exactly the price of the HQ
  level 3 upgrade in Gobernador (Colono pays 60 % of it, `hq_resource_mult`). On top of that, `GameConfig.tech_storage_bonus` adds the storage
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
  calm with the usual tips, but **no real Tithe**, no building or queue damage, production
  at 75% and a quarter of the morale bite. Once per game (saved as `trial_done` /
  `trial_storm` in the storm save), on its own `StormCycle` (`create_trial()`), so it
  never arms the real clock (that still comes with the Foundry); skipped if the
  Foundry comes first, and off in Constructor/Sandbox (`GameMode.storm_trial_enabled()`).
  **Toy Tax (2026-10-17):** when it clears, practice Collectors come down
  (`storm_trial_tithe_*`): with troops at home, a defence board against 1-2 weak
  infantry (scale 0.6; the guided combat lesson if it is the first fight); with nobody
  home, 10 % of the bag (cap 40), never buildings, workers or damage. It is not the
  Tithe: it emits `trial_tithe_resolved` (its own report in `WarReportScreen`), not
  `tithe_resolved`. `trial_tithe_pending` travels in the storm save and is re-asked on
  load (docs/22 §12).

### Resources

| Resource | Role | Starting | Unlock |
|----------|------|----------|--------|
| Gold | Universal currency, troop wages | 300 | Era 1 |
| Wood | Construction | 200 | Era 1 |
| Food | What people eat (Farm, Fishing dock, Market); in the pool; `Type.FOOD` after the materials | 80 | Era 1 |
| Steel | Advanced construction | 0 | Era 2 (Foundry) |
| Oil | Late-game construction | 0 | Era 3 (Refinery) |

### Buildings (61 total, `data/buildings/*.tres`)

| Building | Size | Cost (G/S/O/W + materials) | Workers | Production | Era |
|----------|------|-----------------|---------|------------|-----|
| Nucleo (core) | 3x3 | Free | 0 | +10 worker room (2026-10-24; was 5); manual processes only: its own, every unlocked workshop recipe and hand mining, 1.5x slower. Never damaged; a tall monument (8.9 m, own flag mast) on the same 3x3 | - |
| House | 2x2 | 50/0/0/30 | 0 | +6 workers (room in houses; 9 / 12 at levels 2 / 3) | 1 |
| Sawmill | 2x2 | 80/0/0/50 | 2 | 6 wood/12s; makes planks | 1 |
| Farm | 2x2 | 40/0/0/30 | 2 | Food by crop: 20 / 125 / 600 per 1 / 5 / 20 min; anywhere with a road; max 6 | 1 |
| Gold Mine | 2x2 | 120/0/0/80 | 3 | 8 gold/12s; makes ingots | 1 |
| Warehouse | 2x2 | 60/0/0/40 | 1 | +500 shared storage (+250 per level above 1) | 1 |
| Market | 2x2 | 100/0/0/60 | 1 | Opens the market (ABRIR MERCADO); needs a Gold Mine; max 1 | 1 |
| Laboratory | 2x2 | 150/0/0/100 | 2 | Opens the tech tree (INVESTIGAR); needs a House; max 1 | 1 |
| Foundry | 2x2 | 200/0/0/120 | 3 | 5 steel/15s; makes beams | 1->2 |
| Barracks | 2x2 | 120/0/0/80 + 10 planks | 1 | Trains units (ArmyManager); era 1 = infantry only | 1 |
| Refinery | 2x2 | 300/150/0/100 + 6 beams | 4 | 4 oil/18s; makes fuel | 2->3 |
| Tower | 2x2 | 150/60/20/30 + 4 beams | 1 | Storm mitigation + an artillery crew on defensive boards (only while operational) | 2-3 |
| HQ (capstone) | 2x2 | 500/300/200/200 + 20 beams, 10 ingots, 10 fuel | 5 | 10 gold/20s | 3 |
| Road | 1x1 | 1/0/0/0 | 0 | +2 morale; instant; joins everything to the Núcleo | deco |
| Garden | 2x2 | 30/0/0/20 | 0 | +5 morale | deco |
| Fountain | 2x2 | 60/20/0/10 | 0 | +7 morale | deco |
| Statue | 2x2 | 120/40/0/0 + 3 ingots | 0 | +10 morale | deco |
| Windmill (1.1) | 2x2 | 70/0/0/50 | 1 | Farms within 4 cells +20 %; needs a Farm; rank 3 | 1 |
| Silo (1.1) | 2x2 | 60/0/0/40 | 0 | +300 food outside the shared bag; slows spoilage in Gobernador; needs a Farm | 1 |
| Tavern (1.1) | 2x2 | 90/0/0/60 | 2 | 6 food + 4 gold per consumption tick: +2 morale, +1 growth (houses within 4) | 1 |
| Carpentry (1.1) | 2x2 | 70/0/0/60 | 2 | Own processes: planks and furniture; needs a Sawmill | 1 |
| Well (1.1) | 2x2 | 40/0/0/30 | 0 | −20 % storm damage within 3 cells, +15 % health after the storm; rank 2 | 1 |
| Lighthouse (1.1) | 2x2 | 180/0/0/120 + 6 planks | 1 | Storm Warning +20 s; max 1 | 1-2 |
| Fuel depot (1.1) | 2x2 | 200/80/0/80 + 4 beams | 1 | +500 oil outside the shared bag; needs a Refinery | 3 |
| Shipyard (1.1) | 2x2 | 220/80/0/120 + 10 planks, 4 beams | 3 | Trains ships; must touch the coast; needs a Foundry; no cap (2026-10-18) | 2 |
| Aerodrome (1.1) | 2x2 | 320/140/60/80 + 8 beams, 6 fuel | 4 | Trains planes and airships; needs a Refinery; no cap (2026-10-18) | 3 |
| Fishing dock (1.1) | 2x2 | 60/0/0/40 | 2 | 12 food + 3 gold/30s, no crop; on the coast with a school of fish within reach 4 (2 docks per school); caps 3/4/6; process "Ahumar pescado" 15 wood → 25 food | 1 |
| Trade port (1.2) | 2x2 | 300/100/0/160 + 12 planks, 6 beams | 2 | The smuggler's ship docks every 6-10 min for 90 s with 3 offers; on the coast, faces the water; needs Market + Foundry; max 1 | 2 |
| Exchange house (1.2) | 2x2 | 350/120/0/100 + 8 ingots, 4 beams | 2 | Market spread −10 points (30 % → 20 %, floor 8 %); Governor: 1 % interest on stored gold per minute (cap 20); needs Market + Foundry; **rank 6**; max 1 | 2 |
| Diesel plant (1.2) | 2x2 | 320/160/80/60 + 6 beams, 4 fuel | 2 | Burns 1 fuel / 45 s; sawmills, gold mines, foundries, refineries within 5 cells +15 %; needs a Refinery; **rank 9** (1.2: no blueprints); max 2 | 3 |
| 10 cheap decorations | 2x2 | 10-40 gold + 5-30 wood | 0 | +1 to +3 morale; no cap; Street lamp, Bench, Hedge, Street tree, Colony sign free; Flower pots, Hay cart rank 2; Bonfire 3; Flagpole 5; Palm trees 13 | deco |
| Bastion (1.2) | **2x1** | 60/25/0/30 | 0 | Wall: −30 % storm damage to what stands behind it (towards the island centre) within 3 cells; a +2 defence cover cell on defensive boards (1 per 3 bastions, max 2); needs Foundry + Barracks; caps 6/10/14 | 2 |
| Scrapyard (1.2) | 2x2 | 160/40/0/90 + 6 planks | 2 | Repairs −40 % within 4 cells; after each Storm: 12 steel per ruin in its area, 1 part per 2 ruins (max 3), lifts 1 ruin to 35 %; needs a Foundry; **rank 4**; caps 1/2/2 | 2 |
| Telegraph (1.2) | 2x2 | 200/60/0/80 + 4 beams | 1 | +1 contract slot ("El telégrafo", orders from any source) and new contracts last +50 %; needs Foundry + Warehouse; max 1 | 2 |
| 18 more decorations (1.2) | 2x2 (Governor's plaza 3x3) | 40-500 gold, steel from era 2, oil from era 3 | 0 | +4 to +18 morale; no cap; ranks 4-18, Museum cannon / Storm column by refused Taxes; boat and wreck coast only | deco |

The seven "(1.1)" rows (`feat/edificios-utiles-1`, doc 21 §6.3): areas in
`scripts/buildings/UtilityEffects.gd` (on build/demolish, never per frame), look in
`scripts/buildings/UtilityToys.gd` (one procedural toy mesh per type until its bake
exists) and `BuildingArt2D._utility`. Full table: `docs/03-buildings.md`.

**Fishing dock (feat/muelle-pesca, doc 21 §6.3 n.º 7):** `fishing_dock`, era 1, the
second food producer, and a little gold from the same school (12 food + 3 gold / 30 s).
Its deposit rule (`fish_shoal`, reach `fishing_dock_reach` 4, `"shore": true`,
`"per_deposit"` 2 via `PlacementRules.deposit_with_room()`) puts it on the coast: the
**school of fish** is the first sea deposit (`MapGenerator.SHORE_DEPOSIT_IDS`), 3-5 per
island **out at sea** (fix/peces-en-el-mar: `min_gap` 1 to `max_gap` 3 water cells off
the land, `GameConfig.sea_deposit_rolls`, own RNG seeded by the island;
`GridManager.place_sea_obstacle`), never runs out (`GameConfig.endless_deposits`, no
hand mining). A plank pier joins the dock to its school (`MapGenerator.pier_path`,
`DockPier3D` / `DockPier2D`, view only); no access ring. Old saves get their shoals on
load (`MapGenerator.ensure_shore_deposits()`); old coast-hugging shoals that no dock
reaches are moved out to sea there, the ones with a dock stay. In Gobernador its fresh fish spoils in half
the time (`fishing_dock_spoil_mult`). All its numbers live in the GameConfig block
"Muelle de pesca" at the end of the file: `_register_fishing_dock()` adds its rows
to the shared tables (limits, deposit rule, processes, stock cap, styles) when
GameConfig is created. Baked toy model `assets/models/toy/fishing_dock.tscn`; 2D
`BuildingArt2D._fishing_dock` / `_dep_fish_shoal`; 3D shoal `DepositMesh._fish_shoal`.
¿QUÉ HACER? only offers it as food support when no Farm fits. Detail: docs/02
"Yacimientos de mar", docs/03 "Muelle de pesca".

**Defensa (1.2, `feat/edificios-defensa-vida`, doc 21 §6.3 n.º 11, 12, 18):** the
Bastion, Scrapyard and Telegraph rows. **The neighbourhood beauty of that branch did
not make the 1.2** (Bryan, 2026-10-25): no `beauty*` metas, no `BeautyTrim`, no extra
room or morale for houses, no `beauty_changed` signal (`tests/buildings/test_v12_unlocks.gd`
and `test_defense_life.gd` check it stays out). Areas in
`scripts/buildings/DefenseLifeEffects.gd` (called right after `UtilityEffects` from
`ProductionManager._refresh_areas()`, on build/demolish/finish/ruin/repair/upgrade/
staffing, never per frame; metas `bastion_cover`, `scrap_cover`; runtime
`GameConfig.defense_cover_cells`, `contract_extra_slots`, `contract_duration_mult`,
cleared in `ProductionManager.reset()`). All numbers in the GameConfig block
"Defensa y vida" at the end of the file; `_register_defense_life_buildings()` adds
their table rows. **Bastion cover** is pure combat model:
`Encounter.cover` + `CombatRules.damage(..., cover)`; a board without bastions is
unchanged (docs/15 §3). **Telegraph** slot: `ContractBoard.WIRE` (saved in
`contracts`, with `from`; ENCARGOS shows "El telégrafo · <who>"). The building panel
shows what each one covers in its status line (`DefenseLifeEffects.info_line`).
Looks: `DefenseToys.gd` + bakes in `assets/models/toy/`; 2D
`BuildingArt2D._bastion/_scrapyard/_telegraph`. Detail: docs/03 "Defensa".

**Economy buildings (1.2, feat/edificios-economia, doc 21 §6.3 n.º 13, 14, 16; doc 14
§P4):** `trade_port`, `exchange`, `diesel_plant`. Numbers in the GameConfig block
"Economia" at the end of the file (`_register_economy_buildings()` adds their rows to
limits, prerequisites, construction/lot styles and active fx). The Trade port is in
`PlacementRules.SHORE_ONLY` and `FACES_WATER` (like the Shipyard). `EconomyManager`
(autoload, last) runs the smuggler's ship (pure `scripts/economy/SmugglerShip.gd`):
no clock without a working port (standing, road, workers), first ship 75 s after,
then every 6-10 min; never in Ash/Storm (it sails early if the Ash comes); waits while
a board is open. Three offers: exclusive (2-4 spare parts at 60 gold; the **minor
blueprint** of the branch is off in the 1.2, `smuggler_plan_chance = 0`, see below), a
workshop material, and a resource deal (sells at 75 % of the Market buy price or buys
at 1.6× its sell price). The panel is a CartoonTheme window (`SmugglerPanel`, modal,
dodge of the ☰).
The Exchange's spread cut is `GameConfig.market_spread_cut` (runtime, set by
`UtilityEffects.refresh`), read through `GameConfig.effective_market_spread()` by
`MarketManager`. The Diesel plant's area is the meta `diesel_bonus` on industrials
(UtilityEffects, on build/demolish/workers change, or when a plant runs out of fuel);
`ProductionManager.get_cycle_yield` applies it only live (not offline). Looks: own toy
models (`scripts/buildings/EconomyToys.gd`, baked to `assets/models/toy/<id>.tscn`,
picked by `EconomyToys.create()` without `model_scene`), 2D in `BuildingArt2D`; the
ship is `scripts/map/SmugglerShip3D.gd` (one shared ~320-tri mesh, Tweens, no
`_process`) and `scripts/view2d/SmugglerShip2D.gd`, children of the placers; tapping it
(`EconomyManager.ship_hit`) or VER EL BARCO on the port opens `scripts/ui/SmugglerPanel.gd`
(created on demand, not in the scenes). Detail: docs/03 "Economía de la 1.2", docs/02,
docs/05 "Casa de cambio".

**Unlocks without blueprints (1.2 integration, `integracion/v1.2b`):** the Núcleo
1-5 + blueprints branch did not make the 1.2, so the era caps stay
(`building_limits_by_era`) and the buildings that asked for "Núcleo N + blueprint"
open by era, requisites and rank (block "Integracion de la 1.2" at the end of
GameConfig, `V12_RANK_BUILDINGS`): Trade port = Market + Foundry (era 2); Scrapyard =
Foundry + **rank 4**; Exchange = Market + Foundry + **rank 6**; Diesel plant = Refinery
(era 3) + **rank 9**. None of them is in `combat_blueprint_buildings` any more (only
the military branch's two, which have no `.tres`), and the smuggler sells no
blueprints. Tests: `tests/buildings/test_v12_unlocks.gd`.

**Cheap decorations (feat/decoraciones-1):** `lamp_post`, `park_bench`, `hedge`,
`avenue_tree`, `flower_planter`, `colony_sign`, `hay_cart`, `bonfire`, `flagpole`,
`palm_trees` (doc 21 §6.4 of the private context). One shared mesh per type from
`scripts/buildings/DecorMesh.gd` (baked `assets/models/toy/<id>_mesh.res` when it
exists, procedural until then), returned by `DieselpunkBuildingFactory.create()`;
2D in `BuildingArt2D`. Table, pieces and what is pending: `docs/03-buildings.md`.

**The other 18 decorations (feat/decoraciones-y-trafico, 1.2):** `flower_stall`,
`community_garden`, `small_fountain`, `entrance_arch`, `bandstand`, `beached_boat`,
`gear_garden`, `fair_stage`, `fair_tent`, `pond_bridge`, `water_mill`, `museum_cannon`,
`container_mural`, `clock_tower`, `wreck_monument`, `storm_column`, `moored_airship`,
`governor_plaza` (3x3) — the rest of doc 21 §6.4, +4 to +18 morale, ranks 4-18 (§6.5),
the Museum cannon and the Storm column by refused Taxes (`decor_deed_unlocks`,
`PlacementRules.check_deed()`), the boat and the wreck coast only
(`decor_shore_only`). Procedural in `scripts/buildings/DecorMesh2.gd` (served by
`DecorMesh`, drawn by `DecorBatch3D`), all 18 baked (236-596 triangles, the plaza 916),
2D in `BuildingArt2D._d2_<id>()`. Their rows in `rank_rewards`, `construction_style`
and `building_lot_style` are added by `GameConfig._register_decorations_traffic()` at
the end of GameConfig (not written inside the tables). Detail: docs/03.

**Key constraint:** Foundry costs 0 steel (it unlocks steel). Refinery costs 0 oil (it unlocks oil).

**Building caps rise with the era (2026-10-14, Bryan's D1).** `GameConfig.building_limits_by_era`
holds `[era 1, era 2, era 3]` (≈ ×1.5 / ×2: house 10/15/20, farm 6/9/12, sawmill 5/8/10,
gold mine 4/6/8, foundry 3/5/6, refinery 2/3/4); era 1 is the old cap. **The Barracks
has no cap since 2026-10-18** (`building_limits["barracks"] = -1`, not in the era
table); the brake is on the army instead (see Army & Units).
Warehouse stays 5 (keeps 1000 + 5×500 = 3500 = HQ L3) and tower stays 6 (4 already
reach the 60 % mitigation cap); Market, Laboratory and HQ stay 1. **Decorations have no
cap** (any `BuildingData.is_decoration`, no table entry needed). The only reader is
`GameConfig.get_building_limit(id)`: era in progress + `rank_limit_bonus`; -1 in
Sandbox. Nothing new is saved (derived from era and rank). CONSTRUIR shows
"3/6 · era 2: 9" on each card and refreshes on `era_advanced`. Detail: docs/03.

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
gives with real numbers (`upgrade_effect_lines()`). The level shows on the model, with
no floating plate (2026-10-17): in 3D the same model grows (mostly upwards,
`LevelTrim.level_scale`), stands on a stone plinth with a brass band and gains brick
chimneys at its back corners (one at II, two at III with a lit lamp; decorations get
corner lamps instead), all in one cached `LevelTrim` mesh hung from the model; in 2D
the same pieces are baked into the drawing, plus small brass chevrons with no box.

**Decorations by rank:** see the rank paragraph below and the decorations row above;
the road is never locked.

**Finishing and collecting feel (2026-10-14, `feat/salto-y-camara`):** a finished
building jumps 1.0 → 1.12 → 1.0 in 0.3 s with a one-shot puff of 8 dust motes
(`BuildingFx.bounce` / `dust_burst_3d` / `dust_burst_2d`, a Tween, no `_process`; only
the jump in Minimal quality); collect icons pop in and bob only while there is
something to collect, and on collecting the icon and its "+N" fly to their HUD chip
(`FloatingText.fly_to_hud`). The baked models carry a dark contact edge at the foot of
the walls (`LotMesh.contact_edge`).

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
Refinery (era 3) needs Foundry + Barracks + Laboratory (`building_prerequisites`).

**Early Barracks (2026-10-17, `feat/cuartel-temprano`):** the Barracks is era 1, no
steel, one worker, and needs only the Sawmill (its planks). ¿QUÉ HACER? asks for it right
after the first Sawmill (`Objectives.LINE`, `needs: tithe`), then the Farm, one soldier
and the first mission; the guided tutorial has a Barracks step (5 of 13) right after
collecting the wood. Artillery/Tank keep their era (`ArmyManager.is_unlocked`), and the
ARMY panel says what unlocks them (`LBL_ARMY_LOCKED_ERA_*`). The Tower now also needs
the Foundry. Measured with `line_probe` on 1.0 and on 1.1 (docs/22 §12): no stall, era 1 16.8-18.8 min.

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

- **Every building is at least 2x2**, except the road (1x1) and the Bastion wall (2x1, 1.2). The baked models already
  fit their plot (`model_scale` / `model_stretch` stay at 1; they were for the old
  GLBs); `BuildingData.instantiate_model()` is the only way to spawn one.
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
- **Traffic (1.2):** `scripts/map/RoadTraffic.gd` (next to WorkerWalkers in both
  placers): a few toy diesel trucks drive from staffed extractors to the nearest
  Warehouse (or the Núcleo) along the road network and back, the load in the
  resource's colour. One truck per `traffic_sources_per_truck` sources, capped per
  profile (`traffic_truck_cap` 12/8/5) and **none in Mínima**
  (`traffic_truck_cap_minimal`); indoors through Ash, Storm and Tithe. Data in
  `TruckActor.gd`, drawn by `TrafficFigures3D` (one MultiMesh, one draw call) or
  `TrafficFigures2D` (one `_draw`); one `_process` for all, off when there are none.
  View only, never saved. Detail in docs/04 §Traffic and docs/26 §7.8.
- **Auto-road:** `evaluate_placement()` accepts an unconnected spot when a free route
  to the network exists and returns it as `"route"`; the placers charge building +
  route together (`Rules.cost_with_route`, 1 gold per tile) and lay it with
  `Rules.pave_route()` (emits `building_placed` per tile). Roads are instant
  (`build_time = 0`). No route → reason `"road"` (`LBL_NEEDS_ROAD`).
- **Long road (drag):** with the road in hand, mouse press-drag-release (touch: tap
  start, tap end, tap end again or ✓) lays a whole line: straight or L (longer axis
  first, R / ↻ flips the corner), else the shortest free path. Existing road is
  crossed free; it must touch the network; tiles are laid from the network out and,
  short of gold, only the affordable ones (`PlacementRules.plan_road_line` /
  `lay_road_line`, state in `PlacementAssist`, preview via `assist_show_line`). A
  click without drag still lays one tile. docs/21 §9 "Carretera larga".
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
- Nucleo provides 10 starting room and the game starts with 10 people (`population_start`, 2026-10-24: the short tutorial — sawmill, gold mine, barracks, first soldier, first battle — runs without a House; with 5 the old tutorial ran out of workers). Houses provide 6 each and arrive full when finished
- Each production building requires workers (see table above), first built = first served
- **Workshop queue (2026-10-19):** each ×1 / ×5 / MÁX in a building card ADDS batches to that process (`ProcessManager.enqueue_process` / `enqueue_mining`, paid when queued, capped by `process_batch_max`; `dequeue()` removes batches not started and refunds them in full). One process per building at a time; the save is the same `count` / `total`
- **Retirar / poner trabajadores:** `PopulationManager.set_workers_off(node, off)` (button
  in BuildingInfoPanel) frees a building's workers for others and stops it; saved per
  building as `workers_off`. Badge: "sin trabajadores (retirados)"
- **No vein, no work:** a Sawmill, Gold Mine or Foundry whose deposit was mined out by
  hand stops (`PlacementRules.has_its_deposit()`, meta `has_vein`, badge "sin veta")
- **Manual mining takes workers:** mining a deposit by hand holds
  `GameConfig.mining_workers` (2) while it lasts and needs the deposit to touch a road
  joined to the Núcleo (`ProcessManager.mining_blocker()`: `MINE_NEEDS_ROAD` /
  `MINE_NEEDS_WORKERS`)
- **A finished House fills at once** (2026-10-19): when its construction or upgrade ends, every worker that fits comes in (`PopulationManager._move_in()`, "+6 trabajadores" over the house, `residents_arrived` so the new walkers leave that house), unless morale < 30. The +1 per tick (20s; 40s early) drip, with morale >= 30 and room, is only for getting lost people back (docs/04)
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
| `hq_max` | **HQ Level 3 — the single key of the Final Audit** (it asks for the three campaign pieces) |

HQ upgrade costs: `hq_upgrade_costs` (L2 1300g/900s/500o/300w + 350 beams, 140 ingots, 200 fuel; L3 1500g/800s/500o/700w + 700 beams, 280 ingots, 400 fuel); Colono pays 30 % of the workshop materials and 60 % of the bag (`hq_material_mult` 0.3, `hq_resource_mult` 0.6 in `game_tier_rules`), Gobernador all of it. L3 also asks for the three pieces.

**In Campaña, HQ level 3 does not win the game.** Since 2026-10-25 (`feat/ritmo-colono`,
docs/15 §13) the Final Audit has **one key**: HQ level 3. Each campaign boss hands over
a **piece** (Land: Planos del Bastión, Sea: Casco del Leviatán, Air: Motor del
Zepelín; `GameConfig.CAMPAIGN_PIECES`, `CampaignBook.has_piece()` = boss beaten) and
the HQ level 3 upgrade asks for the three on top of its cost
(`GameConfig.hq_needs_pieces()`, `CombatManager.hq_missing_pieces()` /
`hq_pieces_text()` "Para el CG 3 te faltan: pieza de Mar, pieza de Aire";
`ProductionManager.start_upgrade()` refuses without them).
`ProgressionManager.final_audit_ready()` is `hq_max`; `final_audit_missing()` lists the
missing pieces and HQ 3. The pieces are steps of ¿QUÉ HACER?'s line
(`Objectives.LINE` entries `kind: "campaign"`, with the HQ standing — after the
Shipyard, the Aerodrome and the six siege tanks — and before HQ level 2). `GameMode.audit_needs_campaigns()` (rule `audit_needs_campaigns`: Campaña
and Supervivencia yes; Constructor/Sandbox no) and the global switch
`GameConfig.final_audit_needs_campaigns` (tests of the 1.0 path turn it off) decide
whether HQ 3 asks for pieces. Old saves: a piece is a boss already beaten; one with
HQ 3 done and campaigns unfinished can call the siege. Then
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

**The ending with a choice (1.2, Bryan's decision 2026-10-25, `integracion/v1.2b`).**
Winning the Final Audit in Campaña or Supervivencia (`GameMode.empire_enabled()`) no
longer ends on one screen. `VictoryScreen` shows the victory (stats) with **EL LIBRO**
instead of SEGUIR; the next window is the table with the Tax book and two cards, each
with its instructor's face and line (`InstructorFace.gd`, a still bust in a circle):
**FIRMAR** (Sergeant Bombarda: "Sign it. Now we collect.") or **QUEMAR** (Captain
Remache: "Burn it. Nobody should need permission to breathe."). `EmpireManager.choose_ending()`
stores it once and saves:
- **Sign** → "AHORA FIRMAS TÚ" (Remache: "That is how the Regency started.") and the
  archipelago phase below.
- **Burn** → "LA ISLA ES LIBRE": the Storm already stopped for good, there is no phase
  and nobody collects; keep playing (¿QUÉ HACER? = free world), title "Quemó el libro"
  next to the rank and the **Sun** flag emblem before its rank (the lore: the sun comes
  up for the first time in three generations).
A save won with the book still on the table asks again on load
(`VictoryScreen._offer_pending_choice`); ¿QUÉ HACER? says `OBJ_WHY_BOOK` meanwhile. Old
saves of the empire branch that had started the phase count as signed. Constructor
keeps its own victory (no book). Texts: block `FINAL CON ELECCION` of `Tr.gd` (`END_*`).
Tests: `tests/ui/test_final_choice.gd`.

**Volverse el Imperio (1.2, `feat/volverse-imperio`) — after signing.** `EmpireManager`
opens a new phase on the same island. Six neighbouring islands
(`GameConfig.empire_islands`: crest, difficulty 1-3, islands needed first, a 2-3
mission chain of pure-domain fights — sea or air first, the land landing last, a boss
in the Ash Citadel — periodic tribute and a unique reward: a decoration before its
rank, flag pieces or a title). Missions are offers `{kind: "conquest", island, mission,
domain, ...}` built by the pure `scripts/empire/ConquestGenerator.gd`, launched from
MISIONES → IMPERIO tab (`SkirmishPanel`, island pills, the campaign track) and shown on
`ArchipelagoPanel` (a CartoonTheme window: map left, island card right; opened from the
colony card — tap the rank — ARCHIPIÉLAGO, from the IMPERIO tab or from the signing
screen; mounted at runtime by `VictoryScreen` as a sibling, so neither `.tscn`
changes). ¿QUÉ HACER? proposes the next conquest (`Objectives.empire_step()`).
Imperial titles by islands held show next to the rank title. Values unmeasured
(`empire_*` at the end of `GameConfig`).
Full detail in `docs/15-combat.md` §6 and `docs/20-modos-de-juego.md`.

### Governor Rank — full doc: `docs/06-progression-victory.md` §Governor rank

A third axis next to eras and milestones: XP inside the run (owner's decision,
2026-10-04). `RankManager` adds XP from EventBus signals (`GameConfig.rank_xp_sources`:
build 15, upgrade 25, production cycle 1, process/mining 5, trade 5, unit 10, fight won
40, expedition won 80, storm 30 + 10/severity, milestone 100) and **derives** the rank
from it (`rank_xp_thresholds`, 18 ranks, step `100 + 60*(n-1)`, ~9860 XP for the last;
not yet measured with the line probe). Titles `RANK_TITLE_<n>` (Colono, Capataz … Cónsul
… Archigobernador). `rank_rewards` gives decorations (Garden, Flower pots, Hay cart 2; Bonfire 3; Fountain, Flagpole 5; Statue 8; Palm trees 13),
extra building slots (`rank_limit_bonus`), small bonuses (`rank_production_bonus`
+7 % and `rank_storage_bonus` +8 % at rank 18, **assigned**, never added, so loading
twice is safe), flag pieces (`patterns`, `emblems`, `colors`) and the regiment's
paint schemes (`paints`: plain 1, stripes 3, spots 6, desert 9, snow 12, parade 15).

**The player's country (2026-10-12):** a name (max `COLONY_NAME_MAX` = 26, "Al azar"
names like "Liga de Vaporia" in ES/EN, a short ES/EN word filter in
`scripts/services/ColonyIdentity.gd`) and a flag built from pieces: a recipe
`{"pattern", "emblem", "colors": [field 1, field 2, emblem]}` drawn by code in
`scripts/ui/ColonyFlag.gd` (14 patterns, 12 emblems + none, 13 colours from
`colony_colors` / ToyPalette; `fix_spec()` keeps it readable, cached textures,
`draw_spec()` for lists). Rank 1 opens 5 patterns, 4 emblems and 6 colours; the
showier ones come by rank (`rank_rewards`). Picked in the editor
`scripts/ui/ColonyIdentityPanel.gd` (`open("new"|"edit")`, signals `confirmed` /
`cancelled`), opened from the COLONIA card (tap the rank badge, RankPanel) and as the New Game step (NewGameDialog →
`GameManager.start_new_game(mode, tier, identity)`; `_new_game()` applies it with
`RankManager.set_colony()` right after `RankManager.reset()`). Flies on the Nucleo and
on every Barracks, and on no other building (2026-10-18: not on the HQ any more;
`ColonyFlag.FLAG_BUILDINGS = ["barracks"]`) (`ColonyFlag3D`: small plane + vertex-shader
wave, off in low quality; hangs from the model's `FlagAnchor` marker when it has one —
the Barracks has a short mast on its roof ridge, flag at `BARRACKS_SCALE`; shared
plane/material/shader/pole meshes, no `_process`; hidden under construction or in
ruins; `ColonyFlag2D` from `BuildingArt2D.flag_mount()`), signs the war
reports, the audit defeat, the victory and the board header (`ColonyByline`), and its
first colour fills our board tokens' round mark. Signal `colony_identity_changed`. The basic
buildings keep their era unlocks. Locks go through `PlacementRules.check_rank()`; the
CONSTRUIR card shows a padlock and "Rango N". UI: `RankPanel` (badge in slot
`rank_badge`, rank-up toast with SFX `rank_up`, the COLONIA card). Saved as `"rank": {"xp", "colony": {"name", "flag"}}`;
a save without it is rank 1 with a country rolled from `GridManager.island_seed`; an old
`"flag"`/`"color"` pair is translated to pieces. Sandbox has every rank unlock open.

### Contracts (ENCARGOS) — full doc: `docs/27-encargos.md`

A board of 3 timed delivery contracts, one slot per source (doc 21 §2.3 of the
private context): **the Regency** (era 2+, asks steel/beams/ingots, later oil/fuel;
pays a discount on the next Tithe), **the neighbours** (era 1, wood/food/gold/planks;
pay morale, colonists once that exists), **the smuggler** (era 1, wood and workshop
materials; pays gold or scarce resources). Rewards are fixed when the contract
appears. Colono: missing one costs nothing; Gobernador: missing or refusing lowers
that source's reputation and cuts its next rewards. Pure model
`scripts/economy/ContractBoard.gd` (returns events, own RNG, no `class_name`),
service `ContractManager` (last autoload), panel `ContractPanel` from the COLONIA card
(tap the rank badge; it left ☰ in the 2026-10 redesign). ¿QUÉ HACER? shows a deliverable contract as an extra line
(`Objectives.contract_step()`, outside `next_step()` so the line probe is unchanged).
Tunables `contract_*` at the end of `GameConfig`; mode rule `"contracts"` (off in
Sandbox). Saved as `"contracts"`; a save without it gets a fresh board. Values not
yet measured with `line_probe`.

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

**Colono in 3-4 h, three chapters (2026-10-25, `feat/ritmo-colono`, docs/06
§Capítulos, docs/22 §17):** I *Nadie nos mira* (to the Foundry), II *La cuenta* (the
Refinery and the Land piece), III *El libro* (the Sea and Air pieces, HQ 3, the
siege). `scripts/services/Chapters.gd` (static) derives them; `ProgressionManager`
keeps `chapters_closed` (save `progression.chapters`) and emits
`EventBus.chapter_completed(n)`; ¿QUÉ HACER? shows the chapter and its goals and
`scripts/ui/ChapterScreen.gd` (created by ObjectivePanel) shows the short closing card
(chapter III closes with the victory screen). Colono's pace comes from
`game_tier_rules`: `campaign_missions` (Land 4, Sea 2, Air 2 of the table's 6/5/5;
Gobernador plays all 16), `hq_material_mult` (0.3), `hq_resource_mult` (0.6) and `final_audit_waves_delta` (−1: a 3-4 wave siege); Gobernador 1, 1 and 0. Measured: Colono 3 h 24-4 h 28, Gobernador 6 h 13-7 h 54 (docs/22 §17).

### Army & Units (management -> combat bridge)

- **ArmyManager** trains each unit at **its** building (`unit_types[...]["building"]`:
  Barracks for land, Shipyard for sea, Aerodrome for air; no key = Barracks).
  Parallel training slots = one per building, only for that building's units, up to
  a ceiling per kind (`army_training_slots_max` 5 for Barracks,
  `army_training_slots_max_by_building` 2 for Shipyard / Aerodrome;
  `GameConfig.get_training_slots_for()`, `max_slots(building)`, `training_in(building)`;
  one unit per slot, no queue). Cost paid up-front. `has_military_building()` (any of
  the three) opens the army panel and the skirmishes.
- Capacity (`GameConfig.get_army_capacity_for(counts)`, the one function): Barracks
  `3 base + 8` for each of the first `army_full_capacity_barracks` (3), `+4` after,
  capped at `army_capacity_max` (43) — `get_army_capacity(n)`; Shipyard and Aerodrome
  the same rule (`army_building_capacity()`: +4 for the first 2, +2 after, capped at
  +12 each); the whole army at `army_capacity_max_total` (67). Barracks, Shipyard and
  Aerodrome have no building cap (2026-10-18), so this is the brake, with price,
  workers and gold upkeep behind it. Owned units AND units in training count.
- Units gated by era (`ProgressionManager.current_era >= unit.era`).

| Unit | Domain | Building | Era | Cost | Train | Upkeep | Power |
|------|--------|----------|-----|------|-------|--------|-------|
| Infantry | land | Barracks | 1 | 40g + 20w | 20s | 1 gold | 10 |
| Artillery | land | Barracks | 2 | 120g + 50s | 45s | 2 gold | 28 |
| Vehicle | land | Barracks | 3 | 300g + 130s + 60o + 8 beams | 100s | 4 gold | 65 |
| Torpedo boat | sea | Shipyard | 2 | 100g + 40s + 40w | 40s | 2 gold | 24 |
| Gunboat | sea | Shipyard | 2 | 130g + 60s + 6 planks | 50s | 2 gold | 30 |
| Dreadnought | sea | Shipyard | 3 | 320g + 160s + 60o + 10 beams | 110s | 5 gold | 75 |
| Fighter | air | Aerodrome | 3 | 200g + 60s + 6 fuel | 60s | 3 gold | 40 |
| Bomber | air | Aerodrome | 3 | 260g + 90s + 40o + 8 fuel | 80s | 4 gold | 50 |
| Airship | air | Aerodrome | 3 | 280g + 60s + 60o + 10 fuel | 90s | 4 gold | 55 |

- **Air and sea (1.1, `feat/aire-mar-reglas`, `docs/15-combat.md` §11):** ships only
  move on water/shore and planes fly over everything (`combat_domain_moves`); air and
  surface share a cell (two layers); land and sea hit planes only 1 square away and
  artillery never (`combat_domain_targets`; the fighter is the anti-air); the
  advantage table has a sea circle and air/sea crosses. Water exists only on coast
  missions (the Dock expedition and some bandit raids, era 2+, with enemy ships) and
  at home when your garrison has ships (`CombatManager.home_terrain()`); ships cannot
  launch to a mission without water. Each coastal fight brings ONE enemy ship in a
  body's slot (era 2 torpedo boat/gunboat, era 3 gunboat; no enemy dreadnought). The
  Final Audit's airships and fighter escort are coded but OFF
  (`final_audit_airships_last_wave` = 0, `final_audit_air_escort_fighters` = 0):
  measured, they broke the siege (docs/17 "Aire y mar"). Numbers: docs/16, docs/17.
  The Shipyard ghost turns itself to face the nearest water (`PlacementRules.FACES_WATER`)
  and the 2D view draws `rotation_steps` with the 3D convention (`Building2D.view_steps()`).

- **Upkeep:** every 90s (`army_upkeep_interval`; 30 s until the 1.1 final round), gold-only. If short, drains remaining gold to 0 and emits
  `army_upkeep_unpaid`. Sustained non-payment **deserts** units, the most expensive
  first (`ArmyManager._desert()` → `army_deserted`).
- **Defending the base** (Tithe, not the Final Audit): of the army units that fall,
  `combat_defense_return_share` (2/3, rounded in their favour; at least one dies)
  come back wounded instead of dying, cheapest die first
  (`CombatManager.defense_wounded()`, the hook for the 1.2 Infirmary; war report
  line "Vuelven heridos").
- **Campaign retries:** each defeat in the campaign mission that is due eases its
  enemy x0.95 (floor x0.80, `campaign_retry_ease` / `campaign_retry_floor`,
  `CampaignBook.fails`, saved); winning resets it. Same map. Kept after the damage
  roll (2026-10-25, measured in docs/16 "Azar del daño": with the roll alone, 5-33 %
  of the hard maps never fell in 4 tries) and now **visible** in MISIONES
  (`CombatManager.campaign_retry_ease_pct()`, "la Regencia ha perdido fuerza: −10 %").
- **Military Power** = sum of unit power. Combat consumes this army for real:
  `ArmyManager` stays the source of truth and `CombatManager` only debits the dead
  (`remove_units()`), so Power never lies while a column is out.
- EventBus signals: `unit_training_started`, `unit_trained`, `army_changed`,
  `army_upkeep_unpaid`, `unit_training_cancelled`, `army_deserted`.
- The Ejército and Misiones buttons of the bottom bar (BottomBar) stay locked (grey, padlock, reason on hold) until a military building (Barracks, Shipyard or Aerodrome) exists.
- Combat stats for these unit types are separate, in
  `GameConfig.combat_unit_stats` — see `docs/15-combat.md` §8.
- **The regiment (cosmetic only, 2026-10-14, `docs/15-combat.md` §12):** name, colour
  and emblem (the flag pieces open by rank; "" = same as the flag), a paint scheme
  (`GameConfig.REGIMENT_PAINTS`, opened by rank with the `paints` key of
  `rank_rewards`) and stars at 10/25/50 fights won (`regiment_star_wins`). Saved by
  `ArmyManager` as `"regiment"` inside `"army"` (old saves = default, cleared in
  `reset()`, idempotent load that does **not** clamp by rank: the army loads before the
  rank, so `get_regiment_look()` resolves locked pieces when drawing). Edited in the
  REGIMIENTO card at the top of the Cuartel list (`scripts/ui/RegimentCard.gd`);
  pure helpers and cached badge/paint textures in `scripts/ui/RegimentLook.gd`.
  Shown on our pieces in both 3D combat views (paint on the `team` surface through
  `scripts/combat_view/regiment_paint.gdshader`, one shared material per colour and
  paint; a badge sprite with emblem and stars beside the HP plate, one shared texture)
  and as the colour of our round mark on the 2D board (brass ring with stars).
  Nothing in `scripts/combat/` reads it. Signal `regiment_changed`.

### Combat (PVE) — full doc: `docs/15-combat.md`

Three layers, and the rule that holds them together: **the models never emit**.
Every mutating method in `scripts/combat/` returns an `Array` of event dicts; a
service drains it onto the `EventBus`; the UI only reads and calls.

- **Pure models** (`scripts/combat/`): `CombatUnit`, `CombatRules`, `Encounter`,
  `CombatAI`, `AutoResolver`, `Expedition`, `ExpeditionGenerator`, `FinalAudit`,
  `SortieBoard` (the sortie board, 2026-10-14), `CampaignBook`, `ThreatBoard` (coastal
  threats, 1.2).
  No nodes, no timers, no global `randf()` — every one is headless-testable.
- **Damage roll (2026-10-25, `feat/ritmo-colono`, docs/15 §3 "El daño y su azar"):**
  each hit rolls inside ±`combat_damage_spread` (0.12) of the expected damage
  (`CombatRules.damage()` is the centre the AI plans with; `damage_range()`,
  `rolled_damage(a, t, roll)`). The roll comes from the `Encounter`'s own seeded
  `rng` (`board_seed()` by default, `seed_rng()`; `CombatManager.fight_seed()` mixes
  in played time so a retry is another night): **same seed + same moves = same
  fight**. The preview shows the range ("8-11 de 75", "¡Cae!" / "¿Cae?").
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
  NotificationPanel holds its alerts (log at once; only one `danger` shows, small;
  milestones, eras and rank-ups are alerts too since 2026-10-18) and HelperPanel
  goes quiet (except the `encounter` tip); all resume on
  `EventBus.encounter_closed` (end of `CombatManager.end_encounter()`).

Three roads reach the same board: an expedition node (player picks the party in
`SkirmishPanel`, which calls `CombatManager.launch_expedition()`; a win pays loot),
the Tithe defence (`get_garrison()` + tower crews, a win pays nothing but the Tithe
goes uncollected), and a Final Audit wave (the siege garrison + tower crews, carried
wave to wave with its damage). When the Tithe lands while a board is already open,
`AutoResolver` plays the *same* `Encounter` with the AI on both sides — there is no
second combat formula anywhere — and `WarReportScreen` shows the result.

**La Visita (2026-10-25, `feat/ritmo-colono`, docs/15 §5):** only one Tax in
`storm_tithe_board_every` (3) goes to the board — the first real one and then every
third (`StormManager.is_visit_due()`, from `storms_survived`). The others are resolved
by the home troops with the same `auto_resolve_defense()` (`reason: "auto_tithe"`);
for `storm_tithe_choice_seconds` (12) StormManager offers **¡PELEAR!** (StormHUD
`FightTitheButton`, `fight_this_tithe()`, signal `tithe_choice_changed`), then
`resolve_tithe_auto()`. `WarReportScreen` paints one card: the fight, the Tax glued to
it and "la próxima Visita, dentro de N Impuestos" (`tithes_before_visit()`). The
era-1 trial Tax always goes to the board.

**The expedition runs end to end from the UI:** launch in `SkirmishPanel`, the node
map / draft / final report in `BattleScreen` (`select_node()`, `apply_draft()`,
`abandon_expedition()`), attrition and permadeath across nodes, units away are
locked out of the garrison, and a run in flight is saved and reopens its map on load
(`expedition_resumed`). `start_skirmish()` is no longer called from `scripts/` (only
tests use it); the dev-only test fight goes through `dev_start_encounter()`.

**Three campaigns (2026-10-18, branch `feat/tres-campanas`, docs/15 §13):**
Land (Barracks, era 1: 5 missions + boss), Sea (Shipyard, era 2: 4 + boss) and Air
(Aerodrome, era 3: 4 + boss) — Colono plays Land 4, Sea 2, Air 2 of them
(`GameConfig.campaign_mission_list()`; missions are always named by their **table
index**, `campaign_base_count()`; `CampaignBook.progress` is that index, so old saves
load as they were) — each a chain of short maps (1-3 fights) in a **pure
domain**: only that domain's units (the bomber cannot hit planes, so it stays home
from Air; `GameConfig.campaign_unit_allowed()`), enemies of the same domain, sea fights
on an all-water board with rocky islets (`CombatRules.open_sea_terrain`), air fights
over a coast. Model `CampaignBook` (pure, owned by CombatManager, save key
`campaigns`, reset in `CombatManager.reset()`); a mission is an offer
`{kind: "campaign", domain, mission, seed, era}` rebuilt by
`ExpeditionGenerator.campaign_mission_map()`; `CombatManager.launch_campaign_mission()`,
`campaign_lock_reason()`, `campaign_offer()`. Only the last fight pays (gold/wood,
steel at sea, oil in the air, parts, settlers on land, a Tithe cut; the boss more and a
blueprint if any); 150 s rest between missions; XP `campaign_mission` 60 / `campaign_boss`
250. UI: tabs TIERRA / MAR / AIRE / ATAQUES RÁPIDOS in SkirmishPanel (padlock + reason,
N/M, boss), the mission map painted sea or sky, `Objectives.campaign_step()` (second
line) and `campaign_gate_step()` (main step once HQ 3 is done). The short 3-fight
expedition of the sortie board became the Land campaign
(`combat_board_expeditions_enabled = false`); **mixed** missions (coast: land + ships,
pirates, the Dock) are future (`combat_mixed_missions_enabled = false`); their code and
tests stay (the tests turn the switch on). Tunables: `campaign_*`.

**Sorties (2026-10-14, branch `feat/escaramuzas`, docs/15 §4b, untested):** after the
first sortie, a board of offers (`SortieBoard`, owned by CombatManager, save key
`sorties`) holds one **raid** (1 fight: raiders → spare parts + settlers, or the Regency
outpost → spare parts + a Tithe discount through `StormManager.add_tithe_discount()` when
that function exists) and, from era 2, one **short expedition** (3 fights, 30 % heal
between them, boss pays parts, settlers and a blueprint). The whole map is rolled from
the offer, shown in `SkirmishPanel` before launching with loot and Favorable / Igualada /
Difícil; `launch_sortie()` launches it. Exclusive loot: `ResourceManager.Type.PARTS`
(material outside the bag; level 3 of producers asks for it, `upgrade_parts_cost`),
settlers (population up to housing), blueprints (`combat_blueprint_buildings`, hook
`CombatManager.blueprint_locked()` — PlacementRules still has to call it). The enemy
**routs** below `combat_retreat_ratio` (30 %) on column boards, never on defence;
"**resolver solo**" (`auto_resolve_current()`) only on raids and the Tithe with double
strength. HUD button `SkirmishButton` (slot `skirmish_button`, red dot from
`CombatManager.sortie_reason()`); ¿QUÉ HACER? shows the same reason as a second line
(`Objectives.sortie_step()`; `next_step()` unchanged). Tunables: `combat_raid_*`,
`combat_expedition_*`, `combat_loot_*`, `combat_sortie_*`, `combat_retreat_ratio`,
`combat_auto_resolve_ratio`, `combat_odds_*`. The old 6-8 node expedition
(`launch_expedition()`) is untouched.

**Coastal threats (1.2, branch `feat/amenazas-costa`, docs/15 §14, untested):**
OPTIONAL LOOT ONLY (Bryan, 2026-10-18). Raiders (on the beach, or in a boat on the
water once a Shipyard stands), the Regency vanguard (era 2+) and wrecks appear on the
shore every 150-270 played seconds (at most 2 at once, from the first Barracks + first
sortie won), are drawn on both maps (`ThreatMarks3D` under MapGenerator, one cached
vertex-colour mesh per type; `ThreatMarks2D` under MapGenerator2D, one `_draw`; nothing
per frame), last 240-360 s and **leave on their own, doing no harm**. Attacking one is a
single **pure-domain** fight (land troops on the shore, ships only on the water; offer
`{kind: "threat", threat_id, threat_type, seed, era, domain}`, map and loot rebuilt by
`ExpeditionGenerator.threat_map/threat_rewards/threat_loot`); a wreck is explored with
2 workers for 60 s, no fight. Loot: gold/wood (steel from the vanguard), spare parts
and sometimes a workshop material (`_apply_loot` now handles `planks/ingots/beams/fuel`).
Tapping a mark (both placers, only on a cell with no building/deposit) opens
`ThreatCard` (child of SkirmishPanel; a CartoonTheme side card on the right, no veil,
its content in a scroll): what it is, time left, enemies (discs), odds, loot,
¡AL ATAQUE! (opens MISIONES > ATAQUES RÁPIDOS with it picked: `SkirmishPanel.open_threat`)
or EXPLORAR. Threats are listed in ATAQUES RÁPIDOS next to the sortie raids
(`SkirmishPanel.raid_offers()`, the troop picker filtered by `pure_domain()`), wrecks
as EXPLORAR rows. One
`notice` per new mark; leaving/clearing go to the log. ¿QUÉ HACER? only gets the second
line (`THREAT_WHY_EASY`, last in `sortie_reason()`): an unseen mark with easy loot.
Model `ThreatBoard` (pure), service `ThreatManager`, save key `threats`, tunables
`threat_*` at the end of GameConfig, texts in Tr block "# Amenazas de costa".

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

**Teaching combat (2026-10-14, `docs/15-combat.md` §3 "Enseñar el combate", docs/23 §2.4):**
- *Previews*, pure functions added to `CombatRules`: `preview_damage()` (the hit you
  would deal, written over every target: "-18 de 75", "¡Cae!"), `threat_cells()` (where
  the enemy can move and shoot next turn: the **Ver alcance enemigo** toggle in
  `BattleScreen`, orange cells/spots), `min_range_cells()` (the artillery's ✕ next to
  it) and `fire_cells_from()`. Computed in `BattleScreen._refresh()` per combat event,
  never per frame; drawn by `Board3D.set_overlays()` (new `Mark` values at the end of
  the enum) in both 3D views and by the 2D cells.
- *Unit card* (`scripts/ui/UnitCard.gd`): health, attack, defence, move, range (min
  range for artillery), strong/weak against with multipliers, one phrase. Icons drawn,
  numbers read from `combat_unit_stats` / `combat_type_advantage` or from the live unit.
  Tap a piece on the board (any view) or FICHA in `ArmyPanel`.
- *Guided fights*: `TutorialManager` lessons `basics` (steps 1-5, first board of the
  game) and `artillery` (6-7, first board with our artillery), derived from combat
  signals by the pure `derive_combat_step()`; `EventBus.combat_lesson_step_changed`;
  `TutorialPanel` draws them where `BattleScreen.coach_anchor()` says. Saved as
  `combat_lessons_done` inside the `tutorial` key. No Skip on steps 1-3, Skip on 4-7,
  "Repetir combate guiado" in the AYUDA index. Six combat guides at the end of
  `HelpCatalog.ENTRIES`. The practice range (design doc 21 §4.4) is not done.

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
  EventBus signals (era music crossfade, build/trade/event SFX, combat, the Storm and
  the Tithe, the Final Audit, rank, collecting, UI clicks and toggles).
- Assets: **5 music tracks** (three eras, victory and an own `combat` theme, CC0),
  **47 SFX** and **4 ambient loops** in `assets/audio/{music,sfx,ambient}/`. **No aliases
  any more**: every key in `SFX_MANIFEST` has its own clip (combat, Storm, Tithe, rank,
  collect / harvest included). Gains per clip in `SFX_GAIN_DB`. Missing files are
  skipped silently — audio never crashes the game. Sources and licences:
  `assets/audio/MANIFEST.md`, `assets/CREDITS.md` and `THIRD-PARTY-NOTICES.md`.
- **Combat by unit type (1.1):** on `unit_attacked` / `unit_moved` / `unit_died` the
  unit is read from `CombatManager.get_unit(uid)` and its `unit_id` / `domain()` pick
  the clip (`ATTACK_SFX`, `MOVE_SFX`, `DEATH_SFX_BY_DOMAIN`, `IMPACT_SFX_BY_DOMAIN`):
  rifle, cannon, tank, propeller planes, airship, ship horn, torpedo, splash, sinking,
  crash. 13 mono 22 kHz OGG clips (140 KB) synthesised by `tools/gen_combat_audio.gd`.
  Infantry and artillery move silently; `combat_hit` is the fallback.
- **Ambience:** `day` (waves + birds), `night` (crickets + soft waves), `storm`
  (wind + rain + distant thunder) and `coast` (the board's shore: surf, breeze, gulls,
  while a board is open), 40 s OGG loops made by synthesis with
  `tools/gen_ambient_audio.gd` (own work). One plays at a time and they cross-fade
  (`AMBIENT_FADE_SECONDS` 4) following the Storm phase, `DayClock`
  (`day_phase_changed`) and the board (`encounter_started` / `encounter_closed`);
  Storm > board > night > day.
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
- `[ui]`: `grid_visible` (map grid toggle, off by default; GridOverlayControl applies it, BuildingPlacer
  restores it after placement, never in Minimal quality), `helper_visible` (help callouts, OFF by default since the 2026-10 redesign; Ayuda turns them on, the guided tutorial forces its own),
  `touch_controls` (`auto` / `always` / `never`; "auto" follows the device profile:
  tablet and phone yes, PC no — a touch on a touch laptop does not turn them on) and
  `touch_controls_opacity`, `instructors_visible` (the instructor busts, docs/23 §9), `view_mode` (`3d` / `2d`), `fullscreen`, `locale`;
- `[interfaz]`: `window_theme` (`dark` slate bunker windows, the default since the dieselpunk skin of 2026-10-25, / `light` sober paper; `CartoonTheme.window_theme`, `GameConfig.ui_theme`; the old `ui_theme` key of the cartoon skin is ignored and erased on save), device profile, UI scale, text size, palette, high contrast, panel
  opacity, hidden HUD elements, moved layout, `touch_controls_size` (size of the
  on-screen controls: `auto` = the profile's, PC 100 % / tablet 115 % / phone
  130 %, or `small` … `xlarge`; docs/21 §9), `fps_cap` (`auto` / `30`…`120` /
  `unlimited`: the FPS cap, 30 while paused and 10 without focus; "auto" is 30 on a
  PC in Minimal) — docs/21 §10; `graphics_quality` (`auto` / `high` / `low` /
  `minimal`) plus `quality_detected` / `quality_detected_reason` (the first-launch
  detection, once) — docs/21 §12, docs/26 §7; `combat_view` (`front` / `board`: how
  the 3D combat board is shown, docs/15 §3 "Las dos vistas");
- `[partidas]`: `activa` — which saved game is the active one (`GameConfig.saves_active_slot`);
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
- **Report:** ☰ → Informar de un fallo (small, at the foot of the menu) copies `BugReport.build()`
  (version, OS, GPU/renderer, profile, quality, view, locale, mode/tier, era, speed,
  last 40 log lines) to the clipboard. `BugReport.sanitize()` turns home-dir paths
  into `~` and the colony name into `<colonia>`.

### Performance — full doc: `docs/26-rendimiento.md`

Owner's priority since 2026-10-12: the game has to run "on a potato". Budget: 60 fps on
a mid PC, 30 fps on an old integrated GPU and on a cheap Android tablet (docs/26 §2).
Every new effect, mesh, sound or `_process` has to justify its cost.

- **Measure:** `tools/perf_probe.gd` (six seeded scenarios, CSV/JSON in `reports/perf/`,
  private user dir). The numbers in docs/26 §4 were taken **before** the optimisations
  below; nothing has been re-measured since.
- **Quality and FPS:** `GameConfig.ui_graphics_quality` `auto` / `high` / `low` /
  `minimal`. `WorldLook.settings_for()` decides the 3D cost (SSAO only in Forward+,
  glow, shadow cascades, MSAA, 3D resolution 0.7 on PC / 0.6 on mobile in Minimal, the
  simple island); `GraphicsQuality.apply_runtime()` the rest (smoke/sparks hidden, site
  pennants still, no always-on grid, walkers capped at `life_figure_cap_minimal`).
  Minimal on a PC writes `user://renderer_override.cfg` so the next launch runs the
  Mobile renderer. First launch with `auto` runs a detection (GPU name patterns, RAM,
  threads, then a few measured seconds behind the title menu). FPS cap per profile
  (`fps_cap`), 30 while paused, 10 without focus.
- **Done (2026-10-12/14):** roads in one `RoadBatch3D` (≤ 16 draw calls); building
  name labels created only when selected and no status badge on what does not work;
  shared materials for flags, lots, level trims and the 8 ash steps of a damaged
  building (`BuildingHealth`); deposits as one baked mesh each (`DepositMesh.gd`);
  baked 2D art (`ArtCache2D`) and no `_process` on 2D roads; auto-road placement in one
  batch (`placement_batch_started` / `placement_batch_finished`: one save and one
  recount per route); cached road network and Núcleo per `GridManager.map_version()`;
  panels that update instead of rebuilding (ConstructionMenu, TutorialPanel,
  ObjectivePanel, ResourceHUD, ArmyPanel, TechTreePanel); the 3D map is switched off
  (`disable_3d`) while the 3D combat board covers it.
- **Rules for new work:** one baked mesh per building or decoration with the shared
  `ToyPalette` materials; animation by shader (`TIME`), not `_process`; no real lights
  (night glow is emission); area effects computed on build/demolish, never per frame.

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
  (`GameManager.open_saves_list()`, from the title menu "PARTIDAS n/5" and from ☰ → PARTIDAS) has Load and Delete
  (confirmed); `load_slot()`, `delete_slot()`, `leave_deleted_slot()` (the in-memory game was deleted: open the most
  recent or a new one). `clear_save()` discards only the active slot (the reused fresh island, tests)
- Saves (top-level keys written by `GameManager._write_save()`): `resources`, `buildings` (level, name, construction state, health), `deposits`, `camera`, `progression` (eras, milestones, played time, the `final_audit` and the closed `chapters`), `market`, `unlocked_resources`, `population`, `random_events`, `active_processes`, `stockpiles` (what waits in each building, Farm crops, production clocks), `tech_tree`, `army`, `expedition` (CombatManager: the run in flight, with `kind`/`offer`/`loot` for sorties), `sorties` (CombatManager: the sortie board, blueprints, Tithe-discount note), `campaigns` (CombatManager: the three campaigns, `CampaignBook`; a save without it = none started), `storm` (StormCycle + armed/halted/trial; since 1.1 also the Regency Order: `tithe_discounts`, `order`, `calm_total`, `barometer_offset`), `tutorial` (also `combat_lessons_done`), `day` (DayClock: the hour, 0-1; frozen while the game is closed), `rank` (RankManager: XP and the country, `colony`: name + flag recipe), `contracts` (ContractManager: the board, docs/27), `economy` (EconomyManager: the smuggler's ship with its offers and dice, bought blueprints, fuel and interest clocks), `threats` (ThreatManager: coastal threats, `ThreatBoard`; a save without it = empty shore), `empire` (EmpireManager: the archipelago after victory, `Archipelago`; a save without it = nothing started, and a save with the Audit already won starts the phase on load), `game_mode`, `grid` (width, height, island seed; restored before anything is placed). Same save for the 3D and 2D views
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
+-- project.godot                    # Engine config (version 1.0.0), 32 autoloads (31 game + BeckettRuntime), renderer override hook
+-- export_presets.cfg               # Windows Desktop, Android, Android QA (emulador) — no secrets
+-- LICENSE, THIRD-PARTY-NOTICES.md, licenses/  # Licence, third-party notices, the engine's copyright text
+-- CLAUDE.md                        # THIS FILE - AI guidance
+-- readme.md                        # Game overview (Spanish, public)
+-- docs/                            # Per-system deep docs 01-26 (INDEX.md); media/ = screenshots
+-- specs/001-combate-pve/           # Spec, plan and tasks for the combat pillar
+-- .specify/memory/constitution.md  # Non-negotiable project rules (Spec-Driven Development)
+-- qa/maestro/                      # Maestro flows for the Android tablet emulator (QA APK, coordinates + screenshots)
|   +-- 01_...08_*.yaml              # One regression flow per tablet bug (README.md explains how to run them)
|   +-- comun/                       # Shared sub-flows: start, new game, skip lore, wait
|   +-- herramientas/                # Python helpers to collect and compare screenshots
+-- tests/                           # gdUnit4, 239 suites: audio/ build/ buildings/ combat/ economy/ input/
|                                    #   integration/ map/ modes/ save/ storm/ support/ tutorial/ ui/ view2d/
|   +-- save/save_parking.gd         # Parks the real save during a suite; refuses the player's dir
|   +-- save/settings_parking.gd     # Same for settings.cfg and GameConfig's UI fields
+-- scenes/
|   +-- main/Main.tscn               # Entry scene (3D); ViewRouter may hand over to Main2D
|   +-- main/Main2D.tscn             # The 2D view: same UI nodes, 2D world nodes
|   +-- buildings/BuildingPlacer.tscn
|   +-- combat/Board3D.tscn          # The 3D combat diorama (camera, sun, terrain, marks, units, fx)
|   +-- ui/                          # One .tscn per panel (29), incl. PrologueScreen and HelpIndexPanel
+-- scripts/                         # 211 .gd files, ~102k lines
|   +-- buildings/
|   |   +-- BuildingData.gd          # Resource class for building definitions (get_display_name())
|   |   +-- BuildingPlacer.gd        # 3D placement/move/demolish + mesh spawning
|   |   +-- PlacementRules.gd        # Shared placement rules for 3D and 2D: deposit adjacency, footprint, road network and auto-road, upgrade effects
|   |   +-- PlacementAssist.gd       # Touch placement (tap aims, tap ghost/✓ builds), valid-spot highlight — docs/21 §9
|   |   +-- BuildingStatusBadge.gd   # Worker pictogram / "Zzz" + why a building is stopped (3D)
|   |   +-- ColonyFlag3D.gd          # The country flag on the Nucleo and Barracks masts (shader wave, FlagAnchor)
|   |   +-- BuildingLook.gd          # Rule (both views): construction phase / upgrade / ruin / active / idle; site style per type + seeded layout per instance
|   |   +-- BuildingLookVisual.gd    # Applies it in 3D (child "LookVisual"); BuildingPlacer syncs it with one map-wide clock
|   |   +-- BuildingFx.gd            # Generated smoke/dust/glow/sparks sprite sheets (8 frames, 4x2) + TIME shaders, 3D and 2D
|   |   +-- SiteFx.gd                # Construction-site animation by shader (crane swing, hook, pennant), 3D and 2D
|   |   +-- DieselpunkBuildingFactory.gd  # Procedural 3D meshes: decorations via DecorMesh and the road meshes (fallback when there is no model_scene)
|   |   +-- LotPlan.gd, BuildingLot.gd, LotMesh.gd  # The lot: rule (both views), 3D node, one-mesh builder
|   |   +-- ToyPalette.gd, ToyTones.gd # The shared toy palette and its two map-wide materials (solid, glow)
|   |   +-- RoadBatch3D.gd           # Every 3D road as a MultiMesh per neighbour mask
|   |   +-- LevelTrim.gd             # Level pieces of an upgraded building: plinth, chimneys / lamps (II / III)
|   |   +-- FarmCrops3D.gd, StockIcon3D.gd, SiteMesh.gd  # The Farm's beds (toy_crops shader), collect icon, construction-site mesh
|   |   +-- DecorMesh.gd             # The 10 cheap decorations: one shared mesh per type (baked if present, procedural otherwise)
|   |   +-- DecorMesh2.gd            # The other 18 decorations (procedural; DecorMesh serves them)
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
|   |   +-- regiment_paint.gdshader  # The regiment's paint on our pieces' team surface (cosmetic)
|   |   +-- FrontOrders.gd           # Front view orders (approach cell, reachable targets, AVANZAR) -> the same move/attack calls
|   +-- grid/
|   |   +-- GridManager.gd           # Cell grid (size per game, saved), land mask, map_version()
|   |   +-- GridOverlayControl.gd    # Applies the grid toggle to the 3D overlay
|   +-- map/
|   |   +-- IslandGenerator.gd       # Procedural island mesh (coast, cliff, sand, foam, sea)
|   |   +-- IslandShape.gd           # Pure: the land mask and coast polygon from the seed and `island_coast`
|   |   +-- WorldLook.gd             # WorldEnvironment script: what each graphics quality costs
|   |   +-- DepositMesh.gd           # Deposits as one baked toy mesh per type, size, variant and depletion stage
|   |   +-- MapGenerator.gd          # Random deposits: 3-6 per type, room and a road path for each extractor
|   |   +-- WorkerWalkers.gd         # Workers and citizens walking the road network (view only, 3D and 2D)
|   |   +-- RoadTraffic.gd, TruckActor.gd, TrafficFigures3D.gd  # Trucks from extractors to the warehouse (view only; 2D: view2d/TrafficFigures2D.gd)
|   |   +-- WalkerActor.gd, WalkerFigures3D.gd  # One figure's data; the 3D MultiMesh drawer (2D: view2d/WalkerFigures2D.gd)
|   |   +-- StormSky.gd              # Autoload: sky/light of the time of day and the storm
|   +-- storm/StormCycle.gd          # PURE model: the storm's phase clock
|   +-- economy/ContractBoard.gd     # PURE model: the contract board (3 slots, clocks, rewards, reputation)
|   +-- economy/SmugglerShip.gd      # PURE model: the smuggler's ship of the Trade port (clock, 3 offers, own RNG; 1.2)
|   +-- empire/                      # PURE models of Volverse el Imperio: Archipelago.gd (islands, progress, tribute) and ConquestGenerator.gd (conquest missions)
|   +-- storm/DayCycle.gd            # PURE model: the day/night clock (DayClock ticks it)
|   +-- services/                    # The 31 game autoloads (table above) + BeckettGate.gd
|   |   +-- ...Manager.gd / EventBus.gd / GameConfig.gd / Tr.gd / DeviceProfile.gd
|   |   +-- GameMode.gd              # Static: the mode of this run and its rules
|   |   +-- Objectives.gd            # Static: the next step for ¿QUÉ HACER?
|   |   +-- Chapters.gd              # Static: the three chapters of the Campaign (docs/06 §Capítulos)
|   |   +-- GraphicsQuality.gd       # Static (preload): set_quality(), what Minimal turns off outside WorldLook, renderer override, detection rules
|   |   +-- SaveSlots.gd             # Static (preload): user://partidas/, the index, up to 5 games
|   |   +-- ColonyIdentity.gd        # Static: country flag pieces by rank, random names/flags, word filter
|   |   +-- FloatingText.gd          # Static utility: animated 3D text labels
|   |   +-- ErrorLog.gd, BugReport.gd  # Local error log (Logger, rotated) and the "Informar de un fallo" text
|   +-- ui/                          # 50 scripts: one per panel, plus
|   |   +-- UITheme.gd               # Static dieselpunk theme: tokens, fonts, styleboxes, unit icons
|   |   +-- UILayoutConfig.gd        # Screen slots, panel->slot map, conflicts
|   |   +-- HudRegistry.gd, LayoutEditor.gd        # Hideable/movable HUD elements, the layout editor
|   |   +-- ModalKit.gd              # Builds the war-report / dialog cards from UITheme pieces
|   |   +-- PauseMenu.gd, TitleMenu.gd, NewGameDialog.gd, PauseWatcher.gd
|   |   +-- BattleScreen.gd, SkirmishPanel.gd, WarReportScreen.gd, AuditWaveBanner.gd, AuditDefeatScreen.gd
|   |   +-- InstructorBust.gd           # The two instructors (Capt. Remache: colony, Sgt. Bombarda: combat), code-drawn busts beside tutorial/tip/war-report cards (docs/23 §9)
|   |   +-- TutorialPanel.gd, CoachArrow.gd, PrologueScreen.gd, RegenciaSeal.gd, QuickGuide.gd, DragScroll.gd, TouchTooltip.gd
|   |   +-- HelperPanel.gd, HelpCallout.gd, HelpCatalog.gd, HelpTargets.gd, HelpIndexPanel.gd
|   |   +-- CartoonPicker.gd         # The redesign's selector (pills or ◀ option ▶), replaces dropdowns in Settings (docs/28 §15)
|   |   +-- RankPanel.gd, ColonyFlag.gd  # Governor rank badge/toast/COLONIA card; the flag drawn from pieces
|   |   +-- RegimentCard.gd, RegimentLook.gd  # The REGIMIENTO card in the Cuartel; regiment look, badge and paint helpers (cosmetic)
|   |   +-- ColonyIdentityPanel.gd, ColonyByline.gd  # Country name + flag editor; flag + name line on reports
|   |   +-- SandboxPanel.gd, SettingsPanel.gd, StormHUD.gd, ObjectivePanel.gd, ArmyPanel.gd, TechTreePanel.gd
|   |   +-- ChapterScreen.gd         # The short chapter-closing card (created by ObjectivePanel)
|   |   +-- BuildingInfoPanel.gd, ConstructionMenu.gd, MarketPanel.gd, NotificationPanel.gd,
|   |   +-- OnScreenControls.gd, ProcessActionsPanel.gd (+ ProcessCard.gd), ProgressPanel.gd, ResourceHUD.gd, VictoryScreen.gd
|   |   +-- HarvestSection.gd, SavesPanel.gd, GameSpeedButton.gd, TextKit.gd  # RECOGER, PARTIDAS list, x1/x2, icon+number rows
|   +-- view2d/                      # The 2D view (docs/18): same services, flat world
|       +-- ViewRouter.gd, ViewMode.gd, View2D.gd  # Scene routing, the view preference, world<->pixel maths
|       +-- Camera2DController.gd, Island2D.gd, GridOverlay2D.gd, StormTint2D.gd
|       +-- BuildingPlacer2D.gd, MapGenerator2D.gd, Building2D.gd (no `_process` of its own: `Building2DClock.gd` checks one slice of the buildings per frame, a round every 0.4 s), BuildingArt2D.gd, BuildingIcon2D.gd
|       +-- Deposit2D.gd, StatusBadge2D.gd, FloatingText2D.gd, ColonyFlag2D.gd, StockIcon2D.gd
|       +-- ArtCache2D.gd, WalkerFigures2D.gd  # Baked 2D drawings (one textured rect per building); the 2D walkers
+-- data/buildings/                  # 55 .tres building definitions
+-- assets/
|   +-- audio/{music,sfx,ambient}/   # 5 tracks, 47 SFX, 4 ambient loops (see MANIFEST.md)
|   +-- models/toy/                  # Baked toy buildings (<id>.tscn + <id>_mesh.res, toy_solid / toy_glow materials)
|   +-- models/toy/units/            # Baked combat toys (<id>_player / <id>_regency, boss_mark, crew_nest)
|   +-- models/cc0/                  # CC0 source pieces (KayKit, Kenney) the bakers read; each pack has a .gdignore, so Godot never imports or exports it
|   +-- models/buildings/<id>/       # The old GLBs: unused, excluded from the export
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
    +-- build_toy_models.gd, toy_kit.gd, toy_recipes/  # Bakes the toy buildings; `-- --units` the combat toys (toy_recipes/units/)
    +-- gen_ambient_audio.gd         # Synthesises the four ambient loops (+ storm siren and thunder)
    +-- gen_combat_audio.gd          # Synthesises the 13 combat sounds by unit type (mono OGG source WAVs)
    +-- perf_probe.gd, perf_probe_runner.gd  # The performance probe (docs/26)
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

Building 3D meshes: `BuildingPlacer._create_building_mesh()` instantiates a building's
`model_scene` when it has one and falls back to `DieselpunkBuildingFactory` when it is
unset:

| Source | Buildings |
|---|---|
| Baked toy model (`model_scene` = `assets/models/toy/<id>.tscn`) | `nucleo`, `house`, `sawmill`, `farm`, `gold_mine`, `warehouse`, `market`, `laboratory`, `foundry`, `barracks`, `refinery`, `tower`, `headquarters`, `garden`, `fountain`, `statue`, `fishing_dock`, `shipyard`, `aerodrome` (19). The Farm adds its beds as a separate mesh (`Crops`, `FarmCrops3D`) animated by the shared `toy_crops.gdshader` |
| `EconomyToys` (through `DieselpunkBuildingFactory.create()`) | `trade_port`, `exchange`, `diesel_plant` (1.2): their bake `assets/models/toy/<id>.tscn` (baked 2026-10-18; no `model_scene` in the `.tres`), the shared procedural mesh if it is missing. Also the smuggler's ship (`ship_mesh()`) |
| `DecorMesh` (through `DieselpunkBuildingFactory.create()`) | the 28 decorations (the 10 cheap ones and the 18 of `DecorMesh2`): one shared mesh per type, baked `assets/models/toy/<id>_mesh.res` (all baked), procedural (LotMesh boxes, cylinders, balls) as the fallback |
| `RoadBatch3D` | `road`: the node carries no mesh; the batch draws every tile with `DieselpunkBuildingFactory.road_mesh()` per neighbour mask |

The toy models are baked offline by `tools/build_toy_models.gd` from the recipes in
`tools/toy_recipes/<id>.gd`: CC0 pieces (KayKit, Kenney, `assets/models/cc0/`, source
only) recoloured to the shared `ToyPalette` plus own pieces, merged by `LotMesh` into one
vertex-coloured mesh with a solid and (if something glows) a glow surface; the whole
map shares two materials (`toy_solid.tres`, `toy_glow.tres`, plus `toy_crops.tres` for
the Farm's beds). Each model is baked to the rectangle its lot leaves
(`LotPlan.model_rect`), centre at the origin, base at y = 0, facing +Z, and may carry a
`FxAnchor` (smoke) or `FlagAnchor` (colony flag) marker. The game only loads what is
baked. The old GLBs stay in `assets/models/buildings/`, unused and excluded from the
export. Full detail: docs/03 "Modelos: maqueta de juguete".

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

### Player-facing words (2026-10-16)

The game is for 10-15 year olds. Every text the player reads follows the vocabulary
table in `docs/23-onboarding.md` §7: Cobradores / Collectors (not Tasadores), Impuesto /
Tax (not Diezmo), Ataque Final / Final Assault (not Auditoría), Olvidados / Forgotten,
Misiones / Missions (not Escaramuzas), Casa, Almacén, Tanque, tropas en casa (not
guarnición), cañoneros (not dotación). Code identifiers (`tithe`, `audit`, `garrison`,
`skirmish`) keep their names; only the values in `Tr.gd` changed.

### Key Rule: GDScript first (decided 2026-09-12)

- **GDScript for everything**, combat included. The whole project (31 game autoloads + all UI) is GDScript; a second language adds build times, cross-runtime debugging and marshalling for no benefit here.
- The old plan put unit AI, combat math and pathfinding in C# **for performance**. That argument does not apply at the agreed combat scale: an 8x8 board with 4–6 units per side. GDScript is orders of magnitude more than enough.
- **Migrate later, only on evidence**: if a profiled module proves too slow, port that module to C#. Do not create the .NET project speculatively.

### Adding a New Building

1. Create `data/buildings/my_building.tres` with BuildingData fields (at least 2x2: only the
   road is 1x1; materials go in `cost_materials`). It will need a road to the Núcleo like
   everything else
2. Add its cap: a row in `GameConfig.building_limits_by_era` if it rises with the era, or in `GameConfig.building_limits` if fixed. A decoration (`is_decoration`) needs neither: it has no cap
3. Add prerequisites in `GameConfig.building_prerequisites` (if any)
4. Add processes in `GameConfig.building_processes` (if any), and a row in `GameConfig.building_deposit_rules` if it must touch a deposit
5. Give it a look in both views: a baked toy model for 3D (a recipe in `tools/toy_recipes/<id>.gd`, baked with `tools/build_toy_models.gd -- --only=<id>` into `assets/models/toy/<id>.tscn`, set as `model_scene`; only CC0 or own pieces, and new CC0 packs listed in `THIRD-PARTY-NOTICES.md`) or, failing that, a case in `DieselpunkBuildingFactory`, and a drawing in `scripts/view2d/BuildingArt2D.gd` for 2D (map, ghost and menu icon share it); and a row in `GameConfig.construction_style` so its construction site has its own materials, fence, tarp and phase-2 silhouette (docs/03, "Obra por edificio y por instancia"; without one it uses `construction_style_default`). Give it a lot in `GameConfig.building_lot_style` (ground, trim, yard, props and a `signature` if the model lacks an exaggerated element) — docs/03 "Parcela y atrezo"
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
- `decor_rank_unlocks` / `decor_deed_unlocks` / `decor_shore_only` - the other 18 decorations (rank, deed, coast); `traffic_*` - the trucks (end of the file, `_register_decorations_traffic()`)
- `empire_islands` / `empire_tier_enemy` / `empire_boss_extra_scale` / `empire_tribute_interval` / `empire_mission_cooldown` / `empire_reward_mult` / `empire_titles` - Volverse el Imperio (the archipelago after victory; block at the end of GameConfig, unmeasured)
- `REGIMENT_PAINTS` / `regiment_star_wins` - the regiment's paints and stars (cosmetic only)
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
- `contract_*` - the contract board: source eras, first delays, cooldown, era scaling, reputation, Tithe fallback gold, rank XP, templates (docs/27)
- `game_mode_rules` / `sandbox_*` - per-mode rules and multipliers on top of the base
  values (modes apply factors; the balance line changes the base values — docs/20, docs/22)
- `game_tier_rules` - Colono / Gobernador: market, spoilage, harder enemy and, since
  `feat/ritmo-colono`, `campaign_missions` (which campaign missions each tier plays)
  and `hq_material_mult` (HQ workshop materials) — the 3-4 h / 6-8 h pace (docs/22 §17)
- `combat_damage_spread` - the damage roll (±12 %; 0 = fixed damage); `campaign_retry_*` - the visible ease per defeat
- `storm_tithe_board_every` / `storm_tithe_choice_seconds` - la Visita: one Tax in N on the board, the ¡PELEAR! window
- `population_floor` / `population_regrow_floor` - the ruin floor
- `autosave_interval` / `autosave_debounce` / `max_offline_seconds` - saving and offline

### Shared Utilities

- **FloatingText** (`scripts/services/FloatingText.gd`): Static class for spawning animated 3D text labels. Use `FloatingText.spawn()` for custom text or `FloatingText.spawn_resource()` for resource gain/loss display (`spawn_on()` / `spawn_resource_on()` work on any node, 2D included; the 2D view draws them with `FloatingText2D`). Colors come from `GameConfig.resource_colors`.
- **DieselpunkBuildingFactory** (`scripts/buildings/DieselpunkBuildingFactory.gd`): Static factory generating dieselpunk building meshes from primitives (rivets, pipes, brass/rust palette, shared PBR metal maps). `create(building_id, cell_size, grid_size)` and connectivity-aware `create_road(cell_size, neighbors)`. Called by BuildingPlacer and the ConstructionMenu thumbnails **as the fallback when a building has no `model_scene`** — today only the 10 cheap decorations, which it hands to `DecorMesh` — and by `RoadBatch3D` for the road meshes (`road_mesh()`).
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
`estrategia/`, `ui_tour/`, `build/`, `assets/models/buildings/` and `*.md`. `tests/build/test_export_guards.gd`
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

**In progress for the 1.0 (2026-10-14): phase 1 of the loop redesign.** After playing,
the owner found the loop hard to follow, skirmishes optional, long and random, the
units unexplained and the building limits too tight. Already landed from phase 1:
limits by era and uncapped decorations (`feat/topes-por-era`), the ten cheap
decorations (`feat/decoraciones-1`, their CC0 bakes still pending) and the finishing
"pop", rewarding collect and closer start camera (`feat/salto-y-camara`). Still to
come (do not document as shipped until it lands): a visible ESCARAMUZAS button and
¿QUÉ HACER? asking to go out when there is a reason; short expeditions (a 1-fight raid,
a 3-fight expedition) with map, enemies and loot shown before launching, and loot only
found outside (blueprints, spare parts, settlers, a cheaper Tithe); the enemy
withdrawing when it is lost (not in the siege) and "resolve alone" only with double
strength; a guided first fight and unit cards with damage previews and enemy reach.

Still not there:

- **Cloud save wiring:** `CloudSaveManager` exists but needs credentials (the export
  excludes `.env`, so they would have to come from `user://` or the build) and a UI
- **Tower behaviour beyond the boards:** towers mitigate storm damage and field crews
  on defensive boards; they have no attack of their own on the base map
- **Gameplay at night:** the day/night cycle is light, walkers and sound only
- **Re-measuring:** the balance line (docs/22) predates roads, materials, food and the
  irregular island, and the performance numbers (docs/26 §4) predate the
  optimisations; both need a new probe run
- **Open balance decisions** listed in `docs/22-linea-jugable.md` §7 and
  `docs/13-roadmap.md`
- **Distribution:** Windows code signing (SmartScreen), Android release keystore, AAB
  and store listing
- **Out of scope for v1:** PvP and co-op
