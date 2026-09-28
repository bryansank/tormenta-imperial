extends GdUnitTestSuite
## El menu principal: sale sobre la partida con el arbol en pausa, ofrece
## "Continuar" solo cuando hay algo que continuar, pide confirmacion antes de
## borrar una partida y presta el panel de Ajustes sin que la pausa lo congele.
##
## Todo lo que pausa el arbol se deshace en el mismo test, sin esperar frames:
## con el arbol en pausa el propio runner de gdUnit se pararia.

var _loaded_saved := false

func before_test() -> void:
	_loaded_saved = GameManager.loaded_from_save
	get_tree().paused = false

func after_test() -> void:
	get_tree().paused = false
	GameManager.loaded_from_save = _loaded_saved
	load("res://scripts/ui/TitleMenu.gd").set_dismissed_for_tests(false)
	for child in GameManager.get_children():
		if child is ConfirmationDialog:
			child.queue_free()

func _menu() -> CanvasLayer:
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/TitleMenu.tscn").instantiate())
	add_child(menu)
	menu.set_dismissed_for_tests(false)
	return menu

func test_it_does_not_open_by_itself_without_a_window() -> void:
	# Headless (tests, exportaciones de servidor): pausaria el arbol de las pruebas.
	var menu := _menu()
	assert_bool(menu.should_show_on_launch()).is_false()
	assert_bool(menu.visible).is_false()
	assert_bool(get_tree().paused).is_false()

func test_it_keeps_working_while_the_tree_is_paused() -> void:
	var menu := _menu()
	assert_int(menu.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)

func test_opening_pauses_the_game_and_closing_releases_it() -> void:
	var menu := _menu()
	menu.open_menu()
	var paused_while_open: bool = get_tree().paused
	var visible_while_open: bool = menu.visible
	menu.close_menu()
	assert_bool(paused_while_open).is_true()
	assert_bool(visible_while_open).is_true()
	assert_bool(get_tree().paused).is_false()
	assert_bool(menu.visible).is_false()

func test_it_does_not_release_a_pause_it_did_not_take() -> void:
	# Desde el menu de pausa el arbol ya esta parado: cerrar este menu no puede
	# soltar la pausa de otro.
	var menu := _menu()
	get_tree().paused = true
	menu.open_menu()
	menu.close_menu()
	var still_paused: bool = get_tree().paused
	get_tree().paused = false
	assert_bool(still_paused).is_true()

func test_continue_is_offered_only_with_a_game_to_continue() -> void:
	var menu := _menu()
	GameManager.loaded_from_save = false
	menu.open_menu()
	var fresh_offers: bool = menu._continue_btn.visible
	menu.close_menu()
	# Tras jugar un rato en esta sesion (se cerro el menu), si hay que continuar.
	menu.open_menu()
	var after_playing: bool = menu._continue_btn.visible
	menu.close_menu()
	assert_bool(fresh_offers).is_false()
	assert_bool(after_playing).is_true()

func test_continue_is_offered_after_loading_a_save() -> void:
	var menu := _menu()
	GameManager.loaded_from_save = true
	menu.open_menu()
	var offered: bool = menu._continue_btn.visible
	menu.close_menu()
	assert_bool(offered).is_true()

func test_a_brand_new_island_starts_without_asking() -> void:
	# No habia partida: la nueva ya esta montada detras, no hay nada que borrar.
	var menu := _menu()
	GameManager.loaded_from_save = false
	menu.open_menu()
	menu._on_new_game()
	var dialogs := _dialogs()
	assert_bool(menu.visible).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_int(dialogs.size()).is_equal(0)

func test_new_game_over_a_save_asks_for_confirmation_first() -> void:
	var menu := _menu()
	GameManager.loaded_from_save = true
	menu.open_menu()
	menu._on_new_game()
	var dialogs := _dialogs()
	var still_open: bool = menu.visible
	menu.close_menu()
	assert_int(dialogs.size()).is_equal(1)
	# El dialogo tiene que poder pulsarse con el arbol en pausa.
	assert_int(dialogs[0].process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_bool(still_open).is_true()

func test_settings_open_over_the_menu_and_give_it_back_on_close() -> void:
	var settings: CanvasLayer = auto_free(load("res://scenes/ui/SettingsPanel.tscn").instantiate())
	add_child(settings)
	var menu := _menu()
	menu.open_menu()
	menu._on_settings()
	var settings_mode: int = settings.process_mode
	var menu_hidden: bool = not menu._root.visible
	settings.toggle()  # cerrar Ajustes
	var menu_back: bool = menu._root.visible
	var restored: int = settings.process_mode
	menu.close_menu()
	assert_int(settings_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_bool(menu_hidden).is_true()
	assert_bool(menu_back).is_true()
	assert_int(restored).is_equal(Node.PROCESS_MODE_INHERIT)

## Cambiar de vista (GameManager.switch_to_scene) monta la otra escena con su
## propio TitleMenu. Que el menu ya se solto en esta sesion no puede depender de
## que el script siga cargado: una copia nueva del script (lo que queda si el
## motor lo descarga entre escenas) tiene que seguir sabiendolo.
func test_the_dismissal_outlives_the_scene_and_its_script() -> void:
	var menu := _menu()
	menu.open_menu()
	menu._on_continue()
	var fresh := GDScript.new()
	fresh.source_code = load("res://scripts/ui/TitleMenu.gd").source_code
	fresh.reload()
	var other: CanvasLayer = auto_free(CanvasLayer.new())
	other.set_script(fresh)
	# Sin partida cargada, "Continuar" solo sale si el menu ya se solto.
	GameManager.loaded_from_save = false
	assert_bool(other.has_game_to_continue()).override_failure_message(
		"la otra escena olvido que el menu ya se habia soltado").is_true()

func test_a_menu_never_dismissed_is_not_taken_as_dismissed() -> void:
	var fresh := GDScript.new()
	fresh.source_code = load("res://scripts/ui/TitleMenu.gd").source_code
	fresh.reload()
	var other: CanvasLayer = auto_free(CanvasLayer.new())
	other.set_script(fresh)
	GameManager.loaded_from_save = false
	assert_bool(other.has_game_to_continue()).is_false()

func _dialogs() -> Array:
	var found: Array = []
	for child in GameManager.get_children():
		if child is ConfirmationDialog and not child.is_queued_for_deletion():
			found.append(child)
	return found
