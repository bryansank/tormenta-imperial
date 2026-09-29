extends GdUnitTestSuite
## Pantalla -> celda en la vista 2D, y la camara 2D (docs/18-vista-2d.md).
##
## El mapeo es puro (View2D): se fija con transformaciones de lienzo hechas a
## mano (zoom y desplazamiento), sin ventana. La camara se prueba de verdad:
## sus senales, su estado compatible con el de la 3D y que su lienzo lleva cada
## celda a donde dice View2D. Deja GameManager._camera como estaba.

const View2D := preload("res://scripts/view2d/View2D.gd")
const Cam2D := preload("res://scripts/view2d/Camera2DController.gd")
const StormTint := preload("res://scripts/view2d/StormTint2D.gd")
const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")

var _saved_camera: Node = null

func before_test() -> void:
	_saved_camera = GameManager._camera
	# Estos casos fijan el mapeo de la rejilla de 40x40; una partida nueva de
	# otra suite pudo dejar un tamano sorteado (mapa aleatorio).
	GridManager.reset_size()

func after_test() -> void:
	GameManager._camera = _saved_camera if is_instance_valid(_saved_camera) else null
	GridManager.reset_size()

## Lienzo de una camara centrada en `center_px` con `zoom`, en una pantalla de `screen`.
func _xform(center_px: Vector2, zoom: float, screen := Vector2(1280, 720)) -> Transform2D:
	return Transform2D(0.0, Vector2(zoom, zoom), 0.0, screen * 0.5 - center_px * zoom)

# ── Mundo <-> pixeles ─────────────────────────────────────────────────

func test_the_grid_corner_and_centre_map_to_known_pixels() -> void:
	assert_float(View2D.cell_px()).is_equal(32.0)
	assert_vector(View2D.cell_origin_px(Vector2i(0, 0))).is_equal(Vector2(-640, -640))
	assert_vector(View2D.cell_origin_px(Vector2i(20, 20))).is_equal(Vector2(0, 0))
	# El Nucleo 3x3 en (20,20): su centro 2D es el building_center 3D, en pixeles.
	assert_vector(View2D.footprint_center_px(Vector2i(20, 20), Vector2i(3, 3))).is_equal(Vector2(48, 48))
	var w3 := GridManager.building_center(Vector2i(20, 20), Vector2i(3, 3))
	assert_vector(View2D.world_to_px(w3)).is_equal(Vector2(48, 48))

func test_every_cell_centre_maps_back_to_its_cell() -> void:
	for cell in [Vector2i(0, 0), Vector2i(39, 39), Vector2i(0, 39), Vector2i(17, 3), Vector2i(20, 20)]:
		var centre := View2D.footprint_center_px(cell, Vector2i.ONE)
		assert_that(View2D.px_to_cell(centre)).is_equal(cell)
		# Y las esquinas interiores de la celda tambien.
		var o := View2D.cell_origin_px(cell)
		assert_that(View2D.px_to_cell(o + Vector2(0.1, 0.1))).is_equal(cell)
		assert_that(View2D.px_to_cell(o + Vector2(31.9, 31.9))).is_equal(cell)

func test_outside_the_grid_is_an_invalid_cell_not_the_edge_cell() -> void:
	var water := View2D.px_to_cell(Vector2(-700, 0))
	assert_bool(GridManager.is_valid_cell(water)).is_false()
	assert_bool(GridManager.is_valid_cell(View2D.px_to_cell(Vector2(0, 641)))).is_false()

func test_world_and_pixels_round_trip() -> void:
	var w := Vector3(3.5, 0.0, -12.25)
	assert_vector(View2D.px_to_world(View2D.world_to_px(w))).is_equal(w)

# ── Pantalla -> celda ─────────────────────────────────────────────────

func test_the_screen_centre_is_the_cell_under_the_camera() -> void:
	var target := View2D.footprint_center_px(Vector2i(20, 20), Vector2i.ONE)
	for zoom in [0.6, 1.0, 1.8, 4.5]:
		assert_that(View2D.screen_to_cell(_xform(target, zoom), Vector2(640, 360))).is_equal(Vector2i(20, 20))

func test_moving_one_cell_on_screen_depends_on_zoom() -> void:
	var target := View2D.footprint_center_px(Vector2i(10, 10), Vector2i.ONE)
	var x := _xform(target, 2.0)
	# A zoom 2 una celda son 64 px de pantalla.
	assert_that(View2D.screen_to_cell(x, Vector2(640 + 64, 360))).is_equal(Vector2i(11, 10))
	assert_that(View2D.screen_to_cell(x, Vector2(640, 360 - 64))).is_equal(Vector2i(10, 9))
	assert_that(View2D.screen_to_cell(x, Vector2(640 + 20, 360))).is_equal(Vector2i(10, 10))

func test_screen_and_pixel_round_trip() -> void:
	var x := _xform(Vector2(123, -45), 1.37)
	var px := Vector2(-300.5, 211.25)
	assert_vector(View2D.screen_to_px(x, View2D.px_to_screen(x, px))).is_equal_approx(px, Vector2(0.001, 0.001))

func test_a_drag_moves_the_camera_by_the_grabbed_distance() -> void:
	# Arrastrar 64 px a la derecha a zoom 2 = 32 px de mapa = 2 unidades de mundo,
	# y el objetivo se mueve al reves (se agarra el terreno).
	var x := _xform(Vector2.ZERO, 2.0)
	var d := View2D.screen_drag_to_world_delta(x, Vector2(100, 100), Vector2(164, 100))
	assert_vector(d).is_equal_approx(Vector2(-2, 0), Vector2(0.001, 0.001))

# ── La camara 2D ──────────────────────────────────────────────────────

func test_camera_state_uses_the_3d_format_and_round_trips() -> void:
	var cam: Camera2D = auto_free(Cam2D.new())
	add_child(cam)
	cam.set_state({"target_x": 4.0, "target_y": -6.0, "yaw": 45.0, "distance": 30.0})
	var st: Dictionary = cam.get_state()
	assert_float(float(st["target_x"])).is_equal(4.0)
	assert_float(float(st["target_y"])).is_equal(-6.0)
	# El giro no existe en 2D, pero se conserva para devolverselo a la 3D.
	assert_float(float(st["yaw"])).is_equal(45.0)
	assert_float(float(st["distance"])).is_equal(30.0)
	assert_vector(cam.position).is_equal(Vector2(4, -6) * View2D.PX_PER_UNIT)
	assert_float(cam.zoom.x).is_equal_approx(View2D.distance_to_zoom(30.0) * cam.screen_boost(), 0.0001)

func test_camera_registers_with_game_manager() -> void:
	var cam: Camera2D = auto_free(Cam2D.new())
	add_child(cam)
	assert_object(GameManager._camera).is_same(cam)

func test_camera_follows_world_drags_and_stays_on_the_map() -> void:
	var cam: Camera2D = auto_free(Cam2D.new())
	add_child(cam)
	cam.set_state({"target_x": 0.0, "target_y": 0.0, "distance": 20.0})
	EventBus.camera_drag_world_requested.emit(Vector2(3, -2))
	assert_float(float(cam.get_state()["target_x"])).is_equal(3.0)
	assert_float(float(cam.get_state()["target_y"])).is_equal(-2.0)
	EventBus.camera_drag_world_requested.emit(Vector2(500, 500))
	assert_float(float(cam.get_state()["target_x"])).is_equal(40.0)
	assert_float(float(cam.get_state()["target_y"])).is_equal(40.0)

func test_zoom_requests_are_clamped_like_the_3d_camera() -> void:
	var cam: Camera2D = auto_free(Cam2D.new())
	add_child(cam)
	for i in range(100):
		EventBus.camera_zoom_requested.emit(1.0)
	assert_float(cam._target_distance).is_equal(cam.max_distance)
	for i in range(100):
		EventBus.camera_zoom_requested.emit(-1.0)
	assert_float(cam._target_distance).is_equal(cam.min_distance)

# ── La tormenta en 2D ─────────────────────────────────────────────────

func test_the_storm_darkens_in_the_same_three_steps_as_the_3d_sky() -> void:
	assert_float(StormTint.target_weight(StormCycleScript.Phase.CALM, 3, false)).is_equal(0.0)
	assert_float(StormTint.target_weight(StormCycleScript.Phase.WARNING, 3, false)).is_equal(0.35)
	assert_float(StormTint.target_weight(StormCycleScript.Phase.ASH, 3, false)).is_equal(0.7)
	assert_float(StormTint.target_weight(StormCycleScript.Phase.STORM, 1, false)).is_greater_equal(0.6)
	assert_float(StormTint.target_weight(StormCycleScript.Phase.STORM, 99, false)).is_equal(1.0)
	# Ganada la Auditoria Final: despejado para siempre.
	assert_float(StormTint.target_weight(StormCycleScript.Phase.STORM, 5, true)).is_equal(0.0)
