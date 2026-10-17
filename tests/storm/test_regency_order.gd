extends GdUnitTestSuite
## La Orden de la Regencia y el barometro (doc 21 §2.2, D5 = A).
##
## Lo que se vigila: las rebajas del Diezmo se suman con tope y se tiran con cada
## Diezmo; viajan en el guardado `storm` y cargar dos veces da lo mismo; un
## guardado de antes no trae nada y no rompe; el barometro da un margen que
## siempre contiene el momento de verdad y nunca un numero solo; y la API publica
## de StormManager (la que usa la rama de escaramuzas) apunta y cobra.
##
## Escrito sin ejecutar (regla de Bryan: un solo pase de pruebas al final).

const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")
const SEED := 20261014

var _saved_storm: Dictionary = {}
var _saved_resources: Dictionary = {}
var _saved_cfg: Dictionary = {}

func before_test() -> void:
	_saved_storm = StormManager.get_save_data()
	_saved_resources = {}
	var all: Dictionary = ResourceManager.get_all()
	for type in all:
		_saved_resources[ResourceManager.get_type_name(type)] = int(all[type])
	_saved_cfg = {
		"max": GameConfig.storm_order_discount_max,
		"delivery": GameConfig.storm_order_delivery_pct,
		"false_alarm": GameConfig.storm_false_alarm_chance,
	}

func after_test() -> void:
	StormManager.load_save_data(_saved_storm)
	StormManager._tithe_to_resume = false
	ResourceManager.set_amounts(_saved_resources)
	GameConfig.storm_order_discount_max = _saved_cfg["max"]
	GameConfig.storm_order_delivery_pct = _saved_cfg["delivery"]
	GameConfig.storm_false_alarm_chance = _saved_cfg["false_alarm"]

func _cycle() -> StormCycle:
	return StormCycleScript.create(SEED)

## Un guardado de Tormenta armada en calma, para StormManager.
func _armed_calm() -> Dictionary:
	var data: Dictionary = _cycle().to_dict()
	data["armed"] = true
	data["halted"] = false
	return data

# ── Rebajas (modelo puro) ────────────────────────────────────────────

func test_discounts_add_up_per_source_and_in_total() -> void:
	var cycle := _cycle()
	cycle.add_tithe_discount("entrega", 0.15)
	cycle.add_tithe_discount("expedicion", 0.10)
	cycle.add_tithe_discount("expedicion", 0.10)
	assert_float(cycle.discount_from("expedicion")).is_equal_approx(0.20, 0.0001)
	assert_float(cycle.tithe_discount()).is_equal_approx(0.35, 0.0001)

func test_the_total_discount_has_a_cap() -> void:
	GameConfig.storm_order_discount_max = 0.5
	var cycle := _cycle()
	for i in 10:
		cycle.add_tithe_discount("expedicion", 0.10)
	assert_float(cycle.tithe_discount()).is_equal_approx(0.5, 0.0001)
	# El Diezmo nunca baja de la mitad.
	assert_int(cycle.discounted(100)).is_equal(50)

func test_discounted_rounds_up() -> void:
	var cycle := _cycle()
	cycle.add_tithe_discount("entrega", 0.15)
	assert_int(cycle.discounted(61)).is_equal(52)   # 51,85 -> 52
	assert_int(cycle.discounted(0)).is_equal(0)

func test_no_discount_is_written_while_they_collect() -> void:
	var cycle := _cycle()
	cycle.phase = StormCycle.Phase.TITHE
	cycle.add_tithe_discount("entrega", 0.15)
	assert_float(cycle.tithe_discount()).is_equal(0.0)

func test_settling_the_tithe_clears_the_order_and_discounts() -> void:
	var cycle := _cycle()
	cycle.roll_order(["planks"])
	cycle.add_tithe_discount("entrega", 0.15)
	cycle.phase = StormCycle.Phase.TITHE
	cycle.settle_tithe(0, 2, false)
	assert_float(cycle.tithe_discount()).is_equal(0.0)
	assert_bool(cycle.order.is_empty()).is_true()
	assert_float(cycle.calm_total).is_greater(0.0)

func test_a_false_alarm_keeps_the_order() -> void:
	GameConfig.storm_false_alarm_chance = 1.0
	var cycle := _cycle()
	cycle.roll_order(["planks"])
	cycle.add_tithe_discount("entrega", 0.15)
	cycle.summon_now()
	cycle.forced = false   # que la moneda decida: falsa alarma segura
	cycle.advance(GameConfig.get_storm_warning() + 0.1)
	assert_int(cycle.phase).is_equal(StormCycle.Phase.CALM)
	assert_bool(cycle.order.is_empty()).is_false()
	assert_float(cycle.tithe_discount()).is_equal_approx(0.15, 0.0001)

# ── El encargo ───────────────────────────────────────────────────────

func test_the_order_only_asks_for_known_candidates() -> void:
	var cycle := _cycle()
	var order: Dictionary = cycle.roll_order(["beams", "nonsense"])
	assert_str(String(order["res"])).is_equal("beams")
	assert_int(int(order["amount"])).is_equal(int(GameConfig.storm_order_delivery_base["beams"]))
	assert_bool(cycle.roll_order(["nonsense"]).is_empty()).is_true()

func test_the_order_grows_with_storms_but_has_a_cap() -> void:
	var cycle := _cycle()
	cycle.storms_survived = 1000
	var order: Dictionary = cycle.roll_order(["planks"])
	var cap: int = roundi(float(GameConfig.storm_order_delivery_base["planks"]) * GameConfig.storm_order_delivery_growth_max)
	assert_int(int(order["amount"])).is_equal(cap)

func test_completing_the_order_writes_its_discount_once() -> void:
	var cycle := _cycle()
	cycle.roll_order(["planks"])
	assert_bool(cycle.complete_order()).is_true()
	assert_bool(cycle.complete_order()).is_false()
	assert_float(cycle.discount_from("entrega")).is_equal_approx(GameConfig.storm_order_delivery_pct, 0.0001)

func test_rolling_the_order_does_not_move_the_storm_clock() -> void:
	# La Orden tiene su propio generador: con la misma semilla, la calma dura lo
	# mismo se sortee o no un encargo.
	var plain := _cycle()
	var with_order := _cycle()
	for i in 5:
		with_order.roll_order(["planks", "ingots"])
	plain.phase = StormCycle.Phase.TITHE
	with_order.phase = StormCycle.Phase.TITHE
	plain.settle_tithe(0, 2)
	with_order.settle_tithe(0, 2)
	assert_float(with_order.seconds_left).is_equal(plain.seconds_left)

# ── Barometro ────────────────────────────────────────────────────────

func test_the_barometer_range_always_contains_the_truth() -> void:
	for s in 50:
		var cycle := StormCycleScript.create(SEED + s)
		for step in 12:
			var baro: Dictionary = cycle.barometer()
			if baro.is_empty():
				break
			var minutes: float = cycle.seconds_left / 60.0
			assert_float(minutes).is_greater_equal(float(baro["low"]))
			assert_float(minutes).is_less_equal(float(baro["high"]))
			assert_int(int(baro["high"])).is_greater(int(baro["low"]))
			cycle.advance(cycle.calm_total / 12.0)

func test_the_barometer_fills_up_during_the_calm() -> void:
	var cycle := _cycle()
	var start: float = float(cycle.barometer()["fill"])
	cycle.advance(cycle.calm_total * 0.5)
	var half: float = float(cycle.barometer()["fill"])
	assert_float(start).is_equal_approx(0.0, 0.001)
	assert_float(half).is_equal_approx(0.5, 0.01)

func test_no_barometer_outside_the_calm() -> void:
	var cycle := _cycle()
	cycle.summon_now()
	assert_bool(cycle.barometer().is_empty()).is_true()

# ── Guardado ─────────────────────────────────────────────────────────

func test_the_order_survives_a_save_and_loading_twice_changes_nothing() -> void:
	var cycle := _cycle()
	cycle.roll_order(["ingots"])
	cycle.add_tithe_discount("entrega", 0.15)
	cycle.add_tithe_discount("expedicion", 0.10)
	var data: Dictionary = cycle.to_dict()
	var once := StormCycleScript.from_dict(data)
	var twice := StormCycleScript.from_dict(once.to_dict())
	assert_float(twice.tithe_discount()).is_equal_approx(0.25, 0.0001)
	assert_str(String(twice.order["res"])).is_equal("ingots")
	assert_float(twice.calm_total).is_equal_approx(cycle.calm_total, 0.001)
	assert_float(twice.barometer_offset).is_equal_approx(cycle.barometer_offset, 0.001)

func test_an_old_save_loads_without_order_or_discounts() -> void:
	var old := {"v": 2, "phase": StormCycle.Phase.CALM, "seconds_left": 200.0, "severity": 2}
	var cycle := StormCycleScript.from_dict(old)
	assert_float(cycle.tithe_discount()).is_equal(0.0)
	assert_bool(cycle.order.is_empty()).is_true()
	assert_float(cycle.calm_total).is_equal(200.0)
	assert_bool(cycle.barometer().is_empty()).is_false()

# ── StormManager: la API publica ─────────────────────────────────────

func test_add_tithe_discount_needs_an_armed_clock() -> void:
	var data: Dictionary = _cycle().to_dict()
	data["armed"] = false
	StormManager.load_save_data(data)
	assert_float(StormManager.add_tithe_discount("expedicion", 0.10, false)).is_equal(-1.0)

func test_add_tithe_discount_is_additive_and_saved() -> void:
	if not GameMode.tithe_enabled() or not GameMode.storm_enabled():
		return   # modo sin Diezmo en este proceso: no hay Orden que probar
	StormManager.load_save_data(_armed_calm())
	StormManager.add_tithe_discount("expedicion", 0.10, false)
	StormManager.add_tithe_discount("expedicion", 0.10, false)
	assert_float(StormManager.get_discount_from("expedicion")).is_equal_approx(0.20, 0.0001)
	var saved: Dictionary = StormManager.get_save_data()
	StormManager.load_save_data(saved)
	StormManager.load_save_data(saved)
	assert_float(StormManager.get_tithe_discount()).is_equal_approx(0.20, 0.0001)

func test_loading_an_armed_old_save_rolls_an_order() -> void:
	if not GameMode.tithe_enabled() or not GameMode.storm_enabled():
		return
	StormManager.load_save_data(_armed_calm())
	assert_bool(StormManager.get_order().is_empty()).is_false()
	# Y no se vuelve a sortear al cargar otra vez lo mismo.
	var first: Dictionary = StormManager.get_order()
	StormManager.load_save_data(StormManager.get_save_data())
	assert_dict(StormManager.get_order()).is_equal(first)

func test_delivering_pays_and_discounts() -> void:
	if not GameMode.tithe_enabled() or not GameMode.storm_enabled():
		return
	StormManager.load_save_data(_armed_calm())
	var order: Dictionary = StormManager.get_order()
	if order.is_empty():
		return
	var type: int = ResourceManager.name_to_type(String(order["res"]))
	ResourceManager.unlock(type)
	ResourceManager.add(type, int(order["amount"]) + 5)
	if not StormManager.can_deliver_order():
		return   # bolsa llena en este proceso (madera u oro): nada que comprobar
	var before: int = ResourceManager.get_amount(type)
	assert_bool(StormManager.deliver_order()).is_true()
	assert_int(ResourceManager.get_amount(type)).is_equal(before - int(order["amount"]))
	assert_float(StormManager.get_discount_from("entrega")).is_equal_approx(GameConfig.storm_order_delivery_pct, 0.0001)
	assert_bool(StormManager.deliver_order()).is_false()

func test_the_preview_shows_the_discount() -> void:
	if not GameMode.tithe_enabled() or not GameMode.storm_enabled():
		return
	StormManager.load_save_data(_armed_calm())
	StormManager.add_tithe_discount("entrega", 0.2, false)
	var preview: Dictionary = StormManager.tithe_preview()
	assert_float(float(preview["ratio_after"])).is_equal_approx(float(preview["ratio"]) * 0.8, 0.0001)
	assert_int(int(preview["escort"])).is_greater(0)

func test_reset_throws_the_order_away() -> void:
	if not GameMode.tithe_enabled() or not GameMode.storm_enabled():
		return
	StormManager.load_save_data(_armed_calm())
	StormManager.add_tithe_discount("entrega", 0.2, false)
	StormManager.reset()
	assert_float(StormManager.get_tithe_discount()).is_equal(0.0)
	assert_bool(StormManager.get_order().is_empty()).is_true()
