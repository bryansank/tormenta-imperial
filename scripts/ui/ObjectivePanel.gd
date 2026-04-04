extends CanvasLayer
## Panel that explains the game goals and "What to do".
## Toggled via EventBus.

var _panel: PanelContainer
var _is_open := false

func _ready() -> void:
	layer = 15 # Higher than other UI
	visible = false
	_setup_ui()
	EventBus.objective_panel_toggled.connect(toggle)

func _setup_ui() -> void:
	# Backdrop
	var backdrop := UITheme.make_backdrop()
	backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			toggle()
	)
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(500, 450)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)

	# Header
	var header := UITheme.make_panel_header(Tr.t("LBL_OBJ_TITLE"), toggle)
	vbox.add_child(header)

	vbox.add_child(UITheme.make_separator())

	# Content - Scrollable
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 20)
	scroll.add_child(content)

	# Goal Section
	content.add_child(UITheme.section_header(Tr.t("LBL_OBJ_MISSION")))
	var main_goal := UITheme.make_label(Tr.t("LBL_OBJ_MISSION_DESC"), "body")
	main_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(main_goal)

	# Step-by-step
	content.add_child(UITheme.make_separator())
	content.add_child(UITheme.section_header(Tr.t("LBL_OBJ_STEPS")))

	var steps := [
		Tr.t("LBL_OBJ_STEP_1"),
		Tr.t("LBL_OBJ_STEP_2"),
		Tr.t("LBL_OBJ_STEP_3"),
		Tr.t("LBL_OBJ_STEP_4"),
		Tr.t("LBL_OBJ_STEP_5"),
	]
	
	for step in steps:
		var l := UITheme.make_label(step, "body", UITheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(l)

	# Controls Tip
	content.add_child(UITheme.make_separator())
	var tip := UITheme.make_label(Tr.t("LBL_OBJ_TIP"), "small", UITheme.ACCENT)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(tip)

	# Close Button at bottom
	var close_btn := Button.new()
	close_btn.text = Tr.t("BTN_UNDERSTOOD")
	UITheme.style_button(close_btn, UITheme.POSITIVE, UITheme.FONT_SECTION)
	close_btn.pressed.connect(toggle)
	vbox.add_child(close_btn)

func toggle() -> void:
	_is_open = not _is_open
	visible = _is_open
	if _is_open:
		# Could play sound or animation here
		pass
