extends CanvasLayer
## Ajustes, en pestanas: Audio · Interfaz · Controles · Accesibilidad · Juego.
## Todo se guarda en user://settings.cfg (del dispositivo, no de la partida).
##
## Cada pestana es su propio scroll: a 1024x768, en tablet o con letra grande
## el panel entero no cabe, y lo que no cabe se desplaza sin perder la cabecera
## ni el boton de cerrar. Cada pestana tiene su "Restablecer".
##
## Lo que se aplica al momento: volumenes, musica, vista, rejilla, pantalla
## completa, controles, escala de interfaz, mostrar/ocultar HUD, disposicion.
## Lo que cambia tokens de UITheme (tamano de texto, paleta, alto contraste,
## opacidad, perfil) se previsualiza en la tarjeta de muestra y se aplica al
## pulsar APLICAR o al cerrar: los paneles se construyen una vez, asi que
## DeviceProfile.rebuild_ui() recarga la escena conservando la partida y vuelve
## a abrir Ajustes en la misma pestana. Ver docs/21-interfaz-y-dispositivos.md.

const ViewMode := preload("res://scripts/view2d/ViewMode.gd")

enum Tab { AUDIO, INTERFACE, CONTROLS, ACCESSIBILITY, GAME }

## Escalas ofrecidas (0 = la del perfil de dispositivo).
const SCALE_STEPS := [0, 75, 90, 100, 115, 130, 150]
## Alto que se reserva fuera de los scrolls: cabecera, pestanas, APLICAR y
## cerrar, y los margenes del panel.
const CHROME_H := 300.0

var _panel: PanelContainer
var _backdrop: ColorRect
var _settings_btn: Button
var _fullscreen_check: CheckButton
var _music_btn: Button
var _music_check: CheckButton
var _tabs: TabContainer
var _scrolls: Array[ScrollContainer] = []
var _bodies: Array[VBoxContainer] = []
var _apply_btn: Button
var _preview: PanelContainer
var _hud_checks: Dictionary = {}
var _audio_sliders: Dictionary = {}
var _is_open := false
## Hay cambios que solo se ven al reconstruir la interfaz.
var _needs_rebuild := false

func _ready() -> void:
	layer = 15
	_setup_ui()
	UIManager.register_panel(self, "SettingsPanel")
	# Tras una reconstruccion pedida desde aqui, Ajustes vuelve a abrirse donde
	# estaba el jugador: si no, parece que el boton cerro el panel sin mas.
	if DeviceProfile.reopen_settings_tab >= 0:
		var tab := DeviceProfile.reopen_settings_tab
		DeviceProfile.reopen_settings_tab = -1
		_reopen.call_deferred(tab)

func _reopen(tab: int) -> void:
	if not _is_open:
		toggle()
	select_tab(tab)

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
	for side in ["top", "left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	vbox.add_child(UITheme.make_panel_header(Tr.t("LBL_SETTINGS_TITLE"), toggle))

	_tabs = TabContainer.new()
	_tabs.name = "SettingsTabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Recortadas: en un movil en vertical las cinco pestanas no caben y la
	# barra se desplaza con sus flechas en vez de ensanchar el panel.
	_tabs.clip_tabs = true
	UITheme.style_tabs(_tabs)
	vbox.add_child(_tabs)

	_build_audio_tab(_add_tab("TAB_AUDIO"))
	_build_interface_tab(_add_tab("TAB_INTERFACE"))
	_build_controls_tab(_add_tab("TAB_CONTROLS"))
	_build_accessibility_tab(_add_tab("TAB_ACCESSIBILITY"))
	_build_game_tab(_add_tab("TAB_GAME"))

	# APLICAR: solo cuando hay algo que necesita reconstruir la interfaz.
	_apply_btn = Button.new()
	_apply_btn.name = "ApplyButton"
	_apply_btn.text = Tr.t("BTN_UI_APPLY")
	_apply_btn.tooltip_text = Tr.t("LBL_UI_APPLY_HINT")
	UITheme.style_button(_apply_btn, UITheme.WARNING.darkened(0.35), UITheme.FONT_BODY)
	_apply_btn.pressed.connect(apply_pending)
	_apply_btn.visible = false
	vbox.add_child(_apply_btn)

	var close_btn := Button.new()
	close_btn.text = Tr.t("BTN_UNDERSTOOD")
	UITheme.style_button(close_btn, UITheme.POSITIVE, UITheme.FONT_SECTION)
	close_btn.pressed.connect(toggle)
	vbox.add_child(close_btn)

	_sync_music(GameConfig.audio_music_enabled)
	_fit_scroll()
	UILayoutManager.layout_changed.connect(_fit_scroll)
	EventBus.helper_visibility_changed.connect(func(_v): _sync_hud_checks())

## Una pestana: un scroll con su columna. Devuelve la columna.
func _add_tab(title_key: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title_key
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, Tr.t(title_key))
	# Aire a los lados: a la izquierda para que el recorte del scroll no se coma
	# la primera letra, a la derecha para la barra de desplazamiento.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 6)
	scroll.add_child(pad)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(body)
	_scrolls.append(scroll)
	_bodies.append(body)
	if _scrolls.size() == 1:
		scroll.name = "SettingsScroll"
	return body

## Restablecer al pie de cada pestana, a la izquierda y discreto.
func _add_reset(body: VBoxContainer, callback: Callable) -> Button:
	body.add_child(UITheme.make_separator())
	var btn := Button.new()
	btn.name = "ResetTab"
	btn.text = Tr.t("BTN_RESET_TAB")
	UITheme.style_button(btn, UITheme.BTN, UITheme.FONT_BODY)
	btn.pressed.connect(callback)
	body.add_child(btn)
	return btn

func select_tab(tab: int) -> void:
	if _tabs != null:
		_tabs.current_tab = clampi(tab, 0, _tabs.get_tab_count() - 1)
		_fit_scroll()

func current_tab() -> int:
	return _tabs.current_tab if _tabs != null else 0

# ── Audio ─────────────────────────────────────────────────────────────

func _build_audio_tab(body: VBoxContainer) -> void:
	body.add_child(_make_volume_row("master", Tr.t("LBL_VOL_MASTER"), GameConfig.audio_master_volume,
		func(v: float): AudioManager.set_master_volume(v)))
	_music_check = UITheme.make_check_button(Tr.t("LBL_MUSIC_ENABLED"), GameConfig.audio_music_enabled,
		func(pressed: bool): AudioManager.set_music_enabled(pressed))
	body.add_child(_music_check)
	body.add_child(_make_volume_row("music", Tr.t("LBL_VOL_MUSIC"), GameConfig.audio_music_volume,
		func(v: float): AudioManager.set_music_volume(v)))
	body.add_child(_make_volume_row("sfx", Tr.t("LBL_VOL_SFX"), GameConfig.audio_sfx_volume,
		func(v: float): AudioManager.set_sfx_volume(v), true))
	_add_reset(body, reset_audio)

## Los valores de serie de GameConfig (AUDIO_DEFAULTS: bajos, bug 4).
func reset_audio() -> void:
	var defaults: Dictionary = GameConfig.AUDIO_DEFAULTS
	for key in defaults:
		var slider: HSlider = _audio_sliders.get(key)
		if slider != null:
			slider.value = defaults[key]
	AudioManager.set_music_enabled(true)
	GameConfig.save_user_settings()

# ── Interfaz ──────────────────────────────────────────────────────────

func _build_interface_tab(body: VBoxContainer) -> void:
	body.add_child(UITheme.section_header(Tr.t("LBL_SECTION_DEVICE")))
	var modes: Array = GameConfig.DEVICE_PROFILE_MODES
	var labels: Array = [Tr.t("OPT_PROFILE_AUTO") % _profile_name(DeviceProfile.detected())]
	for mode in modes.slice(1):
		labels.append(_profile_name(mode))
	var profile_row := UITheme.make_option_row(Tr.t("LBL_DEVICE_PROFILE"), labels,
		modes.find(GameConfig.ui_device_profile), func(idx: int):
			DeviceProfile.set_profile_override(modes[idx])
			_mark_rebuild())
	profile_row.name = "ProfileRow"
	body.add_child(profile_row)

	var scale_labels: Array = []
	for pct in SCALE_STEPS:
		scale_labels.append(Tr.t("OPT_SCALE_PROFILE") % roundi(float(DeviceProfile.DEFAULTS[DeviceProfile.current()]["ui_scale"]) * 100.0) if pct == 0 else "%d %%" % pct)
	var scale_idx := maxi(0, SCALE_STEPS.find(GameConfig.ui_scale_pct))
	var scale_row := UITheme.make_option_row(Tr.t("LBL_UI_SCALE"), scale_labels, scale_idx, func(idx: int):
		GameConfig.ui_scale_pct = SCALE_STEPS[idx]
		GameConfig.save_user_settings()
		DeviceProfile.apply_scale())
	scale_row.name = "ScaleRow"
	body.add_child(scale_row)

	var text_opts: Array = ["auto"] + UITheme.TEXT_SIZES
	var text_labels: Array = []
	for opt in text_opts:
		text_labels.append(Tr.t("OPT_TEXT_" + String(opt).to_upper()))
	var text_row := UITheme.make_option_row(Tr.t("LBL_TEXT_SIZE"), text_labels,
		maxi(0, text_opts.find(GameConfig.ui_text_size)), func(idx: int):
			GameConfig.ui_text_size = text_opts[idx]
			GameConfig.save_user_settings()
			_mark_rebuild())
	text_row.name = "TextSizeRow"
	body.add_child(text_row)

	body.add_child(UITheme.make_separator())
	body.add_child(UITheme.section_header(Tr.t("LBL_SECTION_VIEW")))
	body.add_child(_make_view_mode_row())
	var grid_check := UITheme.make_check_button(
		Tr.t("LBL_SHOW_GRID"), GameConfig.ui_grid_visible,
		func(pressed: bool):
			GameConfig.ui_grid_visible = pressed
			EventBus.grid_overlay_toggled.emit(pressed)
			GameConfig.save_user_settings()
	)
	grid_check.name = "GridCheck"
	body.add_child(grid_check)
	# Pantalla completa — tambien con F11; el interruptor se sincroniza si se
	# cambia por teclado mientras el panel esta abierto.
	_fullscreen_check = UITheme.make_check_button(
		Tr.t("LBL_FULLSCREEN"), GameConfig.ui_fullscreen,
		func(pressed: bool): GameConfig.set_fullscreen(pressed)
	)
	body.add_child(_fullscreen_check)
	EventBus.fullscreen_changed.connect(func(enabled: bool):
		_fullscreen_check.set_pressed_no_signal(enabled)
	)

	body.add_child(UITheme.make_separator())
	body.add_child(UITheme.section_header(Tr.t("LBL_SECTION_HUD")))
	body.add_child(_make_hint(Tr.t("LBL_HUD_HINT")))
	for id in HudRegistry.hideable_ids():
		var check := UITheme.make_check_button(Tr.t(HudRegistry.label_key(id)), not HudRegistry.is_hidden(id),
			func(pressed: bool): HudRegistry.set_hidden(id, not pressed))
		check.name = "Hud_" + String(id).replace(".", "_")
		_hud_checks[id] = check
		body.add_child(check)

	body.add_child(UITheme.make_separator())
	body.add_child(UITheme.section_header(Tr.t("LBL_SECTION_LAYOUT")))
	body.add_child(_make_hint(Tr.ti("LBL_LAYOUT_HINT")))
	var layout_row := HBoxContainer.new()
	layout_row.add_theme_constant_override("separation", 8)
	var edit_btn := Button.new()
	edit_btn.name = "EditLayoutButton"
	edit_btn.text = Tr.t("BTN_EDIT_LAYOUT")
	edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(edit_btn, UITheme.INFO, UITheme.FONT_BODY)
	edit_btn.pressed.connect(start_layout_edit)
	layout_row.add_child(edit_btn)
	var reset_layout_btn := Button.new()
	reset_layout_btn.name = "ResetLayoutButton"
	reset_layout_btn.text = Tr.t("BTN_RESET_LAYOUT")
	reset_layout_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(reset_layout_btn, UITheme.BTN, UITheme.FONT_BODY)
	reset_layout_btn.pressed.connect(UILayoutManager.reset_user_layout)
	layout_row.add_child(reset_layout_btn)
	body.add_child(layout_row)

	_add_reset(body, reset_interface)

func _profile_name(profile: String) -> String:
	return Tr.t("OPT_PROFILE_" + profile.to_upper())

## Interfaz de serie: perfil automatico, escala y texto del perfil, todo el HUD
## a la vista y la disposicion de serie. La vista 2D/3D y el idioma no se tocan:
## cambiarlos recarga la partida y nadie lo espera de "restablecer".
func reset_interface() -> void:
	GameConfig.ui_device_profile = "auto"
	GameConfig.ui_scale_pct = 0
	GameConfig.ui_text_size = "auto"
	GameConfig.ui_grid_visible = true
	EventBus.grid_overlay_toggled.emit(true)
	HudRegistry.show_all()
	UILayoutManager.reset_user_layout()
	GameConfig.save_user_settings()
	DeviceProfile.apply_scale()
	_sync_hud_checks()
	_mark_rebuild()

func _sync_hud_checks() -> void:
	for id in _hud_checks:
		(_hud_checks[id] as CheckButton).set_pressed_no_signal(not HudRegistry.is_hidden(id))

## Cierra Ajustes (y lo que lo presto: pausa, menu principal) y abre el editor.
func start_layout_edit() -> void:
	if CombatManager.is_board_open():
		EventBus.notification_posted.emit(Tr.t("NOTIF_LAYOUT_AFTER_BATTLE"), "info", UITheme.INFO)
		return
	if _is_open:
		toggle()
	UILayoutManager.start_layout_edit()

# ── Controles ─────────────────────────────────────────────────────────

func _build_controls_tab(body: VBoxContainer) -> void:
	# Controles en pantalla: tres estados porque "automatico" (tablet y movil;
	# en PC nunca) es el valor bueno para casi todos.
	var touch_idx := GameConfig.TOUCH_CONTROLS_MODES.find(GameConfig.ui_touch_controls)
	var row := UITheme.make_option_row(
		Tr.t("LBL_TOUCH_CONTROLS"),
		[Tr.t("OPT_TOUCH_AUTO"), Tr.t("OPT_TOUCH_ALWAYS"), Tr.t("OPT_TOUCH_NEVER")],
		touch_idx,
		func(idx: int): GameConfig.set_touch_controls(GameConfig.TOUCH_CONTROLS_MODES[idx])
	)
	row.name = "TouchControlsRow"
	body.add_child(row)
	body.add_child(_make_hint(Tr.ti("LBL_CONTROLS_SUMMARY")))
	_add_reset(body, reset_controls)

func reset_controls() -> void:
	GameConfig.set_touch_controls("auto")
	var row := find_child("TouchControlsRow", true, false)
	if row != null:
		(row.get_child(1) as OptionButton).selected = 0

# ── Accesibilidad ─────────────────────────────────────────────────────

func _build_accessibility_tab(body: VBoxContainer) -> void:
	var pal_labels: Array = []
	for p in UITheme.PALETTES:
		pal_labels.append(Tr.t("OPT_PALETTE_" + String(p).to_upper()))
	var pal_row := UITheme.make_option_row(Tr.t("LBL_PALETTE"), pal_labels,
		maxi(0, UITheme.PALETTES.find(GameConfig.ui_palette)), func(idx: int):
			GameConfig.ui_palette = UITheme.PALETTES[idx]
			GameConfig.save_user_settings()
			_mark_rebuild())
	pal_row.name = "PaletteRow"
	body.add_child(pal_row)

	var hc := UITheme.make_check_button(Tr.t("LBL_HIGH_CONTRAST"), GameConfig.ui_high_contrast,
		func(pressed: bool):
			GameConfig.ui_high_contrast = pressed
			GameConfig.save_user_settings()
			_mark_rebuild())
	hc.name = "HighContrastCheck"
	body.add_child(hc)

	body.add_child(_make_percent_row("opacity", Tr.t("LBL_PANEL_OPACITY"), GameConfig.ui_panel_opacity,
		UITheme.OPACITY_MIN, UITheme.OPACITY_MAX, func(v: float):
			GameConfig.ui_panel_opacity = v
			_mark_rebuild(false), func(): GameConfig.save_user_settings()))

	body.add_child(UITheme.make_separator())
	body.add_child(UITheme.section_header(Tr.t("LBL_PREVIEW")))
	_preview = PanelContainer.new()
	_preview.name = "PalettePreview"
	body.add_child(_preview)
	_refresh_preview()
	_add_reset(body, reset_accessibility)

func reset_accessibility() -> void:
	GameConfig.ui_palette = "default"
	GameConfig.ui_high_contrast = false
	GameConfig.ui_panel_opacity = 1.0
	GameConfig.save_user_settings()
	var pal_row := find_child("PaletteRow", true, false)
	if pal_row != null:
		(pal_row.get_child(1) as OptionButton).selected = 0
	var hc := find_child("HighContrastCheck", true, false) as CheckButton
	if hc != null:
		hc.set_pressed_no_signal(false)
	var op: HSlider = _audio_sliders.get("opacity")
	if op != null:
		op.set_value_no_signal(1.0)
	_mark_rebuild()

## Muestra con los tokens que quedarian (sin aplicarlos): aliado / enemigo,
## bueno / aviso / malo, recursos y una barra de vida en sus tres tramos, sobre
## el fondo de tarjeta con la opacidad elegida, y el texto al tamano elegido.
func _refresh_preview() -> void:
	if _preview == null:
		return
	for child in _preview.get_children():
		child.queue_free()
	var tokens := UITheme.resolve_tokens(GameConfig.ui_palette, GameConfig.ui_high_contrast, GameConfig.ui_panel_opacity)
	var style := StyleBoxFlat.new()
	style.bg_color = tokens["HUD_BG"]
	style.border_color = tokens["ACCENT"]
	style.set_border_width_all(3 if GameConfig.ui_high_contrast else 2)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(4)
	_preview.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_preview.add_child(col)
	var fs := UITheme.scaled_font(UITheme._FONT_BASE["body"],
		float(UITheme.TEXT_SCALES.get(_pending_text_size(), 1.0)))
	var min_ratio := 7.0 if GameConfig.ui_high_contrast else 4.5
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 14)
	col.add_child(row1)
	for pair in [["POSITIVE", "LBL_PREVIEW_ALLY"], ["DANGER", "LBL_PREVIEW_ENEMY"], ["WARNING", "LBL_PREVIEW_WARNING"], ["INFO", "LBL_PREVIEW_INFO"]]:
		var l := Label.new()
		l.text = Tr.t(pair[1])
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", UITheme.readable(tokens[pair[0]], UITheme.UI_BG_REFERENCE, min_ratio))
		l.add_theme_color_override("font_outline_color", tokens["OUTLINE_COLOR"])
		l.add_theme_constant_override("outline_size", UITheme.outline_for(fs))
		row1.add_child(l)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	col.add_child(row2)
	for key in ["POSITIVE", "WARNING", "DANGER", "RES_GOLD", "RES_WOOD", "RES_STEEL", "RES_OIL", "BOARD_MOVE", "BOARD_TARGET"]:
		var sw := ColorRect.new()
		sw.color = tokens[key]
		sw.custom_minimum_size = Vector2(28, 18)
		sw.tooltip_text = key
		row2.add_child(sw)
	var dim := Label.new()
	dim.text = Tr.t("LBL_PREVIEW_SECONDARY")
	dim.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dim.add_theme_font_size_override("font_size", UITheme.scaled_font(UITheme._FONT_BASE["small"],
		float(UITheme.TEXT_SCALES.get(_pending_text_size(), 1.0))))
	dim.add_theme_color_override("font_color", UITheme.readable(tokens["TEXT_DIM"], UITheme.UI_BG_REFERENCE, min_ratio))
	col.add_child(dim)

func _pending_text_size() -> String:
	return DeviceProfile.effective_text_size()

# ── Juego ─────────────────────────────────────────────────────────────

func _build_game_tab(body: VBoxContainer) -> void:
	body.add_child(_make_language_row())
	body.add_child(UITheme.make_separator())
	var new_game_btn := Button.new()
	new_game_btn.text = Tr.t("BTN_NEW_GAME")
	UITheme.style_button(new_game_btn, UITheme.DANGER, UITheme.FONT_BODY)
	new_game_btn.pressed.connect(GameManager.request_new_game)
	body.add_child(new_game_btn)

# ── Reconstruir ───────────────────────────────────────────────────────

func _mark_rebuild(refresh_preview: bool = true) -> void:
	_needs_rebuild = true
	if _apply_btn != null:
		_apply_btn.visible = true
	if refresh_preview:
		_refresh_preview()
	else:
		_refresh_preview.call_deferred()

func needs_rebuild() -> bool:
	return _needs_rebuild

## Reconstruye la interfaz con lo elegido. Con `reopen` (boton APLICAR) Ajustes
## vuelve a abrirse en esta pestana; al cerrar el panel, no.
## Sin partida (tests, arranque) o con un tablero abierto no se recarga: los
## tokens ya estan puestos para lo que se construya a partir de ahora.
func apply_pending(reopen: bool = true) -> void:
	if not _needs_rebuild:
		return
	_needs_rebuild = false
	_apply_btn.visible = false
	DeviceProfile.rebuild_ui(current_tab() if reopen else -1)

# ── Piezas ────────────────────────────────────────────────────────────

func _make_hint(text: String) -> Label:
	var l := UITheme.make_label(text, "small", UITheme.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## Alto de los scrolls: lo que pide la pestana mas alta, sin pasar de la
## pantalla menos la cabecera, las pestanas y los botones de abajo.
func _fit_scroll() -> void:
	if _scrolls.is_empty() or not is_inside_tree():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var wanted := 120.0
	for body in _bodies:
		wanted = maxf(wanted, body.get_combined_minimum_size().y)
	var h := clampf(wanted, 120.0, maxf(120.0, vp.y - CHROME_H))
	for scroll in _scrolls:
		scroll.custom_minimum_size.y = h

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
func _make_volume_row(key: String, label_text: String, initial: float, apply: Callable, sfx_preview := false) -> VBoxContainer:
	return _make_percent_row(key, label_text, initial, 0.0, 1.0, apply, func():
		GameConfig.save_user_settings()
		if sfx_preview:
			AudioManager.play_sfx("ui_click"))

## Fila con regulador en porcentaje. `on_change` en cada paso; `on_commit` al
## soltar (guardar, previsualizar un sonido).
func _make_percent_row(key: String, label_text: String, initial: float, min_v: float, max_v: float,
		on_change: Callable, on_commit: Callable) -> VBoxContainer:
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
	slider.name = "Slider_" + key
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 0.05
	slider.value = initial
	# Alto de dedo en tablet: el regulador es un control que se arrastra.
	slider.custom_minimum_size = Vector2(0, UITheme.touch_px(28.0))
	row.add_child(slider)
	_audio_sliders[key] = slider
	slider.value_changed.connect(func(v: float):
		on_change.call(v)
		value_label.text = "%d%%" % roundi(v * 100.0)
	)
	slider.drag_ended.connect(func(changed: bool):
		if changed:
			on_commit.call()
	)
	return row

func toggle() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_backdrop.visible = _is_open
	if _is_open:
		_fit_scroll()
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)
		# Guardar al cerrar: un deslizador movido con teclado o mando no emite
		# drag_ended, y lo elegido tiene que sobrevivir al reinicio.
		GameConfig.save_user_settings()
		# Cerrar con cambios pendientes es aplicarlos: nadie espera que la
		# letra grande que eligio se quede sin verse.
		if _needs_rebuild:
			apply_pending(false)

func is_open() -> bool:
	return _is_open
