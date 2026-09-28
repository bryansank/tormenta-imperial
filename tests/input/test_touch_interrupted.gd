extends GdUnitTestSuite
## El gesto tactil que el sistema corta por la mitad.
##
## Si el soltar de un dedo no llega —la aplicacion se va a segundo plano, entra
## una llamada, Android cancela el gesto— su indice se queda vivo en
## `_touch_points`. A partir de ahi el dedo siguiente entra ya como SEGUNDO: el
## arrastre de uno deja de funcionar y todo toque se lee como pellizco, hasta
## reiniciar el juego.
##
## El motor no purga nada por su cuenta al perder el foco: reenvia lo que mande
## el sistema. En Android eso es un ACTION_CANCEL, que Godot convierte en un
## soltar por dedo... o en uno solo con `index` -1, que es lo que se le reprocha
## desde 4.0 (godotengine/godot#74199) y no borra ningun indice de los que este
## servicio sigue.
##
## Los eventos se construyen a mano y se meten por `_unhandled_input`: en headless
## el motor no entrega tactil, y esperarlo dejaria la prueba siempre en verde.
## El servicio se instancia aparte del autoload para no dejarle estado puesto.

const InputSvc := preload("res://scripts/services/InputService.gd")

var _svc: Node = null
var _saved_touch_threshold := 0.0

func before_test() -> void:
	_saved_touch_threshold = GameConfig.touch_drag_threshold_px
	GameConfig.touch_drag_threshold_px = 10.0
	_svc = auto_free(InputSvc.new())
	add_child(_svc)

func after_test() -> void:
	GameConfig.touch_drag_threshold_px = _saved_touch_threshold

# ── Utillaje ─────────────────────────────────────────────────────────

func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	return ev

func _cancel(index: int, pos: Vector2) -> InputEventScreenTouch:
	var ev := _touch(index, pos, false)
	ev.canceled = true
	return ev

func _drag(index: int, from_pos: Vector2, to_pos: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = to_pos
	ev.relative = to_pos - from_pos
	return ev

func _feed(event: InputEvent) -> void:
	_svc._unhandled_input(event)

# ── Perder el foco suelta el dedo ────────────────────────────────────

func test_losing_focus_unglues_a_finger_that_never_lifted() -> void:
	_feed(_touch(0, Vector2(400, 300), true))
	assert_bool(_svc.is_touch_gesture_active()).is_true()

	# Es la notificacion de APLICACION y no la de ventana: la de ventana se la
	# queda el nodo Window, y esto es un autoload — nunca la veria.
	_svc.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)

	assert_bool(_svc.is_touch_gesture_active()).is_false()
	assert_bool(_svc.is_touch_panning()).is_false()

func test_after_losing_focus_the_next_finger_is_the_first_one_again() -> void:
	# Esto es el sintoma tal y como lo ve el jugador: vuelve al juego, apoya un
	# dedo y el mapa no se mueve, porque su dedo esta entrando como el segundo.
	_feed(_touch(0, Vector2(400, 300), true))
	_svc.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)

	_feed(_touch(1, Vector2(200, 200), true))
	_feed(_drag(1, Vector2(200, 200), Vector2(280, 200)))

	assert_bool(_svc.is_touch_panning()).is_true()
	assert_bool(_svc.touch_pan_consumed_click()).is_true()

func test_a_gesture_cut_short_does_not_end_as_a_tap() -> void:
	# Un gesto que corta el sistema no es un toque deliberado. Si Godot fabrica
	# un clic emulado al cerrarlo, nadie quiere que ese clic suelte el edificio
	# que se estaba colocando.
	_feed(_touch(0, Vector2(400, 300), true))
	_svc.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)

	assert_bool(_svc.touch_pan_consumed_click()).is_true()

func test_a_touch_that_starts_after_the_purge_is_a_clean_tap_again() -> void:
	# Y la marca no se queda pegada: el dedo siguiente empieza limpio y un toque
	# corto vuelve a valer como clic.
	_feed(_touch(0, Vector2(400, 300), true))
	_svc.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)

	_feed(_touch(0, Vector2(200, 200), true))
	_feed(_touch(0, Vector2(202, 201), false))

	assert_bool(_svc.touch_pan_consumed_click()).is_false()
	assert_bool(_svc.is_touch_gesture_active()).is_false()

# ── El cancel del sistema levanta todos los dedos ────────────────────

func test_a_cancel_without_a_finger_to_point_at_lifts_them_all() -> void:
	# Asi llega el ACTION_CANCEL de Android cuando Godot no sabe a que dedo
	# apunta (godotengine/godot#74199). Borrar el indice -1 no borra nada.
	_feed(_touch(0, Vector2(400, 300), true))
	_feed(_touch(1, Vector2(500, 300), true))
	assert_bool(_svc.is_touch_gesture_active()).is_true()

	_feed(_touch(-1, Vector2(400, 300), false))

	assert_bool(_svc.is_touch_gesture_active()).is_false()

func test_a_release_marked_as_cancelled_lifts_them_all_too() -> void:
	_feed(_touch(0, Vector2(400, 300), true))
	_feed(_touch(1, Vector2(500, 300), true))

	_feed(_cancel(0, Vector2(400, 300)))

	assert_bool(_svc.is_touch_gesture_active()).is_false()

# ── Y un soltar normal sigue siendo un soltar normal ─────────────────

func test_lifting_one_of_two_fingers_still_leaves_the_other_one_down() -> void:
	_feed(_touch(0, Vector2(400, 300), true))
	_feed(_touch(1, Vector2(500, 300), true))

	_feed(_touch(1, Vector2(500, 300), false))

	assert_bool(_svc.is_touch_gesture_active()).is_true()
	# El que queda vuelve a empezar como dedo de paneo, como siempre.
	_feed(_drag(0, Vector2(400, 300), Vector2(480, 300)))
	assert_bool(_svc.is_touch_panning()).is_true()
