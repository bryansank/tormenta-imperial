extends Node
## Provides layout positioning to UI panels based on UILayoutConfig slot assignments.
## Panels call apply_layout() to position their Controls instead of hardcoding offsets.
## Emits layout_changed when viewport resizes so panels can reposition.

signal layout_changed

var _viewport_size := Vector2(1280, 720)

## Margen libre que se deja entre un panel y el borde de pantalla al recortarlo.
const EDGE_MARGIN := 8.0

## Controles ya colocados: {"id": String, "ref": WeakRef}. Se vuelven a colocar
## al cambiar el tamano de ventana (p.ej. al entrar o salir de pantalla completa)
## para que los paneles se recorten al viewport nuevo y nada se salga.
var _placed: Array[Dictionary] = []

func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_resized)
	_viewport_size = Vector2(get_viewport().get_visible_rect().size)
	# Apply the global UI theme so built-in controls stop looking "default".
	get_tree().root.theme = UITheme.build_global_theme()

func _on_viewport_resized() -> void:
	_viewport_size = Vector2(get_viewport().get_visible_rect().size)
	_reapply_all()
	layout_changed.emit()

func _reapply_all() -> void:
	var alive: Array[Dictionary] = []
	for entry in _placed:
		var ref: WeakRef = entry["ref"]
		var control: Variant = ref.get_ref()
		if control == null or not is_instance_valid(control):
			continue
		alive.append(entry)
		_place(String(entry["id"]), control as Control)
	_placed = alive

func _remember(panel_id: String, control: Control) -> void:
	for entry in _placed:
		var ref: WeakRef = entry["ref"]
		if ref.get_ref() == control:
			entry["id"] = panel_id
			return
	_placed.append({"id": panel_id, "ref": weakref(control)})

## Recorta el tamano pedido al viewport actual. Sin esto, con la tipografia
## grande y una ventana estrecha (movil 400x720) los modales se salen de pantalla.
func _clamp_to_viewport(size: Vector2) -> Vector2:
	var max_w: float = maxf(_viewport_size.x - EDGE_MARGIN * 2.0, 120.0)
	var max_h: float = maxf(_viewport_size.y - EDGE_MARGIN * 2.0, 120.0)
	if size.x > 0.0:
		size.x = minf(size.x, max_w)
	if size.y > 0.0:
		size.y = minf(size.y, max_h)
	return size

## Applies anchor, offset, grow direction and minimum size to a Control
## based on the slot assigned to panel_id in UILayoutConfig.
func apply_layout(panel_id: String, control: Control) -> void:
	_remember(panel_id, control)
	_place(panel_id, control)

func _place(panel_id: String, control: Control) -> void:
	var slot_name: String = UILayoutConfig.PANEL_SLOTS.get(panel_id, "")
	if slot_name.is_empty():
		push_warning("UILayoutManager: No slot assigned for '%s'" % panel_id)
		return

	var slot: Dictionary = UILayoutConfig.SLOTS[slot_name]
	var anchor: Rect2 = slot["anchor"]
	var margin: Dictionary = slot["margin"]
	var grow_h: int = slot["grow_h"]
	var grow_v: int = slot["grow_v"]
	var size: Vector2 = _clamp_to_viewport(UILayoutConfig.PANEL_SIZES.get(panel_id, slot["max_size"]))

	# Set anchors (Rect2: position = (left, top), size = (right, bottom))
	control.anchor_left = anchor.position.x
	control.anchor_top = anchor.position.y
	control.anchor_right = anchor.size.x
	control.anchor_bottom = anchor.size.y

	# Set grow directions
	control.grow_horizontal = grow_h
	control.grow_vertical = grow_v

	# When anchors span a range (e.g., 0 to 1), offsets are insets from edges.
	# When anchors are at a single point, offsets position the control relative to that point.
	var h_spans: bool = anchor.position.x != anchor.size.x
	var v_spans: bool = anchor.position.y != anchor.size.y

	var m_left: float = margin["left"]
	var m_right: float = margin["right"]
	var m_top: float = margin["top"]
	var m_bottom: float = margin["bottom"]

	# Horizontal offsets
	if h_spans:
		control.offset_left = m_left
		if size.x > 0:
			control.offset_right = m_left + size.x
		else:
			control.offset_right = -m_right
	else:
		_apply_h_point(control, grow_h, m_left, m_right, size.x)

	# Vertical offsets
	if v_spans:
		control.offset_top = m_top
		control.offset_bottom = -m_bottom
	else:
		_apply_v_point(control, grow_v, m_top, m_bottom, size.y)

	# Set minimum size (ya recortado al viewport)
	if size.x > 0:
		control.custom_minimum_size.x = size.x
	if size.y > 0:
		control.custom_minimum_size.y = size.y

## Horizontal offset when anchor is a single point (left == right)
func _apply_h_point(control: Control, grow_h: int, m_left: float, m_right: float, width: float) -> void:
	match grow_h:
		Control.GROW_DIRECTION_END:
			control.offset_left = m_left
			control.offset_right = m_left + (width if width > 0.0 else 0.0)
		Control.GROW_DIRECTION_BEGIN:
			var w: float = width if width > 0.0 else 0.0
			control.offset_left = -(m_right + w)
			control.offset_right = -m_right
		Control.GROW_DIRECTION_BOTH:
			var half_w: float = width / 2.0 if width > 0.0 else 0.0
			control.offset_left = -half_w
			control.offset_right = half_w

## Vertical offset when anchor is a single point (top == bottom)
func _apply_v_point(control: Control, grow_v: int, m_top: float, m_bottom: float, height: float) -> void:
	match grow_v:
		Control.GROW_DIRECTION_END:
			control.offset_top = m_top
			control.offset_bottom = m_top + (height if height > 0.0 else 0.0)
		Control.GROW_DIRECTION_BEGIN:
			var h: float = height if height > 0.0 else 0.0
			control.offset_top = -(m_bottom + h)
			control.offset_bottom = -m_bottom
		Control.GROW_DIRECTION_BOTH:
			var half_h: float = height / 2.0 if height > 0.0 else 0.0
			control.offset_top = -half_h
			control.offset_bottom = half_h

## Returns the y-offset for a sidebar button based on its position in the stacking order.
func get_sidebar_button_offset(panel_id: String) -> float:
	var index: int = UILayoutConfig.SIDEBAR_BUTTON_ORDER.find(panel_id)
	if index < 0:
		return float(UILayoutConfig.SIDEBAR_FIRST_Y)
	if index == 0:
		return float(UILayoutConfig.SIDEBAR_FIRST_Y)
	# First item is the toggle (36px + 6px gap), rest are buttons (38px + 4px gap)
	var y: float = float(UILayoutConfig.SIDEBAR_FIRST_Y + UILayoutConfig.SIDEBAR_TOGGLE_SIZE + UILayoutConfig.SIDEBAR_TOGGLE_GAP)
	for i in range(1, index):
		y += float(UILayoutConfig.SIDEBAR_BTN_HEIGHT + UILayoutConfig.SIDEBAR_BTN_GAP)
	return y

## Returns pixel Rect2 for a panel's layout (for manual calculations).
func get_layout_rect(panel_id: String) -> Rect2:
	var slot_name: String = UILayoutConfig.PANEL_SLOTS.get(panel_id, "")
	if slot_name.is_empty():
		return Rect2(0, 0, _viewport_size.x, _viewport_size.y)

	var slot: Dictionary = UILayoutConfig.SLOTS[slot_name]
	var anchor: Rect2 = slot["anchor"]
	var margin: Dictionary = slot["margin"]
	var size: Vector2 = _clamp_to_viewport(UILayoutConfig.PANEL_SIZES.get(panel_id, slot["max_size"]))

	var x: float = anchor.position.x * _viewport_size.x + float(margin["left"])
	var y: float = anchor.position.y * _viewport_size.y + float(margin["top"])
	var w: float = size.x if size.x > 0.0 else _viewport_size.x
	var h: float = size.y if size.y > 0.0 else _viewport_size.y

	return Rect2(x, y, w, h)
