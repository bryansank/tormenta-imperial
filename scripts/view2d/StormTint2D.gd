extends CanvasModulate
## La Tormenta en la vista 2D: el mapa se apaga y cae ceniza.
##
## Es la pareja de StormSky (que en 2D no tiene WorldEnvironment ni sol que
## tocar) con las mismas reglas: el cielo se cierra en tres pasos, uno por fase
## (Aviso 0.35, Ceniza 0.7, Tormenta segun la severidad, nunca menos de 0.6), y
## la severidad solo se ve cuando ya esta encima. Se cierra en FADE_IN segundos
## y se abre en FADE_OUT.
##
## No escucha senales: lee la fase de StormManager cada frame. Asi una partida
## cargada en plena ceniza abre oscura sin re-derivar nada, y la Auditoria Final
## ganada (tormenta detenida) aclara sola.
##
## CanvasModulate solo tine el lienzo del mapa: la interfaz (CanvasLayer) queda
## igual de legible. La ceniza que cae va en su propia capa, por debajo de la UI.

const StormSkyScript := preload("res://scripts/map/StormSky.gd")
const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")

## El tono al que tiende el mapa con la tormenta encima (ceniza de hierro).
const ASH_TINT := Color(0.46, 0.40, 0.35)

var _weight := 0.0
var _ash: CPUParticles2D = null
var _ash_layer: CanvasLayer = null

func _ready() -> void:
	color = Color.WHITE
	_ash_layer = CanvasLayer.new()
	_ash_layer.name = "AshLayer"
	_ash_layer.layer = 1
	add_child(_ash_layer)
	_ash = CPUParticles2D.new()
	_ash.name = "Ash"
	_ash.amount = 220
	_ash.lifetime = 6.0
	_ash.preprocess = 6.0
	_ash.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_ash.direction = Vector2(0.35, 1.0)
	_ash.spread = 15.0
	_ash.gravity = Vector2(10, 30)
	_ash.initial_velocity_min = 50.0
	_ash.initial_velocity_max = 110.0
	_ash.scale_amount_min = 2.0
	_ash.scale_amount_max = 4.5
	_ash.color = Color(0.78, 0.75, 0.70, 0.8)
	_ash.emitting = false
	_ash_layer.add_child(_ash)

## Peso de oscuridad que pide la fase actual (0 = despejado, 1 = lo peor).
static func target_weight(phase: int, severity: int, halted: bool) -> float:
	if halted:
		return 0.0
	match phase:
		StormCycleScript.Phase.WARNING:
			return StormSkyScript.WEIGHT_WARNING
		StormCycleScript.Phase.ASH:
			return StormSkyScript.WEIGHT_ASH
		StormCycleScript.Phase.STORM, StormCycleScript.Phase.TITHE:
			return clampf(float(severity) / float(maxi(1, GameConfig.storm_severity_max)), 0.6, 1.0)
	return 0.0

func current_weight() -> float:
	return _weight

## Herramientas de captura: >= 0 fija el peso sin mirar la tormenta.
var forced_weight := -1.0

func _process(delta: float) -> void:
	var target := target_weight(StormManager.get_phase(), StormManager.get_severity(), StormManager.is_halted())
	var fade := StormSkyScript.FADE_IN if target > _weight else StormSkyScript.FADE_OUT
	_weight = move_toward(_weight, target, delta / fade)
	if forced_weight >= 0.0:
		_weight = forced_weight
	color = Color.WHITE.lerp(ASH_TINT, _weight)
	var vp := get_viewport().get_visible_rect().size
	# Emite desde toda la pantalla (y un poco por encima): la ceniza aparece
	# repartida en el acto, no como una cortina que baja desde el borde.
	_ash.position = Vector2(vp.x * 0.5, vp.y * 0.4)
	_ash.emission_rect_extents = Vector2(vp.x * 0.6, vp.y * 0.6)
	var falling := _weight >= StormSkyScript.WEIGHT_ASH - 0.05
	if _ash.emitting != falling:
		_ash.emitting = falling
