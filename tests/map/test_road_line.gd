extends GdUnitTestSuite
## Carretera larga (2026-10-19, feat/carretera-arrastrar): las reglas del tramo
## que se dibuja arrastrando, sin vista. PlacementRules.plan_road_line da el
## camino (recto, en L o el mas corto por celdas libres), que celdas hay que
## tender (desde la red hacia fuera, sin las que ya son carretera) y cuantas se
## pueden pagar.
##
## Toca GridManager (con nodos de mentira) y la bolsa de ResourceManager; cada
## caso las deja como estaban.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")

var _nodes: Array = []
var _resources: Dictionary = {}

func before_test() -> void:
	GridManager.clear_all()
	GridManager.reset_size()
	_nodes.clear()
	_resources = ResourceManager.get_all().duplicate()
	ResourceManager.set_amounts({"gold": 500, "wood": 0, "steel": 0, "oil": 0})

func after_test() -> void:
	GridManager.clear_all()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	var by_name := {}
	for type in _resources:
		by_name[ResourceManager.get_type_name(type)] = _resources[type]
	ResourceManager.set_amounts(by_name)

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

func _gold() -> int:
	return ResourceManager.get_amount(ResourceManager.Type.GOLD)

# ── El camino ─────────────────────────────────────────────────────────

func test_a_straight_line_has_every_cell_between_the_two_ends() -> void:
	var cells := Rules.road_line_cells(Vector2i(14, 11), Vector2i(20, 11))
	assert_int(cells.size()).is_equal(7)
	assert_that(cells[0]).is_equal(Vector2i(14, 11))
	assert_that(cells[6]).is_equal(Vector2i(20, 11))

func test_an_l_goes_along_the_longer_axis_first_and_flip_switches_the_corner() -> void:
	# 5 a lo ancho, 2 a lo alto: primero en horizontal, el codo en (19,11).
	var cells := Rules.road_line_cells(Vector2i(14, 11), Vector2i(19, 13))
	assert_int(cells.size()).is_equal(8)
	assert_bool(cells.has(Vector2i(19, 11))).is_true()
	assert_bool(cells.has(Vector2i(14, 13))).is_false()
	# Con el codo cambiado (R o ↻), primero en vertical: el codo en (14,13).
	var flipped := Rules.road_line_cells(Vector2i(14, 11), Vector2i(19, 13), true)
	assert_int(flipped.size()).is_equal(8)
	assert_bool(flipped.has(Vector2i(14, 13))).is_true()
	assert_bool(flipped.has(Vector2i(19, 11))).is_false()

func test_a_line_from_the_network_is_valid_and_costs_one_gold_a_tile() -> void:
	_core_with_ring()
	# De la acera (13,11) hacia la derecha hasta (20,11): 7 tramos nuevos.
	var plan := Rules.plan_road_line(Vector2i(13, 11), Vector2i(20, 11))
	assert_bool(bool(plan["ok"])).is_true()
	assert_int((plan["new"] as Array).size()).is_equal(7)
	assert_int(int(plan["affordable"])).is_equal(7)
	assert_str(Rules.road_line_label(plan)).is_equal(Tr.t("LBL_ROAD_LINE_COST") % [7, 7])

func test_cells_that_are_already_road_are_crossed_and_not_charged() -> void:
	_core_with_ring()
	# De (5,9) a (16,9): cruza la acera de arriba (x 9..13), que ya es carretera.
	var plan := Rules.plan_road_line(Vector2i(5, 9), Vector2i(16, 9))
	assert_bool(bool(plan["ok"])).is_true()
	assert_int((plan["cells"] as Array).size()).is_equal(12)
	assert_int((plan["new"] as Array).size()).is_equal(12 - 5)
	for c in plan["new"]:
		assert_bool(Rules.is_road_at(c)).is_false()

func test_the_new_tiles_go_from_the_network_outwards() -> void:
	_core_with_ring()
	# Se dibuja de fuera hacia la red: aun asi el primero en tenderse es el que
	# toca la acera, y cada uno toca al anterior (nunca queda un trozo suelto).
	var plan := Rules.plan_road_line(Vector2i(20, 11), Vector2i(14, 11))
	var new: Array = plan["new"]
	assert_that(new[0]).is_equal(Vector2i(14, 11))
	for i in range(1, new.size()):
		assert_int(absi((new[i] as Vector2i).x - (new[i - 1] as Vector2i).x)).is_equal(1)

func test_a_line_that_does_not_touch_the_network_is_refused() -> void:
	_core_with_ring()
	var plan := Rules.plan_road_line(Vector2i(20, 3), Vector2i(26, 3))
	assert_bool(bool(plan["ok"])).is_false()
	assert_str(String(plan["reason"])).is_equal("road")
	assert_str(Rules.road_line_label(plan)).is_equal(Tr.t("LBL_NEEDS_ROAD"))

func test_a_line_that_is_all_road_already_says_so() -> void:
	_core_with_ring()
	var plan := Rules.plan_road_line(Vector2i(9, 9), Vector2i(13, 9))
	assert_bool(bool(plan["ok"])).is_false()
	assert_str(String(plan["reason"])).is_equal("built")

func test_a_blocked_l_takes_the_other_corner() -> void:
	_core_with_ring()
	# Una casa en el codo horizontal (19..20, 11..12): la L va por el otro lado.
	_put("house", Vector2i(19, 11))
	var plan := Rules.plan_road_line(Vector2i(14, 11), Vector2i(19, 14))
	assert_bool(bool(plan["ok"])).is_true()
	assert_bool((plan["cells"] as Array).has(Vector2i(14, 14))).is_true()

func test_with_both_corners_blocked_it_goes_around_by_the_shortest_way() -> void:
	_core_with_ring()
	# Una casa justo en medio de una recta: rodea la casa.
	_put("house", Vector2i(17, 11))
	var plan := Rules.plan_road_line(Vector2i(14, 11), Vector2i(21, 11))
	assert_bool(bool(plan["ok"])).is_true()
	var cells: Array = plan["cells"]
	assert_bool(cells.has(Vector2i(17, 11))).is_false()
	assert_bool(cells.has(Vector2i(18, 11))).is_false()
	# 8 en recta + 1 de subir y 1 de bajar por encima de la casa.
	assert_int(cells.size()).is_equal(8 + 2)
	for i in range(1, cells.size()):
		assert_int(((cells[i] as Vector2i) - (cells[i - 1] as Vector2i)).length_squared()).is_equal(1)

func test_with_no_way_through_it_is_red() -> void:
	_core_with_ring()
	# El final dentro de una casa: no hay camino.
	_put("house", Vector2i(20, 11))
	var plan := Rules.plan_road_line(Vector2i(14, 11), Vector2i(20, 11))
	assert_bool(bool(plan["ok"])).is_false()
	assert_str(String(plan["reason"])).is_equal("occupied")
	assert_array(plan["cells"]).is_not_empty()

# ── El oro ────────────────────────────────────────────────────────────

func test_without_enough_gold_only_the_affordable_part_is_offered() -> void:
	_core_with_ring()
	ResourceManager.set_amounts({"gold": 3, "wood": 0, "steel": 0, "oil": 0})
	var plan := Rules.plan_road_line(Vector2i(13, 11), Vector2i(20, 11))
	assert_bool(bool(plan["ok"])).is_true()
	assert_int(int(plan["affordable"])).is_equal(3)
	assert_str(Rules.road_line_label(plan)).is_equal(Tr.t("LBL_ROAD_LINE_SHORT") % [3, 7])

func test_affordable_tiles_counts_whole_tiles() -> void:
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 0})
	assert_int(Rules.affordable_road_tiles(5)).is_equal(0)
	ResourceManager.set_amounts({"gold": 9, "wood": 0, "steel": 0, "oil": 0})
	assert_int(Rules.affordable_road_tiles(5)).is_equal(5)
	assert_int(Rules.affordable_road_tiles(20)).is_equal(9)

func test_the_result_text_says_how_many_were_laid() -> void:
	assert_str(Rules.road_line_result_text({"laid": 7, "wanted": 7, "reason": ""})).is_equal(Tr.t("LBL_ROAD_LINE_LAID") % 7)
	assert_str(Rules.road_line_result_text({"laid": 3, "wanted": 7, "reason": "gold"})).is_equal(Tr.t("LBL_ROAD_LINE_PARTIAL") % [3, 7])
	assert_str(Rules.road_line_result_text({"laid": 0, "wanted": 7, "reason": "gold"})).is_equal(Tr.t("LBL_ROAD_LINE_NO_GOLD"))

func test_the_texts_exist_in_both_languages() -> void:
	for key in ["LBL_ROAD_LINE_COST", "LBL_ROAD_LINE_SHORT", "LBL_ROAD_LINE_LAID", "LBL_ROAD_LINE_PARTIAL",
			"LBL_ROAD_LINE_NO_GOLD", "LBL_ROAD_LINE_BUILT", "LBL_ROAD_LINE_BLOCKED",
			"HELP_T_ROAD_DRAG", "HELP_B_ROAD_DRAG", "HELP_B_ROAD_DRAG_TOUCH"]:
		for loc in ["es", "en"]:
			assert_bool((Tr._STRINGS[loc] as Dictionary).has(key)).override_failure_message("%s/%s" % [loc, key]).is_true()
