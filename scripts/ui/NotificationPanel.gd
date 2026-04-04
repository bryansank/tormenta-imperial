extends CanvasLayer
## Activity log and notification panel.
## Shows toast notifications and maintains a scrollable history.
## Status bar shows population, workers, and morale.

const MAX_LOG_ENTRIES := 50
const TOAST_DURATION := 4.0

var _panel: PanelContainer
var _log_btn: Button
var _is_open := false
var _log_entries: Array = []
var _log_vbox: VBoxContainer
var _toast_container: VBoxContainer
var _pop_label: Label
var _morale_label: Label
var _morale_bar: ProgressBar
var _workers_label: Label
var _status_panel: PanelContainer
var _objective_label: Label

func _ready() -> void:
	layer = 11
	_setup_ui()
	EventBus.notification_posted.connect(_on_notification)
	EventBus.population_changed.connect(_on_population_changed)
	EventBus.morale_changed.connect(_on_morale_changed)
	EventBus.workers_changed.connect(_on_workers_changed)
	EventBus.phase_advanced.connect(_on_phase_advanced)
	EventBus.milestone_completed.connect(func(_m): _update_objective_hint())
	_update_status_labels()
	_update_objective_hint()
	# Hide status bar until Phase 1 when pop/morale become relevant
	if ProgressionManager.current_phase < GameConfig.Phase.SETTLEMENT:
		_status_panel.visible = false

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Status bar (top-left below HUD)
	_status_panel = PanelContainer.new()
	var status_panel := _status_panel
	status_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	status_panel.position = Vector2(10, 54)
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = UITheme.PANEL_BG
	status_style.set_corner_radius_all(UITheme.CORNER)
	status_style.set_content_margin_all(10)
	status_style.border_color = UITheme.ACCENT_DIM
	status_style.set_border_width_all(2)
	status_style.border_width_left = 4
	status_style.border_color = UITheme.ACCENT
	status_style.shadow_color = Color(0, 0, 0, 0.4)
	status_style.shadow_size = 4
	status_panel.add_theme_stylebox_override("panel", status_style)
	root.add_child(status_panel)

	var status_vbox := VBoxContainer.new()
	status_vbox.add_theme_constant_override("separation", 5)
	status_panel.add_child(status_vbox)

	# Population row with icon
	var pop_row := HBoxContainer.new()
	pop_row.add_theme_constant_override("separation", 6)
	var pop_icon := UITheme.make_label("\u2302", "body", UITheme.CAT_SUPPORT)  # House icon
	pop_row.add_child(pop_icon)
	_pop_label = UITheme.make_label("", "small", UITheme.CAT_SUPPORT)
	pop_row.add_child(_pop_label)
	status_vbox.add_child(pop_row)

	# Workers row with icon
	var work_row := HBoxContainer.new()
	work_row.add_theme_constant_override("separation", 6)
	var work_icon := UITheme.make_label("\u2692", "body", UITheme.INFO)  # Hammer & pick
	work_row.add_child(work_icon)
	_workers_label = UITheme.make_label("", "small", UITheme.INFO)
	work_row.add_child(_workers_label)
	status_vbox.add_child(work_row)

	# Morale row with icon + progress bar
	var morale_row := HBoxContainer.new()
	morale_row.add_theme_constant_override("separation", 6)
	var morale_icon := UITheme.make_label("\u2665", "body", UITheme.WARNING)  # Heart
	morale_row.add_child(morale_icon)
	_morale_label = UITheme.make_label("", "small", UITheme.WARNING)
	morale_row.add_child(_morale_label)
	status_vbox.add_child(morale_row)

	# Morale bar
	_morale_bar = UITheme.make_progress_bar(UITheme.WARNING, 8)
	_morale_bar.custom_minimum_size.x = 110
	_morale_bar.max_value = 100.0
	_morale_bar.value = PopulationManager.get_morale()
	status_vbox.add_child(_morale_bar)

	# Log button integrated below status
	_log_btn = Button.new()
	_log_btn.text = Tr.t("BTN_LOG")
	_log_btn.custom_minimum_size = Vector2(0, 28)
	_log_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(_log_btn, UITheme.BTN, UITheme.FONT_SMALL)
	_log_btn.pressed.connect(_toggle_panel)
	status_vbox.add_child(_log_btn)

	# Objective hint (top-center)
	var obj_panel := PanelContainer.new()
	obj_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	obj_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	obj_panel.position = Vector2(-160, 54)
	obj_panel.custom_minimum_size = Vector2(320, 0)
	var obj_style := StyleBoxFlat.new()
	obj_style.bg_color = Color(0.08, 0.06, 0.04, 0.85)
	obj_style.set_corner_radius_all(UITheme.CORNER)
	obj_style.set_content_margin_all(10)
	obj_style.border_width_bottom = 2
	obj_style.border_color = UITheme.ACCENT
	obj_panel.add_theme_stylebox_override("panel", obj_style)
	obj_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(obj_panel)

	_objective_label = UITheme.make_label("", "small", UITheme.ACCENT)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_panel.add_child(_objective_label)

	# Toast container (bottom-left)
	_toast_container = VBoxContainer.new()
	_toast_container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_toast_container.position = Vector2(10, -200)
	_toast_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast_container.add_theme_constant_override("separation", 4)
	_toast_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_container)

	# Log panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_left = 10
	_panel.offset_right = 320
	_panel.offset_top = 168
	_panel.offset_bottom = -10
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	root.add_child(_panel)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(panel_vbox)

	panel_vbox.add_child(UITheme.make_panel_header(Tr.t("LBL_LOG_TITLE"), _toggle_panel))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_vbox.add_child(scroll)

	_log_vbox = VBoxContainer.new()
	_log_vbox.add_theme_constant_override("separation", 2)
	_log_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_log_vbox)

func _on_notification(message: String, category: String, color: Color) -> void:
	_log_entries.push_front({"message": message, "category": category, "color": color})
	if _log_entries.size() > MAX_LOG_ENTRIES:
		_log_entries.pop_back()
	_refresh_log()
	_show_toast(message, color)

func _show_toast(text: String, color: Color) -> void:
	var toast_bg := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.PANEL_BG
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	style.border_color = color.darkened(0.3)
	style.border_width_left = 3
	toast_bg.add_theme_stylebox_override("panel", style)
	toast_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := UITheme.make_label(text, "small", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size.x = 280
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_bg.add_child(label)
	_toast_container.add_child(toast_bg)

	var tween := create_tween()
	tween.tween_interval(TOAST_DURATION)
	tween.tween_property(toast_bg, "modulate:a", 0.0, 1.0)
	tween.tween_callback(toast_bg.queue_free)

func _refresh_log() -> void:
	for child in _log_vbox.get_children():
		child.queue_free()
	for entry in _log_entries:
		var label := UITheme.make_label(entry["message"], "small", entry["color"])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		_log_vbox.add_child(label)

func _on_population_changed(current: int, max_pop: int) -> void:
	_pop_label.text = Tr.t("LBL_POPULATION") % [current, max_pop]

func _on_morale_changed(new_morale: int) -> void:
	_morale_label.text = Tr.t("LBL_MORALE") % new_morale
	_morale_bar.value = new_morale
	var color: Color
	if new_morale <= 30:
		color = UITheme.DANGER
	elif new_morale <= 60:
		color = UITheme.WARNING
	else:
		color = UITheme.POSITIVE
	_morale_label.add_theme_color_override("font_color", color)
	# Update bar fill color
	var fill := _morale_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		fill.bg_color = color

func _on_workers_changed(used: int, total: int) -> void:
	_workers_label.text = Tr.t("LBL_WORKERS") % [used, total]

func _update_status_labels() -> void:
	_pop_label.text = Tr.t("LBL_POPULATION") % [PopulationManager.get_population(), PopulationManager.get_max_population()]
	_workers_label.text = Tr.t("LBL_WORKERS") % [PopulationManager.get_used_workers(), PopulationManager.get_population()]
	_morale_label.text = Tr.t("LBL_MORALE") % PopulationManager.get_morale()

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open

# ── Phase & Objective System ──

func _on_phase_advanced(new_phase: int) -> void:
	# Show status bar once consumption kicks in
	if new_phase >= GameConfig.Phase.SETTLEMENT:
		_status_panel.visible = true
	# Notify the player about the new phase
	var phase_msg: String = Tr.t("PHASE_%d" % new_phase)
	if phase_msg != "PHASE_%d" % new_phase:
		EventBus.notification_posted.emit(phase_msg, "info", UITheme.ACCENT)
	_update_objective_hint()

func _update_objective_hint() -> void:
	if not _objective_label:
		return
	var phase: int = ProgressionManager.current_phase
	var hint: String = ""
	match phase:
		GameConfig.Phase.FOUNDATION:
			hint = Tr.t("OBJ_PHASE_0")
		GameConfig.Phase.SETTLEMENT:
			if not ProgressionManager.is_milestone_completed("first_gold_mine"):
				hint = Tr.t("OBJ_PHASE_1")
			else:
				hint = Tr.t("OBJ_PHASE_1_DONE")
		GameConfig.Phase.ECONOMY:
			if not ProgressionManager.is_milestone_completed("first_warehouse"):
				hint = Tr.t("OBJ_PHASE_2")
			else:
				hint = Tr.t("OBJ_PHASE_2_DONE")
		GameConfig.Phase.SURVIVAL:
			if not ProgressionManager.is_milestone_completed("era_2"):
				hint = Tr.t("OBJ_PHASE_3")
			else:
				hint = Tr.t("OBJ_PHASE_3_DONE")
		_:
			hint = Tr.t("OBJ_PHASE_4")
	_objective_label.text = hint
