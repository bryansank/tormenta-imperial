extends GdUnitTestSuite
## El trafico (RoadTraffic, feat/decoraciones-y-trafico, doc 21 §7 V5): cuantos
## camiones salen segun los extractores y el tope del dispositivo y de la
## calidad, que salen de extractores con dotacion y van al Almacen (o al
## Nucleo), que la Tormenta los mete dentro, que las dos vistas los dibujan y
## que nada viaja en el guardado. Escritas sin correr (regla de Bryan).
##
## La misma ciudad de mentira que test_city_life.

const Traffic := preload("res://scripts/map/RoadTraffic.gd")
const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")

var _nodes: Array = []
var sawmill: Node
var mine: Node
var warehouse: Node
var core: Node

func before_test() -> void:
	GridManager.clear_all()
	_nodes.clear()

func after_test() -> void:
	GridManager.clear_all()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	PopulationManager.reset()

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id)

func _put(id: String, cell: Vector2i) -> Node:
	var n := Node.new()
	_nodes.append(n)
	assert_bool(GridManager.place_building(cell, _data(id), n)).is_true()
	return n

## Nucleo en (10,10) con su acera (9..13), una casa, un aserradero y una mina
## tocando la acera; con `with_warehouse`, un Almacen tambien.
func _town(pop: int, with_warehouse: bool) -> void:
	core = _put("nucleo", Vector2i(10, 10))
	for y in range(9, 14):
		for x in range(9, 14):
			if x >= 10 and x <= 12 and y >= 10 and y <= 12:
				continue
			_put("road", Vector2i(x, y))
	_put("house", Vector2i(7, 10))
	sawmill = _put("sawmill", Vector2i(10, 14))
	mine = _put("gold_mine", Vector2i(10, 7))
	if with_warehouse:
		warehouse = _put("warehouse", Vector2i(12, 7))
	PopulationManager.load_save_data({"population": pop})

func _traffic(layer: Node = null, is_2d: bool = false) -> Node:
	var t: Node = Traffic.new()
	t.setup(layer, is_2d)
	add_child(t)
	t.set_process(false)   # el tiempo lo lleva la prueba con tick()
	t.seed_rng(4321)
	auto_free(t)
	return t

func _run(t: Node, seconds: float, step: float = 0.1) -> int:
	var most := 0
	var s := 0.0
	while s < seconds:
		t.tick(step)
		most = maxi(most, t.driving_count())
		s += step
	return most

# ── Cuantos ──────────────────────────────────────────────────────────────

func test_one_truck_per_two_extractors_with_a_cap() -> void:
	assert_int(Traffic.truck_budget(0, 12, 2)).is_equal(0)
	assert_int(Traffic.truck_budget(1, 12, 2)).is_equal(1)
	assert_int(Traffic.truck_budget(5, 12, 2)).is_equal(3)
	assert_int(Traffic.truck_budget(40, 5, 2)).is_equal(5)

func test_the_phone_gets_fewer_and_minimal_quality_none() -> void:
	assert_int(Traffic.truck_cap("phone", 0)).is_less(Traffic.truck_cap("tablet", 0))
	assert_int(Traffic.truck_cap("tablet", 0)).is_less(Traffic.truck_cap("pc", 0))
	assert_int(Traffic.truck_cap("pc", 1)).is_equal(GameConfig.traffic_truck_cap_minimal)
	# Pocos y baratos: nunca mas que una fraccion de la gente.
	assert_int(Traffic.truck_cap("pc", 0)).is_less_equal(GameConfig.life_figure_cap["pc"] / 4)

func test_only_producers_carry_cargo() -> void:
	assert_object(Traffic.cargo_color(_data("sawmill"))).is_not_null()
	assert_object(Traffic.cargo_color(_data("gold_mine"))).is_not_null()
	assert_object(Traffic.cargo_color(_data("house"))).is_null()
	assert_object(Traffic.cargo_color(_data("garden"))).is_null()
	assert_object(Traffic.cargo_color(_data("nucleo"))).is_null()
	assert_bool(Traffic.is_depot(_data("warehouse"))).is_true()

# ── A donde van ──────────────────────────────────────────────────────────

func test_trucks_run_from_extractors_to_the_warehouse() -> void:
	_town(14, true)
	var t := _traffic()
	t.reconcile()
	assert_int(t.truck_count()).is_equal(Traffic.truck_budget(2, Traffic.truck_cap()))
	for k in t.trucks():
		assert_bool(k.source == sawmill or k.source == mine).is_true()
		assert_object(k.dest).is_same(warehouse)
	assert_int(_run(t, 30.0)).is_greater(0)
	# Ida cargado, vuelta vacio: alguno cambia de estado en el camino.
	var loaded := {}
	for i in 600:
		t.tick(0.1)
		for k in t.trucks():
			if k.out:
				loaded[k.loaded] = true
	assert_bool(loaded.has(true) and loaded.has(false)).is_true()

func test_without_a_warehouse_they_unload_at_the_core() -> void:
	_town(14, false)
	var t := _traffic()
	t.reconcile()
	assert_int(t.truck_count()).is_greater(0)
	for k in t.trucks():
		assert_object(k.dest).is_same(core)

func test_withdrawn_workers_park_the_truck() -> void:
	_town(14, true)
	PopulationManager.set_workers_off(mine, true)
	PopulationManager.set_workers_off(sawmill, true)
	var t := _traffic()
	t.reconcile()
	assert_int(t.truck_count()).is_equal(0)

func test_trucks_stay_on_the_road_network() -> void:
	_town(14, true)
	var t := _traffic()
	t.reconcile()
	var net: Dictionary = preload("res://scripts/map/WorkerWalkers.gd").network_from(GridManager.get_all_buildings())
	for i in 400:
		t.tick(0.1)
		for k in t.trucks():
			if not k.out or k.scale < 0.99:
				continue   # en la puerta, entrando o saliendo
			var c := Vector2i(floori(k.pos.x), floori(k.pos.y))
			assert_bool(net.has(c)).override_failure_message("fuera de la red en %s" % c).is_true()

# ── La Tormenta ──────────────────────────────────────────────────────────

func test_the_storm_parks_every_truck() -> void:
	_town(14, true)
	var t := _traffic()
	t.reconcile()
	assert_int(_run(t, 20.0)).is_greater(0)
	t._on_storm_phase(StormCycleScript.Phase.ASH, 10.0)
	_run(t, 1.0)
	assert_int(t.driving_count()).is_equal(0)
	for phase in [StormCycleScript.Phase.STORM, StormCycleScript.Phase.TITHE]:
		t._on_storm_phase(phase, 10.0)
		assert_int(_run(t, 20.0)).is_equal(0)
	t._on_storm_phase(StormCycleScript.Phase.CALM, 0.0)
	assert_bool(t.is_sheltered()).is_false()
	assert_int(_run(t, 20.0)).is_greater(0)

# ── Dibujo ───────────────────────────────────────────────────────────────

func test_both_views_draw_the_trucks() -> void:
	for is_2d in [false, true]:
		GridManager.clear_all()
		_town(14, true)
		var layer: Node = auto_free(Node2D.new() if is_2d else Node3D.new())
		add_child(layer)
		var t := _traffic(layer, is_2d)
		t.reconcile()
		_run(t, 15.0)
		var figs: Node = layer.get_node("Trucks")
		figs.render(t.trucks())
		assert_int(figs.visible_count()).is_equal(t.driving_count())
		await get_tree().process_frame
		for n in _nodes:
			if is_instance_valid(n):
				n.free()
		_nodes.clear()

func test_one_draw_call_and_a_cheap_truck() -> void:
	var mesh: ArrayMesh = preload("res://scripts/map/TrafficFigures3D.gd").truck_mesh()
	assert_int(mesh.get_surface_count()).is_equal(1)
	assert_int(preload("res://tools/toy_kit.gd").tri_count(mesh)).is_less_equal(450)

## Solo vista: ni se guarda ni deja metas en los edificios.
func test_nothing_travels_in_the_save() -> void:
	_town(14, true)
	var before := sawmill.get_meta_list().size()
	var t := _traffic()
	t.reconcile()
	_run(t, 20.0)
	assert_bool(t.has_method("get_save_data")).is_false()
	assert_int(sawmill.get_meta_list().size()).is_equal(before)
