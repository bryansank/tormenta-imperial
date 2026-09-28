extends GdUnitTestSuite
## Girar dos dedos rota la camara 3D; pellizcarlos hace zoom (bug 13).
##
## Antes InputService solo medía la distancia entre los dos dedos: un giro a
## distancia constante no hacia nada. Ahora mide tambien el angulo de la linea
## que los une y bloquea el gesto en lo primero que pase su umbral
## (GameConfig.twist_lock_degrees / pinch_lock_scale). Rotar es 1:1: los grados
## que giran los dedos son los que gira la camara (camera_rotate_step_requested).
## En 2D no hay giro (docs/18): ahi un giro no hace nada, ni zoom.
##
## Los eventos van a mano por `_unhandled_input`, como en test_touch_pan.

const InputSvc := preload("res://scripts/services/InputService.gd")
const CameraScript := preload("res://scripts/camera/MonumentalCamera.gd")

var _svc: Node = null
var _cam: Camera3D = null
var _rotations: Array = []
var _zooms: Array = []

func before_test() -> void:
	_rotations = []
	_zooms = []
	EventBus.camera_rotate_step_requested.connect(_on_rot)
	EventBus.camera_zoom_requested.connect(_on_zoom)
	_cam = auto_free(Camera3D.new())
	add_child(_cam)
	_cam.position = Vector3(0, 14, 14)
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	_cam.current = true
	_svc = auto_free(InputSvc.new())
	add_child(_svc)

func after_test() -> void:
	EventBus.camera_rotate_step_requested.disconnect(_on_rot)
	EventBus.camera_zoom_requested.disconnect(_on_zoom)

func _on_rot(deg: float) -> void:
	_rotations.append(deg)

func _on_zoom(amount: float) -> void:
	_zooms.append(amount)

func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	return ev

func _drag(index: int, pos: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = rel
	return ev

func _feed(ev: InputEvent) -> void:
	_svc._unhandled_input(ev)

func _sum(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s

## Dos dedos a `r` px del centro, girados `total_deg` en pasos de 3 grados, y
## con la separacion multiplicada por `scale_end` al final.
func _two_finger(total_deg: float, scale_end: float = 1.0, lift := true) -> void:
	var c := Vector2(640, 360)
	var r := 150.0
	var p0 := c + Vector2(-r, 0)
	var p1 := c + Vector2(r, 0)
	_feed(_touch(0, p0, true))
	_feed(_touch(1, p1, true))
	var steps := maxi(1, int(absf(total_deg) / 3.0))
	for k in range(1, steps + 1):
		var t := float(k) / steps
		var a := deg_to_rad(total_deg * t)
		var rr := r * lerpf(1.0, scale_end, t)
		var n0 := c + Vector2(-rr, 0).rotated(a)
		var n1 := c + Vector2(rr, 0).rotated(a)
		_feed(_drag(0, n0, n0 - p0))
		_feed(_drag(1, n1, n1 - p1))
		p0 = n0
		p1 = n1
	if lift:
		_feed(_touch(0, p0, false))
		_feed(_touch(1, p1, false))

func test_a_twist_at_constant_distance_rotates_the_camera_one_to_one() -> void:
	_two_finger(45.0)
	assert_array(_zooms).is_empty()
	assert_array(_rotations).is_not_empty()
	# 1:1: la suma de pasos es el giro de los dedos.
	assert_float(absf(_sum(_rotations))).is_equal_approx(45.0, 0.5)

func test_a_pure_pinch_zooms_and_never_rotates() -> void:
	_two_finger(0.0, 1.6)
	assert_array(_rotations).is_empty()
	assert_array(_zooms).is_not_empty()
	# Separar los dedos acerca (zoom negativo), como antes.
	assert_float(_sum(_zooms)).is_less(0.0)

func test_a_small_wobble_does_not_decide_anything() -> void:
	# 5 grados y 5 % de separacion: por debajo de los dos umbrales.
	_two_finger(5.0, 1.05)
	assert_array(_rotations).is_empty()
	assert_array(_zooms).is_empty()

func test_once_locked_to_rotate_a_pinch_does_not_zoom() -> void:
	# El bloqueo es por gesto: girar 30 grados y luego separar no hace zoom.
	_two_finger(30.0, 1.0, false)
	assert_str(_svc.gesture_lock()).is_equal("rotate")
	var pts: Array = _svc._touch_points.values()
	var p0: Vector2 = pts[0]
	var p1: Vector2 = pts[1]
	var c := (p0 + p1) * 0.5
	_feed(_drag(1, c + (p1 - c) * 1.5, (p1 - c) * 0.5))
	assert_array(_zooms).is_empty()

func test_lifting_a_finger_resets_the_lock() -> void:
	_two_finger(30.0, 1.0, false)
	assert_str(_svc.gesture_lock()).is_equal("rotate")
	var pts: Array = _svc._touch_points.values()
	_feed(_touch(1, pts[1], false))
	assert_str(_svc.gesture_lock()).is_equal("")
	_feed(_touch(0, pts[0], false))
	_rotations = []
	# Gesto nuevo: esta vez pellizco puro, y manda el zoom.
	_two_finger(0.0, 1.6)
	assert_array(_rotations).is_empty()
	assert_array(_zooms).is_not_empty()

func test_without_a_3d_camera_a_twist_does_nothing() -> void:
	# Vista 2D: sin giro de camara (docs/18). Y un giro tampoco da zoom.
	_cam.clear_current()
	_cam.queue_free()
	await await_idle_frame()
	if get_viewport().get_camera_3d() != null:
		# Otra suite dejo una camara viva en la raiz: la regla es pura, se prueba asi.
		assert_str(InputSvc.decide_two_finger_lock(300.0, 300.0, 0.0, deg_to_rad(40.0), false)).is_equal("")
		return
	_two_finger(45.0)
	assert_array(_rotations).is_empty()
	assert_array(_zooms).is_empty()

func test_the_lock_rule_is_the_first_threshold_crossed() -> void:
	assert_str(InputSvc.decide_two_finger_lock(300.0, 300.0, 0.0, deg_to_rad(9.0), true)).is_equal("rotate")
	assert_str(InputSvc.decide_two_finger_lock(300.0, 330.0, 0.0, deg_to_rad(2.0), true)).is_equal("zoom")
	assert_str(InputSvc.decide_two_finger_lock(300.0, 310.0, 0.0, deg_to_rad(4.0), true)).is_equal("")
	# Sin giro permitido, girar mucho no bloquea en nada.
	assert_str(InputSvc.decide_two_finger_lock(300.0, 300.0, 0.0, deg_to_rad(60.0), false)).is_equal("")

func test_the_terrain_turns_with_the_fingers() -> void:
	# El signo: con los dedos girando en el sentido de las agujas del reloj en
	# pantalla (angulo creciente con la Y hacia abajo), un punto del suelo tiene
	# que girar igual alrededor del centro de la pantalla.
	var cam: Camera3D = auto_free(CameraScript.new())
	add_child(cam)
	cam.current = true
	await await_idle_frame()
	var ground := Vector3(6.0, 0.0, 0.0)
	var centre_px := cam.unproject_position(Vector3.ZERO)
	var before := cam.unproject_position(ground) - centre_px
	_two_finger(30.0)
	var deg := _sum(_rotations)
	assert_float(deg).is_greater(0.0)
	# La camara ya lo recibio por EventBus; se salta el suavizado.
	assert_float(cam._target_yaw).is_equal_approx(deg, 0.01)
	cam._yaw = cam._target_yaw
	cam._update_transform()
	var after := cam.unproject_position(ground) - cam.unproject_position(Vector3.ZERO)
	# El angulo en pantalla del punto crece (mismo sentido que los dedos).
	assert_float(angle_difference(before.angle(), after.angle())).is_greater(0.0)

func test_the_touch_slop_is_measured_in_dp() -> void:
	# 14 dp en una tablet de 280 dpi con el lienzo escalado x2.3: 10.65 px del lienzo.
	assert_float(InputSvc.touch_slop_for(14.0, 280, 2.3, 8.0)).is_equal_approx(14.0 * 280.0 / 160.0 / 2.3, 0.01)
	# Nunca por debajo del suelo en pixeles.
	assert_float(InputSvc.touch_slop_for(14.0, 96, 4.0, 8.0)).is_equal(8.0)
	# Sin dpi conocido, 1 dp = 1 px.
	assert_float(InputSvc.touch_slop_for(14.0, 0, 1.0, 8.0)).is_equal(14.0)
