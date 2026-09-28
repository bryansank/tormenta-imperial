extends CanvasLayer
## Settings panel: audio volume sliders (master / music / SFX).
## Values apply live through AudioManager and persist to user://settings.cfg.

var _panel: PanelContainer
var _backdrop: ColorRect
var _settings_btn: Button
var _fullscreen_check: CheckButton
var _music_btn: Button
var _music_check: CheckButton
var _scroll: ScrollContainer
var _scroll_body: VBoxContainer
var _is_open := false

const ViewMode := preload("res://scripts/view2d/ViewMode.gd")

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
	_settings_btn.custom_minimum_size = Vector2(164, UILayoutConfig.SIDEBAR_BTN_HEIGHT)
	_settings_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_settings_btn.offset_left = -176
	_settings_btn.offset_top = UILayoutManager.get_sidebar_button_offset("SettingsPanel.button")
	UITheme.style_card_button(_settings_btn, UITheme.BTN.lightened(0.05), UITheme.ACCENT)
	_settings_btn.pressed.connect(toggle)
	_settings_btn.visible = false  # Start collapsed with sidebar
	root.add_child(_settings_btn)
	EventBus.sidebar_toggled.connect(func(vis: bool): _settings_btn.visible = vis)

	# Musica si/no de un clic desde el menu ☰, sin abrir Ajustes.
	_music_btn = Button.new()
	_music_btn.name = "MusicQuickButton"
	_music_btn.custom_minimum_size = Vector2(164, UILayoutConfig.SIDEBAR_BTN_HEIGHT)
	_music_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_music_btn.offset_left = -176
	_music_btn.offset_top = UILayoutManager.get_sidebar_button_offset("SettingsPanel.music_button")
	UITheme.style_card_button(_music_btn, UITheme.BTN.lightened(0.05), UITheme.ACCENT)
	_music_btn.pressed.connect(AudioManager.toggle_music)
	_music_btn.visible = false
	root.add_child(_music_btn)
	EventBus.sidebar_toggled.connect(func(vis: bool): _music_btn.visible = vis)
	EventBus.music_toggled.connect(_sync_music)

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

	# Todo lo que va debajo de la cabecera, en un scroll: con el idioma, los
	# controles en pantalla, la musica y la vista 2D/3D el panel pasaba de
	# 1000 px y a 720 de alto se salia por arriba, sin titulo ni cerrar.
	_scroll = ScrollContainer.new()
	_scroll.name = "SettingsScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll)
	_scroll_body = VBoxContainer.new()
	_scroll_body.add_theme_constant_override("separation", 15)
	_scroll_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_scroll_body)
	vbox = _scroll_body

	vbox.add_child(UITheme.section_header(Tr.t("LBL_SETTINGS_AUDIO")))

	vbox.add_child(_make_volume_row(
		Tr.t("LBL_VOL_MASTER"), GameConfig.audio_master_volume,
		func(v: float): AudioManager.set_master_volume(v)
	))
	_music_check = UITheme.make_check_button(Tr.t("LBL_MUSIC_ENABLED"), GameConfig.audio_music_enabled,
		func(pressed: bool): AudioManager.set_music_enabled(pressed))
	vbox.add_child(_music_check)
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
	var grid_check := UITheme.make_check_button(
		Tr.t("LBL_SHOW_GRID"), GameConfig.ui_grid_visible,
		func(pressed: bool):
			GameConfig.ui_grid_visible = pressed
			EventBus.grid_overlay_toggled.emit(pressed)
			GameConfig.save_user_settings()
	)
	vbox.add_child(grid_check)

	# Pantalla completa — tambien con F11; el interruptor se sincroniza si se
	# cambia por teclado mientras el panel esta abierto.
	_fullscreen_check = UITheme.make_check_button(
		Tr.t("LBL_FULLSCREEN"), GameConfig.ui_fullscreen,
		func(pressed: bool): GameConfig.set_fullscreen(pressed)
	)
	vbox.add_child(_fullscreen_check)
	EventBus.fullscreen_changed.connect(func(enabled: bool):
		_fullscreen_check.set_pressed_no_signal(enabled)
	)

	vbox.add_child(_make_view_mode_row())
	# Controles en pantalla: tres estados porque "automatico" (movil, o PC tras
	# un toque real) es el valor bueno para casi todos; en PC salen apagados.
	var touch_idx := GameConfig.TOUCH_CONTROLS_MODES.find(GameConfig.ui_touch_controls)
	vbox.add_child(UITheme.make_option_row(
		Tr.t("LBL_TOUCH_CONTROLS"),
		[Tr.t("OPT_TOUCH_AUTO"), Tr.t("OPT_TOUCH_ALWAYS"), Tr.t("OPT_TOUCH_NEVER")],
		touch_idx,
		func(idx: int): GameConfig.set_touch_controls(GameConfig.TOUCH_CONTROLS_MODES[idx])
	))
	vbox.add_child(_make_language_row())

	vbox.add_child(UITheme.make_separator())
	vbox.add_child(UITheme.section_header(Tr.t("LBL_SETTINGS_GAME")))

	var new_game_btn := Button.new()
	new_game_btn.text = Tr.t("BTN_NEW_GAME")
	UITheme.style_button(new_game_btn, UITheme.DANGER, UITheme.FONT_BODY)
	new_game_btn.pressed.connect(GameManager.request_new_game)
	vbox.add_child(new_game_btn)

	# Close button at bottom
	var close_btn := Button.new()
	close_btn.text = Tr.t("BTN_UNDERSTOOD")
	UITheme.style_button(close_btn, UITheme.POSITIVE, UITheme.FONT_SECTION)
	close_btn.pressed.connect(toggle)
	vbox.add_child(close_btn)
	_sync_music(GameConfig.audio_music_enabled)
	_fit_scroll()
	UILayoutManager.layout_changed.connect(_fit_scroll)

## Alto del scroll: lo que pide el contenido, sin pasar de la pantalla menos la
## cabecera y los margenes (como el scroll de ramas del arbol tecnologico).
func _fit_scroll() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var wanted: float = _scroll_body.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(wanted, 120.0, maxf(120.0, vp.y - 200.0))

## El boton del menu y el interruptor dicen lo mismo, cambie quien cambie.
func _sync_music(enabled: bool) -> void:
	_music_btn.text = Tr.t("BTN_MUSIC_ON") if enabled else Tr.t("BTN_MUSIC_OFF")
	_music_btn.modulate = Color(1, 1, 1, 1.0 if enabled else 0.7)
	if _music_check != null:
		_music_check.set_pressed_no_signal(enabled)

## Selector de idioma: IDIOMA  [Español] [English]. Un boton por idioma con su
## nombre en ese idioma, para que quien no entienda el actual encuentre el suyo.
## El activo va en dorado (pulsarlo otra vez no hace nada). Elegir otro lo aplica, lo guarda y
## recarga la partida (GameManager escucha EventBus.locale_changed).
func _make_language_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "LanguageRow"
	row.add_theme_constant_override("separation", 8)
	var label := UITheme.make_label(Tr.t("LBL_LANGUAGE"), "body")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	for locale in Tr.LOCALES:
		var btn := Button.new()
		btn.name = "Locale_" + locale
		btn.text = Tr.t("LBL_LOCALE_" + locale.to_upper())
		btn.custom_minimum_size = Vector2(96, 36)
		var active: bool = locale == Tr.get_locale()
		UITheme.style_button(btn, UITheme.ACCENT if active else UITheme.BTN, UITheme.FONT_BODY)
		btn.pressed.connect(GameConfig.set_locale.bind(locale))
		row.add_child(btn)
	return row

## Vista del mapa: [3D] [2D]. Elegir la otra guarda la preferencia y la partida
## y abre la otra escena (ViewMode.switch_to, docs/18-vista-2d.md).
func _make_view_mode_row() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "ViewModeRow"
	box.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var label := UITheme.make_label(Tr.t("LBL_VIEW_MODE"), "body")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var current := ViewMode.current(get_tree()) if is_inside_tree() else ""
	if current == "":
		current = ViewMode.requested()
	var group := ButtonGroup.new()
	for mode in [ViewMode.MODE_3D, ViewMode.MODE_2D]:
		var btn := Button.new()
		btn.name = "View" + mode.to_upper()
		btn.text = Tr.t("BTN_VIEW_3D" if mode == ViewMode.MODE_3D else "BTN_VIEW_2D")
		btn.toggle_mode = true
		btn.button_group = group
		btn.button_pressed = mode == current
		UITheme.style_button(btn, UITheme.INFO if mode == current else UITheme.BTN, UITheme.FONT_BODY)
		btn.pressed.connect(func():
			if mode != ViewMode.current(get_tree()):
				ViewMode.switch_to(mode, get_tree())
		)
		btn.tooltip_text = Tr.t("LBL_VIEW_MODE_HINT")
		row.add_child(btn)
	return box

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
