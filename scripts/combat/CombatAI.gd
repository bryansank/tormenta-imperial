extends RefCounted
class_name CombatAI
## Decides what one enemy unit does on its turn. Pure and deterministic: it reads
## an Encounter and returns a plan, it never mutates anything and never touches
## the EventBus. CombatManager executes the plan one step at a time so the player
## can follow it.
##
## Criterio (T038): cerrar distancia, elegir el objetivo que mas cambia la
## batalla y mantener la artilleria a su distancia de tiro. Todo desempate acaba
## en el `uid` menor, asi que el mismo tablero siempre produce el mismo plan: es
## lo que permite que AutoResolver decida una defensa sin jugador y que el
## resultado sea reproducible al recargar la partida.

const Rules := preload("res://scripts/combat/CombatRules.gd")

## Returns an ordered list of actions:
##   {"action": "move",   "to": Vector2i}
##   {"action": "attack", "target": uid}
##   {"action": "defend"}
##   {"action": "wait"}
##
## Sirve para cualquier bando: el "rival" es siempre el lado contrario al de la
## unidad, asi que la misma IA conduce al enemigo en el tablero y a la
## guarnicion cuando una defensa se resuelve sin jugador (AutoResolver).
static func plan_turn(encounter: Encounter, uid: int) -> Array:
	var unit: CombatUnit = encounter.get_unit(uid)
	if unit == null or not unit.is_alive():
		return [{"action": "wait"}]

	var enemies: Array = encounter.living(rival_side(unit.side))
	if enemies.is_empty():
		return [{"action": "wait"}]

	var plan: Array = []
	var destination: Vector2i = _best_cell(encounter, unit, enemies)
	if destination != unit.position:
		plan.append({"action": "move", "to": destination})

	var target: CombatUnit = _pick_target(unit, destination, enemies)
	if target != null:
		plan.append({"action": "attack", "target": target.uid})
	elif not unit.defending:
		# Sin nadie a tiro ni siquiera tras moverse, la unidad se atrinchera en
		# vez de quedarse mirando (T039): moverse no cierra el turno, asi que
		# acercarse y defender en la nueva casilla es una jugada completa.
		plan.append({"action": "defend"})
	elif plan.is_empty():
		plan.append({"action": "wait"})
	return plan

## El bando al que dispara una unidad de `side`.
static func rival_side(side: int) -> int:
	return Encounter.PLAYER if side == Encounter.ENEMY else Encounter.ENEMY

# ── Eleccion de casilla ────────────────────────────────

## Puntua todas las casillas donde la unidad podria plantarse, quedarse quieta
## incluida, y se queda con la mejor.
##
## Las claves se comparan lexicograficamente y **menor es mejor**; ante un empate
## exacto gana la primera candidata, que siempre es la posicion actual. De ahi
## sale el "prefiere mantenerse": una unidad que ya dispara bien no se reubica
## por gusto, y la artilleria que ya esta a su alcance no avanza ni retrocede.
static func _best_cell(encounter: Encounter, unit: CombatUnit, enemies: Array) -> Vector2i:
	var candidates: Array = [unit.position]
	candidates.append_array(encounter.valid_moves(unit.uid))

	var best: Vector2i = unit.position
	var best_key: Array = _cell_key(unit, unit.position, enemies)
	for i in range(1, candidates.size()):
		var key: Array = _cell_key(unit, candidates[i], enemies)
		if _precedes(key, best_key):
			best_key = key
			best = candidates[i]
	return best

## Clave de una casilla. El primer campo es el que manda: una casilla desde la
## que se dispara este turno (0) vale mas que cualquier cantidad de avance (1),
## asi que la IA nunca pasa de largo junto a un objetivo al que podia pegar.
##
## Casilla con tiro: se ordena por la calidad del objetivo que cubre, de modo que
## entre dos posiciones de disparo gana la que apunta al rival que mas urge. La
## distancia y el uid del objetivo quedan fuera a proposito: dos casillas que
## cubren rivales igual de urgentes empatan, y el empate lo gana quedarse quieto.
## Casilla muda: se ordena por lo lejos que queda de la distancia ideal — el
## alcance minimo de la unidad. Ahi vive el repliegue de la artilleria: pegada a
## un rival no tiene tiro (clave 1), y cualquier casilla a la que pueda retirarse
## y disparar tiene clave 0, asi que se aleja en lugar de aguantar a bocajarro.
static func _cell_key(unit: CombatUnit, cell: Vector2i, enemies: Array) -> Array:
	var target: CombatUnit = _pick_target(unit, cell, enemies)
	if target != null:
		var key: Array = [0]
		key.append_array(_target_quality(unit, target))
		return key

	var nearest: int = 9999
	for enemy in enemies:
		nearest = mini(nearest, Rules.manhattan(cell, enemy.position))
	return [1, absi(nearest - unit.min_range()), 0, 0]

# ── Eleccion de objetivo (T038) ────────────────────────

## Prioridad de objetivo, de mas a menos importante:
##   1. Un rival al que **puede matar este turno**: el dano calculado (con la
##      guardia del rival ya contada) alcanza o supera sus HP restantes. Un
##      muerto deja de pegar; nada rinde mas en un turno.
##   2. Si ninguno muere, el de mayor **valor** (`power` de GameConfig): mejor
##      morder al vehiculo que a la infanteria que lo escolta.
##   3. A igual valor, el de **menos HP**: es el que antes caera.
##   4. A igual HP, el **mas cercano**, para no dejar hueco al que ya tienes
##      encima.
##   5. A igual distancia, el **`uid` menor**. Es el desempate que garantiza
##      determinismo: el mismo tablero siempre produce el mismo plan.
static func _pick_target(unit: CombatUnit, from: Vector2i, enemies: Array) -> CombatUnit:
	var best: CombatUnit = null
	var best_key: Array = []
	for enemy in enemies:
		var dist: int = Rules.manhattan(from, enemy.position)
		if dist < unit.min_range() or dist > unit.attack_range():
			continue
		var key: Array = _target_quality(unit, enemy)
		key.append(dist)
		key.append(enemy.uid)
		if best == null or _precedes(key, best_key):
			best = enemy
			best_key = key
	return best

## Los tres criterios que no dependen de donde este la unidad: rematable, valor y
## HP. `_pick_target` les anade distancia y uid; `_cell_key` solo el uid.
static func _target_quality(unit: CombatUnit, enemy: CombatUnit) -> Array:
	var lethal: int = 0 if Rules.damage(unit, enemy) >= enemy.hp else 1
	return [lethal, -enemy.power(), enemy.hp]

## Orden lexicografico: `true` si `a` es estrictamente mejor que `b`.
static func _precedes(a: Array, b: Array) -> bool:
	for i in range(mini(a.size(), b.size())):
		if a[i] != b[i]:
			return a[i] < b[i]
	return false
