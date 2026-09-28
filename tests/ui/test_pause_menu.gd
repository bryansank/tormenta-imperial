extends GdUnitTestSuite
## El menu de pausa: ESC lo abre solo cuando ESC no es de otro (una ventana
## abierta, un edificio en la mano, el menu principal encima), la pausa es de
## verdad (los servicios dejan de procesar, el menu y la musica no) y lo que
## presta —Ajustes, la intro— vuelve a su sitio al cerrarse.
##
## Cada test que pausa el arbol lo suelta antes de esperar un frame: con el
## arbol en pausa el runner de gdUnit tambien se pararia.

var _stubs: Array = []

func before_test() -> void:
	get_tree().paused = false
	_stubs.clear()

func after_test() -> void:
	get_tree().paused = false
	for stub in _stubs:
		if is_instance_valid(stub):
			stub.queue_free()

func _menu() -> CanvasLayer:
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/PauseMenu.tscn").instantiate())
	add_child(menu)
	return menu

func _esc() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	return event

## Un BuildingPlacer de mentira: solo contesta a is_idle().
func _placer(idle: bool) -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar idle := true\nfunc is_idle() -> bool:\n\treturn idle\n"
	script.reload()
	var node := Node.new()
	node.set_script(script)
	node.name = "BuildingPlacer"
	node.set("idle", idle)
	add_child(node)
	_stubs.append(node)
	return node

# ── Cuando ESC es pausa ──────────────────────────────────────────────

func test_escape_opens_the_pause_and_pauses_the_tree() -> void:
	var menu := _menu()
	menu._unhandled_input(_esc())
	var open: bool = menu.is_open()
	var paused: bool = get_tree().paused
	menu.resume()
	assert_bool(open).is_true()
	assert_bool(paused).is_true()
	assert_bool(get_tree().paused).is_false()

func test_escape_again_resumes() -> void:
	var menu := _menu()
	menu._unhandled_input(_esc())
	menu._unhandled_input(_esc())
	assert_bool(menu.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()

func test_an_open_window_keeps_escape_for_itself() -> void:
	# UIManager cierra la ventana de arriba con ESC; la pausa no se mete.
	var menu := _menu()
	var window: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(window)
	UIManager.open_window(window)
	var can: bool = menu.can_pause()
	UIManager.close_window(window)
	assert_bool(can).is_false()
	assert_bool(menu.can_pause()).is_true()

func test_a_building_in_hand_keeps_escape_for_the_placer() -> void:
	var placer := _placer(false)
	var menu := _menu()
	assert_bool(menu.can_pause()).is_false()
	placer.set("idle", true)
	assert_bool(menu.can_pause()).is_true()

func test_it_never_stacks_over_someone_elses_pause() -> void:
	var menu := _menu()
	get_tree().paused = true
	var can: bool = menu.can_pause()
	get_tree().paused = false
	assert_bool(can).is_false()

func test_the_touch_button_opens_it_too() -> void:
	var menu := _menu()
	menu.pause_button().pressed.emit()
	var open: bool = menu.is_open()
	var button_hidden: bool = not menu.pause_button().visible
	menu.resume()
	assert_bool(open).is_true()
	assert_bool(button_hidden).is_true()
	assert_bool(menu.pause_button().visible).is_true()

# ── La pausa es de verdad ────────────────────────────────────────────

func test_services_stop_while_the_menu_and_the_music_keep_going() -> void:
	var menu := _menu()
	menu.open_pause()
	# can_process() es lo que el motor mira antes de llamar a _process, a los
	# Timer y a la entrada: si da false, ese nodo esta parado de verdad.
	var production: bool = ProductionManager.can_process()
	var population: bool = PopulationManager.can_process()
	var storm: bool = StormManager.can_process()
	var army: bool = ArmyManager.can_process()
	var combat: bool = CombatManager.can_process()
	var audio: bool = AudioManager.can_process()
	var own: bool = menu.can_process()
	menu.resume()
	assert_bool(production).is_false()
	assert_bool(population).is_false()
	assert_bool(storm).is_false()
	assert_bool(army).is_false()
	assert_bool(combat).is_false()
	assert_bool(audio).is_true()
	assert_bool(own).is_true()

func test_a_pausable_timer_does_not_tick_while_paused() -> void:
	var timer: Timer = auto_free(Timer.new())
	timer.wait_time = 5.0
	add_child(timer)
	timer.start()
	var menu := _menu()
	menu.open_pause()
	var left_before: float = timer.time_left
	var timer_runs: bool = timer.can_process()
	menu.resume()
	assert_bool(timer_runs).is_false()
	assert_float(left_before).is_greater(0.0)

# ── Lo que presta ────────────────────────────────────────────────────

func test_settings_can_be_used_while_paused_and_come_back() -> void:
	var settings: CanvasLayer = auto_free(load("res://scenes/ui/SettingsPanel.tscn").instantiate())
	add_child(settings)
	var menu := _menu()
	menu.open_pause()
	menu._on_settings()
	var mode_open: int = settings.process_mode
	var card_hidden: bool = not menu._root.visible
	# ESC con Ajustes encima cierra Ajustes, no la pausa.
	menu._unhandled_input(_esc())
	var still_open: bool = menu.is_open()
	var card_back: bool = menu._root.visible
	var mode_back: int = settings.process_mode
	menu.resume()
	assert_int(mode_open).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_bool(card_hidden).is_true()
	assert_bool(still_open).is_true()
	assert_bool(card_back).is_true()
	assert_int(mode_back).is_equal(Node.PROCESS_MODE_INHERIT)

## Historia (integracion #31 + #32): el menu se cierra y suelta la pausa ANTES
## de pedir el prologo, porque el prologo espera a que no haya pausa ni menu.
## Al cerrar el prologo se vuelve a la partida, sin pausa y sin el menu.
func test_story_closes_the_menu_and_replays_the_prologue() -> void:
	var tutorial: CanvasLayer = auto_free(load("res://scenes/ui/TutorialPanel.tscn").instantiate())
	add_child(tutorial)
	var seen_before: bool = TutorialManager.intro_seen
	var menu := _menu()
	menu.open_pause()
	menu._on_story()
	var menu_closed: bool = not menu.is_open()
	var intro_open: bool = tutorial.is_intro_open()
	tutorial._close()
	var card_back: bool = menu._root.visible
	# El prologo pausa mientras se lee (la pausa es suya, no del menu) y la suelta.
	var paused: bool = get_tree().paused
	TutorialManager.intro_seen = seen_before
	assert_bool(menu_closed).is_true()
	assert_bool(paused).is_false()
	assert_bool(intro_open).is_true()
	assert_bool(card_back).is_false()

func test_main_menu_hands_the_pause_to_the_title() -> void:
	var title: CanvasLayer = auto_free(load("res://scenes/ui/TitleMenu.tscn").instantiate())
	add_child(title)
	var menu := _menu()
	menu.open_pause()
	menu._on_main_menu()
	var pause_closed: bool = not menu.is_open()
	var title_open: bool = title.is_open()
	var paused: bool = get_tree().paused
	var blocked: bool = not menu.can_pause()
	# "Continuar" del menu principal suelta la pausa, porque ahora es suya.
	title.close_menu()
	title.set_dismissed_for_tests(false)
	assert_bool(pause_closed).is_true()
	assert_bool(title_open).is_true()
	assert_bool(paused).is_true()
	assert_bool(blocked).is_true()
	assert_bool(get_tree().paused).is_false()

## Menu unico: el boton va siempre arriba a la derecha (donde estaba el ☰),
## con palabra y de tamano dedo, en PC, tablet y movil.
func test_the_menu_button_sits_top_right_and_is_finger_sized() -> void:
	var menu := _menu()
	var btn: Button = menu.menu_button()
	assert_float(btn.anchor_left).is_equal(1.0)
	assert_float(btn.anchor_top).is_equal(0.0)
	assert_float(btn.custom_minimum_size.y).is_greater_equal(float(UITheme.MIN_BTN_H))
	assert_str(btn.text).is_equal(Tr.t("BTN_GAME_MENU"))
