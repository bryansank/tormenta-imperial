extends RefCounted
class_name CombatAI
## Decides what one enemy unit does on its turn. Pure and deterministic: it reads
## an Encounter and returns a plan, it never mutates anything and never touches
## the EventBus. CombatManager executes the plan one step at a time so the player
## can follow it.
##
## Criterio (T038, rehecho en la 1.1): cerrar distancia hacia lo que importa,
## elegir el objetivo donde el golpe mas quita (la parte de su vida que se lleva
## por la amenaza que supone para los suyos, `shot_worth`), no perder turnos con
## lo que apenas se daña, y mantener la artilleria a su distancia de tiro. Todo desempate acaba
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
	var ctx: Dictionary = _context(encounter, unit, enemies)
	_focus_target(unit, enemies, ctx)
	var destination: Vector2i = _best_cell(encounter, unit, enemies, ctx)
	if destination != unit.position:
		plan.append({"action": "move", "to": destination})

	var target: CombatUnit = _pick_target(unit, destination, enemies, ctx)
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

# ── Lo que vale cada golpe (1.1, docs/15 §8 "La IA") ──────────

## Lo que la IA sabe del tablero al empezar el turno de una unidad: para cada
## rival, cuanto vale pegarle (`worth`), si cae de un golpe (`lethal`) y a quien
## ir si no hay tiro bueno (`focus`). Nada depende de la casilla desde la que se
## dispare (el dano no cambia con la distancia), asi que se calcula una vez por
## turno y no una vez por casilla candidata.
static func _context(encounter: Encounter, unit: CombatUnit, enemies: Array) -> Dictionary:
	var allies: Array = encounter.living(unit.side)
	var worth: Dictionary = {}
	var lethal: Dictionary = {}
	for enemy in enemies:
		# Con la cobertura del Bastion de su casilla (0 en casi todos los tableros).
		var dealt: int = encounter.damage_between(unit, enemy)
		lethal[enemy.uid] = dealt >= enemy.hp
		worth[enemy.uid] = shot_worth(unit, enemy, allies)
	return {"worth": worth, "lethal": lethal, "focus": null}

## Cuanto vale que `unit` pegue a `enemy`: la parte de su vida que se lleva el
## golpe por la amenaza que supone `enemy` para los nuestros, elevada a
## `GameConfig.combat_ai_threat_weight`.
##
##   * La parte de la vida, y no el dano a secas: 8 puntos a un canon de 75 de
##     vida valen mas que 8 a un dirigible de 350. Ahi entra la ventaja por tipo
##     (va dentro de CombatRules.damage) y "apenas le hago nada".
##   * La amenaza = el mayor dano que `enemy` puede hacer a uno de los nuestros
##     (a los que puede pegar por dominio). Un canon que rompe blindados urge mas
##     que un dirigible que les araña; un rival que no puede pegar a nadie de los
##     nuestros (un bombardero contra una escuadrilla) no urge nada.
##
## Sustituye al `power` de GameConfig, que media lo que cuesta una unidad y no lo
## que hace en ESTE tablero: con el, los blindados perseguian al dirigible
## (poder 55) mientras los canones (28) los destrozaban (docs/17 "Aire y mar").
static func shot_worth(unit: CombatUnit, enemy: CombatUnit, allies: Array) -> float:
	var dealt: int = mini(Rules.damage(unit, enemy), enemy.hp)
	var frac: float = float(dealt) / float(maxi(1, enemy.hp))
	var weight: float = GameConfig.combat_ai_threat_weight
	if weight <= 0.0:
		return frac
	return frac * pow(threat_of(enemy, allies), weight)

## El mayor dano que `enemy` haria de un golpe a una de las unidades de `allies`
## a las que puede pegar alguna vez. 0 si no puede pegar a ninguna.
static func threat_of(enemy: CombatUnit, allies: Array) -> float:
	var best: int = 0
	for ally in allies:
		if not ally.is_alive() or Rules.max_reach(enemy, ally) <= 0:
			continue
		best = maxi(best, Rules.damage(enemy, ally))
	return float(best)

## A quien ir cuando no hay tiro este turno: el rival que mas vale **descontado por
## los turnos que tardaria en tenerlo a tiro** (valor / (1 + turnos)). Un canon a
## dos turnos puede valer menos que una infanteria al lado; un dirigible al que
## apenas se araña no vale la caminata. Desempate: el mas cercano, el uid menor.
static func _focus_target(unit: CombatUnit, enemies: Array, ctx: Dictionary) -> void:
	var best: CombatUnit = null
	var best_key: Array = []
	for enemy in enemies:
		var reach: int = Rules.max_reach(unit, enemy)
		if reach <= 0:
			continue
		var dist: int = Rules.strike_distance(unit, unit.position, enemy)
		var turns: int = _turns_to_reach(unit, dist, reach)
		var value: float = float(ctx["worth"][enemy.uid]) / float(1 + turns)
		var key: Array = [-value, dist, enemy.uid]
		if best == null or _precedes(key, best_key):
			best = enemy
			best_key = key
	ctx["focus"] = best

## Turnos (0 = este) que tarda en ponerse a `reach` de un rival a `dist`.
static func _turns_to_reach(unit: CombatUnit, dist: int, reach: int) -> int:
	var gap: int = maxi(0, dist - reach)
	if gap == 0:
		return 0
	var move: int = unit.move_range()
	if move <= 0:
		return 99
	return int(ceil(float(gap) / float(move)))

# ── Eleccion de casilla ────────────────────────────────

## Puntua todas las casillas donde la unidad podria plantarse, quedarse quieta
## incluida, y se queda con la mejor.
##
## Las claves se comparan lexicograficamente y **menor es mejor**; ante un empate
## exacto gana la primera candidata, que siempre es la posicion actual. De ahi
## sale el "prefiere mantenerse": una unidad que ya dispara bien no se reubica
## por gusto, y la artilleria que ya esta a su alcance no avanza ni retrocede.
static func _best_cell(encounter: Encounter, unit: CombatUnit, enemies: Array, ctx: Dictionary) -> Vector2i:
	var candidates: Array = [unit.position]
	candidates.append_array(encounter.valid_moves(unit.uid))

	var best: Vector2i = unit.position
	var best_key: Array = _cell_key(unit, unit.position, enemies, ctx)
	for i in range(1, candidates.size()):
		var key: Array = _cell_key(unit, candidates[i], enemies, ctx)
		if _precedes(key, best_key):
			best_key = key
			best = candidates[i]
	return best

## Clave de una casilla. El primer campo es el que manda: una casilla desde la
## que se dispara este turno (0) vale mas que cualquier cantidad de avance (1),
## asi que la IA nunca pasa de largo junto a un objetivo al que podia pegar.
## (Probado y descartado en la 1.1: dejar de contar como "de tiro" las casillas
## cuyo mejor golpe valia poco frente al foco. Hacia perder turnos caminando y
## bajaba los asedios 15-30 puntos; docs/15 §8 "La IA".)
##
## Casilla con tiro: se ordena por la calidad del objetivo que cubre, de modo que
## entre dos posiciones de disparo gana la que apunta al rival que mas urge. La
## distancia y el uid del objetivo quedan fuera a proposito: dos casillas que
## cubren rivales igual de urgentes empatan, y el empate lo gana quedarse quieto.
## Casilla muda: se ordena por lo lejos que queda del rival al que va (`focus`,
## el que mas vale descontado por los turnos que tarda en llegar) respecto a la
## distancia ideal —el alcance minimo de la unidad—. Ahi vive el
## repliegue de la artilleria: pegada a un rival no tiene tiro (clave 1), y
## cualquier casilla a la que pueda retirarse y disparar tiene clave 0.
static func _cell_key(unit: CombatUnit, cell: Vector2i, enemies: Array, ctx: Dictionary) -> Array:
	var target: CombatUnit = _pick_target(unit, cell, enemies, ctx)
	if target != null:
		var key: Array = [0]
		key.append_array(_target_quality(target, ctx))
		return key

	# Aire y mar: el foco solo es un rival al que esta unidad puede pegar alguna
	# vez (una lancha no persigue aviones). Si no hay ninguno, todas las casillas
	# valen lo mismo y se queda donde esta.
	var focus: CombatUnit = ctx["focus"]
	if focus == null:
		return [1, 0, 0, 0]
	return [1, absi(Rules.strike_distance(unit, cell, focus) - unit.min_range()), 0, 0]

# ── Eleccion de objetivo ───────────────────────────────

## Prioridad de objetivo entre los que estan a tiro, de mas a menos importante:
##   1. Un rival al que **puede matar este turno**: el dano calculado (con la
##      guardia del rival ya contada) alcanza o supera sus HP restantes. Un
##      muerto deja de pegar; nada rinde mas en un turno.
##   2. El de **mas valor del golpe** (`shot_worth`): la parte de su vida que se
##      lleva, por la amenaza que supone para los nuestros. La ventaja por tipo
##      va dentro (en el dano y en la amenaza).
##   3. A igual valor, el de **menos HP**: es el que antes caera.
##   4. A igual HP, el **mas cercano**, para no dejar hueco al que ya tienes
##      encima.
##   5. A igual distancia, el **`uid` menor**. Es el desempate que garantiza
##      determinismo: el mismo tablero siempre produce el mismo plan.
static func _pick_target(unit: CombatUnit, from: Vector2i, enemies: Array, ctx: Dictionary) -> CombatUnit:
	var best: CombatUnit = null
	var best_key: Array = []
	for enemy in enemies:
		# Aire y mar: el alcance contra ese dominio (CombatRules.can_hit_from). Entre
		# tierra y tierra es el min_range/range de siempre.
		if not Rules.can_hit_from(unit, from, enemy):
			continue
		var dist: int = Rules.strike_distance(unit, from, enemy)
		var key: Array = _target_quality(enemy, ctx)
		key.append(dist)
		key.append(enemy.uid)
		if best == null or _precedes(key, best_key):
			best = enemy
			best_key = key
	return best

## Los criterios que no dependen de donde este la unidad: rematable, valor del
## golpe y HP. `_pick_target` les anade distancia y uid.
static func _target_quality(enemy: CombatUnit, ctx: Dictionary) -> Array:
	var lethal: int = 0 if bool(ctx["lethal"][enemy.uid]) else 1
	return [lethal, -float(ctx["worth"][enemy.uid]), enemy.hp]

## Orden lexicografico: `true` si `a` es estrictamente mejor que `b`.
static func _precedes(a: Array, b: Array) -> bool:
	for i in range(mini(a.size(), b.size())):
		if a[i] != b[i]:
			return a[i] < b[i]
	return false
