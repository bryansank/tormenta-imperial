extends CanvasLayer
## Tech tree UI panel. Shows 3 branches with 5 tiers each.

var _panel: PanelContainer
var _backdrop: ColorRect
var _tech_btn: Button
var _is_open := false
var _tech_buttons: Dictionary = {}
var _progress_label: Label
var _progress_bar: ProgressBar

func _ready() -> void:
	layer = 11
	_setup_ui()
	EventBus.notification_posted.connect(func(_m, _c, _col): _refresh_tech_states())

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
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)

	_tech_btn = Button.new()
	_tech_btn.text = Tr.t("BTN_TECH")
	_tech_btn.custom_minimum_size = Vector2(120, 36)
	_tech_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_tech_btn.offset_left = -135
	_tech_btn.offset_top = 130
	UITheme.style_button(_tech_btn, UITheme.INFO.darkened(0.2))
	_tech_btn.pressed.connect(_toggle_panel)
	root.add_child(_tech_btn)

	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(_e): _toggle_panel())
	root.add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(540, 0)
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UITheme.make_panel_style())
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
	var branches_row := HBoxContainer.new()
	branches_row.add_theme_constant_override("separation", 12)
	vbox.add_child(branches_row)

	var branch_colors := {
		"industrial": UITheme.BRANCH_INDUSTRIAL,
		"military": UITheme.BRANCH_MILITARY,
		"logistics": UITheme.BRANCH_LOGISTICS,
	}

	for branch in ["industrial", "military", "logistics"]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		col.add_child(UITheme.section_header(
			Tr.t("TECH_BRANCH_" + branch.to_upper()), branch_colors[branch]
		))

		var techs := TechTreeManager.get_branch_techs(branch)
		techs.sort_custom(func(a, b): return a["tier"] < b["tier"])
		for tech in techs:
			var btn := _create_tech_button(tech, branch_colors[branch])
			col.add_child(btn)
			_tech_buttons[tech["id"]] = btn

		branches_row.add_child(col)

func _create_tech_button(tech: Dictionary, branch_color: Color) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(155, 0)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var researched := TechTreeManager.is_researched(tech["id"])
	var can_research := TechTreeManager.can_research(tech["id"])

	var lines: Array = []
	lines.append("T%d: %s" % [tech["tier"], Tr.t(tech["name"])])

	var cost_parts: Array = []
	for res_name in tech.get("cost", {}):
		cost_parts.append("%d %s" % [tech["cost"][res_name], Tr.res_name(res_name)])
	if not cost_parts.is_empty():
		lines.append(Tr.t("FMT_COST") % " | ".join(cost_parts))

	for key in tech.get("bonus", {}):
		var val = tech["bonus"][key]
		match key:
			"production_mult": lines.append("+%d%% %s" % [int(val * 100), Tr.t("LBL_PRODUCTION")])
			"storage_bonus": lines.append("+%d %s" % [val, Tr.t("LBL_STORAGE")])
			"market_spread_reduction": lines.append("-%d%% spread" % [int(val * 100)])
			"morale_bonus": lines.append("+%d %s" % [val, Tr.t("LBL_MORALE_WORD")])
			"consumption_reduction": lines.append("-%d%% consumo" % [int(val * 100)])
			"build_speed": lines.append("+%d%% velocidad" % [int(val * 100)])

	btn.text = "\n".join(lines)

	if researched:
		UITheme.style_card_button(btn, UITheme.POSITIVE.darkened(0.4), UITheme.POSITIVE)
		btn.add_theme_color_override("font_color", UITheme.POSITIVE)
		btn.disabled = true
	elif can_research:
		UITheme.style_card_button(btn, branch_color.darkened(0.6), branch_color)
	else:
		UITheme.style_card_button(btn, UITheme.BTN_DISABLED, UITheme.TEXT_DIM)
		btn.disabled = true

	var tech_id: String = tech["id"]
	btn.pressed.connect(func():
		TechTreeManager.start_research(tech_id)
		_refresh_tech_states()
	)
	return btn

func _refresh_tech_states() -> void:
	for tech_id in _tech_buttons:
		var btn: Button = _tech_buttons[tech_id]
		var researched := TechTreeManager.is_researched(tech_id)
		var can_research := TechTreeManager.can_research(tech_id)
		if researched:
			btn.disabled = true
			btn.add_theme_color_override("font_color", UITheme.POSITIVE)
		elif can_research:
			btn.disabled = false
			btn.add_theme_color_override("font_color", UITheme.TEXT)
		else:
			btn.disabled = true
			btn.add_theme_color_override("font_color", UITheme.TEXT_DIM)

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_backdrop.visible = _is_open
	if _is_open:
		_refresh_tech_states()
		UIManager.open_window(self)
	else:
		UIManager.close_window(self)
