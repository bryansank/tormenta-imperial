# Roadmap

Development roadmap for Tormenta Imperial: what is done, what is still open, and in
which order things were built.
Status legend: ✅ done · 🚧 in progress · ⬜ planned · 💤 backlog / nice-to-have · ❓ open decision

> **Version 1.0.0 is being assembled** on the `integracion/arte-v1` branch
> (`project.godot` `config/version="1.0.0"`). The game is playable from the first
> sawmill to the victory, in 3D and 2D, on PC and on an Android tablet build. Between
> 2026-10-11 and 2026-10-14 some 25 branches landed on top of the playable game: the
> "toy diorama" art, the irregular island, food and the Farm, collected production,
> day and night, sound for everything, several saved games, the country and its flag,
> the front view of combat, game speed, graphics quality down to "Mínima" and a round
> of performance work. **Phase 1 of the loop redesign** (below) has started landing
> too (limits by era, ten cheap decorations, the finishing "pop" and the camera); the
> rest of it goes into the 1.0, then a playtest and the release.
>
> This file describes the state of `integracion/arte-v1` as merged into the
> `docs/puesta-al-dia-1.0` branch on 2026-10-14. Branches that were still open then are
> listed under "In progress", not as done.

---

## ✅ Shipped

### Core

- ✅ Grid building placement (**60-74 cells a side, rolled per game**, an irregular
  island with the sea inside the grid), 27 building types (all 2x2 but the Núcleo and
  the road; 14 of them decorations, the road included), caps per type that rise with the era, rotation, move, demolish; extractors must touch their deposit
  (`GameConfig.building_deposit_rules`)
- ✅ Random map: 3-6 deposits of each type on land, each with room and a road path for
  its extractor; island shape from a saved seed
- ✅ Road network joined to the Núcleo, auto-road when placing, "no road, no work",
  workers walking the roads (and going home at night and during the Storm)
- ✅ 5 resources in one shared pool (gold, wood, food, steel, oil) + 3-era unlock;
  4 workshop materials outside the pool (planks, ingots, beams, fuel) asked for by the
  advanced buildings
- ✅ Production that waits in each building up to a cap and is collected with a tap;
  full, the building stops (nothing is thrown away); spoilage only in Gobernador
- ✅ Manual processes and hand mining in batches (×1 / ×5 / MÁX); the Núcleo runs every
  unlocked workshop recipe and hand mining, 1.5x slower
- ✅ Market and Laboratory as buildings: trade and research open from them
- ✅ Population / workers (really assigned, and the player can take them off a
  building) / morale / food consumption, famine and the ruin floor
- ✅ Internal market with floating prices (food included)
- ✅ 8 random events (from the SURVIVAL phase, per mode)
- ✅ 9 milestones; the capstone summons the Final Audit (Campaña) or wins (Constructor)
- ✅ Tech tree (15 techs, 3 branches; storage techs +1000)
- ✅ Save/load with autosave, up to five saved games, fight checkpoints, corrupt-save
  backup and silent offline progression — [09-save-system.md](09-save-system.md)
- ✅ Audio: `AudioManager` (runtime buses, signal-driven, music on/off) with 5 music
  tracks, 47 SFX and 4 ambient loops, no aliases left; combat sounds by unit type (land, sea, air) and a coast loop on the board (1.1)
- ✅ i18n ES/EN with a language selector (reload keeping the game)

### Milestones

| Milestone | Status | Doc |
|---|---|---|
| M1 — Economic floor | ✅ | this file, below |
| M2 — The storm bites | ✅ | this file, below |
| M3 — Expedition & the double clock | ✅ | [15-combat.md](15-combat.md) §4 |
| M4 — The Final Audit | ✅ | [15-combat.md](15-combat.md) §6, [17-balance-asedio.md](17-balance-asedio.md) |

### The 1.0 round (2026-10-11 to 2026-10-14)

| Item | Status | Where it lives |
|---|---|---|
| **Toy diorama look**: 16 buildings are baked models (CC0 KayKit / Kenney pieces recoloured to one ten-colour `ToyPalette`, one vertex-coloured mesh each, two materials for the whole map; the Farm adds its beds growing by shader, `toy_crops`) and the ten new decorations share one procedural mesh per type until they are baked; every building on its own lot with ground, kerb and props and a dark contact edge; the Núcleo as a tall monument with its own flag mast (also in 2D); upgraded buildings grow and carry a brass trim per level (also in 2D); the road is drawn in one batch | ✅ | `tools/build_toy_models.gd`, `tools/toy_recipes/`, `assets/models/toy/`, `LotPlan` / `BuildingLot` / `LotMesh`, `LevelTrim`, [03-buildings.md](03-buildings.md) "Modelos: maqueta de juguete" |
| **World look**: warm sky and sun, island cliff / sand / foam / sea shaders, deposits as toy miniatures that change as they are mined, the same in 2D with baked drawings | ✅ | `WorldLook`, `IslandGenerator`, `DepositMesh`, `ArtCache2D`, [02-economy.md](02-economy.md), [21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md) §12 |
| **Irregular island**: 60-74 grid, 2-4 bays and 1-3 capes from the seed, sea inside the grid, land kept around the Núcleo; old saves keep their square island | ✅ | `IslandShape`, `GameConfig.island_coast`, [02-economy.md](02-economy.md) "The irregular island" |
| **Food, the Farm and collecting**: people eat food (not wood and gold); the Farm with 1 / 5 / 20 min crops; production waits in the buildings and is collected with a tap; spoilage after 2 h only in Gobernador | ✅ | `ProductionManager`, `HarvestSection`, `StockIcon3D` / `StockIcon2D`, [02-economy.md](02-economy.md), [04-population-morale.md](04-population-morale.md) |
| **Batches and the Núcleo as every workshop**: ×1 / ×5 / MÁX on every process and hand mining; the Núcleo offers every unlocked recipe, slower; the quick guide no longer opens by itself | ✅ | `ProcessManager`, `ProcessCard`, [02-economy.md](02-economy.md) "Lotes" |
| **Day and night**: a 16-minute cycle (night 3 min) that tints the light, sends people home and changes the ambience; no gameplay rule yet | ✅ | `DayClock`, `DayCycle`, `StormSky`, [21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md) §12 |
| **Sound for everything**: own clips for combat, the Storm, the Tithe, rank, collecting and UI; an own combat theme; day, night and Storm ambience | ✅ | `AudioManager`, `assets/audio/MANIFEST.md` |
| **Several saved games**: up to five, one file each in `user://partidas/`, a saved-games list, "Nueva partida" never deletes, the legacy save migrated | ✅ | `SaveSlots`, `SavesPanel`, `GameManager`, [09-save-system.md](09-save-system.md) |
| **The country and its flag**: a name and a flag built from pieces (patterns, emblems, colours unlocked by rank), picked when starting a game or later; it flies on the Núcleo and the HQ and signs the reports | ✅ | `ColonyIdentity`, `ColonyIdentityPanel`, `ColonyFlag`, `RankManager`, [06-progression-victory.md](06-progression-victory.md) |
| **Combat in 3D**: the board as a diorama with baked toy units in the colony colour; the **front view** by default (both sides face to face, no grid in sight) and the 8x8 board as the alternative; type advantage artillery > vehicle > infantry > artillery (×1.5 / ×0.75); colony notices held during a fight | ✅ | `scripts/combat_view/`, `scenes/combat/Board3D.tscn`, `combat_type_advantage`, [15-combat.md](15-combat.md) §3, [16-balance-combate.md](16-balance-combate.md), [17-balance-asedio.md](17-balance-asedio.md) |
| **Game speed and bug reports**: x1 / x2 (button or F) on the simulation only; a local error log and "Informar de un fallo" that copies a sanitised report | ✅ | `GameConfig.sim_delta()`, `GameSpeedButton`, `ErrorLog`, `BugReport`, [21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md) §13 |
| **Performance**: measured and audited first; then an FPS cap per profile (lower while paused or unfocused), the "Mínima" quality with first-launch detection and the Mobile renderer on weak PCs, roads in one batch, fewer labels and shared materials, baked 2D art, auto-road in one batch, cached road network, panels that update instead of rebuilding. Not re-measured after the optimisations | ✅ | `tools/perf_probe.gd`, `GraphicsQuality`, `DeviceProfile`, `RoadBatch3D`, [26-rendimiento.md](26-rendimiento.md) |
| **Helps for what is new**: one-time tips and AYUDA entries for saved games, speed, rank, flag and country, bug reports, day and night, the Farm, collecting and the irregular island | ✅ | `TutorialManager`, `HelperPanel`, `HelpCatalog`, [23-onboarding.md](23-onboarding.md) |
| **Distribution notes**: free, direct downloads from GitHub Releases, no stores or itch.io for now; LEEME files for testers | ✅ | [19-exportar.md](19-exportar.md) §8, `tools/dist/` |

### Around the core (before the 1.0 round)

| Item | Status | Where it lives |
|---|---|---|
| **2D view**: flat top-down world on the same services, UI and save; switch in Settings or `-- --view=2d` | ✅ | `scenes/main/Main2D.tscn`, `scripts/view2d/`, [18-vista-2d.md](18-vista-2d.md) |
| **Game modes**: Campaña, Constructor, Supervivencia, Sandbox, picked in the New Game dialog and saved with the run. Since 2026-09-28 the dialog only offers Campaña (`GameMode.OFFERED`); the other three are set aside, not deleted | ✅ | `scripts/services/GameMode.gd`, `GameConfig.game_mode_rules`, `NewGameDialog`, `SandboxPanel`, [20-modos-de-juego.md](20-modos-de-juego.md) |
| **Configurable UI and devices**: PC / tablet / phone profiles, UI scale and text size, `aspect=expand`, Settings in tabs, show/hide HUD elements, movable panels per profile, colour-blind palettes, high contrast, panel opacity | ✅ | `DeviceProfile`, `HudRegistry`, `LayoutEditor`, `UITheme.configure()`, [21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md) |
| **One game menu**: ☰ MENÚ (COLONIA + PARTIDA, real pause, ESC / Android back) and the title menu | ✅ | `PauseMenu`, `TitleMenu`, [08-ui-systems.md](08-ui-systems.md) |
| **Tablet / touch**: one-finger grab-pan with the same maths as the mouse, pinch zoom, two-finger twist, tap-to-aim and tap-to-build placement with valid spots, finger-sized controls, hold-to-repeat, hold-to-read tooltips, help texts per input | ✅ | `InputService`, `PlacementAssist`, `OnScreenControls`, `TouchTooltip`, `Tr.ti()`, [21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md) §9 |
| **Onboarding**: the prologue in three folios and plain language, a guided coach-mark tutorial on the real UI, help callouts one at a time, the AYUDA index (the quick guide lives there since 2026-10-14) | ✅ | `PrologueScreen`, `QuickGuide`, `TutorialPanel`, `TutorialManager`, `HelperPanel`, `HelpIndexPanel`, [23-onboarding.md](23-onboarding.md) |
| **Build UX**: cost on every card and why a locked card cannot be built, one building per placement, construction label with % and time left, drag-to-scroll on every list | ✅ | `ConstructionMenu`, `PlacementRules.keeps_placing()`, `DragScroll`, [08-ui-systems.md](08-ui-systems.md) |
| **One UI palette**: ten named colours, everything else derived; plain boxes instead of textured metal; the activity log moved to the menu, only important toasts on screen | ✅ | `UITheme._BASE`, [24-paleta.md](24-paleta.md) |
| **Save format 2**: the grid size and seed saved; a save from before roads and 2x2 is set aside with a date and a new colony starts | ✅ | `GameManager.SAVE_FORMAT`, [09-save-system.md](09-save-system.md) |
| **Colono / Gobernador**: two tiers of the Campaña. Colono is the plain game; Gobernador (unlocked by profile after a finished game) adds the Storm calendar and a visible spread in the Market, spoilage, harder enemies, Tithe and Final Audit | ✅ | `GameMode.tier()`, `GameConfig.game_tier_rules`, `NewGameDialog`, [20-modos-de-juego.md](20-modos-de-juego.md), [16-balance-combate.md](16-balance-combate.md) |
| **Governor rank**: XP from what the colony does, 18 ranks with titles, decoration unlocks, extra slots, small permanent bonuses, flag pieces | ✅ | `RankManager` (autoload 27), `RankPanel`, `PlacementRules.check_rank()`, [06-progression-victory.md](06-progression-victory.md) §Governor rank |
| **City life**: workers and citizens leave their houses, walk the roads to work and hide during the Storm | ✅ | `scripts/map/WorkerWalkers.gd`, `WalkerFigures3D` / `WalkerFigures2D`, [04-population-morale.md](04-population-morale.md) |
| **Less text**: icons and numbers before sentences in every panel, one-line notices and war reports, help bubbles of one or two sentences, the tech card with INVESTIGAR, the objective strip gone (the next step lives in ¿QUÉ HACER?) | ✅ | `TextKit`, `TouchTooltip`, `TechTreePanel`, `ObjectivePanel`, [21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md) |
| **Building look**: construction phases that differ per building and per instance (animated), ruin and working smoke in 3D and 2D, icon scales 24/42/60/96 | ✅ | `BuildingLook*`, `BuildingFx`, `SiteFx`, `BuildingArt2D`, `tools/look_probe.gd`, [03-buildings.md](03-buildings.md) |
| **Balance 2026-10-04**: gentle trial storm in era 1 (no Tithe), hand mining cut so era 2 lands at 8.6-10.2 min, a tower whose crew dies is left damaged, siege morale read at QUE BAJEN, touch "auto" only on phone/tablet, the first skirmish as an easy single-node run with fixed loot | ✅ | `storm_trial_*`, `mining_data`, `StormManager`, `FinalAudit`, [22-linea-jugable.md](22-linea-jugable.md) §5.5, [17-balance-asedio.md](17-balance-asedio.md) |
| **War reports**: blind-defence report, Tithe report (COBRADO / REPELIDO), siege banner, lost-siege report | ✅ | `WarReportScreen`, `AuditWaveBanner`, `AuditDefeatScreen` |
| **Balance line**: the whole campaign played at real timings over ten seeds; dead ends fixed; 10/10 won in 2 h 18 min – 4 h (median 3 h 11 min); the ¿QUÉ HACER? panel | ✅ | `tools/line_probe.gd`, `scripts/services/Objectives.gd`, [22-linea-jugable.md](22-linea-jugable.md) |
| **Combat balance** measured, not guessed | ✅ | `tools/balance_probe.gd`, `tools/siege_probe.gd`, [16-balance-combate.md](16-balance-combate.md), [17-balance-asedio.md](17-balance-asedio.md) |
| **Windows export**: one `.exe`, dev bridge gated, no dev files or tokens in the package, own save folder | ✅ | `export_presets.cfg` "Windows Desktop", [19-exportar.md](19-exportar.md) |
| **Release packaging**: zips for testers with the licence, third-party notices and a LEEME | ✅ | `tools/package_release.sh` / `.ps1`, `THIRD-PARTY-NOTICES.md`, `licenses/`, [19-exportar.md](19-exportar.md) §8 |
| **Android export**: debug APK (arm64, landscape, immersive, Mobile renderer, no permissions); an x86_64 OpenGL QA preset for the emulator | ✅ | "Android" and "Android QA (emulador)" presets, [19-exportar.md](19-exportar.md) §11 |
| **Tablet QA flows** on the Android emulator | ✅ | `qa/maestro/` (README inside) |
| **Tests isolated from the player's saves** | ✅ | `tools/run_tests.sh` / `.ps1`, `tests/save/save_parking.gd` |
| **Legal frame**: the Venezuelan rules that touch a war-themed game, content and communication rules | ✅ | [25-marco-legal.md](25-marco-legal.md) |

---

## ✅ Milestone 1 — Economic floor

Tuning on systems that already exist: the biggest change in feel for the least new code.

| Item | Status | Notes |
|------|--------|-------|
| Shared storage pool | ✅ | One cap for the **sum** of the five resources. Era 1 = 600, Era 2 = 800, Era 3 = 1000, +500/warehouse (max 5) — Era 3 ceiling is exactly the HQ-3 price (3500), 4500 with the storage techs. Touches `GameConfig.get_storage_cap`, `ResourceManager.add`, `ResourceHUD`, save load |
| **Storm cycle** | ✅ | `CALM → WARNING → ASH → STORM → TITHE`, plus a `WARNING → CALM` false alarm that banks +1 severity for next time. Calm interval is a random range; phase durations stay fixed. Two production multipliers (ash 0.50, storm 0.15). The Storm arms with the first Foundry |
| Phase indicator instead of a clock | ✅ | `StormHUD`: colour and icon for the current phase, nothing in calm. Severity is not announced |
| Queue stays open, the storm ruins it | ✅ | Processes, mining and training can run through all phases, but anything still in flight when the STORM lands is lost with its cost (a whole batch included) |
| Corruption tax (cancellation) | ✅ | Refund 70% in calm and 40% while the storm cycle is active, clamped to the free space in the shared pool |
| Famine & desertion | ✅ | After two grace ticks, unpaid food kills population and unpaid upkeep deserts units |
| Ruin floor | ✅ | The Nucleo is never damaged, population never drops below 1 and regrows below 5 regardless of morale — there is always a thread to rebuild from |

## ✅ Milestone 2 — The storm bites

| Item | Status | Notes |
|------|--------|-------|
| Building health system | ✅ | `BuildingHealth` autoload: damage, ruined state that halts output, proportional repair cost, state persisted |
| Repair | ✅ | Costs scale with the damage taken — a scratch is cheap, a ruin nearly costs rebuilding |
| Storm sky | ✅ | `StormSky.gd` (3D) and `StormTint2D` (2D) — darkening scaled by severity, blended over the time of day |
| Selective damage | ✅ | Priority: defence and morale first, then housing, then production. Never the Nucleo, never the last sawmill or gold mine (anti-softlock) |
| Minimum Quota | ✅ | An empty warehouse no longer means a free Tithe: from the second visit the debt is collected in buildings and workers |
| Arms race | ✅ | `StormCycle.storms_survived` feeds `assessor_roster()`: winning today means heavier guns tomorrow |
| Defensive towers | ✅ | Mitigate storm damage (15% each, 60% cap) and field an artillery crew on the defensive boards (Tithe and Final Audit), outside the deploy cap, back row, max 2 — only while operational |

## ✅ Milestone 3 — Expedition & the double clock

Tasks T022-T029 are specified in `specs/001-combate-pve/tasks.md`. The expedition runs
end to end from the UI.

| Item | Status | Where it lives |
|------|--------|----------------|
| `ExpeditionGenerator` + `Expedition` pure models (boss reachable across many seeds) | ✅ | `scripts/combat/ExpeditionGenerator.gd`, `scripts/combat/Expedition.gd`, `tests/combat/test_expedition_generator.gd`, `tests/combat/test_expedition.gd` |
| `launch_expedition()` and the rest of the service API (`select_node`, `apply_draft`, `abandon_expedition`, `enter_current_node`) | ✅ | `scripts/services/CombatManager.gd`, `tests/combat/test_expedition_wiring.gd` |
| Expedition save/load — seed + cleared nodes, map regenerated, board never saved | ✅ | `Expedition.to_dict/from_dict`, `CombatManager.get_save_data/load_save_data`, `GameManager` |
| Chained encounters with attrition and permadeath | ✅ | `Expedition.build_encounter_units()`, `CombatManager.enter_current_node()` |
| **Unit lockout**: `get_garrison()` excludes units away on expedition | ✅ | `CombatManager.get_garrison()` / `get_units_on_expedition()` |
| **Defensive auto-resolve**: the *same* `Encounter` headless, AI on both sides | ✅ | `scripts/combat/AutoResolver.gd`, `CombatManager.auto_resolve_defense()`, `StormManager._auto_resolve_tithe()` |
| After-action report for the blind defence | ✅ | `WarReportScreen` listens to `defense_auto_resolved` |
| Storm notifications drawn over `BattleScreen` | ✅ | `NotificationPanel` toast layer vs `BattleScreen.layer`, `tests/storm/test_storm_toasts_over_board.gd`; since 2026-10-14 the colony's own notices wait until the board closes |
| **Skirmish panel, map view, draft modal, final report** | ✅ | `SkirmishPanel` calls `CombatManager.launch_expedition(party)`; `BattleScreen` builds the map, the draft modal and the report on top of the board. `tests/ui/test_expedition_ui.gd` |
| Listeners for the expedition signals | ✅ | `draft_offered` / `draft_applied` → BattleScreen; `expedition_node_selected` → BattleScreen, SkirmishPanel; `expedition_resumed` → BattleScreen, SkirmishPanel, ArmyPanel. A campaign in flight reopens its map on load |
| **Unit silhouettes on the 2D board** and baked toy units on the 3D one | ✅ | `assets/textures/ui/units/*.png` from `tools/gen_unit_icons.gd`, `UITheme.unit_icon()`; `assets/models/toy/units/` |
| Combat audio | ✅ | `AudioManager` on the combat and Final Audit signals, `tests/audio/test_audio_combat.gd`; every key has its own clip and the combat theme is its own track; 1.1: shots, engines, planes, ships, torpedo, sinking and crash by unit type (`tools/gen_combat_audio.gd`, `tests/audio/test_audio_units_ambient.gd`) |
| Helper callout for Escaramuzas | ✅ | `HelperPanel` `SkirmishCallout`, `tests/ui/test_helper_skirmish_callout.gd` |
| End-to-end probe | ✅ | `tools/expedition_probe.gd` |

## ✅ Milestone 4 — The Final Audit

| Item | Status | Where it lives |
|------|--------|----------------|
| HQ level 3 summons the siege instead of instantly winning (Campaña, Supervivencia) | ✅ | `ProgressionManager._complete_milestone()` → `summon_final_audit()`; `scripts/combat/FinalAudit.gd`, `tests/combat/test_final_audit.gd` |
| 3-5 chained defensive encounters with attrition, entered with "QUE BAJEN" | ✅ | `final_audit_wave_ready` → `CombatManager._on_final_audit_wave_ready()` → `start_defense()`; `tests/storm/test_final_audit_wiring.gd` |
| Winning emits `storm_halted_forever` and the Storm stops for good | ✅ | `ProgressionManager._publish_audit()`, `StormManager._on_halted_forever()`, `StormSky.restore_now()` |
| Losing sacks the settlement; the siege can be summoned again after rebuilding (not in Supervivencia) | ✅ | `StormManager._on_final_audit_lost()`; `FinalAudit.can_resummon()` / `resummon()` with a floor of `final_audit_resummon_min_units` (3); `AuditDefeatScreen` |
| The siege is hard and winnable | ✅ | [17-balance-asedio.md](17-balance-asedio.md): the maximum garrison wins ~82% (measured before the type advantage; its effect on the siege is in the same doc) |

---

## 🚧 In progress

### Phase 1 of the loop redesign (goes into the 1.0)

After playing the 1.0 build, the owner found that the loop is hard to follow and has
little "what for", that skirmishes do not feel necessary and are too random and too
long, that nobody explains how units work and move, and that the building limits are
too tight for the resources the colony makes. A redesign plan was written on
2026-10-14 (kept in the owner's private notes). Its diagnosis, measured on the code and
the probes:

- **Skirmishes pay what the colony already has** (gold and wood) and the line probe
  wins 10 of 10 campaigns without a single expedition; they cost real units and those
  units do not defend the Tithe; they hide in ☰ MENÚ; the loot is only seen after
  launching.
- **Expeditions are long and random:** `combat_map_depth` (4, 6) × `combat_map_branching`
  (2, 3) gives 6-8 fights of 3-5 minutes each, with no healing between nodes, and each
  fight drags 3-5 rounds after it is decided.
- **The board teaches nothing:** the tutorial ends on the colony map; the artillery's
  minimum range, the type advantage and the enemy's reach are never explained.
- **Limits are small and fixed** (`GameConfig.building_limits`), rank barely raises
  them, and era 3 brings nothing new to build but the HQ.

Owner's decisions (2026-10-14): **limits that rise with the era** (about ×1.5 in era 2
and ×2 in era 3, decorations without a cap) instead of a Núcleo with levels;
**loot only found outside** (blueprints, spare parts, settlers, plus a cheaper Tithe)
already in the 1.0; a **1-fight raid and a 3-fight expedition**. The board's 8x8 rules
and the damage formula are not touched.

| # | Branch | What | State |
|---|---|---|---|
| 1.1 | `feat/escaramuza-visible` | ESCARAMUZAS as a HUD button (with a red dot when there is a reason to go out); ¿QUÉ HACER? asks for a skirmish again when there is a motive | ⬜ not started |
| 1.2 | `feat/expedicion-corta` | Short runs: a 3-fight expedition, the map rolled when it appears and shown before launching with its enemies and loot, "Favorable / Difícil" from both rosters' power, 30% healing between fights; exclusive loot (blueprints, spare parts, settlers, a cheaper Tithe) | ⬜ not started |
| 1.3 | `feat/retirada-enemiga` | The enemy withdraws below 30% of its total health (not in the siege); "resolve alone" only with at least double strength, through the same `AutoResolver` | ⬜ not started |
| 1.4 | `feat/tutorial-tablero` | A guided first fight (select, move, attack, watch the enemy, defend) and a second one with artillery (minimum range, the type circle) | 🚧 in `feat/ensenar-combate`, not integrated |
| 1.5 | `feat/fichas-y-vistas-previas` | Unit cards from `combat_unit_stats` (move, range, strong / weak against), damage preview when aiming, the enemy's reach, the ✕ on the artillery's adjacent cells | 🚧 in `feat/ensenar-combate`, not integrated |
| 1.6 | `feat/topes-por-era` | Building limits that rise with the era (`building_limits_by_era`: house 10/15/20, farm 6/9/12, sawmill 5/8/10, gold mine 4/6/8, foundry 3/5/6, refinery 2/3/4, barracks 3/4/5; warehouse 5 and tower 6 stay), read only through `GameConfig.get_building_limit()`; decorations without a cap; CONSTRUIR shows "3/6 · era 2: 9" | ✅ done |
| 1.7 | `feat/decoraciones-1` | Ten cheap decorations (street lamp, bench, hedge, street tree, flower pots, colony sign, hay cart, bonfire, flagpole, palm trees), +1 to +3 morale, no cap, five free and the rest by rank (2, 3, 5, 13), with their 2D drawing | ✅ done; the 3D meshes are procedural (`DecorMesh`) until their CC0 recipes are baked |
| 1.8 | `feat/salto-y-camara` | A "pop" when a building finishes, collect icons that bounce and fly to the HUD, a closer start camera that tilts as it zooms in, a dark contact edge on the baked models | ✅ done |

Every phase ends by re-measuring the campaign (`tools/line_probe.gd`, with its player
taught to raid), the siege (`tools/siege_probe.gd`), the fights
(`tools/balance_probe.gd`) and performance (`tools/perf_probe.gd` on a large decorated
colony), and by updating `CLAUDE.md`, docs/03, docs/15, docs/23 and this file.

### Other branches landing on the 1.0

| Branch | What | State |
|---|---|---|
| `balance/campana-4-6h` | A 4-6 h campaign measured with the irregular island; ¿QUÉ HACER? suggests upgrading a producer when the pool is full | Open, not integrated |
| `feat/ensenar-combate` | Teaching the combat (covers 1.4-1.5: guided fight, unit cards, previews) | 🚧 branch open, not integrated yet |

## ❓ Open balance decisions

Measured by the balance line and left to the owner
([22-linea-jugable.md](22-linea-jugable.md) §7):

1. ✅ **A "resolve alone" button for the Tithe** — decided 2026-10-04: **no**, the board
   is the game. **Reopened 2026-10-14** by the redesign ("too long"): only with at
   least double strength, never in the siege (phase 1.3).
2. ✅ **The era-3 storage squeeze** — decided 2026-10-04 and built: production waits in
   the buildings and they stop when full; nothing is thrown away. What enters the bag
   directly (hand mining, purchases, loot) and does not fit is still lost, with a
   warning.
3. ✅ **A scripted test storm in era 1** (decided 2026-10-04): a gentle trial storm
   around minute 5, no Tithe, once per game (`storm_trial_*`, docs/22 §5.5).
4. ✅ **How long era 1 should last** (decided 2026-10-04: 8-12 min): hand mining cut
   (`mining_data`), era 2 at 8.6-10.2 min for the default probe player. Still open: the
   Núcleo/sawmill processes take a player who chains them to the Foundry by minute
   4.6-4.9 (lever: `building_processes`; the Núcleo now runs every recipe, slower).
5. ✅ **Where the set-aside modes go** (decided 2026-10-04): Constructor, Supervivencia and
   Sandbox still work and load, and they come back one at a time, later; meanwhile the
   Campaña got two tiers (Colono / Gobernador). The New Game dialog offers only Campaña
   (`GameMode.OFFERED`).
6. ❓ **The rest of the redesign** (later phases): the Regency's order each calm with a
   storm barometer, map threats that grow if ignored, contracts, unit doctrines, beauty
   points per neighbourhood. Proposed, not decided beyond phase 1 (a Núcleo with levels
   was turned down in favour of limits by era).

Also pending on the balance side: a human playtest with real timings (checklist in
[22-linea-jugable.md](22-linea-jugable.md) §9) and a test on a physical tablet. The
balance line of docs/22 was measured **before** roads, 2x2 buildings, materials,
food, collecting and the irregular island: its timings need a new run of
`tools/line_probe.gd` (the `balance/campana-4-6h` branch has started that work).

## 💤 Backlog

- 🚧 Cloud saves: `CloudSaveManager` (Supabase REST, auth + save/load) implemented but
  **unwired** — needs credentials an export can read (the package excludes `.env`) and
  a login UI ([12-cloud-saves.md](12-cloud-saves.md))
- ⬜ Later redesign phases (1.1-1.2): the Regency's order and barometer, map threats and
  raids, exclusive loot beyond phase 1, contracts, 18 new useful buildings and 28 more
  decorations, a regiment (name, colours, emblem, paint) and doctrines, a practice
  range, beauty per neighbourhood, traffic on the roads, bigger buttons
- 💤 Night with a gameplay effect (today `DayClock.is_night()` is read by nobody but the
  light, the walkers and the sound)
- 💤 Towers with an attack of their own on the base map
- 💤 Sea and shore resources: the shore band is kept free of land deposits and
  `MapGenerator.shore_cells()` / `_generate_shore_deposits()` are the hook
- 💤 Sea and air units: the combat model already carries a `domain` per unit
  ([15-combat.md](15-combat.md) §11)
- 💤 Re-measure performance after the optimisations, on a weak PC and a real cheap
  tablet ([26-rendimiento.md](26-rendimiento.md) §8)
- 💤 Guide and readme screenshots (`docs/media/`) retaken with the toy look, roads and
  the irregular island
- 💤 Achievements / statistics
- 💤 Distribution: Windows code signing (SmartScreen), Android release keystore, AAB
  and store listing ([19-exportar.md](19-exportar.md) §8, §11.10)
- 💤 Small known gaps listed per system: [15-combat.md](15-combat.md) §10,
  [18-vista-2d.md](18-vista-2d.md) "Huecos conocidos",
  [21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md) §11,
  [23-onboarding.md](23-onboarding.md) §6, and the orphan signals in
  [10-signals-reference.md](10-signals-reference.md)

---

## Dependency order (as it was built)

```
M1 economy ──────────────┐
    │                    │
    └──▶ building ──────▶ M2 storm bites
         health           │
                          ├──▶ M3 expedition + double clock
                          └──▶ M4 Final Audit
                                   │
                                   └──▶ 2D view · modes · UI & devices · touch
                                        · onboarding · balance line · exports
                                              │
                                              └──▶ 1.0 round: toy art · island · food
                                                   · day/night · sound · saves · flag
                                                   · combat 3D · performance
                                                        │
                                                        └──▶ redesign phase 1 ──▶ 1.0
                                                             (limits by era, decorations,
                                                              pop + camera done)
```

Milestone 1 came first because it is tuning, not construction. Milestone 4 depended
only on Milestone 2.

## Out of scope

PvP and co-op · meta-progression between expeditions · non-combat expedition nodes ·
loot boxes or paid randomness (every reward is shown before it is earned).
