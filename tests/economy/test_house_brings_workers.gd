extends GdUnitTestSuite
## Una Casa trae a su gente al terminarla (decision de Bryan, 2026-10-19).
## Antes llegaba de uno en uno, +1 por tic de crecimiento, y una Casa tardaba
## unos dos minutos en llenarse: "siento que tardan en aparecer". Ahora, al
## acabar la obra (o la mejora), entran todos los que caben, si la moral no esta
## por debajo del umbral de crecimiento. El goteo de _tick_growth queda para
## recuperar a los que se pierden. Los recien llegados salen de esa casa.

const Walkers := preload("res://scripts/map/WorkerWalkers.gd")

var _nodes: Array = []
var _saved_population: Dictionary = {}
var _arrived: Array = []

func before_test() -> void:
	GridManager.clear_all()
	_nodes.clear()
	_arrived.clear()
	_saved_population = PopulationManager.get_save_data()
	EventBus.residents_arrived.connect(_on_arrived)
	DayClock.reset()

func after_test() -> void:
	if EventBus.residents_arrived.is_connected(_on_arrived):
		EventBus.residents_arrived.disconnect(_on_arrived)
	GridManager.clear_all()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	PopulationManager.reset()
	PopulationManager.load_save_data(_saved_population)
	DayClock.reset()

func _on_arrived(home: Node, count: int) -> void:
	_arrived.append([home, count])

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id)

func _put(id: String, cell: Vector2i) -> Node:
	var n := Node.new()
	_nodes.append(n)
	assert_bool(GridManager.place_building(cell, _data(id), n)).is_true()
	return n

## Nucleo (sitio para 5) con su acera, una mina (3 obreros) y un aserradero (2)
## pegados a ella, y una Casa en obra. Poblacion 5, moral `morale`.
func _base(morale: int = 75) -> Dictionary:
	_put("nucleo", Vector2i(10, 10))
	for y in range(9, 14):
		for x in range(9, 14):
			if x >= 10 and x <= 12 and y >= 10 and y <= 12:
				continue
			_put("road", Vector2i(x, y))
	var sawmill := _put("sawmill", Vector2i(14, 10))
	var mine := _put("gold_mine", Vector2i(10, 7))
	var house := _put("house", Vector2i(7, 10))
	house.set_meta("under_construction", true)
	PopulationManager.load_save_data({"population": 5, "morale": morale})
	return {"sawmill": sawmill, "mine": mine, "house": house}

## Lo que hace ProductionManager al terminar la obra.
func _finish(house: Node) -> void:
	house.remove_meta("under_construction")
	EventBus.construction_completed.emit(house)

func _room(level: int) -> int:
	return int(_data("house").population_capacity
		* GameConfig.level_mult(GameConfig.upgrade_capacity_multiplier, level))

func test_a_finished_house_fills_at_once() -> void:
	var b := _base()
	assert_int(PopulationManager.get_population()).is_equal(5)
	_finish(b["house"])
	assert_int(PopulationManager.get_population()).override_failure_message(
		"los 6 de la Casa llegan juntos al terminarla, sin esperar tics").is_equal(5 + _room(1))
	assert_int(PopulationManager.get_max_population()).is_equal(5 + _room(1))
	assert_int(_arrived.size()).is_equal(1)
	assert_object(_arrived[0][0]).is_same(b["house"])
	assert_int(int(_arrived[0][1])).is_equal(_room(1))
	# El reparto se rehace con la gente nueva.
	assert_bool(PopulationManager.is_building_staffed(b["sawmill"])).is_true()
	assert_bool(PopulationManager.is_building_staffed(b["mine"])).is_true()

func test_with_low_morale_nobody_comes_at_once() -> void:
	var b := _base(GameConfig.morale_growth_threshold - 5)
	_finish(b["house"])
	assert_int(PopulationManager.get_population()).is_equal(5)
	assert_int(_arrived.size()).is_equal(0)
	# Siguen viniendo de uno en uno cuando la moral se recupera.
	PopulationManager._tick_growth()
	assert_int(PopulationManager.get_population()).is_equal(5)
	PopulationManager._morale = GameConfig.morale_growth_threshold
	PopulationManager._tick_growth()
	assert_int(PopulationManager.get_population()).is_equal(6)

func test_an_upgrade_brings_its_extra_room_and_the_ones_it_displaced() -> void:
	var b := _base()
	var house: Node = b["house"]
	_finish(house)
	assert_int(PopulationManager.get_population()).is_equal(5 + _room(1))
	# Durante la mejora la casa no da sitio: los suyos se quedan fuera.
	house.set_meta("under_construction", true)
	PopulationManager._recalculate_all()
	assert_int(PopulationManager.get_population()).is_equal(5)
	house.remove_meta("under_construction")
	house.set_meta("level", 2)
	EventBus.building_upgrade_completed.emit(house, 2)
	assert_int(_room(2)).is_greater(_room(1))
	assert_int(PopulationManager.get_population()).is_equal(5 + _room(2))
	assert_int(int(_arrived[-1][1])).is_equal(_room(2))

func test_an_upgrade_without_eviction_adds_only_the_extra() -> void:
	var b := _base()
	var house: Node = b["house"]
	_finish(house)
	house.set_meta("level", 2)
	EventBus.building_upgrade_completed.emit(house, 2)
	assert_int(PopulationManager.get_population()).is_equal(5 + _room(2))
	assert_int(int(_arrived[-1][1])).is_equal(_room(2) - _room(1))

func test_losses_come_back_slowly() -> void:
	var b := _base()
	_finish(b["house"])
	PopulationManager._set_population(8)
	PopulationManager._tick_growth()
	assert_int(PopulationManager.get_population()).override_failure_message(
		"los que se pierden vuelven de uno en uno, no de golpe").is_equal(9)

func test_a_house_without_road_brings_nobody() -> void:
	var b := _base()
	var loose := _put("house", Vector2i(30, 30))
	loose.set_meta("under_construction", true)
	PopulationManager._recalculate_all()
	_finish(loose)
	assert_int(PopulationManager.get_population()).is_equal(5)
	assert_int(_arrived.size()).is_equal(0)
	assert_bool(b["house"].has_meta("under_construction")).is_true()

func test_other_buildings_bring_nobody() -> void:
	var b := _base()
	var sawmill: Node = b["sawmill"]
	sawmill.set_meta("under_construction", true)
	PopulationManager._recalculate_all()
	_finish(sawmill)
	assert_int(PopulationManager.get_population()).is_equal(5)
	assert_int(_arrived.size()).is_equal(0)

func test_the_newcomers_walk_out_of_the_new_house() -> void:
	var b := _base()
	var w: Node = Walkers.new()
	w.setup(null, false)
	add_child(w)
	w.set_process(false)
	w.seed_rng(1234)
	auto_free(w)
	w.reconcile()
	var before: Array = w.actors().duplicate()
	_finish(b["house"])
	w.reconcile()
	var fresh := 0
	for a in w.actors():
		if before.has(a):
			continue
		assert_object(a.home).override_failure_message(
			"una figura nueva sale de la Casa recien llenada").is_same(b["house"])
		fresh += 1
	assert_int(fresh).is_greater(0)
