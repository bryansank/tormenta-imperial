extends GdUnitTestSuite
## Extractor junto a su yacimiento (A2 + P1).
##
## Decision del dueno: el aserradero se levanta adyacente a un bosque, la mina
## a una veta y la fundicion a un yacimiento de hierro (alcance 1, diagonal
## incluida, sin pisarlo); la Refineria sigue solapando y consumiendo su pozo
## (alcance 0). La regla vive en GameConfig.building_deposit_rules, la
## distancia en MapGenerator.deposit_within_reach (pura) y el veredicto completo
## en BuildingPlacer.evaluate_placement, que usan por igual el fantasma, el
## clic y el MOVER. Aqui se fijan las tres capas.
##
## Toca el GridManager real: cada caso lo deja limpio.

const MapGen := preload("res://scripts/map/MapGenerator.gd")
const Placer := preload("res://scripts/buildings/BuildingPlacer.gd")

var _map: Node = null

func before_test() -> void:
	GridManager.clear_all()
	_map = auto_free(MapGen.new())
	add_child(_map)

func after_test() -> void:
	if is_instance_valid(_map):
		_map.clear_all_deposits()
	GridManager.clear_all()

func _cells(origin: Vector2i, size: Vector2i) -> Array:
	return GridManager.cells_for(origin, size)

# ── La distancia pura ────────────────────────────────────────────────

func test_a_touching_cell_is_within_reach_one() -> void:
	# Bosque en (10,10)-(11,11); edificio 2x1 en (12,10) lo toca por el lado.
	assert_bool(MapGen.deposit_within_reach(Vector2i(10, 10), Vector2i(2, 2), _cells(Vector2i(12, 10), Vector2i(2, 1)), 1)).is_true()

func test_two_cells_away_is_not_within_reach_one() -> void:
	assert_bool(MapGen.deposit_within_reach(Vector2i(10, 10), Vector2i(2, 2), _cells(Vector2i(13, 10), Vector2i(2, 1)), 1)).is_false()

func test_a_diagonal_touch_counts() -> void:
	# Esquina con esquina: (12,12) toca (11,11) en diagonal.
	assert_bool(MapGen.deposit_within_reach(Vector2i(10, 10), Vector2i(2, 2), [Vector2i(12, 12)], 1)).is_true()
	assert_bool(MapGen.deposit_within_reach(Vector2i(10, 10), Vector2i(2, 2), [Vector2i(13, 13)], 1)).is_false()

func test_reach_zero_means_overlap_only() -> void:
	# La Refineria: sobre el pozo si, al lado no.
	assert_bool(MapGen.deposit_within_reach(Vector2i(10, 10), Vector2i(2, 2), [Vector2i(11, 11)], 0)).is_true()
	assert_bool(MapGen.deposit_within_reach(Vector2i(10, 10), Vector2i(2, 2), [Vector2i(12, 10)], 0)).is_false()

func test_overlapping_is_also_within_reach_one() -> void:
	# La distancia no prohibe pisar el bosque: eso lo hace la ocupacion de la rejilla.
	assert_bool(MapGen.deposit_within_reach(Vector2i(10, 10), Vector2i(2, 2), [Vector2i(10, 10)], 1)).is_true()

func test_reach_works_on_wide_deposits() -> void:
	# Bosque 4x3 en (5,5): (9,8) toca la esquina inferior derecha (8,7).
	assert_bool(MapGen.deposit_within_reach(Vector2i(5, 5), Vector2i(4, 3), [Vector2i(9, 8)], 1)).is_true()
	assert_bool(MapGen.deposit_within_reach(Vector2i(5, 5), Vector2i(4, 3), [Vector2i(10, 8)], 1)).is_false()

# ── La regla en GameConfig ───────────────────────────────────────────

func test_the_three_extractors_need_an_adjacent_deposit() -> void:
	for pair in [["sawmill", "forest"], ["gold_mine", "gold_vein"], ["foundry", "iron_deposit"]]:
		var rule: Dictionary = GameConfig.get_deposit_rule(String(pair[0]))
		assert_str(String(rule["deposit"])).is_equal(String(pair[1]))
		assert_int(int(rule["reach"])).is_equal(1)
		assert_bool(bool(rule["consumes"])).is_false()

func test_the_refinery_still_sits_on_and_eats_its_well() -> void:
	var rule: Dictionary = GameConfig.get_deposit_rule("refinery")
	assert_str(String(rule["deposit"])).is_equal("oil_well")
	assert_int(int(rule["reach"])).is_equal(0)
	assert_bool(bool(rule["consumes"])).is_true()

func test_every_rule_has_a_translated_message_in_both_languages() -> void:
	for id in GameConfig.building_deposit_rules:
		var key := String(GameConfig.building_deposit_rules[id]["message"])
		for locale in ["es", "en"]:
			assert_bool(Tr._STRINGS[locale].has(key)).override_failure_message("%s missing in %s" % [key, locale]).is_true()

func test_a_building_without_a_rule_builds_anywhere() -> void:
	assert_bool(GameConfig.get_deposit_rule("house").is_empty()).is_true()
	assert_bool(Placer.evaluate_placement("house", Vector2i(3, 3), Vector2i(1, 1), _map)["ok"]).is_true()

# ── El veredicto completo (fantasma, clic y mover usan esta funcion) ──

func test_a_sawmill_next_to_a_forest_is_allowed() -> void:
	_map.spawn_deposit("forest", Vector2i(10, 10), -1, Vector2i(2, 2))
	var v: Dictionary = Placer.evaluate_placement("sawmill", Vector2i(12, 10), Vector2i(2, 1), _map)
	assert_bool(v["ok"]).is_true()
	assert_object(v["deposit"]).is_not_null()

func test_a_sawmill_two_cells_from_the_forest_is_refused_for_the_deposit() -> void:
	_map.spawn_deposit("forest", Vector2i(10, 10), -1, Vector2i(2, 2))
	var v: Dictionary = Placer.evaluate_placement("sawmill", Vector2i(13, 10), Vector2i(2, 1), _map)
	assert_bool(v["ok"]).is_false()
	assert_str(String(v["reason"])).is_equal("deposit")

func test_a_sawmill_on_the_diagonal_is_allowed() -> void:
	_map.spawn_deposit("forest", Vector2i(10, 10), -1, Vector2i(2, 2))
	assert_bool(Placer.evaluate_placement("sawmill", Vector2i(12, 12), Vector2i(2, 1), _map)["ok"]).is_true()

func test_a_sawmill_on_top_of_the_forest_is_refused_because_the_cells_are_taken() -> void:
	# Nadie construye encima de los arboles: alcance 1 no consume ni solapa.
	_map.spawn_deposit("forest", Vector2i(10, 10), -1, Vector2i(2, 2))
	var v: Dictionary = Placer.evaluate_placement("sawmill", Vector2i(10, 10), Vector2i(2, 1), _map)
	assert_bool(v["ok"]).is_false()
	assert_str(String(v["reason"])).is_equal("occupied")

func test_the_wrong_deposit_type_does_not_count() -> void:
	_map.spawn_deposit("gold_vein", Vector2i(10, 10), -1, Vector2i(2, 2))
	assert_bool(Placer.evaluate_placement("sawmill", Vector2i(12, 10), Vector2i(2, 1), _map)["ok"]).is_false()
	assert_bool(Placer.evaluate_placement("gold_mine", Vector2i(12, 10), Vector2i(2, 2), _map)["ok"]).is_true()

func test_the_refinery_must_overlap_its_well_and_the_well_cells_do_not_block_it() -> void:
	_map.spawn_deposit("oil_well", Vector2i(10, 10), -1, Vector2i(2, 2))
	# Solapando: valido aunque las celdas del pozo esten "ocupadas" (se consume).
	var on_top: Dictionary = Placer.evaluate_placement("refinery", Vector2i(10, 10), Vector2i(2, 2), _map)
	assert_bool(on_top["ok"]).is_true()
	assert_object(on_top["deposit"]).is_not_null()
	# Al lado: no.
	var beside: Dictionary = Placer.evaluate_placement("refinery", Vector2i(12, 10), Vector2i(2, 2), _map)
	assert_bool(beside["ok"]).is_false()
	assert_str(String(beside["reason"])).is_equal("deposit")

func test_moving_respects_the_same_rule() -> void:
	# Un aserradero ya colocado junto al bosque: moverlo lejos se rechaza, y
	# moverlo a otra celda que siga tocando el bosque se acepta aunque sus
	# celdas actuales cuenten como libres (ignore_building).
	_map.spawn_deposit("forest", Vector2i(10, 10), -1, Vector2i(2, 2))
	var data: BuildingData = load("res://data/buildings/sawmill.tres")
	var sawmill: Node3D = auto_free(Node3D.new())
	assert_bool(GridManager.place_building(Vector2i(12, 10), data, sawmill)).is_true()
	var far: Dictionary = Placer.evaluate_placement("sawmill", Vector2i(20, 20), data.grid_size, _map, sawmill)
	assert_bool(far["ok"]).is_false()
	assert_str(String(far["reason"])).is_equal("deposit")
	var still_adjacent: Dictionary = Placer.evaluate_placement("sawmill", Vector2i(12, 11), data.grid_size, _map, sawmill)
	assert_bool(still_adjacent["ok"]).is_true()

func test_without_a_map_generator_a_ruled_building_is_refused_not_crashed() -> void:
	assert_bool(Placer.evaluate_placement("sawmill", Vector2i(5, 5), Vector2i(2, 1), null)["ok"]).is_false()

# ── El buscador sobre yacimientos vivos ──────────────────────────────

func test_find_deposit_near_cells_and_the_reach_zero_wrapper_agree() -> void:
	var forest: Node3D = _map.spawn_deposit("forest", Vector2i(10, 10), -1, Vector2i(2, 2))
	assert_object(_map.find_deposit_near_cells("forest", [Vector2i(12, 11)], 1)).is_same(forest)
	assert_object(_map.find_deposit_near_cells("forest", [Vector2i(12, 11)], 0)).is_null()
	assert_object(_map.find_deposit_at_cells("forest", [Vector2i(11, 11)])).is_same(forest)

func test_a_removed_deposit_no_longer_satisfies_anyone() -> void:
	var well: Node3D = _map.spawn_deposit("oil_well", Vector2i(10, 10), -1, Vector2i(2, 2))
	_map.remove_deposit(well)
	assert_bool(Placer.evaluate_placement("refinery", Vector2i(10, 10), Vector2i(2, 2), _map)["ok"]).is_false()
