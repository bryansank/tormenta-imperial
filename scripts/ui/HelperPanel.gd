extends CanvasLayer
## In-game helper: an always-visible "?" button that toggles on-screen callouts
## explaining where each menu lives, how to build, and the camera controls —
## plus a building guide modal describing every building.
## The on/off state persists in user://settings.cfg (GameConfig.ui_helper_visible).

## Node name of the Skirmish callout, so tests and tools can find it.
const SKIRMISH_CALLOUT_NAME := "SkirmishCallout"
## Width of the Skirmish callout and the gap it keeps from the sidebar button.
const SKIRMISH_CALLOUT_WIDTH := 240
const SKIRMISH_CALLOUT_GAP := 12
## Sidebar buttons hang from the right edge at offset_left = -176 (see
## SkirmishPanel/ArmyPanel); the callout sits to their left.
const SIDEBAR_BTN_LEFT := 176

var _callouts: Control
var _helper_btn: Button
var _guide_btn: Button
var _guide_panel: PanelContainer
var _backdrop: ColorRect
var _guide_open := false
var _skirmish_callout: PanelContainer
var _sidebar_visible := false

func _ready() -> void:
	layer = 14  # Above HUD (10), below modal panels (15)
	_setup_ui()
	UIManager.register_panel(self, "HelperPanel.modal")
	# Cuando hay ceniza en camino, el tutorial se calla: sus globos tapan media
	# pantalla y en ese momento lo unico que importa es el indicador de fase.
	EventBus.storm_incoming.connect(func(_s): _set_callouts_visible(false))
	EventBus.tithe_resolved.connect(func(_paid, _taken): _restore_callouts())
	# Y vuelve si el aviso queda en nada: sin esto una falsa alarma dejaria los
	# globos callados hasta la siguiente cobranza, que puede no llegar nunca.
	EventBus.storm_false_alarm.connect(func(_deferred): _restore_callouts())
	# El globo de Escaramuzas sigue al boton lateral: mismo gate (hay Cuartel y
	# la barra esta abierta) y mismas señales que usa SkirmishPanel para decidirlo.
	EventBus.sidebar_toggled.connect(_on_sidebar_toggled)
	EventBus.building_placed.connect(func(_d, _c): _update_skirmish_callout())
	EventBus.building_demolished.connect(func(_n, _c): _update_skirmish_callout())
	EventBus.army_changed.connect(func(_a = null): _update_skirmish_callout())
	EventBus.game_new_started.connect(_update_skirmish_callout)
	EventBus.game_load_completed.connect(_update_skirmish_callout)
	_update_skirmish_callout()
	_set_callouts_visible(GameConfig.ui_helper_visible)

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# "?" toggle — always visible, next to the hamburger menu (top-right)
	_helper_btn = Button.new()
	_helper_btn.text = "?"
	_helper_btn.tooltip_text = Tr.t("BTN_HELPER_TIP")
	_helper_btn.custom_minimum_size = Vector2(UILayoutConfig.SIDEBAR_TOGGLE_SIZE, UILayoutConfig.SIDEBAR_TOGGLE_SIZE)
	_helper_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# A la izquierda del menu hamburguesa, mismo lado tactil (44 px).
	_helper_btn.offset_left = -(UILayoutConfig.SIDEBAR_TOGGLE_SIZE * 2 + 20)
	_helper_btn.offset_right = -(UILayoutConfig.SIDEBAR_TOGGLE_SIZE + 20)
	_helper_btn.offset_top = 10
	_helper_btn.offset_bottom = 10 + UILayoutConfig.SIDEBAR_TOGGLE_SIZE
	UITheme.style_button(_helper_btn, UITheme.INFO, UITheme.FONT_SECTION)
	_helper_btn.pressed.connect(_toggle_helper)
	root.add_child(_helper_btn)

	# Callout layer (tips anchored around the screen)
	_callouts = Control.new()
	_callouts.set_anchors_preset(Control.PRESET_FULL_RECT)
	_callouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_callouts)

	# Top-left: resources HUD
	_add_callout(Tr.t("LBL_HELP_RESOURCES"), Control.PRESET_TOP_LEFT, Vector2(12, 100), 250)
	# Top-right: hamburger menus (left of the sidebar area)
	_add_callout(Tr.t("LBL_HELP_MENUS"), Control.PRESET_TOP_RIGHT, Vector2(-282, 56), 270)
	# Top-center: current objective
	_add_callout(Tr.t("LBL_HELP_OBJECTIVE"), Control.PRESET_CENTER_TOP, Vector2(-130, 118), 260)
	# Bottom-center: construction flow
	_add_callout(Tr.t("LBL_HELP_BUILD"), Control.PRESET_CENTER_BOTTOM, Vector2(-150, -160), 300)
	# Bottom-left: camera pan
	_add_callout(Tr.t("LBL_HELP_CAMERA"), Control.PRESET_BOTTOM_LEFT, Vector2(20, -260), 220)
	# Bottom-right: rotate/zoom
	_add_callout(Tr.t("LBL_HELP_ZOOM"), Control.PRESET_BOTTOM_RIGHT, Vector2(-240, -260), 220)
	# Right, beside the Skirmish sidebar button: one callout, shown only while
	# that button exists (first Barracks built, sidebar open). Never a wall.
	var skirmish_x := -(SIDEBAR_BTN_LEFT + SKIRMISH_CALLOUT_GAP + SKIRMISH_CALLOUT_WIDTH)
	var skirmish_y := UILayoutManager.get_sidebar_button_offset("SkirmishPanel.button")
	_skirmish_callout = _add_callout(Tr.t("LBL_HELP_SKIRMISH"), Control.PRESET_TOP_RIGHT, Vector2(skirmish_x, skirmish_y), SKIRMISH_CALLOUT_WIDTH)
	_skirmish_callout.name = SKIRMISH_CALLOUT_NAME
	_skirmish_callout.visible = false

	# Building guide button (under the "?", only while helper is on)
	_guide_btn = Button.new()
	_guide_btn.text = Tr.t("BTN_BUILDING_GUIDE")
	_guide_btn.custom_minimum_size = Vector2(180, 34)
	_guide_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_guide_btn.offset_left = -282
	_guide_btn.offset_right = -102
	_guide_btn.offset_top = 10
	_guide_btn.offset_bottom = 44
	UITheme.style_card_button(_guide_btn, UITheme.BTN.lightened(0.05), UITheme.INFO)
	_guide_btn.pressed.connect(_toggle_guide)
	_callouts.add_child(_guide_btn)

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

## One anchored tip label with a dark framed background. Returns the box so a
## caller can toggle it later; most callouts are static and ignore it.
func _add_callout(text: String, preset: Control.LayoutPreset, offset: Vector2, width: int) -> PanelContainer:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.04, 0.88)
	style.border_color = UITheme.ACCENT_DIM
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	box.add_theme_stylebox_override("panel", style)
	box.set_anchors_preset(preset)
	box.offset_left = offset.x
	box.offset_top = offset.y
	box.offset_right = offset.x + width
	# Give a tiny nominal height and let the container's minimum size grow it
	# downward to fit the text — otherwise bottom-anchored boxes stretch to the
	# screen edge.
	box.offset_bottom = offset.y + 10
	box.grow_vertical = Control.GROW_DIRECTION_END
	box.custom_minimum_size = Vector2(width, 0)

	var label := UITheme.make_label(text, "small", UITheme.TEXT_BRIGHT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	_callouts.add_child(box)
	return box

## Same gate as SkirmishPanel's sidebar button: a Barracks exists and the
## sidebar is open. Lives inside _callouts, so the "?" toggle and the storm
## silence still apply on top of this.
func _update_skirmish_callout(_arg = null) -> void:
	if _skirmish_callout == null:
		return
	_skirmish_callout.visible = _sidebar_visible and ArmyManager.barracks_count() > 0

func _on_sidebar_toggled(is_visible: bool) -> void:
	_sidebar_visible = is_visible
	_update_skirmish_callout()

## True while the Skirmish callout is actually on screen: its own gate passed
## AND the callout layer is on (the "?" toggle / storm silence hide the layer,
## not the box). For tests and probes.
func is_skirmish_callout_shown() -> bool:
	return _skirmish_callout != null and _callouts.visible and _skirmish_callout.visible

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

func _toggle_helper() -> void:
	var vis := not GameConfig.ui_helper_visible
	GameConfig.ui_helper_visible = vis
	GameConfig.save_user_settings()
	_set_callouts_visible(vis)
	if not vis and _guide_open:
		_toggle_guide()

func _set_callouts_visible(vis: bool) -> void:
	_callouts.visible = vis
	_helper_btn.modulate = Color(1, 1, 1, 1.0 if vis else 0.55)

## Pasada la tormenta, los globos vuelven solo si el jugador no los habia
## apagado el mismo. Silenciarlos por una tormenta no es cambiar su preferencia.
func _restore_callouts() -> void:
	_set_callouts_visible(GameConfig.ui_helper_visible)

func _toggle_guide() -> void:
	_guide_open = not _guide_open
	_guide_panel.visible = _guide_open
	_backdrop.visible = _guide_open
	if _guide_open:
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)
