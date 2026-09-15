extends CanvasLayer
## In-game helper: on-screen callouts anchored to the HUD panels they explain,
## plus a building guide modal describing every building.
##
## It is switched on and off from the AYUDA entry of the ☰ menu (A6). It used
## to be a floating "?" next to the menu: one more button in a corner that was
## already full. The on/off state persists in user://settings.cfg
## (GameConfig.ui_helper_visible).
##
## The callouts go quiet on their own (A4) while any window is open, while the
## ☰ menu is unfolded, and from the moment the Storm is announced until the
## Tithe is settled: they cover half the screen and at those moments something
## else matters. Going quiet never changes the player's preference: they come
## back afterwards.
##
## Each callout is placed by UILayoutManager (slots tip_*), stacked under the
## panel it talks about, so it follows the HUD when the HUD changes size
## instead of living at fixed pixel offsets that stop being true.

var _callouts: Control
var _help_btn: Button
var _guide_btn: Button
var _guide_panel: PanelContainer
var _backdrop: ColorRect
var _guide_open := false
var _storm_silenced := false
var _sidebar_open := false
## Callouts that only make sense with the touch buttons on screen, and the one
## that replaces them on a desktop.
var _touch_tips: Array[Control] = []
var _desktop_tips: Array[Control] = []

func _ready() -> void:
	layer = 14  # Above HUD (10), below modal panels (15)
	_setup_ui()
	UIManager.register_panel(self, "HelperPanel.modal")
	UIManager.window_opened.connect(func(_w): _refresh_callouts())
	UIManager.window_closed.connect(func(_w): _refresh_callouts())
	EventBus.sidebar_toggled.connect(_on_sidebar_toggled)
	# Cuando hay ceniza en camino, el tutorial se calla: sus globos tapan media
	# pantalla y en ese momento lo unico que importa es el indicador de fase.
	EventBus.storm_incoming.connect(func(_s): _set_storm_silenced(true))
	EventBus.tithe_resolved.connect(func(_paid, _taken): _set_storm_silenced(false))
	# Y vuelve si el aviso queda en nada: sin esto una falsa alarma dejaria los
	# globos callados hasta la siguiente cobranza, que puede no llegar nunca.
	EventBus.storm_false_alarm.connect(func(_deferred): _set_storm_silenced(false))
	EventBus.touch_controls_changed.connect(func(_enabled): _refresh_touch_tips())
	_refresh_touch_tips()
	_refresh_callouts()

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# AYUDA — one more entry of the ☰ sidebar, same size and style as the rest.
	_help_btn = Button.new()
	_help_btn.text = Tr.t("BTN_HELP")
	_help_btn.tooltip_text = Tr.t("BTN_HELPER_TIP")
	_help_btn.custom_minimum_size = Vector2(UILayoutConfig.SIDEBAR_BTN_WIDTH, UILayoutConfig.SIDEBAR_BTN_HEIGHT)
	_help_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_help_btn.offset_left = -(UILayoutConfig.SIDEBAR_BTN_WIDTH + 12)
	_help_btn.offset_top = UILayoutManager.get_sidebar_button_offset("HelperPanel.button")
	UITheme.style_card_button(_help_btn, UITheme.BTN.lightened(0.05), UITheme.INFO)
	_help_btn.pressed.connect(_toggle_helper)
	_help_btn.visible = false  # Start collapsed with sidebar
	root.add_child(_help_btn)

	# Callout layer (tips anchored around the screen)
	_callouts = Control.new()
	_callouts.set_anchors_preset(Control.PRESET_FULL_RECT)
	_callouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_callouts)

	# Left column: under resources -> population (-> log when open)
	_add_callout(Tr.t("LBL_HELP_RESOURCES_POOL"), "HelperPanel.tip_resources")
	# Top-right: the ☰ menu, with the building guide right there
	var menus_box := _add_callout(Tr.t("LBL_HELP_MENUS"), "HelperPanel.tip_menus")
	# Center column: under the objective banner
	_add_callout(Tr.t("LBL_HELP_OBJECTIVE"), "HelperPanel.tip_objective")
	# Bottom-center: construction flow, above the BUILD button
	_add_callout(Tr.t("LBL_HELP_BUILD"), "HelperPanel.tip_build")
	# Camera: one text for the touch D-pad, another for keyboard and mouse
	_touch_tips.append(_add_callout(Tr.t("LBL_HELP_CAMERA"), "HelperPanel.tip_camera_touch").get_parent())
	_touch_tips.append(_add_callout(Tr.t("LBL_HELP_ZOOM"), "HelperPanel.tip_zoom").get_parent())
	_desktop_tips.append(_add_callout(Tr.t("LBL_HELP_CAMERA_DESKTOP"), "HelperPanel.tip_camera").get_parent())

	# Building guide button lives inside the menus callout: it is help too.
	_guide_btn = Button.new()
	_guide_btn.text = Tr.t("BTN_BUILDING_GUIDE")
	UITheme.style_card_button(_guide_btn, UITheme.BTN.lightened(0.05), UITheme.INFO)
	_guide_btn.pressed.connect(_toggle_guide)
	menus_box.add_child(_guide_btn)

	# ── Building guide modal ──
	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_toggle_guide()
	)
	root.add_child(_backdrop)

	_guide_panel = PanelContainer.new()
	_guide_panel.visible = false
	UILayoutManager.apply_layout("HelperPanel.modal", _guide_panel)
	_guide_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	root.add_child(_guide_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_guide_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	vbox.add_child(UITheme.make_panel_header(Tr.t("LBL_GUIDE_TITLE"), _toggle_guide))
	vbox.add_child(UITheme.make_separator())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)

	for data in _load_buildings():
		list.add_child(_make_building_entry(data))

## One tip box placed by the layout system. Returns its inner VBox so callers
## can add more than the text (the building guide button, for one).
## Steel-blue frame on purpose: brass is the HUD's state; blue is help.
func _add_callout(text: String, panel_id: String) -> VBoxContainer:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", UITheme.make_hud_card_style(UITheme.INFO, 1))
	UILayoutManager.apply_layout(panel_id, box)
	_callouts.add_child(box)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(inner)

	var label := UITheme.make_label(text, "small", UITheme.TEXT_BRIGHT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(label)
	return inner

func _load_buildings() -> Array:
	var result: Array = []
	var dir := DirAccess.open("res://data/buildings")
	if not dir:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res = load("res://data/buildings/" + file_name)
			if res is BuildingData:
				result.append(res)
		file_name = dir.get_next()
	result.sort_custom(func(a, b): return a.display_name < b.display_name)
	return result

func _make_building_entry(data: BuildingData) -> VBoxContainer:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)

	var title := UITheme.make_label("%s  (%dx%d)" % [data.display_name, data.grid_size.x, data.grid_size.y], "body", UITheme.ACCENT)
	entry.add_child(title)

	var meta := UITheme.make_label(_meta_line(data), "small", UITheme.TEXT_DIM)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_child(meta)

	if not data.description.is_empty():
		var desc := UITheme.make_label(data.description, "small", UITheme.TEXT)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_child(desc)
	return entry

## "Costo: 120 oro, 80 madera · Trabajadores: 3 · Produce: 8 oro"
func _meta_line(data: BuildingData) -> String:
	var parts: Array[String] = []

	var costs: Array[String] = []
	for pair in [[data.cost_gold, "gold"], [data.cost_steel, "steel"], [data.cost_oil, "oil"], [data.cost_wood, "wood"]]:
		if pair[0] > 0:
			costs.append("%d %s" % [pair[0], Tr.res_name(pair[1])])
	parts.append("%s: %s" % [Tr.t("LBL_GUIDE_COST"), ", ".join(costs) if not costs.is_empty() else Tr.t("LBL_FREE")])

	if data.workers_required > 0:
		parts.append("%s: %d" % [Tr.t("LBL_GUIDE_WORKERS"), data.workers_required])

	var produces: Array[String] = []
	for pair in [[data.produces_gold, "gold"], [data.produces_steel, "steel"], [data.produces_oil, "oil"], [data.produces_wood, "wood"]]:
		if pair[0] > 0:
			produces.append("%d %s" % [pair[0], Tr.res_name(pair[1])])
	if not produces.is_empty():
		parts.append("%s: %s" % [Tr.t("LBL_GUIDE_PRODUCES"), ", ".join(produces)])
	if data.population_capacity > 0:
		parts.append("%s: +%d" % [Tr.t("LBL_GUIDE_HOUSING"), data.population_capacity])
	if data.morale_bonus > 0:
		parts.append("%s: +%d" % [Tr.t("LBL_GUIDE_MORALE"), data.morale_bonus])

	return " · ".join(parts)

# ── Visibility ──

func _toggle_helper() -> void:
	var vis := not GameConfig.ui_helper_visible
	GameConfig.ui_helper_visible = vis
	GameConfig.save_user_settings()
	_refresh_callouts()
	if not vis and _guide_open:
		_toggle_guide()

func _on_sidebar_toggled(is_visible: bool) -> void:
	_sidebar_open = is_visible
	_help_btn.visible = is_visible
	_refresh_callouts()

func _set_storm_silenced(silenced: bool) -> void:
	_storm_silenced = silenced
	_refresh_callouts()

## The one place that decides whether the callouts show. Everything else just
## flips a reason and calls this.
func _refresh_callouts() -> void:
	var wanted: bool = GameConfig.ui_helper_visible
	var quiet: bool = _storm_silenced or _sidebar_open or UIManager.is_any_window_open()
	_callouts.visible = wanted and not quiet
	# The menu entry dims when help is off, so the player sees the state.
	_help_btn.modulate = Color(1, 1, 1, 1.0 if wanted else 0.55)

func is_showing_callouts() -> bool:
	return _callouts.visible

func _refresh_touch_tips() -> void:
	var touch := GameConfig.touch_controls_enabled()
	for tip in _touch_tips:
		tip.visible = touch
	for tip in _desktop_tips:
		tip.visible = not touch

func _toggle_guide() -> void:
	_guide_open = not _guide_open
	_guide_panel.visible = _guide_open
	_backdrop.visible = _guide_open
	if _guide_open:
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)
