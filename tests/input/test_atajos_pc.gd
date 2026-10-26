extends GdUnitTestSuite
## Atajos de teclado de PC (feat/atajos-pc): B/M/H, 1/2/3 y, con el tablero
## abierto, Enter/D/E. Pasan por InputService -> EventBus.shortcut_pressed.

var _saved_profile := "auto"
var _saved_speed := 1.0
var _got: Array = []

func before_test() -> void:
	_saved_profile = GameConfig.ui_device_profile
	_saved_speed = GameConfig.game_speed
	_got.clear()

func after_test() -> void:
	GameConfig.ui_device_profile = _saved_profile
	GameConfig.set_game_speed(_saved_speed)

func _on(a: StringName) -> void:
	_got.append(a)

func test_mapa_acciones() -> void:
	assert_str(InputService.shortcut_action(KEY_B, false, false, false)).is_equal("build")
	assert_str(InputService.shortcut_action(KEY_M, false, false, false)).is_equal("missions")
	assert_str(InputService.shortcut_action(KEY_H, false, false, false)).is_equal("help")

func test_combate_solo_con_tablero() -> void:
	assert_str(InputService.shortcut_action(KEY_D, false, false, false)).is_equal("")
	assert_str(InputService.shortcut_action(KEY_E, false, false, false)).is_equal("")
	assert_str(InputService.shortcut_action(KEY_ENTER, false, false, false)).is_equal("")
	assert_str(InputService.shortcut_action(KEY_D, true, false, false)).is_equal("defend")
	assert_str(InputService.shortcut_action(KEY_E, true, false, false)).is_equal("wait")
	assert_str(InputService.shortcut_action(KEY_ENTER, true, false, false)).is_equal("end_turn")

func test_tablero_abierto_bloquea_los_del_mapa() -> void:
	assert_str(InputService.shortcut_action(KEY_B, true, false, false)).is_equal("")
	assert_str(InputService.shortcut_action(KEY_M, true, false, false)).is_equal("")
	assert_str(InputService.shortcut_action(KEY_H, true, false, false)).is_equal("")

func test_escribiendo_o_menu_principal_no_dispara() -> void:
	assert_str(InputService.shortcut_action(KEY_B, false, false, true)).is_equal("")
	assert_str(InputService.shortcut_action(KEY_D, true, false, true)).is_equal("")
	assert_str(InputService.shortcut_action(KEY_B, false, true, false)).is_equal("")
	assert_str(InputService.shortcut_action(KEY_1, false, true, false)).is_equal("")

func test_wasd_qe_no_son_atajos_fuera_de_combate() -> void:
	for k in [KEY_W, KEY_A, KEY_S, KEY_Q]:
		assert_str(InputService.shortcut_action(k, false, false, false)).is_equal("")
	assert_str(InputService.shortcut_action(KEY_E, false, false, false)).is_equal("")

func test_emite_por_el_bus() -> void:
	EventBus.shortcut_pressed.connect(_on)
	InputService.handle_shortcut(KEY_B)
	EventBus.shortcut_pressed.disconnect(_on)
	assert_array(_got).contains([&"build"])

func test_velocidad() -> void:
	GameConfig.set_game_speed(1.0)
	InputService.handle_shortcut(KEY_2)
	assert_float(GameConfig.game_speed).is_equal(2.0)
	InputService.handle_shortcut(KEY_1)
	assert_float(GameConfig.game_speed).is_equal(1.0)
	# La x3 no existe: no cambia nada.
	assert_str(InputService.handle_shortcut(KEY_3)).is_equal("")
	assert_float(GameConfig.game_speed).is_equal(1.0)

func test_tooltip_solo_en_pc() -> void:
	GameConfig.ui_device_profile = DeviceProfile.PC
	assert_str(InputService.hint("Construir", "build")).is_equal("Construir (B)")
	GameConfig.ui_device_profile = DeviceProfile.TABLET
	assert_str(InputService.hint("Construir", "build")).is_equal("Construir")

func test_ayuda_tiene_seccion_teclas() -> void:
	var HC := load("res://scripts/ui/HelpCatalog.gd")
	assert_bool(HC.has("guide_keys")).is_true()
	var e: Dictionary = HC.entry("guide_keys")
	var saved: String = Tr.get_locale()
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		assert_str(Tr.t(String(e["title"]))).is_not_equal(String(e["title"]))
		assert_str(Tr.t(String(e["body"]))).contains("Enter")
	Tr.set_locale(saved)
