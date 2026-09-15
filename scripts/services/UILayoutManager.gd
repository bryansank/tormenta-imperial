extends Node
## Provides layout positioning to UI panels based on UILayoutConfig slot assignments.
## Panels call apply_layout() to position their Controls instead of hardcoding offsets.
## Emits layout_changed when viewport resizes so panels can reposition.
##
## Apilado real (A8): un slot con `stack_after` se coloca bajo el borde inferior
## REAL del panel referido, medido tras el layout, y se vuelve a colocar cuando
## ese panel cambia de tamano, se muestra u oculta, o cambia la ventana. Los
## huecos fijos en pixeles se comian unos a otros cada vez que crecia la letra;
## esto los sustituye por una regla: "debajo del anterior, con este hueco".

signal layout_changed

var _viewport_size := Vector2(1280, 720)

## Margen libre que se deja entre un panel y el borde de pantalla al recortarlo.
const EDGE_MARGIN := 8.0

## Hueco por defecto entre un panel y el que se apila debajo.
const DEFAULT_STACK_GAP := 6.0

## Tope de niveles al resolver cadenas de apilado. La configuracion no tiene
## ciclos (hay un test que lo vigila), pero un bucle infinito en el layout
## colgaria el juego entero, asi que se corta igual.
const MAX_STACK_DEPTH := 8

## Controles ya colocados: {"id": String, "ref": WeakRef}. Se vuelven a colocar
## al cambiar el tamano de ventana (p.ej. al entrar o salir de pantalla completa)
## para que los paneles se recorten al viewport nuevo y nada se salga.
var _placed: Array[Dictionary] = []

## Ids de paneles cuyos dependientes hay que recolocar en el proximo flush.
## Se agrupan y se resuelven en diferido: `resized` salta en mitad del pase de
## layout y mover otros controles ahi mismo es pedir avisos del motor.
var _pending_restack: Dictionary = {}

## Si el menu ☰ esta desplegado. Cambia el borde inferior de la columna de
## botones y, con el, donde empieza el panel de edificio.
var _sidebar_expanded := false

func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_resized)
	_viewport_size = Vector2(get_viewport().get_visible_rect().size)
	# Apply the global UI theme so built-in controls stop looking "default".
	get_tree().root.theme = UITheme.build_global_theme()
	EventBus.sidebar_toggled.connect(_on_sidebar_toggled)

func _on_viewport_resized() -> void:
	_viewport_size = Vector2(get_viewport().get_visible_rect().size)
	_reapply_all()
	layout_changed.emit()

func _on_sidebar_toggled(is_visible: bool) -> void:
	_sidebar_expanded = is_visible
	_restack_after(UILayoutConfig.SIDEBAR_STACK_REF)

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

## El control colocado mas reciente con ese id. El mas reciente y no el primero
## porque los tests instancian el mismo panel varias veces y liberan el anterior.
func _find_placed(panel_id: String) -> Control:
	for i in range(_placed.size() - 1, -1, -1):
		var entry: Dictionary = _placed[i]
		if String(entry["id"]) != panel_id:
			continue
		var control: Variant = (entry["ref"] as WeakRef).get_ref()
		if control != null and is_instance_valid(control):
			return control as Control
	return null

func _id_of(control: Control) -> String:
	for entry in _placed:
		if (entry["ref"] as WeakRef).get_ref() == control:
			return String(entry["id"])
	return ""

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
	_watch(control)
	_place(panel_id, control)
	# Quien se apile debajo de este panel se recoloca en cuanto exista.
	_restack_after(panel_id)

## Escucha los cambios del control que mueven a quien se apila debajo. Una
## sola vez por control: apply_layout se llama varias veces sobre el mismo.
func _watch(control: Control) -> void:
	if control.has_meta("_uilm_watched"):
		return
	control.set_meta("_uilm_watched", true)
	control.resized.connect(_on_watched_changed.bind(control))
	control.visibility_changed.connect(_on_watched_changed.bind(control))

func _on_watched_changed(control: Control) -> void:
	if not is_instance_valid(control):
		return
	var panel_id := _id_of(control)
	if not panel_id.is_empty():
		_restack_after(panel_id)

## Marca a los dependientes de `ref_id` para recolocarlos en diferido.
func _restack_after(ref_id: String) -> void:
	if not _has_dependents(ref_id):
		return
	var was_empty := _pending_restack.is_empty()
	_pending_restack[ref_id] = true
	if was_empty:
		_flush_restack.call_deferred()

func _has_dependents(ref_id: String) -> bool:
	for slot_name in UILayoutConfig.SLOTS:
		if String(UILayoutConfig.SLOTS[slot_name].get("stack_after", "")) == ref_id:
			return true
	return false

## Recoloca en cascada: si el estado se mueve, el log que va debajo tambien, y
## asi hasta el final de la columna. Todo en el mismo frame, no uno por nivel.
func _flush_restack() -> void:
	var rounds := 0
	while not _pending_restack.is_empty() and rounds < MAX_STACK_DEPTH:
		rounds += 1
		var refs: Array = _pending_restack.keys()
		_pending_restack.clear()
		var alive: Array[Dictionary] = []
		for entry in _placed:
			var control: Variant = (entry["ref"] as WeakRef).get_ref()
			if control == null or not is_instance_valid(control):
				continue
			alive.append(entry)
			var panel_id := String(entry["id"])
			var slot_name: String = UILayoutConfig.PANEL_SLOTS.get(panel_id, "")
			if slot_name.is_empty():
				continue
			var after := String(UILayoutConfig.SLOTS[slot_name].get("stack_after", ""))
			if after in refs:
				_place(panel_id, control as Control)
				if _has_dependents(panel_id):
					_pending_restack[panel_id] = true
		_placed = alive
	_pending_restack.clear()

## Borde superior (en px de viewport) de un slot apilado bajo `ref_id`.
## Si el referido esta oculto o no existe, se ocupa su sitio: la columna se
## compacta en vez de dejar un agujero del tamano de un panel invisible.
func _stack_top(ref_id: String, gap: float, depth: int = 0) -> float:
	if depth > MAX_STACK_DEPTH:
		return 0.0
	if ref_id == UILayoutConfig.SIDEBAR_STACK_REF:
		return get_sidebar_bottom() + gap
	var ref := _find_placed(ref_id)
	if ref != null and ref.is_visible_in_tree():
		var rect := ref.get_global_rect()
		return rect.position.y + rect.size.y + gap
	return _slot_top(ref_id, depth + 1)

## Donde empieza un panel segun su slot: su propio apilado si lo tiene, y si no
## su ancla mas su margen.
func _slot_top(panel_id: String, depth: int = 0) -> float:
	var slot_name: String = UILayoutConfig.PANEL_SLOTS.get(panel_id, "")
	if slot_name.is_empty():
		return 0.0
	var slot: Dictionary = UILayoutConfig.SLOTS[slot_name]
	var after := String(slot.get("stack_after", ""))
	if not after.is_empty():
		return _stack_top(after, float(slot.get("gap", DEFAULT_STACK_GAP)), depth)
	var anchor: Rect2 = slot["anchor"]
	return anchor.position.y * _viewport_size.y + float(slot["margin"]["top"])

## Borde inferior de la columna de botones del menu ☰. Desplegado, cuenta todos
## los botones del orden aunque alguno este oculto por fase: es un techo, y
## un panel un poco mas abajo molesta menos que uno tapado por un boton.
func get_sidebar_bottom() -> float:
	var y := float(UILayoutConfig.SIDEBAR_FIRST_Y + UILayoutConfig.SIDEBAR_TOGGLE_SIZE)
	if _sidebar_expanded:
		var buttons := UILayoutConfig.SIDEBAR_BUTTON_ORDER.size() - 1
		if buttons > 0:
			y += float(UILayoutConfig.SIDEBAR_TOGGLE_GAP)
			y += float(buttons * UILayoutConfig.SIDEBAR_BTN_HEIGHT + (buttons - 1) * UILayoutConfig.SIDEBAR_BTN_GAP)
	return y

func is_sidebar_expanded() -> bool:
	return _sidebar_expanded

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

	# Apilado: el margen superior deja de ser un numero fijo y pasa a ser el
	# borde inferior real del panel de arriba, en coordenadas del ancla.
	var after := String(slot.get("stack_after", ""))
	if not after.is_empty():
		var top := _stack_top(after, float(slot.get("gap", DEFAULT_STACK_GAP)))
		m_top = top - anchor.position.y * _viewport_size.y

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
	var y: float = _slot_top(panel_id)
	var w: float = size.x if size.x > 0.0 else _viewport_size.x
	var h: float = size.y if size.y > 0.0 else _viewport_size.y

	return Rect2(x, y, w, h)
