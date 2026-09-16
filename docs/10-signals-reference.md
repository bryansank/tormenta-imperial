# EventBus Signals Reference

All inter-system communication flows through `EventBus` (`scripts/services/EventBus.gd`). Systems emit signals; others subscribe. No direct references between services.

**97 signals**, in the order they are declared in `EventBus.gd`. Emitters and
consumers below were read out of `scripts/` — tests that emit or listen for a
signal are **not** counted as wiring, because a signal only exercised by a test is
not wired in the game.

Three patterns count as a connection, and all three are included here:

- `EventBus.<signal>.connect(...)` — the normal case.
- `var bus := EventBus` then `bus.<signal>.connect(...)` — `BuildingStatusBadge`.
- `EventBus.connect("<signal>", ...)` — `ArmyPanel`, `BattleScreen`, `SkirmishPanel`
  use the string form for `expedition_resumed`, and `AudioManager._connect_optional()`
  uses it for the two Final Audit signals it guards with `has_signal()`.

Rows marked *(no emitter)* or *(no listener)* are declared but not wired on that
side. That is recorded on purpose: see [Orphan signals](#orphan-signals) for the
full list and why each one is there.

## Camera

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `camera_pan_requested` | `direction: Vector2` | InputService, OnScreenControls | MonumentalCamera |
| `camera_zoom_requested` | `amount: float` | InputService, OnScreenControls | MonumentalCamera |
| `camera_drag_moved` | `delta: Vector2` | InputService | MonumentalCamera |
| `camera_drag_world_requested` | `delta: Vector2` (world XZ) | InputService (touch grab-pan), BuildingPlacer (left-drag grab-pan) | MonumentalCamera |
| `camera_rotate_requested` | `amount: float` | InputService | MonumentalCamera |
| `camera_rotate_step_requested` | `degrees: float` | OnScreenControls | MonumentalCamera |

Touch and mouse share `camera_drag_world_requested` on purpose: one finger and the
left button go through the same screen→world conversion
(`InputService.screen_drag_to_world_delta`), so they cannot drift apart.

## Resources

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `resource_changed` | `resource_type: String, new_amount: int, delta: int` | ResourceManager | ResourceHUD, ProgressionManager |
| `resources_insufficient` | `resource_type: String, required: int, available: int` | ResourceManager, MarketManager | ResourceHUD, AudioManager |
| `storage_overflow` | `resource_type: String, lost: int, cap: int` | ResourceManager | TutorialManager |

`storage_overflow` fires when the shared pool was full and `lost` units did not
fit. The player is warned once per game, via a TutorialManager tip.

## Buildings

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `building_selected_for_placement` | `building_data: Resource` | ConstructionMenu | BuildingPlacer, BuildingInfoPanel, OnScreenControls |
| `building_placement_cancelled` | — | *(no emitter)* | BuildingPlacer, OnScreenControls |
| `building_placed` | `building_data: Resource, cell: Vector2i` | BuildingPlacer | ProductionManager, GameManager, ProgressionManager, ArmyPanel, SkirmishPanel, HelperPanel, OnScreenControls, AudioManager |
| `building_moved` | `from_cell: Vector2i, to_cell: Vector2i` | BuildingPlacer | GameManager |
| `building_removed` | `cell: Vector2i` | *(no emitter)* | *(no listener)* |

## Selection

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `building_clicked` | `building_node: Node3D, building_data: Resource` | BuildingPlacer | BuildingInfoPanel, BuildingPlacer |
| `building_deselected` | — | BuildingPlacer | BuildingInfoPanel, BuildingPlacer, OnScreenControls |
| `deposit_clicked` | `deposit_node: Node3D, deposit_id: String, cell: Vector2i` | BuildingPlacer | BuildingInfoPanel |
| `request_move_building` | `building_node: Node3D` | BuildingInfoPanel | BuildingPlacer |
| `building_renamed` | `building_node: Node3D, new_name: String` | BuildingInfoPanel | GameManager |
| `building_rotate_requested` | — | OnScreenControls | BuildingPlacer |

## Processes & Mining

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `process_started` | `building_node: Node3D, process_id: String` | ProcessManager | BuildingStatusBadge |
| `process_completed` | `building_node: Node3D, process_id: String` | ProcessManager | BuildingInfoPanel, BuildingStatusBadge, AudioManager |
| `mining_started` | `deposit_node: Node3D, deposit_id: String` | ProcessManager | BuildingStatusBadge |
| `mining_completed` | `deposit_node: Node3D, deposit_id: String` | ProcessManager | MapGenerator, BuildingInfoPanel, BuildingStatusBadge, AudioManager |
| `process_cancelled` | `building_node: Node3D, process_id: String, refunded: Dictionary` | ProcessManager | BuildingStatusBadge |

`refunded` on `process_cancelled` is resource → amount **already applied**: it is
what the UI promised before confirming, and what was actually paid back.

## Construction

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `construction_started` | `building_node: Node3D` | ProductionManager | BuildingStatusBadge |
| `construction_completed` | `building_node: Node3D` | ProductionManager | BuildingInfoPanel, ProgressionManager, PopulationManager, BuildingStatusBadge, AudioManager |

## Production

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `production_tick` | `building_node: Node3D` | ProductionManager | TechTreeManager, BuildingStatusBadge |

## Upgrades

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `building_upgrade_started` | `building_node: Node3D, new_level: int` | ProductionManager | BuildingStatusBadge |
| `building_upgrade_completed` | `building_node: Node3D, new_level: int` | ProductionManager | BuildingInfoPanel, ProgressionManager, PopulationManager, BuildingStatusBadge, AudioManager |

## Demolish

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `request_demolish_building` | `building_node: Node3D` | BuildingInfoPanel | BuildingPlacer |
| `building_demolished` | `building_node: Node3D, cell: Vector2i` | BuildingPlacer | GameManager, PopulationManager, BuildingInfoPanel, ArmyPanel, SkirmishPanel, HelperPanel, AudioManager |

## Deposits

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `deposit_depleted` | `deposit_node: Node3D, deposit_id: String` | MapGenerator | BuildingInfoPanel |

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
| `consumption_failed` | `resource: String` | PopulationManager | *(no listener)* |
| `population_starved` | `deaths: int, population: int` | PopulationManager | *(no listener)* |

`population_starved` reports a famine that actually killed: `deaths` is how many
died, `population` what is left afterwards (never below the floor).

## Army

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `unit_training_started` | `unit_id: String, duration: float` | ArmyManager | *(no listener)* |
| `unit_trained` | `unit_id: String` | ArmyManager | AudioManager |
| `army_changed` | — | ArmyManager | ArmyPanel, SkirmishPanel, HelperPanel |
| `army_upkeep_unpaid` | `gold_short: int` | ArmyManager | ArmyPanel |
| `unit_training_cancelled` | `unit_id: String, refunded: Dictionary` | ArmyManager | *(no listener)* |
| `army_deserted` | `unit_id: String, count: int` | ArmyManager | PopulationManager |

`army_upkeep_unpaid` is the warning; `army_deserted` is the bill — sustained
unpaid upkeep loses the most expensive unit first.

## Combat

Emitted only by `CombatManager`. `side`: 0 = player, 1 = enemy.

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `expedition_started` | `expedition_id: int, node_count: int` | CombatManager | BattleScreen, SkirmishPanel, ArmyPanel, NotificationPanel, AudioManager |
| `expedition_node_selected` | `node_index: int` | CombatManager | BattleScreen, SkirmishPanel |
| `encounter_started` | `encounter_index: int, is_boss: bool` | CombatManager | BattleScreen, SkirmishPanel, TutorialManager, AudioManager |
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
| `defense_auto_resolved` | `victory: bool, rounds: int, summary: Dictionary` | CombatManager | *(no listener)* |

`result` on `expedition_ended`: 0 = victory, 1 = defeat, 2 = abandoned.

`expedition_resumed` is connected with the string form
(`EventBus.connect("expedition_resumed", ...)`) in all three panels. It fires when
a save with a campaign in flight is loaded, so the UI can reopen the map on the
current node; the board itself is never saved, so there is never an open encounter
waiting behind it.

`defense_auto_resolved` covers the garrison fighting alone: the Tithe landed while
an expedition held the board, so the defence was resolved blind through
`AutoResolver`. `summary` is `CombatManager.get_last_result()`. It is the **only**
signal that fight emits — no `encounter_*`, `turn_started` or `unit_*` accompanies
it, because the open board would claim them as its own. `StormManager` reads the
return value of `auto_resolve_defense()` directly instead of listening.

Full design: [15-combat.md](15-combat.md).

## Building Health

Emitted only by `BuildingHealth`. A ruined building stays where it is and stops
producing until the repair is paid; it is never destroyed on its own.

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `building_damaged` | `building_node: Node3D, health: int, max_health: int` | BuildingHealth | *(no listener)* |
| `building_ruined` | `building_node: Node3D` | BuildingHealth | BuildingStatusBadge, TutorialManager |
| `building_repaired` | `building_node: Node3D` | BuildingHealth | BuildingStatusBadge |

## Imperial Storm

Emitted only by `StormManager`. The storm is dispatched on a schedule, not rolled
at random — the player is meant to see it coming and prepare. `phase` values
follow `StormCycle.Phase`.

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `storm_phase_changed` | `phase: int, seconds_left: float` | StormManager | StormHUD |
| `storm_incoming` | `seconds_until: float` | StormManager | StormHUD, StormSky, HelperPanel, TutorialManager |
| `storm_false_alarm` | `deferred: int` | StormManager | StormHUD, StormSky, HelperPanel |
| `storm_ash_started` | — | StormManager | ProcessManager, ArmyManager, StormHUD, StormSky, TutorialManager |
| `storm_started` | `severity: int` | StormManager | ProcessManager, ArmyManager, StormHUD, StormSky, TutorialManager |
| `storm_tick` | `phase: int, seconds_left: float` | StormManager | StormHUD |
| `storm_ended` | `severity: int` | StormManager | ProcessManager, ArmyManager, StormHUD, StormSky |
| `tithe_demanded` | `severity: int` | StormManager | TutorialManager |
| `tithe_resolved` | `paid: bool, taken: Dictionary` | StormManager | StormHUD, HelperPanel |

`storm_incoming` carries no severity on purpose — the warning window says the ash
is on the horizon, and the size of the bill is only announced with `storm_started`.
A warning that comes to nothing emits `storm_false_alarm(deferred)`, and `deferred`
is the severity the next real storm inherits: postponed, not forgiven.
`taken` on `tithe_resolved` is resource → amount.

## The Final Audit

Emitted only by `ProgressionManager`. HQ level 3 no longer wins the game: it
summons the Regency's definitive audit, and surviving it is the victory. A siege is
3–5 consecutive waves against the same garrison.

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `final_audit_summoned` | `waves: int, summons: int` | ProgressionManager | SkirmishPanel, AudioManager *(optional connect)* |
| `final_audit_started` | `waves: int` | ProgressionManager | SkirmishPanel |
| `final_audit_wave_ready` | `wave: int, roster: Dictionary, scale: float` | ProgressionManager | CombatManager |
| `final_audit_wave_cleared` | `wave: int, remaining: int` | ProgressionManager | *(no listener)* |
| `final_audit_lost` | `wave: int` | ProgressionManager | StormManager, SkirmishPanel |
| `storm_halted_forever` | — | ProgressionManager | StormManager, StormSky, SkirmishPanel, AudioManager *(optional connect)* |

`final_audit_wave_ready` is the seam of the siege: the model says which wave it is
and with how much weight, and whoever drives the board is the one that calls
`CombatManager.start_defense()`. Nobody else.

`final_audit_lost` is not a game over — the maximum Tithe is collected and the town
is left in ruins, but the siege can be summoned again once the army is rebuilt.

`storm_halted_forever` stops the Storm for good, and nothing else has permission to
stop the cycle. AudioManager wires both optional rows through `_connect_optional()`,
which is guarded by `EventBus.has_signal()`.

## Random Events

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `random_event_started` | `event_id: String, event_data: Dictionary` | RandomEventManager | AudioManager |
| `random_event_ended` | `event_id: String` | RandomEventManager | *(no listener)* |

## Notifications

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `notification_posted` | `message: String, category: String, color: Color` | 15 scripts — every manager plus ArmyPanel, SkirmishPanel and NotificationPanel itself | NotificationPanel, TechTreePanel |
| `objective_panel_toggled` | — | *(no emitter)* | ObjectivePanel |

`notification_posted` is the one genuinely global signal: ArmyManager, ArmyPanel,
BuildingPlacer, CloudSaveManager, CombatManager, MapGenerator, NotificationPanel,
PopulationManager, ProcessManager, ProductionManager, RandomEventManager,
ResourceManager, SkirmishPanel, StormManager and TechTreeManager all post to it.
TechTreePanel listens only to refresh its tech states on any message.

## UI

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `sidebar_toggled` | `visible: bool` | MarketPanel | ArmyPanel, ConstructionMenu, HelperPanel, MarketPanel, ObjectivePanel, ProgressPanel, SettingsPanel, SkirmishPanel, TechTreePanel |
| `grid_overlay_toggled` | `visible: bool` | SettingsPanel | GridOverlayControl |
| `fullscreen_changed` | `enabled: bool` | GameConfig | SettingsPanel |

`sidebar_toggled` has one emitter and nine listeners: `MarketPanel` owns the
sidebar, and every other panel just shifts out of its way.

## Persistence

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `game_new_started` | — | GameManager | TutorialManager, HelperPanel, AudioManager |
| `game_load_completed` | — | GameManager | ArmyManager, ProcessManager, StormManager, ArmyPanel, SkirmishPanel, BattleScreen, HelperPanel, AudioManager, TutorialManager |

## Tutorial

Emitted only by `TutorialManager`, except `tutorial_intro_closed`, which the panel
emits back. The manager decides **what** is taught and **when**; `TutorialPanel`
only paints what arrives, so the manager knows no panel and can be tested without a
scene.

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `tutorial_intro_requested` | — | TutorialManager | TutorialPanel, NotificationPanel |
| `tutorial_tip_requested` | `tip_id: String, title: String, body: String` | TutorialManager | TutorialPanel |
| `tutorial_intro_closed` | — | TutorialPanel | TutorialManager, NotificationPanel |

The tip text arrives already translated so the panel does not have to know what it
is about. `tutorial_intro_closed` is what marks the intro as seen, whether it was
read or skipped — insisting again would be punishing the "Skip" button.

## Orphan signals

Declared in `EventBus.gd` but not wired on one or both sides. All of them are
suppressed with `@warning_ignore("unused_signal")`, so the editor will not flag
them; this list is the only record.

**13 of the 97 signals** have a gap on one side or the other.

### Neither emitted nor consumed (3)

Dead declarations. Nothing would change today if they were deleted.

| Signal | Note |
|--------|------|
| `building_removed` | Marked `# reserved: future use` in `EventBus.gd`. `building_demolished` does the job today |
| `ground_clicked` | The whole "Ground Interaction" block is reserved for future terrain interaction |
| `ground_hover` | Same |

### No emitter, but listeners already waiting (2)

Wiring that will start working the day something fires it.

| Signal | Listeners | Note |
|--------|-----------|------|
| `building_placement_cancelled` | BuildingPlacer, OnScreenControls | Marked `# reserved: BuildingPlacer cancel flow`. Both consumers are connected; nothing ever emits it |
| `objective_panel_toggled` | ObjectivePanel | The panel listens for a toggle nobody emits |

### Emitted, but no listener in `scripts/` (8)

| Signal | Emitter | Note |
|--------|---------|------|
| `consumption_failed` | PopulationManager | Superseded in practice by `population_starved` and by direct notifications |
| `population_starved` | PopulationManager | Only `tests/economy/test_starvation_desertion.gd` listens. The player hears about a famine through `notification_posted`, not through this |
| `unit_training_started` | ArmyManager | `ArmyPanel` polls `ArmyManager` instead of listening |
| `unit_training_cancelled` | ArmyManager | Same |
| `building_damaged` | BuildingHealth | `BuildingStatusBadge` reacts to `building_ruined` and `building_repaired` but not to partial damage — a scratch gets no icon |
| `defense_auto_resolved` | CombatManager | Only `tests/storm/test_defense_auto_resolve.gd` listens. `StormManager` reads the return value of `auto_resolve_defense()` directly and posts its own notification. The signal is there for a proper after-action report that has not been built |
| `final_audit_wave_cleared` | ProgressionManager | There is no wave-by-wave readout; `SkirmishPanel` refreshes from `final_audit_started` / `final_audit_lost` instead |
| `random_event_ended` | RandomEventManager | Timed effects expire inside the manager; nothing reacts to the end |

Not on this list, despite looking thin in the tables above: `process_started`,
`mining_started`, `process_cancelled`, `construction_started` and
`building_upgrade_started` each have exactly one consumer, `BuildingStatusBadge`,
which connects through a `var bus := EventBus` alias. They are wired.
