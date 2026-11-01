extends GdUnitTestSuite
## Beta 0.9 (QA tablet real, 2026-10-26): la camara no se va al mar abierto.
## Se limita lo que se ve, no solo el centro: la tierra mas
## GameConfig.camera_bounds_margin_cells, en 3D (MonumentalCamera, con giro y
## zoom) y en 2D (Camera2DController).

const Cam3D := preload("res://scripts/camera/MonumentalCamera.gd")
const Cam2D := preload("res://scripts/view2d/Camera2DController.gd")

func test_clamp_axis_keeps_the_view_inside_or_centres_it() -> void:
	# Vista de -5..+5 en un limite de 0..100: el centro va de 5 a 95.
	assert_float(Cam3D.clamp_axis(-50.0, 0.0, 100.0, -5.0, 5.0)).is_equal(5.0)
	assert_float(Cam3D.clamp_axis(500.0, 0.0, 100.0, -5.0, 5.0)).is_equal(95.0)
	assert_float(Cam3D.clamp_axis(40.0, 0.0, 100.0, -5.0, 5.0)).is_equal(40.0)
	# Vista mas grande que el limite: centrada, vaya donde vaya.
	assert_float(Cam3D.clamp_axis(-80.0, 0.0, 100.0, -70.0, 70.0)).is_equal(50.0)
	assert_float(Cam3D.clamp_axis(80.0, 0.0, 100.0, -70.0, 70.0)).is_equal(50.0)
	# Vista asimetrica (de frente se ve mas lejos que cerca).
	assert_float(Cam3D.clamp_axis(-99.0, 0.0, 100.0, -20.0, 8.0)).is_equal(20.0)
	assert_float(Cam3D.clamp_axis(99.0, 0.0, 100.0, -20.0, 8.0)).is_equal(92.0)
	# 2D: media vista simetrica.
	assert_float(Cam2D.clamp_axis(-50.0, 0.0, 100.0, 10.0)).is_equal(10.0)
	assert_float(Cam2D.clamp_axis(70.0, 0.0, 100.0, 60.0)).is_equal(50.0)

func test_the_footprint_sees_farther_ahead_than_behind() -> void:
	# Giro 0: la camara esta en +Z y mira hacia -Z; el fondo es -Z.
	var fp: Rect2 = Cam3D.view_footprint(24.0, -46.0, 0.0, 16.0 / 9.0)
	assert_float(fp.position.y).is_less(0.0)
	assert_float(fp.end.y).is_greater(0.0)
	assert_float(-fp.position.y).is_greater(fp.end.y)
	# De lado, simetrica.
	assert_float(fp.position.x).is_equal_approx(-fp.end.x, 0.001)

func test_the_footprint_grows_with_distance_and_turns_with_yaw() -> void:
	var near: Rect2 = Cam3D.view_footprint(12.0, -38.0, 0.0, 16.0 / 9.0)
	var far: Rect2 = Cam3D.view_footprint(95.0, -52.0, 0.0, 16.0 / 9.0)
	assert_float(far.size.x).is_greater(near.size.x)
	assert_float(far.size.y).is_greater(near.size.y)
	# Girada 180: el fondo pasa a +Z.
	var turned: Rect2 = Cam3D.view_footprint(24.0, -46.0, 180.0, 16.0 / 9.0)
	assert_float(turned.end.y).is_greater(-turned.position.y)
	# Girada 90: el ancho y el fondo se cambian de eje.
	var side: Rect2 = Cam3D.view_footprint(24.0, -46.0, 90.0, 16.0 / 9.0)
	var front: Rect2 = Cam3D.view_footprint(24.0, -46.0, 0.0, 16.0 / 9.0)
	assert_float(side.size.x).is_equal_approx(front.size.y, 0.01)
	assert_float(side.size.y).is_equal_approx(front.size.x, 0.01)

func test_the_3d_camera_never_shows_open_sea() -> void:
	var cam: Camera3D = auto_free(Cam3D.new())
	add_child(cam)
	await await_idle_frame()
	cam.fit_to_grid()
	var land: Rect2 = GridManager.land_world_rect()
	var margin: float = GameConfig.camera_bounds_margin_cells * GridManager.cell_size
	assert_object(cam.boundary_min).is_equal(land.grow(margin).position)
	# Arrastre largo hacia fuera, con cada metodo: el borde de lo visto queda
	# dentro del limite.
	for d in [Vector2(-5000, 0), Vector2(5000, 0), Vector2(0, -5000), Vector2(0, 5000)]:
		cam.set_state({"target_x": 0.0, "target_y": 0.0, "yaw": 0.0, "distance": 24.0})
		EventBus.camera_drag_world_requested.emit(d)
		cam._clamp_to_boundaries()
		var fp: Rect2 = Cam3D.view_footprint(24.0, cam.pitch_for(24.0), 0.0, cam._aspect(), cam.fov)
		var t: Dictionary = cam.get_state()
		var seen := Rect2(Vector2(t["target_x"], t["target_y"]) + fp.position, fp.size)
		var bounds := Rect2(cam.boundary_min, cam.boundary_max - cam.boundary_min)
		assert_bool(bounds.grow(0.01).encloses(seen) or seen.size.x > bounds.size.x or seen.size.y > bounds.size.y) \
			.override_failure_message("visto %s fuera de %s" % [seen, bounds]).is_true()

func test_the_2d_camera_never_shows_open_sea() -> void:
	# La camara 2D se registra en GameManager al entrar: se deja la de antes.
	var prev: Node = GameManager._camera
	var cam: Camera2D = auto_free(Cam2D.new())
	add_child(cam)
	await await_idle_frame()
	cam.look_at_world(Vector2(-5000, 5000), 24.0)
	var half: Vector2 = cam.view_half_extent()
	var t: Dictionary = cam.get_state()
	if half.x * 2.0 <= cam.boundary_max.x - cam.boundary_min.x:
		assert_float(float(t["target_x"]) - half.x).is_greater_equal(cam.boundary_min.x - 0.01)
	if half.y * 2.0 <= cam.boundary_max.y - cam.boundary_min.y:
		assert_float(float(t["target_y"]) + half.y).is_less_equal(cam.boundary_max.y + 0.01)
	GameManager.register_camera(prev)
