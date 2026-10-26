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
## Retirada enemiga (doc 21 §3.4, D7 = B): en expediciones e incursiones el
## enemigo se retira cuando le queda menos de `rout_ratio` de la vida con la que
## empezo, y el combate se gana sin rematar. Apagado por defecto: el Diezmo y el
## asedio se pelean hasta el final. No toca la formula de dano.
var enemy_can_rout: bool = false
var rout_ratio: float = 0.0
## Vida total del enemigo al empezar (la base de la retirada).
var enemy_start_hp: int = 0
## El combate acabo porque el enemigo se retiro.
var routed: bool = false
## Aire y mar (docs/15 §11): el terreno de cada casilla, Vector2i -> "land" |
## "water" | "shore". Vacio = todo tierra (todos los combates de antes). Lo
## genera CombatRules.coastal_terrain() a partir de una semilla; el tablero no
## se guarda, asi que basta con guardar esa semilla.
var terrain: Dictionary = {}
## Unidades que no cupieron en el tablero o no tienen donde plantarse (un barco
## en un tablero sin agua). No pelean, no mueren, no cuentan: se quedan "en el
## puerto". Normalmente vacio: quien compone los bandos ya evita mandarlas.
var reserve: Array = []
## Cobertura (Bastion, feat/edificios-defensa-vida): casilla -> defensa de mas
## para quien este encima (solo de superficie: un avion no se esconde detras de
## un parapeto). Vacio = sin cobertura, el tablero de siempre. Solo la ponen los
## tableros de defensa (Impuesto y asedio) con algun Bastion en pie.
var cover: Dictionary = {}
## El azar del dano (feat/ritmo-colono, docs/15 §3 "El dano y su azar"): un
## generador PROPIO, sembrado. create() lo siembra con una semilla sacada del
## tablero tal como empieza (bandos, vida, casillas), asi que el mismo tablero da
## el mismo combate; quien quiera otra noche (un reintento, otro Impuesto) llama
## seed_rng() con su semilla antes de start(). Misma semilla y mismas jugadas =
## mismo combate. Nunca randf() global.
var rng := RandomNumberGenerator.new()
var rng_seed: int = 0

# ── Construction ─────────────────────────────────────────────────────

## `units` arrive already built (CombatUnit instances) so the expedition can hand
## over survivors carrying their damage from the previous node (FR-011).
##
## `p_terrain` (aire y mar): el terreno del tablero. Vacio = todo tierra.
static func create(p_units: Array, p_index: int, p_is_boss: bool, p_is_defense: bool = false, p_back_row: Array = [], p_can_rout: bool = false, p_terrain: Dictionary = {}) -> Encounter:
	var e := Encounter.new()
	e.units = p_units
	e.index = p_index
	e.is_boss = p_is_boss
	e.is_defense = p_is_defense
	e.terrain = p_terrain
	for uid in p_back_row:
		e.back_row_uids[int(uid)] = true
	e.board_size = GameConfig.combat_board_size
	e.turn_limit = GameConfig.combat_turn_limit
	# Una defensa nunca se retira: es el Diezmo o el asedio (D7 = B).
	e.enemy_can_rout = p_can_rout and not p_is_defense
	e.rout_ratio = GameConfig.combat_retreat_ratio
	e._build_deploy_zones()
	e._deploy()
	e._bench_undeployed()
	# Despues de desplegar: lo que se quedo en reserva no cuenta para la retirada.
	for unit in Rules.living_units(e.units, ENEMY):
		e.enemy_start_hp += unit.hp
	e.seed_rng(e.board_seed())
	return e

## Pone `cells` como casillas de cobertura con `bonus` de defensa cada una.
## Se llama tras create(); no mueve a nadie (el despliegue ya esta hecho y las
## dotaciones de torre suelen quedar encima, en la fila de atras).
func set_cover(cells: Array, bonus: int) -> void:
	cover.clear()
	if bonus <= 0:
		return
	for c in cells:
		cover[c as Vector2i] = bonus

## La defensa de mas que da la casilla `cell` (0 sin cobertura).
func cover_at(cell: Vector2i) -> int:
	return int(cover.get(cell, 0))

## La defensa de mas de `unit` donde esta ahora: la de su casilla si es de
## superficie, 0 si vuela o no esta en el tablero.
func cover_for(unit: CombatUnit) -> int:
	if unit == null or cover.is_empty() or unit.position.x < 0 or unit.layer() == "air":
		return 0
	return cover_at(unit.position)

## El dano que haria `attacker` a `target` en este tablero (cobertura incluida).
func damage_between(attacker: CombatUnit, target: CombatUnit) -> int:
	return Rules.damage(attacker, target, cover_for(target))
## La semilla que sale del tablero tal como empieza: indice, jefe, defensa y cada
## unidad (tipo, bando, vida, escala y casilla). Pura: el mismo tablero, la misma.
func board_seed() -> int:
	var parts: Array = [index, is_boss, is_defense]
	for unit in units:
		parts.append([unit.unit_id, unit.side, unit.hp, snappedf(unit.scale, 0.001), unit.position])
	var value: int = hash(parts)
	return value if value != 0 else 1

## Siembra el azar del dano. Llamar antes de start() (o de AutoResolver.resolve).
func seed_rng(value: int) -> void:
	rng_seed = value if value != 0 else 1
	rng.seed = rng_seed

## ¿Hay agua en este tablero?
func has_water() -> bool:
	return Rules.has_water(terrain)

## El terreno de una casilla ("land" si el tablero no dice nada).
func terrain_at(cell: Vector2i) -> String:
	return Rules.terrain_at(terrain, cell)

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
##
## Aire y mar (docs/15 §11): cada dominio forma por su cuenta y solo en las
## casillas que puede pisar. Primero el mar (que solo tiene el agua y la
## orilla), luego la tierra, luego el aire, que va en su propia capa y puede
## quedar encima de los demas. Con solo unidades de tierra y sin terreno, sale
## exactamente el despliegue de siempre.
const DEPLOY_ORDER := ["sea", "land", "air"]

func _deploy() -> void:
	# Todos empiezan fuera: quien no encuentre sitio se queda en reserva
	# (_bench_undeployed), en vez de conservar una casilla de otro tablero.
	for unit in Rules.living_units(units, PLAYER) + Rules.living_units(units, ENEMY):
		unit.position = Vector2i(-1, -1)
	for side in [PLAYER, ENEMY]:
		var rows: Array = _rows_for(side)
		var rear: Dictionary = {}
		var line: Dictionary = {}
		for unit in Rules.living_units(units, side):
			var bucket: Dictionary = rear if back_row_uids.has(unit.uid) else line
			var domain: String = unit.domain()
			if not bucket.has(domain):
				bucket[domain] = []
			bucket[domain].append(unit)

		var taken_by_layer: Dictionary = {"surface": {}, "air": {}}
		# La retaguardia coge la fila de atras ANTES de que forme la linea, porque
		# el bando entero suele caber en la primera fila: si se repartiera por
		# orden, nadie llegaria nunca atras.
		for domain in _deploy_domains(rear):
			var group: Array = rear[domain]
			_fill_row(group, int(rows[rows.size() - 1]), taken_by_layer[Rules.layer_of(domain)], domain)
			# La retaguardia que no cupo atras forma con la linea.
			if not group.is_empty():
				if not line.has(domain):
					line[domain] = []
				line[domain] = group + line[domain]
		for domain in _deploy_domains(line):
			var pending: Array = line[domain]
			for row in rows:
				if pending.is_empty():
					break
				_fill_row(pending, int(row), taken_by_layer[Rules.layer_of(domain)], domain)

## Los dominios presentes en `buckets`, en DEPLOY_ORDER (y cualquier otro al final).
func _deploy_domains(buckets: Dictionary) -> Array:
	var out: Array = []
	for domain in DEPLOY_ORDER:
		if buckets.has(domain):
			out.append(domain)
	for domain in buckets:
		if not out.has(domain):
			out.append(domain)
	return out

## Saca del tablero a los vivos que no encontraron sitio (Encounter.reserve). Solo
## crea una lista nueva si hay alguno: si no, `units` sigue siendo la que entro.
func _bench_undeployed() -> void:
	var benched: Array = []
	for unit in units:
		if unit.is_alive() and unit.position.x < 0:
			benched.append(unit)
	if benched.is_empty():
		return
	reserve = benched
	var kept: Array = []
	for unit in units:
		if not benched.has(unit):
			kept.append(unit)
	units = kept

## Centra en esa fila a los que quepan y los saca de `pending`. Respeta las
## celdas ya ocupadas, para que la linea no aplaste a la retaguardia al desbordar.
## Solo usa las casillas que `domain` puede pisar (sin terreno, todas).
func _fill_row(pending: Array, row: int, taken: Dictionary, domain: String = CombatUnit.DOMAIN_LAND) -> void:
	var free: Array = []
	for x in range(board_size.x):
		var cell := Vector2i(x, row)
		if not taken.has(cell) and Rules.can_stand(domain, terrain_at(cell)):
			free.append(cell)
	# Los barcos forman en el agua: la orilla (arena) solo si en el agua de esa
	# fila no caben todos. Centrar entre agua y orilla dejaba un acorazado varado
	# en la playa al empezar (ronda visual de la 1.1).
	if domain == CombatUnit.DOMAIN_SEA:
		var water: Array = free.filter(func(c): return terrain_at(c) == Rules.TERRAIN_WATER)
		if water.size() >= pending.size():
			free = water
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

## La unidad viva en esa casilla. Con aire y mar puede haber dos (un avion encima
## de un soldado o de un barco): manda la de superficie, y si no hay, la de aire.
## Para elegir capa, get_unit_at_layer(); para todas, get_units_at().
func get_unit_at(cell: Vector2i) -> CombatUnit:
	var flying: CombatUnit = null
	for unit in units:
		if unit.is_alive() and unit.position == cell:
			if unit.layer() == "surface":
				return unit
			if flying == null:
				flying = unit
	return flying

## La unidad viva de esa capa ("surface" / "air") en esa casilla, o null.
func get_unit_at_layer(cell: Vector2i, layer: String) -> CombatUnit:
	for unit in units:
		if unit.is_alive() and unit.position == cell and unit.layer() == layer:
			return unit
	return null

## Todas las unidades vivas de esa casilla (0, 1 o 2: una por capa).
func get_units_at(cell: Vector2i) -> Array:
	var out: Array = []
	for unit in units:
		if unit.is_alive() and unit.position == cell:
			out.append(unit)
	return out

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
	# Aire y mar: solo bloquea la propia capa y solo se pisa lo que el dominio
	# permite. Sin terreno y todo de tierra, es la BFS de siempre.
	return Rules.reachable_cells(
		unit.position, unit.move_range(), board_size,
		Rules.occupied_cells(units, uid, unit.layer()), terrain, unit.domain()
	)

## Lo que el bando `side` amenaza en su proximo turno (Ver alcance enemigo),
## respetando el terreno de este tablero.
func threat_cells(side: int) -> Array:
	return Rules.threat_cells(units, side, board_size, terrain)

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
	if should_rout():
		routed = true
		var events: Array = [{"e": "enemy_routed", "survivors": living(ENEMY).size()}]
		state = State.WON
		events.append({"e": "encounter_ended", "victory": true, "rounds": round_number, "routed": true})
		return events
	return []

## El enemigo esta perdido y se va: le queda menos de `rout_ratio` de su vida
## inicial. Solo donde se permite (expedicion e incursion).
func should_rout() -> bool:
	if not enemy_can_rout or rout_ratio <= 0.0 or enemy_start_hp <= 0:
		return false
	if living(ENEMY).is_empty():
		return false
	return Rules.hp_fraction(units, ENEMY, enemy_start_hp) < rout_ratio

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
	# El golpe sale del rango con la tirada de este tablero (rng sembrado), con la
	# cobertura de la casilla del blanco (Bastion). Con combat_damage_spread = 0 el
	# rango es un solo numero y no se tira nada.
	var cover_bonus: int = cover_for(target)
	var span: Vector2i = Rules.damage_range(attacker, target, cover_bonus)
	var dealt: int = span.x if span.x == span.y else Rules.rolled_damage(attacker, target, rng.randf(), cover_bonus)
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
