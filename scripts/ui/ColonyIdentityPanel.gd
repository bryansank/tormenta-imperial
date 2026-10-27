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
## Siempre queda bonita: los colores que no se distinguirian o no se leerian
## salen apagados con el simbolo de prohibido debajo y no se pueden tocar, y al
## cambiar una pieza la receta se arregla sola (ColonyFlag.fix_spec). Lo cerrado
## por rango, apagado y con la placa [candado] N debajo (CartoonTheme.piece_tile).
## Al cerrarse (confirmar o cancelar) se libera solo salvo `auto_free = false`.

signal confirmed(colony_name: String, spec: Dictionary)
signal cancelled

const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")
const ColonyIdentity := preload("res://scripts/services/ColonyIdentity.gd")
const DragScroll := preload("res://scripts/ui/DragScroll.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

## Por encima del dialogo de Nueva partida (40) y del menu (30).
const LAYER := 41
const CARD_W := 800.0
const PREVIEW := Vector2(168, 112)
const PREVIEW_SMALL := Vector2(120, 80)
const THUMB := Vector2(66, 44)
const SWATCH := 48.0
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
## La raiz de la ventana (CartoonTheme.window): cinta, panel y X.
var _window: Control
var _tabs_row: HBoxContainer
## Telefono: ventana a pantalla completa, pestanas solo con icono.
var _small := false
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
	_set_button_text(_secondary_btn, Tr.t("BTN_IDENTITY_SKIP") if _mode == "new" else Tr.t("BTN_CANCEL"))
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
	_small = CT.is_phone() if is_inside_tree() else false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_backdrop = CT.veil()
	_root.add_child(_backdrop)
	# Ventana crema con la cinta "TU PAIS" (docs/28 §6). En telefono, sin cinta:
	# los 360 de alto son para la bandera y las piezas.
	var w := CT.menu_window(Tr.t("LBL_IDENTITY_TITLE"), CT.sem("ACCENT"), _small, true)
	_window = w["root"]
	_window.name = "IdentityWindow"
	_root.add_child(_window)
	_card = w["panel"]
	_card.name = "IdentityCard"
	if _small:
		# Sin cinta de verdad: con ella la tarjeta bajaba 30 px y LISTO quedaba
		# por debajo del borde de un telefono de 360 de alto.
		(w["ribbon"] as Control).visible = false
		_card.offset_top = 0.0
		(w["top_pad"] as Control).custom_minimum_size.y = 0.0
	var close: Button = w["close"]
	close.name = "CloseButton"
	close.tooltip_text = Tr.t("BTN_CLOSE")
	close.pressed.connect(func(): secondary() if _mode == "new" else cancel())
	var col: VBoxContainer = w["body"]

	# Fila del nombre: [  Monte Biela  ] [dado]  (el aviso, corto, debajo).
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	col.add_child(name_row)
	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.max_length = GameConfig.COLONY_NAME_MAX
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size = Vector2(0, CT.menu_h("btn"))
	_name_edit.add_theme_font_override("font", CT.title_font())
	_name_edit.add_theme_font_size_override("font_size", CT.fs("title"))
	_name_edit.add_theme_color_override("font_color", CT.text("window"))
	_name_edit.add_theme_color_override("font_placeholder_color", CT.text("window", true))
	_name_edit.add_theme_color_override("caret_color", CT.text("window"))
	var es := CT.well_style("window", 14, 8)
	es.content_margin_left = 14
	es.border_color = CT.c("window", "CARD_BORDER")
	es.set_border_width_all(CT.BORDER)
	_name_edit.add_theme_stylebox_override("normal", es)
	var ef := es.duplicate() as StyleBoxFlat
	ef.border_color = CT.sem("ACCENT")
	_name_edit.add_theme_stylebox_override("focus", ef)
	_name_edit.placeholder_text = Tr.t("LBL_IDENTITY_NAME_HINT")
	_name_edit.tooltip_text = Tr.t("LBL_IDENTITY_NAME_HINT")
	_name_edit.text_changed.connect(func(t: String):
		_name = t
		_name_error.visible = false)
	_name_edit.text_submitted.connect(func(_t): confirm())
	name_row.add_child(_name_edit)
	var name_dice := CT.text_button("" if _small else Tr.t("UI2M_ID_RANDOM"), "raid", "secondary", CT.menu_h("btn"))
	name_dice.name = "RandomName"
	name_dice.tooltip_text = Tr.t("BTN_IDENTITY_RANDOM_NAME")
	name_dice.focus_mode = Control.FOCUS_NONE
	name_dice.pressed.connect(randomize_name)
	name_row.add_child(name_dice)
	if _small:
		# Sin cinta la ✕ cae en la fila del nombre: se le deja su hueco para que
		# no tape el dado.
		var close_room := Control.new()
		close_room.name = "CloseRoom"
		close_room.custom_minimum_size = Vector2(close.custom_minimum_size.x, 0)
		close_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_row.add_child(close_room)
	_name_error = CT.label(Tr.t("LBL_IDENTITY_NAME_BAD"), "small", CT.danger_text())
	_name_error.name = "NameError"
	_name_error.visible = false
	col.add_child(_name_error)

	# Bandera a la izquierda (con su dado y los botones de abajo); piezas a la
	# derecha: asi cabe en un telefono apaisado de 360 de alto.
	var main := BoxContainer.new()
	main.add_theme_constant_override("separation", 10 if _small else 16)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Telefono en vertical: bandera arriba y piezas debajo (lado a lado salia
	# 28 px por la derecha en 400 de ancho).
	main.vertical = CT.portrait()
	col.add_child(main)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6 if _small else 10)
	main.add_child(left)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", CT.well_style("window", 12, 6))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(frame)
	if main.vertical:
		# En columna la bandera no se estira a lo ancho.
		frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview = TextureRect.new()
	_preview.name = "FlagPreview"
	_preview.custom_minimum_size = PREVIEW_SMALL if _small else PREVIEW
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_SCALE
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_preview)
	var flag_dice := CT.text_button(Tr.t("UI2M_ID_RANDOM"), "raid", "secondary", CT.menu_h("small"))
	flag_dice.name = "RandomFlag"
	flag_dice.tooltip_text = Tr.t("BTN_IDENTITY_RANDOM_FLAG")
	flag_dice.focus_mode = Control.FOCUS_NONE
	flag_dice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flag_dice.pressed.connect(randomize_flag)
	left.add_child(flag_dice)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	# En columna el hueco sobrante es para las piezas, no para la bandera.
	spacer.visible = not main.vertical
	_secondary_btn = CT.text_button(Tr.t("BTN_CANCEL"), "back", "secondary", CT.menu_h("small"))
	_secondary_btn.name = "Secondary"
	_secondary_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_secondary_btn.pressed.connect(secondary)
	left.add_child(_secondary_btn)
	_ok_btn = CT.text_button(Tr.t("BTN_IDENTITY_OK"), "check", "primary", CT.menu_h("btn"))
	_ok_btn.name = "Confirm"
	_ok_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ok_btn.pressed.connect(func(): confirm())
	left.add_child(_ok_btn)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if main.vertical:
		right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	main.add_child(right)
	_tabs_row = HBoxContainer.new()
	_tabs_row.name = "Tabs"
	_tabs_row.add_theme_constant_override("separation", 6)
	right.add_child(_tabs_row)

	_scroll = ScrollContainer.new()
	_scroll.name = "PieceScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 80)
	right.add_child(_scroll)
	DragScroll.attach.call_deferred(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)

## Las tres pestanas (fondo, emblema, colores): la elegida en laton con labio.
## Se rehacen al cambiar (CartoonTheme.tab da otra pieza segun este elegida).
func _rebuild_tabs() -> void:
	for c in _tabs_row.get_children():
		_tabs_row.remove_child(c)
		c.queue_free()
	_tab_buttons.clear()
	for kind in TABS:
		var key: String = {"patterns": "LBL_IDENTITY_TAB_PATTERN", "emblems": "LBL_IDENTITY_TAB_EMBLEM",
			"colors": "LBL_IDENTITY_TAB_COLORS"}[kind]
		var title := Tr.t(key).capitalize()
		var glyph: String = {"patterns": "screen", "emblems": "star", "colors": "access"}[kind]
		var b := CT.tab("" if _small else title, glyph, kind == _tab, "window", CT.sem("ACCENT"), CT.menu_h("small"))
		b.name = "Tab_" + kind
		b.tooltip_text = title
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("selected", kind == _tab)
		var k: String = kind
		# Diferido: la pestana pulsada se rehace y no se puede quitar en su propia senal.
		b.pressed.connect(func(): select_tab.call_deferred(k))
		_tabs_row.add_child(b)
		_tab_buttons[kind] = b

func _relayout() -> void:
	if _window == null or not is_inside_tree():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	CT.place_window(_window, vp, Vector2(CARD_W, 560), _small)

# ── Refresco ──

func _refresh() -> void:
	if _preview == null:
		return
	_preview.texture = ColonyFlag.texture(_spec)
	_rebuild_tabs()
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
		var lock := 0 if unlocked else ColonyIdentity.piece_rank(kind, id)
		# La pieza entera arriba; debajo, la placa del rango si esta cerrada
		# (CartoonTheme.piece_tile: todas las fichas miden igual).
		var pic: Control
		if kind == "emblems" and String(id) == "none":
			pic = CT.none_piece(THUMB)
		else:
			var tex := TextureRect.new()
			tex.custom_minimum_size = THUMB
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.texture = ColonyFlag.small_texture(_thumb_spec(kind, id))
			if not unlocked:
				tex.modulate = Color(1, 1, 1, 0.5)
			pic = tex
		var btn := CT.piece_tile(pic, id == current, unlocked, lock)
		btn.name = "Piece_" + String(id)
		var label_key := ("FLAG_PATTERN_" if kind == "patterns" else "FLAG_EMBLEM_") + String(id).to_upper()
		btn.tooltip_text = Tr.t(label_key)
		if not unlocked:
			btn.tooltip_text += " · " + Tr.t("LBL_RANK_LOCK") % lock
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
		_content.add_child(CT.group_title(Tr.t(key)))
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
	var lock := 0 if unlocked else ColonyIdentity.piece_rank("colors", color_id)
	# La muestra entera arriba, sin nada pintado encima; debajo, la placa del
	# rango (cerrada) o la de "no se leeria" (abierta pero no vale aqui).
	var swatch := CT.piece_swatch(ColonyFlag.color_of(color_id), Vector2(SWATCH - 12.0, SWATCH - 16.0), not allowed)
	var btn := CT.piece_tile(swatch, String(_spec["colors"][slot]) == color_id, allowed, lock, unlocked and not allowed)
	btn.name = "Color_%d_%s" % [slot, color_id]
	# Minimo para el dedo: 48 de ancho y de alto.
	btn.custom_minimum_size = Vector2(maxf(btn.custom_minimum_size.x, 48.0), maxf(btn.custom_minimum_size.y, 48.0))
	btn.tooltip_text = Tr.t("COLONY_COLOR_" + color_id.to_upper())
	if unlocked and not allowed:
		btn.tooltip_text += " · " + Tr.t("LBL_IDENTITY_UNREADABLE")
	elif not unlocked:
		btn.tooltip_text += " · " + Tr.t("LBL_RANK_LOCK") % lock
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

## Cambia el texto de una pastilla (su etiqueta y la meta "text").
func _set_button_text(b: Button, text_s: String) -> void:
	b.set_meta("text", text_s)
	for l in b.find_children("*", "Label", true, false):
		(l as Label).text = text_s
		return
