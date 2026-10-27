extends GdUnitTestSuite
## El barco del contrabandista, modelo puro (scripts/economy/SmugglerShip.gd,
## feat/edificios-economia, doc 14 §P4): reloj, atraque, ofertas y guardado.
## Sin escena ni autoloads que cambien: todo con un RNG sembrado.
##
## Escrita sin correr (regla de Bryan: un solo pase de pruebas al final).

const Ship := preload("res://scripts/economy/SmugglerShip.gd")

const CLOCK := {"port": true, "calm": true, "first_wait": 60.0,
	"interval_min": 360.0, "interval_max": 600.0, "dock_seconds": 90.0}

func _cfg() -> Dictionary:
	return {
		"offer_count": 3,
		"parts_amount": [2, 4],
		"parts_price": 60,
		"plan_chance": 0.45,
		"plan_price_per_rank": 40,
		"plan_price_min": 120,
		"materials": {"planks": {"amount": [8, 14], "price": 13}, "beams": {"amount": [4, 8], "price": 52}},
		"resource_amount": [40, 80],
		"sell_discount": 0.75,
		"buy_premium": 1.6,
		"buy_chance": 0.5,
	}

func _offer_ctx(plans: Array = []) -> Dictionary:
	var ctx := CLOCK.duplicate()
	ctx.merge({
		"materials": ["planks", "beams"],
		"resources": ["wood", "steel"],
		"prices": {"wood": {"buy": 4, "sell": 2}, "steel": {"buy": 10, "sell": 6}},
		"plans": plans,
		"plan_ranks": {"palm_trees": 13, "statue": 8},
		"cfg": _cfg(),
	})
	return ctx

func _ship(seed_value := 1234):
	return Ship.create(seed_value)

## Avanza hasta que pida atracar (o se acabe el margen). Devuelve los segundos.
func _until_ready(ship, ctx: Dictionary, limit := 2000.0) -> float:
	var t := 0.0
	while t < limit:
		for e in ship.advance(1.0, ctx):
			if String(e.get("e", "")) == "ready":
				return t
		t += 1.0
	return -1.0

# ── Reloj ─────────────────────────────────────────────────────────────

func test_without_a_port_nothing_comes() -> void:
	var ship = _ship()
	var ctx := CLOCK.duplicate()
	ctx["port"] = false
	assert_float(_until_ready(ship, ctx, 1500.0)).is_equal(-1.0)
	assert_bool(ship.is_docked()).is_false()

func test_the_first_ship_comes_after_the_first_wait() -> void:
	var ship = _ship()
	var t := _until_ready(ship, CLOCK)
	assert_float(t).is_between(58.0, 61.0)

func test_it_does_not_come_while_ash_falls() -> void:
	var ship = _ship()
	var stormy := CLOCK.duplicate()
	stormy["calm"] = false
	assert_float(_until_ready(ship, stormy, 300.0)).is_equal(-1.0)
	# En cuanto escampa, entra (el reloj ya estaba a cero).
	assert_float(_until_ready(ship, CLOCK, 5.0)).is_equal(0.0)

func test_dock_gives_three_offers_and_the_next_wait_is_in_range() -> void:
	var ship = _ship()
	_until_ready(ship, CLOCK)
	var events: Array = ship.dock(_offer_ctx())
	assert_str(String(events[0]["e"])).is_equal("docked")
	assert_bool(ship.is_docked()).is_true()
	assert_float(ship.docked_left).is_equal(90.0)
	assert_int(ship.offers.size()).is_equal(3)
	assert_float(ship.wait_left).is_between(360.0, 600.0)
	assert_int(ship.visits).is_equal(1)

func test_it_leaves_after_its_time() -> void:
	var ship = _ship()
	_until_ready(ship, CLOCK)
	ship.dock(_offer_ctx())
	var reason := ""
	for i in 100:
		for e in ship.advance(1.0, CLOCK):
			if String(e.get("e", "")) == "departed":
				reason = String(e["reason"])
		if reason != "":
			break
	assert_str(reason).is_equal("time")
	assert_bool(ship.is_docked()).is_false()
	assert_int(ship.offers.size()).is_equal(0)

func test_the_ash_sends_it_away_early() -> void:
	var ship = _ship()
	_until_ready(ship, CLOCK)
	ship.dock(_offer_ctx())
	var stormy := CLOCK.duplicate()
	stormy["calm"] = false
	var events: Array = ship.advance(1.0, stormy)
	assert_str(String(events[0]["e"])).is_equal("departed")
	assert_str(String(events[0]["reason"])).is_equal("storm")

# ── Ofertas ───────────────────────────────────────────────────────────

func test_offers_are_one_exclusive_one_material_one_resource() -> void:
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		var ship = _ship(seed_value)
		var offers: Array = ship.roll_offers(_offer_ctx(["palm_trees"]))
		assert_int(offers.size()).is_equal(3)
		assert_bool(String(offers[0]["kind"]) in ["parts", "plan"]).is_true()
		assert_str(String(offers[1]["kind"])).is_equal("material")
		assert_bool(String(offers[2]["kind"]) in ["sell", "buy"]).is_true()
		for o in offers:
			assert_bool(bool(o["sold"])).is_false()

func test_a_plan_is_only_one_of_the_pool_and_priced_by_rank() -> void:
	var seen_plan := false
	for seed_value in range(1, 40):
		var ship = _ship(seed_value)
		var o: Dictionary = ship.roll_offers(_offer_ctx(["palm_trees"]))[0]
		if String(o["kind"]) == "plan":
			seen_plan = true
			assert_str(String(o["plan"])).is_equal("palm_trees")
			assert_int(int(o["price"])).is_equal(13 * 40)
	assert_bool(seen_plan).is_true()

func test_no_plan_when_the_pool_is_empty() -> void:
	for seed_value in range(1, 30):
		var ship = _ship(seed_value)
		var o: Dictionary = ship.roll_offers(_offer_ctx([]))[0]
		assert_str(String(o["kind"])).is_equal("parts")
		var n: int = int(o["give"]["parts"])
		assert_int(n).is_between(2, 4)
		assert_int(int(o["price"])).is_equal(n * 60)

func test_sell_is_cheaper_and_buy_pays_more_than_the_market() -> void:
	for seed_value in range(1, 30):
		var ship = _ship(seed_value)
		var o: Dictionary = ship.roll_offers(_offer_ctx())[2]
		var prices: Dictionary = _offer_ctx()["prices"]
		if String(o["kind"]) == "sell":
			var res: String = (o["give"] as Dictionary).keys()[0]
			var n: int = int(o["give"][res])
			assert_int(n % 10).is_equal(0)
			assert_bool(int(o["price"]) < int(prices[res]["buy"]) * n).is_true()
		else:
			var res: String = (o["ask"] as Dictionary).keys()[0]
			var n: int = int(o["ask"][res])
			assert_bool(int(o["pay"]) > int(prices[res]["sell"]) * n).is_true()

func test_an_offer_sells_once() -> void:
	var ship = _ship()
	_until_ready(ship, CLOCK)
	ship.dock(_offer_ctx())
	assert_bool(ship.offer(0).is_empty()).is_false()
	assert_bool(ship.mark_sold(0)).is_true()
	assert_bool(ship.offer(0).is_empty()).is_true()
	assert_bool(ship.mark_sold(0)).is_false()

# ── Guardado ──────────────────────────────────────────────────────────

func test_save_round_trip_keeps_the_ship_and_its_dice() -> void:
	var ship = _ship(77)
	_until_ready(ship, CLOCK)
	ship.dock(_offer_ctx(["statue"]))
	ship.mark_sold(1)
	ship.advance(10.0, CLOCK)
	var data: Dictionary = ship.to_dict()
	var back = Ship.from_dict(data)
	assert_float(back.docked_left).is_equal(ship.docked_left)
	assert_float(back.wait_left).is_equal(ship.wait_left)
	assert_int(back.visits).is_equal(1)
	assert_int(back.offers.size()).is_equal(3)
	assert_bool(bool(back.offers[1]["sold"])).is_true()
	# Mismo dado: las proximas ofertas salen iguales.
	var a: Array = ship.roll_offers(_offer_ctx())
	var b: Array = back.roll_offers(_offer_ctx())
	assert_str(JSON.stringify(a)).is_equal(JSON.stringify(b))

func test_loading_twice_is_the_same() -> void:
	var ship = _ship(5)
	_until_ready(ship, CLOCK)
	ship.dock(_offer_ctx())
	var data: Dictionary = ship.to_dict()
	var once = Ship.from_dict(data)
	var twice = Ship.from_dict(once.to_dict())
	assert_str(JSON.stringify(once.to_dict())).is_equal(JSON.stringify(twice.to_dict()))

func test_an_empty_save_is_a_new_ship() -> void:
	var ship = Ship.from_dict({})
	assert_bool(ship.is_docked()).is_false()
	assert_int(ship.visits).is_equal(0)
	assert_float(ship.wait_left).is_less(0.0)
