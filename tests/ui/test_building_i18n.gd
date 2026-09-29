extends GdUnitTestSuite
## Los nombres y descripciones de edificio, y los de los procesos en cola, se
## traducen al ensenarlos. Nada que vea el jugador sale crudo del .tres ni se
## congela traducido en el estado o en el guardado.

const BUILDINGS_DIR := "res://data/buildings/"

var _saved_locale := "es"
var _nodes: Array = []
var _saved_resources: Dictionary = {}

func before_test() -> void:
	_saved_locale = Tr.get_locale()
	_saved_resources = {}
	for type in ResourceManager.get_all():
		_saved_resources[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)

func after_test() -> void:
	Tr.set_locale(_saved_locale)
	for node in _nodes:
		if is_instance_valid(node):
			ProcessManager.cancel(node)
			GridManager.remove_building(node)
			node.free()
	_nodes.clear()
	ResourceManager.set_amounts(_saved_resources)

func _all_buildings() -> Array:
	var result: Array = []
	for file in DirAccess.get_files_at(BUILDINGS_DIR):
		if file.ends_with(".tres"):
			var data := load(BUILDINGS_DIR + file) as BuildingData
			if data:
				result.append(data)
	return result

func _process_def(building_id: String, process_id: String) -> Dictionary:
	for proc in ProcessManager.get_processes_for(building_id):
		if proc["id"] == process_id:
			return proc
	return {}

func test_every_building_has_a_name_and_description_in_both_languages() -> void:
	var buildings := _all_buildings()
	assert_int(buildings.size()).is_equal(16)
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for data in buildings:
			var name_key := "BLD_%s_NAME" % data.id.to_upper()
			var desc_key := "BLD_%s_DESC" % data.id.to_upper()
			assert_str(Tr.t(name_key)).override_failure_message(
				"falta %s en %s" % [name_key, locale]).is_not_equal(name_key)
			assert_str(Tr.t(desc_key)).override_failure_message(
				"falta %s en %s" % [desc_key, locale]).is_not_equal(desc_key)

func test_the_building_name_follows_the_locale() -> void:
	var sawmill := load(BUILDINGS_DIR + "sawmill.tres") as BuildingData
	Tr.set_locale("es")
	assert_str(sawmill.get_display_name()).is_equal("Aserradero")
	Tr.set_locale("en")
	assert_str(sawmill.get_display_name()).is_equal("Sawmill")
	assert_str(sawmill.get_description()).is_equal(Tr.t("BLD_SAWMILL_DESC"))

func test_an_unknown_building_falls_back_to_its_raw_fields() -> void:
	var data := BuildingData.new()
	data.id = "not_a_building"
	data.display_name = "Cosa"
	data.description = "Sin traducir"
	assert_str(data.get_display_name()).is_equal("Cosa")
	assert_str(data.get_description()).is_equal("Sin traducir")

func test_a_queued_process_is_named_in_the_current_language() -> void:
	ResourceManager.set_amounts({"wood": 300})
	var node := Node3D.new()
	_nodes.append(node)
	Tr.set_locale("es")
	assert_bool(ProcessManager.start_process(node, _process_def("nucleo", "wood_planks"))).is_true()
	var es_name := ProcessManager.get_active_name(node)
	Tr.set_locale("en")
	var en_name := ProcessManager.get_active_name(node)
	assert_str(es_name).is_equal(Tr._STRINGS["es"]["PROC_WOOD_PLANKS"])
	assert_str(en_name).is_equal(Tr._STRINGS["en"]["PROC_WOOD_PLANKS"])
	assert_bool(ProcessManager.get_active(node).has("name")).is_false()

func _placed_node(cell: Vector2i) -> Node3D:
	var node := Node3D.new()
	_nodes.append(node)
	var data := load(BUILDINGS_DIR + "house.tres") as BuildingData
	assert_bool(GridManager.place_building(cell, data, node)).is_true()
	return node

func _free_cell() -> Vector2i:
	for y in range(GridManager.grid_height):
		for x in range(GridManager.grid_width):
			var cell := Vector2i(x, y)
			if GridManager.is_cell_free(cell):
				return cell
	return Vector2i(-1, -1)

func test_the_save_carries_the_key_not_the_translated_name() -> void:
	ResourceManager.set_amounts({"wood": 300})
	var cell := _free_cell()
	var node := _placed_node(cell)
	ProcessManager.start_process(node, _process_def("nucleo", "wood_planks"))
	var entry: Dictionary = {}
	for e in ProcessManager.get_save_data():
		if Vector2i(e["cell_x"], e["cell_y"]) == cell:
			entry = e
	assert_str(str(entry.get("name_key", ""))).is_equal("PROC_WOOD_PLANKS")
	assert_bool(entry.has("name")).is_false()

func test_an_old_save_with_a_translated_name_recovers_the_key() -> void:
	var cell := _free_cell()
	var node := _placed_node(cell)
	ProcessManager.load_save_data([{
		"cell_x": cell.x, "cell_y": cell.y, "id": "wood_planks",
		"name": "Tablones viejos", "remaining": 10.0, "duration": 30.0,
		"produces": {"wood": 35}}])
	Tr.set_locale("en")
	assert_str(ProcessManager.get_active_name(node)).is_equal(Tr.t("PROC_WOOD_PLANKS"))

func test_an_old_save_with_an_unknown_id_keeps_its_text() -> void:
	var cell := _free_cell()
	var node := _placed_node(cell)
	ProcessManager.load_save_data([{
		"cell_x": cell.x, "cell_y": cell.y, "id": "gone_process",
		"name": "Proceso retirado", "remaining": 10.0, "duration": 30.0,
		"produces": {}}])
	assert_str(ProcessManager.get_active_name(node)).is_equal("Proceso retirado")
