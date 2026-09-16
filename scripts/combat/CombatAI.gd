extends RefCounted
class_name CombatAI
## Decides what one enemy unit does on its turn. Pure and deterministic: it reads
## an Encounter and returns a plan, it never mutates anything and never touches
## the EventBus. CombatManager executes the plan one step at a time so the player
## can follow it.
##
## Deliberately simple (plan T019): close in, focus the weakest thing you can
## reach, and keep artillery at its stand-off distance. Smarter behaviour —
## flanking, retreating, protecting the guns — belongs to US4.

const Rules := preload("res://scripts/combat/CombatRules.gd")

## A cell that lets the unit shoot this turn is worth more than any amount of
## walking, so the AI never wanders past a target it could have hit.
const SCORE_CAN_ATTACK := 1000.0

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

## Scores every cell the unit could stand on, including staying put.
static func _best_cell(encounter: Encounter, unit: CombatUnit, enemies: Array) -> Vector2i:
	var candidates: Array = [unit.position]
	candidates.append_array(encounter.valid_moves(unit.uid))

	var best: Vector2i = unit.position
	var best_score: float = -INF
	for cell in candidates:
		var score: float = _score_cell(unit, cell, enemies)
		if score > best_score:
			best_score = score
			best = cell
	return best

static func _score_cell(unit: CombatUnit, cell: Vector2i, enemies: Array) -> float:
	var nearest: int = 9999
	var can_hit := false
	var weakest_hp: int = 9999
	for enemy in enemies:
		var dist: int = Rules.manhattan(cell, enemy.position)
		nearest = mini(nearest, dist)
		if dist >= unit.min_range() and dist <= unit.attack_range():
			can_hit = true
			weakest_hp = mini(weakest_hp, enemy.hp)

	if can_hit:
		# Among shooting positions, prefer the one covering the weakest target.
		return SCORE_CAN_ATTACK - float(weakest_hp)
	# Otherwise walk in, but never closer than the unit's minimum range: artillery
	# that hugs the enemy is artillery that cannot fire next turn.
	var ideal: int = unit.min_range()
	return -float(absi(nearest - ideal))

## Focus fire: the target that dies soonest. Ties go to the higher-value unit so
## the AI shoots the tank rather than the infantry escorting it.
static func _pick_target(unit: CombatUnit, from: Vector2i, enemies: Array) -> CombatUnit:
	var best: CombatUnit = null
	for enemy in enemies:
		var dist: int = Rules.manhattan(from, enemy.position)
		if dist < unit.min_range() or dist > unit.attack_range():
			continue
		if best == null or enemy.hp < best.hp or (enemy.hp == best.hp and enemy.power() > best.power()):
			best = enemy
	return best
