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
## Las paginas largas (HelpCatalog.is_page: topes, mejoras, eras, taller, torres)
## se leen aqui mismo, en grande y sin reloj, con "Volver" a la lista
## (feat/topes-mejoras-ayuda). Lo de arriba (interruptor, herramientas, lista)
## va en _list_mode; la pagina, en _page_mode.
var _list_mode: VBoxContainer
var _page_mode: VBoxContainer
var _page_title: Label
var _page_body: Label
var _page_scroll: ScrollContainer
var _page_id := ""

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
	_show_list()
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

	_list_mode = VBoxContainer.new()
	_list_mode.name = "ListMode"
	_list_mode.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_mode.add_theme_constant_override("separation", UITheme.SEPARATION)
	col.add_child(_list_mode)
	_build_page_mode(col)
	col = _list_mode

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
		TutorialManager.replay_guide()))
	tools.add_child(_tool_button("BTN_STORY", func():
		close()
		TutorialManager.show_prologue()))
	# El combate guiado otra vez en la proxima pelea (docs/23 §2.4).
	var combat_replay := _tool_button("BTN_CGUIDE_REPLAY", func():
		close()
		TutorialManager.replay_combat_lessons()
		EventBus.notification_posted.emit(Tr.t("MSG_CGUIDE_REPLAY"), "notice", UITheme.INFO))
	combat_replay.name = "CombatGuideReplay"
	tools.add_child(combat_replay)
	# La guia rapida (cuatro bloques en una pantalla): ya no sale sola al empezar
	# (14-10), pero aqui se puede volver a ver entera (feat/topes-mejoras-ayuda).
	var quick := _tool_button("BTN_QUICK_GUIDE", func():
		close()
		var tp := get_tree().get_first_node_in_group("tutorial_panel")
		if tp != null and tp.has_method("open_quick_guide"):
			tp.open_quick_guide())
	quick.name = "QuickGuideOpen"
	tools.add_child(quick)

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
	b.tooltip_text = HelpCatalog.summary(id)
	UITheme.style_card_button(b, UITheme.BTN.lightened(0.05), UITheme.INFO)
	b.pressed.connect(func():
		if HelpCatalog.is_page(id):
			show_page(id)
			return
		close()
		TutorialManager.reopen_help(id))
	return b

# ── Paginas largas ───────────────────────────────────────────────────

func _build_page_mode(col: VBoxContainer) -> void:
	_page_mode = VBoxContainer.new()
	_page_mode.name = "PageMode"
	_page_mode.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_mode.add_theme_constant_override("separation", UITheme.SEPARATION)
	_page_mode.visible = false
	col.add_child(_page_mode)
	_page_title = UITheme.make_label("", "section", UITheme.ACCENT)
	_page_title.name = "PageTitle"
	_page_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_mode.add_child(_page_title)
	_page_scroll = ScrollContainer.new()
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_mode.add_child(_page_scroll)
	_page_body = UITheme.make_label("", "body", UITheme.TEXT)
	_page_body.name = "PageBody"
	_page_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_scroll.add_child(_page_body)
	var back := _tool_button("BTN_HELP_BACK", _show_list)
	back.name = "PageBack"
	_page_mode.add_child(back)

## Abre una pagina larga dentro del indice y la marca como vista.
func show_page(id: String) -> void:
	if not HelpCatalog.has(id):
		return
	if not _open:
		open()
	_page_id = id
	_page_title.text = HelpCatalog.title(id)
	_page_body.text = HelpCatalog.body(id)
	_page_scroll.scroll_vertical = 0
	_list_mode.visible = false
	_page_mode.visible = true
	TutorialManager.mark_help_seen(id)

func _show_list() -> void:
	_page_id = ""
	if _page_mode != null:
		_page_mode.visible = false
	if _list_mode != null:
		_list_mode.visible = true

## La pagina abierta ahora ("" en la lista). Para pruebas.
func current_page() -> String:
	return _page_id

func page_text() -> String:
	return _page_body.text if _page_body != null else ""

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
