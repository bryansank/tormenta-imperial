extends GdUnitTestSuite
## La isla llena la rejilla (P2, A1).
##
## Antes la isla era una superelipse inscrita en el cuadrado de la rejilla: las
## esquinas eran agua y can_place() no lo sabia, asi que se construia en el mar.
## La decision del dueno fue que la isla crezca hasta cubrir las 40x40 celdas.
## Estos casos fijan la geometria: cada esquina de cada celda queda dentro del
## poligono de hierba, con cualquier semilla de ondulacion.

const IslandGen := preload("res://scripts/map/IslandGenerator.gd")

func _grass(seed_val: float, margin: float = 3.0, radius: float = 8.0, amplitude: float = 2.0) -> PackedVector2Array:
	var half: Vector2 = IslandGen.grid_half_extents()
	var wobble: Array = IslandGen.make_wobble(IslandGen.SEGMENTS, seed_val, amplitude)
	return IslandGen.border_points(half.x, half.y, margin, radius, wobble)

## Todas las esquinas de celda de la rejilla, en coordenadas de mundo (XZ).
func _cell_corners() -> Array:
	var out: Array = []
	var origin: Vector3 = GridManager.get_origin()
	for x in range(GridManager.grid_width + 1):
		for y in range(GridManager.grid_height + 1):
			out.append(Vector2(origin.x + x * GridManager.cell_size, origin.z + y * GridManager.cell_size))
	return out

# ── Cobertura ────────────────────────────────────────────────────────

func test_every_cell_corner_is_on_grass() -> void:
	# Varias semillas: la ondulacion no puede meter el borde dentro de la rejilla.
	for seed_val in [0.0, 13.7, 42.0, 77.7, 99.9]:
		var poly := _grass(seed_val)
		for corner in _cell_corners():
			assert_bool(Geometry2D.is_point_in_polygon(corner, poly)) \
				.override_failure_message("corner %s outside grass (seed %s)" % [corner, seed_val]) \
				.is_true()

func test_the_grid_corners_themselves_are_land() -> void:
	# El caso que fallaba: la celda (0,0) y sus tres hermanas eran agua.
	var poly := _grass(5.0)
	var half: Vector2 = IslandGen.grid_half_extents()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			assert_bool(Geometry2D.is_point_in_polygon(Vector2(half.x * sx, half.y * sz), poly)).is_true()

func test_with_zero_wobble_the_shape_still_covers_the_grid() -> void:
	# La ondulacion solo puede ayudar; la garantia la da el margen.
	var poly := _grass(0.0, 3.0, 8.0, 0.0)
	for corner in _cell_corners():
		assert_bool(Geometry2D.is_point_in_polygon(corner, poly)).is_true()

func test_the_shore_starts_outside_the_grid() -> void:
	# Ningun punto del borde de hierba cae dentro del cuadrado de la rejilla.
	var half: Vector2 = IslandGen.grid_half_extents()
	for p in _grass(21.0):
		assert_bool(absf(p.x) >= half.x - 0.001 or absf(p.y) >= half.y - 0.001) \
			.override_failure_message("border point %s inside the grid" % p).is_true()

# ── Piezas de la geometria ───────────────────────────────────────────

func test_wobble_is_never_negative_and_bounded() -> void:
	for w in IslandGen.make_wobble(128, 33.3, 2.0):
		assert_float(float(w)).is_between(0.0, 2.0)

func test_corner_radius_limit_matches_the_margin() -> void:
	# R <= m * sqrt2 / (sqrt2 - 1): con margen 3 caben esquinas de hasta ~10.24.
	assert_float(IslandGen.max_corner_radius(3.0)).is_equal_approx(10.2426, 0.001)
	assert_float(IslandGen.max_corner_radius(0.0)).is_equal_approx(0.0, 0.0001)

func test_a_corner_radius_at_the_limit_still_touches_the_grid_corner() -> void:
	var margin := 3.0
	var r: float = IslandGen.max_corner_radius(margin)
	var half: Vector2 = IslandGen.grid_half_extents()
	var poly := _grass(0.0, margin, r, 0.0)
	# Justo en el limite la esquina de la rejilla queda sobre el borde: se
	# comprueba un pelo por dentro para no depender de la tolerancia del poligono.
	var eps := 0.05
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(half.x - eps, half.y - eps), poly)).is_true()

func test_rounded_square_radius_on_the_axes_is_the_half_extent() -> void:
	assert_float(IslandGen.rounded_square_radius(0.0, 43.0, 43.0, 8.0)).is_equal_approx(43.0, 0.001)
	assert_float(IslandGen.rounded_square_radius(PI / 2.0, 43.0, 43.0, 8.0)).is_equal_approx(43.0, 0.001)

func test_rounded_square_radius_on_the_diagonal_is_shorter_than_the_sharp_corner() -> void:
	var sharp: float = sqrt(2.0) * 43.0
	var rounded: float = IslandGen.rounded_square_radius(PI / 4.0, 43.0, 43.0, 8.0)
	assert_float(rounded).is_less(sharp)
	# Y con radio 0 vuelve a ser el cuadrado puro.
	assert_float(IslandGen.rounded_square_radius(PI / 4.0, 43.0, 43.0, 0.0)).is_equal_approx(sharp, 0.001)

func test_the_shore_ring_is_strictly_outside_the_grass() -> void:
	var half: Vector2 = IslandGen.grid_half_extents()
	var wobble: Array = IslandGen.make_wobble(64, 3.0, 2.0)
	var grass := IslandGen.border_points(half.x, half.y, 3.0, 8.0, wobble)
	var shore := IslandGen.border_points(half.x, half.y, 3.0, 8.0, wobble, 3.5)
	for i in range(grass.size()):
		assert_float(shore[i].length()).is_greater(grass[i].length())
