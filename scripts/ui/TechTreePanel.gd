extends CanvasLayer
## INVESTIGAR: el arbol tecnologico (rediseno fase 2, docs/28-guia-ui.md).
##
## Ventana crema con la cinta azul. Tres ramas de cinco niveles. Cada
## tecnologia es una tarjeta corta: "1 · Nombre" y su ventaja ("+10 %
## producción"). El color dice el estado: investigada (verde claro), disponible
## (crema con el borde de su rama), bloqueada (apagada, pero se puede tocar). El
## porque de la bloqueada y el lore, al mantener pulsado.
##
## Tocar una tarjeta la ELIGE, no la investiga. A la derecha, su ficha: nombre,
## nivel y rama, una frase de lore, la ventaja, el coste en iconos (en rojo lo
## que falta), el tiempo, el requisito, el porque y el boton INVESTIGAR.
##
## PC y tablet: las tres ramas lado a lado y la ficha a la derecha. Telefono (o
## lienzo estrecho): a la izquierda un carril con las tres ramas (solo icono),
## en medio la rama elegida y la ficha a la derecha; a pantalla completa.

const CT := preload("res://scripts/ui/CartoonTheme.gd")
const TextKit := preload("res://scripts/ui/TextKit.gd")

const BRANCHES := ["industrial", "military", "logistics"]
const BRANCH_GLYPHS := {"industrial": "wrench", "military": "army", "logistics": "market"}

var _panel: Control
var _win: Dictionary = {}
var _backdrop: ColorRect
var _tech_btn: Button
var _is_open := false
var _tech_buttons: Dictionary = {}
var _progress_label: Label
var _progress_bar: ProgressBar
var _branches_scroll: ScrollContainer
## Ramas + ficha, siempre lado a lado (la ficha a la derecha).
var _body: BoxContainer
var _rail: VBoxContainer
var _branch_cols: Dictionary = {}
var _branch_tabs: Dictionary = {}
var _shown_branch := "industrial"
var _narrow := false
var _detail: PanelContainer
var _selected := ""
var _d_name: Label
var _d_tier: Label
var _d_lore: Label
var _d_branch: Label
var _d_cost: HBoxContainer
var _d_time: Label
var _d_effect: Label
var _d_req: Label
var _d_reason: Label
var _research_btn: Button

## Ancho de la ficha de detalle (PC) y en telefono.
const DETAIL_WIDTH := 300.0
const DETAIL_WIDTH_PHONE := 250.0
## Por debajo de este ancho de lienzo las ramas van de una en una (carril).
const SIDE_DETAIL_MIN_WIDTH := 880.0
## Ancho minimo de una tarjeta.
const CARD_WIDTH := 170.0
const CARD_WIDTH_NARROW := 150.0
## Tamano de la ventana en PC.
const WINDOW_SIZE := Vector2(1120, 640)

## Las ramas no caben lado a lado en un lienzo de `width`: van de una en una,
## con el carril de ramas a la izquierda.
static func detail_below(width: float) -> bool:
	return width < SIDE_DETAIL_MIN_WIDTH

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)

func _ready() -> void:
	layer = 11
	_setup_ui()
	# La ficha nace con algo dentro (la primera que se puede investigar).
	_refresh_tech_states()
	_fit_scroll()
	UIManager.register_panel(self, "TechTreePanel.modal")
	EventBus.notification_posted.connect(func(_m, _c, _col): _request_refresh())
	# El motivo "faltan recursos" cambia con la bolsa.
	EventBus.resource_changed.connect(func(_t, _a, _d): _request_refresh())
	UILayoutManager.layout_changed.connect(_fit_scroll)
	get_viewport().size_changed.connect(_fit_scroll)
	# La barra de investigacion solo se mueve con el panel abierto.
	set_process(false)

## Repintar las 15 tarjetas solo con el panel abierto y una vez por fotograma.
var _refresh_queued := false
func _request_refresh() -> void:
	if not _is_open or _refresh_queued:
		return
	_refresh_queued = true
	_flush_refresh.call_deferred()

func _flush_refresh() -> void:
	_refresh_queued = false
	if _is_open:
		_refresh_tech_states()

func _process(_delta: float) -> void:
	if _is_open and TechTreeManager.is_researching():
		var progress := TechTreeManager.get_research_progress()
		_progress_bar.value = progress
		var current := TechTreeManager.get_current_research()
		var tech := TechTreeManager.get_tech(current.get("tech_id", ""))
		if not tech.is_empty():
			_progress_label.text = Tr.t("FMT_RESEARCHING") % [Tr.t(tech["name"]), int(progress * 100)]
		_progress_bar.visible = true
		_progress_label.visible = true
	elif _is_open:
		_progress_bar.visible = false
		_progress_label.visible = false

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# El boton lateral de la columna vieja: se conserva, oculto.
	_tech_btn = Button.new()
	_tech_btn.text = Tr.t("BTN_TECH")
	_tech_btn.custom_minimum_size = Vector2(164, UILayoutConfig.SIDEBAR_BTN_HEIGHT)
	_tech_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_tech_btn.offset_left = -176
	_tech_btn.offset_top = UILayoutManager.get_sidebar_button_offset("TechTreePanel.button")
	UITheme.style_card_button(_tech_btn, UITheme.BTN.lightened(0.05), UITheme.INFO)
	_tech_btn.pressed.connect(_toggle_panel)
	_tech_btn.visible = false
	root.add_child(_tech_btn)
	EventBus.sidebar_toggled.connect(func(vis: bool): _tech_btn.visible = vis)

	_backdrop = CT.veil()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _toggle_panel())
	root.add_child(_backdrop)

	_win = CT.window(Tr.t("UI2C_TECH_TITLE"), CT.sem("INFO"))
	_panel = _win["root"]
	_panel.name = "TechWindow"
	_panel.visible = false
	(_win["close"] as Button).pressed.connect(_toggle_panel)
	(_win["close"] as Button).tooltip_text = Tr.t("UI2C_CLOSE")
	(_win["panel"] as Control).gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			UIManager.focus_window(self))
	root.add_child(_panel)

	var vbox: VBoxContainer = _win["body"]

	# Que es el arbol, en una linea; el parrafo entero, al mantener.
	var intro := CT.label(Tr.t("LBL_TECH_INTRO_SHORT"), "small", CT.text("window", true))
	intro.name = "Intro"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.mouse_filter = Control.MOUSE_FILTER_PASS
	intro.tooltip_text = Tr.t("LBL_TECH_INTRO")
	vbox.add_child(intro)

	# Lo que se investiga ahora: frase corta y barra.
	_progress_label = CT.label("", "small", CT.text("window"))
	_progress_label.visible = false
	vbox.add_child(_progress_label)
	_progress_bar = CT.progress(0.0, CT.sem("INFO"), "window", 12)
	_progress_bar.visible = false
	vbox.add_child(_progress_bar)

	_body = HBoxContainer.new()
	_body.name = "TechBody"
	_body.add_theme_constant_override("separation", 12)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_body)

	# Carril de ramas (solo en lienzo estrecho).
	_rail = VBoxContainer.new()
	_rail.name = "BranchRail"
	_rail.add_theme_constant_override("separation", 6)
	_body.add_child(_rail)

	# Las ramas, en un scroll que se arrastra con el dedo.
	_branches_scroll = ScrollContainer.new()
	_branches_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_branches_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_branches_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_branches_scroll)
	var branches_row := HBoxContainer.new()
	branches_row.add_theme_constant_override("separation", 10)
	branches_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_branches_scroll.add_child(branches_row)

	for branch in BRANCHES:
		var col := VBoxContainer.new()
		col.name = "BranchCol_" + branch
		col.add_theme_constant_override("separation", 6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Cabecera: icono y nombre; que hace la rama, al mantener.
		var head_row := HBoxContainer.new()
		head_row.add_theme_constant_override("separation", 6)
		var g := CT.make_glyph(String(BRANCH_GLYPHS[branch]), 24, _branch_color(branch))
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head_row.add_child(g)
		var head := CT.label(Tr.t("TECH_BRANCH_" + branch.to_upper()), "button", CT.text("window"))
		head.name = "Branch_" + branch
		head.mouse_filter = Control.MOUSE_FILTER_PASS
		head.tooltip_text = Tr.t("TECH_BRANCH_" + branch.to_upper() + "_DESC")
		head_row.add_child(head)
		col.add_child(head_row)

		var techs := TechTreeManager.get_branch_techs(branch)
		techs.sort_custom(func(a, b): return a["tier"] < b["tier"])
		for tech in techs:
			var btn := _create_tech_button(tech, _branch_color(branch))
			col.add_child(btn)
			_tech_buttons[tech["id"]] = btn
		branches_row.add_child(col)
		_branch_cols[branch] = col

	_build_detail()
	_build_rail()

## Color propio de cada rama (borde de sus tarjetas e icono).
static func _branch_color(branch: String) -> Color:
	match branch:
		"industrial":
			return CT.sem("ACCENT")
		"military":
			return CT.sem("DANGER")
	return CT.sem("INFO")

func _build_rail() -> void:
	for child in _rail.get_children():
		_rail.remove_child(child)
		child.queue_free()
	_branch_tabs.clear()
	for branch in BRANCHES:
		var sel: bool = branch == _shown_branch
		var t := CT.tab("", String(BRANCH_GLYPHS[branch]), sel, "window", CT.sem("INFO") if sel else Color(0, 0, 0, 0), 48)
		t.name = "BranchTab_" + branch
		t.custom_minimum_size = Vector2(52, 48)
		t.tooltip_text = Tr.t("TECH_BRANCH_" + branch.to_upper())
		t.focus_mode = Control.FOCUS_NONE
		var b: String = branch
		t.pressed.connect(func(): _show_branch(b))
		_rail.add_child(t)
		_branch_tabs[branch] = t

## En lienzo estrecho, ensena solo la rama `branch`.
func _show_branch(branch: String) -> void:
	if branch == _shown_branch and _rail.get_child_count() > 0:
		_apply_branch_visibility()
		return
	_shown_branch = branch
	_build_rail()
	_apply_branch_visibility()
	_branches_scroll.scroll_vertical = 0

func _apply_branch_visibility() -> void:
	for branch in _branch_cols:
		(_branch_cols[branch] as Control).visible = not _narrow or branch == _shown_branch
	_rail.visible = _narrow

## Coloca la ventana y decide: tres ramas lado a lado o una con carril.
func _fit_scroll() -> void:
	if _branches_scroll == null or _panel == null or not is_inside_tree():
		return
	var vp := _vp()
	var ph := CT.is_phone()
	_narrow = ph or detail_below(vp.x)
	if ph:
		CT.fit_fullscreen(_win)
	else:
		CT.place_center(_win, vp, WINDOW_SIZE)
	if _detail != null:
		_detail.custom_minimum_size.x = DETAIL_WIDTH_PHONE if _narrow else DETAIL_WIDTH
	for btn in _tech_buttons.values():
		(btn as Button).custom_minimum_size.x = CARD_WIDTH_NARROW if _narrow else CARD_WIDTH
	_apply_branch_visibility()

func _create_tech_button(tech: Dictionary, branch_color: Color) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.focus_mode = Control.FOCUS_NONE
	# "1 · Eficiencia Básica" y "+10 % producción": dos lineas cortas. El coste,
	# el porque y el lore, en la ficha y al mantener pulsado.
	var text := tech_card_short(tech)
	btn.set_meta("base_text", text)
	btn.text = text
	btn.set_meta("branch_color", branch_color)
	var tech_id: String = tech["id"]
	btn.name = "Tech_" + tech_id
	_style_card(btn, tech_id, TechTreeManager.is_researched(tech_id), TechTreeManager.can_research(tech_id))
	_apply_blocker_text(btn, tech_id)
	# Tocar elige; investigar es el boton de la ficha.
	btn.pressed.connect(func(): select(tech_id))
	return btn

## Lo que dice una tarjeta: nivel y nombre, y la ventaja. Estatica para las pruebas.
static func tech_card_short(tech: Dictionary) -> String:
	var lines: Array = ["%d · %s" % [int(tech["tier"]), Tr.t(tech["name"])]]
	var advantage := advantage_text(tech)
	if advantage != "":
		lines.append(advantage)
	return "\n".join(lines)

## Lo fijo de una tarjeta en texto plano: nivel y nombre, coste y ventaja, una
## cosa por linea (para el tooltip y las pruebas).
static func tech_card_text(tech: Dictionary) -> String:
	var lines: Array = ["%d · %s" % [int(tech["tier"]), Tr.t(tech["name"])]]
	var cost: Dictionary = tech.get("cost", {})
	if not cost.is_empty():
		lines.append(TextKit.cost_text(cost))
	var advantage := advantage_text(tech)
	if advantage != "":
		lines.append(advantage)
	return "\n".join(lines)

## La ventaja en claro, con los numeros de GameConfig.tech_definitions. Estatica
## y publica para las pruebas. Varias ventajas van separadas por coma.
static func advantage_text(tech: Dictionary) -> String:
	var parts: Array = []
	var bonus: Dictionary = tech.get("bonus", {})
	for key in bonus:
		var val = bonus[key]
		match key:
			"production_mult": parts.append(Tr.t("TECH_ADV_PRODUCTION") % roundi(float(val) * 100.0))
			"storage_bonus": parts.append(Tr.t("TECH_ADV_STORAGE") % int(val))
			"market_spread_reduction": parts.append(Tr.t("TECH_ADV_SPREAD") % roundi(float(val) * 100.0))
			"morale_bonus": parts.append(Tr.t("TECH_ADV_MORALE") % int(val))
			"consumption_reduction": parts.append(Tr.t("TECH_ADV_CONSUMPTION") % roundi(float(val) * 100.0))
			"build_speed": parts.append(Tr.t("TECH_ADV_BUILD") % roundi(float(val) * 100.0))
	return ", ".join(parts)

## La linea de lore de una tecnologia: que es en el mundo del juego.
static func lore_text(tech_id: String) -> String:
	return Tr.t("TECH_LORE_" + tech_id)

func _refresh_tech_states() -> void:
	if _selected == "" or TechTreeManager.get_tech(_selected).is_empty():
		_selected = _default_selection()
	for tech_id in _tech_buttons:
		var btn: Button = _tech_buttons[tech_id]
		_style_card(btn, tech_id, TechTreeManager.is_researched(tech_id), TechTreeManager.can_research(tech_id))
		_apply_blocker_text(btn, tech_id)
	_refresh_detail()

## Investigada (verde claro), disponible (crema con el borde de su rama),
## bloqueada (apagada, pero se toca para leerla). La elegida, borde de laton.
func _style_card(btn: Button, tech_id: String, researched: bool, can_research: bool) -> void:
	var state := "open"
	if researched:
		state = "done"
	elif not can_research:
		state = "locked"
	var key := "%s|%s" % [state, tech_id == _selected]
	if btn.get_meta("style_key", "") == key:
		return
	btn.set_meta("style_key", key)
	CT.style_card_button(btn, state, tech_id == _selected, btn.get_meta("branch_color", Color(0, 0, 0, 0)))

# ── Ficha de la tecnologia elegida ────────────────────────────────────

func _build_detail() -> void:
	_detail = PanelContainer.new()
	_detail.name = "TechDetail"
	var ds := CT.card_style("window")
	ds.set_content_margin_all(10)
	_detail.add_theme_stylebox_override("panel", ds)
	_detail.custom_minimum_size.x = DETAIL_WIDTH
	_body.add_child(_detail)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_detail.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_d_name = CT.label("", "title", CT.text("window"))
	_d_name.name = "DetailName"
	_d_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_d_name)
	_d_tier = CT.label("", "small", CT.text("window", true))
	_d_tier.name = "DetailTier"
	_d_tier.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_d_tier)
	# La ventaja, lo primero: es lo que se compra.
	_d_effect = CT.label("", "button", CT.positive_text())
	_d_effect.name = "DetailEffect"
	_d_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_d_effect)
	# Una frase de lore (que es en el mundo).
	_d_lore = CT.para("", "window", true)
	_d_lore.name = "DetailLore"
	box.add_child(_d_lore)
	# La frase de la rama: al mantener pulsada la linea de nivel (menos texto).
	_d_branch = CT.para("", "window", true, "small")
	_d_branch.name = "DetailBranch"
	_d_branch.visible = false
	box.add_child(_d_branch)
	_d_req = CT.para("", "window", false, "small")
	_d_req.name = "DetailRequires"
	box.add_child(_d_req)

	# Fuera del scroll: coste, tiempo, porque y el boton.
	var cost_line := HBoxContainer.new()
	cost_line.add_theme_constant_override("separation", 8)
	outer.add_child(cost_line)
	_d_cost = CT.cost_strip({})
	_d_cost.name = "DetailCost"
	_d_cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_line.add_child(_d_cost)
	var clock := CT.make_glyph("clock", 20)
	clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost_line.add_child(clock)
	_d_time = CT.label("", "number", CT.text("window"))
	_d_time.name = "DetailTime"
	cost_line.add_child(_d_time)
	_d_reason = CT.why_label()
	_d_reason.name = "DetailReason"
	_d_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	outer.add_child(_d_reason)
	_research_btn = CT.text_pill(Tr.t("BTN_RESEARCH"), "primary", CT.h("big"))
	_research_btn.name = "ResearchButton"
	_research_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_research_btn.pressed.connect(_on_research_pressed)
	outer.add_child(_research_btn)

## Elige una tecnologia: su tarjeta se marca, la ficha la cuenta y, en lienzo
## estrecho, se ensena su rama.
func select(tech_id: String) -> void:
	if TechTreeManager.get_tech(tech_id).is_empty():
		return
	_selected = tech_id
	_refresh_tech_states()
	var branch := String(TechTreeManager.get_tech(tech_id).get("branch", ""))
	if branch != "" and branch != _shown_branch:
		_show_branch(branch)

func selected_tech() -> String:
	return _selected

func detail_panel() -> PanelContainer:
	return _detail

func research_button() -> Button:
	return _research_btn

func _on_research_pressed() -> void:
	if _selected == "" or not TechTreeManager.can_research(_selected):
		return
	TechTreeManager.start_research(_selected)
	_refresh_tech_states()

## Lo que la ficha ensena sin nada elegido: la que esta en curso, o la primera
## que se puede investigar ya, o la primera sin investigar.
func _default_selection() -> String:
	var current: String = String(TechTreeManager.get_current_research().get("tech_id", ""))
	if current != "":
		return current
	var first_open := ""
	for tech in TechTreeManager.get_all_techs():
		var id: String = tech["id"]
		if TechTreeManager.can_research(id):
			return id
		if first_open == "" and not TechTreeManager.is_researched(id):
			first_open = id
	if first_open != "":
		return first_open
	var all := TechTreeManager.get_all_techs()
	return String(all[0]["id"]) if not all.is_empty() else ""

func _refresh_detail() -> void:
	if _detail == null:
		return
	var tech := TechTreeManager.get_tech(_selected)
	_detail.visible = not tech.is_empty()
	if tech.is_empty():
		return
	var branch: String = String(tech.get("branch", ""))
	_d_name.text = Tr.t(tech["name"])
	_d_tier.text = Tr.t("FMT_TECH_TIER") % [int(tech["tier"]), Tr.t("TECH_BRANCH_" + branch.to_upper())]
	_d_branch.text = Tr.t("TECH_BRANCH_" + branch.to_upper() + "_DESC")
	_d_tier.tooltip_text = _d_branch.text
	_d_lore.text = lore_text(_selected)
	var researched := TechTreeManager.is_researched(_selected)
	var cost: Dictionary = tech.get("cost", {})
	var missing: Dictionary = {} if researched else TechTreeManager.get_missing_cost(_selected)
	CT.fill_cost_strip(_d_cost, cost, missing)
	_d_time.text = TextKit.short_time(GameConfig.get_duration(float(tech.get("duration", 30.0))))
	_d_time.tooltip_text = Tr.t("FMT_TECH_TIME") % _d_time.text
	_d_effect.text = advantage_text(tech)
	_d_req.text = requirement_text(tech)
	var met: bool = TechTreeManager.get_missing_prerequisites(_selected).is_empty()
	_d_req.add_theme_color_override("font_color", CT.text("window", true) if met else CT.danger_text())
	var current: String = String(TechTreeManager.get_current_research().get("tech_id", ""))
	var reason := ""
	if researched:
		reason = Tr.t("LBL_TECH_RESEARCHED")
	elif current == _selected:
		reason = Tr.t("LBL_TECH_IN_PROGRESS")
	else:
		reason = blocker_text(_selected)
	_d_reason.text = reason
	_d_reason.visible = reason != ""
	_d_reason.add_theme_color_override("font_color", CT.positive_text() if researched else CT.danger_text())
	_research_btn.disabled = not TechTreeManager.can_research(_selected)
	_research_btn.visible = not researched and current != _selected

## "Requiere: Eficiencia Basica" o "Sin requisitos". Estatica para las pruebas.
static func requirement_text(tech: Dictionary) -> String:
	var reqs: Array = tech.get("requires", [])
	if reqs.is_empty():
		return Tr.t("LBL_TECH_NO_REQ")
	var names: Array = []
	for req in reqs:
		names.append(Tr.t(TechTreeManager.get_tech(req).get("name", req)))
	return Tr.t("LBL_REQUIRES") % ", ".join(names)

## La tarjeta no lleva el porque a la vista (menos texto): va primero en su
## tooltip, con el coste y el lore. Se reescribe en cada refresco, sin apilarse.
func _apply_blocker_text(btn: Button, tech_id: String) -> void:
	var base: String = String(btn.get_meta("base_text", btn.text))
	btn.text = base
	var reason: String = blocker_text(tech_id)
	var tech := TechTreeManager.get_tech(tech_id)
	var lines: Array = []
	if reason != "":
		lines.append(reason)
	if not tech.is_empty() and not (tech.get("cost", {}) as Dictionary).is_empty():
		lines.append(TextKit.cost_text(tech["cost"]))
	lines.append(lore_text(tech_id))
	btn.tooltip_text = "\n".join(lines)

## El motivo legible. Publico para las pruebas; lee el veredicto del manager y no
## repite sus reglas.
func blocker_text(tech_id: String) -> String:
	match TechTreeManager.get_research_blocker(tech_id):
		"TECH_BLOCK_RESEARCHING":
			return Tr.t("TECH_BLOCK_RESEARCHING")
		"TECH_BLOCK_PREREQ":
			var names: Array = []
			for req in TechTreeManager.get_missing_prerequisites(tech_id):
				names.append(Tr.t(TechTreeManager.get_tech(req).get("name", req)))
			return Tr.t("TECH_BLOCK_PREREQ") % ", ".join(names)
		"TECH_BLOCK_COST":
			return Tr.t("TECH_BLOCK_COST") % TextKit.cost_text(TechTreeManager.get_missing_cost(tech_id))
	return ""

## Abre INVESTIGAR (barra de abajo, ficha del Laboratorio).
func open() -> void:
	if not _is_open:
		_toggle_panel()

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_backdrop.visible = _is_open
	set_process(_is_open)
	if _is_open:
		_fit_scroll()
		_refresh_tech_states()
		var branch := String(TechTreeManager.get_tech(_selected).get("branch", ""))
		if branch != "":
			_show_branch(branch)
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)
