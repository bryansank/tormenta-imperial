extends CanvasLayer
## Settings panel: audio volume sliders (master / music / SFX).
## Values apply live through AudioManager and persist to user://settings.cfg.

var _panel: PanelContainer
var _backdrop: ColorRect
var _settings_btn: Button
var _is_open := false

func _ready() -> void:
	layer = 15
	_setup_ui()
	UIManager.register_panel(self, "SettingsPanel")

func _setup_ui() -> void:
	# Root control holds the always-present sidebar button; the modal itself
	# (backdrop + panel) is toggled independently so the button stays visible.
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Sidebar button — lives in the hamburger menu
	_settings_btn = Button.new()
	_settings_btn.text = Tr.t("BTN_SETTINGS")
	_settings_btn.custom_minimum_size = Vector2(140, 38)
	_settings_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_settings_btn.offset_left = -152
	_settings_btn.offset_top = UILayoutManager.get_sidebar_button_offset("SettingsPanel.button")
	UITheme.style_card_button(_settings_btn, UITheme.BTN.lightened(0.05), UITheme.ACCENT)
	_settings_btn.pressed.connect(toggle)
	_settings_btn.visible = false  # Start collapsed with sidebar
	root.add_child(_settings_btn)
	EventBus.sidebar_toggled.connect(func(vis: bool): _settings_btn.visible = vis)

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
	UILayoutManager.apply_layout("SettingsPanel.modal", _panel)
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

	var header := UITheme.make_panel_header(Tr.t("LBL_SETTINGS_TITLE"), toggle)
	vbox.add_child(header)

	vbox.add_child(UITheme.make_separator())

	vbox.add_child(UITheme.section_header(Tr.t("LBL_SETTINGS_AUDIO")))

	vbox.add_child(_make_volume_row(
		Tr.t("LBL_VOL_MASTER"), GameConfig.audio_master_volume,
		func(v: float): AudioManager.set_master_volume(v)
	))
	vbox.add_child(_make_volume_row(
		Tr.t("LBL_VOL_MUSIC"), GameConfig.audio_music_volume,
		func(v: float): AudioManager.set_music_volume(v)
	))
	vbox.add_child(_make_volume_row(
		Tr.t("LBL_VOL_SFX"), GameConfig.audio_sfx_volume,
		func(v: float): AudioManager.set_sfx_volume(v),
		true
	))

	vbox.add_child(UITheme.make_separator())
	vbox.add_child(UITheme.section_header(Tr.t("LBL_SETTINGS_UI")))

	# Map grid toggle
	var grid_check := CheckButton.new()
	grid_check.text = Tr.t("LBL_SHOW_GRID")
	grid_check.button_pressed = GameConfig.ui_grid_visible
	grid_check.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	grid_check.add_theme_color_override("font_color", UITheme.TEXT)
	grid_check.toggled.connect(func(pressed: bool):
		GameConfig.ui_grid_visible = pressed
		EventBus.grid_overlay_toggled.emit(pressed)
		GameConfig.save_user_settings()
	)
	vbox.add_child(grid_check)

	# Close button at bottom
	var close_btn := Button.new()
	close_btn.text = Tr.t("BTN_UNDERSTOOD")
	UITheme.style_button(close_btn, UITheme.POSITIVE, UITheme.FONT_SECTION)
	close_btn.pressed.connect(toggle)
	vbox.add_child(close_btn)

## One labelled volume slider row: NAME  [--------o---]  85%
func _make_volume_row(label_text: String, initial: float, apply: Callable, sfx_preview := false) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var top := HBoxContainer.new()
	row.add_child(top)

	var name_label := UITheme.make_label(label_text, "body")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)

	var value_label := UITheme.make_label("%d%%" % roundi(initial * 100.0), "body", UITheme.ACCENT)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial
	slider.custom_minimum_size = Vector2(0, 24)
	row.add_child(slider)

	slider.value_changed.connect(func(v: float):
		apply.call(v)
		value_label.text = "%d%%" % roundi(v * 100.0)
	)
	# Persist (and audibly preview SFX level) only when the drag ends.
	slider.drag_ended.connect(func(changed: bool):
		if changed:
			GameConfig.save_user_settings()
			if sfx_preview:
				AudioManager.play_sfx("ui_click")
	)
	return row

func toggle() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_backdrop.visible = _is_open
	if _is_open:
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)
