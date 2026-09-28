extends CanvasLayer
## El indice de AYUDA: todas las ayudas vistas hasta ahora (y siempre las
## basicas), por categoria. Tocar una la vuelve a abrir, senalando su control.
##
## Se abre con `open()` desde quien quiera: el menu ☰ unico busca el primer nodo
## del grupo "help_index". Arriba, lo de siempre a mano: el interruptor de las
## ayudas automaticas (el mismo de Ajustes > Interfaz), la guia de edificios,
## repetir el tutorial y volver a leer la historia.
##
## Una ventana normal de UIManager: ESC la cierra y mientras esta abierta los
## globos se callan.

const HelpCatalog := preload("res://scripts/ui/HelpCatalog.gd")

const CARD_MAX := Vector2(640, 600)
const EDGE := 16.0

## HelperPanel, que lo crea. Para la guia de edificios.
var helper: Node = null

var _root: Control
var _backdrop: ColorRect
var _card: PanelContainer
var _list: VBoxContainer
var _auto_check: CheckButton
var _open := false

func _ready() -> void:
	add_to_group("help_index")
	_build()
	visible = false
	UIManager.register_panel(self, "HelpIndexPanel")
	get_viewport().size_changed.connect(_fit)

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	# Se abre tambien desde el menu de pausa o el principal, con el arbol parado.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh()
	_fit()
	UIManager.open_panel(self)

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	UIManager.close_panel(self)

## UIManager lo llama con ESC.
func _close() -> void:
	close()

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func is_open() -> bool:
	return _open

## Los ids que se listan ahora, por categoria. Para pruebas.
func listed_ids() -> Array:
	var out: Array = []
	for cat in HelpCatalog.CATEGORIES:
		out.append_array(_ids_for(cat))
	return out

func _ids_for(cat: String) -> Array:
	var out: Array = []
	for id in HelpCatalog.ids_in(cat):
		if not HelpCatalog.allowed(id):
			continue
		if HelpCatalog.is_basic(id) or TutorialManager.has_seen_help(id):
			out.append(id)
	return out

# ── Construccion ─────────────────────────────────────────────────────

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_backdrop = UITheme.make_backdrop()
	_backdrop.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			close())
	_root.add_child(_backdrop)

	_card = PanelContainer.new()
	_card.name = "Card"
	_card.add_theme_stylebox_override("panel", UITheme.make_panel_style())
	_root.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.SEPARATION)
	_card.add_child(col)
	col.add_child(UITheme.make_panel_header(Tr.t("LBL_HELP_INDEX_TITLE"), close))

	_auto_check = UITheme.make_check_button(Tr.t("LBL_HELP_AUTO"), GameConfig.ui_helper_visible,
		func(on: bool):
			if helper != null and helper.has_method("set_auto_help"):
				helper.set_auto_help(on)
			else:
				HudRegistry.set_hidden("HelperPanel.callouts", not on))
	_auto_check.name = "AutoHelp"
	col.add_child(_auto_check)

	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 8)
	tools.add_theme_constant_override("v_separation", 8)
	col.add_child(tools)
	tools.add_child(_tool_button("BTN_BUILDING_GUIDE", func():
		close()
		if helper != null and helper.has_method("open_building_guide"):
			helper.open_building_guide()))
	tools.add_child(_tool_button("BTN_GUIDE_REPLAY", func():
		close()
		TutorialManager.start_guide(true)))
	tools.add_child(_tool_button("BTN_STORY", func():
		close()
		TutorialManager.show_prologue()))

	col.add_child(UITheme.make_separator())
	var hint := UITheme.make_label(Tr.ti("LBL_HELP_INDEX_HINT"), "small", UITheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

func _tool_button(key: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = Tr.t(key)
	b.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H)
	UITheme.style_button(b, UITheme.BTN, UITheme.FONT_SMALL)
	b.pressed.connect(cb)
	return b

func _refresh() -> void:
	_auto_check.set_pressed_no_signal(GameConfig.ui_helper_visible)
	for c in _list.get_children():
		c.queue_free()
	for cat in HelpCatalog.CATEGORIES:
		var ids := _ids_for(cat)
		if ids.is_empty():
			continue
		_list.add_child(UITheme.section_header(Tr.t(HelpCatalog.CATEGORY_KEYS[cat]), UITheme.INFO.lightened(0.35)))
		for id in ids:
			_list.add_child(_entry(id))

func _entry(id: String) -> Button:
	var b := Button.new()
	b.name = "Help_" + id
	var seen := TutorialManager.has_seen_help(id)
	b.text = ("✓  " if seen else "•  ") + HelpCatalog.title(id)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H)
	b.tooltip_text = HelpCatalog.body(id)
	UITheme.style_card_button(b, UITheme.BTN.lightened(0.05), UITheme.INFO)
	b.pressed.connect(func():
		close()
		TutorialManager.reopen_help(id))
	return b

func _fit() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = minf(CARD_MAX.x, vp.x - EDGE * 2.0)
	var h: float = minf(CARD_MAX.y, vp.y - EDGE * 2.0)
	# Anclas al centro y margenes: el tamano lo dan las anclas, no el contenido
	# (la lista va en un scroll y no puede estirar la tarjeta fuera de pantalla).
	_card.custom_minimum_size = Vector2.ZERO
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.offset_left = -w * 0.5
	_card.offset_right = w * 0.5
	_card.offset_top = -h * 0.5
	_card.offset_bottom = h * 0.5
