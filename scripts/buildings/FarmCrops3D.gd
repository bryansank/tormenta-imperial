extends MeshInstance3D
## Los bancales de la Granja en 3D (docs/03, "La Granja"): el nodo "Crops" del
## modelo horneado `assets/models/toy/farm.tscn`. La malla (tools/toy_crops.gd)
## lleva los tres cultivos y el rotor del molino; el shader compartido
## (`toy_crops.gdshader`) los hace crecer, madurar, mecerse y girar con
## parametros POR INSTANCIA. Aqui solo se leen los servicios cada REFRESH
## segundos y se tocan los parametros que cambian: ni nodos, ni mallas, ni
## materiales nuevos.
##
## - `growth`: el ciclo del cultivo (ProductionManager.get_cycle_progress); con
##   la cosecha esperando y la granja parada, 1 (alto y maduro).
## - `crop`: el cultivo elegido (indice en GameConfig.farm_crops).
## - `ripe`: hay cosecha que recoger (ProductionManager.has_stock).
## - `wind`: mas viento en la ceniza y la Tormenta.
## - `rotor_angle`: el molino gira mientras la granja trabaja (unico parametro
##   que se pone cada frame, y solo entonces).
##
## En una vista previa no hay edificio detras: se queda a media altura, verde.
## No escucha senales: relee cada poco, como FarmField3D antes y el aspecto del
## edificio (BuildingLook).

const REFRESH := 0.25
## Radianes por segundo del rotor trabajando.
const ROTOR_SPEED := 1.6
const WIND_CALM := 1.0
const WIND_ASH := 1.8
const WIND_STORM := 2.6

var _building: Node = null
var _looked := false
var _timer := 0.0
var _working := false
var _angle := 0.0
## Lo ultimo que se puso en cada parametro (solo se toca lo que cambia).
var _sent := {}

func _ready() -> void:
	# El shader sube y mece las plantas por encima de la malla horneada.
	extra_cull_margin = 0.8
	_put_param("growth", 0.6)

func _process(delta: float) -> void:
	if _working:
		_angle = fmod(_angle + delta * ROTOR_SPEED, TAU)
		set_instance_shader_parameter("rotor_angle", _angle)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH
	_refresh()

func _refresh() -> void:
	if not _looked or (_building != null and not is_instance_valid(_building)):
		_building = _find_building()
		_looked = true
	if _building == null:
		return
	var data: BuildingData = null
	var info := GridManager.get_building_info(_building)
	if not info.is_empty():
		data = info["data"]
	var ripe := ProductionManager.has_stock(_building)
	_working = data != null and ProductionManager.can_work(_building, data) and not ProductionManager.is_full(_building) \
		and not _building.has_meta("under_construction")
	var growth := ProductionManager.get_cycle_progress(_building)
	if ripe and not _working:
		growth = 1.0
	if _building.has_meta("under_construction"):
		growth = 0.0
	_put_param("growth", snappedf(clampf(growth, 0.0, 1.0), 0.005))
	_put_param("ripe", 1.0 if ripe else 0.0)
	_put_param("crop", float(crop_index(ProductionManager.get_crop(_building))))
	_put_param("wind", _wind())

## El indice del cultivo en GameConfig.farm_crops (el shader dibuja 0, 1, 2).
static func crop_index(crop_id: String) -> int:
	for i in GameConfig.farm_crops.size():
		if String(GameConfig.farm_crops[i]["id"]) == crop_id:
			return mini(i, 2)
	return 0

static func _wind() -> float:
	if StormManager.is_storming():
		return WIND_STORM
	if StormManager.is_ashfall():
		return WIND_ASH
	return WIND_CALM

func _put_param(param: String, value: float) -> void:
	if _sent.has(param) and is_equal_approx(float(_sent[param]), value):
		return
	_sent[param] = value
	set_instance_shader_parameter(param, value)

## El edificio de la rejilla del que cuelga este modelo (2 o 3 niveles arriba).
func _find_building() -> Node:
	var n: Node = get_parent()
	for i in 5:
		if n == null:
			return null
		if not GridManager.get_building_info(n).is_empty():
			return n
		n = n.get_parent()
	return null

## Para los tests y las vistas previas: cuanto ha crecido lo que se ve.
func get_growth() -> float:
	return float(_sent.get("growth", 0.6))

func is_working() -> bool:
	return _working
