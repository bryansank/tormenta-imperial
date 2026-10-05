extends GdUnitTestSuite
## La vida de la ciudad (WorkerWalkers, 2026-10-04): cuantas figuras salen
## segun la poblacion y el tope del dispositivo, que los obreros solo van a
## edificios con dotacion de verdad, que la Tormenta vacia las calles, que las
## dos vistas dibujan sin errores y que nada de esto viaja en el guardado.
##
## Edificios de mentira en GridManager (como test_road_network) y la poblacion
## real de PopulationManager, que es quien marca `staffed`.

const Walkers := preload("res://scripts/map/WorkerWalkers.gd")
const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")

var _nodes: Array = []
var house_a: Node
var house_b: Node
var sawmill: Node
var mine: Node
var fountain: Node
var market: Node

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

## Nucleo en (10,10) con su acera (9..13), dos casas, un aserradero, una mina,
## una fuente y un mercado, todos tocando la acera. Poblacion `pop`.
func _town(pop: int) -> void:
	_put("nucleo", Vector2i(10, 10))
	for y in range(9, 14):
		for x in range(9, 14):
			if x >= 10 and x <= 12 and y >= 10 and y <= 12:
				continue
			_put("road", Vector2i(x, y))
	house_a = _put("house", Vector2i(7, 10))
	house_b = _put("house", Vector2i(14, 10))
	sawmill = _put("sawmill", Vector2i(10, 14))
	mine = _put("gold_mine", Vector2i(10, 7))
	fountain = _put("fountain", Vector2i(7, 13))
	market = _put("market", Vector2i(14, 13))
	PopulationManager.load_save_data({"population": pop})

func _walkers(layer: Node = null, is_2d: bool = false) -> Node:
	var w: Node = Walkers.new()
	w.setup(layer, is_2d)
	add_child(w)
	w.set_process(false)   # el tiempo lo lleva la prueba con tick()
	w.seed_rng(1234)
	auto_free(w)
	return w

## Anda `seconds` y devuelve el maximo de figuras que se vieron en la calle.
func _most_out(w: Node, seconds: float, step: float = 0.1) -> int:
	var most := 0
	var t := 0.0
	while t < seconds:
		w.tick(step)
		most = maxi(most, w.walker_count())
		t += step
	return most

func _run(w: Node, seconds: float, step: float = 0.1) -> void:
	var t := 0.0
	while t < seconds:
		w.tick(step)
		t += step

# ── Cuantas ──────────────────────────────────────────────────────────────

func test_one_figure_per_two_people() -> void:
	var b: Dictionary = Walkers.figure_budget(10, 4, 60, 2)
	assert_int(int(b["workers"])).is_equal(2)
	assert_int(int(b["citizens"])).is_equal(3)
	# Sin gente no sale nadie.
	b = Walkers.figure_budget(0, 0, 60, 2)
	assert_int(int(b["workers"]) + int(b["citizens"])).is_equal(0)

func test_the_cap_holds_and_splits_in_proportion() -> void:
	var b: Dictionary = Walkers.figure_budget(500, 200, 26, 2)
	assert_int(int(b["workers"]) + int(b["citizens"])).is_equal(26)
	assert_int(int(b["workers"])).is_equal(10)
	assert_int(int(b["citizens"])).is_equal(16)

func test_the_phone_gets_fewer_than_the_pc() -> void:
	assert_int(Walkers.figure_cap("phone")).is_less(Walkers.figure_cap("tablet"))
	assert_int(Walkers.figure_cap("tablet")).is_less(Walkers.figure_cap("pc"))
	# El tope de PC aguanta la medida de rendimiento (60+ figuras).
	assert_int(Walkers.figure_cap("pc")).is_greater_equal(60)

func test_the_night_hook_thins_the_streets() -> void:
	var day: Dictionary = Walkers.figure_budget(40, 10, 60, 2, 1.0)
	var night: Dictionary = Walkers.figure_budget(40, 10, 60, 2, GameConfig.life_night_presence)
	assert_int(int(night["workers"]) + int(night["citizens"])).is_less(int(day["workers"]) + int(day["citizens"]))

func test_figures_follow_the_population() -> void:
	_town(14)
	var w := _walkers()
	w.reconcile()
	var b: Dictionary = Walkers.figure_budget(PopulationManager.get_population(),
		PopulationManager.get_used_workers(), Walkers.figure_cap())
	assert_int(w.actor_count()).is_equal(int(b["workers"]) + int(b["citizens"]))
	assert_int(w.actor_count()).is_greater(0)

# ── A donde van ──────────────────────────────────────────────────────────

func test_workers_only_go_to_staffed_buildings() -> void:
	_town(14)
	PopulationManager.set_workers_off(mine, true)
	assert_bool(bool(mine.get_meta("staffed", false))).is_false()
	assert_bool(bool(sawmill.get_meta("staffed", false))).is_true()
	var w := _walkers()
	w.reconcile()
	var workers := 0
	for a in w.actors():
		if a.role == Walkers.ROLE_WORKER:
			workers += 1
			assert_object(a.target).is_not_same(mine)
			assert_bool(a.target == sawmill or a.target == market).is_true()
	assert_int(workers).is_greater(0)
	# Y andando un buen rato nadie entra en la mina.
	for i in 600:
		w.tick(0.1)
		for a in w.actors():
			assert_object(a.dest).is_not_same(mine)
			assert_object(a.at).is_not_same(mine)

func test_withdrawing_workers_sends_them_home() -> void:
	_town(14)
	var w := _walkers()
	w.reconcile()
	_run(w, 30.0)
	PopulationManager.set_workers_off(sawmill, true)
	w.reconcile()
	for a in w.actors():
		if a.role == Walkers.ROLE_WORKER and not a.retiring:
			assert_object(a.target).is_not_same(sawmill)
	_run(w, 40.0)
	for a in w.actors():
		assert_object(a.at).is_not_same(sawmill)

func test_a_building_without_a_road_gets_nobody() -> void:
	_town(14)
	var lone := _put("sawmill", Vector2i(30, 30))
	PopulationManager.load_save_data({"population": 14})
	assert_bool(bool(lone.get_meta("connected", true))).is_false()
	var w := _walkers()
	w.reconcile()
	_run(w, 30.0)
	for a in w.actors():
		assert_object(a.target).is_not_same(lone)
		assert_object(a.dest).is_not_same(lone)

func test_citizens_stop_at_decorations_and_go_home() -> void:
	_town(14)
	var w := _walkers()
	w.reconcile()
	var looked := false
	var shopped := false
	for i in 3000:
		w.tick(0.1)
		for a in w.actors():
			if a.role != Walkers.ROLE_CITIZEN:
				continue
			if a.state == Walkers.State.IDLE and a.dest == fountain:
				looked = true
			if a.state == Walkers.State.INSIDE and a.at == market:
				shopped = true
		if looked and shopped:
			break
	assert_bool(looked).override_failure_message("nadie se paro ante la fuente").is_true()
	assert_bool(shopped).override_failure_message("nadie entro al mercado").is_true()

func test_the_door_is_on_the_road_side() -> void:
	_town(10)
	var net: Dictionary = preload("res://scripts/buildings/PlacementRules.gd").connected_roads()
	var door: Dictionary = Walkers.door_of(house_a, net)
	assert_bool(door.is_empty()).is_false()
	# La casa ocupa x=7..8; su puerta da a la acera de x=9.
	assert_int((door["road"] as Vector2i).x).is_equal(9)
	var edge: Vector2 = door["edge"]
	assert_float(edge.x).is_between(8.5, 9.5)

## La red que usa la vida (una pasada) es la misma que la de las reglas.
func test_the_network_matches_the_rules() -> void:
	_town(10)
	_put("road", Vector2i(30, 30))   # suelta: no cuenta
	var mine_net: Dictionary = Walkers.network_from(GridManager.get_all_buildings())
	var rules_net: Dictionary = preload("res://scripts/buildings/PlacementRules.gd").connected_roads()
	assert_int(mine_net.size()).is_equal(rules_net.size())
	for c in rules_net:
		assert_bool(mine_net.has(c)).is_true()

# ── La Tormenta ──────────────────────────────────────────────────────────

func test_the_storm_empties_the_streets_and_the_calm_fills_them() -> void:
	_town(14)
	var w := _walkers()
	w.reconcile()
	assert_int(_most_out(w, 20.0)).is_greater(0)
	w._on_storm_phase(StormCycleScript.Phase.WARNING, 10.0)
	assert_bool(w.is_hurrying()).is_true()
	w._on_storm_phase(StormCycleScript.Phase.ASH, 10.0)
	_run(w, 1.0)
	assert_int(w.walker_count()).is_equal(0)
	for phase in [StormCycleScript.Phase.STORM, StormCycleScript.Phase.TITHE]:
		w._on_storm_phase(phase, 10.0)
		for i in 300:
			w.tick(0.1)
			assert_int(w.walker_count()).is_equal(0)
	# Pasado el Diezmo vuelven a salir.
	w._on_storm_phase(StormCycleScript.Phase.CALM, 0.0)
	assert_bool(w.is_sheltered()).is_false()
	assert_int(_most_out(w, 15.0)).is_greater(0)

# ── Las dos vistas ───────────────────────────────────────────────────────

func test_both_views_draw_the_figures() -> void:
	_town(14)
	for is_2d in [false, true]:
		var layer: Node = Node2D.new() if is_2d else Node3D.new()
		add_child(layer)
		auto_free(layer)
		var w := _walkers(layer, is_2d)
		w.reconcile()
		var figures: Node = layer.get_node("Figures")
		var seen := 0
		for i in 200:
			w.tick(0.1)
			figures.render(w.actors())
			assert_int(figures.visible_count()).is_equal(w.walker_count())
			seen = maxi(seen, figures.visible_count())
		assert_int(seen).is_greater(0)

# ── Solo vista ───────────────────────────────────────────────────────────

func test_nothing_travels_in_the_save() -> void:
	_town(14)
	var before := GridManager.get_all_buildings().size()
	var layer := Node3D.new()
	add_child(layer)
	auto_free(layer)
	var w := _walkers(layer, false)
	w.reconcile()
	_run(w, 20.0)
	# Las figuras no son edificios: GridManager (lo que se guarda) no cambia.
	assert_int(GridManager.get_all_buildings().size()).is_equal(before)
	assert_bool(w.has_method("get_save_data")).is_false()
	# Y la capa de figuras no cuelga del contenedor de edificios.
	for info in GridManager.get_all_buildings():
		assert_object(info["node"]).is_not_same(layer.get_node("Figures"))
