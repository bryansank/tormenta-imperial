extends GdUnitTestSuite
## Ajustes en pestanas (docs/21): Audio · Interfaz · Controles · Accesibilidad
## · Juego. Que esten todas, que cada una tenga su Restablecer, que quepa en
## pantalla, que los interruptores del HUD manden, que lo que necesita
## reconstruir la interfaz lo diga, y los globos callados en pausa.
##
## Sin partida arrancada: APLICAR no recarga nada (rebuild_ui devuelve false).
## settings.cfg y GameConfig vuelven intactos (SettingsParking).

const SettingsParking := preload("res://tests/save/settings_parking.gd")
const SettingsScene := preload("res://scenes/ui/SettingsPanel.tscn")

var _parked: Dictionary
var _panel

func before_test() -> void:
	_parked = SettingsParking.park()

func after_test() -> void:
	if is_instance_valid(_panel):
		if _panel.is_open():
			_panel._needs_rebuild = false
			_panel.toggle()
		_panel.free()
	SettingsParking.restore(_parked)

func _open():
	_panel = SettingsScene.instantiate()
	add_child(_panel)
	_panel.toggle()
	return _panel

func test_the_five_tabs_are_there_in_order() -> void:
	var p = _open()
	var tabs: TabContainer = p.find_child("SettingsTabs", true, false)
	assert_int(tabs.get_tab_count()).is_equal(5)
	var titles: Array = []
	for i in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(i))
	assert_array(titles).is_equal([Tr.t("TAB_AUDIO"), Tr.t("TAB_INTERFACE"), Tr.t("TAB_CONTROLS"),
		Tr.t("TAB_ACCESSIBILITY"), Tr.t("TAB_GAME")])

func test_every_tab_but_game_has_its_reset() -> void:
	var p = _open()
	var tabs: TabContainer = p.find_child("SettingsTabs", true, false)
	for i in 4:
		assert_object(tabs.get_child(i).find_child("ResetTab", true, false)).override_failure_message("pestana %d" % i).is_not_null()

func test_the_old_rows_still_exist() -> void:
	var p = _open()
	for n in ["LanguageRow", "ViewModeRow", "TouchControlsRow", "MusicQuickButton", "ProfileRow", "ScaleRow",
			"TextSizeRow", "PaletteRow", "HighContrastCheck", "PalettePreview", "EditLayoutButton", "ResetLayoutButton"]:
		assert_object(p.find_child(n, true, false)).override_failure_message(n).is_not_null()

func test_the_panel_fits_on_screen_on_every_tab() -> void:
	var p = _open()
	var vp: Vector2 = p.get_viewport().get_visible_rect().size
	for i in 5:
		p.select_tab(i)
		await await_idle_frame()
		await await_idle_frame()
		var r: Rect2 = p._panel.get_global_rect()
		assert_float(r.size.y).override_failure_message("pestana %d: %s" % [i, r]).is_less_equal(vp.y)
		assert_float(r.position.y).is_greater_equal(0.0)
		assert_float(r.end.x).is_less_equal(vp.x)

func test_the_tabs_are_finger_sized() -> void:
	var p = _open()
	var tabs: TabContainer = p.find_child("SettingsTabs", true, false)
	await await_idle_frame()
	assert_float(tabs.get_tab_bar().size.y).is_greater_equal(float(UITheme.MIN_BTN_H) - 1.0)

func test_a_hud_switch_hides_that_element() -> void:
	var p = _open()
	var check: CheckButton = p.find_child("Hud_StormHUD", true, false)
	assert_bool(check.button_pressed).is_true()
	check.button_pressed = false
	assert_bool(HudRegistry.is_hidden("StormHUD")).is_true()
	check.button_pressed = true
	assert_bool(HudRegistry.is_hidden("StormHUD")).is_false()

func test_the_help_switch_follows_the_ayuda_button() -> void:
	var p = _open()
	var check: CheckButton = p.find_child("Hud_HelperPanel_callouts", true, false)
	GameConfig.ui_helper_visible = false
	EventBus.helper_visibility_changed.emit(false)
	assert_bool(check.button_pressed).is_false()

func test_palette_text_and_contrast_ask_for_a_rebuild() -> void:
	var p = _open()
	var apply: Button = p.find_child("ApplyButton", true, false)
	assert_bool(apply.visible).is_false()
	var row: Node = p.find_child("PaletteRow", true, false)
	(row.get_child(1) as OptionButton).item_selected.emit(1)
	assert_str(GameConfig.ui_palette).is_equal(UITheme.PALETTES[1])
	assert_bool(p.needs_rebuild()).is_true()
	assert_bool(apply.visible).is_true()
	# Sin partida no se recarga nada, pero no se rompe.
	p.apply_pending()
	assert_bool(p.needs_rebuild()).is_false()

func test_the_preview_uses_the_pending_palette() -> void:
	var p = _open()
	var row: Node = p.find_child("PaletteRow", true, false)
	(row.get_child(1) as OptionButton).item_selected.emit(UITheme.PALETTES.find("red_green"))
	await await_idle_frame()
	var preview: PanelContainer = p.find_child("PalettePreview", true, false)
	var swatch := preview.find_children("*", "ColorRect", true, false)[0] as ColorRect
	assert_bool(swatch.color.is_equal_approx(UITheme._PALETTE_TOKENS["red_green"]["POSITIVE"])).is_true()
	# Y los tokens reales no cambian hasta aplicar.
	assert_str(UITheme.palette).is_equal("default")

func test_the_ui_scale_applies_and_persists() -> void:
	var p = _open()
	var row: Node = p.find_child("ScaleRow", true, false)
	(row.get_child(1) as OptionButton).item_selected.emit(p.SCALE_STEPS.find(130))
	assert_int(GameConfig.ui_scale_pct).is_equal(130)
	GameConfig.ui_scale_pct = 0
	GameConfig.load_user_settings()
	assert_int(GameConfig.ui_scale_pct).is_equal(130)

func test_reset_interface_puts_everything_back() -> void:
	var p = _open()
	GameConfig.ui_scale_pct = 150
	GameConfig.ui_text_size = "xlarge"
	GameConfig.ui_device_profile = "phone"
	HudRegistry.set_hidden("StormHUD", true)
	UILayoutManager.set_user_offset("StormHUD", Vector2(16, 16))
	p.reset_interface()
	assert_int(GameConfig.ui_scale_pct).is_equal(0)
	assert_str(GameConfig.ui_text_size).is_equal("auto")
	assert_str(GameConfig.ui_device_profile).is_equal("auto")
	assert_bool(HudRegistry.is_hidden("StormHUD")).is_false()
	assert_vector(UILayoutManager.get_user_offset("StormHUD")).is_equal(Vector2.ZERO)
	assert_bool((p.find_child("Hud_StormHUD", true, false) as CheckButton).button_pressed).is_true()

func test_reset_accessibility() -> void:
	var p = _open()
	GameConfig.ui_palette = "tritan"
	GameConfig.ui_high_contrast = true
	GameConfig.ui_panel_opacity = 0.5
	p.reset_accessibility()
	assert_str(GameConfig.ui_palette).is_equal("default")
	assert_bool(GameConfig.ui_high_contrast).is_false()
	assert_float(GameConfig.ui_panel_opacity).is_equal(1.0)

func test_reset_audio_brings_the_music_back() -> void:
	var p = _open()
	var saved := [GameConfig.audio_master_volume, GameConfig.audio_music_volume, GameConfig.audio_sfx_volume, GameConfig.audio_music_enabled]
	AudioManager.set_music_enabled(false)
	p.reset_audio()
	var after := [GameConfig.audio_master_volume, GameConfig.audio_music_volume, GameConfig.audio_sfx_volume, GameConfig.audio_music_enabled]
	AudioManager.set_master_volume(saved[0])
	AudioManager.set_music_volume(saved[1])
	AudioManager.set_sfx_volume(saved[2])
	AudioManager.set_music_enabled(saved[3])
	# Los de serie bajaron (bug 4): GameConfig.AUDIO_DEFAULTS.
	assert_array(after).is_equal([0.8, 0.35, 0.5, true])

func test_edit_layout_closes_settings_first() -> void:
	var p = _open()
	p.start_layout_edit()
	var open_after: bool = p.is_open()
	UILayoutManager.stop_layout_edit()
	assert_bool(open_after).is_false()

# ── Globos de ayuda bajo la pausa ────────────────────────────────────

func test_help_callouts_go_quiet_while_the_tree_is_paused() -> void:
	var helper: CanvasLayer = auto_free(load("res://scenes/ui/HelperPanel.tscn").instantiate())
	add_child(helper)
	var quiet_running: bool = helper.is_quiet()
	get_tree().paused = true
	var quiet_paused: bool = helper.is_quiet()
	get_tree().paused = false
	assert_bool(quiet_running).is_false()
	assert_bool(quiet_paused).is_true()

func test_the_pause_watcher_refreshes_the_callouts() -> void:
	var helper: CanvasLayer = auto_free(load("res://scenes/ui/HelperPanel.tscn").instantiate())
	add_child(helper)
	var watcher: Node = helper.get_node("PauseWatcher")
	assert_int(watcher.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	GameConfig.ui_helper_visible = true
	helper._refresh_callouts()
	get_tree().paused = true
	watcher._process(0.0)
	var shown_paused: bool = helper.is_showing_callouts()
	get_tree().paused = false
	watcher._process(0.0)
	assert_bool(shown_paused).is_false()
	assert_bool(helper.is_showing_callouts()).is_equal(not helper.is_quiet())
