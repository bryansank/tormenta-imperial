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
var _workers_label: Label

func _ready() -> void:
	layer = 11
	_setup_ui()
	EventBus.notification_posted.connect(_on_notification)
	EventBus.population_changed.connect(_on_population_changed)
	EventBus.morale_changed.connect(_on_morale_changed)
	EventBus.workers_changed.connect(_on_workers_changed)
	_update_status_labels()

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)

	# Status bar (top-left below HUD)
	var status_panel := PanelContainer.new()
	status_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	status_panel.position = Vector2(10, 50)
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = UITheme.PANEL_BG
	status_style.set_corner_radius_all(UITheme.CORNER)
	status_style.set_content_margin_all(8)
	status_style.border_color = UITheme.ACCENT_DIM
	status_style.set_border_width_all(1)
	status_panel.add_theme_stylebox_override("panel", status_style)
	root.add_child(status_panel)

	var status_vbox := VBoxContainer.new()
	status_vbox.add_theme_constant_override("separation", 3)
	status_panel.add_child(status_vbox)

	_pop_label = UITheme.make_label("", "small", UITheme.CAT_SUPPORT)
	status_vbox.add_child(_pop_label)

	_workers_label = UITheme.make_label("", "small", UITheme.INFO)
	status_vbox.add_child(_workers_label)

	_morale_label = UITheme.make_label("", "small", UITheme.WARNING)
	status_vbox.add_child(_morale_label)

	# Toast container (bottom-left)
	_toast_container = VBoxContainer.new()
	_toast_container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_toast_container.position = Vector2(10, -200)
	_toast_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast_container.add_theme_constant_override("separation", 4)
	_toast_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_container)

	# Log button
	_log_btn = Button.new()
	_log_btn.text = Tr.t("BTN_LOG")
	_log_btn.custom_minimum_size = Vector2(100, 32)
	_log_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_log_btn.position = Vector2(10, 130)
	UITheme.style_button(_log_btn, UITheme.BTN, UITheme.FONT_SMALL)
	_log_btn.pressed.connect(_toggle_panel)
	root.add_child(_log_btn)

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
	if new_morale <= 30:
		_morale_label.add_theme_color_override("font_color", UITheme.DANGER)
	elif new_morale <= 60:
		_morale_label.add_theme_color_override("font_color", UITheme.WARNING)
	else:
		_morale_label.add_theme_color_override("font_color", UITheme.POSITIVE)

func _on_workers_changed(used: int, total: int) -> void:
	_workers_label.text = Tr.t("LBL_WORKERS") % [used, total]

func _update_status_labels() -> void:
	_pop_label.text = Tr.t("LBL_POPULATION") % [PopulationManager.get_population(), PopulationManager.get_max_population()]
	_workers_label.text = Tr.t("LBL_WORKERS") % [PopulationManager.get_used_workers(), PopulationManager.get_population()]
	_morale_label.text = Tr.t("LBL_MORALE") % PopulationManager.get_morale()

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
