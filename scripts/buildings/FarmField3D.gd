extends Node3D
## El cultivo de la Granja en 3D (2026-10-04): crece con el ciclo del cultivo
## (ProductionManager.get_cycle_progress), se dora al madurar, se mece con el
## viento y, con la cosecha esperando a ser recogida, se queda alto y dorado. El
## molino de aspas ("WindRotor", hermano en la malla) gira mientras la granja
## trabaja. Lo crea DieselpunkBuildingFactory._build_farm(); no escucha senales:
## relee cada poco, como el aspecto del edificio.
##
## En una vista previa (menu CONSTRUIR, fantasma de colocar) no hay edificio
## detras: el campo se ensena a media altura y verde.

const REFRESH := 0.2
const GREEN := Color(0.35, 0.7, 0.22)
const RIPE := Color(0.88, 0.72, 0.25)

var _building: Node = null
var _looked := false
var _timer := 0.0
var _growth := 0.6
var _ripe := false
var _working := false
var _rotor: Node3D = null

func _ready() -> void:
	_rotor = get_parent().get_node_or_null("WindRotor") as Node3D
	_apply()

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	rotation.z = sin(t * 1.3 + position.x) * 0.025
	if _rotor != null and _working:
		_rotor.rotation.z -= delta * 1.6
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH
	if not _looked or (_building != null and not is_instance_valid(_building)):
		_building = _find_building()
		_looked = true
	if _building == null:
		return
	var data: BuildingData = null
	var info := GridManager.get_building_info(_building)
	if not info.is_empty():
		data = info["data"]
	_ripe = ProductionManager.has_stock(_building)
	_working = data != null and ProductionManager.can_work(_building, data) and not ProductionManager.is_full(_building)
	_growth = 1.0 if _ripe and not _working else ProductionManager.get_cycle_progress(_building)
	if _building.has_meta("under_construction"):
		_growth = 0.0
	_apply()

## El cultivo de 0 (recien plantado) a 1 (listo), y el color de verde a dorado.
func _apply() -> void:
	var g := clampf(_growth, 0.0, 1.0)
	scale = Vector3(1.0, lerpf(0.12, 1.0, g), 1.0)
	var mat: Variant = get_meta("crop_material", null)
	if mat is StandardMaterial3D:
		var c := GREEN.lerp(RIPE, clampf((g - 0.55) / 0.45, 0.0, 1.0))
		if _ripe and not _working:
			c = RIPE
		(mat as StandardMaterial3D).albedo_color = c

## El edificio de la rejilla del que cuelga esta malla (3 o 4 niveles arriba).
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
	return _growth
