extends RefCounted
class_name FrontOrders
## Las ordenes de la vista frontal (docs/15 §3, "Las dos vistas"). En el frente
## no se ven casillas (los sitios a los que ir se iluminan como manchas en el
## suelo y se tocan para mover). Ademas, el jugador toca a un enemigo y su unidad "se acerca y
## dispara", o pulsa AVANZAR. Esto traduce esas dos intenciones a las MISMAS
## acciones de siempre del Encounter (mover y atacar), asi que no hay una regla
## nueva ni un segundo camino: la vista frontal y el tablero 8x8 mueven el mismo
## modelo y una pelea da lo mismo en las dos.
##
## Es VISTA (vive en scripts/combat_view/, no en los modelos): ni el Encounter,
## ni la IA, ni AutoResolver saben que existe. Puro y de solo lectura: lee un Encounter y devuelve casillas o uids. Nunca
## muta nada ni toca el EventBus; quien ejecuta es BattleScreen a traves de
## CombatManager (move_unit / attack). Todo desempate es determinista.

const Rules := preload("res://scripts/combat/CombatRules.gd")
const NO_CELL := Vector2i(-1, -1)

## Desde donde atacar a `target_uid` este turno:
##   * la posicion actual si ya esta a tiro;
##   * si no ha movido, la casilla alcanzable desde la que le llega con menos
##     camino (a igualdad, la mas alejada del objetivo: la artilleria no se mete
##     encima; despues, la fila y la columna menores);
##   * NO_CELL si no hay forma de pegarle este turno.
static func approach_cell(encounter: Encounter, uid: int, target_uid: int) -> Vector2i:
	if encounter == null:
		return NO_CELL
	var unit: CombatUnit = encounter.get_unit(uid)
	var target: CombatUnit = encounter.get_unit(target_uid)
	if unit == null or target == null or not unit.is_alive() or not target.is_alive():
		return NO_CELL
	if unit.has_acted or target.side == unit.side:
		return NO_CELL
	if encounter.valid_targets(uid).has(target_uid):
		return unit.position
	var best := NO_CELL
	var best_key: Array = []
	for cell in encounter.valid_moves(uid):
		var dist: int = Rules.manhattan(cell, target.position)
		if dist < unit.min_range() or dist > unit.attack_range():
			continue
		var key: Array = [Rules.manhattan(unit.position, cell), -dist, cell.y, cell.x]
		if best == NO_CELL or _precedes(key, best_key):
			best = cell
			best_key = key
	return best

## Los enemigos a los que esta unidad puede pegar este turno, moviendose o no
## (uids, en orden de uid). Es lo que el frente marca con el aro rojo.
static func reachable_targets(encounter: Encounter, uid: int) -> Array:
	var out: Array = []
	if encounter == null:
		return out
	var unit: CombatUnit = encounter.get_unit(uid)
	if unit == null or not unit.is_alive():
		return out
	for other in encounter.living(CombatAI.rival_side(unit.side)):
		if approach_cell(encounter, uid, other.uid) != NO_CELL:
			out.append(other.uid)
	out.sort()
	return out

## AVANZAR: la casilla a la que iria el mando (CombatAI) con esta unidad, sin
## atacar. NO_CELL si ya ha movido o se quedaria donde esta.
static func advance_cell(encounter: Encounter, uid: int) -> Vector2i:
	if encounter == null:
		return NO_CELL
	var unit: CombatUnit = encounter.get_unit(uid)
	if unit == null or not unit.is_alive() or unit.moved_this_turn or unit.has_acted:
		return NO_CELL
	for step in CombatAI.plan_turn(encounter, uid):
		if String(step.get("action", "")) == "move":
			var to: Vector2i = step["to"]
			return to if encounter.valid_moves(uid).has(to) else NO_CELL
	return NO_CELL

static func _precedes(a: Array, b: Array) -> bool:
	for i in range(mini(a.size(), b.size())):
		if a[i] != b[i]:
			return a[i] < b[i]
	return false
