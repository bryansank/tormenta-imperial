extends GdUnitTestSuite
## La progresion offline rinde con la MISMA formula que el tic en vivo
## (ProductionManager.get_cycle_yield): una ruina o un edificio sin obreros no
## produce estando fuera, y el nivel, la tecnologia y la moral cuentan. Lo
## pasajero (tormenta, plaga) no se simula offline y por eso no se cobra.
##
## Desde 2026-10-04 lo producido fuera se queda EN LOS EDIFICIOS, con su tope,
## y hay que recogerlo al volver; la gente come de la comida cultivada fuera,
## nunca de la bolsa; y si el modo lo pide, lo acumulado se echa a perder.

const FOUNDRY := "res://data/buildings/foundry.tres"
const FARM := "res://data/buildings/farm.tres"

var _saved_producing: Dictionary = {}
var _saved_constructing: Dictionary = {}
var _saved_stock: Dictionary = {}
var _saved_crops: Dictionary = {}
var _saved_tier: int = 0
var _saved_resources: Dictionary = {}
var _saved_population: Dictionary = {}
var _saved_tech_bonus := 0.0
var _saved_storm_mult := 1.0
var _nodes: Array = []
var _data: BuildingData

func before_test() -> void:
	_saved_producing = ProductionManager._producing
	_saved_constructing = ProductionManager._constructing
	ProductionManager._producing = {}
	ProductionManager._constructing = {}
	_saved_stock = ProductionManager._stock
	_saved_crops = ProductionManager._crops
	ProductionManager._stock = {}
	ProductionManager._crops = {}
	_saved_tier = GameMode.tier
	_saved_resources = {}
	for type in ResourceManager.get_all():
		_saved_resources[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 0, "food": 0})
	_saved_population = PopulationManager.get_save_data()
	# Moral 50 = 1,0x: el numero esperado se lee sin cuentas.
	PopulationManager.load_save_data({"population": _saved_population["population"], "morale": 50})
	_saved_tech_bonus = GameConfig.tech_production_bonus
	GameConfig.tech_production_bonus = 0.0
	_saved_storm_mult = GameConfig.event_production_multiplier
	_data = load(FOUNDRY) as BuildingData

func after_test() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	ProductionManager._producing = _saved_producing
	ProductionManager._constructing = _saved_constructing
	ProductionManager._stock = _saved_stock
	ProductionManager._crops = _saved_crops
	GameMode.tier = _saved_tier
	ResourceManager.set_amounts(_saved_resources)
	PopulationManager.load_save_data(_saved_population)
	GameConfig.tech_production_bonus = _saved_tech_bonus
	GameConfig.event_production_multiplier = _saved_storm_mult

func _foundry(staffed := true, level := 1) -> Node3D:
	var node := Node3D.new()
	node.set_meta("staffed", staffed)
	node.set_meta("level", level)
	_nodes.append(node)
	ProductionManager._producing[node] = {"timer": 0.0, "data": _data}
	return node

func _interval() -> float:
	return GameConfig.get_production_interval(_data.production_interval)

## Tres ciclos y medio: el medio no se paga.
func _elapsed() -> float:
	return _interval() * 3.5

func test_a_staffed_foundry_earns_offline_what_it_would_earn_online() -> void:
	var node := _foundry()
	var online: int = ProductionManager.get_cycle_yield(node, _data)["steel"]
	assert_int(online).is_equal(_data.produces_steel)
	var earned := ProductionManager.apply_offline_progression(_elapsed())
	assert_int(int(earned.get("steel", 0))).is_equal(online * 3)

func test_a_ruined_building_produces_nothing_offline() -> void:
	var node := _foundry()
	node.set_meta("health", 0)
	var earned := ProductionManager.apply_offline_progression(_elapsed())
	assert_int(int(earned.get("steel", 0))).is_equal(0)

func test_an_unstaffed_building_produces_nothing_offline() -> void:
	_foundry(false)
	var earned := ProductionManager.apply_offline_progression(_elapsed())
	assert_int(int(earned.get("steel", 0))).is_equal(0)

func test_level_and_tech_bonus_count_offline() -> void:
	_foundry(true, 2)
	GameConfig.tech_production_bonus = 0.25
	var mult := GameConfig.get_production_multiplier(2) + 0.25
	var earned := ProductionManager.apply_offline_progression(_elapsed())
	assert_int(int(earned.get("steel", 0))).is_equal(int(_data.produces_steel * mult) * 3)

func test_the_storm_is_not_charged_offline() -> void:
	var node := _foundry()
	GameConfig.event_production_multiplier = GameConfig.storm_production_multiplier
	var online: int = ProductionManager.get_cycle_yield(node, _data)["steel"]
	var earned := ProductionManager.apply_offline_progression(_elapsed())
	assert_int(online).is_less(_data.produces_steel)
	assert_int(int(earned.get("steel", 0))).is_equal(_data.produces_steel * 3)

func test_a_clock_rollback_or_garbage_pays_nothing() -> void:
	_foundry()
	assert_dict(ProductionManager.apply_offline_progression(-5000.0)).is_empty()
	assert_dict(ProductionManager.apply_offline_progression(NAN)).is_empty()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.STEEL)).is_equal(0)

func test_a_huge_jump_is_capped_at_the_offline_limit() -> void:
	var node := _foundry()
	var per_cycle: int = ProductionManager.get_cycle_yield(node, _data, false)["steel"]
	var capped_cycles := int(GameConfig.max_offline_seconds / _interval())
	# El tope del edificio manda por encima del de tiempo: lleno, se para.
	var expected: int = mini(per_cycle * capped_cycles, ProductionManager.get_stock_cap(node))
	var earned := ProductionManager.apply_offline_progression(1.0e12)
	assert_int(int(earned.get("steel", 0))).is_equal(expected)
	assert_bool(ProductionManager.is_full(node)).is_true()

# ── Lo de fuera se recoge al volver (2026-10-04) ──

func test_offline_production_waits_in_the_building_not_in_the_bag() -> void:
	var node := _foundry()
	var earned := ProductionManager.apply_offline_progression(_elapsed())
	assert_int(int(ProductionManager.get_stock(node).get("steel", 0))).is_equal(int(earned["steel"]))
	assert_int(ResourceManager.get_amount(ResourceManager.Type.STEEL)).is_equal(0)
	# Y al recogerlo, entra.
	ProductionManager.collect(node)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.STEEL)).is_equal(int(earned["steel"]))

func test_a_crop_keeps_growing_across_short_absences() -> void:
	var farm := _farm()
	ProductionManager.plant_crop(farm, "crop_long")
	var half := GameConfig.get_crop_duration("crop_long") * 0.6
	ProductionManager.apply_offline_progression(half)
	assert_int(ProductionManager.get_stock_total(farm)).is_equal(0)
	ProductionManager.apply_offline_progression(half)
	assert_int(int(ProductionManager.get_stock(farm).get("food", 0))).is_greater(0)

func test_people_eat_from_the_food_grown_offline_never_from_the_bag() -> void:
	ResourceManager.set_amounts({"food": 50})
	var farm := _farm()
	var secs := GameConfig.get_crop_duration("crop_short") * 4.0 + 0.5
	var crop_food := int(GameConfig.get_crop("crop_short")["food"])
	var earned := ProductionManager.apply_offline_progression(secs)
	var cons := GameConfig.get_duration(GameConfig.consumption_interval)
	var eaten := mini(4 * crop_food, int(PopulationManager.get_population() * int(secs / cons)))
	assert_int(int(earned.get("food", 0))).is_equal(4 * crop_food - eaten)
	assert_int(ProductionManager.get_stock_total(farm)).is_equal(4 * crop_food - eaten)
	# La bolsa no se toca.
	assert_int(ResourceManager.get_amount(ResourceManager.Type.FOOD)).is_equal(50)

func test_offline_spoilage_only_when_the_mode_asks() -> void:
	var node := _foundry()
	ProductionManager._add_to_stock(node, {"steel": 100})
	node.set_meta("staffed", false)
	GameMode.tier = GameMode.Tier.COLONIST
	ProductionManager.apply_offline_progression(GameConfig.spoil_after_seconds + 10.0)
	assert_dict(ProductionManager.get_stock(node)).is_equal({"steel": 100})
	assert_dict(ProductionManager.last_offline_spoiled).is_empty()
	ProductionManager._stock[node]["age"] = 0.0
	GameMode.tier = GameMode.Tier.GOVERNOR  # se estropea solo en Gobernador
	ProductionManager.apply_offline_progression(GameConfig.spoil_after_seconds + 10.0)
	assert_dict(ProductionManager.get_stock(node)).is_equal({"steel": 50})
	assert_dict(ProductionManager.last_offline_spoiled).is_equal({"steel": 50})

func _farm() -> Node3D:
	var node := Node3D.new()
	node.set_meta("staffed", true)
	node.set_meta("level", 1)
	_nodes.append(node)
	ProductionManager._producing[node] = {"timer": 0.0, "data": load(FARM)}
	return node
