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

## Recoloca todo contra el lienzo actual. DeviceProfile lo llama al cambiar la
## escala de interfaz (content_scale_factor no siempre avisa size_changed).
func refresh_viewport() -> void:
	_on_viewport_resized()

func _on_viewport_resized() -> void:
	_viewport_size = Vector2(get_viewport().get_visible_rect().size)
	_column_narrow_state = is_column_narrow()
	_reapply_all()
	# Al cruzar el umbral de pantalla estrecha cambian las cadenas de apilado:
	# se recoloca a todos los que cuelgan de alguien, no solo a los de siempre.
	for entry in _placed:
		_restack_after(String(entry["id"]))
	layout_changed.emit()

## Pantalla estrecha (movil en vertical): la columna central (Tormenta y
## objetivo) no cabe entre la izquierda y el menu ☰, asi que baja a la columna
## izquierda. Ver UILayoutConfig.NARROW_SLOTS.
func is_narrow() -> bool:
	return _viewport_size.x < UILayoutConfig.NARROW_WIDTH

## La columna central no cabe entre la izquierda y el menu ☰ (tablet 4:3, o
## cualquier lienzo estrecho por la escala de interfaz): baja a la izquierda.
## Tambien cuando la columna izquierda REAL es mas ancha de lo previsto (cuatro
## recursos y el LIMPIAR de desarrollo, letra grande): se mide lo que ocupan
## recursos y poblacion mas la pausa que va a su derecha, no el slot.
func is_column_narrow() -> bool:
	if _viewport_size.x < UILayoutConfig.COLUMN_NARROW_WIDTH:
		return true
	# El objetivo (el mas ancho) sube a la fila de arriba cuando la Tormenta
	# esta en calma, asi que tiene que librar tambien la pausa.
	var center_left := _viewport_size.x * 0.5 - UILayoutConfig.CENTER_COLUMN_HALF_WIDTH
	return center_left < left_column_right() + UILayoutConfig.PAUSE_RESERVE + UILayoutConfig.COLUMN_GAP

## Borde derecho real de la columna izquierda: recursos y poblacion (los que no
## se hayan movido a mano). Sin contar la pausa, que va a su derecha.
func left_column_right() -> float:
	var right := float(UILayoutConfig.SLOTS["top_left"]["margin"]["left"] + UILayoutConfig.SLOTS["top_left"]["max_size"].x)
	for id in UILayoutConfig.LEFT_COLUMN_IDS:
		if has_user_offset(id):
			continue
		var c := _find_placed(id)
		if c != null and c.is_visible_in_tree():
			right = maxf(right, c.get_global_rect().end.x)
	return right

## Donde va el boton de pausa: a la derecha del ancho REAL de los recursos (en
## su fila), no en una x fija que cuatro recursos y LIMPIAR ya pasaban.
func pause_button_position() -> Vector2:
	var res := _find_placed("ResourceHUD")
	if res != null and res.is_visible_in_tree():
		var r := res.get_global_rect()
		return Vector2(r.end.x + UILayoutConfig.PAUSE_GAP, r.position.y)
	var slot: Dictionary = UILayoutConfig.SLOTS["top_left"]
	return Vector2(float(slot["margin"]["left"] + slot["max_size"].x) + UILayoutConfig.PAUSE_GAP, float(slot["margin"]["top"]))

## Emitida cuando un panel colocado cambia de tamano o de visibilidad. La pausa
## la usa para ir siempre a la derecha del ancho REAL de los recursos.
signal panel_rect_changed(panel_id: String)

var _column_narrow_state := false

## Si la columna izquierda crecio o encogio lo bastante para cambiar donde va
## la central, se recoloca todo (en diferido: estamos dentro de un resized).
func _check_column_state() -> void:
	var now := is_column_narrow()
	if now == _column_narrow_state:
		return
	_column_narrow_state = now
	_reapply_all()
	for entry in _placed:
		_restack_after(String(entry["id"]))
	layout_changed.emit()

## La definicion del slot que vale AHORA: la base, con lo que cambie en
## pantalla estrecha encima. Todo el manager lee los slots por aqui.
func get_slot(slot_name: String) -> Dictionary:
	var base: Dictionary = UILayoutConfig.SLOTS.get(slot_name, {})
	var override: Dictionary = {}
	if is_narrow():
		override = UILayoutConfig.NARROW_SLOTS.get(slot_name, {})
	elif is_column_narrow():
		if slot_name in UILayoutConfig.COLUMN_SLOTS:
			override = UILayoutConfig.NARROW_SLOTS.get(slot_name, {})
		override = UILayoutConfig.COLUMN_NARROW_SLOTS.get(slot_name, override)
	if override.is_empty():
		return base
	var merged := base.duplicate()
	merged.merge(override, true)
	return merged

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
		panel_rect_changed.emit(panel_id)
		if panel_id in UILayoutConfig.LEFT_COLUMN_IDS:
			_check_column_state.call_deferred()
		# Un panel movido que crece (log abierto, texto largo) no se sale.
		if has_user_offset(panel_id):
			_clamp_on_screen.call_deferred(control)

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
		if String(get_slot(slot_name).get("stack_after", "")) == ref_id:
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
			var after := String(get_slot(slot_name).get("stack_after", ""))
			if after in refs:
				_place(panel_id, control as Control)
				if _has_dependents(panel_id):
					_pending_restack[panel_id] = true
		_placed = alive
	_pending_restack.clear()

## Borde superior (en px de viewport) de un slot apilado bajo `ref_id`.
## Si el referido esta oculto o no existe, se ocupa su sitio: la columna se
## compacta en vez de dejar un agujero del tamano de un panel invisible.
func _stack_top(ref_id: String, gap: float, depth: int = 0, follow_moved: bool = false) -> float:
	if depth > MAX_STACK_DEPTH:
		return 0.0
	if ref_id == UILayoutConfig.SIDEBAR_STACK_REF:
		return get_sidebar_bottom() + gap
	# Un panel que el jugador saco de su columna deja el hueco libre: quien iba
	# debajo sube a ocupar su sitio, como si estuviera oculto.
	# Salvo los globos de ayuda (follow_moved): explican ese panel y lo siguen.
	if has_user_offset(ref_id) and not follow_moved:
		return _slot_top(ref_id, depth + 1)
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
	var slot: Dictionary = get_slot(slot_name)
	var after := String(slot.get("stack_after", ""))
	if not after.is_empty():
		return _stack_top(after, float(slot.get("gap", DEFAULT_STACK_GAP)), depth, bool(slot.get("follow_moved", false)))
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

## El boton "☰ MENÚ" (PauseMenu, capa 30) vive arriba a la derecha y queda por
## encima de cualquier ventana. Una ventana centrada tan grande que llega debajo
## de el (tablet: la lista de CONSTRUIR ocupa casi toda la pantalla) perdia su X
## tapada por el boton. Se acorta por arriba y por abajo lo justo para que su
## cabecera empiece debajo del boton. Devuelve el tamano ya corregido.
const MENU_BUTTON_FALLBACK_W := 150.0
const MENU_BUTTON_MARGIN := 10.0
const MENU_BUTTON_GAP := 6.0

func clear_menu_button(size: Vector2) -> Vector2:
	if size.x <= 0.0 or size.y <= 0.0:
		return size
	var btn_rect := Rect2(_viewport_size.x - MENU_BUTTON_MARGIN - MENU_BUTTON_FALLBACK_W,
		MENU_BUTTON_MARGIN, MENU_BUTTON_FALLBACK_W, float(UITheme.MIN_BTN_H))
	if is_inside_tree():
		var btn := get_tree().get_first_node_in_group("hud_menu_button") as Control
		if btn != null and is_instance_valid(btn) and btn.size.x > 0.0:
			btn_rect = btn.get_global_rect()
	var right := (_viewport_size.x + size.x) * 0.5
	var top := (_viewport_size.y - size.y) * 0.5
	var band := btn_rect.end.y + MENU_BUTTON_GAP
	if right > btn_rect.position.x and top < band:
		size.y = maxf(_viewport_size.y - 2.0 * band, 120.0)
	return size

func _place(panel_id: String, control: Control) -> void:
	var slot_name: String = UILayoutConfig.PANEL_SLOTS.get(panel_id, "")
	if slot_name.is_empty():
		push_warning("UILayoutManager: No slot assigned for '%s'" % panel_id)
		return

	var slot: Dictionary = get_slot(slot_name)
	var anchor: Rect2 = slot["anchor"]
	var margin: Dictionary = slot["margin"]
	var grow_h: int = slot["grow_h"]
	var grow_v: int = slot["grow_v"]
	var size: Vector2 = _clamp_to_viewport(UILayoutConfig.PANEL_SIZES.get(panel_id, slot["max_size"]))
	if slot_name == "center_modal":
		size = clear_menu_button(size)

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
		var top := _stack_top(after, float(slot.get("gap", DEFAULT_STACK_GAP)), 0, bool(slot.get("follow_moved", false)))
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

	# Disposicion del jugador (Editar disposicion): el slot es la posicion de
	# serie y el desplazamiento guardado se suma encima. Luego se recorta a la
	# pantalla, que con otra ventana el mismo desplazamiento podria sacarlo.
	var user := get_user_offset(panel_id)
	if user != Vector2.ZERO:
		control.offset_left += user.x
		control.offset_right += user.x
		control.offset_top += user.y
		control.offset_bottom += user.y
		_clamp_on_screen.call_deferred(control)

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

	var slot: Dictionary = get_slot(slot_name)
	var anchor: Rect2 = slot["anchor"]
	var margin: Dictionary = slot["margin"]
	var size: Vector2 = _clamp_to_viewport(UILayoutConfig.PANEL_SIZES.get(panel_id, slot["max_size"]))

	var x: float = anchor.position.x * _viewport_size.x + float(margin["left"])
	var y: float = _slot_top(panel_id)
	var w: float = size.x if size.x > 0.0 else _viewport_size.x
	var h: float = size.y if size.y > 0.0 else _viewport_size.y

	return Rect2(x, y, w, h)

# ══════════════════════════════════════
# DISPOSICION DEL JUGADOR (paneles movibles, docs/21)
# ══════════════════════════════════════
# Desplazamientos en px de lienzo sobre la posicion de serie de cada slot,
# guardados en GameConfig.ui_layout por perfil de dispositivo y proporcion de
# ventana (DeviceProfile.layout_key): mover el HUD en la tablet no lo mueve en
# el PC, ni lo que vale en 16:9 se aplica a 4:3.

## Rejilla a la que se ajusta un panel arrastrado, y distancia a la que se
## pega a un borde de la pantalla.
const SNAP_GRID := 8.0
const SNAP_EDGE := 16.0

signal user_layout_changed

var _editor: CanvasLayer = null

func layout_key() -> String:
	var dp := get_node_or_null("/root/DeviceProfile")
	if dp != null and dp.has_method("layout_key"):
		return dp.layout_key()
	return "pc|16:9"

func _user_layout() -> Dictionary:
	var d: Variant = GameConfig.ui_layout.get(layout_key(), {})
	return d if d is Dictionary else {}

func get_user_offset(panel_id: String) -> Vector2:
	var v: Variant = _user_layout().get(panel_id, null)
	if v is Vector2:
		return v
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO

func has_user_offset(panel_id: String) -> bool:
	return get_user_offset(panel_id) != Vector2.ZERO

## Fija el desplazamiento de un panel y lo recoloca. `persist` false sirve para
## el arrastre en vivo: se guarda una sola vez al soltar.
func set_user_offset(panel_id: String, offset: Vector2, persist: bool = true) -> void:
	var key := layout_key()
	var d: Dictionary = _user_layout().duplicate()
	if offset.length() < 0.5:
		d.erase(panel_id)
	else:
		d[panel_id] = [roundf(offset.x), roundf(offset.y)]
	if d.is_empty():
		GameConfig.ui_layout.erase(key)
	else:
		GameConfig.ui_layout[key] = d
	var control := _find_placed(panel_id)
	if control != null:
		_place(panel_id, control)
		_restack_after(panel_id)
	if persist:
		GameConfig.save_user_settings()
		user_layout_changed.emit()

## "Restablecer disposicion": borra lo movido en este perfil y proporcion.
func reset_user_layout() -> void:
	GameConfig.ui_layout.erase(layout_key())
	GameConfig.save_user_settings()
	_reapply_all()
	for entry in _placed:
		_restack_after(String(entry["id"]))
	user_layout_changed.emit()

func placed_control(panel_id: String) -> Control:
	return _find_placed(panel_id)

## Rectangulo en pantalla que ocuparia `rect` desplazado para no salirse (con
## EDGE_MARGIN de aire). Puro: el editor y el recorte lo comparten.
static func clamp_rect_to(rect: Rect2, viewport: Vector2, margin: float = EDGE_MARGIN) -> Vector2:
	var shift := Vector2.ZERO
	if rect.size.x + margin * 2.0 <= viewport.x:
		if rect.position.x < margin:
			shift.x = margin - rect.position.x
		elif rect.end.x > viewport.x - margin:
			shift.x = viewport.x - margin - rect.end.x
	else:
		shift.x = margin - rect.position.x
	if rect.size.y + margin * 2.0 <= viewport.y:
		if rect.position.y < margin:
			shift.y = margin - rect.position.y
		elif rect.end.y > viewport.y - margin:
			shift.y = viewport.y - margin - rect.end.y
	else:
		shift.y = margin - rect.position.y
	return shift

## Ajuste de un desplazamiento arrastrado: a la rejilla, y pegado al borde si
## el panel queda a menos de SNAP_EDGE de el. Puro.
static func snap_offset(offset: Vector2, rect_at_offset: Rect2, viewport: Vector2) -> Vector2:
	var snapped_offset := Vector2(snappedf(offset.x, SNAP_GRID), snappedf(offset.y, SNAP_GRID))
	var r := Rect2(rect_at_offset.position + (snapped_offset - offset), rect_at_offset.size)
	if absf(r.position.x - EDGE_MARGIN) < SNAP_EDGE:
		snapped_offset.x += EDGE_MARGIN - r.position.x
	elif absf(viewport.x - EDGE_MARGIN - r.end.x) < SNAP_EDGE:
		snapped_offset.x += viewport.x - EDGE_MARGIN - r.end.x
	if absf(r.position.y - EDGE_MARGIN) < SNAP_EDGE:
		snapped_offset.y += EDGE_MARGIN - r.position.y
	elif absf(viewport.y - EDGE_MARGIN - r.end.y) < SNAP_EDGE:
		snapped_offset.y += viewport.y - EDGE_MARGIN - r.end.y
	return snapped_offset

## Mete en pantalla un panel movido. No toca lo guardado: en otra ventana el
## mismo desplazamiento puede volver a caber.
func _clamp_on_screen(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree():
		return
	var shift := clamp_rect_to(control.get_global_rect(), _viewport_size)
	if shift == Vector2.ZERO:
		return
	control.offset_left += shift.x
	control.offset_right += shift.x
	control.offset_top += shift.y
	control.offset_bottom += shift.y

# ── Modo "Editar disposicion" ──

func is_editing_layout() -> bool:
	return _editor != null and is_instance_valid(_editor)

## Abre el editor encima de todo. Devuelve false si no hay escena de juego o
## hay un tablero abierto (no se reordena el HUD en mitad de una batalla).
func start_layout_edit() -> bool:
	if is_editing_layout():
		return true
	if CombatManager.is_board_open():
		return false
	var scene := get_tree().current_scene
	if scene == null:
		return false
	_editor = preload("res://scripts/ui/LayoutEditor.gd").new()
	scene.add_child(_editor)
	return true

func stop_layout_edit() -> void:
	if is_editing_layout():
		_editor.finish()
	_editor = null
