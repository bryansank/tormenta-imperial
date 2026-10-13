extends RefCounted
class_name DayCycle
## El reloj del dia: amanecer, dia, atardecer y noche (docs/21 §12).
##
## Estado puro, como StormCycle: sin nodos, sin EventBus, sin temporizadores y
## sin azar. `tick(delta)` avanza la hora y devuelve un Array de eventos
## (`{"e": "day_phase_changed", "phase": int, "hour": float}`) que DayClock
## republica en el EventBus. Asi un dia entero se recorre en una prueba sin
## escena.
##
## Hoy solo pinta (StormSky, StormTint2D). Esta pensado para que mañana una
## regla pregunte `is_night()` o `light_weight()` sin tocar el reloj.
##
## La hora va de 0 a 1 y empieza al rayar el alba:
##     0 ── amanecer ── dia ── atardecer ── noche ── 1 (= 0)
## Las cuatro duraciones se pasan al crearlo (DayClock las lee de GameConfig);
## el modelo no lee configuracion global.

enum Phase {
	DAWN,   ## Sale el sol: la luz sube, el cielo se calienta.
	DAY,    ## Luz plena: la de Main.tscn tal cual.
	DUSK,   ## Se pone: luz calida que baja.
	NIGHT,  ## Luna: azulada y mas baja, pero siempre legible.
}

## Lo que dura cada fase, en segundos reales.
var dawn_seconds: float = 90.0
var day_seconds: float = 600.0
var dusk_seconds: float = 90.0
var night_seconds: float = 180.0

## La hora del dia (0-1). Se guarda en la partida.
var hour: float = 0.0
## La fase en la que esta `hour`. Derivada, pero se guarda aparte para que
## `tick()` sepa si ha cambiado.
var phase: int = Phase.DAY

# ── Construccion ─────────────────────────────────────────────────────

## Un dia con estas duraciones (segundos; ninguna por debajo de 1 s). Empieza
## al principio del dia pleno: una partida
## nueva nunca abre de noche.
static func create(dawn: float, day: float, dusk: float, night: float) -> DayCycle:
	var cycle := DayCycle.new()
	cycle.dawn_seconds = maxf(dawn, 1.0)
	cycle.day_seconds = maxf(day, 1.0)
	cycle.dusk_seconds = maxf(dusk, 1.0)
	cycle.night_seconds = maxf(night, 1.0)
	cycle.set_hour(cycle.day_start())
	return cycle

## Un ciclo completo, en segundos.
func length() -> float:
	return dawn_seconds + day_seconds + dusk_seconds + night_seconds

## La hora a la que empieza el dia pleno (fin del amanecer).
func day_start() -> float:
	return dawn_seconds / length()

## Pone la hora a mano (cargar partida, sondas). No devuelve eventos: quien la
## pone sabe que la ha cambiado. Admite cualquier numero y lo envuelve en 0-1.
func set_hour(value: float) -> void:
	hour = fposmod(value, 1.0)
	phase = phase_at(hour)

# ── El reloj ─────────────────────────────────────────────────────────

## Avanza `delta` segundos. Devuelve un evento por cada fase en la que entra
## (con un delta grande puede entrar en varias; nunca mas de cuatro).
func tick(delta: float) -> Array:
	if delta <= 0.0:
		return []
	var events: Array = []
	var total := length()
	# Las vueltas enteras no cambian nada que se vea: se saltan.
	var remaining := fposmod(delta, total) if delta >= total else delta
	while remaining > 0.0:
		var to_edge := (_phase_end(phase) - hour) * total
		if remaining < to_edge:
			hour += remaining / total
			break
		remaining -= to_edge
		hour = fposmod(_phase_end(phase), 1.0)
		phase = (phase + 1) % 4
		events.append({"e": "day_phase_changed", "phase": phase, "hour": hour})
	return events

# ── Consultas ────────────────────────────────────────────────────────

func is_night() -> bool:
	return phase == Phase.NIGHT

## La fase de una hora cualquiera.
func phase_at(h: float) -> int:
	h = fposmod(h, 1.0)
	for p in [Phase.DAWN, Phase.DAY, Phase.DUSK]:
		if h < _phase_end(p):
			return p
	return Phase.NIGHT

## Cuanto lleva la fase actual (0 al entrar, 1 al salir).
func phase_progress() -> float:
	var start := _phase_start(phase)
	var span := _phase_end(phase) - start
	if span <= 0.0:
		return 1.0
	return clampf((hour - start) / span, 0.0, 1.0)

## Cuanta luz de dia hay: 1 en el dia pleno, 0 en la noche, y una curva suave
## en el amanecer y el atardecer. Lo que mira quien pinta, y lo que miraria una
## regla de "de noche se produce menos".
func light_weight() -> float:
	match phase:
		Phase.DAY:
			return 1.0
		Phase.NIGHT:
			return 0.0
		Phase.DAWN:
			return smoothstep(0.0, 1.0, phase_progress())
		_:
			return 1.0 - smoothstep(0.0, 1.0, phase_progress())

## Cuanto pesa la luz calida (naranja) del sol bajo: 0 de dia y de noche, y un
## arco que sube y baja dentro del amanecer y del atardecer.
func warm_weight() -> float:
	if phase != Phase.DAWN and phase != Phase.DUSK:
		return 0.0
	return sin(PI * phase_progress())

## Por donde va la luz en el cielo, de -1 (este, sale) a 1 (oeste, se pone).
## De dia recorre el arco de ida; de noche la luna lo vuelve a recorrer al reves,
## de modo que la direccion de la luz nunca salta (solo cambia su color y su
## fuerza). 0 es el mediodia (y la medianoche).
func sun_arc() -> float:
	var lit_end := _phase_end(Phase.DUSK)
	if hour < lit_end:
		return lerpf(-1.0, 1.0, hour / lit_end)
	var night_span := 1.0 - lit_end
	if night_span <= 0.0:
		return 1.0
	return lerpf(1.0, -1.0, (hour - lit_end) / night_span)

# ── Guardado ─────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {"hour": hour}

## Solo la hora: las duraciones vienen de la configuracion de hoy, asi que
## retocar `day_cycle_*` no deja a las partidas viejas a medias.
func load_dict(data: Dictionary) -> void:
	set_hour(float(data.get("hour", day_start())))

# ── Internos ─────────────────────────────────────────────────────────

func _phase_start(p: int) -> float:
	match p:
		Phase.DAWN:
			return 0.0
		Phase.DAY:
			return dawn_seconds / length()
		Phase.DUSK:
			return (dawn_seconds + day_seconds) / length()
		_:
			return (dawn_seconds + day_seconds + dusk_seconds) / length()

func _phase_end(p: int) -> float:
	if p == Phase.NIGHT:
		return 1.0
	return _phase_start(p + 1)
