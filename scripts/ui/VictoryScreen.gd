extends CanvasLayer
## Full-screen victory overlay shown when HQ reaches max level.

var _backdrop: ColorRect

func _ready() -> void:
	layer = 20
	EventBus.victory_achieved.connect(_show_victory)

func _show_victory(stats: Dictionary) -> void:
	# Backdrop
	_backdrop = UITheme.make_backdrop()
	_backdrop.color.a = 0.0
	add_child(_backdrop)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	UILayoutManager.apply_layout("VictoryScreen", panel)
	panel.modulate.a = 0.0

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# Title
	var title := UITheme.make_label(Tr.t("LBL_VICTORY_TITLE"), "title", UITheme.ACCENT)
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Subtitle
	var subtitle := UITheme.make_label(Tr.t("LBL_VICTORY_SUBTITLE"), "body", UITheme.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(subtitle)

	vbox.add_child(UITheme.make_separator())

	# Stats
	var time_played: float = stats.get("time_played", 0.0)
	_add_stat(vbox, Tr.t("LBL_STAT_TIME"), _format_time(time_played))
	_add_stat(vbox, Tr.t("LBL_STAT_BUILDINGS"), str(stats.get("buildings_built", 0)))
	_add_stat(vbox, Tr.t("LBL_STAT_TRADES"), str(stats.get("trades_completed", 0)))
	_add_stat(vbox, Tr.t("LBL_STAT_MILESTONES"), str(stats.get("milestones", 0)))

	vbox.add_child(UITheme.make_separator())

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)

	var continue_btn := Button.new()
	continue_btn.text = Tr.t("BTN_CONTINUE")
	continue_btn.custom_minimum_size = Vector2(150, 44)
	UITheme.style_button(continue_btn, UITheme.POSITIVE)
	continue_btn.pressed.connect(func():
		_backdrop.queue_free()
		panel.queue_free()
	)
	btn_row.add_child(continue_btn)

	var new_btn := Button.new()
	new_btn.text = Tr.t("BTN_NEW_GAME")
	new_btn.custom_minimum_size = Vector2(150, 44)
	UITheme.style_button(new_btn, UITheme.DANGER)
	new_btn.pressed.connect(func(): GameManager.clear_save())
	btn_row.add_child(new_btn)

	vbox.add_child(btn_row)
	add_child(panel)

	# Fade in
	var tween := create_tween()
	tween.tween_property(_backdrop, "color:a", 0.45, 0.5)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_OUT)

func _add_stat(parent: VBoxContainer, label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := UITheme.make_label(label_text, "body", UITheme.TEXT_DIM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := UITheme.make_label(value_text, "body", UITheme.TEXT_BRIGHT)
	row.add_child(value)
	parent.add_child(row)

func _format_time(seconds: float) -> String:
	var s := int(seconds)
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm %ds" % [s / 60, s % 60]
	return "%dh %dm" % [s / 3600, (s % 3600) / 60]
