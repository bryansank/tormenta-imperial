extends CanvasLayer
## Panel that explains the game goals and "What to do".
## Toggled via EventBus.

var _panel: PanelContainer
var _backdrop: ColorRect
var _obj_btn: Button
var _is_open := false

func _ready() -> void:
	layer = 15 # Higher than other UI
	_setup_ui()
	EventBus.objective_panel_toggled.connect(toggle)
	UIManager.register_panel(self, "ObjectivePanel")

func _setup_ui() -> void:
	# Root control holds the always-present sidebar button; the modal itself
	# (backdrop + panel) is toggled independently so the button stays visible.
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Sidebar button ("¿Qué hacer?") — lives in the hamburger menu
	_obj_btn = Button.new()
	_obj_btn.text = Tr.t("BTN_OBJECTIVES")
	_obj_btn.custom_minimum_size = Vector2(140, 38)
	_obj_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_obj_btn.offset_left = -152
	_obj_btn.offset_top = UILayoutManager.get_sidebar_button_offset("ObjectivePanel.button")
	UITheme.style_card_button(_obj_btn, UITheme.BTN.lightened(0.05), UITheme.INFO)
	_obj_btn.pressed.connect(toggle)
	_obj_btn.visible = false  # Start collapsed with sidebar
	root.add_child(_obj_btn)
	EventBus.sidebar_toggled.connect(func(vis: bool): _obj_btn.visible = vis)

	# Backdrop
	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			toggle()
	)
	root.add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.visible = false
	UILayoutManager.apply_layout("ObjectivePanel", _panel)
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	root.add_child(_panel)

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
	_panel.visible = _is_open
	_backdrop.visible = _is_open
	if _is_open:
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)

func _toggle_panel() -> void:
	toggle()
