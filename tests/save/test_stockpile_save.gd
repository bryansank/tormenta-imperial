extends GdUnitTestSuite
## Lo acumulado en los edificios, el cultivo de cada Granja y su reloj viajan en
## el guardado (clave "stockpiles", 2026-10-04). La carga es idempotente, una
## celda sin edificio se ignora y un guardado anterior carga sin nada que
## recoger. Un guardado sin comida trae un poco para no morir de hambre al abrir.

const FARM := "res://data/buildings/farm.tres"
const SAWMILL := "res://data/buildings/sawmill.tres"
## Celdas lejos del centro de cualquier partida de prueba.
const FARM_CELL := Vector2i(2, 2)
const MILL_CELL := Vector2i(6, 2)

var _saved_producing: Dictionary = {}
var _saved_stock: Dictionary = {}
var _saved_crops: Dictionary = {}
var _saved_resources: Dictionary = {}
var _farm_node: Node3D
var _mill_node: Node3D

func before_test() -> void:
	_saved_producing = ProductionManager._producing
	_saved_stock = ProductionManager._stock
	_saved_crops = ProductionManager._crops
	ProductionManager._producing = {}
	ProductionManager._stock = {}
	ProductionManager._crops = {}
	_saved_resources = {}
	for type in ResourceManager.get_all():
		_saved_resources[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	_farm_node = _place(FARM, FARM_CELL)
	_mill_node = _place(SAWMILL, MILL_CELL)

func after_test() -> void:
	for node in [_farm_node, _mill_node]:
		if is_instance_valid(node):
			GridManager.remove_building(node)
			node.free()
	ProductionManager._producing = _saved_producing
	ProductionManager._stock = _saved_stock
	ProductionManager._crops = _saved_crops
	ResourceManager.set_amounts(_saved_resources)

func _place(path: String, cell: Vector2i) -> Node3D:
	var data := load(path) as BuildingData
	var node := Node3D.new()
	node.set_meta("staffed", true)
	assert_bool(GridManager.place_building(cell, data, node)).is_true()
	ProductionManager._producing[node] = {"timer": 0.0, "data": data}
	return node

func _snapshot() -> Array:
	ProductionManager._add_to_stock(_mill_node, {"wood": 42})
	ProductionManager._add_to_stock(_farm_node, {"food": 77})
	ProductionManager.plant_crop(_farm_node, "crop_long")
	ProductionManager._producing[_farm_node]["timer"] = 33.0
	ProductionManager._stock[_farm_node]["age"] = 900.0
	return JSON.parse_string(JSON.stringify(ProductionManager.get_save_data()))

func test_stock_crop_and_clock_survive_a_save() -> void:
	var saved := _snapshot()
	ProductionManager._stock.clear()
	ProductionManager._crops.clear()
	ProductionManager._producing[_farm_node]["timer"] = 0.0
	ProductionManager.load_save_data(saved)
	assert_dict(ProductionManager.get_stock(_mill_node)).is_equal({"wood": 42})
	assert_dict(ProductionManager.get_stock(_farm_node)).is_equal({"food": 77})
	assert_str(ProductionManager.get_crop(_farm_node)).is_equal("crop_long")
	assert_float(float(ProductionManager._producing[_farm_node]["timer"])).is_equal(33.0)
	assert_float(ProductionManager.get_stock_age(_farm_node)).is_equal(900.0)

func test_loading_twice_does_not_double_anything() -> void:
	var saved := _snapshot()
	ProductionManager.load_save_data(saved)
	ProductionManager.load_save_data(saved)
	assert_dict(ProductionManager.get_stock(_mill_node)).is_equal({"wood": 42})
	assert_dict(ProductionManager.get_stock(_farm_node)).is_equal({"food": 77})

func test_an_entry_without_a_building_is_ignored() -> void:
	ProductionManager.load_save_data([{"cell_x": 30, "cell_y": 30, "stock": {"wood": 5}},
		{"cell_x": MILL_CELL.x, "cell_y": MILL_CELL.y, "stock": {"unobtainium": 9, "wood": 3}}])
	assert_dict(ProductionManager.get_all_stock()).is_equal({"wood": 3})

func test_an_old_save_has_nothing_to_collect_and_default_crops() -> void:
	ProductionManager._add_to_stock(_mill_node, {"wood": 10})
	ProductionManager.load_save_data([])
	assert_dict(ProductionManager.get_all_stock()).is_empty()
	assert_str(ProductionManager.get_crop(_farm_node)).is_equal(GameConfig.farm_default_crop)

func test_reset_throws_everything_away() -> void:
	_snapshot()
	ProductionManager.reset()
	assert_dict(ProductionManager._stock).is_empty()
	assert_dict(ProductionManager._crops).is_empty()

func test_the_game_writes_and_reads_the_stockpiles() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/services/GameManager.gd")
	assert_bool(src.contains("data[\"stockpiles\"] = ProductionManager.get_save_data()")).is_true()
	var start: int = src.find("func _load_game")
	var end: int = src.find("\nfunc ", start + 1)
	var load_body := src.substr(start, end - start)
	assert_bool(load_body.contains("ProductionManager.load_save_data(")).is_true()
	assert_bool(load_body.contains("legacy_save_food")).is_true()

func test_a_save_without_food_loads_with_some() -> void:
	# Lo que hace el cargador con un guardado anterior a la comida.
	ResourceManager.set_amounts({"food": 0})
	var old := {"gold": 100, "wood": 50, "steel": 0, "oil": 0}
	ResourceManager.set_amounts(old)
	if not old.has("food"):
		ResourceManager.set_amounts({"food": GameConfig.legacy_save_food})
	assert_int(ResourceManager.get_amount(ResourceManager.Type.FOOD)).is_equal(GameConfig.legacy_save_food)
	assert_int(GameConfig.legacy_save_food).is_greater(0)

func test_a_new_game_resets_production_in_all_three_places() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/services/GameManager.gd")
	for fn in ["func _new_game", "func clear_save()", "func clear_save_and_reload_from"]:
		var start: int = src.find(fn)
		assert_int(start).is_greater(-1)
		var end: int = src.find("\nfunc ", start + 1)
		assert_bool(src.substr(start, end - start).contains("ProductionManager.reset()")).is_true()
