extends GdUnitTestSuite
## Comida, Granja y produccion que se recoge (2026-10-04, decisiones de Bryan en
## tormenta-imperial-contexto/17):
##   - la gente come COMIDA en vez de madera y oro, y el hambre funciona igual;
##   - la Granja cultiva por duracion: 1 / 5 / 20 min, el largo rinde mas por minuto;
##   - todo productor acumula en el edificio hasta un tope y se para lleno;
##   - recoger mete en la bolsa lo que cabe y deja dentro el resto, nunca lo tira;
##   - lo acumulado se echa a perder a medias pasadas 2 h, solo si el modo lo pide.

const FARM := "res://data/buildings/farm.tres"
const SAWMILL := "res://data/buildings/sawmill.tres"
const NUCLEO := "res://data/buildings/nucleo.tres"

var _saved_resources: Dictionary = {}
var _saved_producing: Dictionary = {}
var _saved_constructing: Dictionary = {}
var _saved_stock: Dictionary = {}
var _saved_crops: Dictionary = {}
var _saved_population: Dictionary = {}
var _saved_warehouses := 0
var _saved_era := 1
var _saved_spoil: Variant = null
var _saved_tech_bonus := 0.0
var _saved_reduction := 0.0
var _nodes: Array = []
var _farm: BuildingData
var _sawmill: BuildingData

func before_test() -> void:
	_saved_resources = {}
	for type in ResourceManager.get_all():
		_saved_resources[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	_saved_warehouses = ResourceManager.get_warehouse_count()
	_saved_era = ResourceManager.get_era()
	ResourceManager.set_warehouse_count(0)
	ResourceManager.set_era(1)
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 0, "food": 0})
	_saved_producing = ProductionManager._producing
	_saved_constructing = ProductionManager._constructing
	_saved_stock = ProductionManager._stock
	_saved_crops = ProductionManager._crops
	ProductionManager._producing = {}
	ProductionManager._constructing = {}
	ProductionManager._stock = {}
	ProductionManager._crops = {}
	_saved_population = PopulationManager.get_save_data()
	# Moral 50 = 1,0x: las cuentas se leen sin multiplicar. Diez habitantes con
	# sitio para ellos (sin casas en la rejilla, el recuento los dejaria en 1).
	PopulationManager.load_save_data({"population": 10, "morale": 50})
	PopulationManager._max_population = 10
	PopulationManager._population = 10
	_saved_spoil = GameConfig.game_mode_rules["campaign"].get("spoilage", false)
	_saved_tech_bonus = GameConfig.tech_production_bonus
	GameConfig.tech_production_bonus = 0.0
	_saved_reduction = GameConfig.tech_consumption_reduction
	GameConfig.tech_consumption_reduction = 0.0
	_farm = load(FARM) as BuildingData
	_sawmill = load(SAWMILL) as BuildingData

func after_test() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	ProductionManager._producing = _saved_producing
	ProductionManager._constructing = _saved_constructing
	ProductionManager._stock = _saved_stock
	ProductionManager._crops = _saved_crops
	ResourceManager.set_warehouse_count(_saved_warehouses)
	ResourceManager.set_era(_saved_era)
	ResourceManager.set_amounts(_saved_resources)
	PopulationManager.load_save_data(_saved_population)
	GameConfig.game_mode_rules["campaign"]["spoilage"] = _saved_spoil
	GameConfig.tech_production_bonus = _saved_tech_bonus
	GameConfig.tech_consumption_reduction = _saved_reduction

# ── Ayudas ───────────────────────────────────────────────────────────

func _producer(data: BuildingData, staffed := true) -> Node3D:
	var node := Node3D.new()
	node.set_meta("staffed", staffed)
	node.set_meta("level", 1)
	_nodes.append(node)
	ProductionManager._producing[node] = {"timer": 0.0, "data": data}
	return node

func _food() -> int:
	return ResourceManager.get_amount(ResourceManager.Type.FOOD)

func _wood() -> int:
	return ResourceManager.get_amount(ResourceManager.Type.WOOD)

## Avanza la produccion `seconds` en pasos de un segundo, como el juego.
func _run(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		ProductionManager._tick_production(1.0)
		ProductionManager._tick_spoilage(1.0)
		t += 1.0

# ══════════════════════════════════════════════════════════════════════
# La gente come comida
# ══════════════════════════════════════════════════════════════════════

func test_food_is_a_pool_resource_that_exists_from_the_start() -> void:
	assert_bool(ResourceManager.is_unlocked(ResourceManager.Type.FOOD)).is_true()
	assert_bool(ResourceManager.is_material(ResourceManager.Type.FOOD)).is_false()
	ResourceManager.set_amounts({"food": 120})
	assert_int(ResourceManager.get_total_stored()).is_equal(120)

func test_a_new_game_starts_with_some_food() -> void:
	assert_int(int(GameConfig.starting_resources.get("food", 0))).is_greater(0)
	# Cabe entera con el oro y la madera en la bolsa de la era 1.
	var total := 0
	for res in GameConfig.starting_resources:
		total += int(GameConfig.starting_resources[res])
	assert_int(total).is_less_equal(GameConfig.get_storage_cap(0, 1))

func test_people_eat_food_not_wood_or_gold() -> void:
	ResourceManager.set_amounts({"gold": 100, "wood": 100, "food": 100})
	PopulationManager._tick_consumption()
	var pop := PopulationManager.get_population()
	assert_int(_food()).is_equal(100 - pop * GameConfig.food_per_pop)
	assert_int(_wood()).is_equal(100)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(100)
	assert_int(PopulationManager.get_unpaid_ticks()).is_equal(0)

func test_the_consumption_tech_still_cuts_what_they_eat() -> void:
	GameConfig.tech_consumption_reduction = 0.5
	ResourceManager.set_amounts({"food": 100})
	PopulationManager._tick_consumption()
	assert_int(_food()).is_equal(100 - maxi(1, int(PopulationManager.get_population() * 0.5)))
	assert_int(PopulationManager.get_population()).is_equal(10)

func test_without_food_they_go_hungry_even_if_rich() -> void:
	ResourceManager.set_amounts({"gold": 500, "wood": 500, "food": 0})
	var failed := [""]
	var probe := func(res: String): failed[0] = res
	EventBus.consumption_failed.connect(probe)
	PopulationManager._tick_consumption()
	EventBus.consumption_failed.disconnect(probe)
	assert_str(failed[0]).is_equal("food")
	assert_int(PopulationManager.get_unpaid_ticks()).is_equal(1)
	# El oro y la madera no se tocan: no se comen.
	assert_int(_wood()).is_equal(500)

func test_hunger_kills_after_the_grace_like_before() -> void:
	ResourceManager.set_amounts({"food": 0})
	var before := PopulationManager.get_population()
	for i in range(GameConfig.unpaid_grace_ticks + 1):
		PopulationManager._tick_consumption()
	assert_int(PopulationManager.get_population()).is_equal(before - GameConfig.starvation_deaths_per_tick)

func test_eating_what_is_left_still_counts_as_hungry() -> void:
	ResourceManager.set_amounts({"food": 3})
	PopulationManager._tick_consumption()
	assert_int(_food()).is_equal(0)
	assert_int(PopulationManager.get_unpaid_ticks()).is_equal(1)

# ══════════════════════════════════════════════════════════════════════
# La Granja y sus tres cultivos
# ══════════════════════════════════════════════════════════════════════

func test_the_farm_is_a_cheap_era_1_producer_with_workers() -> void:
	assert_bool(_farm.is_producer()).is_true()
	assert_that(_farm.grid_size).is_equal(Vector2i(2, 2))
	assert_int(_farm.workers_required).is_greater(0)
	assert_int(_farm.cost_steel + _farm.cost_oil).is_equal(0)
	assert_int(_farm.cost_gold).is_less(_sawmill.cost_gold)
	# En cualquier sitio: sin regla de yacimiento.
	assert_dict(GameConfig.get_deposit_rule("farm")).is_empty()
	assert_int(GameConfig.get_building_limit("farm")).is_greater(0)

func test_three_crops_of_one_five_and_twenty_minutes() -> void:
	assert_int(GameConfig.farm_crops.size()).is_equal(3)
	var minutes: Array = []
	for crop in GameConfig.farm_crops:
		minutes.append(int(float(crop["duration"]) / 60.0))
	assert_array(minutes).is_equal([1, 5, 20])

func test_longer_crops_yield_more_and_more_per_minute() -> void:
	var last_total := 0
	var last_rate := 0.0
	for crop in GameConfig.farm_crops:
		var total := int(crop["food"])
		var rate := float(total) / float(crop["duration"])
		assert_int(total).is_greater(last_total)
		assert_float(rate).is_greater(last_rate)
		last_total = total
		last_rate = rate

func test_a_new_farm_grows_the_short_crop() -> void:
	var farm := _producer(_farm)
	assert_str(ProductionManager.get_crop(farm)).is_equal(GameConfig.farm_default_crop)
	assert_str(GameConfig.farm_default_crop).is_equal("crop_short")

func test_each_crop_yields_its_food_after_its_time() -> void:
	for crop in GameConfig.farm_crops:
		var farm := _producer(_farm)
		ProductionManager.plant_crop(farm, String(crop["id"]))
		var seconds := GameConfig.get_crop_duration(String(crop["id"]))
		_run(seconds - 1.0)
		assert_int(ProductionManager.get_stock_total(farm)).is_equal(0)
		_run(1.0)
		assert_dict(ProductionManager.get_stock(farm)).is_equal({"food": int(crop["food"])})

func test_changing_crop_starts_over_and_same_crop_does_nothing() -> void:
	var farm := _producer(_farm)
	_run(GameConfig.get_crop_duration("crop_short") * 0.5)
	assert_float(ProductionManager.get_cycle_progress(farm)).is_greater(0.0)
	assert_bool(ProductionManager.plant_crop(farm, "crop_short")).is_false()
	assert_float(ProductionManager.get_cycle_progress(farm)).is_greater(0.0)
	assert_bool(ProductionManager.plant_crop(farm, "crop_long")).is_true()
	assert_float(ProductionManager.get_cycle_progress(farm)).is_equal(0.0)
	assert_str(ProductionManager.get_crop(farm)).is_equal("crop_long")
	assert_bool(ProductionManager.plant_crop(farm, "no_such_crop")).is_false()

func test_a_farm_without_workers_does_not_grow() -> void:
	var farm := _producer(_farm, false)
	_run(GameConfig.get_crop_duration("crop_short") * 2.0)
	assert_float(ProductionManager.get_cycle_progress(farm)).is_equal(0.0)
	assert_int(ProductionManager.get_stock_total(farm)).is_equal(0)

# ══════════════════════════════════════════════════════════════════════
# Acumular, tope y parar
# ══════════════════════════════════════════════════════════════════════

func test_production_waits_in_the_building_not_in_the_bag() -> void:
	var mill := _producer(_sawmill)
	_run(GameConfig.get_production_interval(_sawmill.production_interval))
	assert_dict(ProductionManager.get_stock(mill)).is_equal({"wood": _sawmill.produces_wood})
	assert_int(_wood()).is_equal(0)

func test_every_producer_has_a_cap_that_grows_with_level() -> void:
	var mill := _producer(_sawmill)
	var cap1 := ProductionManager.get_stock_cap(mill)
	assert_int(cap1).is_equal(GameConfig.get_stock_cap("sawmill", 1))
	mill.set_meta("level", 2)
	assert_int(ProductionManager.get_stock_cap(mill)).is_greater(cap1)
	# Lo que no produce no guarda nada.
	assert_int(GameConfig.get_stock_cap("sawmill")).is_greater(0)

func test_it_fills_up_to_the_cap_and_stops() -> void:
	var mill := _producer(_sawmill)
	var cap := ProductionManager.get_stock_cap(mill)
	var interval := GameConfig.get_production_interval(_sawmill.production_interval)
	_run(interval * (cap / _sawmill.produces_wood + 5))
	assert_int(ProductionManager.get_stock_total(mill)).is_equal(cap)
	assert_bool(ProductionManager.is_full(mill)).is_true()
	# Parado: el reloj no corre mientras este lleno.
	var timer_before: float = ProductionManager._producing[mill]["timer"]
	_run(interval * 3)
	assert_float(ProductionManager._producing[mill]["timer"]).is_equal(timer_before)

func test_a_full_building_says_so_on_its_badge() -> void:
	var verdict := BuildingStatusBadge.derive({"can_work": true, "connected": true, "has_vein": true,
		"needs_workers": true, "staffed": true, "produces": true, "full": true})
	assert_int(int(verdict["status"])).is_equal(BuildingStatusBadge.Status.IDLE)
	assert_str(String(verdict["reason"])).is_equal("full")
	assert_str(BuildingStatusBadge.reason_text("full")).is_equal(Tr.t("LBL_STATUS_WHY_FULL"))

# ══════════════════════════════════════════════════════════════════════
# Recoger
# ══════════════════════════════════════════════════════════════════════

func test_collecting_moves_everything_into_the_bag() -> void:
	var mill := _producer(_sawmill)
	ProductionManager._add_to_stock(mill, {"wood": 30})
	var got := ProductionManager.collect(mill)
	assert_dict(got).is_equal({"wood": 30})
	assert_int(_wood()).is_equal(30)
	assert_bool(ProductionManager.has_stock(mill)).is_false()

func test_collecting_restarts_a_stopped_building() -> void:
	var mill := _producer(_sawmill)
	ProductionManager._add_to_stock(mill, {"wood": ProductionManager.get_stock_cap(mill)})
	assert_bool(ProductionManager.is_full(mill)).is_true()
	ProductionManager.collect(mill)
	assert_bool(ProductionManager.is_full(mill)).is_false()
	_run(GameConfig.get_production_interval(_sawmill.production_interval))
	assert_int(ProductionManager.get_stock_total(mill)).is_equal(_sawmill.produces_wood)

func test_with_a_full_bag_what_does_not_fit_stays_in_the_building() -> void:
	var cap := ResourceManager.get_storage_cap()
	ResourceManager.set_amounts({"gold": cap - 10})
	var mill := _producer(_sawmill)
	ProductionManager._add_to_stock(mill, {"wood": 50})
	var got := ProductionManager.collect(mill)
	assert_dict(got).is_equal({"wood": 10})
	assert_int(_wood()).is_equal(10)
	# Nada se tira: los 40 que no cupieron siguen dentro.
	assert_dict(ProductionManager.get_stock(mill)).is_equal({"wood": 40})
	# Y con la bolsa llena del todo, recoger no mete nada ni pierde nada.
	assert_dict(ProductionManager.collect(mill)).is_empty()
	assert_dict(ProductionManager.get_stock(mill)).is_equal({"wood": 40})

func test_collect_all_empties_every_building() -> void:
	var mill := _producer(_sawmill)
	var farm := _producer(_farm)
	ProductionManager._add_to_stock(mill, {"wood": 12})
	ProductionManager._add_to_stock(farm, {"food": 20})
	var got := ProductionManager.collect_all()
	assert_dict(got).is_equal({"wood": 12, "food": 20})
	assert_dict(ProductionManager.get_all_stock()).is_empty()

func test_collecting_tells_the_bus() -> void:
	var mill := _producer(_sawmill)
	ProductionManager._add_to_stock(mill, {"wood": 6})
	var seen := [{}]
	var probe := func(_n: Node, collected: Dictionary): seen[0] = collected
	EventBus.production_collected.connect(probe)
	ProductionManager.collect(mill)
	EventBus.production_collected.disconnect(probe)
	assert_dict(seen[0]).is_equal({"wood": 6})

func test_a_workshop_process_that_does_not_fit_stays_in_its_building() -> void:
	var info_node := _producer(_sawmill)
	# Un proceso que entrega mas de lo que cabe: el resto, al edificio.
	ResourceManager.set_amounts({"gold": ResourceManager.get_storage_cap() - 5})
	ProductionManager.keep_in_building(info_node, {"wood": 20})
	assert_dict(ProductionManager.get_stock(info_node)).is_equal({"wood": 20})
	var rest := ResourceManager.add_fitting(ResourceManager.Type.WOOD, 30)
	assert_int(rest).is_equal(25)
	assert_int(_wood()).is_equal(5)

# ══════════════════════════════════════════════════════════════════════
# Se echa a perder (solo si el modo lo pide)
# ══════════════════════════════════════════════════════════════════════

func test_spoilage_is_off_by_default() -> void:
	assert_bool(GameMode.spoilage_enabled()).is_false()

func test_without_spoilage_nothing_goes_bad_however_long() -> void:
	GameConfig.game_mode_rules["campaign"]["spoilage"] = false
	var farm := _producer(_farm)
	ProductionManager._add_to_stock(farm, {"food": 100})
	ProductionManager._tick_spoilage(GameConfig.spoil_after_seconds * 3.0)
	assert_dict(ProductionManager.get_stock(farm)).is_equal({"food": 100})

func test_with_spoilage_half_is_lost_after_two_hours() -> void:
	GameConfig.game_mode_rules["campaign"]["spoilage"] = true
	assert_float(GameConfig.spoil_after_seconds).is_equal(7200.0)
	var farm := _producer(_farm)
	ProductionManager._add_to_stock(farm, {"food": 100})
	ProductionManager._tick_spoilage(GameConfig.spoil_after_seconds - 1.0)
	assert_dict(ProductionManager.get_stock(farm)).is_equal({"food": 100})
	var lost := [{}]
	var probe := func(_n: Node, l: Dictionary): lost[0] = l
	EventBus.stock_spoiled.connect(probe)
	ProductionManager._tick_spoilage(1.0)
	EventBus.stock_spoiled.disconnect(probe)
	assert_dict(ProductionManager.get_stock(farm)).is_equal({"food": 50})
	assert_dict(lost[0]).is_equal({"food": 50})
	# Vuelve a contar: otras dos horas para la siguiente mitad.
	assert_float(ProductionManager.get_stock_age(farm)).is_equal(0.0)

func test_collecting_resets_the_spoil_clock() -> void:
	GameConfig.game_mode_rules["campaign"]["spoilage"] = true
	ResourceManager.set_amounts({"gold": ResourceManager.get_storage_cap() - 10})
	var farm := _producer(_farm)
	ProductionManager._add_to_stock(farm, {"food": 60})
	ProductionManager._tick_spoilage(GameConfig.spoil_after_seconds * 0.9)
	ProductionManager.collect(farm)
	assert_float(ProductionManager.get_stock_age(farm)).is_equal(0.0)
	ProductionManager._tick_spoilage(GameConfig.spoil_after_seconds * 0.5)
	assert_dict(ProductionManager.get_stock(farm)).is_equal({"food": 50})

# ══════════════════════════════════════════════════════════════════════
# Mercado
# ══════════════════════════════════════════════════════════════════════

func test_food_can_be_bought_and_sold() -> void:
	ResourceManager.set_amounts({"gold": 200, "food": 0})
	var price := MarketManager.get_buy_price("food")
	assert_int(price).is_greater(0)
	assert_bool(MarketManager.buy("food", 20)).is_true()
	assert_int(_food()).is_equal(20)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(200 - price * 20)
	var gold_before := ResourceManager.get_amount(ResourceManager.Type.GOLD)
	var sell := MarketManager.get_sell_price("food")
	assert_bool(MarketManager.sell("food", 10)).is_true()
	assert_int(_food()).is_equal(10)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(gold_before + sell * 10)
	MarketManager.reset()

func test_food_is_on_the_market_list_and_cheap() -> void:
	assert_bool(MarketManager.get_all_prices().has("food")).is_true()
	assert_int(int(GameConfig.market_base_prices["food"])).is_less(int(GameConfig.market_base_prices["wood"]))

func test_an_old_market_save_still_sells_food() -> void:
	MarketManager.load_save_data({"price_mods": {"wood": 1.2, "steel": 1.0, "oil": 0.9}})
	assert_bool(MarketManager.get_all_prices().has("food")).is_true()
	MarketManager.reset()
