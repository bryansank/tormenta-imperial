extends GdUnitTestSuite
## Los materiales del taller (2026-09-28): tablones, lingotes, vigas y
## combustible. Los fabrica cada edificio especializado con su recurso, los
## piden los edificios avanzados, no ocupan el almacen y aparecen cuando se
## termina el primero de su edificio. Y las eras: no se sube sin la base.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const Objectives := preload("res://scripts/services/Objectives.gd")

var _amounts := {}
var _unlocks := {}
var _nodes: Array = []
var _mode := 0

func before_test() -> void:
	# Estado conocido: otra suite puede dejar Sandbox (sin requisitos ni topes).
	_mode = GameMode.current
	GameMode.current = GameMode.Mode.CAMPAIGN
	_amounts = {}
	for t in ResourceManager.get_all():
		_amounts[ResourceManager.get_type_name(t)] = ResourceManager.get_amount(t)
	_unlocks = ResourceManager.get_unlock_state()
	GridManager.clear_all()
	_nodes.clear()

func after_test() -> void:
	GameMode.current = _mode
	ResourceManager.set_amounts(_amounts)
	ResourceManager.set_unlock_state(_unlocks)
	GridManager.clear_all()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id)

func test_there_are_four_materials_with_names() -> void:
	for m in ["planks", "ingots", "beams", "fuel"]:
		var type: int = ResourceManager.name_to_type(m)
		assert_int(type).is_not_equal(-1)
		assert_bool(ResourceManager.is_material(type)).is_true()
		assert_str(Tr.res_name(m)).is_not_empty()

func test_materials_take_no_storage_room() -> void:
	var before: int = ResourceManager.get_total_stored()
	ResourceManager.add(ResourceManager.Type.BEAMS, 500)
	assert_int(ResourceManager.get_total_stored()).is_equal(before)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.BEAMS)).is_greater_equal(500)

func test_each_specialised_building_makes_its_material() -> void:
	for m in GameConfig.material_sources:
		var source: String = GameConfig.get_material_source(m)
		var makes := false
		for proc in GameConfig.get_processes_for(source):
			if (proc.get("produces", {}) as Dictionary).has(m):
				makes = true
		assert_bool(makes).override_failure_message("%s no fabrica %s" % [source, m]).is_true()

func test_the_first_building_of_its_kind_unlocks_the_material() -> void:
	ResourceManager.set_unlock_state({"beams": false})
	ProgressionManager._unlock_material_of("foundry")
	assert_bool(ResourceManager.is_unlocked(ResourceManager.Type.BEAMS)).is_true()

func test_advanced_buildings_ask_for_materials() -> void:
	assert_int(int(_data("barracks").get_cost().get(ResourceManager.Type.PLANKS, 0))).is_greater(0)
	assert_int(int(_data("tower").get_cost().get(ResourceManager.Type.BEAMS, 0))).is_greater(0)
	var hq: Dictionary = _data("headquarters").get_cost()
	for t in [ResourceManager.Type.BEAMS, ResourceManager.Type.INGOTS, ResourceManager.Type.FUEL]:
		assert_int(int(hq.get(t, 0))).is_greater(0)
	# Las mejoras del Cuartel General tambien.
	assert_int(int(GameConfig.get_upgrade_cost(_data("headquarters"), 3).get(ResourceManager.Type.FUEL, 0))).is_greater(0)
	# Lo basico no: una casa o un aserradero se hacen con recursos.
	assert_bool(_data("house").get_cost().has(ResourceManager.Type.PLANKS)).is_false()

func test_a_locked_material_says_where_it_is_made() -> void:
	ResourceManager.set_unlock_state({"planks": false})
	ResourceManager.set_amounts({"planks": 0})
	var text := "\n".join(Rules.block_reasons(_data("barracks")))
	assert_str(text).contains(Tr.res_name("planks"))
	assert_str(text).contains(Tr.t("UNLOCK_HINT_PLANKS"))

func test_the_next_step_asks_to_make_the_missing_material() -> void:
	var n := Node.new()
	_nodes.append(n)
	GridManager.place_building(Vector2i(1, 1), _data("sawmill"), n)
	ResourceManager.set_amounts({"planks": 0})
	var step: Dictionary = Objectives.make_step_for({"kind": "build", "id": "barracks", "count": 1})
	assert_str(String(step.get("kind", ""))).is_equal("make")
	assert_str(String(step.get("id", ""))).is_equal("planks")
	assert_str(String(step.get("building", ""))).is_equal("sawmill")

func test_no_era_without_the_basics() -> void:
	var foundry: Array = GameConfig.get_prerequisites("foundry")
	for b in ["sawmill", "gold_mine", "house", "warehouse"]:
		assert_array(foundry).contains([b])
	assert_array(GameConfig.get_prerequisites("refinery")).contains(["foundry", "barracks"])
