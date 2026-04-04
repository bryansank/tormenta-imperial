extends CanvasLayer
## Shows era progression, milestones checklist, and overall completion.

var _panel: PanelContainer
var _backdrop: ColorRect
var _progress_btn: Button
var _is_open := false
var _milestone_labels: Dictionary = {}
var _era_label: Label
var _bar: ProgressBar

func _ready() -> void:
	layer = 11
	_setup_ui()
	EventBus.milestone_completed.connect(_on_milestone_completed)
	EventBus.era_advanced.connect(_on_era_advanced)

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_progress_btn = Button.new()
	_progress_btn.text = Tr.t("BTN_PROGRESS")
	_progress_btn.custom_minimum_size = Vector2(140, 38)
	_progress_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_progress_btn.offset_left = -152
	_progress_btn.offset_top = UILayoutManager.get_sidebar_button_offset("ProgressPanel.button")
	UITheme.style_card_button(_progress_btn, UITheme.BTN.lightened(0.05), UITheme.WARNING)
	_progress_btn.pressed.connect(_toggle_panel)
	_progress_btn.visible = false  # Start collapsed with sidebar
	root.add_child(_progress_btn)
	EventBus.sidebar_toggled.connect(func(vis: bool): _progress_btn.visible = vis)

	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _toggle_panel())
	root.add_child(_backdrop)

	_panel = PanelContainer.new()
	UILayoutManager.apply_layout("ProgressPanel.modal", _panel)
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_panel.add_child(vbox)

	vbox.add_child(UITheme.make_panel_header(Tr.t("LBL_PROGRESS_TITLE"), _toggle_panel))

	# Era display
	_era_label = UITheme.make_label(
		"%s: %s" % [Tr.t("LBL_CURRENT_ERA"), Tr.t(ProgressionManager.get_era_name())],
		"section", UITheme.INFO
	)
	_era_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_era_label)

	# Progress bar
	_bar = UITheme.make_progress_bar(UITheme.ACCENT)
	_bar.value = ProgressionManager.get_completion_percent()
	_bar.show_percentage = true
	vbox.add_child(_bar)

	vbox.add_child(UITheme.make_separator())

	# Milestones
	for milestone in ProgressionManager.get_milestone_list():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var is_done := ProgressionManager.is_milestone_completed(milestone["id"])

		var check := UITheme.make_label(
			"[X]" if is_done else "[ ]", "body",
			UITheme.POSITIVE if is_done else UITheme.TEXT_DIM
		)
		check.custom_minimum_size.x = 30
		row.add_child(check)

		var name_label := UITheme.make_label(
			Tr.t(milestone["name"]), "body",
			UITheme.TEXT if is_done else UITheme.TEXT_DIM
		)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		_milestone_labels[milestone["id"]] = {"check": check, "name": name_label}
		vbox.add_child(row)

func _on_milestone_completed(milestone_id: String) -> void:
	if _milestone_labels.has(milestone_id):
		var labels: Dictionary = _milestone_labels[milestone_id]
		labels["check"].text = "[X]"
		labels["check"].add_theme_color_override("font_color", UITheme.POSITIVE)
		labels["name"].add_theme_color_override("font_color", UITheme.TEXT)
	_bar.value = ProgressionManager.get_completion_percent()
	_show_milestone_toast(milestone_id)

func _on_era_advanced(new_era: int) -> void:
	_era_label.text = "%s: %s" % [Tr.t("LBL_CURRENT_ERA"), Tr.t(ProgressionManager.get_era_name())]
	_show_era_toast(new_era)

func _show_milestone_toast(milestone_id: String) -> void:
	var milestone_name := milestone_id
	for m in ProgressionManager.get_milestone_list():
		if m["id"] == milestone_id:
			milestone_name = Tr.t(m["name"])
			break
	_show_toast(Tr.t("FMT_MILESTONE_COMPLETE") % milestone_name, UITheme.ACCENT)

func _show_era_toast(era: int) -> void:
	var era_name := Tr.t(GameConfig.era_names.get(era, ""))
	_show_toast(Tr.t("FMT_ERA_UNLOCKED") % era_name, UITheme.INFO)

func _show_toast(text: String, color: Color) -> void:
	var label := UITheme.make_label(text, "section", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position.y = 80
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", 60.0, 0.5).set_ease(Tween.EASE_OUT)
	tween.tween_interval(2.5)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_backdrop.visible = _is_open
	if _is_open:
		UIManager.open_window(self)
	else:
		UIManager.close_window(self)
