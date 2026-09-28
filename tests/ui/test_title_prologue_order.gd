extends GdUnitTestSuite
## El prologo nunca sale detras de otro menu (docs/07 bug 1): la intro vieja se
## abria con game_new_started aunque el menu principal estuviera encima, quedaba
## en la capa 17 congelada por la pausa y se comia los toques de Ajustes.
##
##   menu principal abierto  -> no hay prologo (queda pendiente)
##   Ajustes desde el menu   -> responde: nada suyo por encima
##   soltar el menu          -> el prologo sale, encima de todo
##
## Lo que pausa el arbol se deshace en el mismo test sin esperar frames (con el
## arbol en pausa el runner de gdUnit se pararia): el barrido de TutorialManager
## se llama a mano con _process.

var _saved: Dictionary = {}
var _loaded_saved := false

func before_test() -> void:
	_saved = TutorialManager.get_save_data()
	_loaded_saved = GameManager.loaded_from_save
	TutorialManager.reset()
	get_tree().paused = false

func after_test() -> void:
	get_tree().paused = false
	GameManager.loaded_from_save = _loaded_saved
	load("res://scripts/ui/TitleMenu.gd").set_dismissed_for_tests(false)
	TutorialManager.load_save_data(_saved)

func _scene() -> Dictionary:
	var tutorial: CanvasLayer = auto_free(load("res://scenes/ui/TutorialPanel.tscn").instantiate())
	add_child(tutorial)
	var settings: CanvasLayer = auto_free(load("res://scenes/ui/SettingsPanel.tscn").instantiate())
	add_child(settings)
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/TitleMenu.tscn").instantiate())
	add_child(menu)
	menu.set_dismissed_for_tests(false)
	return {"tutorial": tutorial, "settings": settings, "menu": menu}

func _scan() -> void:
	TutorialManager._process(0.2)

## La capa mas alta con algo visible, sin contar `except`.
func _top_visible_layer(except: Array = []) -> int:
	var top := -1000
	# Solo las de esta prueba: el runner de gdUnit tiene las suyas.
	for n in find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		if cl in except or not cl.visible:
			continue
		var has_visible := false
		for c in cl.get_children():
			if c is Control and (c as Control).visible:
				has_visible = true
				break
		if has_visible:
			top = maxi(top, cl.layer)
	return top

func test_no_prologue_while_the_title_menu_is_open() -> void:
	var s := _scene()
	s["menu"].open_menu()
	EventBus.game_new_started.emit()
	_scan()
	var open_behind: bool = s["tutorial"].is_intro_open()
	var pending: bool = TutorialManager.is_prologue_pending()
	s["menu"].close_menu()
	s["tutorial"]._close()
	assert_bool(open_behind).override_failure_message("el prologo se abrio detras del menu principal").is_false()
	assert_bool(pending).is_true()

func test_settings_from_the_title_menu_is_on_top_and_nothing_eats_its_touches() -> void:
	var s := _scene()
	var menu: CanvasLayer = s["menu"]
	var settings: CanvasLayer = s["settings"]
	menu.open_menu()
	EventBus.game_new_started.emit()
	_scan()
	menu._on_settings()
	_scan()
	var prologue_open: bool = s["tutorial"].is_intro_open()
	var settings_mode: int = settings.process_mode
	# Nada visible por encima de Ajustes salvo el propio menu, que esconde su
	# tarjeta mientras presta la pantalla.
	var above: int = _top_visible_layer([menu, settings])
	var settings_layer: int = settings.layer
	var menu_card_hidden: bool = not menu._card.visible
	settings.toggle()
	menu.close_menu()
	s["tutorial"]._close()
	assert_bool(prologue_open).is_false()
	assert_int(settings_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_bool(menu_card_hidden).is_true()
	assert_int(above).override_failure_message("algo visible por encima de Ajustes (capa %d)" % above).is_less(settings_layer)

func test_dismissing_the_menu_brings_the_prologue_on_top() -> void:
	var s := _scene()
	var menu: CanvasLayer = s["menu"]
	menu.open_menu()
	EventBus.game_new_started.emit()
	_scan()
	menu.close_menu()
	_scan()
	var prologue: CanvasLayer = s["tutorial"].prologue()
	var open_now: bool = prologue.is_open()
	var on_top: bool = prologue.layer > _top_visible_layer([prologue])
	var paused: bool = get_tree().paused
	prologue.close()
	assert_bool(open_now).is_true()
	assert_bool(on_top).is_true()
	assert_bool(paused).override_failure_message("el prologo tiene que parar el juego mientras se lee").is_true()
	assert_bool(get_tree().paused).is_false()
	assert_bool(TutorialManager.intro_seen).is_true()

func test_the_pause_menu_also_holds_it_back() -> void:
	var s := _scene()
	EventBus.game_new_started.emit()
	get_tree().paused = true
	_scan()
	var open_paused: bool = s["tutorial"].is_intro_open()
	get_tree().paused = false
	_scan()
	var open_after: bool = s["tutorial"].is_intro_open()
	s["tutorial"]._close()
	assert_bool(open_paused).is_false()
	assert_bool(open_after).is_true()
