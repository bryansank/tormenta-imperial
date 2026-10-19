extends GdUnitTestSuite
## La primera Mina de oro a mitad de precio (pedido de Bryan, 2026-10-19: "bajale
## el precio a la Mina de oro en el tutorial, la pones demasiado cara"). Un solo
## coste de obra (BuildingData.get_cost): CONSTRUIR, el fantasma, el cobro,
## ¿QUE HACER? y el tutorial ven el mismo precio. Las siguientes, al de la ficha.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const Objectives := preload("res://scripts/services/Objectives.gd")

var _placed: Array = []

func before_test() -> void:
	GridManager.clear_all()
	_placed = []

func after_test() -> void:
	for node in _placed:
		if is_instance_valid(node):
			GridManager.remove_building(node)
			node.free()
	GridManager.clear_all()

func _mine() -> BuildingData:
	return Rules.load_building_data("gold_mine")

func test_the_first_gold_mine_costs_half() -> void:
	var data := _mine()
	var base: Dictionary = data.get_base_cost()
	var cost: Dictionary = data.get_cost()
	assert_int(int(cost[ResourceManager.Type.GOLD])).is_equal(int(base[ResourceManager.Type.GOLD]) / 2)
	assert_int(int(cost[ResourceManager.Type.WOOD])).is_equal(int(base[ResourceManager.Type.WOOD]) / 2)
	assert_float(data.first_discount_factor()).is_equal(0.5)

func test_the_second_one_costs_the_full_price() -> void:
	var data := _mine()
	var node := Node3D.new()
	_placed.append(node)
	assert_bool(GridManager.place_building(Vector2i(2, 2), data, node)).is_true()
	assert_dict(data.get_cost()).is_equal(data.get_base_cost())
	assert_float(data.first_discount_factor()).is_equal(1.0)

func test_upgrades_and_repairs_use_the_full_price() -> void:
	var data := _mine()
	var up: Dictionary = GameConfig.get_upgrade_cost(data, 2)
	var base: Dictionary = data.get_base_cost()
	var mult: float = GameConfig.upgrade_cost_multiplier[1]
	assert_int(int(up[ResourceManager.Type.GOLD])).is_equal(int(base[ResourceManager.Type.GOLD] * mult))

func test_every_screen_reads_the_same_price() -> void:
	var data := _mine()
	var gold: int = int(data.get_cost()[ResourceManager.Type.GOLD])
	ResourceManager.set_amounts({"gold": 0, "wood": 0})
	assert_int(int(Rules.missing_cost(data)["gold"])).is_equal(gold)
	assert_int(int(Rules.cost_by_name(data)["gold"])).is_equal(gold)
	assert_int(int(Objectives.step_cost({"kind": "build", "id": "gold_mine"})[ResourceManager.Type.GOLD])).is_equal(gold)

func test_other_buildings_keep_their_price() -> void:
	for id in ["sawmill", "house", "barracks", "farm"]:
		var data := Rules.load_building_data(id)
		assert_dict(data.get_cost()).override_failure_message(id).is_equal(data.get_base_cost())

func test_the_label_exists_in_both_languages() -> void:
	var saved := Tr.get_locale()
	for lang in ["es", "en"]:
		Tr.set_locale(lang)
		assert_str(Tr.t("LBL_FIRST_HALF_PRICE")).is_not_equal("LBL_FIRST_HALF_PRICE")
	Tr.set_locale(saved)
