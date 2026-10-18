extends GdUnitTestSuite
## Bancos de peces (feat/muelle-pesca): el primer yacimiento de mar. Viven en
## celdas de agua de la rejilla pegadas a la tierra, entre
## GameConfig.sea_deposit_rolls["fish_shoal"].min y max por isla, con su propio
## azar (semilla de la isla), cada uno con hueco en la orilla para un Muelle de
## pesca y camino a la red. No se agotan. Una partida vieja los recibe al cargar
## (MapGenerator.ensure_shore_deposits).
##
## Escrita sin correr (regla de Bryan: un solo pase de pruebas al final).
## Toca el GridManager real: cada caso lo deja limpio.

const MapGen := preload("res://scripts/map/MapGenerator.gd")
const DepositMesh := preload("res://scripts/map/DepositMesh.gd")
const SEEDS := [1, 7, 42, 99, 314, 2718, 4242, 9001]
const SHOAL := "fish_shoal"

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

func _shoals() -> Array:
	return _map.get_all_deposits().filter(func(d): return String(d["id"]) == SHOAL)

func _cells_of(d: Dictionary) -> Array:
	return GridManager.cells_for(Vector2i(d["cell_x"], d["cell_y"]), Vector2i(d["size_x"], d["size_y"]))

# ── Cuantos y donde ───────────────────────────────────────────────────

func test_every_island_brings_its_schools_of_fish() -> void:
	var roll: Dictionary = GameConfig.sea_deposit_rolls[SHOAL]
	for s in SEEDS:
		_new_map(s)
		assert_int(_shoals().size()).override_failure_message("semilla %d: %d bancos" % [s, _shoals().size()]) \
			.is_between(int(roll["min"]), int(roll["max"]))

func test_a_school_is_all_water_and_touches_the_land() -> void:
	for s in SEEDS:
		_new_map(s)
		for d in _shoals():
			var touches := false
			for c in _cells_of(d):
				assert_bool(GridManager.is_water_cell(c)).override_failure_message(
					"semilla %d: banco en tierra (%s)" % [s, c]).is_true()
				for dx in [-1, 0, 1]:
					for dy in [-1, 0, 1]:
						if GridManager.is_land_cell(c + Vector2i(dx, dy)):
							touches = true
			assert_bool(touches).override_failure_message("semilla %d: banco lejos de la costa" % s).is_true()

func test_schools_keep_their_distance() -> void:
	var gap: int = int(GameConfig.sea_deposit_rolls[SHOAL]["spacing"])
	for s in SEEDS:
		_new_map(s)
		var list := _shoals()
		for i in list.size():
			for j in range(i + 1, list.size()):
				var a := Rect2i(Vector2i(list[i]["cell_x"], list[i]["cell_y"]), Vector2i(list[i]["size_x"], list[i]["size_y"]))
				var b := Rect2i(Vector2i(list[j]["cell_x"], list[j]["cell_y"]), Vector2i(list[j]["size_x"], list[j]["size_y"]))
				assert_bool(a.grow(gap).intersects(b)).override_failure_message("semilla %d: dos bancos pegados" % s).is_false()

func test_every_school_leaves_room_for_a_dock_and_a_road() -> void:
	for s in SEEDS:
		_new_map(s)
		assert_bool(_map.all_deposits_workable()).override_failure_message("semilla %d" % s).is_true()
		assert_bool(_map.has_buildable_spot_near(SHOAL, Vector2i(2, 2), 1)).override_failure_message("semilla %d" % s).is_true()

func test_the_same_seed_gives_the_same_schools() -> void:
	_new_map(4242)
	var first := _shoals()
	_new_map(4242)
	assert_array(_shoals()).is_equal(first)

func test_the_schools_do_not_move_the_land_deposits() -> void:
	# Su azar es propio: sortearlos no gasta el global, asi que los de tierra
	# (que van antes) y todo lo que venga despues salen como sin ellos.
	_new_map(314)
	for d in _shoals():
		_map.remove_deposit(GridManager.get_building_at(Vector2i(d["cell_x"], d["cell_y"])))
	seed(777)
	_map.ensure_shore_deposits()
	var after := randi()
	seed(777)
	assert_int(randi()).is_equal(after)
	assert_bool(_shoals().is_empty()).is_false()

# ── En la rejilla ─────────────────────────────────────────────────────

func test_a_school_is_on_the_grid_but_nothing_builds_on_it() -> void:
	_new_map(42)
	var list := _shoals()
	assert_bool(list.is_empty()).is_false()
	var c: Vector2i = _cells_of(list[0])[0]
	var node: Node = GridManager.get_building_at(c)
	assert_object(node).is_not_null()
	assert_str(String(node.get_meta("deposit_id", ""))).is_equal(SHOAL)
	assert_bool(GridManager.is_cell_free(c)).is_false()

func test_sea_obstacles_refuse_land() -> void:
	_new_map(42)
	var core: Vector2i = _map.core_origin() + Vector2i(5, 0)
	assert_bool(GridManager.is_land_cell(core)).is_true()
	var probe: Node = auto_free(Node3D.new())
	assert_bool(GridManager.place_sea_obstacle(core, probe, Vector2i(1, 1))).is_false()

func test_it_never_runs_out() -> void:
	assert_bool(GameConfig.is_endless_deposit(SHOAL)).is_true()
	# Sin minado a mano: nada gasta sus usos.
	assert_bool(GameConfig.mining_data.has(SHOAL)).is_false()
	assert_bool(GameConfig.is_deposit_unlocked(SHOAL)).is_true()

# ── Partidas viejas ───────────────────────────────────────────────────

func test_an_old_game_gets_the_same_schools_on_load() -> void:
	_new_map(9001)
	var first := _shoals()
	for d in first:
		var node: Node = GridManager.get_building_at(Vector2i(d["cell_x"], d["cell_y"]))
		_map.remove_deposit(node)
	assert_array(_shoals()).is_empty()
	_map.ensure_shore_deposits()
	assert_array(_shoals()).is_equal(first)
	# Con bancos ya puestos, no anade ninguno.
	_map.ensure_shore_deposits()
	assert_int(_shoals().size()).is_equal(first.size())

func test_a_square_island_has_no_sea_inside_and_no_schools() -> void:
	# La rejilla de antes (sin semilla de isla): toda tierra, el mar fuera.
	GridManager.reset_size()
	assert_bool(GridManager.is_irregular()).is_false()
	GridManager.place_obstacle(_map.core_origin(), _nucleo, Vector2i(3, 3))
	_map.ensure_shore_deposits()
	assert_array(_shoals()).is_empty()

# ── Aspecto ───────────────────────────────────────────────────────────

func test_the_3d_school_floats_on_the_sea_and_is_cheap() -> void:
	var m: ArrayMesh = DepositMesh.build(SHOAL, Vector2i(2, 2), 3)
	assert_object(m).is_not_null()
	var a := m.get_aabb()
	# Todo a la altura del mar (y < 0), salvo la boya y el pez que salta.
	assert_float(a.position.y).is_less(0.0)
	assert_float(a.end.y).is_less(0.6)
	assert_float(a.size.x).is_less_equal(4.0)
	var tris := 0
	for s in m.get_surface_count():
		tris += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	assert_int(tris).is_less_equal(600)
	# Compartida por tamano y variante, como las de tierra.
	assert_object(DepositMesh.mesh_for(SHOAL, Vector2i(2, 2), 3)).is_same(DepositMesh.mesh_for(SHOAL, Vector2i(2, 2), 3))

func test_texts_exist_in_both_languages() -> void:
	var before := Tr.get_locale()
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for key in ["DEP_FISH_SHOAL", "DEP_SHORT_FISH_SHOAL", "DEP_HINT_FISH_SHOAL", "LBL_DEPOSIT_ENDLESS"]:
			assert_str(Tr.t(key)).override_failure_message(key).is_not_equal(key)
	Tr.set_locale(before)

# ── La arena no los tapa (ronda visual de la 1.1) ─────────────────────

func test_each_school_opens_a_hole_in_the_3d_sand() -> void:
	# La playa 3D baja del cesped por encima de la primera franja de agua, justo
	# donde viven los bancos: la isla abre un hueco en la arena sobre cada uno.
	_new_map(SEEDS[0])
	var rects: Array = _map.sea_deposit_rects()
	assert_int(rects.size()).is_equal(_shoals().size())
	for i in rects.size():
		var d: Dictionary = _shoals()[i]
		var r: Vector4 = rects[i]
		var c := GridManager.building_center(Vector2i(d["cell_x"], d["cell_y"]), Vector2i(d["size_x"], d["size_y"]))
		assert_vector(Vector2(r.x, r.y)).is_equal_approx(Vector2(c.x, c.z), Vector2(0.001, 0.001))
		assert_float(r.z).is_equal_approx(float(d["size_x"]) * GridManager.cell_size * 0.5, 0.001)
	var island: Node3D = auto_free(load("res://scripts/map/IslandGenerator.gd").new())
	island.set_sand_holes(rects)
	assert_int(island.get_sand_holes().size()).is_equal(rects.size())
	# Nunca mas de los que caben en el shader.
	var many: Array = []
	for i in 12:
		many.append(Vector4(i, 0, 1, 1))
	island.set_sand_holes(many)
	assert_int(island.get_sand_holes().size()).is_equal(island.MAX_SAND_HOLES)
