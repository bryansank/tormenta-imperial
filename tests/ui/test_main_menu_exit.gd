extends GdUnitTestSuite
## Bug 3: "cuando ya entro a jugar, no me deja salir al menu principal". El
## boton II no hacia nada, sin avisar, con cualquier ventana abierta (el panel
## de edificio sale con cada toque en el mapa) o con un edificio en la mano, y
## el ☰ no tenia "Menu principal".
##
## Ahora: ☰ MENU -> Menu principal vuelve al menu del titulo SIEMPRE, en todos
## los modos, con lo que haya abierto. Y en las dos vistas: las dos escenas
## montan el mismo menu, con los mismos hermanos (se comprueba en su estado
## empaquetado, sin instanciar la partida entera).

var _root: Node
var _saved_mode: int

func before_test() -> void:
	get_tree().paused = false
	_saved_mode = GameMode.current
	_root = Node.new()
	_root.name = "FakeMain"
	add_child(_root)

func after_test() -> void:
	get_tree().paused = false
	GameMode.current = _saved_mode
	if is_instance_valid(_root):
		var title: Node = _root.get_node_or_null("TitleMenu")
		if title != null and title.is_open():
			title.close_menu()
		_root.free()
	UIManager.reset()
	load("res://scripts/ui/TitleMenu.gd").set_dismissed_for_tests(true)

func _add(scene: String, node_name: String) -> Node:
	var n: Node = load(scene).instantiate()
	n.name = node_name
	_root.add_child(n)
	return n

func _window() -> CanvasLayer:
	var script := GDScript.new()
	script.source_code = "extends CanvasLayer\nvar _is_open := false\nfunc open():\n\t_is_open = true\n\tUIManager.open_panel(self)\nfunc _toggle_panel():\n\t_is_open = not _is_open\n\tif _is_open:\n\t\tUIManager.open_panel(self)\n\telse:\n\t\tUIManager.close_panel(self)\n"
	script.reload()
	var w := CanvasLayer.new()
	w.set_script(script)
	w.name = "BuildingInfoPanel"
	_root.add_child(w)
	return w

func _placer(idle: bool) -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar idle := true\nfunc is_idle() -> bool:\n\treturn idle\n"
	script.reload()
	var node := Node.new()
	node.set_script(script)
	node.name = "BuildingPlacer"
	node.set("idle", idle)
	_root.add_child(node)
	return node

## Pulsa ☰ MENU y luego "Menu principal". Devuelve [titulo abierto, menu
## abierto, arbol en pausa, ventanas abiertas].
func _exit_to_title() -> Array:
	var menu: CanvasLayer = _root.get_node("PauseMenu")
	var title: CanvasLayer = _root.get_node("TitleMenu")
	menu.menu_button().pressed.emit()
	menu.entry("Game_MainMenu").pressed.emit()
	var out := [title.is_open(), menu.is_open(), get_tree().paused, UIManager.is_any_window_open()]
	title.close_menu()
	return out

func _setup() -> void:
	_add("res://scenes/ui/PauseMenu.tscn", "PauseMenu")
	_add("res://scenes/ui/TitleMenu.tscn", "TitleMenu")

func test_main_menu_from_plain_play() -> void:
	_setup()
	var r := _exit_to_title()
	assert_bool(r[0]).is_true()
	assert_bool(r[1]).is_false()
	assert_bool(r[2]).is_true()
	assert_bool(get_tree().paused).is_false()

func test_main_menu_with_a_building_panel_open() -> void:
	_setup()
	var w := _window()
	w.open()
	var r := _exit_to_title()
	assert_bool(r[0]).is_true()
	assert_bool(r[3]).is_false()

func test_main_menu_while_placing_a_building() -> void:
	_setup()
	_placer(false)
	var monitor := monitor_signals(EventBus, false)
	var r := _exit_to_title()
	assert_bool(r[0]).is_true()
	await assert_signal(monitor).is_emitted("building_placement_cancelled")

func test_main_menu_in_every_mode() -> void:
	_setup()
	for mode in GameMode.ORDER:
		GameMode.current = mode
		var r := _exit_to_title()
		assert_bool(r[0]).override_failure_message("modo %s" % GameMode.key_of(mode)).is_true()
		assert_bool(get_tree().paused).is_false()

## El menu principal que sale se puede volver a dejar con Continuar, y el
## menu de la partida vuelve a funcionar despues.
func test_continue_brings_the_game_menu_back() -> void:
	_setup()
	_exit_to_title()
	var menu: CanvasLayer = _root.get_node("PauseMenu")
	menu.menu_button().pressed.emit()
	var reopened: bool = menu.is_open()
	menu.resume()
	assert_bool(reopened).is_true()

func _scene_nodes(path: String) -> Array:
	var state := (load(path) as PackedScene).get_state()
	var names: Array = []
	# Hijos directos de la raiz: su padre es ".".
	for i in state.get_node_count():
		if String(state.get_node_path(i, true)) == ".":
			names.append(String(state.get_node_name(i)))
	return names

func test_both_views_mount_the_same_menus() -> void:
	for path in ["res://scenes/main/Main.tscn", "res://scenes/main/Main2D.tscn"]:
		var names := _scene_nodes(path)
		for n in ["PauseMenu", "TitleMenu", "SettingsPanel", "TutorialPanel", "BuildingPlacer",
				"ConstructionMenu", "ObjectivePanel", "MarketPanel", "TechTreePanel", "ArmyPanel"]:
			assert_bool(names.has(n)).override_failure_message("%s sin %s" % [path, n]).is_true()
