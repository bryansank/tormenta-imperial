extends CanvasLayer
## Ajustes (rediseno fase 2, docs/28): una ventana crema con cinta azul y
## cuatro pestanas en un carril de iconos a la izquierda: Sonido · Pantalla ·
## Controles · Juego. Filas grandes con icono, deslizadores, interruptores
## dibujados y selectores de pastillas (o paso a paso, si no caben). Lo raro
## (perfil, escala, FPS, que se ve en pantalla, colores, contraste, opacidad,
## disposicion) va al final de Pantalla, plegado bajo "Mas opciones".
## Todo se guarda en user://settings.cfg (del dispositivo, no de la partida).
##
## Lo que se aplica al momento: volumenes, musica, vista, rejilla, pantalla
## completa, controles, escala, mostrar/ocultar HUD, disposicion. Lo que cambia
## tokens de UITheme (tamano de texto, paleta, alto contraste, opacidad,
## perfil) se previsualiza en la muestra y se aplica con APLICAR o al cerrar:
## DeviceProfile.rebuild_ui() recarga la escena conservando la partida y vuelve
## a abrir Ajustes en la misma pestana. Ver docs/21-interfaz-y-dispositivos.md.
##
## Sin animaciones (docs/28 §0.6): todo cambia al instante.

const ViewMode := preload("res://scripts/view2d/ViewMode.gd")
const WorldLook := preload("res://scripts/map/WorldLook.gd")
const GraphicsQuality := preload("res://scripts/services/GraphicsQuality.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

enum Tab { AUDIO, INTERFACE, CONTROLS, GAME }

## Pestanas: clave del titulo, icono del carril.
const TABS := [["TAB_AUDIO", "sound"], ["TAB_INTERFACE", "screen"], ["TAB_CONTROLS", "controls"], ["TAB_GAME", "game"]]
## Escalas ofrecidas (0 = la del perfil de dispositivo).
const SCALE_STEPS := [0, 75, 90, 100, 115, 130, 150]
## Tope de la ventana en PC/tablet (docs/28 §6).
const WINDOW_MAX := Vector2(1000, 600)

var _panel: Control
var _backdrop: ColorRect
var _settings_btn: Button
var _fullscreen_check: CheckButton
var _music_btn: Button
var _music_check: CheckButton
var _tabs: TabContainer
var _rail: VBoxContainer
var _scrolls: Array[ScrollContainer] = []
var _bodies: Array[VBoxContainer] = []
var _apply_btn: Button
var _preview: PanelContainer
var _advanced: VBoxContainer
var _advanced_btn: Button
var _hud_checks: Dictionary = {}
var _audio_sliders: Dictionary = {}
var _is_open := false
## Hay cambios que solo se ven al reconstruir la interfaz.
var _needs_rebuild := false
## Telefono: carril solo con iconos, filas cortas, ventana a pantalla completa.
var _small := false

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

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)

func _setup_ui() -> void:
	_small = CT.is_phone()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Botones de la columna vieja del ☰ (ya no se ensenan: el menu ☰ abre Ajustes
	# y tiene su propio boton de musica). Se quedan escondidos por compatibilidad.
	_settings_btn = Button.new()
	_settings_btn.name = "SettingsButton"
	_settings_btn.text = Tr.t("BTN_SETTINGS")
	_settings_btn.visible = false
	_settings_btn.pressed.connect(toggle)
	root.add_child(_settings_btn)
	_music_btn = Button.new()
	_music_btn.name = "MusicQuickButton"
	_music_btn.visible = false
	_music_btn.pressed.connect(AudioManager.toggle_music)
	root.add_child(_music_btn)
	EventBus.music_toggled.connect(_sync_music)

	_backdrop = CT.veil()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			toggle()
	)
	root.add_child(_backdrop)

	var w := CT.menu_window(Tr.t("LBL_SETTINGS_TITLE"), CT.sem("INFO"), _small)
	_panel = w["root"]
	_panel.name = "SettingsWindow"
	_panel.visible = false
	root.add_child(_panel)
	var close: Button = w["close"]
	close.name = "CloseButton"
	if close.custom_minimum_size.y < _h("small"):
		var side := float(_h("small"))
		close.custom_minimum_size = Vector2(side, side)
		close.offset_left = -side + 10
		close.offset_right = 10
		close.offset_bottom = close.offset_top + side
	(w["close"] as Button).tooltip_text = Tr.t("BTN_CLOSE")
	(w["close"] as Button).pressed.connect(toggle)
	(w["panel"] as Control).gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			UIManager.focus_window(self))
	var body: VBoxContainer = w["body"]

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 8 if _small else 16)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(main)

	_rail = VBoxContainer.new()
	_rail.name = "TabRail"
	_rail.add_theme_constant_override("separation", 6 if _small else 8)
	_rail.custom_minimum_size.x = 56 if _small else 220
	main.add_child(_rail)

	_tabs = TabContainer.new()
	_tabs.name = "SettingsTabs"
	_tabs.tabs_visible = false
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var empty := StyleBoxEmpty.new()
	_tabs.add_theme_stylebox_override("panel", empty)
	main.add_child(_tabs)

	_build_audio_tab(_add_tab("TAB_AUDIO"))
	_build_interface_tab(_add_tab("TAB_INTERFACE"))
	_build_controls_tab(_add_tab("TAB_CONTROLS"))
	_build_game_tab(_add_tab("TAB_GAME"))
	# Diferido: la pestana que se pulsa no se puede quitar dentro de su propia senal.
	_tabs.tab_changed.connect(func(_i): _rebuild_rail.call_deferred())
	_rebuild_rail()

	# APLICAR: solo cuando hay algo que necesita reconstruir la interfaz. Ambar:
	# avisa de que hay algo pendiente (docs/28 §5).
	_apply_btn = CT.pill_button(Tr.t("UI2M_BTN_APPLY"), "check", "warning", _h("btn"))
	_apply_btn.name = "ApplyButton"
	_apply_btn.tooltip_text = Tr.t("LBL_UI_APPLY_HINT")
	_apply_btn.pressed.connect(apply_pending)
	_apply_btn.visible = false
	_apply_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	body.add_child(_apply_btn)

	_sync_music(GameConfig.audio_music_enabled)
	_fit()
	get_viewport().size_changed.connect(_fit)
	EventBus.helper_visibility_changed.connect(func(_v): _sync_hud_checks())
	EventBus.instructors_visibility_changed.connect(func(_v): _sync_hud_checks())

## La ventana, centrada con su tope (PC) o a pantalla completa (telefono).
func _fit() -> void:
	if _panel == null or not is_inside_tree():
		return
	CT.place_window(_panel, _vp(), WINDOW_MAX, _small)

## El carril de pestanas: la elegida en azul con labio, las demas planas. En
## telefono solo el icono (el nombre al mantener pulsado).
func _rebuild_rail() -> void:
	if _rail == null:
		return
	for c in _rail.get_children():
		_rail.remove_child(c)
		c.queue_free()
	for i in TABS.size():
		var title := Tr.t(UI2M_TAB_KEYS[i])
		var t := CT.tab("" if _small else title, TABS[i][1], i == current_tab(), "window", CT.sem("INFO"), _h("btn"))
		t.name = "Tab_%d" % i
		t.tooltip_text = title
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		t.pressed.connect(func(): select_tab(idx))
		_rail.add_child(t)

## Titulos cortos del carril (los TAB_* de siempre siguen siendo los de la
## pestana del TabContainer).
const UI2M_TAB_KEYS := ["UI2M_TAB_SOUND", "UI2M_TAB_SCREEN", "UI2M_TAB_CONTROLS", "UI2M_TAB_GAME"]

## Una pestana: un scroll con su columna. Devuelve la columna.
func _add_tab(title_key: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title_key
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(scroll)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, Tr.t(title_key))
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 6 if _small else 12)
	pad.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(pad)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6 if _small else 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(body)
	_scrolls.append(scroll)
	_bodies.append(body)
	if _scrolls.size() == 1:
		scroll.name = "SettingsScroll"
	return body

## Restablecer al pie de cada pestana: pastilla secundaria, discreta.
func _add_reset(body: VBoxContainer, callback: Callable) -> Button:
	var btn := CT.pill_button(Tr.t("UI2M_BTN_RESET"), "back", "secondary", _h("small"))
	btn.name = "ResetTab"
	btn.tooltip_text = Tr.t("BTN_RESET_TAB")
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.pressed.connect(callback)
	body.add_child(btn)
	return btn

func select_tab(tab: int) -> void:
	if _tabs != null:
		_tabs.current_tab = clampi(tab, 0, _tabs.get_tab_count() - 1)
		_rebuild_rail.call_deferred()

func current_tab() -> int:
	return _tabs.current_tab if _tabs != null else 0

## Alto de dedo de Ajustes: el de la pieza (CartoonTheme.h), sin bajar del de
## Ajustes en tablet y movil (UITheme.SETTINGS_ROW_H) ni de 48 en telefono.
func _h(size_s: String) -> int:
	var hh := CT.menu_h(size_s)
	if UITheme.settings_touch():
		hh = maxi(hh, UITheme.SETTINGS_ROW_H)
	if _small:
		hh = maxi(hh, CT.TOUCH_MIN)
	return hh

## Una fila con su texto y su control. `short_key`: el texto en telefono.
func _row(row_name: String, glyph: String, key: String, control: Control, value: Label = null,
		tip: String = "", short_key: String = "") -> PanelContainer:
	var text_s := Tr.t(short_key if _small and short_key != "" else key)
	if control is CheckButton or control is HSlider:
		control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, float(_h("small")))
	return CT.setting_row(row_name, glyph, text_s, control, _small, value, tip)

func _picker(options: Array, selected: int, on_selected: Callable, tips: Array = []) -> HBoxContainer:
	return CT.picker(options, selected, on_selected, _h("small"), tips)

# ── Sonido ────────────────────────────────────────────────────────────

func _build_audio_tab(body: VBoxContainer) -> void:
	body.add_child(_volume_row("master", "sound", "UI2M_SET_MASTER", GameConfig.audio_master_volume,
		func(v: float): AudioManager.set_master_volume(v)))
	_music_check = CT.live_switch(GameConfig.audio_music_enabled,
		func(pressed: bool): AudioManager.set_music_enabled(pressed), "MusicSwitch")
	body.add_child(_row("MusicRow", "music", "UI2M_SET_MUSIC", _music_check, null, Tr.t("LBL_MUSIC_ENABLED")))
	body.add_child(_volume_row("music", "music", "UI2M_SET_MUSIC_VOL", GameConfig.audio_music_volume,
		func(v: float): AudioManager.set_music_volume(v), false, "UI2M_SET_MUSIC_VOL_SHORT"))
	body.add_child(_volume_row("sfx", "sound", "UI2M_SET_SFX", GameConfig.audio_sfx_volume,
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

# ── Pantalla ──────────────────────────────────────────────────────────

func _build_interface_tab(body: VBoxContainer) -> void:
	# Horizontal siempre por defecto; vertical, solo si se elige (docs/28 §4.3).
	var orients: Array = GameConfig.ORIENTATIONS
	body.add_child(_row("OrientationRow", "screen", "UI2M_SET_ORIENT",
		_picker([Tr.t("UI2M_OPT_LANDSCAPE"), Tr.t("UI2M_OPT_PORTRAIT")], maxi(0, orients.find(GameConfig.ui_orientation)),
			func(idx: int): GameConfig.set_orientation(orients[idx])), null, Tr.t("LBL_ORIENTATION")))

	body.add_child(_make_view_mode_row())

	var text_opts: Array = ["auto"] + UITheme.TEXT_SIZES
	var text_labels: Array = []
	for opt in text_opts:
		text_labels.append(Tr.t("OPT_TEXT_" + String(opt).to_upper()))
	body.add_child(_row("TextSizeRow", "access", "UI2M_SET_TEXT",
		_picker(text_labels, maxi(0, text_opts.find(GameConfig.ui_text_size)), func(idx: int):
			GameConfig.ui_text_size = text_opts[idx]
			GameConfig.save_user_settings()
			_mark_rebuild()), null, Tr.t("LBL_TEXT_SIZE")))

	# Calidad grafica del mapa 3D (WorldLook): "auto" dice cual le toca. Se ve
	# al momento, sin recargar.
	var q_modes: Array = GameConfig.GRAPHICS_QUALITY_MODES
	var auto_q := WorldLook.effective_quality("auto", RenderingServer.get_current_rendering_method())
	var q_labels: Array = [Tr.t("OPT_QUALITY_AUTO") % Tr.t("OPT_QUALITY_" + auto_q.to_upper()),
		Tr.t("OPT_QUALITY_HIGH"), Tr.t("OPT_QUALITY_LOW"), Tr.t("OPT_QUALITY_MINIMAL")]
	body.add_child(_row("QualityRow", "settings", "UI2M_SET_QUALITY",
		_picker(q_labels, maxi(0, q_modes.find(GameConfig.ui_graphics_quality)), func(idx: int):
			set_graphics_quality(q_modes[idx])), null, Tr.t("LBL_QUALITY_MINIMAL_HINT")))

	# Pantalla completa — tambien con F11; el interruptor se sincroniza si se
	# cambia por teclado mientras el panel esta abierto.
	_fullscreen_check = CT.live_switch(GameConfig.ui_fullscreen,
		func(pressed: bool): GameConfig.set_fullscreen(pressed), "FullscreenCheck")
	body.add_child(_row("FullscreenRow", "screen", "UI2M_SET_FULLSCREEN", _fullscreen_check, null,
		Tr.t("LBL_FULLSCREEN"), "UI2M_SET_FULLSCREEN_SHORT"))
	EventBus.fullscreen_changed.connect(func(enabled: bool):
		_fullscreen_check.set_pressed_no_signal(enabled)
	)

	var grid_check := CT.live_switch(GameConfig.ui_grid_visible, func(pressed: bool):
		GameConfig.ui_grid_visible = pressed
		# En calidad Minima la preferencia se guarda pero no se pinta.
		EventBus.grid_overlay_toggled.emit(GraphicsQuality.grid_always_visible())
		GameConfig.save_user_settings(), "GridCheck")
	body.add_child(_row("GridRow", "build", "UI2M_SET_GRID", grid_check, null, Tr.t("LBL_SHOW_GRID")))

	# Vista del combate (docs/15 §3): frente (por defecto) o el tablero 8x8.
	var cv_modes: Array = GameConfig.COMBAT_VIEWS
	var cv_labels: Array = []
	for mode in cv_modes:
		cv_labels.append(Tr.t("OPT_COMBAT_VIEW_" + String(mode).to_upper()))
	body.add_child(_row("CombatViewRow", "army", "UI2M_SET_COMBAT_VIEW",
		_picker(cv_labels, maxi(0, cv_modes.find(GameConfig.ui_combat_view)), func(idx: int):
			GameConfig.set_combat_view(cv_modes[idx])), null, Tr.t("LBL_COMBAT_VIEW_TIP")))

	_build_advanced(body)
	_add_reset(body, reset_interface)

## "Mas opciones": lo que casi nadie toca, plegado al final de Pantalla.
func _build_advanced(body: VBoxContainer) -> void:
	_advanced_btn = CT.pill_button(Tr.t("UI2M_ADVANCED_SHOW"), "plus", "secondary", _h("small"))
	_advanced_btn.name = "AdvancedToggle"
	_advanced_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_advanced_btn.pressed.connect(func(): set_advanced_open(not _advanced.visible))
	body.add_child(_advanced_btn)
	_advanced = VBoxContainer.new()
	_advanced.name = "Advanced"
	_advanced.add_theme_constant_override("separation", 6 if _small else 10)
	_advanced.visible = false
	body.add_child(_advanced)
	var adv := _advanced

	# Dispositivo, escala y fotogramas.
	adv.add_child(CT.group_title(Tr.t("UI2M_ADVANCED")))
	var modes: Array = GameConfig.DEVICE_PROFILE_MODES
	var labels: Array = [Tr.t("OPT_PROFILE_AUTO") % _profile_name(DeviceProfile.detected())]
	for mode in modes.slice(1):
		labels.append(_profile_name(mode))
	adv.add_child(_row("ProfileRow", "screen", "UI2M_SET_PROFILE",
		_picker(labels, modes.find(GameConfig.ui_device_profile), func(idx: int):
			DeviceProfile.set_profile_override(modes[idx])
			_mark_rebuild()), null, Tr.t("LBL_DEVICE_PROFILE")))

	var scale_labels: Array = []
	for pct in SCALE_STEPS:
		scale_labels.append(Tr.t("OPT_SCALE_PROFILE") % roundi(float(DeviceProfile.DEFAULTS[DeviceProfile.current()]["ui_scale"]) * 100.0) if pct == 0 else "%d %%" % pct)
	adv.add_child(_row("ScaleRow", "plus", "UI2M_SET_SCALE",
		_picker(scale_labels, maxi(0, SCALE_STEPS.find(GameConfig.ui_scale_pct)), func(idx: int):
			GameConfig.ui_scale_pct = SCALE_STEPS[idx]
			GameConfig.save_user_settings()
			DeviceProfile.apply_scale()), null, Tr.t("LBL_UI_SCALE")))

	adv.add_child(_make_fps_row())
	# Detectar de nuevo (docs/26 §7.2): vuelve a "auto" y decide como en el
	# primer arranque.
	var detect_btn := CT.pill_button(Tr.t("UI2M_BTN_DETECT"), "settings", "info", _h("small"))
	detect_btn.name = "DetectQualityButton"
	detect_btn.tooltip_text = Tr.t("BTN_DETECT_QUALITY")
	detect_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	detect_btn.pressed.connect(func():
		DeviceProfile.start_quality_detection(true)
		var picker = _picker_of("QualityRow")
		if picker != null:
			picker.select(maxi(0, GameConfig.GRAPHICS_QUALITY_MODES.find(GameConfig.ui_graphics_quality)))
		_refresh_fps_auto_label()
		if DeviceProfile.is_detecting_quality():
			EventBus.notification_posted.emit(Tr.t("MSG_QUALITY_MEASURING"), "info", UITheme.INFO))
	adv.add_child(detect_btn)

	# Que se ve en pantalla.
	adv.add_child(CT.group_title(Tr.t("UI2M_SET_HUD")))
	var words_modes: Array = GameConfig.HUD_WORDS_MODES
	adv.add_child(_row("HudWordsRow", "game", "UI2M_SET_WORDS",
		_picker([Tr.t("OPT_HUD_WORDS_AUTO"), Tr.t("OPT_HUD_WORDS_ALWAYS"), Tr.t("OPT_HUD_WORDS_NEVER")],
			maxi(0, words_modes.find(GameConfig.ui_hud_words)), func(idx: int):
				GameConfig.set_hud_words(words_modes[idx])), null, Tr.t("LBL_HUD_WORDS_HINT")))
	for id in HudRegistry.hideable_ids():
		var check := CT.live_switch(not HudRegistry.is_hidden(id),
			func(pressed: bool): HudRegistry.set_hidden(id, not pressed), "Hud_" + String(id).replace(".", "_"))
		_hud_checks[id] = check
		check.custom_minimum_size.y = maxf(check.custom_minimum_size.y, float(_h("small")))
		var card := CT.setting_row("HudRow_" + String(id).replace(".", "_"), "", Tr.t(HudRegistry.label_key(id)),
			check, _small)
		adv.add_child(card)

	# Colores y contraste (accesibilidad).
	adv.add_child(CT.group_title(Tr.t("TAB_ACCESSIBILITY")))
	var pal_labels: Array = []
	var pal_tips: Array = []
	for p in UITheme.PALETTES:
		pal_labels.append(Tr.t("UI2M_OPT_PALETTE_" + String(p).to_upper()))
		pal_tips.append(Tr.t("OPT_PALETTE_" + String(p).to_upper()))
	adv.add_child(_row("PaletteRow", "access", "UI2M_SET_PALETTE",
		_picker(pal_labels, maxi(0, UITheme.PALETTES.find(GameConfig.ui_palette)), func(idx: int):
			GameConfig.ui_palette = UITheme.PALETTES[idx]
			GameConfig.save_user_settings()
			_mark_rebuild(), pal_tips), null, Tr.t("LBL_PALETTE")))
	var hc := CT.live_switch(GameConfig.ui_high_contrast, func(pressed: bool):
		GameConfig.ui_high_contrast = pressed
		GameConfig.save_user_settings()
		_mark_rebuild(), "HighContrastCheck")
	adv.add_child(_row("HighContrastRow", "access", "UI2M_SET_CONTRAST", hc, null, Tr.t("LBL_HIGH_CONTRAST")))
	adv.add_child(_percent_row("opacity", "screen", "UI2M_SET_OPACITY", GameConfig.ui_panel_opacity,
		UITheme.OPACITY_MIN, UITheme.OPACITY_MAX, func(v: float):
			GameConfig.ui_panel_opacity = v
			_mark_rebuild(false), func(): GameConfig.save_user_settings(), Tr.t("LBL_PANEL_OPACITY")))
	_preview = PanelContainer.new()
	_preview.name = "PalettePreview"
	adv.add_child(_preview)
	_refresh_preview()

	# Disposicion: mover los paneles del HUD.
	adv.add_child(CT.group_title(Tr.t("UI2M_SET_LAYOUT")))
	var layout_row := HFlowContainer.new()
	layout_row.add_theme_constant_override("h_separation", 8)
	layout_row.add_theme_constant_override("v_separation", 8)
	var edit_btn := CT.pill_button(Tr.t("UI2M_BTN_EDIT"), "move", "info", _h("small"))
	edit_btn.name = "EditLayoutButton"
	edit_btn.tooltip_text = Tr.ti("LBL_LAYOUT_HINT")
	edit_btn.pressed.connect(start_layout_edit)
	layout_row.add_child(edit_btn)
	var reset_layout_btn := CT.pill_button(Tr.t("UI2M_BTN_DEFAULT"), "back", "secondary", _h("small"))
	reset_layout_btn.name = "ResetLayoutButton"
	reset_layout_btn.tooltip_text = Tr.t("BTN_RESET_LAYOUT")
	reset_layout_btn.pressed.connect(UILayoutManager.reset_user_layout)
	layout_row.add_child(reset_layout_btn)
	adv.add_child(layout_row)

## Abre o pliega "Mas opciones".
func set_advanced_open(open: bool) -> void:
	if _advanced == null:
		return
	_advanced.visible = open
	var lbl: Label = _find_label(_advanced_btn)
	if lbl != null:
		lbl.text = Tr.t("UI2M_ADVANCED_HIDE" if open else "UI2M_ADVANCED_SHOW")

func is_advanced_open() -> bool:
	return _advanced != null and _advanced.visible

func _find_label(n: Node) -> Label:
	for c in n.find_children("*", "Label", true, false):
		return c as Label
	return null

## El selector (CartoonPicker) de una fila, o null.
func _picker_of(row_name: String):
	var row := find_child(row_name, true, false)
	return row.find_child("Picker", true, false) if row != null else null

## Cambia la calidad grafica del mapa, la guarda y la aplica ya. En PC, entrar
## en Minima o salir de ella cambia ademas el renderizador, y eso se aplica al
## reiniciar (GraphicsQuality.sync_renderer_override): se avisa.
func set_graphics_quality(quality: String) -> void:
	if not quality in GameConfig.GRAPHICS_QUALITY_MODES:
		return
	# Elegida a mano: el motivo lo dice, y la reparacion de detecciones malas
	# (DeviceProfile._repair_bad_detection) no la toca nunca. set_quality guarda.
	GameConfig.quality_detected_reason = "manual: " + quality
	var restart := GraphicsQuality.set_quality(quality)
	_refresh_fps_auto_label()
	if restart:
		EventBus.notification_posted.emit(Tr.t("MSG_QUALITY_RESTART"), "notice", UITheme.INFO)

## El "Del perfil (N)" de la fila de FPS sigue a la calidad (30 en PC con Minima).
func _refresh_fps_auto_label() -> void:
	var picker = _picker_of("FpsRow")
	if picker != null and int(picker.get("item_count")) > 0:
		picker.set_item_text(0, Tr.t("OPT_FPS_AUTO") % DeviceProfile.auto_fps())

## Fotogramas por segundo: el del perfil, un numero o sin tope. Se aplica al
## momento, sin reconstruir la interfaz.
func _make_fps_row() -> PanelContainer:
	var modes: Array = GameConfig.FPS_CAP_MODES
	var labels: Array = []
	for mode in modes:
		if mode == "auto":
			labels.append(Tr.t("OPT_FPS_AUTO") % DeviceProfile.auto_fps())
		elif mode == "unlimited":
			labels.append(Tr.t("OPT_FPS_UNLIMITED"))
		else:
			labels.append(String(mode))
	return _row("FpsRow", "clock", "UI2M_SET_FPS",
		_picker(labels, maxi(0, modes.find(GameConfig.ui_fps_cap)), func(idx: int):
			DeviceProfile.set_fps_cap(modes[idx])), null, Tr.t("LBL_FPS_HINT"))

func _profile_name(profile: String) -> String:
	return Tr.t("OPT_PROFILE_" + profile.to_upper())

## Pantalla de serie: perfil automatico, escala y texto del perfil, todo el HUD
## a la vista y la disposicion de serie. La vista 2D/3D y el idioma no se tocan:
## cambiarlos recarga la partida y nadie lo espera de "restablecer".
func reset_interface() -> void:
	GameConfig.ui_device_profile = "auto"
	GameConfig.ui_scale_pct = 0
	GameConfig.ui_text_size = "auto"
	GameConfig.ui_grid_visible = false
	EventBus.grid_overlay_toggled.emit(false)
	var grid_check := find_child("GridCheck", true, false) as BaseButton
	if grid_check != null:
		grid_check.set_pressed_no_signal(false)
	if GraphicsQuality.set_quality("auto"):
		EventBus.notification_posted.emit(Tr.t("MSG_QUALITY_RESTART"), "notice", UITheme.INFO)
	GameConfig.ui_combat_view = "front"
	GameConfig.ui_fps_cap = "auto"
	GameConfig.set_hud_words("auto")
	for row_name in ["ProfileRow", "ScaleRow", "TextSizeRow", "QualityRow", "CombatViewRow", "FpsRow", "HudWordsRow"]:
		var picker = _picker_of(row_name)
		if picker != null:
			picker.select(0)
	HudRegistry.show_all()
	UILayoutManager.reset_user_layout()
	GameConfig.save_user_settings()
	DeviceProfile.apply_scale()
	DeviceProfile.apply_fps()
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
	body.add_child(_row("TouchControlsRow", "controls", "UI2M_SET_TOUCH",
		_picker([Tr.t("UI2M_OPT_AUTO"), Tr.t("OPT_TOUCH_ALWAYS"), Tr.t("OPT_TOUCH_NEVER")], touch_idx,
			func(idx: int): GameConfig.set_touch_controls(GameConfig.TOUCH_CONTROLS_MODES[idx]),
			[Tr.t("OPT_TOUCH_AUTO"), "", ""]), null, Tr.t("LBL_TOUCH_CONTROLS")))
	# "Automatico" es solo tablet y movil: un portatil tactil no los saca por
	# tocarlo (decision de Bryan, 2026-10-04). Una frase, bajo la fila.
	var auto_hint := CT.para(Tr.t("LBL_TOUCH_AUTO_HINT"), "window", true, "small")
	auto_hint.name = "TouchAutoHint"
	body.add_child(auto_hint)
	body.add_child(_percent_row("touch_opacity", "screen", "UI2M_SET_OPACITY",
		GameConfig.ui_touch_controls_opacity, GameConfig.TOUCH_OPACITY_MIN, GameConfig.TOUCH_OPACITY_MAX,
		func(v: float): GameConfig.set_touch_controls_opacity(v, false),
		func(): GameConfig.save_user_settings(), Tr.t("LBL_TOUCH_OPACITY")))
	body.add_child(_make_controls_size_row())
	var summary := CT.para(Tr.ti("LBL_CONTROLS_SUMMARY"), "window", true, "small")
	summary.name = "ControlsSummary"
	body.add_child(summary)
	_add_reset(body, reset_controls)

## Tamano de los controles en pantalla: el del perfil o uno fijo. Se ve al
## momento (OnScreenControls y el ✓ de colocar escuchan
## touch_controls_size_changed) y se guarda en settings.cfg [interfaz].
func _make_controls_size_row() -> PanelContainer:
	var modes: Array = GameConfig.TOUCH_CONTROLS_SIZE_MODES
	var labels: Array = []
	for mode in modes:
		if mode == "auto":
			labels.append(Tr.t("OPT_CONTROLS_SIZE_AUTO") % roundi(
				float(DeviceProfile.defaults().get("controls_size", 1.0)) * 100.0))
		else:
			labels.append(Tr.t("OPT_CONTROLS_SIZE_" + String(mode).to_upper()) % roundi(
				float(GameConfig.TOUCH_CONTROLS_SIZE_SCALES[mode]) * 100.0))
	return _row("ControlsSizeRow", "plus", "UI2M_SET_SIZE",
		_picker(labels, maxi(0, modes.find(GameConfig.ui_touch_controls_size)), func(idx: int):
			GameConfig.set_touch_controls_size(modes[idx])), null, Tr.t("LBL_CONTROLS_SIZE_TIP"))

func reset_controls() -> void:
	GameConfig.set_touch_controls("auto")
	GameConfig.set_touch_controls_opacity(0.45)
	GameConfig.set_touch_controls_size("auto")
	for row_name in ["ControlsSizeRow", "TouchControlsRow"]:
		var picker = _picker_of(row_name)
		if picker != null:
			picker.select(0)
	var op: HSlider = _audio_sliders.get("touch_opacity")
	if op != null:
		op.set_value_no_signal(GameConfig.ui_touch_controls_opacity)

# ── Colores (al final de Pantalla) ────────────────────────────────────

func reset_accessibility() -> void:
	GameConfig.ui_palette = "default"
	GameConfig.ui_high_contrast = false
	GameConfig.ui_panel_opacity = 1.0
	GameConfig.save_user_settings()
	var picker = _picker_of("PaletteRow")
	if picker != null:
		picker.select(0)
	var hc := find_child("HighContrastCheck", true, false) as CheckButton
	if hc != null:
		hc.set_pressed_no_signal(false)
	var op: HSlider = _audio_sliders.get("opacity")
	if op != null:
		op.set_value_no_signal(1.0)
	_mark_rebuild()

## Muestra con los tokens que quedarian (sin aplicarlos): aliado / enemigo,
## bueno / aviso / malo y los recursos, sobre la tarjeta. Pastillas de color y
## una palabra: lo justo para ver si se distinguen.
func _refresh_preview() -> void:
	if _preview == null:
		return
	for child in _preview.get_children():
		child.queue_free()
	var tokens := UITheme.resolve_tokens(GameConfig.ui_palette, GameConfig.ui_high_contrast, GameConfig.ui_panel_opacity)
	var style := CT.card_style("window")
	style.set_content_margin_all(10)
	_preview.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_preview.add_child(col)
	var swatches := HFlowContainer.new()
	swatches.add_theme_constant_override("h_separation", 6)
	swatches.add_theme_constant_override("v_separation", 6)
	col.add_child(swatches)
	for key in ["POSITIVE", "WARNING", "DANGER", "RES_GOLD", "RES_WOOD", "RES_STEEL", "RES_OIL", "BOARD_MOVE", "BOARD_TARGET"]:
		var sw := ColorRect.new()
		sw.color = tokens[key]
		sw.custom_minimum_size = Vector2(30, 22)
		sw.tooltip_text = key
		swatches.add_child(sw)
	var words := HFlowContainer.new()
	words.add_theme_constant_override("h_separation", 6)
	words.add_theme_constant_override("v_separation", 6)
	col.add_child(words)
	for pair in [["POSITIVE", "LBL_PREVIEW_ALLY"], ["DANGER", "LBL_PREVIEW_ENEMY"], ["WARNING", "LBL_PREVIEW_WARNING"], ["INFO", "LBL_PREVIEW_INFO"]]:
		words.add_child(CT.badge(Tr.t(pair[1]), tokens[pair[0]]))

func _pending_text_size() -> String:
	return DeviceProfile.effective_text_size()

# ── Juego ─────────────────────────────────────────────────────────────

func _build_game_tab(body: VBoxContainer) -> void:
	body.add_child(_make_language_row())
	var new_game_btn := CT.text_button(Tr.t("BTN_NEW_GAME"), "game", "secondary", _h("btn"))
	new_game_btn.name = "NewGameButton"
	# Ya no borra nada (crea otra partida): sin color de peligro.
	new_game_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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

## El boton del menu y el interruptor dicen lo mismo, cambie quien cambie.
func _sync_music(enabled: bool) -> void:
	_music_btn.text = Tr.t("BTN_MUSIC_ON") if enabled else Tr.t("BTN_MUSIC_OFF")
	if _music_check != null:
		_music_check.set_pressed_no_signal(enabled)

## Selector de idioma: un boton por idioma con su nombre en ese idioma, para
## que quien no entienda el actual encuentre el suyo. El activo va en azul
## (pulsarlo otra vez no hace nada). Elegir otro lo aplica, lo guarda y recarga
## la partida (GameManager escucha EventBus.locale_changed).
func _make_language_row() -> PanelContainer:
	var buttons := HBoxContainer.new()
	buttons.name = "LocaleButtons"
	buttons.add_theme_constant_override("separation", 6)
	for locale in Tr.LOCALES:
		var name_s := Tr.t("LBL_LOCALE_" + locale.to_upper())
		var active: bool = locale == Tr.get_locale()
		var btn := CT.pill_button(locale.to_upper() if _small else name_s, "", "info" if active else "secondary",
			_h("small"), "window", "body")
		btn.name = "Locale_" + locale
		btn.set_meta("text", name_s)
		btn.tooltip_text = name_s
		btn.pressed.connect(GameConfig.set_locale.bind(locale))
		buttons.add_child(btn)
	return _row("LanguageRow", "game", "UI2M_SET_LANG", buttons, null, Tr.t("LBL_LANGUAGE"))

## Vista del mapa: [3D] [2D]. Elegir la otra guarda la preferencia y la partida
## y abre la otra escena (ViewMode.switch_to, docs/18-vista-2d.md).
func _make_view_mode_row() -> PanelContainer:
	var current := ViewMode.current(get_tree()) if is_inside_tree() else ""
	if current == "":
		current = ViewMode.requested()
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	for mode in [ViewMode.MODE_3D, ViewMode.MODE_2D]:
		var btn := CT.pill_button("3D" if mode == ViewMode.MODE_3D else "2D", "", "info" if mode == current else "secondary",
			_h("small"), "window", "body")
		btn.name = "View" + mode.to_upper()
		btn.tooltip_text = Tr.t("BTN_VIEW_3D" if mode == ViewMode.MODE_3D else "BTN_VIEW_2D")
		btn.pressed.connect(func():
			if mode != ViewMode.current(get_tree()):
				ViewMode.switch_to(mode, get_tree())
		)
		buttons.add_child(btn)
	return _row("ViewModeRow", "build", "UI2M_SET_VIEW", buttons, null, Tr.t("LBL_VIEW_MODE_HINT"))

## Volumen: [icono] Nombre [--------o---] 80
func _volume_row(key: String, glyph: String, label_key: String, initial: float, apply: Callable,
		sfx_preview := false, short_key: String = "") -> PanelContainer:
	return _percent_row(key, glyph, label_key, initial, 0.0, 1.0, apply, func():
		GameConfig.save_user_settings()
		if sfx_preview:
			AudioManager.play_sfx("ui_click"), "", short_key)

## Fila con regulador en porcentaje. `on_change` en cada paso; `on_commit` al
## soltar (guardar, previsualizar un sonido).
func _percent_row(key: String, glyph: String, label_key: String, initial: float, min_v: float, max_v: float,
		on_change: Callable, on_commit: Callable, tip: String = "", short_key: String = "") -> PanelContainer:
	var slider := CT.menu_slider("Slider_" + key, initial, min_v, max_v)
	var value_label := CT.label(str(roundi(initial * 100.0)), "number", CT.text("window"))
	_audio_sliders[key] = slider
	slider.value_changed.connect(func(v: float):
		on_change.call(v)
		value_label.text = str(roundi(v * 100.0))
	)
	slider.drag_ended.connect(func(changed: bool):
		if changed:
			on_commit.call()
	)
	return _row("Row_" + key, glyph, label_key, slider, value_label, tip, short_key)

func toggle() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_backdrop.visible = _is_open
	if _is_open:
		_fit()
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
