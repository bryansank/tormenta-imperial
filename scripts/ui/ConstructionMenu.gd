extends CanvasLayer
## Construction menu: a "Build" button that opens a scrollable panel with building options.
## Buildings grouped by category with colored left border cards.

var _panel: PanelContainer
var _build_btn: Button
var _is_open: bool = false
var _root: Control

func _ready() -> void:
	layer = 10
	_setup_ui()
	EventBus.resource_unlocked.connect(_on_resource_unlocked)

func _on_resource_unlocked(_res_name: String) -> void:
	if _root:
		_root.queue_free()
	_setup_ui()

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)

	_build_btn = Button.new()
	_build_btn.text = Tr.t("BTN_BUILD")
	_build_btn.custom_minimum_size = Vector2(160, 48)
	_build_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_btn.position = Vector2(-80, -55)
	UITheme.style_button(_build_btn, UITheme.POSITIVE.darkened(0.15), UITheme.FONT_SECTION)
	_build_btn.pressed.connect(_toggle_panel)
	_root.add_child(_build_btn)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.custom_minimum_size = Vector2(370, 0)
	_panel.position = Vector2(-185, -110)
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UITheme.make_command_panel_style())
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	_root.add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(350, 320)
	_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	vbox.add_child(UITheme.make_panel_header(Tr.t("LBL_BUILDINGS_AVAILABLE"), _toggle_panel))

	# Workers status
	var workers_label := UITheme.make_label(
		Tr.t("LBL_WORKERS") % [PopulationManager.get_used_workers(), PopulationManager.get_population()],
		"small", UITheme.INFO
	)
	workers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(workers_label)

	vbox.add_child(UITheme.make_separator())

	# Load and group buildings
	var buildings := _load_all_buildings()
	var categories := {"production": [], "support": [], "military": [], "decoration": []}
	for data in buildings:
		if data.is_decoration:
			categories["decoration"].append(data)
		elif data.id in ["house", "warehouse"]:
			categories["support"].append(data)
		elif data.id in ["barracks", "tower"]:
			categories["military"].append(data)
		else:
			categories["production"].append(data)

	var cat_names := {
		"production": Tr.t("LBL_CAT_PRODUCTION"),
		"support": Tr.t("LBL_CAT_SUPPORT"),
		"military": Tr.t("LBL_CAT_MILITARY"),
		"decoration": Tr.t("LBL_CAT_DECORATION"),
	}
	var cat_colors := {
		"production": UITheme.CAT_PRODUCTION,
		"support": UITheme.CAT_SUPPORT,
		"military": UITheme.CAT_MILITARY,
		"decoration": UITheme.CAT_DECORATION,
	}

	for cat_id in ["production", "support", "military", "decoration"]:
		if categories[cat_id].is_empty():
			continue
		vbox.add_child(UITheme.section_header(cat_names[cat_id], cat_colors[cat_id]))
		for data in categories[cat_id]:
			var btn := _create_building_button(data, cat_colors[cat_id])
			vbox.add_child(btn)
		if cat_id != "decoration":
			vbox.add_child(UITheme.make_separator())

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	if _is_open:
		UIManager.open_window(self)
	else:
		UIManager.close_window(self)

func _create_building_button(data: BuildingData, cat_color: Color) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(330, 0)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var locked := _has_locked_resource_cost(data)

	var lines: Array = []
	lines.append("%s [%dx%d]" % [data.display_name, data.grid_size.x, data.grid_size.y])

	var cost_parts: Array = []
	if data.cost_gold > 0:
		cost_parts.append(str(data.cost_gold) + " " + Tr.res_name("gold"))
	if data.cost_steel > 0:
		cost_parts.append(str(data.cost_steel) + " " + Tr.res_name("steel"))
	if data.cost_oil > 0:
		cost_parts.append(str(data.cost_oil) + " " + Tr.res_name("oil"))
	if data.cost_wood > 0:
		cost_parts.append(str(data.cost_wood) + " " + Tr.res_name("wood"))
	lines.append(Tr.t("FMT_COST") % (" | ".join(cost_parts) if cost_parts.size() > 0 else Tr.t("LBL_FREE")))

	var prod_parts: Array = []
	if data.produces_gold > 0:
		prod_parts.append("+%d %s" % [data.produces_gold, Tr.res_name("gold")])
	if data.produces_steel > 0:
		prod_parts.append("+%d %s" % [data.produces_steel, Tr.res_name("steel")])
	if data.produces_oil > 0:
		prod_parts.append("+%d %s" % [data.produces_oil, Tr.res_name("oil")])
	if data.produces_wood > 0:
		prod_parts.append("+%d %s" % [data.produces_wood, Tr.res_name("wood")])
	if not prod_parts.is_empty():
		lines.append(Tr.t("FMT_PRODUCES") % " | ".join(prod_parts))

	var reqs := GameConfig.get_prerequisites(data.id)
	if not reqs.is_empty():
		lines.append(Tr.t("LBL_REQUIRES") % " + ".join(reqs))

	if data.workers_required > 0:
		lines.append(Tr.t("LBL_WORKERS_NEEDED") % data.workers_required)
	if data.population_capacity > 0:
		lines.append("+%d pop" % data.population_capacity)
	if data.morale_bonus > 0:
		lines.append("+%d moral" % data.morale_bonus)
	if locked:
		lines.append(Tr.t("LBL_LOCKED_RESOURCE"))

	btn.text = "\n".join(lines)

	if locked:
		UITheme.style_card_button(btn, UITheme.BTN_DISABLED, UITheme.TEXT_DIM)
		btn.disabled = true
	else:
		UITheme.style_card_button(btn, UITheme.CARD_BG, cat_color)

	# Add visual preview icon to the right side
	var preview := _create_building_preview(data)
	if preview:
		btn.add_child(preview)

	btn.pressed.connect(func():
		EventBus.building_selected_for_placement.emit(data)
		_is_open = false
		_panel.visible = false
	)
	return btn

func _has_locked_resource_cost(data: BuildingData) -> bool:
	if data.cost_steel > 0 and not ResourceManager.is_unlocked(ResourceManager.Type.STEEL):
		return true
	if data.cost_oil > 0 and not ResourceManager.is_unlocked(ResourceManager.Type.OIL):
		return true
	return false

func _create_building_preview(data: BuildingData) -> Control:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	container.size_flags_horizontal = Control.SIZE_SHRINK_END
	container.alignment = BoxContainer.ALIGNMENT_END

	# Grid size indicator
	var grid_label := UITheme.make_label(
		"%dx%d" % [data.grid_size.x, data.grid_size.y],
		"small", Color(0.7, 0.7, 0.7)
	)
	grid_label.custom_minimum_size = Vector2(40, 24)
	grid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	container.add_child(grid_label)

	# Color preview rectangle
	var color_preview := ColorRect.new()
	color_preview.color = data.mesh_color
	color_preview.custom_minimum_size = Vector2(32, 32)
	color_preview.modulate = Color.WHITE
	var border_stylebox := StyleBoxFlat.new()
	border_stylebox.set_border_enabled_all(true)
	border_stylebox.set_border_width_all(2)
	border_stylebox.border_color = Color(0.3, 0.3, 0.3, 0.8)
	color_preview.add_theme_stylebox_override("panel", border_stylebox)
	container.add_child(color_preview)

	return container

func _load_all_buildings() -> Array:
	var buildings: Array = []
	var dir := DirAccess.open("res://data/buildings")
	if not dir:
		return buildings
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res = load("res://data/buildings/" + file_name)
			if res is BuildingData and not res.is_core:
				buildings.append(res)
		file_name = dir.get_next()
	buildings.sort_custom(func(a, b): return a.display_name < b.display_name)
	return buildings
