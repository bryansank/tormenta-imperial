extends RefCounted
class_name AutoResolver
## Juega un Encounter entero sin jugador: la misma IA (CombatAI) conduce a los
## dos bandos hasta que el tablero se resuelve. Es lo que pelea la guarnicion
## cuando el Diezmo cae y el jugador tiene el tablero ocupado con una
## expedicion: el mismo modelo, las mismas reglas, ningun calculo aparte.
##
## Puro y determinista: no emite senales, no toca autoloads y no tira dados
## (ni Encounter ni CombatAI lo hacen). Mismo tablero, mismo resultado. Todos los
## eventos que el modelo va devolviendo se acumulan y se entregan al final, para
## que quien llame decida que hacer con ellos (constitucion, principios I y IV).

const AI := preload("res://scripts/combat/CombatAI.gd")

## Tope de pasos por encima del limite de rondas del propio Encounter. Cada
## accion cierra el turno de una unidad o la mueve (y solo puede moverse una vez
## por turno), asi que el modelo avanza siempre; el tope existe para que un
## error futuro en la IA o en el tablero no cuelgue el juego, nunca para que
## salte en una partida sana.
const STEPS_PER_UNIT_TURN := 4

## Resuelve `encounter` hasta WON/LOST/TIMEOUT y devuelve
##   {"victory": bool, "rounds": int, "events": Array}
## `events` son los eventos del modelo en orden, incluido el `encounter_ended`
## final. Si el encuentro llega sin arrancar (DEPLOYING) lo arranca aqui.
static func resolve(encounter: Encounter) -> Dictionary:
	var events: Array = []
	if encounter.state == Encounter.State.DEPLOYING:
		events.append_array(encounter.start())

	var max_steps: int = _step_budget(encounter)
	var steps: int = 0
	while encounter.is_active() and steps < max_steps:
		steps += 1
		var active: CombatUnit = encounter.active_unit()
		if active == null:
			# No deberia pasar con el tablero sano; si pasa, cerrar el turno es la
			# unica salida que no deja el encuentro colgado.
			events.append_array(encounter.end_turn())
			continue
		events.append_array(play_unit_turn(encounter, active.uid))

	# Tope agotado sin resolver (no deberia ocurrir): se da por perdida. Una
	# defensa que no consigue decidirse no es una defensa que se gano.
	return {
		"victory": encounter.player_won(),
		"rounds": _rounds_from(events, encounter),
		"events": events,
	}

## Ejecuta el plan de la IA para una unidad y cierra su turno si el plan no lo
## hizo (una unidad que solo se movio sigue activa). Devuelve los eventos.
static func play_unit_turn(encounter: Encounter, uid: int) -> Array:
	var events: Array = []
	for step in AI.plan_turn(encounter, uid):
		if not encounter.is_active():
			break
		events.append_array(apply_step(encounter, uid, step))
	if encounter.is_active() and encounter.active_unit() != null \
			and encounter.active_unit().uid == uid:
		events.append_array(encounter.end_turn())
	return events

## Traduce un paso del plan a la llamada del modelo. Es la unica tabla de
## acciones que entiende la IA, para que "defend" no se pierda por el camino.
static func apply_step(encounter: Encounter, uid: int, step: Dictionary) -> Array:
	match step.get("action", "wait"):
		"move":
			return encounter.move_unit(uid, step["to"])
		"attack":
			return encounter.attack(uid, step["target"])
		"defend":
			return encounter.defend(uid)
		_:
			return encounter.wait_unit(uid)

static func _step_budget(encounter: Encounter) -> int:
	var per_round: int = maxi(1, encounter.units.size()) * STEPS_PER_UNIT_TURN
	return (encounter.turn_limit + 1) * per_round + STEPS_PER_UNIT_TURN

static func _rounds_from(events: Array, encounter: Encounter) -> int:
	for i in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[i]
		if event.get("e", "") == "encounter_ended":
			return int(event.get("rounds", encounter.round_number))
	return encounter.round_number
