extends GdUnitTestSuite
## Controles tactiles en pantalla solo donde hacen falta (A5).
##
## En escritorio el D-pad y los botones de zoom/rotar ocupaban las cuatro
## esquinas para nada: hay WASD y rueda. El ajuste tiene tres estados porque
## "automatico" (segun haya pantalla tactil) es el valor bueno para casi todos
## y un interruptor de dos posiciones no puede decirlo.
##
## "auto" significa perfil tablet o movil (DeviceProfile), no "hay pantalla
## tactil" ni "llego un toque": muchos portatiles lo dicen y el D-pad salia en un
## PC que se usa con raton. En PC, nunca por defecto.
##
## Toca GameConfig (autoload) y user://settings.cfg; cada prueba deja ambos
## como los encontro. No se usa monitor_signals sobre autoloads.

var _saved_mode := "auto"
## El settings.cfg del jugador se devuelve byte a byte: reescribirlo con
## save_user_settings() lo dejaba con claves nuevas que el jugador no tenia.
var _had_file := false
var _file_bytes := PackedByteArray()

func before_test() -> void:
	_saved_mode = GameConfig.ui_touch_controls
	_had_file = FileAccess.file_exists(GameConfig.USER_SETTINGS_PATH)
	if _had_file:
		_file_bytes = FileAccess.get_file_as_bytes(GameConfig.USER_SETTINGS_PATH)

func after_test() -> void:
	GameConfig.ui_touch_controls = _saved_mode
	GameConfig._real_touch_seen = false
	if _had_file:
		var f := FileAccess.open(GameConfig.USER_SETTINGS_PATH, FileAccess.WRITE)
		f.store_buffer(_file_bytes)
		f.close()
	elif FileAccess.file_exists(GameConfig.USER_SETTINGS_PATH):
		DirAccess.remove_absolute(GameConfig.USER_SETTINGS_PATH)

func test_always_shows_them_even_without_a_touchscreen() -> void:
	GameConfig.ui_touch_controls = "always"
	assert_bool(GameConfig.touch_controls_enabled()).is_true()

func test_never_hides_them_even_on_a_touchscreen() -> void:
	GameConfig.ui_touch_controls = "never"
	assert_bool(GameConfig.touch_controls_enabled()).is_false()

func test_auto_is_off_on_a_desktop() -> void:
	# Muchos portatiles Windows dicen tener pantalla tactil: "auto" no se fia de
	# eso. En el perfil PC los controles no salen (headless = PC).
	GameConfig.ui_touch_controls = "auto"
	GameConfig._real_touch_seen = false
	assert_str(DeviceProfile.current()).is_equal(DeviceProfile.PC)
	assert_bool(GameConfig.touch_controls_enabled()).is_false()

func test_a_real_touch_on_a_pc_does_not_bring_them_in_auto() -> void:
	# Norma de Bryan: en PC nunca hay controles de movimiento en pantalla por
	# defecto. Un toque en un portatil tactil no cambia eso para toda la sesion.
	GameConfig.ui_touch_controls = "auto"
	GameConfig._real_touch_seen = false
	var received: Array = []
	var listener := func(enabled: bool): received.append(enabled)
	EventBus.touch_controls_changed.connect(listener)
	GameConfig.notice_real_touch()
	GameConfig.notice_real_touch()
	EventBus.touch_controls_changed.disconnect(listener)
	assert_bool(GameConfig.touch_controls_enabled()).is_false()
	assert_array(received).is_empty()

func test_auto_follows_a_touch_profile() -> void:
	var saved := GameConfig.ui_device_profile
	GameConfig.ui_touch_controls = "auto"
	GameConfig.ui_device_profile = "tablet"
	var tablet := GameConfig.touch_controls_enabled()
	GameConfig.ui_device_profile = "phone"
	var phone := GameConfig.touch_controls_enabled()
	GameConfig.ui_device_profile = "pc"
	var pc := GameConfig.touch_controls_enabled()
	GameConfig.ui_device_profile = saved
	assert_bool(tablet).is_true()
	assert_bool(phone).is_true()
	assert_bool(pc).is_false()

## Rediseno 2026-10 (docs/28 §12): "se juega con el dedo" no es lo mismo que
## "hay cruceta". En "auto" la cruceta y el zoom solo salen en tablet; el
## telefono juega con gestos (y conserva CANCELAR mientras coloca).
func test_auto_onscreen_controls_only_on_a_tablet() -> void:
	var saved := GameConfig.ui_device_profile
	GameConfig.ui_touch_controls = "auto"
	var got := []
	for prof in ["pc", "tablet", "phone"]:
		GameConfig.ui_device_profile = prof
		got.append([GameConfig.touch_controls_enabled(), GameConfig.onscreen_controls_visible()])
	GameConfig.ui_device_profile = saved
	assert_array(got).is_equal([[false, false], [true, true], [true, false]])

func test_always_and_never_rule_the_onscreen_controls_too() -> void:
	var saved := GameConfig.ui_device_profile
	GameConfig.ui_device_profile = "phone"
	GameConfig.ui_touch_controls = "always"
	var always := GameConfig.onscreen_controls_visible()
	GameConfig.ui_touch_controls = "never"
	var never := GameConfig.onscreen_controls_visible()
	GameConfig.ui_device_profile = saved
	assert_bool(always).is_true()
	assert_bool(never).is_false()

func test_a_phone_without_dpad_still_gets_cancel_while_placing() -> void:
	var saved := GameConfig.ui_device_profile
	GameConfig.ui_device_profile = "phone"
	GameConfig.ui_touch_controls = "auto"
	var osc = auto_free(load("res://scenes/ui/OnScreenControls.tscn").instantiate())
	add_child(osc)
	var idle: bool = osc.visible
	osc._set_placing(true)
	var placing: bool = osc.visible
	var full: bool = osc.full_controls_shown()
	var cancel: bool = osc.is_placing_shown()
	osc._set_placing(false)
	var after: bool = osc.visible
	GameConfig.ui_device_profile = saved
	assert_bool(idle).is_false()
	assert_bool(placing).is_true()
	assert_bool(full).is_false()
	assert_bool(cancel).is_true()
	assert_bool(after).is_false()

func test_an_explicit_never_wins_over_a_real_touch() -> void:
	GameConfig.ui_touch_controls = "never"
	GameConfig._real_touch_seen = false
	GameConfig.notice_real_touch()
	assert_bool(GameConfig.touch_controls_enabled()).is_false()

func test_the_default_is_auto() -> void:
	assert_array(GameConfig.TOUCH_CONTROLS_MODES).contains(["auto", "always", "never"])
	var fresh := GameConfig.TOUCH_CONTROLS_MODES[0]
	assert_str(fresh).is_equal("auto")

func test_the_choice_survives_a_save_and_a_load() -> void:
	GameConfig.set_touch_controls("never")
	GameConfig.ui_touch_controls = "auto"  # se pierde en memoria a proposito
	GameConfig.load_user_settings()
	assert_str(GameConfig.ui_touch_controls).is_equal("never")

func test_an_unknown_value_in_the_file_falls_back_to_auto() -> void:
	# Un archivo editado a mano o de una version vieja no puede dejar los
	# controles en un estado que nadie eligio.
	var cf := ConfigFile.new()
	cf.load(GameConfig.USER_SETTINGS_PATH)
	cf.set_value("ui", "touch_controls", "banana")
	cf.save(GameConfig.USER_SETTINGS_PATH)
	GameConfig.ui_touch_controls = "never"
	GameConfig.load_user_settings()
	assert_str(GameConfig.ui_touch_controls).is_equal("auto")

func test_set_touch_controls_rejects_garbage() -> void:
	GameConfig.set_touch_controls("banana")
	assert_str(GameConfig.ui_touch_controls).is_equal("auto")

func test_changing_the_mode_announces_the_resolved_state() -> void:
	GameConfig.ui_touch_controls = "never"
	var received: Array = []
	var listener := func(enabled: bool): received.append(enabled)
	EventBus.touch_controls_changed.connect(listener)
	GameConfig.set_touch_controls("always")
	EventBus.touch_controls_changed.disconnect(listener)
	assert_array(received).is_equal([true])

func test_the_same_mode_twice_does_not_announce_twice() -> void:
	GameConfig.ui_touch_controls = "always"
	var received: Array = []
	var listener := func(enabled: bool): received.append(enabled)
	EventBus.touch_controls_changed.connect(listener)
	GameConfig.set_touch_controls("always")
	EventBus.touch_controls_changed.disconnect(listener)
	assert_array(received).is_empty()

func test_the_on_screen_layer_obeys_the_setting_live() -> void:
	GameConfig.ui_touch_controls = "never"
	var controls: CanvasLayer = auto_free(load("res://scenes/ui/OnScreenControls.tscn").instantiate())
	add_child(controls)
	await await_idle_frame()
	assert_bool(controls.visible).is_false()

	GameConfig.set_touch_controls("always")
	await await_idle_frame()
	assert_bool(controls.visible).is_true()

	GameConfig.set_touch_controls("never")
	await await_idle_frame()
	assert_bool(controls.visible).is_false()

func test_auto_on_a_touch_laptop_stays_off_however_many_touches() -> void:
	# Portatil Windows tactil: perfil PC detectado, toques reales, pantalla que se
	# declara tactil. "Automatico" es solo movil y tablet: nada de eso lo enciende.
	var saved_profile := GameConfig.ui_device_profile
	GameConfig.ui_device_profile = "auto"
	GameConfig.ui_touch_controls = "auto"
	GameConfig._real_touch_seen = false
	for i in 5:
		GameConfig.notice_real_touch()
	var auto_on := GameConfig.touch_controls_enabled()
	GameConfig.ui_touch_controls = "always"
	var always_on := GameConfig.touch_controls_enabled()
	GameConfig.ui_device_profile = saved_profile
	assert_str(DeviceProfile.detected()).is_equal(DeviceProfile.PC)
	assert_bool(auto_on).is_false()
	# Lo que le queda al portatil tactil: "Siempre".
	assert_bool(always_on).is_true()

func test_the_setting_tells_a_touch_laptop_to_pick_always() -> void:
	assert_str(Tr.t("OPT_TOUCH_AUTO")).contains("tablet")
	assert_str(Tr.t("LBL_TOUCH_AUTO_HINT")).contains(Tr.t("OPT_TOUCH_ALWAYS"))
	var panel = load("res://scenes/ui/SettingsPanel.tscn").instantiate()
	add_child(panel)
	panel.toggle()
	var hint: Label = panel.find_child("TouchAutoHint", true, false)
	var found: bool = hint != null
	var text: String = hint.text if found else ""
	if panel.is_open():
		panel._needs_rebuild = false
		panel.toggle()
	panel.free()
	assert_bool(found).is_true()
	assert_str(text).is_equal(Tr.t("LBL_TOUCH_AUTO_HINT"))
