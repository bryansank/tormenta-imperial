extends Node
## El cielo durante la Tormenta: la isla se apaga y se llena de ceniza.
##
## Sin esto la Tormenta es un número que baja y un aviso de texto. Con esto es
## algo que ves llegar por el horizonte, que es de lo que va el juego.
##
## No toca nada más: solo el `WorldEnvironment` y la luz direccional de `Main`,
## que hasta ahora eran estáticos y ningún script referenciaba. Al pasar la
## tormenta devuelve los valores exactos que había, no unos por defecto.

## Cuánto tarda el cielo en cerrarse y en volver a abrirse.
const FADE_IN := 3.0
const FADE_OUT := 5.0

## El aire sucio del Imperio: ceniza de hierro, no nube de lluvia.
const ASH := Color(0.32, 0.27, 0.22)
const ASH_LIGHT := Color(0.55, 0.45, 0.35)

## Densidad de niebla con la tormenta encima. Lo bastante para comerse el fondo
## de la isla sin dejar al jugador sin ver donde construye.
const MAX_FOG := 0.035

## El cielo se cierra en tres pasos, uno por fase, y ninguno depende de la
## severidad hasta que la tormenta ya esta encima: si el Aviso oscureciera en
## proporcion al golpe que viene, el jugador leeria la factura antes de tiempo y
## la decision de prepararse dejaria de tener riesgo.
const WEIGHT_WARNING := 0.35
const WEIGHT_ASH := 0.7

var _env: Environment = null
var _sun: DirectionalLight3D = null
var _tween: Tween = null

## Los valores originales, para poder devolverlos tal cual.
var _clear: Dictionary = {}

func _ready() -> void:
	EventBus.storm_incoming.connect(_on_incoming)
	EventBus.storm_ash_started.connect(_on_ash)
	EventBus.storm_started.connect(_on_storm)
	EventBus.storm_false_alarm.connect(_on_false_alarm)
	EventBus.storm_ended.connect(_on_ended)
	# Ganada la Auditoria Final no hay fundido: el aire aclara de golpe y para siempre.
	EventBus.storm_halted_forever.connect(restore_now)

## La escena no existe todavía en `_ready` de un autoload, así que se busca
## perezosamente la primera vez que hace falta.
func _resolve() -> bool:
	if _env != null and _sun != null:
		return true
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var we := scene.get_node_or_null("WorldEnvironment")
	var light := scene.get_node_or_null("DirectionalLight")
	if we == null or light == null:
		return false
	_env = (we as WorldEnvironment).environment
	_sun = light as DirectionalLight3D
	if _env == null:
		return false
	_clear = {
		"bg": _env.background_color,
		"ambient": _env.ambient_light_color,
		"ambient_energy": _env.ambient_light_energy,
		"sun": _sun.light_energy,
	}
	# La niebla es lo que de verdad se ve: la hierba de la isla usa un shader
	# propio que apenas responde a la luz, asi que bajar el sol solo no cambia
	# nada en pantalla. La niebla si tine todo por profundidad, y ademas es
	# exactamente lo que hace una tormenta de ceniza: comerse el horizonte.
	_env.fog_enabled = true
	_env.fog_light_color = ASH_LIGHT
	_env.fog_density = 0.0
	return true

# ── Transiciones ─────────────────────────────────────────────────────

## Se oscurece desde el Aviso, no desde el impacto: el cielo cerrándose **es**
## el aviso. Para cuando el texto aparece, el jugador ya lo ha notado.
func _on_incoming(_seconds: float) -> void:
	_close_to(WEIGHT_WARNING)

## Cae ceniza: el cielo se cierra mas, pero todavia no del todo. El salto entre
## una fase y la siguiente es lo que le dice al jugador que esto va a peor sin
## necesidad de un solo numero en pantalla.
func _on_ash() -> void:
	_close_to(WEIGHT_ASH)

## Ya encima, y solo ahora la severidad se ve. El suelo es alto a proposito:
## incluso la tormenta mas floja tiene que oscurecer lo bastante como para que
## se note sin leer nada.
func _on_storm(severity: int) -> void:
	_close_to(clampf(float(severity) / float(maxi(1, GameConfig.storm_severity_max)), 0.6, 1.0))

## El Aviso no era nada. El cielo se despeja sin mas explicacion: el jugador se
## entera de que era falsa alarma mirando por la ventana, no leyendo un aviso.
func _on_false_alarm(_deferred: int) -> void:
	_clear_sky()

func _close_to(weight: float) -> void:
	if not _resolve():
		return
	_start_tween()
	_tween.tween_property(_env, "background_color", _clear["bg"].lerp(ASH, weight), FADE_IN)
	_tween.parallel().tween_property(_env, "ambient_light_color", _clear["ambient"].lerp(ASH_LIGHT, weight), FADE_IN)
	_tween.parallel().tween_property(_env, "ambient_light_energy",
		lerpf(_clear["ambient_energy"], _clear["ambient_energy"] * 0.3, weight), FADE_IN)
	_tween.parallel().tween_property(_sun, "light_energy",
		lerpf(_clear["sun"], _clear["sun"] * 0.15, weight), FADE_IN)
	_tween.parallel().tween_property(_env, "fog_density", MAX_FOG * weight, FADE_IN)
	_tween.parallel().tween_property(_env, "fog_light_color", ASH_LIGHT, FADE_IN)

func _on_ended(_severity: int) -> void:
	_clear_sky()

func _clear_sky() -> void:
	if not _resolve():
		return
	_start_tween()
	_tween.tween_property(_env, "background_color", _clear["bg"], FADE_OUT)
	_tween.parallel().tween_property(_env, "ambient_light_color", _clear["ambient"], FADE_OUT)
	_tween.parallel().tween_property(_env, "ambient_light_energy", _clear["ambient_energy"], FADE_OUT)
	_tween.parallel().tween_property(_sun, "light_energy", _clear["sun"], FADE_OUT)
	_tween.parallel().tween_property(_env, "fog_density", 0.0, FADE_OUT)

func _start_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT)

## Devuelve el cielo al instante. Para cargar partida o empezar de cero.
func restore_now() -> void:
	if not _resolve():
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_env.background_color = _clear["bg"]
	_env.ambient_light_color = _clear["ambient"]
	_env.ambient_light_energy = _clear["ambient_energy"]
	_sun.light_energy = _clear["sun"]
	_env.fog_density = 0.0
