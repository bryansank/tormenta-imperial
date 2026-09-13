extends Node
## Owner of the PVE combat domain: expeditions, encounters, turn order and
## resolution. Nothing else mutates combat state — the UI reads this API and
## reacts to EventBus signals (constitution, principles I and IV).
##
## ArmyManager stays the source of truth for the roster: units committed to an
## expedition are still counted there and are only deducted as casualties when
## the expedition resolves, so Military Power never lies mid-run.
##
## Current scope: encounter core (T012-T013). Expedition map, drafts and the
## economy bridge land in later tasks — see specs/001-combate-pve/tasks.md.

const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")

enum EncounterState { IDLE, DEPLOYING, PLAYER_TURN, ENEMY_TURN, WON, LOST }

var _units: Array = []              ## CombatUnit, both sides, alive and dead
var _turn_order: Array = []         ## uids, rebuilt each round
var _turn_index: int = 0
var _round: int = 1
var _state: int = EncounterState.IDLE
var _is_boss: bool = false
var _encounter_index: int = 0
var _next_uid: int = 1
var _morale_snapshot: float = 50.0

# ── Queries ──────────────────────────────────────────────────────────

func is_in_encounter() -> bool:
	return _state in [EncounterState.DEPLOYING, EncounterState.PLAYER_TURN, EncounterState.ENEMY_TURN]

func get_state() -> int:
	return _state

func get_round() -> int:
	return _round

func get_turn_limit() -> int:
	return GameConfig.combat_turn_limit

func get_board_size() -> Vector2i:
	return GameConfig.combat_board_size

func get_units() -> Array:
	return _units

func get_unit(uid: int) -> CombatUnit:
	for unit in _units:
		if unit.uid == uid:
			return unit
	return null

func get_unit_at(cell: Vector2i) -> CombatUnit:
	for unit in _units:
		if unit.is_alive() and unit.position == cell:
			return unit
	return null

func get_active_unit() -> CombatUnit:
	if _turn_index < 0 or _turn_index >= _turn_order.size():
		return null
	return get_unit(_turn_order[_turn_index])

func get_turn_order() -> Array:
	return _turn_order

func get_morale_snapshot() -> float:
	return _morale_snapshot

## Units the player may still commit: everything trained and not already deployed.
func get_deployable_units() -> Dictionary:
	var available: Dictionary = {}
	for unit_id in GameConfig.get_unit_ids():
		var count: int = ArmyManager.get_count(unit_id)
		if count > 0:
			available[unit_id] = count
	return available

# ── Encounter lifecycle ──────────────────────────────────────────────

## Builds both sides and opens the board. `party` and `enemy_roster` are
## unit_id -> count dictionaries.
func start_encounter(party: Dictionary, enemy_roster: Dictionary, is_boss: bool = false, encounter_index: int = 0) -> void:
	_units.clear()
	_turn_order.clear()
	_turn_index = 0
	_round = 1
	_is_boss = is_boss
	_encounter_index = encounter_index
	_state = EncounterState.DEPLOYING
	_morale_snapshot = _read_morale()

	var scale: float = GameConfig.combat_boss_multiplier if is_boss else 1.0
	_spawn_side(party, 0, 1.0)
	_spawn_side(enemy_roster, 1, scale)
	_deploy_units()

	EventBus.encounter_started.emit(_encounter_index, _is_boss)
	_begin_round()

func _spawn_side(roster: Dictionary, side: int, scale: float) -> void:
	for unit_id in roster.keys():
		for i in int(roster[unit_id]):
			var unit: CombatUnit = CombatUnitScript.create(_next_uid, unit_id, side, scale)
			_next_uid += 1
			if side == 0:
				unit.morale_attack_mod = Rules.morale_attack_mod(_morale_snapshot)
				unit.morale_initiative_bonus = Rules.morale_initiative_bonus(_morale_snapshot)
			_units.append(unit)

## Player deploys on the bottom rows, enemy on the top ones (FR-005).
func _deploy_units() -> void:
	var board: Vector2i = get_board_size()
	var rows := {0: [board.y - 1, board.y - 2], 1: [0, 1]}
	for side in [0, 1]:
		var cells: Array = []
		for row in rows[side]:
			for x in range(board.x):
				cells.append(Vector2i(x, row))
		var index := 0
		for unit in Rules.living_units(_units, side):
			# Spread units across the middle of their rows instead of the corner.
			var offset: int = (board.x - Rules.living_units(_units, side).size()) / 2
			var cell_index: int = index + maxi(0, offset)
			unit.position = cells[cell_index % cells.size()]
			index += 1

func _begin_round() -> void:
	for unit in _units:
		if unit.is_alive():
			unit.begin_turn()
	_turn_order = Rules.build_turn_order(_units)
	_turn_index = -1
	_advance_turn()

## Moves to the next living unit; wraps into a new round when the order is spent.
func _advance_turn() -> void:
	if _check_end_conditions():
		return
	_turn_index += 1
	while _turn_index < _turn_order.size():
		var unit := get_unit(_turn_order[_turn_index])
		if unit != null and unit.is_alive() and not unit.has_acted:
			_state = EncounterState.PLAYER_TURN if unit.side == 0 else EncounterState.ENEMY_TURN
			EventBus.turn_started.emit(unit.side, unit.uid)
			return
		_turn_index += 1
	_round += 1
	if _round > get_turn_limit():
		_finish_encounter(Rules.resolve_timeout(_units) == 0)
		return
	_begin_round()

func end_turn() -> void:
	var unit := get_active_unit()
	if unit != null:
		unit.has_acted = true
	_advance_turn()

func _check_end_conditions() -> bool:
	if not is_in_encounter():
		return true
	if Rules.living_units(_units, 1).is_empty():
		_finish_encounter(true)
		return true
	if Rules.living_units(_units, 0).is_empty():
		_finish_encounter(false)
		return true
	return false

func _finish_encounter(victory: bool) -> void:
	_state = EncounterState.WON if victory else EncounterState.LOST
	EventBus.encounter_ended.emit(victory, _round)

# ── Player actions ───────────────────────────────────────────────────

func get_valid_moves(uid: int) -> Array:
	var unit := get_unit(uid)
	if unit == null or not unit.is_alive() or unit.moved_this_turn:
		return []
	return Rules.reachable_cells(
		unit.position, unit.move_range(), get_board_size(), Rules.occupied_cells(_units, uid)
	)

func get_valid_targets(uid: int) -> Array:
	var unit := get_unit(uid)
	if unit == null or not unit.is_alive() or unit.has_acted:
		return []
	var targets: Array = []
	for other in _units:
		if other.is_alive() and other.side != unit.side and Rules.in_attack_range(unit, other):
			targets.append(other.uid)
	return targets

func move_unit(uid: int, to: Vector2i) -> bool:
	var unit := get_unit(uid)
	if unit == null or not get_valid_moves(uid).has(to):
		return false
	var from := unit.position
	unit.position = to
	unit.moved_this_turn = true
	EventBus.unit_moved.emit(uid, from, to)
	return true

func attack(uid: int, target_uid: int) -> bool:
	var attacker := get_unit(uid)
	var target := get_unit(target_uid)
	if attacker == null or target == null or not get_valid_targets(uid).has(target_uid):
		return false
	var dealt: int = Rules.damage(attacker, target)
	target.take_damage(dealt)
	attacker.has_acted = true
	EventBus.unit_attacked.emit(uid, target_uid, dealt)
	if not target.is_alive():
		target.position = Vector2i(-1, -1)
		EventBus.unit_died.emit(target_uid, target.side)
	_advance_turn()
	return true

func defend(uid: int) -> void:
	var unit := get_unit(uid)
	if unit == null:
		return
	unit.defending = true
	unit.has_acted = true
	EventBus.unit_defended.emit(uid)
	_advance_turn()

func wait_unit(uid: int) -> void:
	var unit := get_unit(uid)
	if unit == null:
		return
	unit.has_acted = true
	_advance_turn()

# ── Dev helper (T014) ────────────────────────────────────────────────

## Starts a standalone encounter with whatever the player has trained, so the
## board can be exercised before the expedition layer exists.
func dev_start_encounter() -> bool:
	if not GameConfig.dev_mode:
		return false
	var party: Dictionary = {}
	var committed := 0
	for unit_id in GameConfig.get_unit_ids():
		var count: int = ArmyManager.get_count(unit_id)
		for i in count:
			if committed >= GameConfig.combat_deploy_cap:
				break
			party[unit_id] = int(party.get(unit_id, 0)) + 1
			committed += 1
	if party.is_empty():
		return false
	start_encounter(party, {"infantry": 2, "artillery": 1}, false, 0)
	return true

# ── Persistence ──────────────────────────────────────────────────────

func _read_morale() -> float:
	if PopulationManager.has_method("get_morale"):
		return float(PopulationManager.get_morale())
	return 50.0

## No expedition layer yet, so nothing persists. Kept so GameManager can wire the
## save slot now and stay backward compatible when expeditions land (T036).
func get_save_data() -> Dictionary:
	return {}

func load_save_data(_data: Dictionary) -> void:
	pass

func reset() -> void:
	_units.clear()
	_turn_order.clear()
	_turn_index = 0
	_round = 1
	_state = EncounterState.IDLE
	_next_uid = 1
