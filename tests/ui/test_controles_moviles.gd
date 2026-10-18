extends GdUnitTestSuite
## Controles moviles (feat/controles-moviles, docs/21 §2 y §9):
## - Los controles en pantalla (cruceta, zoom, girar, R, CANCELAR y el ✓ de
##   colocar) crecen con Ajustes → Controles → Tamano de los controles; "auto"
##   es el del perfil (PC 100 %, tablet 115 %, movil 130 %). Se guarda en
##   settings.cfg [interfaz] touch_controls_size, nunca en la partida.
## - Nunca se salen del lienzo (UILayoutConfig.touch_controls_fit) y lo que va
##   encima de ellos sube lo mismo (touch_controls_lift).
## - En tablet y movil, Ajustes lleva filas de dedo (UITheme.SETTINGS_ROW_H).
##
## settings.cfg, GameConfig y los tokens de UITheme vuelven intactos.

const SettingsParking := preload("res://tests/save/settings_parking.gd")
const SettingsScene := preload("res://scenes/ui/SettingsPanel.tscn")
const OSC := preload("res://scripts/ui/OnScreenControls.gd")

var _parked: Dictionary
var _panel = null

func before_test() -> void:
	_parked = SettingsParking.park()

func after_test() -> void:
	if is_instance_valid(_panel):
		if _panel.is_open():
			_panel._needs_rebuild = false
			_panel.toggle()
		_panel.free()
	_panel = null
	SettingsParking.restore(_parked)
	# Tokens de UITheme como los deja el perfil restaurado (PC en headless).
	DeviceProfile.apply_theme()

func _force_profile(profile: String) -> void:
	GameConfig.ui_device_profile = profile
	DeviceProfile.apply_theme()

# ── Escala: perfil, modos y guardado ──

func test_auto_follows_the_profile_and_phone_is_biggest() -> void:
	var d: Dictionary = DeviceProfile.DEFAULTS
	assert_float(float(d["pc"]["controls_size"])).is_equal(1.0)
	assert_float(float(d["tablet"]["controls_size"])).is_greater(1.0)
	assert_float(float(d["phone"]["controls_size"])).is_greater(float(d["tablet"]["controls_size"]))
	assert_float(GameConfig.touch_controls_scale_for("auto", 1.3)).is_equal(1.3)
	assert_float(GameConfig.touch_controls_scale_for("large", 1.3)).is_equal(1.25)
	assert_float(GameConfig.touch_controls_scale_for("bogus", 1.15)).is_equal(1.15)

func test_forcing_the_profile_changes_the_auto_size() -> void:
	GameConfig.ui_touch_controls_size = "auto"
	_force_profile("phone")
	assert_float(GameConfig.touch_controls_scale()).is_equal(1.3)
	_force_profile("pc")
	assert_float(GameConfig.touch_controls_scale()).is_equal(1.0)

func test_the_size_is_saved_in_settings_interfaz_not_in_the_game() -> void:
	GameConfig.set_touch_controls_size("xlarge")
	var cf := ConfigFile.new()
	assert_int(cf.load(GameConfig.USER_SETTINGS_PATH)).is_equal(OK)
	assert_str(str(cf.get_value("interfaz", "touch_controls_size", ""))).is_equal("xlarge")
	GameConfig.ui_touch_controls_size = "auto"
	GameConfig.load_user_settings()
	assert_str(GameConfig.ui_touch_controls_size).is_equal("xlarge")

func test_an_unknown_saved_size_falls_back_to_auto() -> void:
	var cf := ConfigFile.new()
	cf.load(GameConfig.USER_SETTINGS_PATH)
	cf.set_value("interfaz", "touch_controls_size", "gigante")
	cf.save(GameConfig.USER_SETTINGS_PATH)
	GameConfig.load_user_settings()
	assert_str(GameConfig.ui_touch_controls_size).is_equal("auto")

func test_changing_the_size_is_announced_with_the_resolved_scale() -> void:
	var got: Array = []
	var cb := func(s: float): got.append(s)
	EventBus.touch_controls_size_changed.connect(cb)
	GameConfig.set_touch_controls_size("large", false)
	EventBus.touch_controls_size_changed.disconnect(cb)
	assert_array(got).is_equal([1.25])

# ── Los botones crecen y caben ──

func test_on_screen_buttons_grow_with_the_scale() -> void:
	var osc = auto_free(OSC.new())
	add_child(osc)
	osc.set_controls_scale(1.0)
	var plus: Button = osc.find_child("ZoomIn", true, false)
	var cancel: Button = osc.find_child("CancelPlacement", true, false)
	var base_plus := plus.custom_minimum_size
	var base_cancel := cancel.custom_minimum_size
	assert_float(base_plus.y).is_equal(48.0)
	osc.set_controls_scale(1.5)
	assert_vector(plus.custom_minimum_size).is_equal(base_plus * 1.5)
	assert_vector(cancel.custom_minimum_size).is_equal(base_cancel * 1.5)
	assert_float(osc.get_controls_scale()).is_equal(1.5)
	# Volver a 100 % deja todo como estaba: nada se acumula.
	osc.set_controls_scale(1.0)
	assert_vector(plus.custom_minimum_size).is_equal(base_plus)

func test_the_opacity_survives_a_resize() -> void:
	var osc = auto_free(OSC.new())
	add_child(osc)
	osc.set_opacity(0.6)
	osc.set_controls_scale(1.3)
	for btn in osc.get_buttons():
		assert_float((btn as Button).modulate.a).is_equal_approx(0.6, 0.001)

func test_the_controls_never_leave_a_phone_screen() -> void:
	# Movil apaisado (1280x720 a 130 %), movil real (2400x1080 a 130 %), vertical.
	for vp in [Vector2(985, 554), Vector2(1231, 554), Vector2(480, 1000), Vector2(400, 720)]:
		for requested in [0.85, 1.0, 1.3, 1.5]:
			var s := UILayoutConfig.touch_controls_fit(requested, vp)
			assert_float(s).is_less_equal(requested + 0.0001)
			assert_float(s).is_greater_equal(UILayoutConfig.TOUCH_SCALE_FLOOR)
			var width: float = s * (UILayoutConfig.TOUCH_DPAD_SIDE + UILayoutConfig.TOUCH_RIGHT_COLUMN_W) \
				+ UILayoutConfig.TOUCH_CONTROLS_MARGIN * 2.0
			var height: float = s * UILayoutConfig.TOUCH_RIGHT_COLUMN_H + UILayoutConfig.TOUCH_CONTROLS_MARGIN * 2.0
			if s > UILayoutConfig.TOUCH_SCALE_FLOOR:
				assert_float(width).override_failure_message("%s a %s" % [vp, requested]).is_less_equal(vp.x)
				assert_float(height).override_failure_message("%s a %s" % [vp, requested]).is_less_equal(vp.y)

func test_a_phone_keeps_its_bigger_controls_in_landscape() -> void:
	assert_float(UILayoutConfig.touch_controls_fit(1.3, Vector2(985, 554))).is_equal(1.3)

func test_what_sits_over_the_controls_moves_up_with_them() -> void:
	assert_float(UILayoutConfig.touch_controls_lift(1.0)).is_equal(0.0)
	assert_float(UILayoutConfig.touch_controls_lift(0.85)).is_equal(0.0)
	assert_float(UILayoutConfig.touch_controls_lift(1.5)).is_greater(0.0)
	var slots: Dictionary = UILayoutConfig.SLOTS
	# Apaisado: los globos de las esquinas de abajo suben; CONSTRUIR (centro) no.
	# Los avisos ya no viven abajo (columna izquierda, 2026-10-18): no suben,
	# NotificationPanel.capacity() deja uno si no caben dos sobre la cruceta.
	assert_bool(UILayoutConfig.sits_above_touch_controls("toast_area", slots["toast_area"], false)).is_false()
	assert_bool(UILayoutConfig.sits_above_touch_controls("tip_above_dpad", slots["tip_above_dpad"], false)).is_true()
	assert_bool(UILayoutConfig.sits_above_touch_controls("tip_bottom_right", slots["tip_bottom_right"], false)).is_true()
	assert_bool(UILayoutConfig.sits_above_touch_controls("bottom_center", slots["bottom_center"], false)).is_false()
	# Vertical: CONSTRUIR va encima de la cruceta y sube tambien.
	assert_bool(UILayoutConfig.sits_above_touch_controls("bottom_center", slots["bottom_center"], true)).is_true()
	# Los controles mismos y lo de arriba, nunca.
	assert_bool(UILayoutConfig.sits_above_touch_controls("bottom_controls", slots["bottom_controls"], true)).is_false()
	assert_bool(UILayoutConfig.sits_above_touch_controls("top_right", slots.get("top_right", {}), true)).is_false()

func test_no_lift_on_pc_without_touch_controls() -> void:
	GameConfig.ui_touch_controls = "never"
	GameConfig.ui_touch_controls_size = "xlarge"
	assert_float(UILayoutManager.touch_controls_lift()).is_equal(0.0)
	var toast: Dictionary = UILayoutManager.get_slot("toast_area")
	assert_float(float(toast["margin"]["bottom"])).is_equal(float(UILayoutConfig.SLOTS["toast_area"]["margin"]["bottom"]))

func test_lift_applies_with_touch_controls_on() -> void:
	GameConfig.ui_touch_controls = "always"
	GameConfig.ui_touch_controls_size = "xlarge"
	var lift: float = UILayoutManager.touch_controls_lift()
	assert_float(lift).is_greater(0.0)
	# El globo de la camara, encima de la cruceta (los avisos ya no viven abajo).
	var tip: Dictionary = UILayoutManager.get_slot("tip_above_dpad")
	assert_float(float(tip["margin"]["bottom"])).is_equal(
		float(UILayoutConfig.SLOTS["tip_above_dpad"]["margin"]["bottom"]) + lift)
	# La constante del slot no se toca (get_slot devuelve una copia).
	assert_int(int(UILayoutConfig.SLOTS["tip_above_dpad"]["margin"]["bottom"])).is_equal(200)

# ── Ajustes en tablet y movil ──

func test_pc_settings_rows_stay_as_they_were() -> void:
	_force_profile("pc")
	assert_int(UITheme.SETTINGS_ROW_H).is_equal(UITheme.MIN_BTN_H)
	assert_bool(UITheme.settings_touch()).is_false()

func test_phone_settings_controls_are_finger_sized() -> void:
	_force_profile("phone")
	assert_int(UITheme.SETTINGS_ROW_H).is_greater_equal(48)
	assert_int(UITheme.SETTINGS_ROW_H).is_greater(UITheme._BASE_MIN_BTN_H)
	_panel = SettingsScene.instantiate()
	add_child(_panel)
	_panel.toggle()
	var panel: Control = _panel._panel
	var small: Array = []
	for node in panel.find_children("*", "BaseButton", true, false):
		var c := node as Control
		if c.custom_minimum_size.y < float(UITheme.SETTINGS_ROW_H) - 0.5:
			small.append(c.name)
	assert_array(small).is_empty()
	for node in panel.find_children("Slider_*", "HSlider", true, false):
		assert_float((node as Control).custom_minimum_size.y).is_greater_equal(float(UITheme.SETTINGS_ROW_H))
	var tabs: TabContainer = panel.find_child("SettingsTabs", true, false)
	var sb := tabs.get_theme_stylebox("tab_selected")
	assert_float(sb.content_margin_top * 2.0 + UITheme.FONT_BODY).is_greater_equal(float(UITheme.SETTINGS_ROW_H) - 2.0)

func test_settings_still_fit_on_a_phone() -> void:
	_force_profile("phone")
	_panel = SettingsScene.instantiate()
	add_child(_panel)
	_panel.toggle()
	var vp: Vector2 = _panel.get_viewport().get_visible_rect().size
	for i in 5:
		_panel.select_tab(i)
		await await_idle_frame()
		var r: Rect2 = (_panel._panel as Control).get_global_rect()
		assert_bool(Rect2(Vector2.ZERO, vp).encloses(r)).override_failure_message("pestana %d: %s en %s" % [i, r, vp]).is_true()

func test_controls_tab_has_the_size_row_and_its_reset() -> void:
	_panel = SettingsScene.instantiate()
	add_child(_panel)
	_panel.toggle()
	var row = _panel.find_child("ControlsSizeRow", true, false)
	assert_object(row).is_not_null()
	var picker := row.get_child(1) as OptionButton
	assert_int(picker.item_count).is_equal(GameConfig.TOUCH_CONTROLS_SIZE_MODES.size())
	picker.select(4)
	picker.item_selected.emit(4)
	assert_str(GameConfig.ui_touch_controls_size).is_equal("xlarge")
	_panel.reset_controls()
	assert_str(GameConfig.ui_touch_controls_size).is_equal("auto")
	assert_int(picker.selected).is_equal(0)

func test_size_texts_exist_in_both_languages() -> void:
	for key in ["LBL_CONTROLS_SIZE", "LBL_CONTROLS_SIZE_TIP", "OPT_CONTROLS_SIZE_AUTO", "OPT_CONTROLS_SIZE_SMALL",
			"OPT_CONTROLS_SIZE_NORMAL", "OPT_CONTROLS_SIZE_LARGE", "OPT_CONTROLS_SIZE_XLARGE"]:
		for loc in Tr.LOCALES:
			assert_bool((Tr._STRINGS[loc] as Dictionary).has(key)).override_failure_message("%s %s" % [loc, key]).is_true()
