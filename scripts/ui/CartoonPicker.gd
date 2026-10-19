extends HBoxContainer
## Selector del estilo nuevo (docs/28 §7): sustituye a los desplegables.
##
##   * Hasta MAX_SEGMENTS opciones cortas: pastillas en fila, la elegida azul
##     (`CartoonTheme.segmented`, pero de verdad pulsables).
##   * Mas opciones, o textos largos: un paso a paso  [◀]  Opcion  [▶]  que
##     cabe en un telefono de 640 de ancho.
##
## Habla como un OptionButton (item_selected, selected, item_count, select,
## set_item_text, get_item_text) para que Ajustes y sus pruebas no cambien de
## logica. Sin animacion: elegir cambia el estilo al instante.

signal item_selected(index: int)

const CT := preload("res://scripts/ui/CartoonTheme.gd")

## Pastillas en fila como mucho; con mas, paso a paso.
const MAX_SEGMENTS := 4
## Letras en total a partir de las cuales las pastillas ya no caben en un
## telefono y se pasa al paso a paso.
const MAX_SEGMENT_CHARS := 26

var selected := -1
var _items: Array = []
var _tips: Array = []
var _height := 48
var _role := "window"
var _stepper := false
var _value: Label
var _prev: Button
var _next: Button

## `options`: los textos; `tips` (opcional): el globo de cada uno al mantener.
func setup(options: Array, p_selected: int, height: int = 48, role: String = "window",
		force_stepper: bool = false, tips: Array = []) -> void:
	_items = options.duplicate()
	_tips = tips.duplicate()
	_height = height
	_role = role
	selected = clampi(p_selected, -1, _items.size() - 1)
	var chars := 0
	for o in _items:
		chars += String(o).length()
	_stepper = force_stepper or _items.size() > MAX_SEGMENTS or chars > MAX_SEGMENT_CHARS
	add_theme_constant_override("separation", 6)
	alignment = BoxContainer.ALIGNMENT_END
	_rebuild()

var item_count: int:
	get:
		return _items.size()

func is_stepper() -> bool:
	return _stepper

func select(index: int) -> void:
	if index < 0 or index >= _items.size():
		return
	selected = index
	_rebuild()

func get_item_text(index: int) -> String:
	return String(_items[index]) if index >= 0 and index < _items.size() else ""

func set_item_text(index: int, text_s: String) -> void:
	if index < 0 or index >= _items.size():
		return
	_items[index] = text_s
	_rebuild()

## Pulsar una opcion (o una flecha): la elige y avisa, como un OptionButton.
func pick(index: int) -> void:
	if index < 0 or index >= _items.size():
		return
	selected = index
	# Diferido: la pastilla pulsada no se puede quitar dentro de su propia senal.
	_rebuild.call_deferred()
	item_selected.emit(index)

func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if _stepper:
		_build_stepper()
	else:
		_build_segments()

func _build_segments() -> void:
	for i in _items.size():
		var b := CT.pill_button(String(_items[i]), "", "info" if i == selected else "secondary", _height, _role, "body")
		b.name = "Opt%d" % i
		if i < _tips.size():
			b.tooltip_text = String(_tips[i])
		b.pressed.connect(pick.bind(i))
		add_child(b)

func _build_stepper() -> void:
	_prev = CT.round_button("back", "secondary", _height, "", _role) as Button
	_prev.name = "Prev"
	_prev.disabled = selected <= 0
	_prev.pressed.connect(func(): pick(maxi(0, selected - 1)))
	add_child(_prev)
	var well := PanelContainer.new()
	var ws := CT.well_style(_role, int(_height * 0.5), 4)
	ws.content_margin_left = 12
	ws.content_margin_right = 12
	well.add_theme_stylebox_override("panel", ws)
	well.custom_minimum_size = Vector2(0, _height)
	well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	well.mouse_filter = Control.MOUSE_FILTER_PASS
	_value = CT.label(get_item_text(selected), "body", CT.text(_role))
	_value.name = "Value"
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_value.clip_text = true
	_value.custom_minimum_size = Vector2(96, 0)
	well.add_child(_value)
	if selected >= 0 and selected < _tips.size():
		well.tooltip_text = String(_tips[selected])
	add_child(well)
	_next = CT.round_button("next", "secondary", _height, "", _role) as Button
	_next.name = "Next"
	_next.disabled = selected >= _items.size() - 1
	_next.pressed.connect(func(): pick(mini(_items.size() - 1, selected + 1)))
	add_child(_next)
