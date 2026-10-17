extends CanvasLayer
## PARTIDAS: la lista de partidas guardadas (2026-10-12). La abren el menu
## principal y ☰ MENÚ → PARTIDA, y "Nueva partida" cuando ya hay cinco
## (`make_room`: hay que borrar una antes de seguir).
##
## Una fila por partida, la mas reciente arriba, con poco texto y cifras:
##
##   [bandera] Nombre (o "Colonia N")           EN JUEGO / TERMINADA
##             Campaña · Colono · Era 2 · 1:05 · 12/10 18:30
##                                              [CARGAR] [BORRAR]
##
## BORRAR pide confirmacion en la misma fila. Una partida terminada (Supervivencia
## perdida, sellada) no se carga: solo se borra. Todo sale de UITheme y la lista
## se arrastra con el dedo (DragScroll).
##
## Lo crea GameManager (open_saves_list) y cuelga de el: funciona en la vista 3D
## y en la 2D, con el arbol en pausa, y se libera solo al cargar o cerrar.

signal closed

const LAYER := 40
const MAX_WIDTH := 760.0
## Por debajo de este ancho de tarjeta los botones van debajo de los datos.
const NARROW := 560.0
const FLAG_SIZE := Vector2(42, 28)
## El dibujante de banderas.
const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")
const DragScroll := preload("res://scripts/ui/DragScroll.gd")

var _make_room := false
var _root: Control
var _card: PanelContainer
var _count_label: Label
var _full_label: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
## La fila que esta preguntando "¿Borrar?", o 0.
var _confirm_id := 0

## Antes de add_child.
func setup(make_room: bool = false) -> void:
	_make_room = make_room

func is_make_room() -> bool:
	return _make_room

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_ui()
	refresh()
	get_viewport().size_changed.connect(_relayout)

# ── Construccion ─────────────────────────────────────────────────────

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var backdrop := ModalKit.make_backdrop(0.85)
	backdrop.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	_root.add_child(backdrop)

	_card = ModalKit.make_card(10)
	_card.name = "SavesCard"
	_root.add_child(_card)
	var column: VBoxContainer = _card.get_child(0)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	column.add_child(head)
	var title := UITheme.make_label(Tr.t("BTN_SAVES"), "title", UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_count_label = UITheme.make_label("", "section", UITheme.TEXT_DIM)
	_count_label.name = "Count"
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_count_label)
	var close_btn := Button.new()
	close_btn.name = "Close"
	close_btn.text = "✕"
	close_btn.tooltip_text = Tr.t("BTN_CLOSE")
	close_btn.focus_mode = Control.FOCUS_ALL
	UITheme.style_button(close_btn, UITheme.BTN, UITheme.FONT_SECTION)
	close_btn.custom_minimum_size = Vector2(UITheme.MIN_BTN_H, UITheme.MIN_BTN_H)
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	_full_label = ModalKit.make_text("", "body", UITheme.WARNING)
	_full_label.name = "FullLabel"
	column.add_child(_full_label)
	column.add_child(UITheme.make_separator())

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 10)
	_scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	pad.add_child(_list)
	DragScroll.attach.call_deferred(_scroll)

## Rehace la lista con lo que hay en disco.
func refresh() -> void:
	# Se quedan en el arbol hasta liberarse (un boton de la fila puede ser quien
	# llama), escondidas y con otro nombre para que no choquen con las nuevas.
	for child in _list.get_children():
		if child.is_queued_for_deletion():
			continue
		child.visible = false
		child.name = "Old_%d" % child.get_instance_id()
		child.queue_free()
	var saves: Array = GameManager.list_saves()
	_count_label.text = "%d/%d" % [saves.size(), GameManager.MAX_SAVES]
	_full_label.text = Tr.t("LBL_SAVES_FULL") % [saves.size(), GameManager.MAX_SAVES]
	_full_label.visible = _make_room
	if saves.is_empty():
		_list.add_child(ModalKit.make_text(Tr.t("LBL_SAVES_EMPTY"), "body", UITheme.TEXT_DIM))
	for entry in saves:
		_list.add_child(_make_row(entry))
	_relayout()

func _make_row(entry: Dictionary) -> PanelContainer:
	var id := int(entry.get("id", 0))
	var active: bool = id == GameManager.active_slot() and not GameManager.is_active_slot_deleted()
	var sealed := bool(entry.get("sealed", false))
	var row := PanelContainer.new()
	row.name = "Save_%d" % id
	row.set_meta("save_id", id)
	row.add_theme_stylebox_override("panel", UITheme.make_panel_style(active))
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	row.add_child(box)

	# Bandera, nombre y estado.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	box.add_child(top)
	top.add_child(_make_flag(entry))
	var name_label := UITheme.make_label(display_name(entry), "section", UITheme.TEXT_BRIGHT)
	name_label.name = "Name"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	top.add_child(name_label)
	if sealed:
		top.add_child(_badge(Tr.t("LBL_SAVE_SEALED"), UITheme.DANGER, "Sealed"))
	elif bool(entry.get("broken", false)):
		top.add_child(_badge(Tr.t("LBL_SAVE_BROKEN"), UITheme.WARNING, "Broken"))
	if active:
		top.add_child(_badge(Tr.t("LBL_SAVE_ACTIVE"), UITheme.POSITIVE, "Active"))

	# Datos en cifras y botones; en estrecho, los botones bajan de linea.
	var bottom := HFlowContainer.new()
	bottom.add_theme_constant_override("h_separation", 10)
	bottom.add_theme_constant_override("v_separation", 6)
	box.add_child(bottom)
	var info := UITheme.make_label(info_line(entry), "small", UITheme.TEXT)
	info.name = "Info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.custom_minimum_size.x = 240.0
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.tooltip_text = "%s · %s" % [Tr.t("LBL_SAVE_TIME_TIP"), Tr.t("LBL_SAVE_DATE_TIP")]
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	bottom.add_child(info)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 8)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_END
	bottom.add_child(buttons)
	if _confirm_id == id:
		var ask := UITheme.make_label(Tr.t("LBL_SAVE_DELETE_ASK"), "body", UITheme.DANGER)
		ask.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		buttons.add_child(ask)
		buttons.add_child(_button("No", Tr.t("BTN_SAVE_DELETE_NO"), UITheme.BTN, _ask_delete.bind(0)))
		buttons.add_child(_button("Yes", Tr.t("BTN_SAVE_DELETE_YES"), UITheme.DANGER, delete_save.bind(id)))
	else:
		var load_btn := _button("Load", Tr.t("BTN_SAVE_LOAD"), UITheme.POSITIVE, load_save.bind(id))
		# Terminada: se ve, no se sigue. Con la lista para hacer sitio, solo borrar.
		load_btn.disabled = sealed or _make_room
		load_btn.visible = not _make_room
		buttons.add_child(load_btn)
		buttons.add_child(_button("Delete", Tr.t("BTN_SAVE_DELETE"), UITheme.DANGER, _ask_delete.bind(id)))
	return row

func _button(node_name: String, text: String, color: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = text
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size = Vector2(96, UITheme.MIN_BTN_H)
	UITheme.style_button(btn, color, UITheme.FONT_BUTTON)
	btn.pressed.connect(cb)
	return btn

func _badge(text: String, color: Color, node_name: String) -> Label:
	var label := UITheme.make_label(text, "small", color)
	label.name = node_name
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

## La bandera de la partida (ColonyFlag.draw_spec), o un recuadro del color de
## la colonia si el guardado no trae receta (partidas de antes).
func _make_flag(entry: Dictionary) -> Control:
	var flag := Control.new()
	flag.name = "Flag"
	flag.custom_minimum_size = FLAG_SIZE
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spec: Variant = entry.get("flag_spec", {})
	var color_id := String(entry.get("color", String(GameConfig.COLONY_DEFAULT_SPEC["colors"][0])))
	var fill: Color = GameConfig.colony_colors.get(color_id,
		GameConfig.colony_colors[String(GameConfig.COLONY_DEFAULT_SPEC["colors"][0])])
	flag.draw.connect(func():
		var rect := Rect2(Vector2.ZERO, FLAG_SIZE)
		if spec is Dictionary and not (spec as Dictionary).is_empty():
			ColonyFlag.draw_spec(flag, rect, spec)
		else:
			flag.draw_rect(rect, fill)
		flag.draw_rect(rect, UITheme.TEXT_DIM, false, 1.0))
	return flag

# ── Textos ───────────────────────────────────────────────────────────

## El nombre del pais, o "Colonia N".
static func display_name(entry: Dictionary) -> String:
	var n := String(entry.get("colony_name", "")).strip_edges()
	return n if not n.is_empty() else Tr.t("LBL_SAVE_COLONY_N") % int(entry.get("id", 0))

## "Campaña · Colono · Era 2 · 1:05 · 12/10 18:30": modo, nivel, era, tiempo
## jugado y fecha de la ultima vez.
static func info_line(entry: Dictionary) -> String:
	var mode: int = GameMode.from_key(String(entry.get("mode", "campaign")))
	var tier: int = GameMode.tier_from_key(String(entry.get("tier", "colonist")))
	var parts: Array = [GameMode.display_name(mode)]
	if GameMode.tier_allowed(mode):
		parts.append(Tr.t(GameMode.tier_name_key(tier)))
	parts.append(Tr.t("LBL_SAVE_ERA") % int(entry.get("era", 1)))
	parts.append(played_time(float(entry.get("played_seconds", 0.0))))
	parts.append(short_date(float(entry.get("saved_at", 0.0))))
	return " · ".join(parts)

## Tiempo jugado: "25 min", "2 h", "1 h 05". Sin segundos: "25:00" se leia como
## una hora.
static func played_time(seconds: float) -> String:
	var m: int = floori(maxf(0.0, seconds) / 60.0)
	if m < 60:
		return "%d min" % m
	var h: int = floori(m / 60.0)
	return "%d h" % h if m % 60 == 0 else "%d h %02d" % [h, m % 60]

## "12/10 18:30" en la hora local, o "—" sin fecha.
static func short_date(unix: float) -> String:
	if unix <= 0.0:
		return "—"
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var t: Dictionary = Time.get_datetime_dict_from_unix_time(int(unix) + bias * 60)
	return "%02d/%02d %02d:%02d" % [int(t["day"]), int(t["month"]), int(t["hour"]), int(t["minute"])]

# ── Colocacion ───────────────────────────────────────────────────────

func _relayout() -> void:
	if _card == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	ModalKit.fit_center(_card, MAX_WIDTH, vp)
	# Lo que no quepa en alto se desplaza: titulo y margenes piden unos 150 px.
	var rows: int = maxi(1, row_count())
	var row_h: float = 118.0 if _card.custom_minimum_size.x < NARROW else 92.0
	var wanted: float = float(rows) * row_h
	_scroll.custom_minimum_size = Vector2(0, clampf(wanted, 80.0, maxf(80.0, vp.y - 190.0)))

# ── Acciones ─────────────────────────────────────────────────────────

func _ask_delete(id: int) -> void:
	_confirm_id = id
	refresh()

## Abre la partida `id` (GameManager.load_slot) y se cierra.
func load_save(id: int) -> void:
	if GameManager.load_slot(id):
		_finish()

## Borra la partida `id` (ya confirmada). Si era la que esta en memoria, o la
## lista se abrio para hacer sitio, se sigue: a la partida mas reciente que
## quede, o al selector de "Nueva partida".
func delete_save(id: int) -> void:
	_confirm_id = 0
	if not GameManager.delete_slot(id):
		refresh()
		return
	if _make_room:
		_finish()
		GameManager.request_new_game()
		return
	if GameManager.is_active_slot_deleted():
		_finish()
		GameManager.leave_deleted_slot()
		return
	refresh()

func close() -> void:
	if _make_room and GameManager.is_active_slot_deleted():
		GameManager.leave_deleted_slot()
	_finish()

func _finish() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()

## La fila de la partida `id`, para pruebas.
func row(id: int) -> Control:
	return _list.get_node_or_null("Save_%d" % id) as Control

func row_count() -> int:
	var n := 0
	for child in _list.get_children():
		if child.has_meta("save_id") and not child.is_queued_for_deletion():
			n += 1
	return n

## `_input` y no `_unhandled_input`: cuelga de un autoload, y el menu principal
## (en la escena) se come el ESC antes que cualquier autoload.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _confirm_id != 0:
			_ask_delete(0)
		else:
			close()
		get_viewport().set_input_as_handled()
