extends GdUnitTestSuite
## Una partida guardada en 3D se carga en 2D, y al reves (docs/18-vista-2d.md).
##
## Recorrido real, sin atajos: el colocador y el mapa 3D cargan una partida
## sembrada con GameManager, GameManager.save_game() la escribe, se desmonta la
## vista 3D, el colocador y el mapa 2D cargan ESE fichero y se comprueba que
## cada edificio y cada yacimiento esta en su celda, con su giro, nivel, vida,
## nombre, obra pendiente y usos. Luego el 2D vuelve a guardar y el resultado es
## el mismo que escribio el 3D.
##
## Aparta el guardado del jugador y lo devuelve al terminar. Deja GameManager,
## GridManager, ResourceManager y ProductionManager como estaban.

const Placer3D := preload("res://scripts/buildings/BuildingPlacer.gd")
const MapGen3D := preload("res://scripts/map/MapGenerator.gd")
const Placer2D := preload("res://scripts/view2d/BuildingPlacer2D.gd")
const MapGen2D := preload("res://scripts/view2d/MapGenerator2D.gd")
const Building2D := preload("res://scripts/view2d/Building2D.gd")
const Deposit2D := preload("res://scripts/view2d/Deposit2D.gd")

const SAVE_PATH := "user://save_game.json"
const BACKUP_PATH := "user://save_game.view2d_compat.bak"

const BUILDINGS := [
	{"id": "nucleo", "cell_x": 20, "cell_y": 20},
	{"id": "house", "cell_x": 17, "cell_y": 20, "custom_name": "Casa del capataz"},
	{"id": "sawmill", "cell_x": 15, "cell_y": 17, "rotation": 1},
	{"id": "gold_mine", "cell_x": 25, "cell_y": 17, "level": 2},
	{"id": "warehouse", "cell_x": 24, "cell_y": 20},
	{"id": "tower", "cell_x": 24, "cell_y": 22, "health": 40},
	{"id": "foundry", "cell_x": 26, "cell_y": 20, "construction_remaining": 30.0},
	{"id": "road", "cell_x": 19, "cell_y": 24},
	{"id": "road", "cell_x": 20, "cell_y": 24},
]
const DEPOSITS := [
	{"id": "forest", "cell_x": 12, "cell_y": 16, "size_x": 3, "size_y": 3, "uses_remaining": 4},
	{"id": "gold_vein", "cell_x": 25, "cell_y": 14, "size_x": 2, "size_y": 3},
	{"id": "oil_well", "cell_x": 5, "cell_y": 5, "size_x": 2, "size_y": 2, "uses_remaining": 1},
]

var _scene: Node = null
var _placer: Node = null
var _map: Node = null
var _gm: Dictionary = {}
var _resources: Dictionary = {}
var _unlocks: Dictionary = {}
var _warehouses := 0
var _era := 1
var _dev_mode := true

func before_test() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.rename_absolute(SAVE_PATH, BACKUP_PATH)
	_gm = {"placer": GameManager._placer, "map": GameManager._map_gen, "camera": GameManager._camera,
		"started": GameManager._started, "hold": GameManager._hold_start}
	_resources = ResourceManager.get_all().duplicate()
	_unlocks = ResourceManager.get_unlock_state().duplicate()
	_warehouses = ResourceManager.get_warehouse_count()
	_era = ResourceManager.get_era()
	# Con dev_mode las obras duran 1-2 s: la obra pendiente tiene que seguir ahi.
	_dev_mode = GameConfig.dev_mode
	GameConfig.dev_mode = false
	GridManager.clear_all()

func after_test() -> void:
	_close_view()
	GameConfig.dev_mode = _dev_mode
	var by_name := {}
	for type in _resources:
		by_name[ResourceManager.get_type_name(type)] = _resources[type]
	ResourceManager.set_unlock_state(_unlocks)
	ResourceManager.set_era(_era)
	ResourceManager.set_warehouse_count(_warehouses)
	ResourceManager.set_amounts(by_name)
	# Lo que dejo otro test puede estar ya liberado: se devuelve solo lo vivo.
	GameManager._placer = _alive(_gm["placer"])
	GameManager._map_gen = _alive(_gm["map"])
	GameManager._camera = _alive(_gm["camera"])
	GameManager._started = _gm["started"]
	GameManager._hold_start = _gm["hold"]
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.rename_absolute(BACKUP_PATH, SAVE_PATH)

func _alive(v: Variant) -> Node:
	return v if is_instance_valid(v) else null

# ── Montar y desmontar una vista ──────────────────────────────────────

## Monta la vista (3D o 2D) bajo una escena de pruebas y deja que GameManager
## cargue save_game.json por su camino de siempre.
func _open_view(two_d: bool) -> void:
	_scene = get_tree().current_scene
	GridManager.clear_all()
	GameManager._placer = null
	GameManager._map_gen = null
	GameManager._camera = null
	GameManager._started = false
	GameManager._hold_start = false
	GameManager._warehouse_count = 0
	_placer = (Placer2D if two_d else Placer3D).new()
	_placer.name = "BuildingPlacer"
	_map = (MapGen2D if two_d else MapGen3D).new()
	_map.name = "MapGenerator"
	add_child(_placer)
	add_child(_map)   # registra el segundo: aqui GameManager carga la partida

func _close_view() -> void:
	for info in GridManager.get_all_buildings():
		ProductionManager.unregister(info["node"])
	if is_instance_valid(_placer):
		_placer.clear_all_buildings()
		remove_child(_placer)
		_placer.free()
	if is_instance_valid(_map):
		_map.clear_all_deposits()
		remove_child(_map)
		_map.free()
	_placer = null
	_map = null
	GridManager.clear_all()
	GameManager._started = false
	GameManager._placer = null
	GameManager._map_gen = null

func _write_seed() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"resources": {"gold": 300, "steel": 0, "oil": 0, "wood": 200},
		"buildings": BUILDINGS,
		"deposits": DEPOSITS,
	}, "\t"))
	f.close()

func _read_save() -> Dictionary:
	var json := JSON.new()
	json.parse(FileAccess.get_file_as_string(SAVE_PATH))
	return json.data

## Lo que importa de un guardado, sin marcas de tiempo ni orden.
func _essence(save: Dictionary) -> Dictionary:
	var b: Array = []
	for e in save.get("buildings", []):
		var entry: Dictionary = (e as Dictionary).duplicate()
		for k in ["cell_x", "cell_y", "rotation", "level", "health"]:
			if entry.has(k):
				entry[k] = int(entry[k])
		# La obra avanza unos milisegundos entre guardado y guardado.
		if entry.has("construction_remaining"):
			entry["construction_remaining"] = snappedf(float(entry["construction_remaining"]), 1.0)
		b.append(JSON.stringify(entry, "", true))
	b.sort()
	var d: Array = []
	for e in save.get("deposits", []):
		var entry: Dictionary = (e as Dictionary).duplicate()
		for k in entry:
			if entry[k] is float:
				entry[k] = int(entry[k])
		d.append(JSON.stringify(entry, "", true))
	d.sort()
	return {"buildings": b, "deposits": d}

# ── Casos ─────────────────────────────────────────────────────────────

func test_a_save_written_by_the_3d_view_loads_in_the_2d_view() -> void:
	_write_seed()
	_open_view(false)
	assert_bool(GameManager._started).is_true()
	GameManager.save_game()
	var saved_3d := _read_save()
	_close_view()

	_open_view(true)
	assert_bool(GameManager._started).is_true()
	# Cada edificio en su celda, como nodo 2D, con sus metadatos.
	for entry in BUILDINGS:
		var cell := Vector2i(int(entry["cell_x"]), int(entry["cell_y"]))
		var node: Node = GridManager.get_building_at(cell)
		assert_object(node).override_failure_message("sin edificio en %s" % cell).is_not_null()
		assert_bool(node.get_script() == Building2D).is_true()
		var info := GridManager.get_building_info(node)
		assert_str((info["data"] as BuildingData).id).is_equal(String(entry["id"]))
		assert_that(info["origin_cell"]).is_equal(cell)
		assert_int(int(node.get_meta("rotation_steps", 0))).is_equal(int(entry.get("rotation", 0)))
		assert_int(int(node.get_meta("level", 1))).is_equal(int(entry.get("level", 1)))
		if entry.has("health"):
			assert_int(int(node.get_meta("health"))).is_equal(int(entry["health"]))
		if entry.has("custom_name"):
			assert_str(String(node.get_meta("custom_name"))).is_equal(String(entry["custom_name"]))
		if entry.has("construction_remaining"):
			assert_bool(ProductionManager.is_constructing(node)).is_true()
			assert_object(node.get_node_or_null("ConstructionLabel")).is_not_null()
	# El aserradero girado ocupa 1x2.
	assert_object(GridManager.get_building_at(Vector2i(15, 18))).is_same(GridManager.get_building_at(Vector2i(15, 17)))
	assert_object(GridManager.get_building_at(Vector2i(16, 17))).is_null()
	# Los yacimientos, en su sitio, con sus usos.
	for entry in DEPOSITS:
		var cell := Vector2i(int(entry["cell_x"]), int(entry["cell_y"]))
		var dep: Node = GridManager.get_building_at(cell)
		assert_object(dep).is_not_null()
		assert_bool(dep.get_script() == Deposit2D).is_true()
		assert_str(String(dep.get_meta("deposit_id"))).is_equal(String(entry["id"]))
		assert_that(dep.get_meta("deposit_size")).is_equal(Vector2i(int(entry["size_x"]), int(entry["size_y"])))
		if entry.has("uses_remaining"):
			assert_int(int(dep.get_meta("uses_remaining"))).is_equal(int(entry["uses_remaining"]))
		var far_corner := cell + Vector2i(int(entry["size_x"]) - 1, int(entry["size_y"]) - 1)
		assert_object(GridManager.get_building_at(far_corner)).is_same(dep)
	# Y el 2D guarda exactamente lo mismo que habia guardado el 3D.
	GameManager.save_game()
	assert_dict(_essence(_read_save())).is_equal(_essence(saved_3d))

func test_a_save_written_by_the_2d_view_loads_in_the_3d_view() -> void:
	_write_seed()
	_open_view(true)
	GameManager.save_game()
	var saved_2d := _read_save()
	_close_view()

	_open_view(false)
	for entry in BUILDINGS:
		var cell := Vector2i(int(entry["cell_x"]), int(entry["cell_y"]))
		var node: Node = GridManager.get_building_at(cell)
		assert_object(node).is_not_null()
		assert_bool(node is Node3D).is_true()
		assert_str((GridManager.get_building_info(node)["data"] as BuildingData).id).is_equal(String(entry["id"]))
	GameManager.save_game()
	assert_dict(_essence(_read_save())).is_equal(_essence(saved_2d))

func test_the_warehouse_counts_toward_storage_in_the_2d_view() -> void:
	_write_seed()
	_open_view(true)
	assert_int(ResourceManager.get_warehouse_count()).is_equal(1)
