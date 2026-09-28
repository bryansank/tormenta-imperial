extends CanvasLayer
## Modo "Editar disposicion": un marco encima de cada panel movible
## (HudRegistry.movable_ids) que se arrastra con el raton o con el dedo.
##
## Existe como modo aparte a proposito: fuera de el un toque en el HUD es un
## toque en el HUD y nada se mueve por accidente (en tablet, sobre todo). Dentro,
## un velo para la entrada al mapa y lo unico que responde son los marcos y la
## barra de LISTO / RESTABLECER.
##
## Lo abre UILayoutManager.start_layout_edit() (Ajustes > Interfaz). Mientras
## esta abierto esconde las capas de encima del HUD (ventanas, pausa, menu
## principal) y las devuelve al terminar. Cada arrastre se ajusta a la rejilla
## y a los bordes, no sale de la pantalla y se guarda al soltar
## (UILayoutManager.set_user_offset), por perfil y proporcion de ventana.

const LAYER := 35
## Paneles que se enmarcan aunque su panel los tenga ocultos ahora (la
## Tormenta en calma, la poblacion antes de la fase de asentamiento, avisos
## sin avisos): el jugador tiene que poder colocarlos antes de verlos.
const ALWAYS_FRAMED := ["ResourceHUD", "NotificationPanel.status", "NotificationPanel.objective",
	"StormHUD", "NotificationPanel.toasts", "ConstructionMenu.button"]
const MIN_FRAME := Vector2(140, 44)

var _frames: Dictionary = {}       # panel_id -> Panel
var _hidden_layers: Array = []     # CanvasLayer que se escondieron al entrar
var _drag_id := ""
var _drag_mouse0 := Vector2.ZERO
var _drag_off0 := Vector2.ZERO
var _drag_rect0 := Rect2()
var _finished := false

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "LayoutEditor"
	_hide_upper_layers()
	_build()

func _hide_upper_layers() -> void:
	var scene := get_parent()
	if scene == null:
		return
	# Las capas que llevan HUD se quedan: esconderlas lo compactaria (el
	# apilado ve oculto lo que esta en una capa oculta) y se editaria una
	# disposicion que no es la de verdad.
	var hud_layers := {}
	for id in HudRegistry.ELEMENTS:
		var c := HudRegistry.control_of(id)
		if c != null:
			var cl_of := _layer_of(c)
			if cl_of != null:
				hud_layers[cl_of] = true
	for node in scene.find_children("*", "CanvasLayer", true, false):
		var cl := node as CanvasLayer
		if cl == self or not cl.visible or hud_layers.has(cl):
			continue
		if cl.layer >= 12:
			cl.visible = false
			_hidden_layers.append(weakref(cl))

static func _layer_of(node: Node) -> CanvasLayer:
	var n := node.get_parent()
	while n != null:
		if n is CanvasLayer:
			return n
		n = n.get_parent()
	return null

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Velo: se come los clics al mapa (nada de construir por error).
	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.color = Color(0, 0, 0, 0.3)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(veil)

	for id in HudRegistry.movable_ids():
		var frame := Panel.new()
		frame.name = "Frame_" + String(id).replace(".", "_")
		frame.mouse_filter = Control.MOUSE_FILTER_STOP
		frame.mouse_default_cursor_shape = Control.CURSOR_MOVE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(UITheme.INFO.r, UITheme.INFO.g, UITheme.INFO.b, 0.22)
		style.border_color = UITheme.readable(UITheme.INFO)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		frame.add_theme_stylebox_override("panel", style)
		var label := UITheme.make_label("✥ " + Tr.t(HudRegistry.label_key(id)), "small", UITheme.TEXT_BRIGHT)
		label.position = Vector2(6, 2)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(label)
		frame.gui_input.connect(_on_frame_input.bind(id))
		root.add_child(frame)
		_frames[id] = frame

	# Barra en el centro: los bordes son del HUD, que es lo que se esta moviendo.
	var bar := PanelContainer.new()
	bar.name = "EditorBar"
	bar.add_theme_stylebox_override("panel", UITheme.make_hud_card_style(UITheme.ACCENT, 2))
	bar.set_anchors_preset(Control.PRESET_CENTER)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(bar)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	bar.add_child(col)
	var title := UITheme.make_label(Tr.t("LBL_LAYOUT_EDITING"), "section", UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var hint := UITheme.make_label(Tr.ti("LBL_LAYOUT_EDITING_HINT"), "small", UITheme.TEXT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 320
	col.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var reset := Button.new()
	reset.name = "ResetButton"
	reset.text = Tr.t("BTN_RESET_LAYOUT")
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(reset, UITheme.BTN, UITheme.FONT_BODY)
	reset.pressed.connect(UILayoutManager.reset_user_layout)
	row.add_child(reset)
	var done := Button.new()
	done.name = "DoneButton"
	done.text = Tr.t("BTN_LAYOUT_DONE")
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(done, UITheme.POSITIVE, UITheme.FONT_BODY)
	done.pressed.connect(func(): UILayoutManager.stop_layout_edit())
	row.add_child(done)
	_sync_frames()

func _process(_delta: float) -> void:
	_sync_frames()

## Cada marco sobre el rectangulo real de su panel, cada frame: el panel se
## mueve mientras se arrastra, y puede crecer o cambiar de columna.
func _sync_frames() -> void:
	for id in _frames:
		var frame: Panel = _frames[id]
		var control := UILayoutManager.placed_control(id)
		var show: bool = control != null and not HudRegistry.is_hidden(id) \
			and (id in ALWAYS_FRAMED or control.is_visible_in_tree())
		frame.visible = show
		if not show:
			continue
		var rect := control.get_global_rect()
		rect.size = rect.size.max(MIN_FRAME)
		frame.position = rect.position
		frame.size = rect.size

func _on_frame_input(event: InputEvent, id: String) -> void:
	var control := UILayoutManager.placed_control(id)
	if control == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_id = id
			_drag_mouse0 = (_frames[id] as Control).get_global_mouse_position()
			_drag_off0 = UILayoutManager.get_user_offset(id)
			_drag_rect0 = control.get_global_rect()
		elif _drag_id == id:
			_drag_to((_frames[id] as Control).get_global_mouse_position(), true)
			_drag_id = ""
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag_id == id:
		_drag_to((_frames[id] as Control).get_global_mouse_position(), false)
		get_viewport().set_input_as_handled()

func _drag_to(mouse: Vector2, persist: bool) -> void:
	var vp := get_viewport().get_visible_rect().size
	var wanted := _drag_off0 + (mouse - _drag_mouse0)
	var final := drag_result(_drag_off0, _drag_rect0, wanted, vp)
	UILayoutManager.set_user_offset(_drag_id, final, persist)

## Desplazamiento final de un arrastre: ajustado a rejilla y bordes y metido en
## pantalla. Puro, para los tests.
static func drag_result(offset0: Vector2, rect0: Rect2, wanted: Vector2, viewport: Vector2) -> Vector2:
	var rect_at := Rect2(rect0.position + (wanted - offset0), rect0.size)
	var snapped_off := UILayoutManager.snap_offset(wanted, rect_at, viewport)
	var rect_snapped := Rect2(rect0.position + (snapped_off - offset0), rect0.size)
	return snapped_off + UILayoutManager.clamp_rect_to(rect_snapped, viewport)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		UILayoutManager.stop_layout_edit()

## Cierra el editor y devuelve las capas que escondio.
func finish() -> void:
	if _finished:
		return
	_finished = true
	for ref in _hidden_layers:
		var cl: Variant = (ref as WeakRef).get_ref()
		if cl != null and is_instance_valid(cl):
			(cl as CanvasLayer).visible = true
	_hidden_layers.clear()
	GameConfig.save_user_settings()
	queue_free()

func frame_of(id: String) -> Control:
	return _frames.get(id)
