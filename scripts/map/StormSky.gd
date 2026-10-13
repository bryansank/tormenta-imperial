extends Node
## El cielo durante la Tormenta: la isla se apaga y se llena de ceniza.
##
## Sin esto la Tormenta es un número que baja y un aviso de texto. Con esto es
## algo que ves llegar por el horizonte, que es de lo que va el juego.
##
## No toca nada más: solo el `WorldEnvironment` (y su cielo procedural, si lo
## tiene) y la luz direccional de `Main`. Al pasar la tormenta devuelve los
## valores exactos que había, no unos por defecto.
##
## Con el cielo de maqueta (docs/21 §12) la luz ambiental sale sobre todo del
## cielo, asi que oscurecer el color de fondo ya no basta: tambien se tinen de
## ceniza los cuatro colores del `ProceduralSkyMaterial`, y con ellos la luz
## ambiental y los reflejos del agua.
##
## La isla tambien: el cesped, el canto, la playa, la espuma y el agua llevan el
## uniform `storm_weight` (scripts/map/storm_grade.gdshaderinc), y aqui se le
## da el mismo peso y el mismo fundido que al cielo. La espuma no tiene luz, asi
## que sin esto era lo unico blanco y limpio bajo la ceniza. El peso vive en este
## autoload: si la isla se rehace (grid_resized, recarga), IslandGenerator lo
## lee al crear los materiales y no se pierde la Tormenta.

## Cuánto tarda el cielo en cerrarse y en volver a abrirse.
const FADE_IN := 3.0
const FADE_OUT := 5.0

## El aire sucio del Imperio: ceniza de hierro, no nube de lluvia.
const ASH := Color(0.32, 0.27, 0.22)
const ASH_LIGHT := Color(0.55, 0.45, 0.35)

## Densidad de niebla con la tormenta encima. Lo bastante para comerse el fondo
## de la isla sin dejar al jugador sin ver donde construye. Con el suelo y el
## cielo nuevos (que si responden a la luz) basta mucho menos que antes (0.035,
## que lo dejaba todo de color arena).
const MAX_FOG := 0.014

## Los colores del cielo procedural que se tinen de ceniza, y hacia que tono.
const SKY_KEYS := {
	"sky_top_color": Color(0.24, 0.22, 0.21),
	"sky_horizon_color": Color(0.5, 0.42, 0.34),
	"ground_horizon_color": Color(0.45, 0.38, 0.31),
	"ground_bottom_color": Color(0.16, 0.15, 0.14),
}

## El cielo se cierra en tres pasos, uno por fase, y ninguno depende de la
## severidad hasta que la tormenta ya esta encima: si el Aviso oscureciera en
## proporcion al golpe que viene, el jugador leeria la factura antes de tiempo y
## la decision de prepararse dejaria de tener riesgo.
const WEIGHT_WARNING := 0.35
const WEIGHT_ASH := 0.7

const IslandGen := preload("res://scripts/map/IslandGenerator.gd")

var _env: Environment = null
var _sun: DirectionalLight3D = null
var _tween: Tween = null

## Los valores originales, para poder devolverlos tal cual.
var _clear: Dictionary = {}
## De que Environment son esos valores. El Environment de Main.tscn es un
## sub-recurso cacheado: al recargar la escena puede volver el MISMO objeto, con
## la ceniza que le dejo la partida anterior encima. Si se volvieran a leer ahi,
## el "cielo limpio" seria el oscuro. Solo se capturan de un Environment nuevo.
var _clear_env: Environment = null
## Y de que luz salio la energia del sol limpio.
var _clear_sun_id: int = 0
## El peso de Tormenta que lleva ahora la isla (0 = calma). Durante un fundido
## es el valor del momento.
var _island_weight: float = 0.0

func _ready() -> void:
	EventBus.storm_incoming.connect(_on_incoming)
	EventBus.storm_ash_started.connect(_on_ash)
	EventBus.storm_started.connect(_on_storm)
	EventBus.storm_false_alarm.connect(_on_false_alarm)
	EventBus.storm_ended.connect(_on_ended)
	# Ganada la Auditoria Final no hay fundido: el aire aclara de golpe y para siempre.
	EventBus.storm_halted_forever.connect(restore_now)
	# Al empezar o cargar partida la escena es otra: se vuelve a buscar el cielo
	# y se pinta el de la fase en la que esta la Tormenta, sin fundido.
	EventBus.game_new_started.connect(sync_to_storm)
	EventBus.game_load_completed.connect(sync_to_storm)

## La escena no existe todavía en `_ready` de un autoload, así que se busca
## perezosamente la primera vez que hace falta. Y se vuelve a buscar si la escena
## cambio: tras recargar, la luz vieja esta liberada.
func _resolve() -> bool:
	if _env != null and is_instance_valid(_sun) and _sun.is_inside_tree():
		return true
	_forget_scene()
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
		_sun = null
		return false
	if _clear_env != _env:
		_clear_env = _env
		_clear_sun_id = _sun.get_instance_id()
		_clear = {
			"bg": _env.background_color,
			"ambient": _env.ambient_light_color,
			"ambient_energy": _env.ambient_light_energy,
			"sun": _sun.light_energy,
		}
		var sky_mat := _sky_material()
		if sky_mat != null:
			for key in SKY_KEYS:
				_clear[key] = sky_mat.get(key)
	elif _clear_sun_id != _sun.get_instance_id():
		# Mismo Environment, luz nueva: la luz es un nodo de la escena recien
		# cargada, asi que llega limpia y su energia es la de cielo despejado.
		_clear_sun_id = _sun.get_instance_id()
		_clear["sun"] = _sun.light_energy
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
	_close_to(weight_for(StormCycle.Phase.STORM, severity))

## El Aviso no era nada. El cielo se despeja sin mas explicacion: el jugador se
## entera de que era falsa alarma mirando por la ventana, no leyendo un aviso.
func _on_false_alarm(_deferred: int) -> void:
	_clear_sky()

func _close_to(weight: float) -> void:
	if not _resolve():
		_paint_island(weight)
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
	var sky_mat := _sky_material()
	if sky_mat != null:
		for key in SKY_KEYS:
			if _clear.has(key):
				_tween.parallel().tween_property(sky_mat, key, (_clear[key] as Color).lerp(SKY_KEYS[key], weight), FADE_IN)
	_tween.parallel().tween_method(_paint_island, _island_weight, weight, FADE_IN)

func _on_ended(_severity: int) -> void:
	_clear_sky()

func _clear_sky() -> void:
	if not _resolve():
		_paint_island(0.0)
		return
	_start_tween()
	_tween.tween_property(_env, "background_color", _clear["bg"], FADE_OUT)
	_tween.parallel().tween_property(_env, "ambient_light_color", _clear["ambient"], FADE_OUT)
	_tween.parallel().tween_property(_env, "ambient_light_energy", _clear["ambient_energy"], FADE_OUT)
	_tween.parallel().tween_property(_sun, "light_energy", _clear["sun"], FADE_OUT)
	_tween.parallel().tween_property(_env, "fog_density", 0.0, FADE_OUT)
	var sky_mat := _sky_material()
	if sky_mat != null:
		for key in SKY_KEYS:
			if _clear.has(key):
				_tween.parallel().tween_property(sky_mat, key, _clear[key], FADE_OUT)
	_tween.parallel().tween_method(_paint_island, _island_weight, 0.0, FADE_OUT)

func _start_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT)

## Suelta las referencias a la escena. No toca `_clear`: esos valores son del
## Environment, no de la escena, y se conservan mientras el Environment sea el mismo.
func _forget_scene() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_env = null
	_sun = null

## Lo que pesa la ceniza en cada fase. Publico para poder auditarlo sin cielo.
static func weight_for(phase: int, severity: int) -> float:
	match phase:
		StormCycle.Phase.WARNING:
			return WEIGHT_WARNING
		StormCycle.Phase.ASH:
			return WEIGHT_ASH
		StormCycle.Phase.STORM:
			return clampf(float(severity) / float(maxi(1, GameConfig.storm_severity_max)), 0.6, 1.0)
	return 0.0

## Pinta al instante el cielo de la fase actual. Sin esto, cargar con la ceniza
## cayendo mostraba cielo limpio, y cargar en calma tras una partida oscura
## heredaba la oscuridad.
func sync_to_storm() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var weight: float = 0.0
	if not StormManager.is_halted():
		weight = weight_for(StormManager.get_phase(), StormManager.get_severity())
	if not _resolve():
		# Sin cielo (vista 2D, escena a medio montar): la isla 3D que se cree
		# despues leera este peso.
		_paint_island(weight)
		return
	_apply_now(weight)

func _apply_now(weight: float) -> void:
	_env.background_color = _clear["bg"].lerp(ASH, weight)
	_env.ambient_light_color = _clear["ambient"].lerp(ASH_LIGHT, weight)
	_env.ambient_light_energy = lerpf(_clear["ambient_energy"], _clear["ambient_energy"] * 0.3, weight)
	_sun.light_energy = lerpf(_clear["sun"], _clear["sun"] * 0.15, weight)
	_env.fog_density = MAX_FOG * weight
	_paint_sky(weight)
	_paint_island(weight)

## Tine el cielo procedural `weight` hacia la ceniza (0 = el limpio).
func _paint_sky(weight: float) -> void:
	var sky_mat := _sky_material()
	if sky_mat == null:
		return
	for key in SKY_KEYS:
		if _clear.has(key):
			sky_mat.set(key, (_clear[key] as Color).lerp(SKY_KEYS[key], weight))

## Lo que pesa ahora la Tormenta sobre la isla. IslandGenerator lo pone en los
## materiales que crea, para que una isla rehecha a media tormenta salga oscura.
func get_island_weight() -> float:
	return _island_weight

## Pone `weight` en el `storm_weight` de los materiales de la isla 3D de la
## escena actual (los nodos de IslandGenerator.NODE_NAMES). Sin isla, solo se
## recuerda el peso.
func _paint_island(weight: float) -> void:
	_island_weight = weight
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	for node_name in IslandGen.NODE_NAMES:
		var mesh := tree.current_scene.get_node_or_null(node_name) as MeshInstance3D
		if mesh == null:
			continue
		var mat := mesh.get_surface_override_material(0) as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("storm_weight", weight)

## El cielo procedural del Environment, o null si el fondo es un color liso.
func _sky_material() -> ProceduralSkyMaterial:
	if _env == null or _env.sky == null:
		return null
	return _env.sky.sky_material as ProceduralSkyMaterial

## Vuelve a estado de fabrica: sin escena, sin valores capturados. Para tests y
## para quien necesite empezar de cero de verdad.
##
## No se llama al recargar la escena: el Environment puede sobrevivir a la
## recarga con la ceniza puesta, y olvidar sus valores limpios seria perderlos.
func reset() -> void:
	_forget_scene()
	_clear = {}
	_clear_env = null
	_clear_sun_id = 0
	_island_weight = 0.0

## Devuelve el cielo al instante. Para cargar partida o empezar de cero.
func restore_now() -> void:
	if not _resolve():
		_paint_island(0.0)
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_env.background_color = _clear["bg"]
	_env.ambient_light_color = _clear["ambient"]
	_env.ambient_light_energy = _clear["ambient_energy"]
	_sun.light_energy = _clear["sun"]
	_env.fog_density = 0.0
	_paint_sky(0.0)
	_paint_island(0.0)
