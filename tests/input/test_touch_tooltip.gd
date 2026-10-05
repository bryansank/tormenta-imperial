extends GdUnitTestSuite
## "Mantener pulsado para leer" (TouchTooltip, decision de Bryan del 2026-10-05):
## con el dedo, un toque corto pulsa; uno largo ensena el tooltip en una burbuja
## y NO pulsa; moverse cancela; con raton (PC) no hace nada.
##
## Los eventos se mandan como los fabrica Godot en un movil: primero el raton
## emulado (device -1) y despues el toque. Toca GameConfig (modo de los controles
## tactiles, perfil y "ya hubo un toque real"): todo vuelve como estaba.

const TouchTooltip := preload("res://scripts/ui/TouchTooltip.gd")
const TIP := "Texto de prueba para leer con el dedo"

var _layer: CanvasLayer
var _button: Button
var _press_button: Button
var _presses := 0
var _press_presses := 0
var _tt: Node
var _saved_touch := "auto"
var _saved_profile := "auto"
var _saved_seen := false

func before_test() -> void:
	_saved_touch = GameConfig.ui_touch_controls
	_saved_profile = GameConfig.ui_device_profile
	_saved_seen = GameConfig._real_touch_seen
	GameConfig.ui_touch_controls = "always"
	_presses = 0
	_press_presses = 0
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_button = Button.new()
	_button.text = "LEER"
	_button.tooltip_text = TIP
	_button.position = Vector2(400, 400)
	_button.size = Vector2(160, 48)
	_button.pressed.connect(func(): _presses += 1)
	_layer.add_child(_button)
	_press_button = Button.new()
	_press_button.text = "+"
	_press_button.tooltip_text = "Zoom"
	_press_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_press_button.position = Vector2(700, 400)
	_press_button.size = Vector2(60, 60)
	_press_button.pressed.connect(func(): _press_presses += 1)
	_layer.add_child(_press_button)
	_tt = InputService.touch_tooltip()
	await await_idle_frame()

func after_test() -> void:
	if is_instance_valid(_layer):
		_layer.free()
	# Que ningun dedo de una prueba se quede apoyado para la siguiente.
	_touch(Vector2(1, 1), false)
	GameConfig.ui_touch_controls = _saved_touch
	GameConfig.ui_device_profile = _saved_profile
	GameConfig._real_touch_seen = _saved_seen

## push_input quiere pixeles de ventana; las pruebas piensan en el lienzo.
func _win(pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * pos

func _mouse(pos: Vector2, pressed: bool, device := -1) -> void:
	var e := InputEventMouseButton.new()
	e.device = device
	e.position = _win(pos)
	e.global_position = _win(pos)
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(e)

func _touch(pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = _win(pos)
	t.pressed = pressed
	get_viewport().push_input(t)

## Apoyar o levantar el dedo: raton emulado y luego el toque, como Godot.
func _finger(pos: Vector2, pressed: bool) -> void:
	_mouse(pos, pressed)
	_touch(pos, pressed)

func _drag(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.device = -1
	m.position = _win(pos)
	m.global_position = _win(pos)
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(m)
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = _win(pos)
	get_viewport().push_input(d)

func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

func test_it_lives_under_input_service_and_runs_in_pause() -> void:
	assert_object(_tt).is_not_null()
	assert_int(_tt.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)

func test_the_hold_time_comes_from_game_config() -> void:
	assert_float(GameConfig.touch_tooltip_hold_sec).is_equal_approx(0.5, 0.001)

func test_a_short_tap_presses_and_shows_nothing() -> void:
	var p := _center(_button)
	_finger(p, true)
	_tt.tick(0.1)
	_finger(p, false)
	await await_idle_frame()
	assert_int(_presses).is_equal(1)
	assert_bool(_tt.is_shown()).is_false()

func test_a_long_press_shows_the_tooltip_and_does_not_press() -> void:
	var p := _center(_button)
	_finger(p, true)
	assert_bool(_tt.is_pending()).is_true()
	_tt.tick(GameConfig.touch_tooltip_hold_sec + 0.05)
	assert_bool(_tt.is_shown()).is_true()
	assert_str(_tt.bubble_text()).is_equal(TIP)
	await await_idle_frame()
	# Encima del dedo y dentro de la pantalla.
	var rect: Rect2 = _tt.bubble().get_global_rect()
	var vp := get_viewport().get_visible_rect()
	assert_bool(vp.encloses(rect)).override_failure_message("burbuja %s fuera de %s" % [rect, vp]).is_true()
	assert_float(rect.end.y).is_less_equal(p.y)
	_finger(p, false)
	await await_idle_frame()
	assert_int(_presses).is_equal(0)
	assert_bool(_tt.is_shown()).is_false()
	# El boton no se queda hundido: el toque siguiente pulsa normal.
	_finger(p, true)
	_tt.tick(0.1)
	_finger(p, false)
	await await_idle_frame()
	assert_int(_presses).is_equal(1)

func test_moving_the_finger_cancels_the_bubble() -> void:
	var p := _center(_button)
	_finger(p, true)
	_drag(p + Vector2(0, 40))
	assert_bool(_tt.is_pending()).is_false()
	_tt.tick(1.0)
	assert_bool(_tt.is_shown()).is_false()
	_finger(p + Vector2(0, 40), false)

func test_a_drag_scroll_release_far_away_cancels_it() -> void:
	var p := _center(_button)
	_finger(p, true)
	# Lo que manda DragScroll al empezar a arrastrar una lista.
	_mouse(Vector2(-100000, -100000), false, 0)
	_tt.tick(1.0)
	assert_bool(_tt.is_shown()).is_false()
	_touch(p, false)

func test_a_second_finger_cancels_it() -> void:
	var p := _center(_button)
	_finger(p, true)
	var t := InputEventScreenTouch.new()
	t.index = 1
	t.position = _win(p + Vector2(200, 0))
	t.pressed = true
	get_viewport().push_input(t)
	_tt.tick(1.0)
	assert_bool(_tt.is_shown()).is_false()
	t.pressed = false
	get_viewport().push_input(t)
	_finger(p, false)

func test_hold_to_repeat_buttons_are_not_read() -> void:
	var p := _center(_press_button)
	_finger(p, true)
	_tt.tick(1.0)
	assert_bool(_tt.is_shown()).is_false()
	_finger(p, false)
	await await_idle_frame()
	# Actuo al tocar (en headless el boton ve el raton emulado y el toque: una
	# o dos veces), y nadie le corto la pulsacion.
	assert_int(_press_presses).is_greater_equal(1)

func test_on_pc_with_a_mouse_it_does_nothing() -> void:
	GameConfig.ui_touch_controls = "never"
	GameConfig.ui_device_profile = "pc"
	GameConfig._real_touch_seen = false
	assert_bool(_tt.active()).is_false()
	var p := _center(_button)
	_mouse(p, true, 0)
	_tt.tick(1.0)
	assert_bool(_tt.is_shown()).is_false()
	_mouse(p, false, 0)
	await await_idle_frame()
	assert_int(_presses).is_equal(1)

func test_the_bubble_never_leaves_the_screen() -> void:
	var vp := Vector2(1280, 720)
	var size := Vector2(300, 80)
	for finger in [Vector2(2, 2), Vector2(1278, 5), Vector2(640, 719), Vector2(1279, 719), Vector2(640, 360)]:
		var pos: Vector2 = TouchTooltip.bubble_position(size, finger, vp)
		assert_bool(Rect2(Vector2.ZERO, vp).encloses(Rect2(pos, size))).override_failure_message("dedo %s" % finger).is_true()
	# Con sitio, encima del dedo.
	var above: Vector2 = TouchTooltip.bubble_position(size, Vector2(640, 400), vp)
	assert_float(above.y + size.y).is_less_equal(400.0)

func test_it_finds_the_tooltip_of_a_parent() -> void:
	var holder := PanelContainer.new()
	holder.tooltip_text = "Del padre"
	holder.position = Vector2(100, 100)
	holder.size = Vector2(200, 100)
	_layer.add_child(holder)
	var inner := Label.new()
	inner.text = "hijo"
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.add_child(inner)
	await await_idle_frame()
	var hit: Control = TouchTooltip.control_at(get_tree(), _center(inner))
	assert_object(hit).is_not_null()
	assert_object(TouchTooltip.tooltip_owner(hit, _center(inner))).is_same(holder)

## La guia rapida y AYUDA lo cuentan: "manten pulsado" con el dedo, "pasa el
## raton" con raton (Tr.ti).
func test_the_quick_guide_and_the_help_index_tell_it() -> void:
	var QuickGuide := load("res://scripts/ui/QuickGuide.gd")
	var HelpCatalog := load("res://scripts/ui/HelpCatalog.gd")
	assert_bool(HelpCatalog.ENTRIES.has("guide_read")).is_true()
	assert_str(String(HelpCatalog.ENTRIES["guide_read"]["body"])).is_equal(QuickGuide.READ_HINT)
	for locale in Tr.LOCALES:
		var table: Dictionary = Tr._STRINGS[locale]
		assert_bool(table.has("QG_READ_HINT")).is_true()
		assert_bool(table.has("QG_READ_HINT_TOUCH")).is_true()
	assert_str(Tr.ti("QG_READ_HINT")).is_equal(Tr.t("QG_READ_HINT_TOUCH"))
	var g: CanvasLayer = auto_free(QuickGuide.new())
	add_child(g)
	var hint: Label = g.find_child("QuickGuideReadHint", true, false)
	assert_object(hint).is_not_null()
	assert_str(hint.text).is_equal(Tr.t("QG_READ_HINT_TOUCH"))
