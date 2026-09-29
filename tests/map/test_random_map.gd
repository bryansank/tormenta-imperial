extends GdUnitTestSuite
## Mapa aleatorio (2026-09-28): cada partida sortea el tamano de la rejilla
## (GameConfig.grid_size_min..max, lados pares), la forma de la isla
## (GridManager.island_seed) y, para CADA tipo de yacimiento, cuantos trae
## (GameConfig.deposit_per_type_min..max). Ningun yacimiento pisa el Nucleo ni su
## acera, ninguno cae en la franja de costa, y todos dejan hueco a su extractor
## con camino hasta la red.
##
## La parte de guardar y cargar con GameManager de verdad esta en
## tests/modes/test_game_mode_save.gd (ya monta la colonia y aparta el save).

const MapGen := preload("res://scripts/map/MapGenerator.gd")
const IslandGen := preload("res://scripts/map/IslandGenerator.gd")
const SEEDS := [1, 7, 42, 99, 314, 2718, 4242, 9001, 12345, 55555]

var _map: Node = null
var _nucleo: Node3D = null

func before_test() -> void:
	GridManager.clear_all()
	GridManager.reset_size()
	_map = auto_free(MapGen.new())
	add_child(_map)
	_nucleo = auto_free(Node3D.new())

func after_test() -> void:
	if is_instance_valid(_map):
		_map.clear_all_deposits()
	GridManager.clear_all()
	GridManager.reset_size()

## Una isla como la de _new_game(): tamano sorteado, Nucleo en el centro y mapa.
func _new_map(map_seed: int) -> void:
	_map.clear_all_deposits()
	GridManager.clear_all()
	seed(map_seed)
	GridManager.roll_new_map()
	GridManager.place_obstacle(_map.core_origin(), _nucleo, Vector2i(3, 3))
	_map.generate_new_map()

func _count(deposit_id: String) -> int:
	var n := 0
	for d in _map.get_all_deposits():
		if d["id"] == deposit_id:
			n += 1
	return n

# ── Vetas ─────────────────────────────────────────────────────────────

func test_every_type_brings_between_three_and_six() -> void:
	for s in SEEDS:
		_new_map(s)
		for deposit_id in MapGen.DEPOSIT_IDS:
			assert_int(_count(deposit_id)).override_failure_message(
				"semilla %d: %d de %s" % [s, _count(deposit_id), deposit_id]
			).is_between(GameConfig.deposit_per_type_min, GameConfig.deposit_per_type_max)

func test_the_counts_change_between_games() -> void:
	# Con diez semillas no puede salir diez veces el mismo reparto.
	var seen := {}
	for s in SEEDS:
		_new_map(s)
		var key := ""
		for deposit_id in MapGen.DEPOSIT_IDS:
			key += "%d," % _count(deposit_id)
		seen[key] = true
	assert_int(seen.size()).is_greater(1)

func test_the_same_seed_gives_the_same_map() -> void:
	_new_map(4242)
	var first: Array = _map.get_all_deposits()
	var size := Vector2i(GridManager.grid_width, GridManager.grid_height)
	_new_map(4242)
	assert_array(_map.get_all_deposits()).is_equal(first)
	assert_that(Vector2i(GridManager.grid_width, GridManager.grid_height)).is_equal(size)

func test_no_deposit_touches_the_core_or_its_sidewalk() -> void:
	for s in SEEDS:
		_new_map(s)
		var keep_out: Rect2i = _map.core_ring_rect().grow(GameConfig.deposit_core_gap)
		for d in _map.get_all_deposits():
			var r := Rect2i(Vector2i(d["cell_x"], d["cell_y"]), Vector2i(d["size_x"], d["size_y"]))
			assert_bool(keep_out.intersects(r)).override_failure_message(
				"semilla %d: %s en %s pisa el Nucleo o su acera" % [s, d["id"], r]).is_false()

func test_no_land_deposit_sits_on_the_shore_band() -> void:
	for s in SEEDS:
		_new_map(s)
		for d in _map.get_all_deposits():
			for c in GridManager.cells_for(Vector2i(d["cell_x"], d["cell_y"]), Vector2i(d["size_x"], d["size_y"])):
				assert_bool(MapGen.is_shore_cell(c)).override_failure_message(
					"semilla %d: %s en la costa (%s)" % [s, d["id"], c]).is_false()

func test_every_deposit_leaves_room_for_its_extractor_and_a_road() -> void:
	for s in SEEDS:
		_new_map(s)
		assert_bool(_map.all_deposits_workable()).override_failure_message(
			"semilla %d: algun yacimiento sin hueco o sin camino a la red" % s).is_true()
		assert_bool(_map.has_buildable_spot_near("forest", Vector2i(2, 2), 1)).is_true()
		assert_bool(_map.has_buildable_spot_near("gold_vein", Vector2i(2, 2), 1)).is_true()
		assert_bool(_map.has_buildable_spot_near("iron_deposit", Vector2i(2, 2), 1)).is_true()

func test_a_boxed_in_deposit_is_not_workable() -> void:
	# Un bosque rodeado por completo: sin hueco para el aserradero.
	_map.spawn_deposit("forest", Vector2i(5, 5), -1, Vector2i(2, 2))
	for x in range(1, 11):
		for y in range(1, 11):
			var c := Vector2i(x, y)
			if GridManager.is_cell_free(c):
				GridManager.place_obstacle(c, _nucleo)
	assert_bool(_map.all_deposits_workable()).is_false()

# ── Costa y mar ───────────────────────────────────────────────────────

func test_shore_cells_are_the_outer_band() -> void:
	var band: int = GameConfig.map_shore_band
	var w := GridManager.grid_width
	var h := GridManager.grid_height
	var expected: int = w * h - maxi(w - 2 * band, 0) * maxi(h - 2 * band, 0)
	assert_int(MapGen.shore_cells().size()).is_equal(expected)
	assert_bool(MapGen.is_shore_cell(Vector2i(0, 0))).is_true()
	assert_bool(MapGen.is_shore_cell(Vector2i(w - 1, h / 2))).is_true()
	assert_bool(MapGen.is_shore_cell(Vector2i(w / 2, h / 2))).is_false()

func test_outside_the_grid_is_sea() -> void:
	assert_bool(MapGen.is_sea_cell(Vector2i(-1, 0))).is_true()
	assert_bool(MapGen.is_sea_cell(Vector2i(GridManager.grid_width, 3))).is_true()
	assert_bool(MapGen.is_sea_cell(Vector2i(0, 0))).is_false()
	assert_bool(MapGen.is_shore_cell(Vector2i(-1, 0))).is_false()

# ── Tamano de la rejilla ──────────────────────────────────────────────

func test_the_grid_size_is_in_range_and_even() -> void:
	var sizes := {}
	for s in SEEDS:
		seed(s)
		GridManager.roll_new_map()
		for side in [GridManager.grid_width, GridManager.grid_height]:
			assert_int(side).is_between(GameConfig.grid_size_min, GameConfig.grid_size_max)
			assert_int(side % 2).is_equal(0)
		sizes[Vector2i(GridManager.grid_width, GridManager.grid_height)] = true
	assert_int(sizes.size()).is_greater(1)

func test_the_grid_stays_centred_on_the_world() -> void:
	GridManager.set_grid_size(46, 42)
	var o: Vector3 = GridManager.get_origin()
	var size: Vector2 = GridManager.get_world_size()
	assert_float(o.x + size.x * 0.5).is_equal_approx(0.0, 0.001)
	assert_float(o.z + size.y * 0.5).is_equal_approx(0.0, 0.001)
	assert_that(GridManager.world_to_cell(Vector3(-46.0 + 0.1, 0, -42.0 + 0.1))).is_equal(Vector2i(0, 0))
	assert_that(GridManager.world_to_cell(Vector3(45.9, 0, 41.9))).is_equal(Vector2i(45, 41))

func test_the_size_survives_its_save_data() -> void:
	seed(9001)
	GridManager.roll_new_map()
	var data: Dictionary = GridManager.get_save_data()
	var size := Vector2i(GridManager.grid_width, GridManager.grid_height)
	var island: int = GridManager.island_seed
	GridManager.reset_size()
	# Como llega del JSON: los numeros vuelven como float.
	GridManager.load_save_data(JSON.parse_string(JSON.stringify(data)))
	assert_that(Vector2i(GridManager.grid_width, GridManager.grid_height)).is_equal(size)
	assert_int(GridManager.island_seed).is_equal(island)
	# Cargar dos veces no cambia nada.
	GridManager.load_save_data(data)
	assert_that(Vector2i(GridManager.grid_width, GridManager.grid_height)).is_equal(size)

func test_a_save_without_the_key_is_forty_by_forty() -> void:
	GridManager.set_grid_size(48, 44)
	GridManager.load_save_data({})
	assert_int(GridManager.grid_width).is_equal(40)
	assert_int(GridManager.grid_height).is_equal(40)
	assert_that(GridManager.get_origin()).is_equal(Vector3(-40.0, 0.0, -40.0))
	assert_int(GridManager.island_seed).is_equal(-1)

func test_resizing_announces_it_once() -> void:
	var calls: Array = []
	var cb := func(w: int, h: int): calls.append(Vector2i(w, h))
	EventBus.grid_resized.connect(cb)
	GridManager.set_grid_size(44, 44)
	GridManager.set_grid_size(44, 44)
	EventBus.grid_resized.disconnect(cb)
	assert_array(calls).is_equal([Vector2i(44, 44)])

# ── La isla cubre cualquier rejilla, con cualquier forma ──────────────

func test_every_rolled_island_covers_its_grid() -> void:
	for s in SEEDS:
		seed(s)
		GridManager.roll_new_map()
		var shape: Dictionary = IslandGen.shape_for_seed(GridManager.island_seed)
		var half: Vector2 = IslandGen.grid_half_extents()
		var wobble: Array = IslandGen.make_wobble(IslandGen.SEGMENTS, shape["seed_val"], shape["amplitude"], shape["detail"])
		var poly := IslandGen.border_points(half.x, half.y, shape["margin"], shape["radius"], wobble)
		var o: Vector3 = GridManager.get_origin()
		var cs: float = GridManager.cell_size
		for x in range(GridManager.grid_width + 1):
			for y in range(GridManager.grid_height + 1):
				var corner := Vector2(o.x + x * cs, o.z + y * cs)
				if not Geometry2D.is_point_in_polygon(corner, poly):
					fail("semilla %d (%dx%d): esquina %s en el agua" % [s, GridManager.grid_width, GridManager.grid_height, corner])
					return

func test_island_shapes_differ_between_seeds() -> void:
	var a: Dictionary = IslandGen.shape_for_seed(1)
	var b: Dictionary = IslandGen.shape_for_seed(2)
	assert_bool(a == b).is_false()
	assert_that(IslandGen.shape_for_seed(1)).is_equal(a)

func test_wobble_detail_keeps_the_wobble_in_range() -> void:
	for detail in [0.5, 1.0, 2.0]:
		for w in IslandGen.make_wobble(128, 12.3, 3.0, detail):
			assert_float(float(w)).is_between(0.0, 3.0)
