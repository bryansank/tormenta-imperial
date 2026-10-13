extends Node
## El reloj del dia y la noche (docs/21 §12). Autoload.
##
## Mueve el modelo puro `scripts/storm/DayCycle.gd` y publica sus eventos
## (`day_phase_changed`). Es la unica fuente de "que hora es": StormSky (3D) y
## StormTint2D (2D) lo leen para pintar, y una regla futura ("de noche se
## produce menos") le preguntaria `is_night()` o `light_weight()` sin tocar luces.
##
## Por que un autoload propio y no dentro de StormSky: StormSky es solo luz y
## su `reset()` no se puede llamar al empezar partida (olvidaria los valores
## limpios del Environment, que sobreviven a la recarga). La hora, en cambio, es
## estado de partida: viaja en el save y se limpia con un `reset()` normal desde
## los tres sitios de GameManager. Separados, cada uno cumple su contrato.
##
## Se para con la pausa real (process_mode heredado: el arbol en pausa no lo
## mueve). Fuera del juego no avanza: al volver es la misma hora que al salir
## (docs/09, "offline": solo la produccion corre con el juego cerrado).
##
## `GameConfig.day_cycle_enabled = false` lo apaga: siempre de dia pleno.

const DayCycleScript := preload("res://scripts/storm/DayCycle.gd")

var _cycle: DayCycle = null

func _ready() -> void:
	_cycle = _make()

func _process(delta: float) -> void:
	if not is_enabled() or _cycle == null:
		return
	for event in _cycle.tick(delta):
		if event.get("e", "") == "day_phase_changed":
			EventBus.day_phase_changed.emit(int(event["phase"]), float(event["hour"]))

static func _make() -> DayCycle:
	var d: Array = GameConfig.get_day_cycle_durations()
	return DayCycleScript.create(d[0], d[1], d[2], d[3])

# ── Consultas ────────────────────────────────────────────────────────

func is_enabled() -> bool:
	return GameConfig.day_cycle_enabled

func get_cycle() -> DayCycle:
	return _cycle

## DayCycle.Phase. Apagado, siempre DAY.
func get_phase() -> int:
	if not is_enabled() or _cycle == null:
		return DayCycleScript.Phase.DAY
	return _cycle.phase

func get_hour() -> float:
	return _cycle.hour if _cycle != null else 0.0

func is_night() -> bool:
	return get_phase() == DayCycleScript.Phase.NIGHT

## 1 = dia pleno, 0 = noche cerrada.
func light_weight() -> float:
	if not is_enabled() or _cycle == null:
		return 1.0
	return _cycle.light_weight()

## Cuanto pesa la luz naranja del alba y del ocaso (0-1).
func warm_weight() -> float:
	if not is_enabled() or _cycle == null:
		return 0.0
	return _cycle.warm_weight()

## Por donde va el sol: -1 este, 0 mediodia, 1 oeste (ver DayCycle.sun_arc).
func sun_arc() -> float:
	if not is_enabled() or _cycle == null:
		return 0.0
	return _cycle.sun_arc()

## Pone la hora a mano (sondas, pruebas). No emite: quien la pone ya lo sabe.
func set_hour(value: float) -> void:
	if _cycle == null:
		_cycle = _make()
	_cycle.set_hour(value)

# ── Partida ──────────────────────────────────────────────────────────

## Partida nueva: el dia pleno recien empezado. No avisa a nadie.
func reset() -> void:
	_cycle = _make()

func get_save_data() -> Dictionary:
	return _cycle.to_dict() if _cycle != null else {}

## Idempotente: solo pone la hora guardada. Sin hora (partida vieja), de dia.
func load_save_data(data: Dictionary) -> void:
	_cycle = _make()
	_cycle.load_dict(data)
