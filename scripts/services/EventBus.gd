extends Node
## Global signal bus for decoupled communication between systems.
## All game-wide events flow through here. Systems emit signals, others subscribe.
## Signals are emitted/connected from external scripts, so we suppress unused warnings.

# ── Camera ──
@warning_ignore("unused_signal")
signal camera_pan_requested(direction: Vector2)
@warning_ignore("unused_signal")
signal camera_zoom_requested(amount: float)
@warning_ignore("unused_signal")
signal camera_drag_moved(delta: Vector2)
## World-space grab-pan: move the camera's ground target by an XZ delta (in world units).
@warning_ignore("unused_signal")
signal camera_drag_world_requested(delta: Vector2)
@warning_ignore("unused_signal")
signal camera_rotate_requested(amount: float)
## Discrete camera rotation: snap the yaw by a fixed number of degrees per press.
@warning_ignore("unused_signal")
signal camera_rotate_step_requested(degrees: float)

# ── Resources ──
@warning_ignore("unused_signal")
signal resource_changed(resource_type: String, new_amount: int, delta: int)
@warning_ignore("unused_signal")
signal resources_insufficient(resource_type: String, required: int, available: int)

# ── Buildings ──
@warning_ignore("unused_signal")
signal building_selected_for_placement(building_data: Resource)
@warning_ignore("unused_signal")
signal building_placement_cancelled()  # reserved: BuildingPlacer cancel flow
@warning_ignore("unused_signal")
signal building_placed(building_data: Resource, cell: Vector2i)
@warning_ignore("unused_signal")
signal building_moved(from_cell: Vector2i, to_cell: Vector2i)
@warning_ignore("unused_signal")
signal building_removed(cell: Vector2i)  # reserved: future use

# ── Selection ──
@warning_ignore("unused_signal")
signal building_clicked(building_node: Node3D, building_data: Resource)
@warning_ignore("unused_signal")
signal building_deselected()
@warning_ignore("unused_signal")
signal deposit_clicked(deposit_node: Node3D, deposit_id: String, cell: Vector2i)
@warning_ignore("unused_signal")
signal request_move_building(building_node: Node3D)
@warning_ignore("unused_signal")
signal building_renamed(building_node: Node3D, new_name: String)
@warning_ignore("unused_signal")
signal building_rotate_requested()

# ── Processes & Mining ──
@warning_ignore("unused_signal")
signal process_started(building_node: Node3D, process_id: String)
@warning_ignore("unused_signal")
signal process_completed(building_node: Node3D, process_id: String)
@warning_ignore("unused_signal")
signal mining_started(deposit_node: Node3D, deposit_id: String)
@warning_ignore("unused_signal")
signal mining_completed(deposit_node: Node3D, deposit_id: String)

# ── Construction ──
@warning_ignore("unused_signal")
signal construction_started(building_node: Node3D)
@warning_ignore("unused_signal")
signal construction_completed(building_node: Node3D)

# ── Production ──
@warning_ignore("unused_signal")
signal production_tick(building_node: Node3D)

# ── Upgrades ──
@warning_ignore("unused_signal")
signal building_upgrade_started(building_node: Node3D, new_level: int)
@warning_ignore("unused_signal")
signal building_upgrade_completed(building_node: Node3D, new_level: int)

# ── Demolish ──
@warning_ignore("unused_signal")
signal request_demolish_building(building_node: Node3D)
@warning_ignore("unused_signal")
signal building_demolished(building_node: Node3D, cell: Vector2i)

# ── Deposits ──
@warning_ignore("unused_signal")
signal deposit_depleted(deposit_node: Node3D, deposit_id: String)

# ── Ground Interaction (reserved: future terrain interaction) ──
@warning_ignore("unused_signal")
signal ground_clicked(world_pos: Vector3, cell: Vector2i)
@warning_ignore("unused_signal")
signal ground_hover(world_pos: Vector3, cell: Vector2i)

# ── Market ──
@warning_ignore("unused_signal")
signal market_prices_updated(prices: Dictionary)
@warning_ignore("unused_signal")
signal market_trade_completed(resource: String, amount: int, is_buy: bool, total_price: int)

# ── Progression ──
@warning_ignore("unused_signal")
signal resource_unlocked(resource_name: String)
@warning_ignore("unused_signal")
signal era_advanced(new_era: int)
@warning_ignore("unused_signal")
signal milestone_completed(milestone_id: String)
@warning_ignore("unused_signal")
signal phase_advanced(new_phase: int)
@warning_ignore("unused_signal")
signal victory_achieved(stats: Dictionary)

# ── Population & Morale ──
@warning_ignore("unused_signal")
signal population_changed(current: int, max_pop: int)
@warning_ignore("unused_signal")
signal workers_changed(used: int, total: int)
@warning_ignore("unused_signal")
signal morale_changed(new_morale: int)
@warning_ignore("unused_signal")
signal consumption_failed(resource: String)

# ── Army ──
@warning_ignore("unused_signal")
signal unit_training_started(unit_id: String, duration: float)
@warning_ignore("unused_signal")
signal unit_trained(unit_id: String)
@warning_ignore("unused_signal")
signal army_changed()
@warning_ignore("unused_signal")
signal army_upkeep_unpaid(gold_short: int)

# ── Combat ──
## Emitted only by CombatManager. `side`: 0 = player, 1 = enemy.
## `result` on expedition_ended: 0 = victory, 1 = defeat, 2 = abandoned.
@warning_ignore("unused_signal")
signal expedition_started(expedition_id: int, node_count: int)
@warning_ignore("unused_signal")
signal expedition_node_selected(node_index: int)
@warning_ignore("unused_signal")
signal encounter_started(encounter_index: int, is_boss: bool)
@warning_ignore("unused_signal")
signal turn_started(side: int, unit_uid: int)
@warning_ignore("unused_signal")
signal unit_moved(unit_uid: int, from: Vector2i, to: Vector2i)
@warning_ignore("unused_signal")
signal unit_attacked(attacker_uid: int, target_uid: int, damage: int)
@warning_ignore("unused_signal")
signal unit_defended(unit_uid: int)
@warning_ignore("unused_signal")
signal unit_died(unit_uid: int, side: int)
@warning_ignore("unused_signal")
signal encounter_ended(victory: bool, turns_used: int)
@warning_ignore("unused_signal")
signal draft_offered(options: Array)
@warning_ignore("unused_signal")
signal draft_applied(option: Dictionary)
@warning_ignore("unused_signal")
signal expedition_ended(result: int, rewards: Dictionary, casualties: Dictionary)

# ── Imperial Storm ──
## Emitted only by StormManager. The storm is dispatched on a schedule, not rolled
## at random — the player is meant to see it coming and prepare (see the design in
## the private context folder).
## `phase` values follow StormCycle.Phase.
@warning_ignore("unused_signal")
signal storm_phase_changed(phase: int, seconds_left: float)
## The warning window opens: ash on the horizon, time to decide.
@warning_ignore("unused_signal")
signal storm_incoming(seconds_until: float, severity: int)
@warning_ignore("unused_signal")
signal storm_started(severity: int)
## Per-tick bite while the storm is overhead, for the UI to react to.
@warning_ignore("unused_signal")
signal storm_tick(seconds_left: float)
@warning_ignore("unused_signal")
signal storm_ended(severity: int)
## The Assessors arrive to collect. `taken` is resource_name -> amount.
@warning_ignore("unused_signal")
signal tithe_demanded(severity: int)
@warning_ignore("unused_signal")
signal tithe_resolved(paid: bool, taken: Dictionary)

# ── Random Events ──
@warning_ignore("unused_signal")
signal random_event_started(event_id: String, event_data: Dictionary)
@warning_ignore("unused_signal")
signal random_event_ended(event_id: String)

# ── Notifications ──
@warning_ignore("unused_signal")
signal notification_posted(message: String, category: String, color: Color)
@warning_ignore("unused_signal")
signal objective_panel_toggled()

# ── UI ──
@warning_ignore("unused_signal")
signal sidebar_toggled(visible: bool)
@warning_ignore("unused_signal")
signal grid_overlay_toggled(visible: bool)

# ── Persistence ──
@warning_ignore("unused_signal")
signal game_new_started()
@warning_ignore("unused_signal")
signal game_load_completed()
