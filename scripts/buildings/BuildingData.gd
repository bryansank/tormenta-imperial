class_name BuildingData
extends Resource
## Data definition for a building type. Each .tres file is one building kind.

const DATA_DIR := "res://data/buildings/"

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""

# Grid size in cells (e.g. 1x1, 2x2)
@export var grid_size: Vector2i = Vector2i(1, 1)

# Cost to build {ResourceManager.Type: amount}
@export var cost_gold: int = 0
@export var cost_steel: int = 0
@export var cost_oil: int = 0
@export var cost_wood: int = 0
## Materiales del taller que pide ademas (nombre -> cantidad): "planks",
## "ingots", "beams", "fuel". Solo los edificios avanzados (2026-09-28).
@export var cost_materials: Dictionary = {}

# Build time in seconds (0 = instant)
@export var build_time: float = 0.0

# Resource production per cycle (passive income)
@export var produces_gold: int = 0
@export var produces_steel: int = 0
@export var produces_oil: int = 0
@export var produces_wood: int = 0
@export var production_interval: float = 10.0  # seconds between production

# Visual
@export var mesh_height: float = 1.5
@export var mesh_color: Color = Color(0.5, 0.5, 0.5, 1.0)
@export var model_scene: PackedScene = null
## Escala del GLB dentro de su parcela. Los edificios que pasaron de 1x1 a 2x2
## (2026-09-28) llevan su modelo de siempre agrandado, en vez de uno nuevo.
@export var model_scale: float = 1.0
## Estirado por eje del GLB, encima de model_scale. El Aserradero y la Fundicion
## tenian modelo de 2x1 y ahora ocupan 2x2: se estiran en profundidad (Z) para
## llenar su parcela en vez de verse de dos casillas.
@export var model_stretch: Vector3 = Vector3.ONE

# Workers required to operate (0 = no workers needed)
@export var workers_required: int = 0

# Population capacity provided (only for houses)
@export var population_capacity: int = 0

# Morale bonus (decorations, special buildings)
@export var morale_bonus: int = 0

# Stats
@export var max_health: int = 100

# Core building (unique, auto-placed, cannot be built or moved)
@export var is_core: bool = false

# Decoration (no production, no workers, just morale)
@export var is_decoration: bool = false

## Tras colocarlo, el jugador sigue con otro igual en la mano (como las
## decoraciones). Por defecto no: se coloca uno y se sale (PlacementRules.keeps_placing).
@export var repeat_placement: bool = false

## Nombre para ensenar al jugador, en el idioma actual. `display_name` en el .tres
## queda como respaldo (y como referencia para el editor): cualquier texto que vea
## el jugador sale de aqui, nunca del campo crudo.
func get_display_name() -> String:
	return _translated("BLD_%s_NAME" % id.to_upper(), display_name)

## Descripcion en el idioma actual; mismo respaldo que el nombre.
func get_description() -> String:
	return _translated("BLD_%s_DESC" % id.to_upper(), description)

func _translated(key: String, fallback: String) -> String:
	var text: String = Tr.t(key)
	return fallback if text == key else text

## Helper: get cost as dictionary compatible with ResourceManager.
func get_cost() -> Dictionary:
	var cost := {}
	if cost_gold > 0:
		cost[ResourceManager.Type.GOLD] = cost_gold
	if cost_steel > 0:
		cost[ResourceManager.Type.STEEL] = cost_steel
	if cost_oil > 0:
		cost[ResourceManager.Type.OIL] = cost_oil
	if cost_wood > 0:
		cost[ResourceManager.Type.WOOD] = cost_wood
	for res_name in cost_materials:
		var type: int = ResourceManager.name_to_type(String(res_name))
		if type != -1 and int(cost_materials[res_name]) > 0:
			cost[type] = int(cost_materials[res_name])
	return cost

## Helper: check if this building produces any resources.
func is_producer() -> bool:
	return produces_gold > 0 or produces_steel > 0 or produces_oil > 0 or produces_wood > 0


## Every building definition, in an exported game too. An export renames each
## .tres to *.tres.remap, so scanning the folder with DirAccess for ".tres"
## found nothing there: the build menu came up EMPTY in the APK and the .exe
## while the editor looked fine. ResourceLoader.list_directory() lists the
## loadable names in both cases.
static func load_all() -> Array:
	var result: Array = []
	for file_name in resource_file_names(ResourceLoader.list_directory(DATA_DIR)):
		var res = load(DATA_DIR + file_name)
		if res is BuildingData:
			result.append(res)
	return result


## Keeps only resource file names and drops the ".remap" an export adds, once
## per resource. Pure, so the export case is testable from the editor.
static func resource_file_names(names: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for raw in names:
		var file_name := raw.trim_suffix(".remap")
		if (file_name.ends_with(".tres") or file_name.ends_with(".res")) and not out.has(file_name):
			out.append(file_name)
	return out

## El GLB instanciado a su escala (model_scale), o null si no tiene. Lo usan el
## mapa, el fantasma de colocar y las vistas previas de CONSTRUIR.
func instantiate_model() -> Node3D:
	if model_scene == null:
		return null
	var model := model_scene.instantiate() as Node3D
	if model != null and not is_equal_approx(model_scale, 1.0):
		model.scale *= model_scale
	if model != null and model_stretch != Vector3.ONE:
		model.scale *= model_stretch
	return model
