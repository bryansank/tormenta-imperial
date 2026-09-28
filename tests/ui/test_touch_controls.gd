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
