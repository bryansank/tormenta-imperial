extends GdUnitTestSuite
## La red de carreteras (2026-09-28): todo edificio toca una carretera unida al
## Nucleo, la partida empieza con la acera alrededor, quitar una carretera que
## conecta algo no se deja, y los trabajadores andan por la red.
##
## Solo toca GridManager, con nodos de mentira: la regla es de la rejilla.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")

var _nodes: Array = []

func before_test() -> void:
	GridManager.clear_all()
	_nodes.clear()

func after_test() -> void:
	GridManager.clear_all()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id)

func _put(id: String, cell: Vector2i) -> Node:
	var n := Node.new()
	_nodes.append(n)
	assert_bool(GridManager.place_building(cell, _data(id), n)).is_true()
	return n

## Nucleo 3x3 en (10,10) con su acera: la vuelta de carreteras de (9,9) a (13,13).
func _core_with_ring() -> void:
	_put("nucleo", Vector2i(10, 10))
	for y in range(9, 14):
		for x in range(9, 14):
			if x >= 10 and x <= 12 and y >= 10 and y <= 12:
				continue
			_put("road", Vector2i(x, y))

func test_the_ring_is_the_network() -> void:
	_core_with_ring()
	assert_int(Rules.connected_roads().size()).is_equal(16)

func test_a_building_touching_the_ring_is_connected_and_one_away_is_not() -> void:
	_core_with_ring()
	# Casa 2x2 pegada a la acera por la izquierda (x=7..8, la acera en x=9).
	assert_bool(Rules.is_connected_spot("house", Vector2i(7, 10), Vector2i(2, 2))).is_true()
	# Una celda mas lejos ya no la toca.
	assert_bool(Rules.is_connected_spot("house", Vector2i(6, 10), Vector2i(2, 2))).is_false()
	var verdict := Rules.evaluate_placement("house", Vector2i(6, 10), Vector2i(2, 2), null)
	assert_str(String(verdict["reason"])).is_equal("road")

func test_a_road_has_to_grow_from_the_network() -> void:
	_core_with_ring()
	assert_bool(Rules.is_connected_spot("road", Vector2i(8, 11), Vector2i.ONE)).is_true()
	assert_bool(Rules.is_connected_spot("road", Vector2i(5, 11), Vector2i.ONE)).is_false()

func test_without_a_core_there_is_no_rule() -> void:
	# Escenas de prueba montadas a mano: sin Nucleo no hay red que exigir.
	assert_bool(Rules.is_connected_spot("house", Vector2i(3, 3), Vector2i(2, 2))).is_true()

func test_the_route_paves_the_shortest_way() -> void:
	_core_with_ring()
	# Casa en (4,10): le faltan las celdas x=6..8 para tocar la acera en x=9.
	var route: Variant = Rules.road_route(Vector2i(4, 10), Vector2i(2, 2))
	assert_object(route).is_not_null()
	assert_int((route as Array).size()).is_equal(3)
	# Pegada ya a la acera no hace falta nada.
	assert_array(Rules.road_route(Vector2i(7, 10), Vector2i(2, 2))).is_empty()

func test_a_road_that_links_a_building_cannot_be_removed() -> void:
	_core_with_ring()
	var spur := _put("road", Vector2i(8, 11))
	_put("house", Vector2i(6, 11))
	assert_object(Rules.road_removal_strands(spur)).is_not_null()
	# Una de la acera que no deja a nadie suelto, si.
	var corner: Node = GridManager.get_building_at(Vector2i(13, 13))
	assert_object(Rules.road_removal_strands(corner)).is_null()

func test_workers_walk_from_the_core_to_the_building() -> void:
	_core_with_ring()
	_put("road", Vector2i(8, 11))
	var house := _put("house", Vector2i(6, 11))
	var path: Array = Rules.walk_route(house)
	assert_int(path.size()).is_greater(1)
	# Sale de la acera (junto al Nucleo) y acaba en la carretera del edificio.
	assert_that(path[path.size() - 1]).is_equal(Vector2i(8, 11))

func test_roads_take_no_damage() -> void:
	_core_with_ring()
	var road: Node = GridManager.get_building_at(Vector2i(9, 9))
	assert_bool(BuildingHealth.is_immune(road)).is_true()
	var house := _put("house", Vector2i(7, 10))
	assert_bool(BuildingHealth.is_immune(house)).is_false()

func test_only_the_road_stays_1x1() -> void:
	var dir := DirAccess.open("res://data/buildings")
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var d: BuildingData = load("res://data/buildings/" + f)
		if d.id == "road":
			assert_that(d.grid_size).is_equal(Vector2i.ONE)
		else:
			assert_bool(d.grid_size.x >= 2 and d.grid_size.y >= 2).override_failure_message(
				"%s es de %s" % [d.id, d.grid_size]).is_true()
	assert_int(_data("road").cost_gold).is_equal(1)
