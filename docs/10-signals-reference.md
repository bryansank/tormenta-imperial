# EventBus Signals Reference

All inter-system communication flows through `EventBus` (`scripts/services/EventBus.gd`). Systems emit signals; others subscribe. No direct references between services.

**140 signals** in 30 categories (counted on 2026-10-18, integration of 1.1: `touch_controls_size_changed` from the mobile controls branch, `instructors_visibility_changed` from the instructors branch and the rest added since 2026-10-17; on 2026-10-17 there were 134: the 133 of 1.1 — the 126 of 1.0, `regiment_changed`, `storm_order_changed` and the 5 of [Encargos](#encargos) — plus `trial_tithe_resolved`, the 1.0 toy Tax), mostly in the order they are declared in `EventBus.gd`. Emitters and
consumers below were read out of `scripts/` — tests that emit or listen for a
signal are **not** counted as wiring, because a signal only exercised by a test is
not wired in the game.

Two patterns count as a connection, and both are included here:

- `EventBus.<signal>.connect(...)` — the normal case.
- `var bus := EventBus` then `bus.<signal>.connect(...)` — `BuildingStatusBadge`.

(The old string form, `AudioManager._connect_optional()`, is gone: every signal it
guarded exists, and AudioManager connects them typed.)

Rows marked *(no emitter)* or *(no listener)* are declared but not wired on that
side. That is recorded on purpose: see [Orphan signals](#orphan-signals) for the
full list and why each one is there.

## Camera

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `camera_pan_requested` | `direction: Vector2` | InputService, OnScreenControls | MonumentalCamera, Camera2DController |
| `camera_zoom_requested` | `amount: float` | InputService, OnScreenControls | MonumentalCamera, Camera2DController |
| `camera_drag_moved` | `delta: Vector2` | InputService | MonumentalCamera, Camera2DController |
| `camera_drag_world_requested` | `delta: Vector2` (world XZ) | InputService (touch grab-pan), BuildingPlacer (left-drag grab-pan), BuildingPlacer2D | MonumentalCamera, Camera2DController |
| `camera_rotate_requested` | `amount: float` | InputService | MonumentalCamera |
| `camera_rotate_step_requested` | `degrees: float` | OnScreenControls, InputService | MonumentalCamera |

Touch and mouse share `camera_drag_world_requested` on purpose: one finger and the
left button go through the same screen→world conversion
(`InputService.screen_drag_to_world_delta`), so they cannot drift apart.

## Resources

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `resource_changed` | `resource_type: String, new_amount: int, delta: int` | ResourceManager | ResourceHUD, ProgressionManager, TechTreePanel |
| `resources_insufficient` | `resource_type: String, required: int, available: int` | ResourceManager, MarketManager | ResourceHUD, AudioManager |
| `storage_overflow` | `resource_type: String, lost: int, cap: int` | ResourceManager | TutorialManager, ResourceHUD |

`storage_overflow` fires when the shared pool was full and `lost` units did not
fit. The player is warned once per game, via a TutorialManager tip, and
`ResourceHUD` flashes the storage bar.

## Buildings

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `building_selected_for_placement` | `building_data: Resource` | ConstructionMenu | BuildingPlacer, BuildingInfoPanel, OnScreenControls, TutorialManager, HelperPanel, BuildingPlacer2D |
| `building_placement_cancelled` | — | BuildingPlacer, OnScreenControls, PauseMenu, BuildingPlacer2D | BuildingPlacer, OnScreenControls, TutorialManager, HelperPanel, BuildingPlacer2D |
| `building_placed` | `building_data: Resource, cell: Vector2i` | BuildingPlacer, BuildingPlacer2D | ProductionManager, GameManager, ProgressionManager, ArmyPanel, SkirmishPanel, HelperPanel, OnScreenControls, AudioManager, TutorialManager |
| `placement_batch_started` | — | PlacementRules.pave_route (antes de los tramos del auto-road) | GameManager, PopulationManager (aplazan guardado y recuento) |
| `placement_batch_finished` | `count: int` | PlacementRules.pave_route (tras el ultimo tramo) | GameManager (un guardado), PopulationManager (un recuento) |
| `building_moved` | `from_cell: Vector2i, to_cell: Vector2i` | BuildingPlacer, BuildingPlacer2D | GameManager, TutorialManager, HelperPanel, OnScreenControls |
| `building_removed` | `cell: Vector2i` | *(no emitter)* | *(no listener)* |

## Selection

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `building_clicked` | `building_node: Node, building_data: Resource` | BuildingPlacer, BuildingPlacer2D | BuildingInfoPanel, BuildingPlacer, BuildingPlacer2D |
| `building_deselected` | — | BuildingPlacer, BuildingPlacer2D | BuildingInfoPanel, BuildingPlacer, OnScreenControls, HelperPanel, BuildingPlacer2D |
| `deposit_clicked` | `deposit_node: Node, deposit_id: String, cell: Vector2i` | BuildingPlacer, BuildingPlacer2D | BuildingInfoPanel, BuildingPlacer2D |
| `request_move_building` | `building_node: Node` | BuildingInfoPanel | BuildingPlacer, TutorialManager, HelperPanel, OnScreenControls, BuildingPlacer2D |
| `building_renamed` | `building_node: Node, new_name: String` | BuildingInfoPanel | GameManager |
| `building_rotate_requested` | — | OnScreenControls | BuildingPlacer, BuildingPlacer2D |

## Processes & Mining

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `process_started` | `building_node: Node, process_id: String` | ProcessManager | BuildingStatusBadge |
| `process_completed` | `building_node: Node, process_id: String` | ProcessManager | BuildingInfoPanel, BuildingStatusBadge, AudioManager |
| `mining_started` | `deposit_node: Node, deposit_id: String` | ProcessManager | BuildingStatusBadge |
| `mining_completed` | `deposit_node: Node, deposit_id: String` | ProcessManager | MapGenerator, BuildingInfoPanel, BuildingStatusBadge, AudioManager |
| `process_cancelled` | `building_node: Node, process_id: String, refunded: Dictionary` | ProcessManager | BuildingStatusBadge |

`refunded` on `process_cancelled` is resource → amount **already applied**: it is
what the UI promised before confirming, and what was actually paid back.

## Construction

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `construction_started` | `building_node: Node` | ProductionManager | BuildingStatusBadge |
| `construction_completed` | `building_node: Node` | ProductionManager | BuildingInfoPanel, ProgressionManager, PopulationManager, BuildingStatusBadge, AudioManager, TutorialManager |

## Production

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `production_tick` | `building_node: Node` | ProductionManager | BuildingStatusBadge |

### Food, Farm and collecting (`comida-granja-recoger` block)

All emitted by `ProductionManager`: production waits in each building until it is
collected ([02-economy.md](02-economy.md)).

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `building_stock_changed` | `node: Node, stock: Dictionary` (resource -> amount waiting) | ProductionManager | BuildingStatusBadge, StockIcon3D, StockIcon2D, TutorialManager |
| `production_collected` | `node: Node, collected: Dictionary` (what entered the bag; the rest stays in the building) | ProductionManager | BuildingPlacer, BuildingPlacer2D (the icon and "+N" fly to the HUD), AudioManager (`collect` / `harvest`), TutorialManager |
| `stock_spoiled` | `node: Node, lost: Dictionary` (only with `GameMode.spoilage_enabled()`) | ProductionManager | *(no listener)* |
| `crop_planted` | `node: Node, crop_id: String` | ProductionManager | GameManager (autosave trigger) |

## Upgrades

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `building_upgrade_started` | `building_node: Node, new_level: int` | ProductionManager | BuildingStatusBadge |
| `building_upgrade_completed` | `building_node: Node, new_level: int` | ProductionManager | BuildingInfoPanel, ProgressionManager, PopulationManager, BuildingStatusBadge, AudioManager |

## Demolish

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `request_demolish_building` | `building_node: Node` | BuildingInfoPanel | BuildingPlacer, BuildingPlacer2D |
| `building_demolished` | `building_node: Node, cell: Vector2i` | BuildingPlacer, BuildingPlacer2D | GameManager, PopulationManager, BuildingInfoPanel, ArmyPanel, SkirmishPanel, HelperPanel, AudioManager, TutorialManager |

## Deposits

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `deposit_depleted` | `deposit_node: Node, deposit_id: String` | MapGenerator | BuildingInfoPanel |

## Map

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `grid_resized` | `width: int, height: int` | GridManager (`set_grid_size()`, `roll_new_map()`, `load_save_data()`, only when size or island seed change) | IslandGenerator, Island2D, GridOverlayControl, GridOverlay2D, MonumentalCamera, Camera2DController |

## Ground Interaction (reserved for future terrain interaction)

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `ground_clicked` | `world_pos: Vector3, cell: Vector2i` | *(no emitter)* | *(no listener)* |
| `ground_hover` | `world_pos: Vector3, cell: Vector2i` | *(no emitter)* | *(no listener)* |

## Market

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `market_prices_updated` | `prices: Dictionary` | MarketManager | MarketPanel |
| `market_trade_completed` | `resource: String, amount: int, is_buy: bool, total_price: int` | MarketManager | ProgressionManager, MarketPanel, AudioManager |

## Progression

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `resource_unlocked` | `resource_name: String` | ResourceManager | ResourceHUD, ConstructionMenu, MarketPanel, ArmyPanel, AudioManager |
| `era_advanced` | `new_era: int` | ProgressionManager | ProgressPanel, ResourceManager, ArmyPanel, AudioManager |
| `core_upgrade_started` | `to_level: int` | ProgressionManager (1.2, Núcleo con niveles) | BuildingInfoPanel, GameManager (autosave) |
| `core_level_changed` | `level: int` | ProgressionManager (al terminar la obra y al cargar) | ConstructionMenu (topes y candados "Núcleo N") |
| `milestone_completed` | `milestone_id: String` | ProgressionManager, TechTreeManager | ProgressPanel, NotificationPanel, AudioManager |
| `phase_advanced` | `new_phase: int` | ProgressionManager | MarketPanel, NotificationPanel, StormManager |
| `victory_achieved` | `stats: Dictionary` | ProgressionManager | VictoryScreen, AudioManager |

`victory_achieved` is still the end of the game, but it is now reached **only**
through a won Final Audit — HQ level 3 summons the siege, it does not win.
`new_phase` follows `GameConfig.Phase`.

## Population & Morale

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `population_changed` | `current: int, max_pop: int` | PopulationManager | NotificationPanel |
| `workers_changed` | `used: int, total: int` | PopulationManager | NotificationPanel, BuildingStatusBadge |
| `morale_changed` | `new_morale: int` | PopulationManager | NotificationPanel, SkirmishPanel |
| `consumption_failed` | `resource: String` | PopulationManager | TutorialManager |
| `population_starved` | `deaths: int, population: int` | PopulationManager | *(no listener)* |

`population_starved` reports a famine that actually killed: `deaths` is how many
died, `population` what is left afterwards (never below the floor).

## Army

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `unit_training_started` | `unit_id: String, duration: float` | ArmyManager | *(no listener)* |
| `unit_trained` | `unit_id: String` | ArmyManager | AudioManager, TutorialManager |
| `army_changed` | — | ArmyManager | ArmyPanel, SkirmishPanel, HelperPanel |
| `army_upkeep_unpaid` | `gold_short: int` | ArmyManager | ArmyPanel, TutorialManager |
| `unit_training_cancelled` | `unit_id: String, refunded: Dictionary` | ArmyManager | *(no listener)* |
| `army_deserted` | `unit_id: String, count: int` | ArmyManager | PopulationManager |
| `regiment_changed` | — | ArmyManager | RegimentCard (Cuartel) |

`army_upkeep_unpaid` is the warning; `army_deserted` is the bill — sustained
unpaid upkeep loses the most expensive unit first.

## Combat

Emitted only by `CombatManager`. `side`: 0 = player, 1 = enemy.

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `expedition_started` | `expedition_id: int, node_count: int` | CombatManager | BattleScreen, SkirmishPanel, ArmyPanel, NotificationPanel, AudioManager, TutorialManager |
| `expedition_node_selected` | `node_index: int` | CombatManager | BattleScreen, SkirmishPanel |
| `encounter_started` | `encounter_index: int, is_boss: bool` | CombatManager | BattleScreen, SkirmishPanel, TutorialManager, AudioManager, GameManager |
| `turn_started` | `side: int, unit_uid: int` | CombatManager | BattleScreen |
| `unit_moved` | `unit_uid: int, from: Vector2i, to: Vector2i` | CombatManager | BattleScreen |
| `unit_attacked` | `attacker_uid: int, target_uid: int, damage: int` | CombatManager | BattleScreen, AudioManager |
| `unit_defended` | `unit_uid: int` | CombatManager | BattleScreen |
| `unit_died` | `unit_uid: int, side: int` | CombatManager | BattleScreen, AudioManager |
| `encounter_ended` | `victory: bool, turns_used: int` | CombatManager | BattleScreen, StormManager, AudioManager |
| `draft_offered` | `options: Array` | CombatManager | BattleScreen |
| `draft_applied` | `option: Dictionary` | CombatManager | BattleScreen |
| `expedition_ended` | `result: int, rewards: Dictionary, casualties: Dictionary` | CombatManager | BattleScreen, SkirmishPanel, ArmyPanel, NotificationPanel, AudioManager |
| `expedition_resumed` | `expedition_id: int` | CombatManager | BattleScreen, SkirmishPanel, ArmyPanel |
| `defense_auto_resolved` | `victory: bool, rounds: int, summary: Dictionary` | CombatManager | WarReportScreen |
| `trial_tithe_resolved` | `repelled: bool, taken: Dictionary` | StormManager (the toy Tax of the era-1 trial storm) | WarReportScreen |
| `sortie_offers_changed` | — | CombatManager | SkirmishButton, SkirmishPanel |
| `campaign_changed` | — | CombatManager | SkirmishButton, SkirmishPanel |
| `campaign_mission_won` | domain: String, mission: int, is_boss: bool | CombatManager | RankManager, line_probe_player |
| `campaign_completed` | domain: String | CombatManager | ProgressionManager (`try_summon_final_audit`), line_probe_player |
| `sortie_loot_gained` | `loot: Dictionary` | CombatManager | (sin oyentes: el parte lo lee de `get_last_result()`) |
| `blueprint_unlocked` | `building_id: String` | CombatManager (`grant_blueprints`, botín, misión ganada) | ConstructionMenu (quita el candado "Plano"); aviso `NOTIF_BLUEPRINT_GAINED` |
| `enemy_routed` | — | CombatManager | BattleScreen |
| `encounter_closed` | — (end of `CombatManager.end_encounter()`: the report was read) | CombatManager | NotificationPanel, ProgressPanel, RankPanel, HelperPanel (release the notices held during the fight; they re-check `is_board_open()`, the next siege wave may have opened another board) |

`result` on `expedition_ended`: 0 = victory, 1 = defeat, 2 = abandoned.

`expedition_resumed` is connected in all three panels (BattleScreen, SkirmishPanel,
ArmyPanel). It fires when
a save with a campaign in flight is loaded, so the UI can reopen the map on the
current node; the board itself is never saved, so there is never an open encounter
waiting behind it.

`defense_auto_resolved` covers the garrison fighting alone: the Tithe landed while
an expedition held the board, so the defence was resolved blind through
`AutoResolver`. `summary` is `CombatManager.get_last_result()`. It is the **only**
signal that fight emits — no `encounter_*`, `turn_started` or `unit_*` accompanies
it, because the open board would claim them as its own. `WarReportScreen` listens
and shows the after-action report; `StormManager` still reads the return value of
`auto_resolve_defense()` directly for its own toast.

Full design: [15-combat.md](15-combat.md).

## Building Health

Emitted only by `BuildingHealth`. A ruined building stays where it is and stops
producing until the repair is paid; it is never destroyed on its own.

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `building_damaged` | `building_node: Node, health: int, max_health: int` | BuildingHealth | AuditDefeatScreen |
| `building_ruined` | `building_node: Node` | BuildingHealth | BuildingStatusBadge, TutorialManager, AuditDefeatScreen |
| `building_repaired` | `building_node: Node` | BuildingHealth | BuildingStatusBadge |

## Imperial Storm

Emitted only by `StormManager`. The storm is dispatched on a schedule, not rolled
at random — the player is meant to see it coming and prepare. `phase` values
follow `StormCycle.Phase`.

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `storm_phase_changed` | `phase: int, seconds_left: float` | StormManager | StormHUD, SandboxPanel |
| `storm_incoming` | `seconds_until: float` | StormManager | StormHUD, StormSky, HelperPanel, TutorialManager |
| `storm_false_alarm` | `deferred: int` | StormManager | StormHUD, StormSky, HelperPanel |
| `storm_ash_started` | — | StormManager | ProcessManager, ArmyManager, StormHUD, StormSky, TutorialManager |
| `storm_started` | `severity: int` | StormManager | ProcessManager, ArmyManager, StormHUD, StormSky, TutorialManager |
| `storm_tick` | `phase: int, seconds_left: float` | StormManager | StormHUD |
| `storm_ended` | `severity: int` | StormManager | ProcessManager, ArmyManager, StormHUD, StormSky |
| `tithe_demanded` | `severity: int` | StormManager | TutorialManager |
| `tithe_resolved` | `paid: bool, taken: Dictionary` | StormManager | StormHUD, HelperPanel, WarReportScreen, AuditDefeatScreen |
| `storm_order_changed` | `fresh: bool` | StormManager | StormHUD |

`storm_incoming` carries no severity on purpose — the warning window says the ash
is on the horizon, and the size of the bill is only announced with `storm_started`.
A warning that comes to nothing emits `storm_false_alarm(deferred)`, and `deferred`
is the severity the next real storm inherits: postponed, not forgiven.
`taken` on `tithe_resolved` is resource → amount.
`storm_order_changed` fires when the Regency Order changes (new order, delivered, a
discount added through `StormManager.add_tithe_discount()`); `fresh` is true only for a
new order (clock armed, or after a Tithe), and the HUD opens its card then
(docs/06 §Orden de la Regencia).

## Day and night

Emitted only by `DayClock` (docs/21 §12). `phase` follows `DayCycle.Phase`
(`DAWN`, `DAY`, `DUSK`, `NIGHT`); `hour` is the time of day, 0-1.

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `day_phase_changed` | `phase: int, hour: float` | DayClock | StormSky |

It fires when the clock **enters** a phase, never on load or on a new game: a
consumer re-derives from `DayClock.get_phase()` on `game_load_completed` /
`game_new_started`. StormSky repaints on it (otherwise every
`day_cycle_refresh` s). Visual only today; a future rule (night production, the
walkers' `set_presence()`, a night ambient track) would hang from it.

## The Final Audit

Emitted only by `ProgressionManager`. HQ level 3 no longer wins the game: it
summons the Regency's definitive audit, and surviving it is the victory. A siege is
3–5 consecutive waves against the same garrison.

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `final_audit_summoned` | `waves: int, summons: int` | ProgressionManager | SkirmishPanel, AudioManager *(optional connect)*, TutorialManager, SandboxPanel |
| `final_audit_started` | `waves: int` | ProgressionManager | SkirmishPanel, SandboxPanel |
| `final_audit_wave_ready` | `wave: int, roster: Dictionary, scale: float` | ProgressionManager | CombatManager, AuditWaveBanner |
| `final_audit_wave_cleared` | `wave: int, remaining: int` | ProgressionManager | AuditWaveBanner, SandboxPanel |
| `final_audit_lost` | `wave: int` | ProgressionManager | StormManager, SkirmishPanel, AuditDefeatScreen, WarReportScreen, AuditWaveBanner, SandboxPanel |
| `storm_halted_forever` | — | ProgressionManager | StormManager, StormSky, SkirmishPanel, AudioManager *(optional connect)*, AuditWaveBanner |

`final_audit_wave_ready` is the seam of the siege: the model says which wave it is
and with how much weight, and whoever drives the board is the one that calls
`CombatManager.start_defense()`. Nobody else.

`final_audit_lost` is not a game over in Campaña — the maximum Tithe is collected
and the town is left in ruins, but the siege can be summoned again once the army is
rebuilt. In Supervivencia there is no resummon: `run_ended` follows and the save is
sealed (see [Game modes](#game-modes)).

`storm_halted_forever` stops the Storm for good, and nothing else has permission to
stop the cycle. AudioManager connects both with a typed `.connect`.

## Random Events

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `random_event_started` | `event_id: String, event_data: Dictionary` | RandomEventManager | AudioManager |
| `random_event_ended` | `event_id: String` | RandomEventManager | *(no listener)* |

## Notifications

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `notification_posted` | `message: String, category: String, color: Color` | 23 scripts — every manager plus several panels (see below) | NotificationPanel, TechTreePanel |
| `objective_panel_toggled` | — | *(no emitter)* | ObjectivePanel |

`notification_posted` is the one genuinely global signal: ArmyManager, ArmyPanel,
BuildingPlacer, BuildingPlacer2D, CloudSaveManager, CombatManager, DeviceProfile,
GameManager, MapGenerator, NotificationPanel, PauseMenu, PlacementAssist,
PopulationManager, ProcessManager, ProductionManager, ProgressionManager,
RandomEventManager, ResourceHUD, ResourceManager, SettingsPanel, SkirmishPanel,
StormManager and TechTreeManager all post to it. TechTreePanel listens only to
refresh its tech states on any message.

## UI

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `sidebar_toggled` | `visible: bool` | PlacementAssist | ArmyPanel, HelperPanel, MarketPanel, ObjectivePanel, ProgressPanel, SettingsPanel, SkirmishPanel, TechTreePanel, PlacementAssist, UILayoutManager |
| `grid_overlay_toggled` | `visible: bool` | SettingsPanel | GridOverlayControl, GridOverlay2D |
| `fullscreen_changed` | `enabled: bool` | GameConfig | SettingsPanel |
| `game_speed_changed` | `speed: float` | GameConfig (`set_game_speed`) | GameSpeedButton; the combat view (shortens its animations with `combat_pace`) |
| `touch_controls_changed` | `enabled: bool` (resolved: "auto" already checked against the device) | GameConfig, DeviceProfile | OnScreenControls, ResourceHUD, HelperPanel |
| `touch_controls_opacity_changed` | `opacity: float` | GameConfig | OnScreenControls |
| `touch_controls_size_changed` | `scale: float` (resolved: "auto" already the profile's size) | GameConfig, DeviceProfile | OnScreenControls, PlacementAssist, UILayoutManager |
| `helper_visibility_changed` | `visible: bool` | HudRegistry | HelperPanel, SettingsPanel |
| `instructors_visibility_changed` | `visible: bool` | HudRegistry | TutorialPanel, HelperPanel, WarReportScreen, SettingsPanel (docs/23 §9) |
| `music_toggled` | `enabled: bool` | AudioManager | SettingsPanel, PauseMenu |
| `locale_changed` | `locale: String` | GameConfig (`set_locale()`) | GameManager (saves and reloads the scene keeping the game) |
| `graphics_quality_changed` | `quality: String` (`auto` / `high` / `low` / `minimal`) | GraphicsQuality (`set_quality()`) | WorldLook, DeviceProfile, ColonyFlag3D |

The ☰ sidebar is gone (the single MENÚ replaced it, see
[08-ui-systems.md](08-ui-systems.md)), so `sidebar_toggled` no longer opens
anything: its only emitter is `PlacementAssist`, which sends `false` when a
placement starts so that any panel still shifted out of the way comes back. The
listeners are what is left of the old sidebar layout.

## Persistence

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `game_new_started` | — | GameManager | TutorialManager, HelperPanel, AudioManager, StormSky, NotificationPanel, SandboxPanel, TitleMenu |
| `game_load_completed` | — | GameManager | ArmyManager, ProcessManager, StormManager, ArmyPanel, SkirmishPanel, BattleScreen, HelperPanel, AudioManager, TutorialManager, StormSky, AuditDefeatScreen, NotificationPanel, SandboxPanel, TitleMenu |

## Tutorial

Emitted only by `TutorialManager`, except `tutorial_intro_closed`, which the panel
emits back. The manager decides **what** is taught and **when**; the panels only
paint what arrives, so the manager knows no panel and can be tested without a
scene. Full detail of the prologue, the guided tutorial and the help callouts:
[23-onboarding.md](23-onboarding.md).

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `tutorial_intro_requested` | — | TutorialManager | TutorialPanel, NotificationPanel |
| `tutorial_tip_requested` | `tip_id: String, title: String, body: String` | TutorialManager | HelperPanel |
| `tutorial_intro_closed` | — | TutorialPanel | TutorialManager, NotificationPanel, PauseMenu |
| `tutorial_step_changed` | `step_id: String` (`""` = no step on screen) | TutorialManager | TutorialPanel |
| `tutorial_guide_finished` | `skipped: bool` | TutorialManager | TutorialPanel, HelperPanel |
| `help_reopen_requested` | `help_id: String` (a `HelpCatalog` id) | TutorialManager | HelperPanel |
| `combat_lesson_step_changed` | `step_id: String` (a `TutorialManager.COMBAT_STEPS` id, `""` = none) | TutorialManager | TutorialPanel, BattleScreen |

The tip text arrives already translated so the panel does not have to know what it
is about. `tutorial_intro_closed` is what marks the prologue as seen, whether it was
read or skipped — insisting again would be punishing the "Skip" button.
`tutorial_intro_requested` / `tutorial_intro_closed` kept their names from when the
intro was a paged modal; today they open and close the `PrologueScreen`.

## Game modes

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `run_ended` | `result: String` | ProgressionManager (Survival: Final Audit lost) | GameManager (writes the sealed save one last time) |
| `sandbox_invoked` | `what: String` (`"storm"` / `"audit"`) | StormManager, ProgressionManager | *(no listener)* |

See [20-modos-de-juego.md](20-modos-de-juego.md).

## Governor rank

Emitted only by `RankManager`. XP comes from the signals above; the rank is derived
from it ([06-progression-victory.md](06-progression-victory.md) §Governor rank).

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `governor_xp_changed` | `xp: int, rank: int, gained: int` (`gained` 0 on load) | RankManager | RankPanel |
| `governor_rank_up` | `rank: int, rewards: Dictionary` (merged `rank_rewards` of every rank crossed) | RankManager | RankPanel, ConstructionMenu, AudioManager |
| `colony_identity_changed` | `colony_name: String, flag_spec: Dictionary` (ColonyFlag recipe: `pattern`, `emblem`, `colors` [field 1, field 2, emblem]) | RankManager (`set_colony()`, load) | RankPanel, ColonyFlag3D, ColonyFlag2D, ColonyByline (war reports, audit defeat, victory, board header) |

## Encargos

Los emite solo `ContractManager`, que publica lo que devuelve el modelo puro
`ContractBoard` ([27-encargos.md](27-encargos.md)). `source` es `"regency"`,
`"neighbors"` o `"smuggler"`; `contract` es el encargo entero (`id`, `source`,
`template`, `ask`, `reward`, `seconds_total`, `seconds_left`).

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `contract_offered` | `source: String, contract: Dictionary` | ContractManager | *(no listener: el panel escucha `contract_board_changed`)* |
| `contract_delivered` | `source: String, contract: Dictionary, reward: Dictionary` (ya pagado) | ContractManager (`deliver()`) | AudioManager (`milestone`) |
| `contract_expired` | `source: String, contract: Dictionary, reputation: int` | ContractManager | *(no listener)* |
| `contract_discarded` | `source: String, contract: Dictionary` | ContractManager (`discard()`) | *(no listener)* |
| `contract_board_changed` | — | ContractManager (cualquier evento, `load_save_data()`, `reset()`) | ContractPanel |

Los avisos al jugador van por `notification_posted` (nuevo encargo, cumplido, se
acabo el plazo); la XP de rango (`contract_rank_xp`) la suma ContractManager con
`RankManager.add_xp()`.

## Edificios militares

Rama `feat/edificios-militares` (1.2): la Herreria (doctrinas) y el Campo de tiro
(simulacro). Tres señales nuevas (143 con las 140 de arriba). Las emite solo
`ArmyManager`. La Enfermeria no tiene señal propia: su efecto va en el parte del
combate (`CombatManager.get_last_result()["recovered"]`).

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `doctrine_switch_started` | `doctrine_id: String, seconds: float` | ArmyManager (`choose_doctrine()`) | MilitarySection (ficha de la Herreria) |
| `doctrine_changed` | `doctrine_id: String` (`""` = ninguna) | ArmyManager (al acabar de aprenderla) | MilitarySection |
| `practice_lesson_completed` | `lesson_id: String, first_time: bool, reward: Dictionary` (ya pagado) | ArmyManager (`complete_practice()`, lo llama CombatManager al cerrar un simulacro ganado) | MilitarySection |

El simulacro usa las señales de siempre del tablero (`encounter_started`,
`encounter_ended`...): quien no debe contarlo como combate de verdad pregunta
`CombatManager.is_practice()` (ArmyManager para las estrellas del regimiento,
RankManager para la XP de "fight_won").
Con un Telégrafo en pie (1.2) hay un cuarto hueco, `source = "telegraph"`
(`ContractBoard.WIRE`): su encargo lleva además `from` (la fuente real).

## Defensa y vida (1.2, `feat/edificios-defensa-vida`)

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `beauty_changed` | — | ProductionManager (`_refresh_areas`, cuando `DefenseLifeEffects.refresh()` cambia la belleza de alguna casa) | BuildingPlacer (`_sync_beauty`, adornos `BeautyTrim`), TutorialManager (ayuda `beauty`) |
| `scrap_salvaged` | `steel: int, parts: int, lifted: int` | StormManager (`_scrap_salvage`, al acabar la Tormenta) | *(no listener: el aviso va por `notification_posted`)* |

## Orphan signals

Declared in `EventBus.gd` but not wired on one or both sides. Most are suppressed
with `@warning_ignore("unused_signal")`, so the editor will not flag them; this
list is the only record.

**Of the 127 signals, at least 10** have a gap on one side or the other.

### Neither emitted nor consumed (3)

Dead declarations. Nothing would change today if they were deleted.

| Signal | Note |
|--------|------|
| `building_removed` | Marked `# reserved: future use` in `EventBus.gd`. `building_demolished` does the job today |
| `ground_clicked` | The whole "Ground Interaction" block is reserved for future terrain interaction |
| `ground_hover` | Same |

### No emitter, but listeners already waiting (1)

Wiring that will start working the day something fires it.

| Signal | Listeners | Note |
|--------|-----------|------|
| `objective_panel_toggled` | ObjectivePanel | The panel listens for a toggle nobody emits |

`building_placement_cancelled` used to be here; it is now emitted by
`BuildingPlacer`, `BuildingPlacer2D`, `OnScreenControls` and `PauseMenu` (the menu
cancels a placement before it opens).

### Emitted, but no listener in `scripts/` (6)

| Signal | Emitter | Note |
|--------|---------|------|
| `population_starved` | PopulationManager | Only `tests/economy/test_starvation_desertion.gd` listens. The player hears about a famine through `notification_posted`, not through this |
| `unit_training_started` | ArmyManager | `ArmyPanel` polls `ArmyManager` instead of listening |
| `unit_training_cancelled` | ArmyManager | Same |
| `random_event_ended` | RandomEventManager | Timed effects expire inside the manager; nothing reacts to the end |
| `sandbox_invoked` | StormManager, ProgressionManager | Informative only; nothing listens yet |
| `stock_spoiled` | ProductionManager | Only `tests/economy/test_food_farm_collect.gd` listens; the badge and icon see the loss through `building_stock_changed` |

`consumption_failed` (now read by TutorialManager) and `building_damaged` (now read
by AuditDefeatScreen) used to be on this list.

Not on this list, despite looking thin in the tables above: `process_started`,
`mining_started`, `process_cancelled`, `construction_started` and
`building_upgrade_started` each have exactly one consumer, `BuildingStatusBadge`,
which connects through a `var bus := EventBus` alias. They are wired.
