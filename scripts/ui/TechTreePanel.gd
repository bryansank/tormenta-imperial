extends CanvasLayer
## Tech tree UI panel. Shows 3 branches with 5 tiers each.

var _panel: PanelContainer
var _backdrop: ColorRect
var _tech_btn: Button
var _is_open := false
var _tech_buttons: Dictionary = {}
var _progress_label: Label
var _progress_bar: ProgressBar
var _branches_scroll: ScrollContainer

## Alto del scroll de ramas: la pantalla menos cabecera y margenes.
func _fit_scroll() -> void:
	if _branches_scroll == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_branches_scroll.custom_minimum_size.y = clampf(vp.y - 150.0, 200.0, 540.0)

func _ready() -> void:
	layer = 11
	_setup_ui()
	UIManager.register_panel(self, "TechTreePanel.modal")
	EventBus.notification_posted.connect(func(_m, _c, _col): _refresh_tech_states())
	# El motivo "faltan recursos" cambia con la bolsa: con el panel abierto se
	# vuelve a escribir en cuanto entra o sale algo.
	EventBus.resource_changed.connect(func(_t, _a, _d): if _is_open: _refresh_tech_states())

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

	_tech_btn = Button.new()
	_tech_btn.text = Tr.t("BTN_TECH")
	_tech_btn.custom_minimum_size = Vector2(164, UILayoutConfig.SIDEBAR_BTN_HEIGHT)
	_tech_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_tech_btn.offset_left = -176
	_tech_btn.offset_top = UILayoutManager.get_sidebar_button_offset("TechTreePanel.button")
	UITheme.style_card_button(_tech_btn, UITheme.BTN.lightened(0.05), UITheme.INFO)
	_tech_btn.pressed.connect(_toggle_panel)
	_tech_btn.visible = false  # Start collapsed with sidebar
	root.add_child(_tech_btn)
	EventBus.sidebar_toggled.connect(func(vis: bool): _tech_btn.visible = vis)

	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _toggle_panel())
	root.add_child(_backdrop)

	_panel = PanelContainer.new()
	UILayoutManager.apply_layout("TechTreePanel.modal", _panel)
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_panel.add_child(vbox)

	vbox.add_child(UITheme.make_panel_header(Tr.t("LBL_TECH_TITLE"), _toggle_panel))

	_progress_label = UITheme.make_label("", "body", UITheme.INFO)
	_progress_label.visible = false
	vbox.add_child(_progress_label)

	_progress_bar = UITheme.make_progress_bar(UITheme.INFO, 12)
	_progress_bar.visible = false
	vbox.add_child(_progress_bar)

	# Branch columns
	# Las ramas van en un scroll: cinco niveles con su coste y su motivo de
	# bloqueo no caben en 720 px de alto, y un modal que se sale por arriba se
	# queda sin titulo ni boton de cerrar.
	_branches_scroll = ScrollContainer.new()
	_branches_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_branches_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_branches_scroll)
	_fit_scroll()
	UILayoutManager.layout_changed.connect(_fit_scroll)

	# La frase de arriba va dentro del scroll: fuera empujaria el modal por
	# encima de los 720 px.
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", UITheme.SEPARATION)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_branches_scroll.add_child(content)

	# Que es el arbol y que representa: sin esto nadie sabe para que subir.
	content.add_child(_wrapped_label(Tr.t("LBL_TECH_INTRO"), "body", UITheme.TEXT))

	var branches_row := HBoxContainer.new()
	branches_row.add_theme_constant_override("separation", 12)
	branches_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(branches_row)

	var branch_colors := {
		"industrial": UITheme.BRANCH_INDUSTRIAL,
		"military": UITheme.BRANCH_MILITARY,
		"logistics": UITheme.BRANCH_LOGISTICS,
	}

	for branch in ["industrial", "military", "logistics"]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Cabecera en laton para las tres ramas; la rama solo se nota en la
		# franja izquierda de sus tarjetas (docs/24-paleta.md).
		col.add_child(UITheme.section_header(
			Tr.t("TECH_BRANCH_" + branch.to_upper()), UITheme.ACCENT
		))
		# Que hace la rama y que significa en el mundo.
		col.add_child(_wrapped_label(
			Tr.t("TECH_BRANCH_" + branch.to_upper() + "_DESC"), "small", UITheme.TEXT_DIM
		))

		var techs := TechTreeManager.get_branch_techs(branch)
		techs.sort_custom(func(a, b): return a["tier"] < b["tier"])
		for tech in techs:
			var btn := _create_tech_button(tech, branch_colors[branch])
			col.add_child(btn)
			_tech_buttons[tech["id"]] = btn
			# El lore va fuera del boton: el texto del boton se reescribe con el
			# motivo del bloqueo en cada refresco.
			col.add_child(_wrapped_label(lore_text(tech["id"]), "small", UITheme.TEXT_DIM))

		branches_row.add_child(col)

func _create_tech_button(tech: Dictionary, branch_color: Color) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(155, 0)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# La ventaja es una frase entera: sin ajuste de linea ensancharia la columna.
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var researched := TechTreeManager.is_researched(tech["id"])
	var can_research := TechTreeManager.can_research(tech["id"])

	var lines: Array = []
	lines.append("T%d: %s" % [tech["tier"], Tr.t(tech["name"])])

	var cost_parts: Array = []
	for res_name in tech.get("cost", {}):
		cost_parts.append("%d %s" % [tech["cost"][res_name], Tr.res_name(res_name)])
	if not cost_parts.is_empty():
		lines.append(Tr.t("FMT_COST") % " | ".join(cost_parts))

	var advantage := advantage_text(tech)
	if advantage != "":
		lines.append(Tr.t("LBL_TECH_ADVANTAGE") % advantage)

	# El texto fijo se guarda aparte: el motivo del bloqueo se reescribe en cada
	# refresco y no puede ir acumulandose encima.
	btn.set_meta("base_text", "\n".join(lines))
	btn.text = "\n".join(lines)

	if researched:
		UITheme.style_card_button(btn, UITheme.POSITIVE.darkened(0.4), UITheme.POSITIVE)
		UITheme.set_label_color(btn, UITheme.POSITIVE)
		btn.disabled = true
	elif can_research:
		UITheme.style_card_button(btn, UITheme.CARD_BG, branch_color)
	else:
		UITheme.style_card_button(btn, UITheme.BTN_DISABLED, UITheme.TEXT_DIM)
		btn.disabled = true

	var tech_id: String = tech["id"]
	_apply_blocker_text(btn, tech_id)
	btn.pressed.connect(func():
		TechTreeManager.start_research(tech_id)
		_refresh_tech_states()
	)
	return btn

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

## Etiqueta con ajuste de linea, estilo solo via UITheme.
func _wrapped_label(text: String, size: String, color: Color) -> Label:
	var label := UITheme.make_label(text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _refresh_tech_states() -> void:
	for tech_id in _tech_buttons:
		var btn: Button = _tech_buttons[tech_id]
		var researched := TechTreeManager.is_researched(tech_id)
		var can_research := TechTreeManager.can_research(tech_id)
		if researched:
			btn.disabled = true
			UITheme.set_label_color(btn, UITheme.POSITIVE)
		elif can_research:
			btn.disabled = false
			UITheme.set_label_color(btn, UITheme.TEXT)
		else:
			btn.disabled = true
			UITheme.set_label_color(btn, UITheme.TEXT_DIM)
		_apply_blocker_text(btn, tech_id)

## Un boton apagado sin motivo parece un fallo. Debajo del coste va, escrito, lo
## primero que impide investigarla ahora mismo; si nada lo impide, nada.
func _apply_blocker_text(btn: Button, tech_id: String) -> void:
	var base: String = String(btn.get_meta("base_text", btn.text))
	var reason: String = blocker_text(tech_id)
	btn.text = base if reason == "" else "%s\n%s" % [base, reason]
	btn.tooltip_text = reason

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
			return Tr.t("TECH_BLOCK_COST") % Tr.amount_list(TechTreeManager.get_missing_cost(tech_id))
	return ""

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_backdrop.visible = _is_open
	if _is_open:
		_refresh_tech_states()
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)
