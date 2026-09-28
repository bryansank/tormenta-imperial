extends GdUnitTestSuite
## Perfiles de dispositivo (docs/21): deteccion, escala del lienzo en cada
## proporcion de pantalla, cubo de proporcion, valores de cada perfil y textos
## de ayuda de dedo o de raton.
##
## Las cuentas son estaticas y puras. Lo que toca GameConfig (perfil forzado)
## pasa por SettingsParking. No se usa monitor_signals sobre autoloads.

const SettingsParking := preload("res://tests/save/settings_parking.gd")

var _parked: Dictionary

func before_test() -> void:
	_parked = SettingsParking.park()

func after_test() -> void:
	SettingsParking.restore(_parked)

# ── Deteccion ────────────────────────────────────────────────────────

func test_a_desktop_is_a_pc_whatever_its_screen() -> void:
	assert_str(DeviceProfile.detect_from([], Vector2i(2560, 1600), 280)).is_equal(DeviceProfile.PC)
	assert_str(DeviceProfile.detect_from([], Vector2i(1280, 800), 96)).is_equal(DeviceProfile.PC)

func test_a_windows_touch_laptop_is_still_a_pc() -> void:
	# Sin feature de movil no importa que la pantalla sea tactil ni pequena.
	assert_str(DeviceProfile.detect_from(["pc"], Vector2i(1366, 768), 120)).is_equal(DeviceProfile.PC)

func test_an_android_tablet_is_a_tablet() -> void:
	# 2560x1600 a 320 dpi: lado corto 1600 px = 800 dp.
	assert_str(DeviceProfile.detect_from(["android"], Vector2i(2560, 1600), 320)).is_equal(DeviceProfile.TABLET)
	# El emulador 4:3 de 2048x1536 a 320 dpi: 768 dp.
	assert_str(DeviceProfile.detect_from(["android", "mobile"], Vector2i(2048, 1536), 320)).is_equal(DeviceProfile.TABLET)

func test_an_android_phone_is_a_phone() -> void:
	# 1080x2400 a 420 dpi: 411 dp.
	assert_str(DeviceProfile.detect_from(["android"], Vector2i(1080, 2400), 420)).is_equal(DeviceProfile.PHONE)

func test_an_ipad_on_the_web_without_dpi_is_measured_in_pixels() -> void:
	assert_str(DeviceProfile.detect_from(["web_ios"], Vector2i(768, 1024), 0)).is_equal(DeviceProfile.TABLET)
	assert_str(DeviceProfile.detect_from(["web_android"], Vector2i(360, 780), 0)).is_equal(DeviceProfile.PHONE)

func test_the_tablet_threshold_is_600_dp() -> void:
	assert_float(DeviceProfile.shortest_side_dp(Vector2i(1920, 1200), 320)).is_equal(600.0)
	assert_str(DeviceProfile.detect_from(["android"], Vector2i(1920, 1200), 320)).is_equal(DeviceProfile.TABLET)
	assert_str(DeviceProfile.detect_from(["android"], Vector2i(1920, 1198), 320)).is_equal(DeviceProfile.PHONE)

func test_headless_detects_a_pc() -> void:
	assert_str(DeviceProfile.detected()).is_equal(DeviceProfile.PC)

# ── Perfil forzado ───────────────────────────────────────────────────

func test_the_override_wins_over_the_detection() -> void:
	GameConfig.ui_device_profile = "tablet"
	assert_str(DeviceProfile.current()).is_equal(DeviceProfile.TABLET)
	GameConfig.ui_device_profile = "phone"
	assert_str(DeviceProfile.current()).is_equal(DeviceProfile.PHONE)
	GameConfig.ui_device_profile = "auto"
	assert_str(DeviceProfile.current()).is_equal(DeviceProfile.detected())

func test_the_override_survives_a_save_and_a_load() -> void:
	DeviceProfile.set_profile_override("tablet")
	GameConfig.ui_device_profile = "auto"
	GameConfig.load_user_settings()
	assert_str(GameConfig.ui_device_profile).is_equal("tablet")

func test_garbage_in_the_file_falls_back_to_auto() -> void:
	var cf := ConfigFile.new()
	cf.load(GameConfig.USER_SETTINGS_PATH)
	cf.set_value("interfaz", "device_profile", "nevera")
	cf.set_value("interfaz", "ui_scale_pct", 900)
	cf.set_value("interfaz", "text_size", "enorme")
	cf.set_value("interfaz", "palette", "arcoiris")
	cf.set_value("interfaz", "panel_opacity", 0.01)
	cf.save(GameConfig.USER_SETTINGS_PATH)
	GameConfig.load_user_settings()
	assert_str(GameConfig.ui_device_profile).is_equal("auto")
	assert_int(GameConfig.ui_scale_pct).is_equal(GameConfig.UI_SCALE_MAX)
	assert_str(GameConfig.ui_text_size).is_equal("auto")
	assert_str(GameConfig.ui_palette).is_equal("default")
	assert_float(GameConfig.ui_panel_opacity).is_equal(UITheme.OPACITY_MIN)

func test_each_profile_brings_its_defaults() -> void:
	GameConfig.ui_scale_pct = 0
	GameConfig.ui_text_size = "auto"
	GameConfig.ui_device_profile = "pc"
	var pc := [DeviceProfile.effective_ui_scale(), DeviceProfile.effective_text_size(), DeviceProfile.is_touch_profile()]
	GameConfig.ui_device_profile = "tablet"
	var tablet := [DeviceProfile.effective_ui_scale(), DeviceProfile.effective_text_size(), DeviceProfile.is_touch_profile()]
	GameConfig.ui_device_profile = "phone"
	var phone := [DeviceProfile.effective_ui_scale(), DeviceProfile.effective_text_size(), DeviceProfile.is_touch_profile(), DeviceProfile.layout_variant()]
	assert_array(pc).is_equal([1.0, "normal", false])
	assert_array(tablet).is_equal([1.15, "normal", true])
	assert_array(phone).is_equal([1.3, "large", true, "compact"])

func test_an_explicit_scale_and_text_size_win_over_the_profile() -> void:
	GameConfig.ui_device_profile = "tablet"
	GameConfig.ui_scale_pct = 90
	GameConfig.ui_text_size = "xlarge"
	assert_float(DeviceProfile.effective_ui_scale()).is_equal_approx(0.9, 0.001)
	assert_str(DeviceProfile.effective_text_size()).is_equal("xlarge")

# ── Escala del lienzo: sin bandas negras en ninguna proporcion ──────

func _logical(window: Vector2, ui_scale: float) -> Vector2:
	return DeviceProfile.logical_size_for(window, DeviceProfile.content_scale_for(window, ui_scale))

func test_16_9_at_100_percent_is_the_design_canvas() -> void:
	assert_vector(_logical(Vector2(1280, 720), 1.0)).is_equal_approx(Vector2(1280, 720), Vector2(1, 1))
	assert_vector(_logical(Vector2(1920, 1080), 1.0)).is_equal_approx(Vector2(1280, 720), Vector2(1, 1))

func test_16_10_and_4_3_grow_the_canvas_instead_of_adding_bars() -> void:
	# aspect=expand: el lado sobrante se convierte en lienzo, no en negro.
	assert_vector(_logical(Vector2(1280, 800), 1.0)).is_equal_approx(Vector2(1280, 800), Vector2(1, 1))
	assert_vector(_logical(Vector2(1024, 768), 1.0)).is_equal_approx(Vector2(1280, 960), Vector2(1, 1))

func test_the_tablet_scale_on_a_16_10_tablet() -> void:
	# 2560x1600 a 115 %: 1280x800 de lienzo dividido por 1.15.
	var size := _logical(Vector2(2560, 1600), 1.15)
	assert_float(size.x).is_between(1110.0, 1116.0)
	assert_float(size.y).is_between(693.0, 698.0)
	assert_float(size.x / size.y).is_equal_approx(1.6, 0.01)

func test_ultrawide_keeps_720_of_height() -> void:
	assert_vector(_logical(Vector2(2560, 1080), 1.0)).is_equal_approx(Vector2(1706.7, 720), Vector2(1, 1))

func test_a_portrait_phone_gets_the_narrow_canvas() -> void:
	var size := _logical(Vector2(400, 720), 1.0)
	assert_float(size.x).is_equal_approx(DeviceProfile.PORTRAIT_WIDTH, 0.5)
	assert_float(size.x).is_less(UILayoutConfig.NARROW_WIDTH)
	# Con la escala del perfil movil, no por debajo del minimo en vertical.
	var phone := _logical(Vector2(1080, 2400), 1.3)
	assert_float(phone.x).is_greater_equal(DeviceProfile.MIN_LOGICAL_WIDTH_PORTRAIT - 0.5)
	assert_float(phone.x).is_less(UILayoutConfig.NARROW_WIDTH)

func test_scale_never_squeezes_the_canvas_below_the_minimum() -> void:
	# 150 % en 1280x720 se queda en 133 %: la columna del menu ☰ tiene que caber.
	var size := _logical(Vector2(1280, 720), 1.5)
	assert_float(size.y).is_equal_approx(DeviceProfile.MIN_LOGICAL_HEIGHT, 0.5)
	var tiny := _logical(Vector2(1024, 768), 3.0)
	assert_float(tiny.y).is_greater_equal(DeviceProfile.MIN_LOGICAL_HEIGHT - 0.5)

func test_the_open_sidebar_fits_at_the_minimum_height() -> void:
	var saved := UILayoutManager.is_sidebar_expanded()
	UILayoutManager._sidebar_expanded = true
	var bottom := UILayoutManager.get_sidebar_bottom()
	UILayoutManager._sidebar_expanded = saved
	assert_float(bottom).is_less_equal(DeviceProfile.MIN_LOGICAL_HEIGHT - UILayoutManager.EDGE_MARGIN)

func test_a_smaller_scale_shows_more_canvas() -> void:
	assert_float(_logical(Vector2(1280, 720), 0.75).y).is_equal_approx(960.0, 0.5)

func test_headless_leaves_the_content_scale_alone() -> void:
	DeviceProfile.apply_scale()
	assert_float(get_tree().root.content_scale_factor).is_equal(1.0)

# ── Cubo de proporcion (la disposicion se guarda por cubo) ──────────

func test_aspect_buckets() -> void:
	assert_str(DeviceProfile.aspect_bucket(Vector2(1280, 720))).is_equal("16:9")
	assert_str(DeviceProfile.aspect_bucket(Vector2(1920, 1080))).is_equal("16:9")
	assert_str(DeviceProfile.aspect_bucket(Vector2(1280, 800))).is_equal("16:10")
	assert_str(DeviceProfile.aspect_bucket(Vector2(2560, 1600))).is_equal("16:10")
	assert_str(DeviceProfile.aspect_bucket(Vector2(1024, 768))).is_equal("4:3")
	assert_str(DeviceProfile.aspect_bucket(Vector2(2560, 1080))).is_equal("21:9")
	assert_str(DeviceProfile.aspect_bucket(Vector2(400, 720))).is_equal("portrait")

func test_the_layout_key_carries_profile_and_aspect() -> void:
	GameConfig.ui_device_profile = "tablet"
	assert_str(DeviceProfile.layout_key()).starts_with("tablet|")

# ── Textos de dedo o de raton ────────────────────────────────────────

func test_help_texts_follow_the_input_style() -> void:
	GameConfig.ui_touch_controls = "auto"
	GameConfig.ui_device_profile = "pc"
	var mouse := Tr.ti("LBL_HELP_CAMERA_DESKTOP")
	GameConfig.ui_device_profile = "tablet"
	var touch := Tr.ti("LBL_HELP_CAMERA_DESKTOP")
	assert_str(mouse).is_equal(Tr.t("LBL_HELP_CAMERA_DESKTOP"))
	assert_str(mouse).contains("WASD")
	assert_str(touch).is_equal(Tr.t("LBL_HELP_CAMERA_DESKTOP_TOUCH"))
	assert_str(touch).not_contains("WASD")

func test_touch_texts_never_talk_about_the_mouse() -> void:
	for locale in Tr.LOCALES:
		var table: Dictionary = Tr._STRINGS[locale]
		for key in table:
			if not String(key).ends_with("_TOUCH"):
				continue
			var text := String(table[key]).to_lower()
			for word in ["wasd", "rueda", "ratón", "raton", "clic", "wheel", "mouse", "click", "esc "]:
				assert_bool(text.contains(word)).override_failure_message("%s/%s dice '%s'" % [locale, key, word]).is_false()

func test_every_touch_variant_has_its_mouse_original() -> void:
	for locale in Tr.LOCALES:
		var table: Dictionary = Tr._STRINGS[locale]
		for key in table:
			if String(key).ends_with("_TOUCH") and key != "LBL_NODE_PICK_TOUCH":
				var base := String(key).trim_suffix("_TOUCH")
				assert_bool(table.has(base)).override_failure_message("%s sin %s" % [key, base]).is_true()

func test_without_a_touch_variant_ti_is_t() -> void:
	GameConfig.ui_device_profile = "tablet"
	assert_str(Tr.ti("BTN_BUILD")).is_equal(Tr.t("BTN_BUILD"))
