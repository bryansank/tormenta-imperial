extends GdUnitTestSuite
## Arrastrar el mapa con el dedo, igual que con el raton.
##
## El dedo tenia su propio camino: multiplicaba los pixeles del arrastre por una
## sensibilidad fija y mandaba `camera_drag_moved`. El raton, en cambio, agarra el
## terreno: proyecta el punto de partida y el de llegada sobre el suelo y mueve la
## camara justo ese hueco (`camera_drag_world_requested`). Resultado: con el dedo
## el mapa corria distinto segun el zoom y no se pegaba al dedo.
##
## Ahora los dos llaman a `InputService.screen_drag_to_world_delta`, asi que la
## cuenta es una sola. Estos casos fijan esa cuenta, el umbral que separa un toque
## de un arrastre, el relevo limpio hacia el pellizco y que la interfaz no pierda
## sus toques.
##
## Los eventos se construyen a mano y se meten por `_unhandled_input`: en headless
## el motor no entrega tactil, y esperarlo dejaria la prueba siempre en verde.

const InputSvc := preload("res://scripts/services/InputService.gd")
const Placer := preload("res://scripts/buildings/BuildingPlacer.gd")

var _svc: Node = null
var _cam: Camera3D = null
var _pans: Array = []
var _zooms: Array = []
var _saved_touch_threshold := 0.0
var _saved_mouse_threshold := 0.0
var _saved_placer: Node = null

func before_test() -> void:
	_saved_touch_threshold = GameConfig.touch_drag_threshold_px
	_saved_mouse_threshold = GameConfig.mouse_drag_threshold_px
	_saved_placer = GameManager._placer
	_pans = []
	_zooms = []
	EventBus.camera_drag_world_requested.connect(_on_pan)
	EventBus.camera_zoom_requested.connect(_on_zoom)

	# Camara como la del juego: perspectiva, 45 grados de picado, mirando al centro.
	_cam = auto_free(Camera3D.new())
	add_child(_cam)
	_place_camera(20.0)

	_svc = auto_free(InputSvc.new())
	add_child(_svc)

func after_test() -> void:
	GameConfig.touch_drag_threshold_px = _saved_touch_threshold
	GameConfig.mouse_drag_threshold_px = _saved_mouse_threshold
	GameManager._placer = _saved_placer
	EventBus.camera_drag_world_requested.disconnect(_on_pan)
	EventBus.camera_zoom_requested.disconnect(_on_zoom)

func _on_pan(delta: Vector2) -> void:
	_pans.append(delta)

func _on_zoom(amount: float) -> void:
	_zooms.append(amount)

# ── Utilidades ──

## Coloca la camara a `distance` del origen con el picado de MonumentalCamera.
func _place_camera(distance: float) -> void:
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 60.0
	var pitch := deg_to_rad(45.0)
	_cam.position = Vector3(0.0, distance * sin(pitch), distance * cos(pitch))
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	_cam.current = true

## El punto del suelo bajo una posicion de pantalla, calculado aqui a mano para
## no preguntarle la respuesta al codigo que se esta probando.
func _ground_point(screen_pos: Vector2) -> Vector3:
	var from := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	return from + dir * (-from.y / dir.y)

## Lo que deberia moverse la camara para que el terreno siga al dedo de a hasta b.
func _expected_delta(a: Vector2, b: Vector2) -> Vector2:
	var pa := _ground_point(a)
	var pb := _ground_point(b)
	return Vector2(pa.x - pb.x, pa.z - pb.z)

func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	return ev

func _drag(index: int, from_pos: Vector2, to_pos: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = to_pos
	ev.relative = to_pos - from_pos
	return ev

func _feed(event: InputEvent) -> void:
	_svc._unhandled_input(event)

# ── Umbral: un toque corto sigue siendo un clic ──

func test_a_short_touch_never_moves_the_map() -> void:
	# Cinco pixeles de temblor no son un arrastre: son un dedo intentando estarse
	# quieto encima de un edificio.
	var start := Vector2(400, 300)
	_feed(_touch(0, start, true))
	_feed(_drag(0, start, start + Vector2(4, 3)))
	_feed(_touch(0, start + Vector2(4, 3), false))
	assert_array(_pans).is_empty()

func test_a_short_touch_still_counts_as_a_click() -> void:
	# Quien recibe el clic emulado (BuildingPlacer) pregunta esto al levantar el
	# dedo: si el gesto no llego a arrastrar, el toque selecciona o coloca.
	var start := Vector2(400, 300)
	_feed(_touch(0, start, true))
	_feed(_drag(0, start, start + Vector2(4, 3)))
	_feed(_touch(0, start + Vector2(4, 3), false))
	assert_bool(_svc.touch_pan_consumed_click()).is_false()

func test_past_the_threshold_the_finger_drags_the_map() -> void:
	var start := Vector2(400, 300)
	var finish := Vector2(440, 300)
	_feed(_touch(0, start, true))
	_feed(_drag(0, start, finish))
	assert_array(_pans).has_size(1)
	# El primer paneo arrastra desde donde se apoyo el dedo: los pixeles gastados
	# en cruzar el umbral no se pierden, igual que con el raton.
	assert_vector(_pans[0]).is_equal_approx(_expected_delta(start, finish), Vector2(0.001, 0.001))

func test_a_drag_no_longer_ends_as_a_click() -> void:
	# Arrastrar el mapa y encontrarse un edificio abierto al soltar es lo que hacia
	# que el juego pareciese que interpreta mal el dedo.
	var start := Vector2(400, 300)
	_feed(_touch(0, start, true))
	_feed(_drag(0, start, Vector2(440, 300)))
	assert_bool(_svc.is_touch_panning()).is_true()
	_feed(_touch(0, Vector2(440, 300), false))
	# Sigue en pie despues de levantar el dedo: el clic emulado llega despues.
	assert_bool(_svc.touch_pan_consumed_click()).is_true()

func test_the_threshold_comes_from_the_config() -> void:
	# Si el umbral se incrustase en el codigo, ajustarlo para una pantalla tactil
	# obligaria a tocar el servicio de entrada.
	GameConfig.touch_drag_threshold_px = 200.0
	var start := Vector2(400, 300)
	_feed(_touch(0, start, true))
	_feed(_drag(0, start, Vector2(440, 300)))
	assert_array(_pans).is_empty()

# ── Paridad con el raton ──

func test_the_finger_and_the_mouse_move_the_map_the_same() -> void:
	# Mismo recorrido en pixeles, mismo desplazamiento del mundo. El camino del
	# raton vive en BuildingPlacer, asi que aqui se le da de comer de verdad.
	var start := Vector2(500, 400)
	var finish := Vector2(560, 430)

	_feed(_touch(0, start, true))
	_feed(_drag(0, start, finish))
	assert_array(_pans).has_size(1)
	var finger_delta: Vector2 = _pans[0]

	_pans = []
	var placer: Node3D = auto_free(Placer.new())
	add_child(placer)
	placer._left_pressed = true
	placer._left_press_pos = start
	placer._drag_last_pos = start
	var motion := InputEventMouseMotion.new()
	motion.position = finish
	motion.relative = finish - start
	placer._handle_left_drag(motion)
	assert_array(_pans).has_size(1)
	var mouse_delta: Vector2 = _pans[0]

	assert_vector(finger_delta).is_equal_approx(mouse_delta, Vector2(0.001, 0.001))

func test_the_map_follows_the_finger_and_not_the_other_way_round() -> void:
	# Arrastrar hacia la derecha trae el terreno hacia la derecha, o sea que el
	# objetivo de la camara se va hacia -X. Es el mismo criterio que el raton.
	var start := Vector2(400, 300)
	_feed(_touch(0, start, true))
	_feed(_drag(0, start, Vector2(460, 300)))
	assert_array(_pans).has_size(1)
	assert_float((_pans[0] as Vector2).x).is_less(0.0)

func test_the_same_pixels_move_more_world_when_the_camera_is_far() -> void:
	# Agarrar el terreno significa que el zoom entra en la cuenta: de cerca el mapa
	# se mueve poco y de lejos mucho, con el mismo gesto.
	var start := Vector2(400, 300)
	var finish := Vector2(460, 300)
	_feed(_touch(0, start, true))
	_feed(_drag(0, start, finish))
	var near_delta: float = (_pans[0] as Vector2).length()

	_pans = []
	_place_camera(40.0)
	_feed(_touch(0, start, false))
	_feed(_touch(0, start, true))
	_feed(_drag(0, start, finish))
	var far_delta: float = (_pans[0] as Vector2).length()

	assert_float(far_delta).is_greater(near_delta * 1.5)

# ── Convivencia con el pellizco ──

func test_the_second_finger_stops_the_pan_and_starts_the_pinch() -> void:
	var a := Vector2(400, 300)
	_feed(_touch(0, a, true))
	_feed(_drag(0, a, Vector2(440, 300)))
	assert_bool(_svc.is_touch_panning()).is_true()

	_feed(_touch(1, Vector2(700, 300), true))
	assert_bool(_svc.is_touch_panning()).is_false()

	_pans = []
	_zooms = []
	_feed(_drag(0, Vector2(440, 300), Vector2(340, 300)))
	_feed(_drag(1, Vector2(700, 300), Vector2(800, 300)))
	# Dos dedos separandose acercan la camara, y ni un solo paneo por el camino.
	assert_array(_zooms).is_not_empty()
	assert_array(_pans).is_empty()

func test_lifting_one_pinch_finger_does_not_jerk_the_map() -> void:
	# El dedo que queda ha recorrido media pantalla pellizcando. Si el paneo
	# siguiese contando desde donde se apoyo, el mapa saltaria de golpe.
	var a := Vector2(400, 300)
	var b := Vector2(600, 300)
	_feed(_touch(0, a, true))
	_feed(_touch(1, b, true))
	_feed(_drag(0, a, Vector2(200, 300)))
	_feed(_drag(1, b, Vector2(800, 300)))
	_feed(_touch(1, Vector2(800, 300), false))

	_pans = []
	# Vuelve a empezar de cero: cinco pixeles no bastan.
	_feed(_drag(0, Vector2(200, 300), Vector2(205, 300)))
	assert_array(_pans).is_empty()

	# Y cuando por fin arrastra, mueve solo lo suyo, no lo del pellizco.
	_feed(_drag(0, Vector2(205, 300), Vector2(240, 300)))
	assert_array(_pans).has_size(1)
	assert_vector(_pans[0]).is_equal_approx(
		_expected_delta(Vector2(200, 300), Vector2(240, 300)), Vector2(0.001, 0.001))
	var jump: float = _expected_delta(Vector2(400, 300), Vector2(240, 300)).length()
	assert_float((_pans[0] as Vector2).length()).is_less(jump)

func test_letting_go_of_both_fingers_leaves_nothing_armed() -> void:
	var a := Vector2(400, 300)
	var b := Vector2(600, 300)
	_feed(_touch(0, a, true))
	_feed(_touch(1, b, true))
	_feed(_touch(0, a, false))
	_feed(_touch(1, b, false))
	assert_bool(_svc.is_touch_gesture_active()).is_false()
	assert_bool(_svc.is_touch_panning()).is_false()

# ── La interfaz se queda sus toques ──

func test_a_touch_that_starts_on_the_interface_never_pans() -> void:
	# Un dedo que se apoya en el D-pad o en un panel no llega nunca a
	# `_unhandled_input`: el Control se queda el apoyo. Lo que si puede llegar son
	# sus arrastres, y un arrastre sin apoyo registrado no mueve la camara.
	_feed(_drag(3, Vector2(120, 600), Vector2(320, 600)))
	assert_array(_pans).is_empty()
	assert_bool(_svc.is_touch_gesture_active()).is_false()

func test_an_interface_touch_does_not_break_the_finger_that_is_panning() -> void:
	# El pulgar en el D-pad mientras el indice arrastra el mapa: el arrastre del
	# indice sigue siendo un paneo de un dedo, no un pellizco.
	var a := Vector2(400, 300)
	_feed(_touch(0, a, true))
	_feed(_drag(3, Vector2(120, 600), Vector2(140, 600)))
	_pans = []
	_zooms = []
	_feed(_drag(0, a, Vector2(440, 300)))
	assert_array(_pans).has_size(1)
	assert_array(_zooms).is_empty()

# ── Un pellizco no es un toque ───────────────────────────────────────

## Con el raton emulado desde el tactil encendido, cada gesto del dedo llega
## tambien como boton izquierdo. `BuildingPlacer` difiere la colocacion al soltar
## y pregunta si el gesto se consumio paneando. Un pellizco no panea nunca —
## manda `_handle_pinch`— asi que sin marcarlo aparte la respuesta era "no" y el
## gesto acababa colocando el edificio donde quedo el dedo.
func test_a_pinch_never_ends_up_as_a_click() -> void:
	_feed(_touch(0, Vector2(300, 300), true))
	_feed(_touch(1, Vector2(340, 300), true))
	assert_bool(_svc.touch_pan_consumed_click()).is_true()

	# Y sigue consumido mientras dura el pellizco y al levantar los dedos, que es
	# cuando llega el clic emulado.
	_feed(_drag(0, Vector2(300, 300), Vector2(260, 300)))
	_feed(_drag(1, Vector2(340, 300), Vector2(380, 300)))
	assert_bool(_svc.touch_pan_consumed_click()).is_true()
	_feed(_touch(1, Vector2(380, 300), false))
	_feed(_touch(0, Vector2(260, 300), false))
	assert_bool(_svc.touch_pan_consumed_click()).is_true()

func test_a_plain_tap_after_a_pinch_is_a_click_again() -> void:
	_feed(_touch(0, Vector2(300, 300), true))
	_feed(_touch(1, Vector2(340, 300), true))
	_feed(_touch(1, Vector2(340, 300), false))
	_feed(_touch(0, Vector2(300, 300), false))
	# Gesto nuevo: el primer dedo limpia la marca, o el jugador no podria volver
	# a tocar nada despues de hacer zoom.
	_feed(_touch(0, Vector2(200, 200), true))
	assert_bool(_svc.touch_pan_consumed_click()).is_false()
	_feed(_touch(0, Vector2(200, 200), false))
	assert_bool(_svc.touch_pan_consumed_click()).is_false()
