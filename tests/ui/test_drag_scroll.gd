extends GdUnitTestSuite
## Arrastrar para desplazar (DragScroll): una lista llena de botones se mueve
## con el dedo empiece donde empiece el gesto, arrastrar no pulsa el boton de
## debajo, y la rueda desplaza la lista en vez de tocar lo que haya dentro.

const DragScroll := preload("res://scripts/ui/DragScroll.gd")

var _layer: CanvasLayer
var _scroll: ScrollContainer
var _presses := 0

func before_test() -> void:
	_presses = 0
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
	for i in 20:
		var b := Button.new()
		b.text = "Boton %d" % i
		b.custom_minimum_size = Vector2(180, 40)
		b.pressed.connect(func(): _presses += 1)
		box.add_child(b)
	await await_idle_frame()
	DragScroll.attach(_scroll)
	await await_idle_frame()

func after_test() -> void:
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
	var p := Vector2(100, 30)
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
