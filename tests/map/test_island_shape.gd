extends GdUnitTestSuite
## Isla irregular (2026-10-12): la mascara de tierra de IslandShape y lo que la
## respeta. La forma sale de la semilla (misma semilla, misma isla), es una
## sola masa sin lagos, el Nucleo y su acera siempre en tierra, el borde de la
## rejilla siempre mar, y la tierra en el rango de GameConfig. El agua no se
## construye ni se pavimenta. Una partida guardada sin "shape" sigue siendo la
## isla cuadrada de antes, toda tierra.

const Shape := preload("res://scripts/map/IslandShape.gd")
const MapGen := preload("res://scripts/map/MapGenerator.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")

## Diez islas: (ancho, alto, semilla).
const CASES := [
	[60, 60, 1], [74, 60, 7], [60, 74, 42], [66, 68, 99], [70, 62, 314],
	[62, 70, 2718], [72, 72, 4242], [64, 60, 9001], [68, 74, 12345], [60, 66, 55555],
]

func before_test() -> void:
	GridManager.clear_all()
	GridManager.reset_size()

func after_test() -> void:
	GridManager.clear_all()
	GridManager.reset_size()

func _mask(c: Array) -> PackedByteArray:
	return Shape.build_mask(int(c[0]), int(c[1]), int(c[2]), GameConfig.island_coast)

# ── La mascara ────────────────────────────────────────────────────────

func test_the_same_seed_gives_the_same_island() -> void:
	var a := Shape.build_mask(64, 60, 777, GameConfig.island_coast)
	var b := Shape.build_mask(64, 60, 777, GameConfig.island_coast)
	assert_bool(a == b).is_true()

func test_different_seeds_give_different_islands() -> void:
	var a := Shape.build_mask(64, 60, 1, GameConfig.island_coast)
	var b := Shape.build_mask(64, 60, 2, GameConfig.island_coast)
	assert_bool(a == b).is_false()

func test_the_mask_does_not_touch_the_global_rng() -> void:
	seed(123)
	var expected := randi()
	seed(123)
	Shape.build_mask(64, 60, 5, GameConfig.island_coast)
	assert_int(randi()).is_equal(expected)

func test_every_island_is_one_piece_without_lakes() -> void:
	for c in CASES:
		var m := _mask(c)
		assert_int(Shape.land_components(m, c[0], c[1])).override_failure_message(
			"isla %s: mas de una masa" % [c]).is_equal(1)
		assert_int(Shape.lake_cells(m, c[0], c[1])).override_failure_message(
			"isla %s: lagos interiores" % [c]).is_equal(0)

func test_the_core_and_its_sidewalk_are_always_land() -> void:
	for c in CASES:
		var m := _mask(c)
		var keep: Rect2i = Shape.core_keep_rect(c[0], c[1], GameConfig.island_coast)
		for y in range(keep.position.y, keep.end.y):
			for x in range(keep.position.x, keep.end.x):
				assert_bool(Shape.is_land(m, c[0], c[1], Vector2i(x, y))).override_failure_message(
					"isla %s: (%d,%d) junto al Nucleo es agua" % [c, x, y]).is_true()

func test_the_edge_of_the_grid_is_sea() -> void:
	var edge: int = int(GameConfig.island_coast["edge_water"])
	for c in CASES:
		var m := _mask(c)
		var w: int = c[0]
		var h: int = c[1]
		for y in range(h):
			for x in range(w):
				if x < edge or y < edge or x >= w - edge or y >= h - edge:
					assert_bool(Shape.is_land(m, w, h, Vector2i(x, y))).is_false()

func test_the_land_area_is_in_range() -> void:
	var lo: int = int(GameConfig.island_coast["land_min"])
	var hi: int = int(GameConfig.island_coast["land_max"])
	for c in CASES:
		var n := Shape.count_land(_mask(c))
		var target := Shape.target_land(c[0], c[1], c[2], GameConfig.island_coast)
		# El objetivo, con un 3 % de holgura (la limpieza mueve algo el area).
		assert_int(n).override_failure_message("isla %s: %d celdas de tierra" % [c, n]) \
			.is_between(int(lo * 0.97), int(hi * 1.03))
		assert_int(absi(n - target)).is_less_equal(maxi(8, int(target * 0.03)))

func test_the_island_is_not_a_square_any_more() -> void:
	# Al menos una cuarta parte de la rejilla util es mar: hay bahias.
	var edge: int = int(GameConfig.island_coast["edge_water"])
	for c in CASES:
		var usable: int = (int(c[0]) - 2 * edge) * (int(c[1]) - 2 * edge)
		assert_float(float(Shape.count_land(_mask(c))) / usable).is_less(0.75)

func test_every_land_cell_fits_in_a_block_of_land() -> void:
	# Sin lenguas de una celda: toda celda de tierra esta en un 2x2 de tierra.
	for c in CASES:
		var m := _mask(c)
		var w: int = c[0]
		var h: int = c[1]
		for y in range(h):
			for x in range(w):
				if not Shape.is_land(m, w, h, Vector2i(x, y)):
					continue
				var ok := false
				for o in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
					var base: Vector2i = Vector2i(x, y) + o
					if Shape.is_land(m, w, h, base) and Shape.is_land(m, w, h, base + Vector2i(1, 0)) \
							and Shape.is_land(m, w, h, base + Vector2i(0, 1)) and Shape.is_land(m, w, h, base + Vector2i(1, 1)):
						ok = true
						break
				if not ok:
					fail("isla %s: (%d,%d) es una lengua suelta" % [c, x, y])
					return

func test_the_square_version_is_all_land() -> void:
	var m := Shape.build_mask(40, 40, 1234, {}, Shape.SQUARE)
	assert_int(Shape.count_land(m)).is_equal(1600)
	assert_int(Shape.count_land(Shape.build_mask(40, 40, -1, {}))).is_equal(1600)

func test_game_config_and_the_defaults_match() -> void:
	# IslandShape.DEFAULTS es lo que usa un guardado con parametros viejos.
	assert_that(Shape.with_defaults(GameConfig.island_coast)).is_equal(Shape.with_defaults(Shape.DEFAULTS))
	assert_array(GameConfig.island_coast.keys()).contains_exactly_in_any_order(Shape.DEFAULTS.keys())

# ── La costa ──────────────────────────────────────────────────────────

func test_the_coast_is_closed_counter_clockwise_and_triangulates() -> void:
	for c in CASES.slice(0, 4):
		var m := _mask(c)
		var poly := Shape.coast_polygon(m, c[0], c[1], 2.0, Vector2(-c[0], -c[1]))
		assert_int(poly.size()).is_greater(100)
		assert_float(Shape.signed_area(poly)).is_greater(0.0)
		assert_int(Geometry2D.triangulate_polygon(poly).size()).is_greater(0)

func test_water_under_the_grass_is_only_next_to_land() -> void:
	# La hierba asoma como mucho una celda por fuera de la tierra.
	for c in CASES.slice(0, 3):
		var m := _mask(c)
		var w: int = c[0]
		var h: int = c[1]
		var poly := Shape.coast_polygon(m, w, h, 1.0, Vector2.ZERO)
		for y in range(h):
			for x in range(w):
				if Shape.is_land(m, w, h, Vector2i(x, y)):
					continue
				if not Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
					continue
				var near := false
				for d in Shape.N8:
					if Shape.is_land(m, w, h, Vector2i(x, y) + d):
						near = true
				assert_bool(near).override_failure_message(
					"isla %s: agua (%d,%d) bajo la hierba lejos de la tierra" % [c, x, y]).is_true()

# ── GridManager ───────────────────────────────────────────────────────

func test_a_new_map_is_irregular_and_reloads_identical() -> void:
	seed(4242)
	GridManager.roll_new_map()
	assert_bool(GridManager.is_irregular()).is_true()
	var mask := GridManager.get_land_mask()
	var data: Dictionary = GridManager.get_save_data()
	assert_int(int(data["shape"])).is_equal(Shape.IRREGULAR)
	GridManager.reset_size()
	assert_bool(GridManager.is_irregular()).is_false()
	# Como llega del JSON: los numeros vuelven como float.
	GridManager.load_save_data(JSON.parse_string(JSON.stringify(data)))
	assert_bool(GridManager.get_land_mask() == mask).is_true()
	# Cargar dos veces no cambia nada.
	GridManager.load_save_data(data)
	assert_bool(GridManager.get_land_mask() == mask).is_true()

func test_the_saved_coast_wins_over_game_config() -> void:
	# Retocar la costa en GameConfig no mueve la de una partida guardada.
	seed(77)
	GridManager.roll_new_map()
	var mask := GridManager.get_land_mask()
	var data: Dictionary = JSON.parse_string(JSON.stringify(GridManager.get_save_data()))
	var old: float = GameConfig.island_coast["noise_amp"]
	GameConfig.island_coast["noise_amp"] = 0.01
	GridManager.reset_size()
	GridManager.load_save_data(data)
	GameConfig.island_coast["noise_amp"] = old
	assert_bool(GridManager.get_land_mask() == mask).is_true()

func test_a_save_without_shape_is_the_old_square_island() -> void:
	GridManager.load_save_data({"width": 46, "height": 42, "island_seed": 1234})
	assert_bool(GridManager.is_irregular()).is_false()
	assert_int(GridManager.land_cell_count()).is_equal(46 * 42)
	assert_bool(GridManager.is_land_cell(Vector2i(0, 0))).is_true()
	assert_bool(GridManager.is_land_cell(Vector2i(45, 41))).is_true()
	assert_that(GridManager.land_bounds()).is_equal(Rect2i(0, 0, 46, 42))
	assert_bool(GridManager.get_land_mask().is_empty()).is_true()

func test_the_camera_bounds_are_the_land() -> void:
	seed(9)
	GridManager.roll_new_map()
	var land: Rect2 = GridManager.land_world_rect()
	var grid := Rect2(Vector2(GridManager.get_origin().x, GridManager.get_origin().z), GridManager.get_world_size())
	assert_bool(grid.encloses(land)).is_true()
	assert_bool(land.size.x < grid.size.x and land.size.y < grid.size.y).is_true()

# ── El agua no se construye ───────────────────────────────────────────

## Una celda de mar dentro de la rejilla: el borde (edge_water) siempre lo es.
func _a_water_cell() -> Vector2i:
	return Vector2i(1, 1)

func test_water_is_never_free_nor_placeable() -> void:
	seed(31)
	GridManager.roll_new_map()
	var water := Vector2i(0, 0)
	assert_bool(GridManager.is_water_cell(water)).is_true()
	assert_bool(GridManager.is_cell_free(water)).is_false()
	assert_bool(GridManager.can_place(water, Vector2i(2, 2))).is_false()
	var node: Node = auto_free(Node.new())
	assert_bool(GridManager.place_obstacle(water, node)).is_false()

func test_placing_on_water_says_water() -> void:
	seed(31)
	GridManager.roll_new_map()
	for id in ["house", "road"]:
		var v: Dictionary = Rules.evaluate_placement(id, _a_water_cell(), Vector2i(2, 2) if id == "house" else Vector2i.ONE, null)
		assert_bool(v["ok"]).is_false()
		assert_str(String(v["reason"])).is_equal("water")
	assert_str(Tr.t("LBL_ON_WATER")).is_not_equal("LBL_ON_WATER")

func test_a_road_route_never_crosses_water() -> void:
	seed(31)
	GridManager.roll_new_map()
	var core := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	var nucleo: Node = auto_free(Node.new())
	GridManager.place_building(core, load("res://data/buildings/nucleo.tres"), nucleo)
	# Un hueco de tierra lejos del Nucleo, junto a la costa.
	var b := GridManager.land_bounds()
	var target := Vector2i(-1, -1)
	for x in range(b.position.x, b.end.x):
		var c := Vector2i(x, core.y)
		if GridManager.can_place(c, Vector2i(2, 2)):
			target = c
			break
	assert_that(target).is_not_equal(Vector2i(-1, -1))
	var route: Variant = Rules.road_route(target, Vector2i(2, 2))
	assert_object(route).is_not_null()
	for c in route:
		assert_bool(GridManager.is_land_cell(c)).is_true()

func test_shore_cells_follow_the_coast() -> void:
	seed(31)
	GridManager.roll_new_map()
	var shore: Array = MapGen.shore_cells()
	assert_int(shore.size()).is_greater(50)
	for c in shore:
		assert_bool(GridManager.is_land_cell(c)).is_true()
	assert_bool(MapGen.is_sea_cell(Vector2i(0, 0))).is_true()
	var core := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	assert_bool(MapGen.is_shore_cell(core)).is_false()
