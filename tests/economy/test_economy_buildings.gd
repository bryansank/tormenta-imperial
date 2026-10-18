extends GdUnitTestSuite
## Los tres edificios de economia de la 1.2 (feat/edificios-economia, doc 21
## §6.3 n.º 13, 14 y 16): Puerto comercial, Casa de cambio y Central diesel.
## Fija la receta de "Adding a New Building", los tratos del barco por
## EconomyManager, el spread de la Casa de cambio, el area de la Central y el
## guardado.
##
## Escrita sin correr (regla de Bryan: un solo pase de pruebas al final).
## Toca ResourceManager, GameConfig, RankManager, EconomyManager y la rejilla
## de verdad: cada prueba deja lo que cambia.

const Toys := preload("res://scripts/buildings/EconomyToys.gd")
const Effects := preload("res://scripts/buildings/UtilityEffects.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const Kit := preload("res://scripts/buildings/LotMesh.gd")
const Info := preload("res://scripts/ui/BuildingInfoPanel.gd")

const IDS := ["trade_port", "exchange", "diesel_plant"]
const TRI_BUDGET := 1500

var _saved_amounts: Dictionary = {}
var _saved_unlocks: Dictionary = {}
var _saved_rank: Dictionary = {}
var _saved_economy: Dictionary = {}
var _saved_spread := 0.3
var _saved_cut := 0.0
var _placed: Array = []

func before_test() -> void:
	_saved_amounts = {}
	for type in ResourceManager.get_all():
		_saved_amounts[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	_saved_unlocks = ResourceManager.get_unlock_state()
	_saved_rank = RankManager.get_save_data()
	_saved_economy = EconomyManager.get_save_data()
	_saved_spread = GameConfig.market_spread
	_saved_cut = GameConfig.market_spread_cut
	_placed = []

func after_test() -> void:
	for node in _placed:
		GridManager.remove_building(node)
		if is_instance_valid(node):
			node.free()
	_placed = []
	ResourceManager.set_unlock_state(_saved_unlocks)
	ResourceManager.set_amounts(_saved_amounts)
	RankManager.load_save_data(_saved_rank)
	EconomyManager.load_save_data(_saved_economy)
	GameConfig.market_spread = _saved_spread
	GameConfig.market_spread_cut = _saved_cut
	Effects.refresh()

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id) as BuildingData

## Un barco atracado con estas ofertas (por el guardado: la unica puerta).
func _dock(offers: Array) -> void:
	EconomyManager.load_save_data({"ship": {"wait_left": 300.0, "docked_left": 80.0,
		"offers": offers, "visits": 1, "rng_seed": 9, "rng_state": 9}, "plans": []})

## Un edificio de mentira en la rejilla, en pie, con carretera y con obreros.
func _put(id: String, origin: Vector2i) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	node.set_meta("staffed", true)
	node.set_meta("connected", true)
	var ok := GridManager.place_building(origin, _data(id), node)
	assert_bool(ok).override_failure_message("no cabe %s en %s" % [id, origin]).is_true()
	_placed.append(node)
	return node

## Una fila libre de tierra de `n` huellas 2x2 seguidas (separadas `gap`).
func _free_row(n: int, gap: int) -> Vector2i:
	var cx: int = GridManager.grid_width / 2
	var cy: int = GridManager.grid_height / 2
	for dy in range(-12, 12, 2):
		for dx in range(-14, 6, 2):
			var o := Vector2i(cx + dx, cy + dy)
			var fits := true
			for k in n:
				if not GridManager.can_place(o + Vector2i(k * (2 + gap), 0), Vector2i(2, 2)):
					fits = false
					break
			if fits:
				return o
	return Vector2i(-1, -1)

# ── Catalogo ──────────────────────────────────────────────────────────

func test_the_three_exist_and_are_2x2_with_workers() -> void:
	for id in IDS:
		var d := _data(id)
		assert_object(d).override_failure_message(id).is_not_null()
		assert_str(d.id).is_equal(id)
		assert_that(d.grid_size).is_equal(Vector2i(2, 2))
		assert_int(d.workers_required).is_equal(2)
		assert_bool(d.is_decoration).is_false()
		assert_bool(d.is_producer()).is_false()

func test_names_and_help_in_both_languages() -> void:
	var before := Tr.get_locale()
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for id in IDS:
			for key in ["BLD_%s_NAME" % id.to_upper(), "BLD_%s_DESC" % id.to_upper(),
					"HELP_T_%s" % id.to_upper(), "HELP_B_%s" % id.to_upper()]:
				assert_str(Tr.t(key)).override_failure_message(key).is_not_equal(key)
		for key in ["BTN_OPEN_PORT", "LBL_SMUGGLER_TITLE", "NOTIF_SMUGGLER_ARRIVED", "NOTIF_DIESEL_NO_FUEL",
				"LBL_EXCHANGE_SPREAD", "LBL_DIESEL_RUNNING", "LBL_SMUGGLER_KIND_PARTS", "LBL_SMUGGLER_KIND_PLAN",
				"LBL_SMUGGLER_KIND_MATERIAL", "LBL_SMUGGLER_KIND_SELL", "LBL_SMUGGLER_KIND_BUY"]:
			assert_str(Tr.t(key)).override_failure_message(key).is_not_equal(key)
	Tr.set_locale(before)

func test_caps_prerequisites_site_and_lot() -> void:
	assert_int(GameConfig.get_building_limit("trade_port")).is_equal(1)
	assert_int(GameConfig.get_building_limit("exchange")).is_equal(1)
	assert_int(GameConfig.building_limits["diesel_plant"]).is_equal(2)
	assert_array(GameConfig.get_prerequisites("trade_port")).contains(["market", "foundry"])
	assert_array(GameConfig.get_prerequisites("exchange")).contains(["market", "foundry"])
	assert_array(GameConfig.get_prerequisites("diesel_plant")).contains(["refinery"])
	for id in IDS:
		assert_bool(GameConfig.construction_style.has(id)).override_failure_message(id).is_true()
		assert_bool(GameConfig.building_lot_style.has(id)).override_failure_message(id).is_true()
		assert_bool(GameConfig.building_active_fx.has(id)).override_failure_message(id).is_true()

func test_the_port_goes_on_the_coast_facing_the_water() -> void:
	assert_bool(Rules.needs_shore("trade_port")).is_true()
	assert_bool(Rules.faces_water("trade_port")).is_true()
	assert_bool(Rules.needs_shore("exchange")).is_false()
	assert_bool(Rules.needs_shore("diesel_plant")).is_false()

func test_the_diesel_plant_is_a_mission_blueprint() -> void:
	assert_bool("diesel_plant" in GameConfig.blueprint_required).is_true()

# ── Mallas ────────────────────────────────────────────────────────────

func test_procedural_meshes_are_shared_and_within_budget() -> void:
	for id in IDS:
		var m: ArrayMesh = Toys.mesh(id)
		assert_object(m).override_failure_message(id).is_not_null()
		assert_object(Toys.mesh(id)).is_same(m)
		assert_int(m.get_surface_count()).is_less_equal(2)
		var tris := 0
		for s in m.get_surface_count():
			tris += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var mat := m.surface_get_material(s)
			assert_bool(mat == Kit.solid_material() or mat == Kit.glow_material()).is_true()
		assert_int(tris).override_failure_message("%s: %d tri" % [id, tris]).is_less_equal(TRI_BUDGET)
		var a := m.get_aabb()
		assert_float(a.size.x).override_failure_message(id).is_less_equal(3.0)
		assert_float(a.size.z).override_failure_message(id).is_less_equal(3.0)

func test_the_ship_is_one_cheap_shared_mesh() -> void:
	var m: ArrayMesh = Toys.ship_mesh()
	assert_object(m).is_not_null()
	assert_object(Toys.ship_mesh()).is_same(m)
	var tris := 0
	for s in m.get_surface_count():
		tris += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	assert_int(tris).is_less_equal(600)
	# Proa hacia +X: mas largo que ancho.
	assert_float(m.get_aabb().size.x).is_greater(m.get_aabb().size.z * 2.0)

func test_the_factory_gives_them_a_model() -> void:
	for id in IDS:
		var node := DieselpunkBuildingFactory.create(id, 2.0, Vector2i(2, 2))
		assert_object(node).override_failure_message(id).is_not_null()
		node.free()

# ── Amarre del barco ──────────────────────────────────────────────────

func test_the_berth_is_in_front_of_the_port() -> void:
	var origin := Vector2i(10, 10)
	var center: Vector3 = GridManager.building_center(origin, Vector2i(2, 2))
	# Giro 0: el frente (+Z del modelo) da al sur del mundo (+z).
	var b0: Dictionary = EconomyManager.berth_for(origin, Vector2i(2, 2), 0)
	assert_that(b0["out"]).is_equal(Vector3(0, 0, 1))
	assert_float((b0["pos"] as Vector3).z).is_greater(center.z + GridManager.cell_size)
	assert_float((b0["pos"] as Vector3).x).is_equal_approx(center.x, 0.001)
	# Cada giro mira a un lado distinto, y el barco va a lo largo de la orilla.
	var sides := {}
	for steps in 4:
		var b: Dictionary = EconomyManager.berth_for(origin, Vector2i(2, 2), steps)
		sides[int(b["side"])] = true
		assert_float((b["out"] as Vector3).dot(b["along"])).is_equal_approx(0.0, 0.001)
		# El giro que pone el frente al lado `side` es el de PlacementRules.
		assert_int(Rules.steps_to_face(int(b["side"]), false)).is_equal(steps)
	assert_int(sides.size()).is_equal(4)

# ── Tratos ────────────────────────────────────────────────────────────

func test_selling_to_the_ship_takes_the_goods_and_pays_gold() -> void:
	ResourceManager.set_amounts({"gold": 100, "wood": 100})
	_dock([{"kind": "buy", "ask": {"wood": 60}, "pay": 200, "sold": false}])
	assert_bool(EconomyManager.can_take(0)).is_true()
	assert_bool(EconomyManager.take_offer(0)).is_true()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.WOOD)).is_equal(40)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(300)
	# Una vez.
	assert_bool(EconomyManager.take_offer(0)).is_false()
	assert_bool(bool(EconomyManager.get_offers()[0]["sold"])).is_true()

func test_buying_a_material_charges_gold() -> void:
	ResourceManager.set_amounts({"gold": 500, "planks": 0})
	_dock([{"kind": "material", "give": {"planks": 10}, "price": 130, "sold": false}])
	assert_bool(EconomyManager.take_offer(0)).is_true()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.PLANKS)).is_equal(10)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(370)

func test_spare_parts_open_their_row_even_without_missions() -> void:
	ResourceManager.set_amounts({"gold": 500, "parts": 0})
	_dock([{"kind": "parts", "give": {"parts": 3}, "price": 180, "sold": false}])
	assert_bool(EconomyManager.take_offer(0)).is_true()
	assert_bool(ResourceManager.is_unlocked(ResourceManager.Type.PARTS)).is_true()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.PARTS)).is_equal(3)

func test_not_enough_gold_says_what_is_missing_and_touches_nothing() -> void:
	ResourceManager.set_amounts({"gold": 50})
	_dock([{"kind": "material", "give": {"planks": 10}, "price": 130, "sold": false}])
	assert_bool(EconomyManager.can_take(0)).is_false()
	assert_int(int(EconomyManager.missing_for(0).get("gold", 0))).is_equal(80)
	assert_bool(EconomyManager.take_offer(0)).is_false()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(50)

func test_a_bought_plan_opens_a_rank_building_early() -> void:
	RankManager.load_save_data({})
	var id := "palm_trees"
	assert_bool(RankManager.is_building_unlocked(id)).is_false()
	ResourceManager.set_amounts({"gold": 1000})
	_dock([{"kind": "plan", "plan": id, "price": 520, "sold": false}])
	assert_bool(EconomyManager.take_offer(0)).is_true()
	assert_bool(EconomyManager.has_plan(id)).is_true()
	assert_bool(RankManager.is_building_unlocked(id)).is_true()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(480)
	# Ya no se vuelve a ofrecer.
	assert_bool(id in EconomyManager.plan_pool()).is_false()

func test_the_plan_pool_never_holds_a_mission_blueprint() -> void:
	RankManager.load_save_data({})
	var pool: Array = EconomyManager.plan_pool()
	assert_bool(pool.is_empty()).is_false()
	for id in pool:
		assert_bool(id in GameConfig.blueprint_required).is_false()
		assert_int(RankManager.building_rank(String(id))).is_greater(RankManager.get_rank())

# ── Casa de cambio ────────────────────────────────────────────────────

func test_the_exchange_cuts_the_spread_down_to_its_floor() -> void:
	GameConfig.market_spread = 0.3
	GameConfig.market_spread_cut = 0.0
	assert_float(GameConfig.effective_market_spread()).is_equal_approx(0.3, 0.0001)
	var buy_before := MarketManager.get_buy_price("steel")
	var sell_before := MarketManager.get_sell_price("steel")
	GameConfig.market_spread_cut = GameConfig.exchange_spread_cut
	assert_float(GameConfig.effective_market_spread()).is_equal_approx(0.2, 0.0001)
	assert_int(MarketManager.get_buy_price("steel")).is_less_equal(buy_before)
	assert_int(MarketManager.get_sell_price("steel")).is_greater_equal(sell_before)
	# Con las tecnologias ya muy abajo, nunca cruza el suelo.
	GameConfig.market_spread = 0.12
	assert_float(GameConfig.effective_market_spread()).is_equal_approx(GameConfig.exchange_spread_floor, 0.0001)

func test_interest_is_one_percent_with_a_cap() -> void:
	ResourceManager.set_amounts({"gold": 1000})
	assert_int(EconomyManager.interest_due()).is_equal(10)
	ResourceManager.set_amounts({"gold": 3000})
	assert_int(EconomyManager.interest_due()).is_equal(GameConfig.exchange_interest_cap)

func test_no_interest_in_colonist() -> void:
	if GameMode.is_governor():
		return
	ResourceManager.set_amounts({"gold": 1000})
	assert_int(EconomyManager.pay_interest()).is_equal(0)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(1000)

func test_a_working_exchange_sets_the_cut_and_clear_lifts_it() -> void:
	var o := _free_row(1, 0)
	assert_bool(o.x >= 0).is_true()
	var node := _put("exchange", o)
	Effects.refresh()
	assert_float(GameConfig.market_spread_cut).is_equal(GameConfig.exchange_spread_cut)
	assert_str(Info.economy_status(node, _data("exchange"))).is_not_empty()
	# Sin obreros, no trabaja.
	node.set_meta("staffed", false)
	Effects.refresh()
	assert_float(GameConfig.market_spread_cut).is_equal(0.0)
	Effects.clear()
	assert_float(GameConfig.market_spread_cut).is_equal(0.0)

# ── Central diesel ────────────────────────────────────────────────────

func test_a_running_plant_boosts_industry_within_reach() -> void:
	var o := _free_row(3, 1)
	assert_bool(o.x >= 0).is_true()
	var plant := _put("diesel_plant", o)
	var near := _put("foundry", o + Vector2i(3, 0))
	var house := _put("house", o + Vector2i(6, 0))
	Effects.refresh()
	assert_float(float(near.get_meta(Effects.DIESEL_META, 0.0))).is_equal(GameConfig.diesel_plant_bonus)
	assert_bool(house.has_meta(Effects.DIESEL_META)).is_false()
	assert_int(Effects.diesel_targets_of(plant)).is_equal(1)

func test_without_fuel_the_plant_stops_and_its_area_goes() -> void:
	var o := _free_row(2, 1)
	assert_bool(o.x >= 0).is_true()
	var plant := _put("diesel_plant", o)
	var near := _put("sawmill", o + Vector2i(3, 0))
	Effects.refresh()
	assert_bool(EconomyManager.is_plant_running(plant)).is_true()
	ResourceManager.set_amounts({"fuel": 0})
	assert_int(EconomyManager.burn_fuel()).is_equal(0)
	assert_bool(EconomyManager.is_plant_running(plant)).is_false()
	assert_bool(near.has_meta(Effects.DIESEL_META)).is_false()
	# Con combustible vuelve a arrancar y lo quema.
	ResourceManager.set_amounts({"fuel": 5})
	assert_int(EconomyManager.burn_fuel()).is_equal(1)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.FUEL)).is_equal(5 - GameConfig.diesel_plant_fuel_cost)
	assert_float(float(near.get_meta(Effects.DIESEL_META, 0.0))).is_equal(GameConfig.diesel_plant_bonus)

func test_the_boost_is_live_only_not_offline() -> void:
	var o := _free_row(2, 1)
	assert_bool(o.x >= 0).is_true()
	_put("diesel_plant", o)
	var mine := _put("gold_mine", o + Vector2i(3, 0))
	Effects.refresh()
	var data := _data("gold_mine")
	var live: Dictionary = ProductionManager.get_cycle_yield(mine, data, true)
	var offline: Dictionary = ProductionManager.get_cycle_yield(mine, data, false)
	assert_int(int(live.get("gold", 0))).is_greater_equal(int(offline.get("gold", 0)))

# ── Guardado ──────────────────────────────────────────────────────────

func test_save_load_is_idempotent_and_reset_throws_it_away() -> void:
	_dock([{"kind": "material", "give": {"planks": 10}, "price": 130, "sold": true}])
	EconomyManager.grant_plan("statue")
	var data: Dictionary = EconomyManager.get_save_data()
	EconomyManager.load_save_data(data)
	EconomyManager.load_save_data(data)
	assert_str(JSON.stringify(EconomyManager.get_save_data())).is_equal(JSON.stringify(data))
	assert_bool(EconomyManager.has_plan("statue")).is_true()
	assert_bool(EconomyManager.is_ship_docked()).is_true()
	EconomyManager.reset()
	assert_bool(EconomyManager.has_plan("statue")).is_false()
	assert_bool(EconomyManager.is_ship_docked()).is_false()
	assert_float(GameConfig.market_spread_cut).is_equal(0.0)

func test_an_old_save_without_the_key_loads_clean() -> void:
	EconomyManager.load_save_data({})
	assert_bool(EconomyManager.is_ship_docked()).is_false()
	assert_array(EconomyManager.get_plans()).is_empty()
