extends CanvasLayer
## Construction menu: a "Build" button that opens a scrollable panel with building options.
## Loads all .tres from data/buildings/ and creates buttons for each.

var _panel: PanelContainer
var _build_btn: Button
var _is_open: bool = false

func _ready() -> void:
	layer = 10
	_setup_ui()

func _setup_ui() -> void:
	# Root container anchored to bottom-center
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Build button at bottom center
	_build_btn = Button.new()
	_build_btn.text = "CONSTRUIR"
	_build_btn.custom_minimum_size = Vector2(160, 45)
	_build_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_btn.position = Vector2(-80, -55)
	_style_button(_build_btn, Color(0.2, 0.5, 0.2, 0.85))
	_build_btn.add_theme_font_size_override("font_size", 16)
	_build_btn.pressed.connect(_toggle_panel)
	root.add_child(_build_btn)

	# Panel grows UPWARD from above the build button
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.custom_minimum_size = Vector2(360, 0)
	_panel.position = Vector2(-180, -110)
	_panel.visible = false

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.12, 0.92)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", panel_style)
	root.add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 300)
	_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Title row with close button
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	var title := Label.new()
	title.text = "Edificios disponibles"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	_style_button(close_btn, Color(0.5, 0.15, 0.15, 0.8))
	close_btn.pressed.connect(_toggle_panel)
	title_row.add_child(close_btn)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	vbox.add_child(sep)

	# Load all building .tres
	var buildings := _load_all_buildings()
	for data in buildings:
		var btn := _create_building_button(data)
		vbox.add_child(btn)

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open

func _create_building_button(data: BuildingData) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(320, 55)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var cost_parts: Array = []
	if data.cost_gold > 0:
		cost_parts.append(str(data.cost_gold) + " oro")
	if data.cost_steel > 0:
		cost_parts.append(str(data.cost_steel) + " acero")
	if data.cost_oil > 0:
		cost_parts.append(str(data.cost_oil) + " petroleo")
	if data.cost_wood > 0:
		cost_parts.append(str(data.cost_wood) + " madera")
	var cost_str := " | ".join(cost_parts) if cost_parts.size() > 0 else "Gratis"

	btn.text = "%s [%dx%d]\n%s" % [data.display_name, data.grid_size.x, data.grid_size.y, cost_str]

	_style_button(btn, Color(0.18, 0.18, 0.22, 0.85))
	btn.add_theme_font_size_override("font_size", 13)

	btn.pressed.connect(func():
		EventBus.building_selected_for_placement.emit(data)
		_is_open = false
		_panel.visible = false
	)
	return btn

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

func _style_button(btn: Button, bg_color: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_color
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = bg_color.lightened(0.2)
	hover.set_corner_radius_all(8)
	hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = bg_color.lightened(0.35)
	pressed.set_corner_radius_all(8)
	pressed.set_content_margin_all(8)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
