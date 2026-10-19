extends GdUnitTestSuite
## Arrastrar para desplazar (DragScroll): una lista llena de botones se mueve
## con el dedo empiece donde empiece el gesto, arrastrar no pulsa el boton de
## debajo, y la rueda desplaza la lista en vez de tocar lo que haya dentro.
## Un deslizador solo cambia si el gesto empieza en su bolita/carril y va a lo
## largo de el; en vertical desplaza la lista (bug de Bryan, 2026-10-19).

const DragScroll := preload("res://scripts/ui/DragScroll.gd")

var _layer: CanvasLayer
var _scroll: ScrollContainer
var _presses := 0
var _slider: HSlider
var _strip: ScrollContainer
var _strip_presses := 0

func before_test() -> void:
	_presses = 0
	_strip_presses = 0
	_layer = CanvasLayer.new()
	add_child(_layer)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(10, 10)
	_scroll.size = Vector2(200, 200)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_layer.add_child(_scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(180, 0)
	_scroll.add_child(box)
	# Arriba del todo: un deslizador y una tira horizontal de pastillas, como en
	# Ajustes y en CONSTRUIR.
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.value = 0.5
	_slider.custom_minimum_size = Vector2(180, 40)
	box.add_child(_slider)
	_strip = ScrollContainer.new()
	_strip.custom_minimum_size = Vector2(180, 40)
	_strip.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_strip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	box.add_child(_strip)
	var row := HBoxContainer.new()
	_strip.add_child(row)
	for i in 8:
		var pill := Button.new()
		pill.text = "P%d" % i
		pill.custom_minimum_size = Vector2(70, 40)
		pill.pressed.connect(func(): _strip_presses += 1)
		row.add_child(pill)
	for i in 20:
		var b := Button.new()
		b.text = "Boton %d" % i
		b.custom_minimum_size = Vector2(180, 40)
		b.pressed.connect(func(): _presses += 1)
		box.add_child(b)
	await await_idle_frame()
	DragScroll.attach(_scroll)
	DragScroll.attach(_strip)
	await await_idle_frame()

func after_test() -> void:
	DragScroll.cancel_gesture()
	if is_instance_valid(_layer):
		_layer.free()

## push_input quiere pixeles de ventana; las pruebas piensan en el lienzo.
func _win(pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * pos

func _motion(pos: Vector2, held: bool) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _win(pos)
	e.global_position = _win(pos)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	get_viewport().push_input(e)

func _button(pos: Vector2, pressed: bool, index := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.position = _win(pos)
	e.global_position = _win(pos)
	e.button_index = index
	e.pressed = pressed
	e.factor = 1.0
	if pressed and index == MOUSE_BUTTON_LEFT:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(e)

func test_every_scroll_container_gets_one() -> void:
	assert_object(_scroll.get_node_or_null("DragScroll")).is_not_null()
	DragScroll.attach(_scroll)
	var count := 0
	for c in _scroll.get_children(true):
		if c.name == "DragScroll":
			count += 1
	assert_int(count).is_equal(1)

func test_dragging_over_buttons_scrolls_and_does_not_press() -> void:
	var start := Vector2(100, 150)
	_motion(start, false)
	_button(start, true)
	for i in 6:
		_motion(start - Vector2(0, 20 * (i + 1)), true)
	_button(start - Vector2(0, 120), false)
	await await_idle_frame()
	assert_int(_scroll.scroll_vertical).is_greater(60)
	assert_int(_presses).is_equal(0)

func test_a_tap_still_presses_the_button() -> void:
	var p := _center(_button_n(0))
	_motion(p, false)
	_button(p, true)
	_button(p, false)
	await await_idle_frame()
	assert_int(_presses).is_equal(1)
	assert_int(_scroll.scroll_vertical).is_equal(0)

func test_the_wheel_scrolls_the_list() -> void:
	var p := Vector2(100, 100)
	_motion(p, false)
	_button(p, true, MOUSE_BUTTON_WHEEL_DOWN)
	await await_idle_frame()
	assert_int(_scroll.scroll_vertical).is_greater(0)

func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

func _button_n(n: int) -> Button:
	var box := _scroll.get_child(0)
	return box.get_child(n + 2) as Button

## Un arrastre entero con el raton: pulsar en `from`, `steps` movimientos hasta
## `to`, soltar alli.
func _mouse_drag(from: Vector2, to: Vector2, steps := 6) -> void:
	_motion(from, false)
	_button(from, true)
	for i in steps:
		_motion(from.lerp(to, float(i + 1) / steps), true)
	_button(to, false)

## Lo mismo con el dedo, como lo fabrica Godot en un movil: el toque pasa por
## Input y el raton emulado sale de el.
func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = _win(pos)
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func _finger_move(p: Vector2, rel: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = _win(p)
	d.relative = rel
	Input.parse_input_event(d)
	Input.flush_buffered_events()

func _finger_drag(from: Vector2, to: Vector2, steps := 6) -> void:
	_touch(from, true)
	var last := from
	for i in steps:
		var p := from.lerp(to, float(i + 1) / steps)
		_finger_move(p, p - last)
		last = p
	_touch(to, false)

func test_a_press_waits_until_it_is_a_tap() -> void:
	var b := _button_n(1)
	var p := _center(b)
	_motion(p, false)
	_button(p, true)
	# Pulsado pero quieto: el boton aun no tiene la pulsacion (puede ser un
	# arrastre) y no se ha disparado.
	assert_bool(b.is_pressed()).is_false()
	assert_int(_presses).is_equal(0)
	_button(p, false)
	await await_idle_frame()
	assert_int(_presses).is_equal(1)

func test_a_small_wobble_is_still_a_tap() -> void:
	var p := _center(_button_n(1))
	_mouse_drag(p, p + Vector2(3, 3), 2)
	await await_idle_frame()
	assert_int(_presses).is_equal(1)
	assert_int(_scroll.scroll_vertical).is_equal(0)

func test_a_short_drag_inside_one_button_does_not_press_it() -> void:
	# Arrastrar menos que el alto del boton, sin salir de el: antes pulsaba si
	# el dedo no llegaba a salir del boton.
	var b := _button_n(1)
	var p := _center(b) + Vector2(0, 12)
	_mouse_drag(p, p - Vector2(0, 24), 3)
	await await_idle_frame()
	assert_int(_presses).is_equal(0)
	assert_int(_scroll.scroll_vertical).is_greater(10)

func test_dragging_vertically_over_a_slider_scrolls_and_keeps_its_value() -> void:
	var p := _center(_slider) + Vector2(40, 0)
	_mouse_drag(p, p - Vector2(0, 100))
	await await_idle_frame()
	assert_float(_slider.value).is_equal_approx(0.5, 0.001)
	assert_int(_scroll.scroll_vertical).is_greater(60)

func test_dragging_vertically_over_a_slider_with_the_finger_keeps_its_value() -> void:
	var p := _center(_slider) - Vector2(50, 0)
	_finger_drag(p, p - Vector2(0, 100))
	await await_idle_frame()
	assert_float(_slider.value).is_equal_approx(0.5, 0.001)
	assert_int(_scroll.scroll_vertical).is_greater(60)

func test_dragging_the_knob_sideways_moves_the_slider() -> void:
	var p := _center(_slider)
	_mouse_drag(p, p + Vector2(60, 2))
	await await_idle_frame()
	assert_float(_slider.value).is_greater(0.6)
	assert_int(_scroll.scroll_vertical).is_equal(0)

func test_dragging_the_knob_sideways_with_the_finger_moves_the_slider() -> void:
	var p := _center(_slider)
	_finger_drag(p, p - Vector2(60, 0))
	await await_idle_frame()
	assert_float(_slider.value).is_less(0.4)
	assert_int(_scroll.scroll_vertical).is_equal(0)

func test_the_slider_band_is_its_knob_and_rail() -> void:
	var r := _slider.get_global_rect()
	assert_bool(DragScroll.on_slider_track(_slider, r.get_center())).is_true()
	assert_bool(DragScroll.on_slider_track(_slider, r.get_center() + Vector2(0, 60))).is_false()

func test_dragging_over_buttons_with_the_finger_scrolls_and_does_not_press() -> void:
	var p := _center(_button_n(1))
	_finger_drag(p, p - Vector2(0, 120))
	await await_idle_frame()
	assert_int(_presses).is_equal(0)
	assert_int(_scroll.scroll_vertical).is_greater(60)

func test_a_finger_tap_presses() -> void:
	var p := _center(_button_n(1))
	_touch(p, true)
	_touch(p, false)
	await await_idle_frame()
	assert_int(_presses).is_equal(1)

func test_vertical_drag_over_a_horizontal_strip_scrolls_the_outer_list() -> void:
	var p := _strip.get_global_rect().get_center()
	_mouse_drag(p, p - Vector2(0, 100))
	await await_idle_frame()
	assert_int(_strip_presses).is_equal(0)
	assert_int(_scroll.scroll_vertical).is_greater(60)
	assert_int(_strip.scroll_horizontal).is_equal(0)

func test_sideways_drag_over_the_strip_scrolls_the_strip() -> void:
	var p := _strip.get_global_rect().get_center()
	_mouse_drag(p, p - Vector2(100, 0))
	await await_idle_frame()
	assert_int(_strip_presses).is_equal(0)
	assert_int(_strip.scroll_horizontal).is_greater(60)
	assert_int(_scroll.scroll_vertical).is_equal(0)

func test_a_tap_on_a_strip_pill_presses_it() -> void:
	var p := _strip.get_global_rect().get_center()
	_motion(p, false)
	_button(p, true)
	_button(p, false)
	await await_idle_frame()
	assert_int(_strip_presses).is_equal(1)

func test_starting_to_scroll_cancels_hold_to_read() -> void:
	var tt: Node = InputService.touch_tooltip()
	var saved: String = GameConfig.ui_touch_controls
	GameConfig.ui_touch_controls = "always"
	var b := _button_n(1)
	b.tooltip_text = "Leer"
	var p := _center(b)
	_touch(p, true)
	var armed: bool = tt.is_pending()
	# Movimientos cortos (6 px): ninguno pasa por si solo el umbral del globo,
	# pero la lista empieza a desplazarse y lo desarma.
	for i in 4:
		_finger_move(p - Vector2(0, 6 * (i + 1)), Vector2(0, -6))
	var after: bool = tt.is_pending()
	tt.tick(1.0)
	var shown: bool = tt.is_shown()
	_touch(p - Vector2(0, 24), false)
	GameConfig.ui_touch_controls = saved
	await await_idle_frame()
	if armed:
		assert_bool(after).is_false()
	assert_bool(shown).is_false()
	assert_int(_presses).is_equal(0)

func test_holding_to_read_inside_a_list_does_not_press() -> void:
	var tt: Node = InputService.touch_tooltip()
	var saved: String = GameConfig.ui_touch_controls
	GameConfig.ui_touch_controls = "always"
	var b := _button_n(1)
	b.tooltip_text = "Leer"
	var p := _center(b)
	_touch(p, true)
	var armed: bool = tt.is_pending()
	tt.tick(1.0)
	var shown: bool = tt.is_shown()
	_touch(p, false)
	GameConfig.ui_touch_controls = saved
	await await_idle_frame()
	if armed:
		assert_bool(shown).is_true()
		assert_int(_presses).is_equal(0)
	assert_int(DragScroll.gesture_mode()).is_equal(0)

## Si la plataforma manda el toque ANTES que el raton emulado, el arrastre
## tampoco pulsa: el dedo se reconoce por su posicion.
func test_touch_before_the_emulated_mouse_still_does_not_press() -> void:
	var p := _center(_button_n(1))
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = _win(p)
	t.pressed = true
	get_viewport().push_input(t)
	_motion(p, false)
	_button(p, true)
	for i in 6:
		var q := p - Vector2(0, 20 * (i + 1))
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = _win(q)
		d.relative = Vector2(0, -20)
		get_viewport().push_input(d)
		_motion(q, true)
	_button(p - Vector2(0, 120), false)
	t.pressed = false
	t.position = _win(p - Vector2(0, 120))
	get_viewport().push_input(t)
	await await_idle_frame()
	assert_int(_presses).is_equal(0)
	assert_int(_scroll.scroll_vertical).is_greater(60)

## Una lista que cabe entera tampoco deja que un arrastre pulse.
func test_a_list_that_fits_still_does_not_press_on_drag() -> void:
	_scroll.size = Vector2(200, 2000)
	await await_idle_frame()
	var p := _center(_button_n(1))
	_mouse_drag(p, p + Vector2(0, 30), 3)
	await await_idle_frame()
	assert_int(_presses).is_equal(0)
	_motion(p, false)
	_button(p, true)
	_button(p, false)
	await await_idle_frame()
	assert_int(_presses).is_equal(1)
