extends CanvasModulate
## La Tormenta en la vista 2D: el mapa se tine y, al llegar, un golpe de
## oscuridad con una rafaga de ceniza.
##
## Es la pareja de StormSky (que en 2D no tiene WorldEnvironment ni sol que
## tocar) con las mismas reglas (docs/21 §12, "la Tormenta corta a la vista"):
## el Aviso y la Ceniza apenas tinen (GameConfig.storm_visual_warning / _ash);
## al empezar la Tormenta hay un GOLPE corto (se cierra en
## storm_visual_punch_in s hasta el peso de la severidad, aguanta
## storm_visual_punch s con la ceniza cruzando la pantalla empujada por el
## viento y se abre en storm_visual_punch_out s) y despues el mapa se queda en
## el tono de fondo (storm_visual_linger) hasta que pasa. La severidad solo se
## ve en el golpe. Solo aspecto: la mecanica y las fases no cambian.
##
## Lee la fase de StormManager cada frame (dos lerp sobre un color, sin
## materiales). Asi una partida cargada en plena ceniza abre tenida sin
## re-derivar nada, y la Auditoria Final ganada (tormenta detenida) aclara
## sola. Lo unico que escucha es `storm_started`, para el golpe: cargar a media
## Tormenta no lo repite.
##
## CanvasModulate solo tine el lienzo del mapa: la interfaz (CanvasLayer) queda
## igual de legible. La ceniza que cae va en su propia capa, por debajo de la UI.
##
## Dia y noche (DayClock, docs/21 §12): el mismo tinte parte del color del
## momento del dia (blanco de dia, anaranjado al alba y al ocaso, azul de noche,
## siempre legible) y la Tormenta se mezcla encima hacia la ceniza de siempre:
## con el golpe en pleno la hora no se nota.
##
## Que se note en 2D (feat/vista2d-y-prologo, ronda 1.0 mejora 11): con los
## pesos de la 3D (0.12-0.22 fuera del golpe) la 2D solo se calentaba un poco:
## la Tormenta "apenas cambiaba el color" y la noche era un azul leve. Ahora:
## - la 2D tiene SUELOS propios por fase (`VIEW_FLOOR`, `view_target`): el Aviso
##   ya se calienta, la Ceniza empieza a apagar y la Tormenta se queda en ceniza
##   de verdad; la 3D no cambia (target_weight sigue siendo el suyo);
## - la noche es un azul mas hondo (NIGHT_TINT), y las luces de la colonia
##   (NightLights2D, en su capa: el tinte no las apaga) la hacen legible;
## - una vineta (oscurece los bordes, el centro queda claro): azul de noche,
##   sepia de Tormenta; un solo rectangulo con textura, solo cambia su color;
## - ceniza que cae despacio durante la Ceniza y la Tormenta (`_drift`, pocas
##   motas por perfil), ademas de la rafaga del golpe.
## Todo apagado con calidad Minima salvo el tinte (GraphicsQuality.fx_enabled).

const StormSkyScript := preload("res://scripts/map/StormSky.gd")
const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")
const GraphicsQuality := preload("res://scripts/services/GraphicsQuality.gd")

## El tono al que tiende el mapa con la tormenta encima: ceniza CALIDA, sepia
## tirando a oxido (como el cielo y la luz de StormSky en 3D), no un gris frio:
## la maqueta se apaga pero sigue pareciendo de juguete (2026-10-12).
const ASH_TINT := Color(0.56, 0.43, 0.34)
## Lo poco tenido calienta el mapa antes de apagarlo (luz de tormenta). Hasta
## WARM_UNTIL de peso se va hacia WARN_TINT; desde ahi, hacia la ceniza.
const WARN_TINT := Color(0.98, 0.86, 0.70)
const WARM_UNTIL := 0.35
## El alba y el ocaso, y la noche (azul, pero se sigue leyendo el mapa).
const WARM_TINT := Color(1.0, 0.8, 0.62)
## Mas hondo que antes (0.56, 0.64, 0.92): de noche el mapa se lee por las
## luces, no por el tinte.
const NIGHT_TINT := Color(0.42, 0.5, 0.86)

## Peso minimo de tinte por fase en la 2D (sin golpe). La 3D tiene niebla, sol
## y cielo; la 2D solo el tinte, que con los pesos de la 3D no se notaba.
const VIEW_FLOOR := {
	StormCycleScript.Phase.WARNING: 0.3,
	StormCycleScript.Phase.ASH: 0.48,
	StormCycleScript.Phase.STORM: 0.6,
	StormCycleScript.Phase.TITHE: 0.6,
}
## Vineta: color y opacidad maxima de noche y con la Tormenta.
const VIGNETTE_NIGHT := Color(0.04, 0.06, 0.2)
const VIGNETTE_STORM := Color(0.16, 0.09, 0.04)
const VIGNETTE_NIGHT_ALPHA := 0.5
const VIGNETTE_STORM_ALPHA := 0.6
## Motas de la ceniza que cae despacio, por perfil.
const DRIFT_AMOUNT := {"pc": 60, "tablet": 40, "phone": 24}

var _weight := 0.0
var _ash: CPUParticles2D = null
var _ash_layer: CanvasLayer = null
var _drift: CPUParticles2D = null
var _vignette: TextureRect = null
var _lights_layer: CanvasLayer = null
var _lights: Node2D = null
var _vp_size := Vector2.ZERO
## Lo que le queda al golpe en curso (s) y su peso; 0 = sin golpe.
var _punch_left := 0.0
var _punch_peak := 0.0

func _ready() -> void:
	color = Color.WHITE
	# Las luces de la colonia: su propia capa, que sigue a la camara y que el
	# CanvasModulate no tine (por debajo de la vineta y de la interfaz).
	_lights_layer = CanvasLayer.new()
	_lights_layer.name = "LightsLayer"
	_lights_layer.layer = 1
	_lights_layer.follow_viewport_enabled = true
	add_child(_lights_layer)
	_lights = preload("res://scripts/view2d/NightLights2D.gd").new()
	_lights_layer.add_child(_lights)
	_ash_layer = CanvasLayer.new()
	_ash_layer.name = "AshLayer"
	_ash_layer.layer = 2
	add_child(_ash_layer)
	# La vineta: un degradado radial transparente en el centro, estirado a la
	# pantalla. Solo cambia su color (modulate).
	_vignette = TextureRect.new()
	_vignette.name = "Vignette"
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.texture = vignette_texture()
	_vignette.modulate = Color(VIGNETTE_NIGHT, 0.0)
	_vignette.visible = false
	_ash_layer.add_child(_vignette)
	# La ceniza que cae despacio (Ceniza y Tormenta).
	_drift = CPUParticles2D.new()
	_drift.name = "AshDrift"
	_drift.amount = int(DRIFT_AMOUNT.get(DeviceProfile.current(), 40))
	_drift.lifetime = 7.0
	_drift.preprocess = 4.0
	_drift.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_drift.direction = Vector2(0.35, 1.0)
	_drift.spread = 18.0
	_drift.gravity = Vector2(6, 12)
	_drift.initial_velocity_min = 30.0
	_drift.initial_velocity_max = 70.0
	_drift.scale_amount_min = 1.5
	_drift.scale_amount_max = 3.0
	_drift.color = Color(0.82, 0.74, 0.66, 0.65)
	_drift.emitting = false
	_ash_layer.add_child(_drift)
	# La rafaga del golpe: motas que cruzan la pantalla con el viento.
	_ash = CPUParticles2D.new()
	_ash.name = "Ash"
	_ash.amount = int(GameConfig.storm_visual_gust_amount.get(DeviceProfile.current(), 160))
	_ash.lifetime = 2.2
	_ash.preprocess = 0.6
	_ash.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_ash.direction = Vector2(1.0, 0.3)
	_ash.spread = 10.0
	_ash.gravity = Vector2(20, 40)
	_ash.initial_velocity_min = 260.0
	_ash.initial_velocity_max = 420.0
	_ash.scale_amount_min = 2.0
	_ash.scale_amount_max = 4.5
	_ash.color = Color(0.86, 0.76, 0.66, 0.8)
	_ash.emitting = false
	_ash_layer.add_child(_ash)
	EventBus.storm_started.connect(_on_storm_started)

func _on_storm_started(severity: int) -> void:
	# Con el suelo de la 2D en la Tormenta, el golpe tiene que ir mas alla para notarse.
	_punch_peak = maxf(punch_weight(severity), float(VIEW_FLOOR[StormCycleScript.Phase.STORM]) + 0.2)
	_punch_left = maxf(0.1, GameConfig.storm_visual_punch)

## Peso de tinte que pide la fase actual fuera del golpe (0 = despejado).
static func target_weight(phase: int, _severity: int, halted: bool) -> float:
	if halted:
		return 0.0
	match phase:
		StormCycleScript.Phase.WARNING:
			return StormSkyScript.warning_weight()
		StormCycleScript.Phase.ASH:
			return StormSkyScript.ash_weight()
		StormCycleScript.Phase.STORM, StormCycleScript.Phase.TITHE:
			return StormSkyScript.linger_weight()
	return 0.0

## El peso que pide la fase EN LA 2D: el de la 3D con el suelo de VIEW_FLOOR
## (despejado y Auditoria ganada siguen en 0).
static func view_target(phase: int, severity: int, halted: bool) -> float:
	if halted:
		return 0.0
	return maxf(target_weight(phase, severity, halted), float(VIEW_FLOOR.get(phase, 0.0)))

## ¿Cae ceniza despacio en esta fase? (Ceniza y Tormenta, no detenida.)
static func drifting(phase: int, halted: bool) -> bool:
	if halted:
		return false
	return phase == StormCycleScript.Phase.ASH or phase == StormCycleScript.Phase.STORM or phase == StormCycleScript.Phase.TITHE

## Intensidad de las luces de la colonia: de noche (1 - luz del dia) y, con la
## Tormenta, en proporcion a lo apagado del mapa. Pura, para las pruebas.
static func lights_for(light: float, storm_weight: float) -> float:
	var night := clampf(1.0 - light, 0.0, 1.0)
	return clampf(maxf(smoothstep(0.15, 0.85, night), (storm_weight - 0.35) * 1.4), 0.0, 1.0)

## La vineta: color (de noche azul, con Tormenta sepia) y opacidad. Pura.
static func vignette_for(light: float, storm_weight: float) -> Color:
	var night := clampf(1.0 - light, 0.0, 1.0)
	var s := clampf(storm_weight, 0.0, 1.0)
	var col := VIGNETTE_NIGHT.lerp(VIGNETTE_STORM, s / maxf(0.001, s + night))
	return Color(col, maxf(night * night * VIGNETTE_NIGHT_ALPHA, s * VIGNETTE_STORM_ALPHA))

## Degradado radial: transparente en el centro, negro en las esquinas.
static var _vignette_tex: Texture2D = null
static func vignette_texture() -> Texture2D:
	if _vignette_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0))
		g.set_color(1, Color(1, 1, 1, 1))
		g.add_point(0.55, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.15, 0.5)
		t.width = 128
		t.height = 128
		_vignette_tex = t
	return _vignette_tex

## El peso del golpe para una severidad (el mismo que en 3D).
static func punch_weight(severity: int) -> float:
	return StormSkyScript.punch_weight(severity)

## El tinte del momento del dia: `light` 1 = dia pleno (blanco), 0 = noche;
## `warm` el peso del sol bajo (DayCycle.warm_weight()).
static func day_tint(light: float, warm: float) -> Color:
	var n := 1.0 - light
	return Color.WHITE.lerp(WARM_TINT, warm * 0.8).lerp(NIGHT_TINT, n * n)

## El color del CanvasModulate para un peso de oscuridad: primero se calienta
## (lo poco tenido), despues se apaga hacia la ceniza calida (el golpe).
static func tint_for(weight: float) -> Color:
	var w := clampf(weight, 0.0, 1.0)
	if w <= WARM_UNTIL:
		return Color.WHITE.lerp(WARN_TINT, w / WARM_UNTIL)
	return WARN_TINT.lerp(ASH_TINT, (w - WARM_UNTIL) / (1.0 - WARM_UNTIL))

func current_weight() -> float:
	return _weight

func in_punch() -> bool:
	return _punch_left > 0.0

## Vineta, luces y ceniza lenta. Solo se escribe lo que cambia (un color, un
## alfa, un booleano): nada se repinta por fotograma.
func _update_mood(light: float, fx: bool, drift: bool) -> void:
	var lights_on := lights_for(light, _weight) if fx else 0.0
	if _lights != null:
		_lights.call("set_intensity", lights_on)
	var vig := vignette_for(light, _weight) if fx else Color(0, 0, 0, 0)
	var vig_on := vig.a > 0.01
	if _vignette.visible != vig_on:
		_vignette.visible = vig_on
	if vig_on and not _vignette.modulate.is_equal_approx(vig):
		_vignette.modulate = vig
	var want_drift := drift and fx
	if want_drift:
		var vp := get_viewport().get_visible_rect().size
		if vp != _vp_size or not _drift.emitting:
			_vp_size = vp
			# Cae desde por encima de la pantalla y un poco a la izquierda (viento).
			_drift.position = Vector2(vp.x * 0.4, -20.0)
			_drift.emission_rect_extents = Vector2(vp.x * 0.65, 30.0)
			_drift.lifetime = maxf(4.0, vp.y / 55.0)
	if _drift.emitting != want_drift:
		_drift.emitting = want_drift

func lights() -> Node2D:
	return _lights

## Herramientas de captura: >= 0 fija el peso sin mirar la tormenta.
var forced_weight := -1.0

func _process(delta: float) -> void:
	var halted: bool = StormManager.is_halted()
	var phase: int = StormManager.get_phase()
	var target := view_target(phase, StormManager.get_severity(), halted)
	var seconds := StormSkyScript.FADE_IN if target > _weight else StormSkyScript.FADE_OUT
	if _punch_left > 0.0:
		# El golpe se corta si la Tormenta ya no esta (falsa alarma no puede ser,
		# pero si la Auditoria ganada o un cambio de partida).
		if halted or phase != StormCycleScript.Phase.STORM:
			_punch_left = 0.0
		else:
			_punch_left -= delta
			target = _punch_peak
			seconds = maxf(0.05, GameConfig.storm_visual_punch_in)
	elif _weight > target and _weight > view_target(phase, 1, false) and phase == StormCycleScript.Phase.STORM:
		# Saliendo del golpe: se abre de prisa hasta el tono de fondo.
		seconds = maxf(0.05, GameConfig.storm_visual_punch_out)
	# Una diferencia de 1 se recorre en `seconds`; el golpe, en proporcion a su peso.
	_weight = move_toward(_weight, target, delta / seconds)
	if forced_weight >= 0.0:
		_weight = forced_weight
	# La Tormenta manda sobre la hora del dia: con el golpe en pleno el dia no pinta.
	var light: float = DayClock.light_weight()
	color = tint_for(_weight) * day_tint(light, DayClock.warm_weight()).lerp(Color.WHITE, _weight)
	var fx := GraphicsQuality.fx_enabled()
	_update_mood(light, fx, drifting(phase, halted))
	var gusting := _punch_left > 0.0 and fx
	if _ash.emitting == gusting and not gusting:
		return
	var vp := get_viewport().get_visible_rect().size
	# Emite desde el borde izquierdo y toda la altura (un poco por encima): la
	# rafaga entra por un lado y cruza la pantalla.
	_ash.position = Vector2(vp.x * 0.2, vp.y * 0.45)
	_ash.emission_rect_extents = Vector2(vp.x * 0.45, vp.y * 0.6)
	if _ash.emitting != gusting:
		_ash.emitting = gusting
