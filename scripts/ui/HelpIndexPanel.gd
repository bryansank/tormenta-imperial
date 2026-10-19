extends CanvasLayer
## El indice de AYUDA: todas las ayudas vistas hasta ahora (y siempre las
## basicas), por categoria. Tocar una la vuelve a abrir, senalando su control.
##
## Estilo nuevo (fase 2, docs/28): ventana crema con la cinta azul AYUDA.
##
##   [?Como funciona] [casa Edificios] [> Tutorial] [libro Historia] [tanque Combate]
##   Consejos solos ······························ (o  )
##   [?] Lo basico                       <- una tarjeta por categoria, con icono
##       [?] Construir ············· ✓   <- una fila por ayuda; ✓ si ya se vio
##
## Se abre con `open()` desde quien quiera: el menu ☰ busca el primer nodo del
## grupo "help_index". Las paginas largas (HelpCatalog.is_page: topes, mejoras,
## eras, taller, torres) se leen aqui mismo, sin reloj, con "Volver" a la
## lista: la primera parte entera y el resto por secciones que se despliegan al
## tocarlas (una frase a la vista, el detalle al pedirlo: docs/28 §9).
##
## Una ventana normal de UIManager: ESC la cierra y mientras esta abierta los
## globos se callan. Sin animaciones.

const HelpCatalog := preload("res://scripts/ui/HelpCatalog.gd")
const HelpCalloutScript := preload("res://scripts/ui/HelpCallout.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

const CARD_MAX := Vector2(760, 600)
const EDGE := 16.0
## El icono de cada categoria (CartoonIcon).
const CATEGORY_GLYPHS := {"basics": "help", "economy": "market", "storm": "storm", "army": "army"}

## HelperPanel, que lo crea. Para la guia de edificios.
var helper: Node = null

var _root: Control
var _backdrop: ColorRect
var _window: Control
var _card: PanelContainer
var _list: VBoxContainer
var _auto_check: CheckButton
var _open := false
var _small := false
var _list_mode: VBoxContainer
var _page_mode: VBoxContainer
var _page_title: Label
var _page_body: Label
var _page_sections: VBoxContainer
var _page_scroll: ScrollContainer
var _page_id := ""
var _page_full := ""
## La X (se corre a la izquierda del ☰ si la tapa).
var _close_btn: Control

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
	_small = CT.is_phone()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_backdrop = CT.veil()
	_backdrop.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			close())
	_root.add_child(_backdrop)

	var w := CT.menu_window(Tr.t("UI2M_HELP_TITLE"), CT.sem("INFO"), _small)
	_window = w["root"]
	_window.name = "HelpWindow"
	_root.add_child(_window)
	_card = w["panel"]
	_card.name = "Card"
	(w["close"] as Button).name = "CloseButton"
	(w["close"] as Button).tooltip_text = Tr.t("BTN_CLOSE")
	(w["close"] as Button).pressed.connect(close)
	_close_btn = w["close"]
	var col: VBoxContainer = w["body"]

	_list_mode = VBoxContainer.new()
	_list_mode.name = "ListMode"
	_list_mode.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_mode.add_theme_constant_override("separation", 6 if _small else 10)
	col.add_child(_list_mode)
	_build_page_mode(col)

	# Lo de siempre a mano: pastillas con icono (el nombre entero al mantener).
	var tools := HFlowContainer.new()
	tools.name = "Tools"
	tools.add_theme_constant_override("h_separation", 6)
	tools.add_theme_constant_override("v_separation", 6)
	_list_mode.add_child(tools)
	var quick := _tool_button("UI2M_HELP_HOW", "BTN_QUICK_GUIDE", "help", func():
		close()
		var tp := get_tree().get_first_node_in_group("tutorial_panel")
		if tp != null and tp.has_method("open_quick_guide"):
			tp.open_quick_guide())
	quick.name = "QuickGuideOpen"
	tools.add_child(quick)
	tools.add_child(_tool_button("UI2M_HELP_BUILDINGS", "BTN_BUILDING_GUIDE", "build", func():
		close()
		if helper != null and helper.has_method("open_building_guide"):
			helper.open_building_guide()))
	var replay := _tool_button("UI2M_HELP_TUTORIAL", "BTN_GUIDE_REPLAY", "next", func():
		close()
		TutorialManager.replay_guide())
	replay.name = "GuideReplay"
	tools.add_child(replay)
	var story := _tool_button("UI2M_HELP_STORY", "BTN_STORY", "game", func():
		close()
		TutorialManager.show_prologue())
	story.name = "StoryButton"
	tools.add_child(story)
	# El combate guiado otra vez en la proxima pelea (docs/23 §2.4).
	var combat_replay := _tool_button("UI2M_HELP_COMBAT", "BTN_CGUIDE_REPLAY", "army", func():
		close()
		TutorialManager.replay_combat_lessons()
		EventBus.notification_posted.emit(Tr.t("MSG_CGUIDE_REPLAY"), "notice", UITheme.INFO))
	combat_replay.name = "CombatGuideReplay"
	tools.add_child(combat_replay)

	# Las ayudas que salen solas (el mismo interruptor de Ajustes).
	_auto_check = CT.live_switch(GameConfig.ui_helper_visible, func(on: bool):
		if helper != null and helper.has_method("set_auto_help"):
			helper.set_auto_help(on)
		else:
			HudRegistry.set_hidden("HelperPanel.callouts", not on), "AutoHelp")
	_list_mode.add_child(CT.setting_row("AutoHelpRow", "help", Tr.t("UI2M_HELP_AUTO"), _auto_check, _small,
		null, Tr.t("LBL_HELP_AUTO")))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_mode.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 6)
	scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	pad.add_child(_list)

## Una herramienta: [icono] palabra corta; el nombre largo al mantener pulsado.
func _tool_button(short_key: String, tip_key: String, glyph: String, cb: Callable) -> Button:
	var b := CT.text_button(Tr.t(short_key), glyph, "info", CT.menu_h("small"), "body")
	b.tooltip_text = Tr.t(tip_key)
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
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		var ic := CT.make_glyph(String(CATEGORY_GLYPHS.get(cat, "help")), 26, CT.sem("INFO"))
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(ic)
		head.add_child(CT.label(Tr.t(HelpCatalog.CATEGORY_KEYS[cat]).capitalize(), "title", CT.text("window")))
		_list.add_child(head)
		for id in ids:
			_list.add_child(_entry(id, cat))

## Una fila: [icono de la categoria] Titulo ····· ✓ (vista). El resumen, al
## mantener pulsado.
func _entry(id: String, cat: String) -> Button:
	var seen := TutorialManager.has_seen_help(id)
	var b := CT.list_button(String(CATEGORY_GLYPHS.get(cat, "help")), HelpCatalog.title(id), _small,
		"check" if seen else "", false)
	b.name = "Help_" + id
	b.set_meta("text", HelpCatalog.title(id))
	b.tooltip_text = HelpCatalog.summary(id)
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
	_page_mode.add_theme_constant_override("separation", 8)
	_page_mode.visible = false
	col.add_child(_page_mode)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_page_mode.add_child(head)
	var back := CT.round_button("back", "secondary", CT.menu_h("small"), "", "window") as Button
	back.name = "PageBack"
	back.tooltip_text = Tr.t("BTN_HELP_BACK")
	back.set_meta("text", Tr.t("BTN_HELP_BACK"))
	back.pressed.connect(_show_list)
	head.add_child(back)
	_page_title = CT.label("", "title", CT.text("window"))
	_page_title.name = "PageTitle"
	_page_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_page_title)
	_page_scroll = ScrollContainer.new()
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_mode.add_child(_page_scroll)
	var page_col := VBoxContainer.new()
	page_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_col.add_theme_constant_override("separation", 8)
	_page_scroll.add_child(page_col)
	_page_body = CT.para("", "window")
	_page_body.name = "PageBody"
	_page_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_col.add_child(_page_body)
	_page_sections = VBoxContainer.new()
	_page_sections.name = "PageSections"
	_page_sections.add_theme_constant_override("separation", 6)
	page_col.add_child(_page_sections)

## Abre una pagina larga dentro del indice y la marca como vista. La primera
## parte (hasta el primer parrafo en blanco) va entera; cada parrafo siguiente
## es una seccion que ensena su primera frase y se despliega al tocarla.
func show_page(id: String) -> void:
	if not HelpCatalog.has(id):
		return
	if not _open:
		open()
	_page_id = id
	_page_full = HelpCatalog.body(id)
	_page_title.text = HelpCatalog.title(id)
	var parts := split_sections(_page_full)
	_page_body.text = String(parts[0]) if not parts.is_empty() else ""
	for c in _page_sections.get_children():
		c.queue_free()
	for i in range(1, parts.size()):
		_page_sections.add_child(_section(String(parts[i]), i))
	_page_scroll.scroll_vertical = 0
	_list_mode.visible = false
	_page_mode.visible = true
	TutorialManager.mark_help_seen(id)

## Los parrafos de una pagina (separados por una linea en blanco). Pura.
static func split_sections(text: String) -> Array:
	var out: Array = []
	for p in text.split("\n\n", false):
		var t := String(p).strip_edges()
		if t != "":
			out.append(t)
	return out

## Una seccion plegada: [+] su primera frase; tocarla ensena el parrafo entero.
func _section(text_s: String, index: int) -> Button:
	var short := HelpCalloutScript.first_sentence(text_s)
	var b := Button.new()
	b.name = "Section_%d" % index
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := CT.card_style("window")
	var sel := CT.card_style("window", true)
	for sb in [n, sel]:
		sb.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("hover_pressed", sel)
	b.add_theme_stylebox_override("focus", CT.box(Color(0, 0, 0, 0), CT.sem("ACCENT"), 3, CT.RADIUS_CARD + 2, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	row.offset_top = 6
	row.offset_bottom = -6
	b.add_child(row)
	var ic := CT.make_glyph("plus", 22, CT.sem("INFO"))
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(ic)
	var l := CT.para(short, "window")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	b.toggled.connect(func(on: bool): l.text = text_s if on else short)
	row.minimum_size_changed.connect(func():
		b.custom_minimum_size.y = row.get_combined_minimum_size().y + 12.0)
	b.custom_minimum_size.y = 48.0
	return b

func _show_list() -> void:
	_page_id = ""
	if _page_mode != null:
		_page_mode.visible = false
	if _list_mode != null:
		_list_mode.visible = true

## La pagina abierta ahora ("" en la lista). Para pruebas.
func current_page() -> String:
	return _page_id

## El texto entero de la pagina abierta (todas sus secciones).
func page_text() -> String:
	return _page_full if _page_id != "" else ""

func _fit() -> void:
	if _window == null or not is_inside_tree():
		return
	CT.place_window(_window, get_viewport().get_visible_rect().size, CARD_MAX, _small)
	CT.dodge_menu_button.call_deferred(_close_btn)
