extends GdUnitTestSuite
## Los puestos se reparten cada vez que cambia la gente, no solo al terminar una
## obra (2026-10-12). Antes el que nacia no iba a trabajar hasta la siguiente
## obra: la primera Mina de oro se quedaba parada diez minutos con la gente ya
## nacida, y la era 1 duraba 15 minutos en vez de 10 (tools/line_probe.gd,
## docs/22-linea-jugable.md §11). Y al reves: un muerto de hambre seguia
## "trabajando" en su edificio.

var _nodes: Array = []
var _saved_population: Dictionary = {}

func before_test() -> void:
	GridManager.clear_all()
	_nodes.clear()
	_saved_population = PopulationManager.get_save_data()

func after_test() -> void:
	GridManager.clear_all()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	PopulationManager.reset()
	PopulationManager.load_save_data(_saved_population)

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id)

func _put(id: String, cell: Vector2i) -> Node:
	var n := Node.new()
	_nodes.append(n)
	assert_bool(GridManager.place_building(cell, _data(id), n)).is_true()
	return n

## Nucleo con su acera, un aserradero (2 obreros) y una mina (3) pegados a ella.
## El Nucleo da sitio para 5: con 3 habitantes solo cabe el aserradero.
func _base() -> Dictionary:
	_put("nucleo", Vector2i(10, 10))
	for y in range(9, 14):
		for x in range(9, 14):
			if x >= 10 and x <= 12 and y >= 10 and y <= 12:
				continue
			_put("road", Vector2i(x, y))
	var sawmill := _put("sawmill", Vector2i(14, 10))
	var mine := _put("gold_mine", Vector2i(14, 12))
	PopulationManager.load_save_data({"population": 3, "morale": 75})
	return {"sawmill": sawmill, "mine": mine}

func test_with_three_people_only_the_first_building_is_staffed() -> void:
	var b := _base()
	assert_bool(PopulationManager.is_building_staffed(b["sawmill"])).is_true()
	assert_bool(PopulationManager.is_building_staffed(b["mine"])).is_false()

func test_whoever_is_born_goes_to_work_at_once() -> void:
	var b := _base()
	PopulationManager._tick_growth()
	PopulationManager._tick_growth()
	assert_int(PopulationManager.get_population()).is_equal(5)
	assert_bool(PopulationManager.is_building_staffed(b["mine"])).override_failure_message(
		"con 5 habitantes la mina tiene sus 3 obreros: no hace falta esperar a otra obra").is_true()

func test_whoever_dies_leaves_the_post() -> void:
	var b := _base()
	PopulationManager._tick_growth()
	PopulationManager._tick_growth()
	PopulationManager._set_population(4)
	assert_bool(PopulationManager.is_building_staffed(b["mine"])).is_false()
	assert_bool(PopulationManager.is_building_staffed(b["sawmill"])).is_true()
