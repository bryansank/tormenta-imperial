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
##
## Dia y noche (DayClock, docs/21 §12): los valores "limpios" de Main.tscn son
## los del mediodia. Cada `GameConfig.day_cycle_refresh` segundos se calculan
## los del momento del dia (`_day`: amanecer y atardecer calidos, noche azulada
## pero legible) y la Tormenta se mezcla ENCIMA de ellos hacia la misma ceniza
## de siempre: con la Tormenta en pleno la noche no se nota (la ceniza manda) y
## al pasar vuelve la luz de la hora que sea. Nada se recalcula por frame salvo
## durante los fundidos de la Tormenta (3-5 s), como antes. Tambien mueve un
## parametro del material de ventanas y faroles (`ToyPalette.glow_material()`,
## uno para todo el mapa): de noche brillan mas, de dia menos.

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
const Palette := preload("res://scripts/buildings/ToyPalette.gd")

# ── La luz del dia (multiplicadores y tonos sobre los valores limpios) ──

## El sol bajo del alba y del ocaso, y la luna. La luna es azulada y floja,
## pero el publico tiene 10-15 anos: la noche nunca es oscura de verdad.
const SUN_WARM := Color(1.0, 0.62, 0.38)
const SUN_MOON := Color(0.66, 0.76, 1.0)
const NIGHT_SUN := 0.5
const AMBIENT_WARM := Color(1.0, 0.76, 0.6)
const AMBIENT_NIGHT := Color(0.66, 0.74, 1.0)
const NIGHT_AMBIENT := 1.0
const BG_WARM := Color(0.95, 0.64, 0.46)
const BG_NIGHT := Color(0.22, 0.28, 0.44)
## El cielo procedural al ocaso y de noche (los mismos cuatro colores que SKY_KEYS).
const SKY_WARM := {
	"sky_top_color": Color(0.44, 0.48, 0.72),
	"sky_horizon_color": Color(1.0, 0.64, 0.42),
	"ground_horizon_color": Color(0.92, 0.66, 0.5),
	"ground_bottom_color": Color(0.24, 0.3, 0.44),
}
const SKY_NIGHT := {
	"sky_top_color": Color(0.26, 0.32, 0.5),
	"sky_horizon_color": Color(0.44, 0.5, 0.66),
	"ground_horizon_color": Color(0.42, 0.47, 0.62),
	"ground_bottom_color": Color(0.18, 0.22, 0.34),
}
## Cuanto baja el sol en el alba y el ocaso (radianes bajo el del mediodia) y
## cuanto gira de este a oeste. Nunca por debajo de MIN_ELEVATION: sombras
## largas, pero la maqueta se sigue leyendo.
const SUN_DIP := 0.42
const MIN_ELEVATION := 0.4
const SUN_SWEEP := 0.95
## Multiplicador del material de ventanas: de dia apagadas, de noche (y con la
## Tormenta encima) encendidas. Mas de 1 es HDR: con glow (calidad alta) brillan.
const GLOW_DAY := 0.8
const GLOW_NIGHT := 1.7
const GLOW_STORM := 1.4

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
## Los valores del momento del dia (los "limpios" de ahora). Se recalculan cada
## `day_cycle_refresh` segundos; la Tormenta se mezcla encima.
var _day: Dictionary = {}
var _refresh_left: float = 0.0
## El color original del material de ventanas (static: el material es uno para
## todo el mapa y sobrevive a la recarga, igual que su valor de fabrica).
static var _glow_base = null

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
	# Cambio de fase del dia: repinta ya, sin esperar al siguiente refresco.
	EventBus.day_phase_changed.connect(_on_day_phase)

## El dia se repinta cada pocos segundos, nunca por frame. Con el arbol en
## pausa no corre (y DayClock tampoco avanza).
func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = maxf(GameConfig.day_cycle_refresh, 0.25)
	refresh_day()

func _on_day_phase(_phase: int, _hour: float) -> void:
	refresh_day()

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
		}
		_capture_sun()
		var sky_mat := _sky_material()
		if sky_mat != null:
			for key in SKY_KEYS:
				_clear[key] = sky_mat.get(key)
	elif _clear_sun_id != _sun.get_instance_id():
		# Mismo Environment, luz nueva: la luz es un nodo de la escena recien
		# cargada, asi que llega limpia y su energia es la de cielo despejado.
		_clear_sun_id = _sun.get_instance_id()
		_capture_sun()
	# La niebla es lo que de verdad se ve: la hierba de la isla usa un shader
	# propio que apenas responde a la luz, asi que bajar el sol solo no cambia
	# nada en pantalla. La niebla si tine todo por profundidad, y ademas es
	# exactamente lo que hace una tormenta de ceniza: comerse el horizonte.
	_env.fog_enabled = true
	_env.fog_light_color = ASH_LIGHT
	_env.fog_density = 0.0
	_day = {}
	return true

## Energia, color y orientacion del sol limpio (el del mediodia).
func _capture_sun() -> void:
	_clear["sun"] = _sun.light_energy
	_clear["sun_color"] = _sun.light_color
	_clear["sun_rot"] = _sun.rotation

# ── El momento del dia ───────────────────────────────────────────────

## Los valores limpios de ahora, segun DayClock. Con el ciclo apagado (o en el
## dia pleno, salvo la orientacion del sol) son exactamente los de Main.tscn.
func _day_values() -> Dictionary:
	var light: float = DayClock.light_weight()
	var warm: float = DayClock.warm_weight()
	var n := 1.0 - light
	# Los colores de la noche entran mas tarde que la luz baja (n al cuadrado):
	# en mitad del ocaso manda el naranja, no un azul a medias.
	var nc := n * n
	var d := {}
	if _clear.is_empty():
		return d
	d["bg"] = (_clear["bg"] as Color).lerp(BG_WARM, warm * 0.7).lerp(BG_NIGHT, nc)
	d["ambient"] = (_clear["ambient"] as Color).lerp(AMBIENT_WARM, warm * 0.6).lerp(AMBIENT_NIGHT, nc)
	d["ambient_energy"] = float(_clear["ambient_energy"]) * lerpf(1.0, NIGHT_AMBIENT, n)
	d["sun"] = float(_clear["sun"]) * lerpf(1.0, NIGHT_SUN, n) * (1.0 - 0.1 * warm)
	d["sun_color"] = (_clear["sun_color"] as Color).lerp(SUN_WARM, warm * 0.85).lerp(SUN_MOON, nc)
	d["sun_rot"] = sun_rotation_for(_clear["sun_rot"], DayClock.sun_arc())
	for key in SKY_KEYS:
		if _clear.has(key):
			d[key] = (_clear[key] as Color).lerp(SKY_WARM[key], warm * 0.85).lerp(SKY_NIGHT[key], nc)
	return d

## La orientacion del sol (o de la luna) para un punto del arco: -1 este,
## 0 mediodia (la de Main.tscn tal cual), 1 oeste. Publica para auditarla.
static func sun_rotation_for(base: Vector3, arc: float) -> Vector3:
	if is_zero_approx(arc):
		return base
	var noon_elev := -base.x
	var low := maxf(noon_elev - SUN_DIP, MIN_ELEVATION)
	var elev := lerpf(low, noon_elev, 1.0 - arc * arc) if noon_elev > low else noon_elev
	return Vector3(-elev, base.y + arc * SUN_SWEEP, base.z)

## Recalcula el momento del dia y lo pinta (con la Tormenta que haya encima).
## Lo llama `_process` cada `day_cycle_refresh` segundos y el cambio de fase.
## Durante un fundido de la Tormenta solo actualiza `_day`: el fundido lo lee
## en cada paso, asi que no se pelean.
func refresh_day() -> void:
	if not _resolve():
		_paint_night(_night_for(_island_weight))
		_paint_glow(_island_weight)
		return
	_day = _day_values()
	if _tween != null and _tween.is_valid() and _tween.is_running():
		return
	_apply_weight(_island_weight)

## Cuanto se nota la noche con este peso de Tormenta: la ceniza manda.
func _night_for(storm_w: float) -> float:
	return (1.0 - DayClock.light_weight()) * (1.0 - storm_w)

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
	_fade_to(weight, FADE_IN)

func _on_ended(_severity: int) -> void:
	_clear_sky()

func _clear_sky() -> void:
	_fade_to(0.0, FADE_OUT)

## Funde la Tormenta de su peso actual a `weight` sobre la luz del momento.
## Un solo `tween_method`: cada paso mezcla `_day` con la ceniza.
func _fade_to(weight: float, seconds: float) -> void:
	if not _resolve():
		_paint_island(weight)
		_paint_night(_night_for(weight))
		_paint_glow(weight)
		return
	_day = _day_values()
	_start_tween()
	_tween.tween_method(_apply_weight, _island_weight, weight, seconds)

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
	_day = {}

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
		_paint_night(_night_for(weight))
		_paint_glow(weight)
		return
	_apply_now(weight)

func _apply_now(weight: float) -> void:
	_day = _day_values()
	_apply_weight(weight)

## Escribe todo: la luz del momento del dia (`_day`) con la Tormenta `weight`
## encima. Los objetivos de la ceniza salen de los valores limpios, no de los del
## dia: con la Tormenta en pleno da igual la hora (la ceniza manda), y la noche
## con Tormenta nunca queda mas oscura que la Tormenta de dia.
func _apply_weight(weight: float) -> void:
	if _env == null or not is_instance_valid(_sun) or _clear.is_empty():
		_paint_island(weight)
		return
	if _day.is_empty():
		_day = _day_values()
	_env.background_color = (_day["bg"] as Color).lerp(ASH, weight)
	_env.ambient_light_color = (_day["ambient"] as Color).lerp(ASH_LIGHT, weight)
	_env.ambient_light_energy = lerpf(_day["ambient_energy"], _clear["ambient_energy"] * 0.3, weight)
	_sun.light_energy = lerpf(_day["sun"], _clear["sun"] * 0.15, weight)
	_sun.light_color = (_day["sun_color"] as Color).lerp(_clear["sun_color"], weight)
	_sun.rotation = _day["sun_rot"]
	_env.fog_density = MAX_FOG * weight
	_env.fog_light_color = ASH_LIGHT
	_paint_sky(weight)
	_paint_island(weight)
	_paint_night(_night_for(weight))
	_paint_glow(weight)

## Tine el cielo procedural: el del momento del dia, `weight` hacia la ceniza.
func _paint_sky(weight: float) -> void:
	var sky_mat := _sky_material()
	if sky_mat == null:
		return
	for key in SKY_KEYS:
		if _day.has(key):
			sky_mat.set(key, (_day[key] as Color).lerp(SKY_KEYS[key], weight))

## Lo que pesa ahora la Tormenta sobre la isla. IslandGenerator lo pone en los
## materiales que crea, para que una isla rehecha a media tormenta salga oscura.
func get_island_weight() -> float:
	return _island_weight

## La noche que lleva ahora la isla (uniform `night_weight`). Lo lee
## IslandGenerator al crear los materiales.
func get_island_night_weight() -> float:
	return _night_for(_island_weight)

## Pone `weight` en el `storm_weight` de los materiales de la isla 3D de la
## escena actual (los nodos de IslandGenerator.NODE_NAMES). Sin isla, solo se
## recuerda el peso.
func _paint_island(weight: float) -> void:
	_island_weight = weight
	_set_island_param("storm_weight", weight)

## La noche de la isla (`night_weight`, storm_grade.gdshaderinc).
func _paint_night(night: float) -> void:
	_set_island_param("night_weight", night)

func _set_island_param(param: String, value: float) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	for node_name in IslandGen.NODE_NAMES:
		var mesh := tree.current_scene.get_node_or_null(node_name) as MeshInstance3D
		if mesh == null:
			continue
		var mat := mesh.get_surface_override_material(0) as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter(param, value)

## Las ventanas y faroles de todos los edificios: un solo material compartido
## (ToyPalette.glow_material(), sin luz), asi que basta un parametro para el mapa
## entero. Con un StandardMaterial3D es el `albedo_color` (multiplica el color
## por vertice); con un ShaderMaterial, el uniform `glow_gain` si lo tiene.
func _paint_glow(weight: float) -> void:
	var gain := lerpf(lerpf(GLOW_DAY, GLOW_NIGHT, 1.0 - DayClock.light_weight()), GLOW_STORM, weight)
	paint_glow_gain(gain)

## El multiplicador que lleva ahora el material de ventanas.
static func glow_gain_now() -> float:
	var mat: Material = Palette.glow_material()
	if mat is BaseMaterial3D and _glow_base != null:
		var base_c: Color = _glow_base
		if base_c.r > 0.0:
			return (mat as BaseMaterial3D).albedo_color.r / base_c.r
	return 1.0

static func paint_glow_gain(gain: float) -> void:
	var mat: Material = Palette.glow_material()
	if mat is BaseMaterial3D:
		var base_mat := mat as BaseMaterial3D
		if _glow_base == null:
			_glow_base = base_mat.albedo_color
		var c: Color = _glow_base
		base_mat.albedo_color = Color(c.r * gain, c.g * gain, c.b * gain, c.a)
	elif mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("glow_gain", gain)

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
## Tampoco toca la hora del dia: esa es de DayClock y de su propio reset().
func reset() -> void:
	_forget_scene()
	_clear = {}
	_clear_env = null
	_clear_sun_id = 0
	_island_weight = 0.0
	_refresh_left = 0.0

## Devuelve el cielo al instante (sin Tormenta, con la luz de la hora que sea).
## Para cargar partida o empezar de cero, y al ganar la Auditoria Final.
func restore_now() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not _resolve():
		_paint_island(0.0)
		_paint_night(_night_for(0.0))
		_paint_glow(0.0)
		return
	_apply_now(0.0)
