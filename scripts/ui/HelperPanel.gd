extends CanvasLayer
## In-game helper: on-screen callouts anchored to the HUD panels they explain,
## plus a building guide modal describing every building.
##
## It is switched on and off from the AYUDA entry of the ☰ menu (A6). It used
## to be a floating "?" next to the menu: one more button in a corner that was
## already full. The on/off state persists in user://settings.cfg
## (GameConfig.ui_helper_visible).
##
## The callouts go quiet on their own (A4) while any UIManager window is open
## and from the moment the Storm is announced until the Tithe is settled: they
## cover half the screen and at those moments something else matters. Going
## quiet never changes the player's preference: they come back afterwards.
##
## Each callout is placed by UILayoutManager (slots tip_*), stacked under the
## panel it talks about, so it follows the HUD when the HUD changes size
## instead of living at fixed pixel offsets that stop being true.

## Node name of the Skirmish callout, so tests and tools can find it.
const SKIRMISH_CALLOUT_NAME := "SkirmishCallout"
## Width of the Skirmish callout and the gap it keeps from the sidebar button.
const SKIRMISH_CALLOUT_WIDTH := 240
const SKIRMISH_CALLOUT_GAP := 12
## Sidebar buttons hang from the right edge at offset_left = -176 (see
## SkirmishPanel/ArmyPanel); the callout sits to their left.
const SIDEBAR_BTN_LEFT := 176

var _callouts: Control
var _help_btn: Button
var _guide_btn: Button
var _guide_panel: PanelContainer
var _backdrop: ColorRect
var _guide_open := false
var _skirmish_callout: PanelContainer
var _sidebar_visible := false
var _storm_silenced := false
## While a building is being placed the touch camera tips step aside: the right
## column grows with rotate-building + CANCEL and the zoom tip would cover them.
var _placing := false
## The ☰ tip sits where the unfolded menu draws its buttons: it steps aside
## while the menu is open (the Skirmish tip, which points INTO the menu, stays).
var _menus_tip: Control
## Every layout-placed tip: panel_id -> its PanelContainer. _refresh_tips()
## decides each one's visibility from the rules below.
var _tips: Dictionary = {}
## Tips that only make sense with the touch buttons on screen, and the one that
## replaces them on a desktop.
const TOUCH_TIPS := ["HelperPanel.tip_camera_touch", "HelperPanel.tip_zoom"]
const DESKTOP_TIPS := ["HelperPanel.tip_camera"]

func _ready() -> void:
	# Above the HUD (10-11). UIManager stacks open windows from layer 12 up, so
	# at 14 a callout would draw OVER an open window: that is why the callouts
	# hide while any window is open (_refresh_callouts), instead of relying on
	# layer order.
	layer = 14
	_setup_ui()
	UIManager.register_panel(self, "HelperPanel.modal")
	UIManager.window_opened.connect(func(_w): _refresh_callouts())
	UIManager.window_closed.connect(func(_w): _refresh_callouts())
	# Cuando hay ceniza en camino, el tutorial se calla: sus globos tapan media
	# pantalla y en ese momento lo unico que importa es el indicador de fase.
	EventBus.storm_incoming.connect(func(_s): _set_storm_silenced(true))
	EventBus.tithe_resolved.connect(func(_paid, _taken): _set_storm_silenced(false))
	# Y vuelve si el aviso queda en nada: sin esto una falsa alarma dejaria los
	# globos callados hasta la siguiente cobranza, que puede no llegar nunca.
	EventBus.storm_false_alarm.connect(func(_deferred): _set_storm_silenced(false))
	EventBus.touch_controls_changed.connect(func(_enabled): _refresh_tips())
	# Ajustes > Interfaz tambien los enciende y apaga (HudRegistry).
	EventBus.helper_visibility_changed.connect(func(_vis): _refresh_callouts())
	# La pausa y el menu principal no estan en la pila de UIManager: sin esto
	# los globos se veian bajo el velo de la pausa. Un vigia que corre en pausa
	# mira get_tree().paused y avisa al cambiar.
	var watcher := Node.new()
	watcher.name = "PauseWatcher"
	watcher.process_mode = Node.PROCESS_MODE_ALWAYS
	watcher.set_script(_PauseWatcher)
	watcher.set("owner_panel", self)
	add_child(watcher)
	# Al pasar a pantalla estrecha (o volver) cambia que globos caben.
	UILayoutManager.layout_changed.connect(_refresh_tips)
	EventBus.building_selected_for_placement.connect(func(_d): _set_placing(true))
	EventBus.request_move_building.connect(func(_b): _set_placing(true))
	EventBus.building_placement_cancelled.connect(func(): _set_placing(false))
	EventBus.building_moved.connect(func(_from, _to): _set_placing(false))
	EventBus.building_deselected.connect(func(): _set_placing(false))
	# El globo de Escaramuzas sigue al boton lateral: mismo gate (hay Cuartel y
	# la barra esta abierta) y mismas señales que usa SkirmishPanel para decidirlo.
	EventBus.sidebar_toggled.connect(_on_sidebar_toggled)
	EventBus.building_placed.connect(func(_d, _c): _update_skirmish_callout())
	EventBus.building_demolished.connect(func(_n, _c): _update_skirmish_callout())
	EventBus.army_changed.connect(func(_a = null): _update_skirmish_callout())
	EventBus.game_new_started.connect(_update_skirmish_callout)
	EventBus.game_load_completed.connect(_update_skirmish_callout)
	_update_skirmish_callout()
	_refresh_tips()
	_refresh_callouts()

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# AYUDA — one more entry of the ☰ sidebar, same size and style as the rest.
	_help_btn = Button.new()
	_help_btn.name = "HelpButton"
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
	_add_tip(Tr.t("LBL_HELP_RESOURCES_POOL"), "HelperPanel.tip_resources")
	# Top-right: the ☰ menu, with the building guide right there
	var menus_box := _add_tip(Tr.t("LBL_HELP_MENUS"), "HelperPanel.tip_menus")
	_menus_tip = menus_box.get_parent()
	# Center column: under the objective banner
	_add_tip(Tr.t("LBL_HELP_OBJECTIVE"), "HelperPanel.tip_objective")
	# Bottom-center: construction flow, above the BUILD button
	_add_tip(Tr.t("LBL_HELP_BUILD"), "HelperPanel.tip_build")
	# Camera: one text for the touch D-pad, another for keyboard and mouse
	_add_tip(Tr.ti("LBL_HELP_CAMERA"), "HelperPanel.tip_camera_touch")
	_add_tip(Tr.ti("LBL_HELP_ZOOM"), "HelperPanel.tip_zoom")
	_add_tip(Tr.ti("LBL_HELP_CAMERA_DESKTOP"), "HelperPanel.tip_camera")
	# Right, beside the Skirmish sidebar button: one callout, shown only while
	# that button exists (first Barracks built, sidebar open). Never a wall.
	var skirmish_x := -(SIDEBAR_BTN_LEFT + SKIRMISH_CALLOUT_GAP + SKIRMISH_CALLOUT_WIDTH)
	var skirmish_y := UILayoutManager.get_sidebar_button_offset("SkirmishPanel.button")
	_skirmish_callout = _add_callout(Tr.t("LBL_HELP_SKIRMISH"), Control.PRESET_TOP_RIGHT, Vector2(skirmish_x, skirmish_y), SKIRMISH_CALLOUT_WIDTH)
	_skirmish_callout.name = SKIRMISH_CALLOUT_NAME
	_skirmish_callout.visible = false

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
func _add_tip(text: String, panel_id: String) -> VBoxContainer:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", UITheme.make_hud_card_style(UITheme.INFO, 1))
	UILayoutManager.apply_layout(panel_id, box)
	_callouts.add_child(box)
	_tips[panel_id] = box

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(inner)

	var label := UITheme.make_label(text, "small", UITheme.TEXT_BRIGHT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(label)
	return inner

## One tip at a fixed offset from a screen preset, with the text as the box's
## only child. Only the Skirmish tip still uses it: it points at a sidebar
## button, which is placed by offset too (get_sidebar_button_offset).
func _add_callout(text: String, preset: Control.LayoutPreset, offset: Vector2, width: int) -> PanelContainer:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", UITheme.make_hud_card_style(UITheme.INFO, 1))
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
## sidebar is open. Lives inside _callouts, so the AYUDA toggle and the storm
## silence still apply on top of this.
func _update_skirmish_callout(_arg = null) -> void:
	if _skirmish_callout == null:
		return
	# En pantalla estrecha no cabe a la izquierda del menu: se saldria por el borde.
	_skirmish_callout.visible = _sidebar_visible and ArmyManager.barracks_count() > 0 \
		and not UILayoutManager.is_narrow()

func _on_sidebar_toggled(is_visible: bool) -> void:
	_sidebar_visible = is_visible
	_help_btn.visible = is_visible
	_refresh_tips()
	_update_skirmish_callout()

## True while the Skirmish callout is actually on screen: its own gate passed
## AND the callout layer is on (the AYUDA toggle / storm silence hide the layer,
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
	result.sort_custom(func(a, b): return a.get_display_name() < b.get_display_name())
	return result

func _make_building_entry(data: BuildingData) -> VBoxContainer:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)

	var title := UITheme.make_label("%s  (%dx%d)" % [data.get_display_name(), data.grid_size.x, data.grid_size.y], "body", UITheme.ACCENT)
	entry.add_child(title)

	var meta := UITheme.make_label(_meta_line(data), "small", UITheme.TEXT_DIM)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_child(meta)

	if not data.get_description().is_empty():
		var desc := UITheme.make_label(data.get_description(), "small", UITheme.TEXT)
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
	EventBus.helper_visibility_changed.emit(vis)
	_refresh_callouts()
	if not vis and _guide_open:
		_toggle_guide()

## Shows the callouts if `vis` and nothing on screen asks them to be quiet.
## The menu entry dims when help is off, so the player sees the state.
func _set_callouts_visible(vis: bool) -> void:
	_callouts.visible = vis and not is_quiet()
	_help_btn.modulate = Color(1, 1, 1, 1.0 if vis else 0.55)

## The one place that decides whether the callouts show. Everything else just
## flips a reason and calls this. Pasada la tormenta o cerrada la ventana, los
## globos vuelven solo si el jugador no los habia apagado el mismo: callarlos no
## es cambiar su preferencia.
func _refresh_callouts() -> void:
	_set_callouts_visible(GameConfig.ui_helper_visible)

## Something more important is on screen: an open window, the pause or title
## menu (the tree is paused), or the Storm.
func is_quiet() -> bool:
	return _storm_silenced or UIManager.is_any_window_open() or get_tree().paused

func _set_storm_silenced(silenced: bool) -> void:
	_storm_silenced = silenced
	_refresh_callouts()

func is_showing_callouts() -> bool:
	return _callouts.visible

func _set_placing(placing: bool) -> void:
	_placing = placing
	_refresh_tips()

## Which layout tips show, one rule per line. The layer-wide reasons (help off,
## a window open, the Storm) live in _refresh_callouts; these are per tip.
func _refresh_tips() -> void:
	var touch := GameConfig.touch_controls_enabled()
	# El perfil movil (disposicion compacta) tampoco tiene sitio para seis globos.
	# Con la columna central bajada a la izquierda tampoco: los globos de
	# columna caerian encima del objetivo y de la camara.
	var narrow := UILayoutManager.is_narrow() or UILayoutManager.is_column_narrow() 		or DeviceProfile.layout_variant() == "compact"
	for panel_id in _tips:
		var show := true
		# Pantalla estrecha: solo caben los de NARROW_TIPS.
		if narrow and not panel_id in UILayoutConfig.NARROW_TIPS:
			show = false
		# Perfil movil: ni ese. En vertical caeria sobre las flechas; la intro
		# del tutorial y AYUDA > guia ya lo explican.
		if DeviceProfile.layout_variant() == "compact":
			show = false
		# Los de camara tactil, solo con los botones en pantalla y sin colocar.
		if panel_id in TOUCH_TIPS:
			show = show and touch and not _placing
		if panel_id in DESKTOP_TIPS:
			show = show and not touch
		# El del menu ☰ se aparta cuando el menu se despliega encima.
		if panel_id == "HelperPanel.tip_menus":
			show = show and not _sidebar_visible
		(_tips[panel_id] as Control).visible = show
	_update_skirmish_callout()

func _toggle_guide() -> void:
	_guide_open = not _guide_open
	_guide_panel.visible = _guide_open
	_backdrop.visible = _guide_open
	if _guide_open:
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)

## Vigia de la pausa: el arbol en pausa no llama al _process de HelperPanel.
const _PauseWatcher := preload("res://scripts/ui/PauseWatcher.gd")
