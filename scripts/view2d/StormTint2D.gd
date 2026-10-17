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
const NIGHT_TINT := Color(0.56, 0.64, 0.92)

var _weight := 0.0
var _ash: CPUParticles2D = null
var _ash_layer: CanvasLayer = null
## Lo que le queda al golpe en curso (s) y su peso; 0 = sin golpe.
var _punch_left := 0.0
var _punch_peak := 0.0

func _ready() -> void:
	color = Color.WHITE
	_ash_layer = CanvasLayer.new()
	_ash_layer.name = "AshLayer"
	_ash_layer.layer = 1
	add_child(_ash_layer)
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
	_punch_peak = punch_weight(severity)
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

## Herramientas de captura: >= 0 fija el peso sin mirar la tormenta.
var forced_weight := -1.0

func _process(delta: float) -> void:
	var halted: bool = StormManager.is_halted()
	var phase: int = StormManager.get_phase()
	var target := target_weight(phase, StormManager.get_severity(), halted)
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
	elif _weight > target and _weight > StormSkyScript.linger_weight() and phase == StormCycleScript.Phase.STORM:
		# Saliendo del golpe: se abre de prisa hasta el tono de fondo.
		seconds = maxf(0.05, GameConfig.storm_visual_punch_out)
	# Una diferencia de 1 se recorre en `seconds`; el golpe, en proporcion a su peso.
	_weight = move_toward(_weight, target, delta / seconds)
	if forced_weight >= 0.0:
		_weight = forced_weight
	# La Tormenta manda sobre la hora del dia: con el golpe en pleno el dia no pinta.
	color = tint_for(_weight) * day_tint(DayClock.light_weight(), DayClock.warm_weight()).lerp(Color.WHITE, _weight)
	var gusting := _punch_left > 0.0 and GraphicsQuality.fx_enabled()
	if _ash.emitting == gusting and not gusting:
		return
	var vp := get_viewport().get_visible_rect().size
	# Emite desde el borde izquierdo y toda la altura (un poco por encima): la
	# rafaga entra por un lado y cruza la pantalla.
	_ash.position = Vector2(vp.x * 0.2, vp.y * 0.45)
	_ash.emission_rect_extents = Vector2(vp.x * 0.45, vp.y * 0.6)
	if _ash.emitting != gusting:
		_ash.emitting = gusting
