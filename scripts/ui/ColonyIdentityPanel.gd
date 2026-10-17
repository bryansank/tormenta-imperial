extends CanvasLayer
## El editor del pais: nombre y bandera por piezas (fondo, emblema, colores).
##
##   var panel = preload("res://scripts/ui/ColonyIdentityPanel.gd").new()
##   add_child(panel)
##   panel.confirmed.connect(func(n, spec): ...)
##   panel.cancelled.connect(func(): ...)
##   panel.open("new")     # o "edit"
##
## "new"   el paso de Nueva partida: sale con un nombre y una bandera al azar ya
##         puestos y piezas de rango 1 (con el que empieza toda partida).
##         "Saltar" acepta lo que habia al abrir. NO toca RankManager: quien lo
##         abre decide (NewGameDialog lo pasa a GameManager.start_new_game(),
##         que llama a set_colony() tras RankManager.reset()).
## "edit"  ☰ MENU > COLONIA: parte del pais de esta partida, con las piezas del
##         rango de ahora. Lo engancha RankPanel, que llama a set_colony().
##
## Siempre queda bonita: los colores que no se distinguirian o no se leerian se
## ven tachados y no se pueden tocar, y al cambiar una pieza la receta se arregla
## sola (ColonyFlag.fix_spec). Lo cerrado por rango, con candado y "Rango N".
## Al cerrarse (confirmar o cancelar) se libera solo salvo `auto_free = false`.

signal confirmed(colony_name: String, spec: Dictionary)
signal cancelled

const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")
const ColonyIdentity := preload("res://scripts/services/ColonyIdentity.gd")
const ConstructionMenuScript := preload("res://scripts/ui/ConstructionMenu.gd")
const DragScroll := preload("res://scripts/ui/DragScroll.gd")

## Por encima del dialogo de Nueva partida (40) y del menu (30).
const LAYER := 41
const CARD_W := 800.0
const PREVIEW := Vector2(168, 112)
const THUMB := Vector2(66, 44)
const SWATCH := 46.0
const TABS := ["patterns", "emblems", "colors"]

var auto_free := true

var _mode := "edit"
var _rank := 1
var _all := false
var _name := ""
var _spec: Dictionary = {}
var _initial_name := ""
var _initial_spec: Dictionary = {}
var _tab := "patterns"
var _open := false

var _root: Control
var _backdrop: ColorRect
var _card: PanelContainer
var _preview: TextureRect
var _name_edit: LineEdit
var _name_error: Label
var _tab_buttons := {}
var _scroll: ScrollContainer
var _content: VBoxContainer
var _secondary_btn: Button
var _ok_btn: Button

func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "ColonyIdentityPanel"

func _ready() -> void:
	_build()
	visible = false
	get_viewport().size_changed.connect(_relayout)

# ── API ──

## Abre el editor. `colony_name` / `spec` vacios: los de la partida ("edit") o
## al azar ("new").
func open(mode: String = "edit", colony_name: String = "", spec: Dictionary = {}) -> void:
	if _root == null:
		_build()
	_mode = "new" if mode == "new" else "edit"
	if _mode == "new":
		_rank = 1
		_all = false
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var seed_value := rng.randi()
		_name = colony_name if colony_name != "" else ColonyIdentity.random_name(seed_value, Tr.get_locale())
		_spec = ColonyIdentity.clamp_spec(spec if not spec.is_empty() else ColonyIdentity.random_spec(seed_value, 1), 1)
	else:
		_rank = RankManager.get_rank()
		_all = GameMode.all_unlocked()
		_name = colony_name if colony_name != "" else RankManager.get_colony_name()
		_spec = ColonyIdentity.clamp_spec(spec if not spec.is_empty() else RankManager.get_flag_spec(), _rank, _all)
	_initial_name = _name
	_initial_spec = _spec.duplicate(true)
	_name_edit.text = _name
	_name_error.visible = false
	_secondary_btn.text = Tr.t("BTN_IDENTITY_SKIP") if _mode == "new" else Tr.t("BTN_CANCEL")
	_tab = "patterns"
	_open = true
	visible = true
	_refresh()
	_relayout.call_deferred()

func is_open() -> bool:
	return _open

func get_mode() -> String:
	return _mode

func get_name_text() -> String:
	return _name

func get_spec() -> Dictionary:
	return _spec.duplicate(true)

## Cambia una pieza como si se tocara su boton (las pruebas y la sonda).
## Devuelve false si esta cerrada por rango o no se leeria.
func pick(kind: String, id: String, slot: int = 0) -> bool:
	match kind:
		"patterns":
			if not ColonyIdentity.is_piece_open("patterns", id, _rank, _all):
				return false
			_spec["pattern"] = id
		"emblems":
			if not ColonyIdentity.is_piece_open("emblems", id, _rank, _all):
				return false
			_spec["emblem"] = id
		"colors":
			if not _color_allowed(slot, id):
				return false
			_spec["colors"][slot] = id
		_:
			return false
	_spec = ColonyFlag.fix_spec(_spec, _open_colors())
	_refresh()
	return true

func select_tab(kind: String) -> void:
	if kind in TABS:
		_tab = kind
		_refresh()

func randomize_flag() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_spec = ColonyIdentity.random_spec(rng.randi(), _rank, _all)
	_refresh()

func randomize_name() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_name = ColonyIdentity.random_name(rng.randi(), Tr.get_locale())
	_name_edit.text = _name
	_name_error.visible = false

## LISTO: si el nombre no vale, lo dice corto y no cierra.
func confirm() -> bool:
	_name = ColonyIdentity.clean_name(_name_edit.text)
	if not ColonyIdentity.is_name_allowed(_name):
		_name_error.visible = true
		_name_edit.grab_focus()
		return false
	_finish(true, _name, _spec)
	return true

## Saltar ("new"): lo que habia al abrir. Cancelar ("edit"): nada cambia.
func secondary() -> void:
	if _mode == "new":
		_finish(true, _initial_name, _initial_spec)
	else:
		cancel()

func cancel() -> void:
	_finish(false, "", {})

func _finish(ok: bool, colony_name: String, spec: Dictionary) -> void:
	if not _open:
		return
	_open = false
	visible = false
	if ok:
		confirmed.emit(colony_name, spec.duplicate(true))
	else:
		cancelled.emit()
	if auto_free:
		queue_free()

func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _mode == "new":
			secondary()
		else:
			cancel()

# ── Montaje ──

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_backdrop = ModalKit.make_backdrop()
	_root.add_child(_backdrop)
	_card = ModalKit.make_card(UITheme.SEPARATION)
	_card.name = "IdentityCard"
	_root.add_child(_card)
	var col: VBoxContainer = _card.get_child(0)
	col.add_child(UITheme.make_panel_header(Tr.t("LBL_IDENTITY_TITLE"), func(): secondary() if _mode == "new" else cancel()))

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	col.add_child(top)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	top.add_child(left)
	_preview = TextureRect.new()
	_preview.name = "FlagPreview"
	_preview.custom_minimum_size = PREVIEW
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_SCALE
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_preview)
	var flag_dice := _make_button(Tr.t("BTN_IDENTITY_RANDOM_FLAG"), UITheme.BTN, randomize_flag)
	flag_dice.name = "RandomFlag"
	left.add_child(flag_dice)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	top.add_child(right)
	right.add_child(UITheme.make_label(Tr.t("LBL_IDENTITY_NAME_HINT"), "small", UITheme.TEXT_DIM))
	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.max_length = GameConfig.COLONY_NAME_MAX
	_name_edit.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H + 4)
	_name_edit.add_theme_font_size_override("font_size", UITheme.FONT_BODY + 3)
	var hf := UITheme.heavy_font()
	if hf:
		_name_edit.add_theme_font_override("font", hf)
	_name_edit.placeholder_text = Tr.t("LBL_IDENTITY_NAME_HINT")
	_name_edit.text_changed.connect(func(t: String):
		_name = t
		_name_error.visible = false)
	_name_edit.text_submitted.connect(func(_t): confirm())
	right.add_child(_name_edit)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	right.add_child(name_row)
	var name_dice := _make_button(Tr.t("BTN_IDENTITY_RANDOM_NAME"), UITheme.BTN, randomize_name)
	name_dice.name = "RandomName"
	name_row.add_child(name_dice)
	_name_error = UITheme.make_label(Tr.t("LBL_IDENTITY_NAME_BAD"), "body", UITheme.WARNING)
	_name_error.name = "NameError"
	_name_error.visible = false
	_name_error.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(_name_error)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	col.add_child(tabs)
	for kind in TABS:
		var key: String = {"patterns": "LBL_IDENTITY_TAB_PATTERN", "emblems": "LBL_IDENTITY_TAB_EMBLEM",
			"colors": "LBL_IDENTITY_TAB_COLORS"}[kind]
		var b := _make_button(Tr.t(key), UITheme.BTN, func(): select_tab(kind))
		b.name = "Tab_" + kind
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		_tab_buttons[kind] = b

	_scroll = ScrollContainer.new()
	_scroll.name = "PieceScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 260)
	col.add_child(_scroll)
	DragScroll.attach.call_deferred(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	col.add_child(buttons)
	_secondary_btn = ModalKit.make_menu_button(Tr.t("BTN_CANCEL"), UITheme.BTN, secondary)
	_secondary_btn.name = "Secondary"
	buttons.add_child(_secondary_btn)
	_ok_btn = ModalKit.make_menu_button(Tr.t("BTN_IDENTITY_OK"), UITheme.POSITIVE, func(): confirm())
	_ok_btn.name = "Confirm"
	buttons.add_child(_ok_btn)

func _make_button(text: String, color: Color, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H)
	UITheme.style_button(b, color, UITheme.FONT_BUTTON)
	b.pressed.connect(callback)
	return b

func _relayout() -> void:
	if _card == null or not is_inside_tree():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	ModalKit.fit_center(_card, CARD_W, vp)
	# La lista de piezas se queda con lo que sobre de alto (y se arrastra).
	_scroll.custom_minimum_size.y = clampf(vp.y - 470.0, 120.0, 300.0)
	_card.reset_size()
	_card.offset_top = -_card.size.y * 0.5
	_card.offset_bottom = _card.size.y * 0.5

# ── Refresco ──

func _refresh() -> void:
	if _preview == null:
		return
	_preview.texture = ColonyFlag.texture(_spec)
	for kind in _tab_buttons:
		var b: Button = _tab_buttons[kind]
		UITheme.style_button(b, UITheme.ACCENT_DIM if kind == _tab else UITheme.BTN, UITheme.FONT_BUTTON)
		b.set_meta("selected", kind == _tab)
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	match _tab:
		"patterns":
			_content.add_child(_piece_grid("patterns"))
		"emblems":
			_content.add_child(_piece_grid("emblems"))
		"colors":
			_build_color_rows()
	_relayout.call_deferred()

func _open_colors() -> Array:
	return ColonyIdentity.open_pieces("colors", _rank, _all)

func _piece_grid(kind: String) -> HFlowContainer:
	var grid := HFlowContainer.new()
	grid.name = "Grid_" + kind
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var current: String = _spec["pattern"] if kind == "patterns" else _spec["emblem"]
	for id in ColonyIdentity.catalog(kind):
		var unlocked := ColonyIdentity.is_piece_open(kind, id, _rank, _all)
		var btn := _make_pick_button(id == current, unlocked)
		btn.name = "Piece_" + String(id)
		var label_key := ("FLAG_PATTERN_" if kind == "patterns" else "FLAG_EMBLEM_") + String(id).to_upper()
		btn.tooltip_text = Tr.t(label_key)
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.add_child(box)
		var pic := TextureRect.new()
		pic.custom_minimum_size = THUMB
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pic.texture = ColonyFlag.small_texture(_thumb_spec(kind, id))
		if not unlocked:
			pic.modulate = Color(0.45, 0.45, 0.45)
		box.add_child(pic)
		if not unlocked:
			box.add_child(ConstructionMenuScript.make_rank_lock_row(ColonyIdentity.piece_rank(kind, id)))
		btn.custom_minimum_size = Vector2(THUMB.x + 18, THUMB.y + (34 if not unlocked else 16))
		var piece_id := String(id)
		btn.pressed.connect(func(): pick(kind, piece_id))
		grid.add_child(btn)
	return grid

## La miniatura de una pieza: el fondo con los colores de ahora (sin emblema),
## o el emblema sobre el color que tendria debajo.
func _thumb_spec(kind: String, id: String) -> Dictionary:
	var colors: Array = _spec["colors"]
	if kind == "patterns":
		return {"pattern": id, "emblem": "none", "colors": colors}
	var under: String = ColonyFlag.colors_under_emblem(_spec["pattern"], colors)[0]
	var ink: String = colors[2]
	if not ColonyFlag.emblem_legible("plain", [under, under, under], ink):
		ink = ColonyFlag.fix_spec({"pattern": "plain", "emblem": "gear", "colors": [under, under, ink]}, _open_colors())["colors"][2]
	return {"pattern": "plain", "emblem": id, "colors": [under, under, ink]}

func _build_color_rows() -> void:
	var slots: Array = [0]
	if ColonyFlag.fields_of(_spec["pattern"]) == 2:
		slots.append(1)
	if _spec["emblem"] != "none":
		slots.append(2)
	for slot in slots:
		var key: String = ["LBL_IDENTITY_COLOR_1", "LBL_IDENTITY_COLOR_2", "LBL_IDENTITY_COLOR_EMBLEM"][slot]
		_content.add_child(UITheme.section_header(Tr.t(key)))
		var row := HFlowContainer.new()
		row.name = "Colors_%d" % slot
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		_content.add_child(row)
		for color_id in GameConfig.COLONY_COLOR_ORDER:
			row.add_child(_swatch(slot, color_id))

func _swatch(slot: int, color_id: String) -> Button:
	var unlocked := ColonyIdentity.is_piece_open("colors", color_id, _rank, _all)
	var allowed := unlocked and _color_allowed(slot, color_id)
	var btn := _make_pick_button(String(_spec["colors"][slot]) == color_id, allowed)
	btn.name = "Color_%d_%s" % [slot, color_id]
	btn.tooltip_text = Tr.t("COLONY_COLOR_" + color_id.to_upper())
	if unlocked and not allowed:
		btn.tooltip_text += " · " + Tr.t("LBL_IDENTITY_UNREADABLE")
	btn.custom_minimum_size = Vector2(SWATCH, SWATCH + (0 if unlocked else 16))
	var swatch := ColorRect.new()
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.color = ColonyFlag.color_of(color_id)
	if not allowed:
		swatch.color = swatch.color.darkened(0.55)
	swatch.set_anchors_preset(Control.PRESET_FULL_RECT)
	swatch.offset_left = 6
	swatch.offset_top = 6
	swatch.offset_right = -6
	swatch.offset_bottom = -6 - (16 if not unlocked else 0)
	btn.add_child(swatch)
	if not unlocked:
		# Candado dibujado y el numero de rango, bajo la muestra.
		var row := HBoxContainer.new()
		row.name = "RankLock"
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 2)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		row.offset_top = -18
		row.offset_bottom = -2
		var lock := Control.new()
		lock.custom_minimum_size = Vector2(10, 12)
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock.draw.connect(func(): ConstructionMenuScript.draw_lock(lock, Rect2(Vector2.ZERO, lock.custom_minimum_size), UITheme.WARNING))
		row.add_child(lock)
		var label := UITheme.make_label(str(ColonyIdentity.piece_rank("colors", color_id)), "small", UITheme.WARNING)
		label.name = "RankLockLabel"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)
		btn.add_child(row)
		btn.tooltip_text = Tr.t("LBL_RANK_LOCK") % ColonyIdentity.piece_rank("colors", color_id)
	elif not allowed:
		# Tachado: no se distinguiria o no se leeria.
		var cross := Control.new()
		cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cross.set_anchors_preset(Control.PRESET_FULL_RECT)
		cross.draw.connect(func():
			var s := cross.size
			cross.draw_line(Vector2(8, 8), s - Vector2(8, 8), UITheme.TEXT_DIM, 2.0))
		btn.add_child(cross)
	btn.pressed.connect(func(): pick("colors", color_id, slot))
	return btn

## ¿Se puede poner este color en esta casilla y que la bandera se lea?
func _color_allowed(slot: int, color_id: String) -> bool:
	if not ColonyIdentity.is_piece_open("colors", color_id, _rank, _all):
		return false
	var colors: Array = (_spec["colors"] as Array).duplicate()
	match slot:
		0:
			return true
		1:
			return ColonyFlag.fields_distinct(colors[0], color_id)
		2:
			if ColonyFlag.emblem_legible(_spec["pattern"], colors, color_id):
				return true
			# Si ninguno llega, vale el que mejor se lee (el que pone fix_spec).
			for c in _open_colors():
				if ColonyFlag.emblem_legible(_spec["pattern"], colors, c):
					return false
			colors[2] = color_id
			var fixed := ColonyFlag.fix_spec({"pattern": _spec["pattern"], "emblem": _spec["emblem"], "colors": colors}, _open_colors())
			return String(fixed["colors"][2]) == color_id
	return false

func _make_pick_button(selected: bool, enabled: bool) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = not enabled
	var st := StyleBoxFlat.new()
	st.bg_color = UITheme.CARD_BG if enabled else UITheme.BTN_DISABLED
	st.set_corner_radius_all(4)
	st.border_color = UITheme.ACCENT if selected else UITheme.ACCENT_DIM
	st.set_border_width_all(3 if selected else 1)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, st)
	btn.set_meta("selected", selected)
	return btn
