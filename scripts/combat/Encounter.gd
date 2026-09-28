extends RefCounted
class_name Encounter
## One battle on one node of the map: the board, both sides, the turn order and
## the win conditions. Pure state — no nodes, no EventBus, no timers — so a whole
## encounter can be played out headless in a test.
##
## Every mutating method returns an Array of event dictionaries instead of
## emitting signals. CombatManager drains that list and republishes it on the
## EventBus (constitution, principle IV). That is what keeps this file testable.

const Rules := preload("res://scripts/combat/CombatRules.gd")

enum State { DEPLOYING, PLAYER_TURN, ENEMY_TURN, WON, LOST, TIMEOUT }

const PLAYER := 0
const ENEMY := 1

var board_size: Vector2i = Vector2i(8, 8)
var units: Array = []                ## CombatUnit, both sides, alive and dead
var turn_order: Array = []           ## uids, rebuilt every round
var turn_index: int = -1
var round_number: int = 1
var turn_limit: int = 20
var is_boss: bool = false
## True when the player is being attacked at home instead of marching out. It
## changes who starts where, and what losing costs — see _rows_for().
var is_defense: bool = false
## uids que forman en la retaguardia en vez de en la linea. Hoy son las
## dotaciones de torre: artilleria con alcance minimo 2, que en cabeza se queda
## muda en cuanto el enemigo llega a contacto.
var back_row_uids: Dictionary = {}
var index: int = 0
var state: int = State.DEPLOYING
var deploy_zones: Dictionary = {}    ## side -> Array[Vector2i]

# ── Construction ─────────────────────────────────────────────────────

## `units` arrive already built (CombatUnit instances) so the expedition can hand
## over survivors carrying their damage from the previous node (FR-011).
static func create(p_units: Array, p_index: int, p_is_boss: bool, p_is_defense: bool = false, p_back_row: Array = []) -> Encounter:
	var e := Encounter.new()
	e.units = p_units
	e.index = p_index
	e.is_boss = p_is_boss
	e.is_defense = p_is_defense
	for uid in p_back_row:
		e.back_row_uids[int(uid)] = true
	e.board_size = GameConfig.combat_board_size
	e.turn_limit = GameConfig.combat_turn_limit
	e._build_deploy_zones()
	e._deploy()
	return e

## Player holds the bottom two rows, the enemy the top two (FR-005). Keeping the
## sides apart is what gives the first rounds their approach phase.
##
## Each side's rows are listed front first — the row facing the enemy — because
## that is the order units fill them in.
## Defending at home is worth something: the attackers form up on the far edge
## instead of the near one, which buys the defender a round of approach to place
## themselves. It is the only advantage the player gets for being attacked, and
## without it a defence is just an expedition with worse stakes.
func _rows_for(side: int) -> Array:
	if side == PLAYER:
		return [board_size.y - 2, board_size.y - 1]
	return [0, 1] if is_defense else [1, 0]

func _build_deploy_zones() -> void:
	deploy_zones = {PLAYER: [], ENEMY: []}
	for side in [PLAYER, ENEMY]:
		for row in _rows_for(side):
			for x in range(board_size.x):
				deploy_zones[side].append(Vector2i(x, row))

## Fills the front row before the back one and centres each row, so a squad opens
## as a line facing the enemy instead of a zigzag across two rows.
func _deploy() -> void:
	for side in [PLAYER, ENEMY]:
		var rows: Array = _rows_for(side)
		var rear: Array = []
		var line: Array = []
		for unit in Rules.living_units(units, side):
			if back_row_uids.has(unit.uid):
				rear.append(unit)
			else:
				line.append(unit)

		var taken: Dictionary = {}
		# La retaguardia coge la fila de atras ANTES de que forme la linea, porque
		# el bando entero suele caber en la primera fila: si se repartiera por
		# orden, nadie llegaria nunca atras.
		if not rear.is_empty():
			_fill_row(rear, int(rows[rows.size() - 1]), taken)
		for row in rows:
			if line.is_empty():
				break
			_fill_row(line, int(row), taken)

## Centra en esa fila a los que quepan y los saca de `pending`. Respeta las
## celdas ya ocupadas, para que la linea no aplaste a la retaguardia al desbordar.
func _fill_row(pending: Array, row: int, taken: Dictionary) -> void:
	var free: Array = []
	for x in range(board_size.x):
		var cell := Vector2i(x, row)
		if not taken.has(cell):
			free.append(cell)
	var count: int = mini(pending.size(), free.size())
	if count <= 0:
		return
	var offset: int = maxi(0, (free.size() - count) / 2)
	for i in range(count):
		var cell: Vector2i = free[offset + i]
		pending[0].position = cell
		taken[cell] = true
		pending.remove_at(0)

# ── Queries ──────────────────────────────────────────────────────────

func is_active() -> bool:
	return state in [State.DEPLOYING, State.PLAYER_TURN, State.ENEMY_TURN]

func is_resolved() -> bool:
	return not is_active()

func player_won() -> bool:
	return state == State.WON

func get_unit(uid: int) -> CombatUnit:
	for unit in units:
		if unit.uid == uid:
			return unit
	return null

func get_unit_at(cell: Vector2i) -> CombatUnit:
	for unit in units:
		if unit.is_alive() and unit.position == cell:
			return unit
	return null

func active_unit() -> CombatUnit:
	if turn_index < 0 or turn_index >= turn_order.size():
		return null
	return get_unit(turn_order[turn_index])

func living(side: int) -> Array:
	return Rules.living_units(units, side)

func survivors() -> Array:
	return Rules.living_units(units, PLAYER)

func casualties(side: int) -> Array:
	var fallen: Array = []
	for unit in units:
		if unit.side == side and not unit.is_alive():
			fallen.append(unit)
	return fallen

func valid_moves(uid: int) -> Array:
	var unit := get_unit(uid)
	if unit == null or not unit.is_alive() or unit.moved_this_turn or unit.has_acted:
		return []
	return Rules.reachable_cells(
		unit.position, unit.move_range(), board_size, Rules.occupied_cells(units, uid)
	)

func valid_targets(uid: int) -> Array:
	var unit := get_unit(uid)
	if unit == null or not unit.is_alive() or unit.has_acted:
		return []
	var targets: Array = []
	for other in units:
		if other.is_alive() and other.side != unit.side and Rules.in_attack_range(unit, other):
			targets.append(other.uid)
	return targets

# ── Turn flow ────────────────────────────────────────────────────────

## Opens the encounter. Call once, right after create().
func start() -> Array:
	return _begin_round()

func _begin_round() -> Array:
	for unit in units:
		if unit.is_alive():
			unit.begin_turn()
	turn_order = Rules.build_turn_order(units)
	turn_index = -1
	return _advance()

## Walks to the next unit that can still act, rolling into a new round when the
## order is spent. Resolves the encounter when a side is wiped or time runs out.
func _advance() -> Array:
	var events: Array = []
	var ending := _check_resolution()
	if not ending.is_empty():
		return ending
	turn_index += 1
	while turn_index < turn_order.size():
		var unit := get_unit(turn_order[turn_index])
		if unit != null and unit.is_alive() and not unit.has_acted:
			state = State.PLAYER_TURN if unit.side == PLAYER else State.ENEMY_TURN
			events.append({"e": "turn_started", "side": unit.side, "uid": unit.uid})
			return events
		turn_index += 1
	round_number += 1
	if round_number > turn_limit:
		return _resolve_timeout()
	return _begin_round()

func _check_resolution() -> Array:
	if not is_active():
		return []
	if living(ENEMY).is_empty():
		return _finish(true, State.WON)
	if living(PLAYER).is_empty():
		return _finish(false, State.LOST)
	return []

## Time is up: the side with more total HP takes it, a tie is a player loss.
## Stalling is a losing strategy on purpose (FR-015).
func _resolve_timeout() -> Array:
	var winner: int = Rules.resolve_timeout(units)
	state = State.TIMEOUT
	return [{"e": "encounter_ended", "victory": winner == PLAYER, "rounds": round_number - 1}]

func _finish(victory: bool, new_state: int) -> Array:
	state = new_state
	return [{"e": "encounter_ended", "victory": victory, "rounds": round_number}]

# ── Actions ──────────────────────────────────────────────────────────

## Moving does not end the turn: a unit may move and then attack, but never move
## twice. That single rule is most of what makes the board feel tactical.
func move_unit(uid: int, to: Vector2i) -> Array:
	if not is_active() or not valid_moves(uid).has(to):
		return []
	var unit := get_unit(uid)
	var from := unit.position
	unit.position = to
	unit.moved_this_turn = true
	return [{"e": "unit_moved", "uid": uid, "from": from, "to": to}]

func attack(uid: int, target_uid: int) -> Array:
	if not is_active() or not valid_targets(uid).has(target_uid):
		return []
	var attacker := get_unit(uid)
	var target := get_unit(target_uid)
	var dealt: int = Rules.damage(attacker, target)
	target.take_damage(dealt)
	attacker.has_acted = true
	var events: Array = [{"e": "unit_attacked", "attacker": uid, "target": target_uid, "damage": dealt}]
	if not target.is_alive():
		target.position = Vector2i(-1, -1)
		events.append({"e": "unit_died", "uid": target_uid, "side": target.side})
	events.append_array(_advance())
	return events

func defend(uid: int) -> Array:
	var unit := get_unit(uid)
	if not is_active() or unit == null or unit.has_acted:
		return []
	unit.defending = true
	unit.has_acted = true
	var events: Array = [{"e": "unit_defended", "uid": uid}]
	events.append_array(_advance())
	return events

func wait_unit(uid: int) -> Array:
	var unit := get_unit(uid)
	if not is_active() or unit == null or unit.has_acted:
		return []
	unit.has_acted = true
	return _advance()

func end_turn() -> Array:
	if not is_active():
		return []
	var unit := active_unit()
	if unit != null:
		unit.has_acted = true
	return _advance()

# ── Leaving the board ────────────────────────────────────────────────

## Between encounters the survivors step off the board but keep their damage.
func release_survivors() -> void:
	for unit in units:
		if unit.side == PLAYER and unit.is_alive():
			unit.leave_board()
