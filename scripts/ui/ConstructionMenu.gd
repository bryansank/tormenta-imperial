extends CanvasLayer
## Construction menu: full-screen modal with category tabs, search bar,
## building grid with thumbnails, and a 3D preview panel for the selected building.

var _root: Control
var _backdrop: ColorRect
var _modal: PanelContainer
var _build_btn: Button
var _is_open := false

# Category state
var _all_buildings: Array = []
var _current_category := "all"
var _search_text := ""
var _cat_buttons: Dictionary = {}

# Building grid
var _grid_container: GridContainer
var _grid_scroll: ScrollContainer

# Detail panel (right side)
var _detail_panel: VBoxContainer
var _detail_name: Label
var _detail_cost: Label
var _detail_production: Label
var _detail_extras: Label
var _detail_size: Label
var _detail_build_btn: Button
var _selected_data: BuildingData = null

# 3D Preview
var _preview_viewport: SubViewport
var _preview_container: SubViewportContainer
var _preview_camera: Camera3D
var _preview_model: Node3D = null
var _preview_spin := 0.0

# Thumbnail cache
var _thumb_cache: Dictionary = {}  # building_id -> ImageTexture
var _thumb_rects: Dictionary = {}  # building_id -> TextureRect

const CATEGORIES := ["all", "production", "support", "military", "decoration"]

func _ready() -> void:
	layer = 12
	_load_buildings()
	_setup_ui()
	_generate_thumbnails()
	EventBus.resource_unlocked.connect(func(_r): _refresh_grid())
	EventBus.sidebar_toggled.connect(func(v): _build_btn.visible = v)
	_build_btn.visible = false  # Start collapsed, sidebar controls it
	UIManager.register_panel(self, "ConstructionMenu.modal")

func _process(delta: float) -> void:
	if _preview_model and _is_open and _selected_data:
		_preview_spin += delta * 0.5
		_preview_model.rotation.y = _preview_spin

func _load_buildings() -> void:
	_all_buildings.clear()
	var dir := DirAccess.open("res://data/buildings")
	if not dir:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res = load("res://data/buildings/" + file_name)
			if res is BuildingData and not res.is_core:
				_all_buildings.append(res)
		file_name = dir.get_next()
	_all_buildings.sort_custom(func(a, b): return a.display_name < b.display_name)

func _get_category(data: BuildingData) -> String:
	if data.is_decoration:
		return "decoration"
	if data.id in ["house", "warehouse"]:
		return "support"
	if data.id in ["barracks", "tower"]:
		return "military"
	return "production"

func _get_filtered_buildings() -> Array:
	var result: Array = []
	for data in _all_buildings:
		if _current_category != "all" and _get_category(data) != _current_category:
			continue
		if _search_text != "" and data.display_name.to_lower().find(_search_text.to_lower()) == -1:
			continue
		result.append(data)
	return result

# ══════════════════════════════════════════════════════════════════════
# ── UI Setup ──
# ══════════════════════════════════════════════════════════════════════

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Build button (bottom center)
	_build_btn = Button.new()
	_build_btn.text = Tr.t("BTN_BUILD")
	_build_btn.custom_minimum_size.y = 54
	UILayoutManager.apply_layout("ConstructionMenu.button", _build_btn)
	UITheme.style_button(_build_btn, UITheme.POSITIVE.darkened(0.1), UITheme.FONT_TITLE)
	_build_btn.pressed.connect(_open)
	_root.add_child(_build_btn)

	# Backdrop
	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close()
	)
	_root.add_child(_backdrop)

	# Main modal panel
	_modal = PanelContainer.new()
	UILayoutManager.apply_layout("ConstructionMenu.modal", _modal)
	_modal.visible = false
	_modal.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_modal.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			UIManager.focus_window(self)
	)
	_root.add_child(_modal)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	_modal.add_child(main_vbox)

	# ── Header: title + search + close ──
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	main_vbox.add_child(header)

	var title := UITheme.make_label(Tr.t("LBL_BUILDINGS_AVAILABLE"), "title", UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var search := LineEdit.new()
	search.placeholder_text = Tr.t("LBL_SEARCH")
	search.custom_minimum_size = Vector2(180, 32)
	search.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	search.add_theme_color_override("font_color", UITheme.TEXT)
	search.add_theme_color_override("font_placeholder_color", UITheme.TEXT_DIM)
	var search_style := StyleBoxFlat.new()
	search_style.bg_color = UITheme.BG_DARK
	search_style.set_corner_radius_all(UITheme.CORNER)
	search_style.set_content_margin_all(6)
	search_style.border_color = UITheme.ACCENT_DIM
	search_style.set_border_width_all(1)
	search.add_theme_stylebox_override("normal", search_style)
	var search_focus := search_style.duplicate()
	search_focus.border_color = UITheme.ACCENT
	search_focus.set_border_width_all(2)
	search.add_theme_stylebox_override("focus", search_focus)
	search.text_changed.connect(func(text):
		_search_text = text
		_refresh_grid()
	)
	header.add_child(search)

	header.add_child(UITheme.make_close_button(_close))

	# ── Category tabs ──
	var cat_bar := HBoxContainer.new()
	cat_bar.add_theme_constant_override("separation", 4)
	main_vbox.add_child(cat_bar)

	var cat_labels := {
		"all": Tr.t("LBL_CAT_ALL"),
		"production": Tr.t("LBL_CAT_PRODUCTION"),
		"support": Tr.t("LBL_CAT_SUPPORT"),
		"military": Tr.t("LBL_CAT_MILITARY"),
		"decoration": Tr.t("LBL_CAT_DECORATION"),
	}
	var cat_colors := {
		"all": UITheme.ACCENT,
		"production": UITheme.CAT_PRODUCTION,
		"support": UITheme.CAT_SUPPORT,
		"military": UITheme.CAT_MILITARY,
		"decoration": UITheme.CAT_DECORATION,
	}

	for cat_id in CATEGORIES:
		var btn := Button.new()
		btn.text = cat_labels.get(cat_id, cat_id)
		btn.custom_minimum_size = Vector2(0, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var is_active: bool = cat_id == _current_category
		UITheme.style_button(btn, cat_colors[cat_id].darkened(0.6 if not is_active else 0.2), UITheme.FONT_SMALL)
		var cid: String = cat_id  # capture
		btn.pressed.connect(func(): _select_category(cid))
		cat_bar.add_child(btn)
		_cat_buttons[cat_id] = btn

	main_vbox.add_child(UITheme.make_separator())

	# ── Content: grid (left) + detail (right) ──
	var content := HSplitContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.split_offset = 420
	main_vbox.add_child(content)

	# Left side: scrollable grid of building cards
	_grid_scroll = ScrollContainer.new()
	_grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(_grid_scroll)

	_grid_container = GridContainer.new()
	_grid_container.columns = 3
	_grid_container.add_theme_constant_override("h_separation", 6)
	_grid_container.add_theme_constant_override("v_separation", 6)
	_grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_scroll.add_child(_grid_container)

	# Right side: detail panel with 3D preview
	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size = Vector2(320, 0)
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(detail_scroll)

	_detail_panel = VBoxContainer.new()
	_detail_panel.add_theme_constant_override("separation", 8)
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail_panel)

	# 3D preview SubViewport
	_preview_viewport = SubViewport.new()
	_preview_viewport.size = Vector2i(300, 220)
	_preview_viewport.transparent_bg = true
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.world_3d = World3D.new()

	_preview_camera = Camera3D.new()
	_preview_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_preview_camera.size = 6.0
	_preview_camera.position = Vector3(4.0, 4.5, 4.0)
	_preview_camera.look_at(Vector3(0, 0.5, 0))
	_preview_viewport.add_child(_preview_camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	light.light_energy = 1.3
	_preview_viewport.add_child(light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-30, -150, 0)
	fill_light.light_energy = 0.5
	_preview_viewport.add_child(fill_light)

	_preview_container = SubViewportContainer.new()
	_preview_container.custom_minimum_size = Vector2(300, 220)
	_preview_container.stretch = true
	_preview_container.add_child(_preview_viewport)
	# Border around preview
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color(0.03, 0.03, 0.02, 1.0)
	preview_style.set_corner_radius_all(UITheme.CORNER)
	preview_style.border_color = UITheme.ACCENT_DIM
	preview_style.set_border_width_all(1)
	var preview_wrapper := PanelContainer.new()
	preview_wrapper.add_theme_stylebox_override("panel", preview_style)
	preview_wrapper.add_child(_preview_container)
	_detail_panel.add_child(preview_wrapper)

	# Detail labels
	_detail_name = UITheme.make_label("", "title", UITheme.TEXT_BRIGHT)
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_panel.add_child(_detail_name)

	_detail_size = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	_detail_size.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_panel.add_child(_detail_size)

	_detail_panel.add_child(UITheme.make_separator())

	_detail_cost = UITheme.make_label("", "body", UITheme.WARNING)
	_detail_cost.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail_panel.add_child(_detail_cost)

	_detail_production = UITheme.make_label("", "body", UITheme.POSITIVE)
	_detail_production.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail_panel.add_child(_detail_production)

	_detail_extras = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	_detail_extras.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail_panel.add_child(_detail_extras)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_panel.add_child(spacer)

	# Build button
	_detail_build_btn = Button.new()
	_detail_build_btn.text = Tr.t("BTN_BUILD")
	_detail_build_btn.custom_minimum_size = Vector2(0, 48)
	_detail_build_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(_detail_build_btn, UITheme.POSITIVE.darkened(0.1), UITheme.FONT_TITLE)
	_detail_build_btn.pressed.connect(_on_build_pressed)
	_detail_panel.add_child(_detail_build_btn)

	# Initial state: show placeholder
	_show_no_selection()
	_refresh_grid()

# ══════════════════════════════════════════════════════════════════════
# ── Open / Close ──
# ══════════════════════════════════════════════════════════════════════

func _open() -> void:
	_is_open = true
	_modal.visible = true
	_backdrop.visible = true
	_refresh_grid()
	UIManager.open_panel(self)

func _close() -> void:
	_is_open = false
	_modal.visible = false
	_backdrop.visible = false
	UIManager.close_panel(self)

func _toggle_panel() -> void:
	if _is_open:
		_close()
	else:
		_open()

# ══════════════════════════════════════════════════════════════════════
# ── Category Selection ──
# ══════════════════════════════════════════════════════════════════════

var _cat_colors := {
	"all": UITheme.ACCENT,
	"production": UITheme.CAT_PRODUCTION,
	"support": UITheme.CAT_SUPPORT,
	"military": UITheme.CAT_MILITARY,
	"decoration": UITheme.CAT_DECORATION,
}

func _select_category(cat_id: String) -> void:
	_current_category = cat_id
	# Update button styles
	for cid in _cat_buttons:
		var btn: Button = _cat_buttons[cid]
		var is_active: bool = cid == _current_category
		UITheme.style_button(btn, _cat_colors[cid].darkened(0.6 if not is_active else 0.2), UITheme.FONT_SMALL)
	_refresh_grid()

# ══════════════════════════════════════════════════════════════════════
# ── Grid (building cards) ──
# ══════════════════════════════════════════════════════════════════════

func _refresh_grid() -> void:
	for child in _grid_container.get_children():
		child.queue_free()

	var filtered := _get_filtered_buildings()
	for data in filtered:
		var card := _create_grid_card(data)
		_grid_container.add_child(card)

func _create_grid_card(data: BuildingData) -> PanelContainer:
	var locked := _has_locked_resource_cost(data)
	var cat_color: Color = _cat_colors.get(_get_category(data), UITheme.ACCENT)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(125, 110)
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.CARD_BG if not locked else UITheme.BTN_DISABLED
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	style.border_width_bottom = 3
	style.border_color = cat_color if not locked else UITheme.TEXT_DIM
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	# Thumbnail
	if _thumb_cache.has(data.id):
		var tex_rect := TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(64, 64)
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.texture = _thumb_cache[data.id]
		if locked:
			tex_rect.modulate = Color(0.4, 0.4, 0.4, 0.7)
		_thumb_rects[data.id] = tex_rect
		vbox.add_child(tex_rect)
	else:
		var placeholder := ColorRect.new()
		placeholder.custom_minimum_size = Vector2(64, 64)
		placeholder.color = data.mesh_color if not locked else data.mesh_color.darkened(0.5)
		vbox.add_child(placeholder)

	# Name
	var name_label := UITheme.make_label(data.display_name, "small", UITheme.TEXT if not locked else UITheme.TEXT_DIM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.custom_minimum_size.x = 110
	vbox.add_child(name_label)

	# Interaction
	if not locked:
		card.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_select_building(data)
		)
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.mouse_entered.connect(func():
			style.bg_color = UITheme.CARD_BG.lightened(0.15)
			_select_building(data)
		)
		card.mouse_exited.connect(func():
			style.bg_color = UITheme.CARD_BG
		)

	return card

# ══════════════════════════════════════════════════════════════════════
# ── Detail Panel (right side) ──
# ══════════════════════════════════════════════════════════════════════

func _show_no_selection() -> void:
	_selected_data = null
	_detail_name.text = Tr.t("LBL_SELECT_BUILDING")
	_detail_size.text = ""
	_detail_cost.text = ""
	_detail_production.text = ""
	_detail_extras.text = ""
	_detail_build_btn.visible = false
	_clear_preview_model()

func _select_building(data: BuildingData) -> void:
	if _selected_data == data:
		return
	_selected_data = data
	_preview_spin = 0.0

	# Name + size
	_detail_name.text = data.display_name
	_detail_size.text = "%dx%d" % [data.grid_size.x, data.grid_size.y]

	# Cost
	var cost_parts: Array = []
	if data.cost_gold > 0:
		cost_parts.append("%d %s" % [data.cost_gold, Tr.res_name("gold")])
	if data.cost_steel > 0:
		cost_parts.append("%d %s" % [data.cost_steel, Tr.res_name("steel")])
	if data.cost_oil > 0:
		cost_parts.append("%d %s" % [data.cost_oil, Tr.res_name("oil")])
	if data.cost_wood > 0:
		cost_parts.append("%d %s" % [data.cost_wood, Tr.res_name("wood")])
	_detail_cost.text = Tr.t("FMT_COST") % " | ".join(cost_parts) if not cost_parts.is_empty() else Tr.t("LBL_FREE")

	# Production
	var prod_parts: Array = []
	if data.produces_gold > 0:
		prod_parts.append("+%d %s" % [data.produces_gold, Tr.res_name("gold")])
	if data.produces_steel > 0:
		prod_parts.append("+%d %s" % [data.produces_steel, Tr.res_name("steel")])
	if data.produces_oil > 0:
		prod_parts.append("+%d %s" % [data.produces_oil, Tr.res_name("oil")])
	if data.produces_wood > 0:
		prod_parts.append("+%d %s" % [data.produces_wood, Tr.res_name("wood")])
	if data.production_interval > 0 and not prod_parts.is_empty():
		_detail_production.text = Tr.t("FMT_PRODUCES_EVERY") % [" | ".join(prod_parts), int(data.production_interval)]
	elif not prod_parts.is_empty():
		_detail_production.text = Tr.t("FMT_PRODUCES") % " | ".join(prod_parts)
	else:
		_detail_production.text = ""

	# Extras
	var extras: Array = []
	if data.workers_required > 0:
		extras.append(Tr.t("LBL_WORKERS_NEEDED") % data.workers_required)
	if data.population_capacity > 0:
		extras.append(Tr.t("LBL_POP_CAPACITY") % data.population_capacity)
	if data.morale_bonus > 0:
		extras.append(Tr.t("LBL_MORALE_BONUS") % data.morale_bonus)
	var reqs := GameConfig.get_prerequisites(data.id)
	if not reqs.is_empty():
		extras.append(Tr.t("LBL_REQUIRES") % " + ".join(reqs))
	_detail_extras.text = "\n".join(extras)

	# Build button
	_detail_build_btn.visible = true

	# 3D preview
	_load_preview_model(data)

func _load_preview_model(data: BuildingData) -> void:
	_clear_preview_model()
	if data.model_scene:
		_preview_model = data.model_scene.instantiate()
	else:
		_preview_model = DieselpunkBuildingFactory.create(data.id, GridManager.cell_size, data.grid_size)
	if not _preview_model:
		return
	_preview_viewport.add_child(_preview_model)
	# Adjust camera to fit building
	var max_dim := maxf(data.grid_size.x, data.grid_size.y) * GridManager.cell_size
	_preview_camera.size = max_dim * 2.8
	_preview_spin = 0.0

func _clear_preview_model() -> void:
	if _preview_model and is_instance_valid(_preview_model):
		_preview_model.queue_free()
		_preview_model = null

func _on_build_pressed() -> void:
	if _selected_data:
		EventBus.building_selected_for_placement.emit(_selected_data)
		_close()

# ══════════════════════════════════════════════════════════════════════
# ── Helpers ──
# ══════════════════════════════════════════════════════════════════════

func _has_locked_resource_cost(data: BuildingData) -> bool:
	if data.cost_steel > 0 and not ResourceManager.is_unlocked(ResourceManager.Type.STEEL):
		return true
	if data.cost_oil > 0 and not ResourceManager.is_unlocked(ResourceManager.Type.OIL):
		return true
	return false

# ══════════════════════════════════════════════════════════════════════
# ── Thumbnail Generation (background, for grid cards) ──
# ══════════════════════════════════════════════════════════════════════

func _generate_thumbnails() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.world_3d = World3D.new()

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.0
	camera.position = Vector3(3.5, 4.0, 3.5)
	camera.look_at(Vector3(0, 0.3, 0))
	viewport.add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	light.light_energy = 1.2
	viewport.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, -150, 0)
	fill.light_energy = 0.4
	viewport.add_child(fill)

	add_child(viewport)

	for data in _all_buildings:
		await _render_thumbnail(viewport, camera, data)

	viewport.queue_free()
	# Refresh grid now that thumbnails are ready
	_refresh_grid()

func _render_thumbnail(viewport: SubViewport, camera: Camera3D, data: BuildingData) -> void:
	var model: Node3D = null
	if data.model_scene:
		model = data.model_scene.instantiate()
	else:
		model = DieselpunkBuildingFactory.create(data.id, GridManager.cell_size, data.grid_size)
	if not model:
		return

	viewport.add_child(model)
	var max_dim := maxf(data.grid_size.x, data.grid_size.y) * GridManager.cell_size
	camera.size = max_dim * 2.5

	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

	var image := viewport.get_texture().get_image()
	var tex := ImageTexture.create_from_image(image)
	_thumb_cache[data.id] = tex

	if _thumb_rects.has(data.id) and is_instance_valid(_thumb_rects[data.id]):
		_thumb_rects[data.id].texture = tex

	model.queue_free()
