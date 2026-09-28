extends GdUnitTestSuite
## El menu unico de la partida (bugs 3 y 9 del diagnostico de jugabilidad):
## un solo boton "☰ MENU" que SIEMPRE abre (cierra ventanas y suelta el
## edificio antes), pausa, y ofrece COLONIA (paneles del juego, solo los
## disponibles) y PARTIDA (reanudar, guardar, ajustes, ayuda, historia, menu
## principal, salir). Elegir algo de COLONIA cierra el menu, quita la pausa y
## abre ese panel.
##
## Cada test que pausa el arbol lo suelta antes de esperar un frame.

const MenuScript := preload("res://scripts/ui/PauseMenu.gd")

var _root: Node
var _saved_phase: int
var _saved_mode: int
var _saved_units: Dictionary

func before_test() -> void:
	get_tree().paused = false
	_saved_phase = ProgressionManager.current_phase
	_saved_mode = GameMode.current
	_saved_units = ArmyManager._units.duplicate()
	_root = Node.new()
	_root.name = "FakeMain"
	add_child(_root)

func after_test() -> void:
	get_tree().paused = false
	ProgressionManager.current_phase = _saved_phase
	GameMode.current = _saved_mode
	if is_instance_valid(_root):
		_root.free()
	UIManager.reset()

func _add(scene: String, node_name: String) -> Node:
	var n: Node = load(scene).instantiate()
	n.name = node_name
	_root.add_child(n)
	return n

func _menu() -> CanvasLayer:
	return _add("res://scenes/ui/PauseMenu.tscn", "PauseMenu") as CanvasLayer

## Una ventana de UIManager de mentira (el panel de edificio, por ejemplo).
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

# ── Un solo menu ─────────────────────────────────────────────────────

func test_there_is_one_menu_button_and_no_pause_ii() -> void:
	var menu := _menu()
	var buttons: Array = menu.find_children("*", "Button", true, false).filter(
		func(b): return (b as Button).is_visible_in_tree())
	assert_int(buttons.size()).is_equal(1)
	var btn: Button = buttons[0]
	assert_str(btn.text).is_equal(Tr.t("BTN_GAME_MENU"))
	assert_str(btn.text).is_not_equal("II")

func test_the_market_panel_no_longer_has_its_own_burger() -> void:
	var market := _add("res://scenes/ui/MarketPanel.tscn", "MarketPanel")
	for b in market.find_children("*", "Button", true, false):
		assert_str((b as Button).text).is_not_equal("☰")

func test_the_menu_shows_both_groups_and_the_mode() -> void:
	var menu := _menu()
	GameMode.current = GameMode.Mode.BUILDER
	menu.open_pause()
	var mode_text: String = (menu.find_child("ModeLabel", true, false) as Label).text
	var colony: bool = menu.find_child("ColonyGroup", true, false) != null
	var game: bool = menu.find_child("GameGroup", true, false) != null
	menu.resume()
	assert_bool(colony).is_true()
	assert_bool(game).is_true()
	assert_str(mode_text).contains(GameMode.display_name())
	for id in ["Game_Resume", "Game_Save", "Game_Settings", "Game_Story", "Game_MainMenu", "Game_Quit"]:
		assert_object(menu.entry(id)).override_failure_message(id).is_not_null()

# ── El boton nunca falla en silencio (bug 3) ──────────────────────────

func test_the_button_opens_even_with_a_window_open() -> void:
	var menu := _menu()
	var w := _window()
	w.open()
	assert_bool(UIManager.is_any_window_open()).is_true()
	menu.menu_button().pressed.emit()
	var open: bool = menu.is_open()
	var paused: bool = get_tree().paused
	var windows: bool = UIManager.is_any_window_open()
	menu.resume()
	assert_bool(open).is_true()
	assert_bool(paused).is_true()
	assert_bool(windows).is_false()
	assert_bool(w.get("_is_open")).is_false()

func test_the_button_drops_the_building_in_hand_and_opens() -> void:
	var menu := _menu()
	_placer(false)
	var monitor := monitor_signals(EventBus, false)
	menu.menu_button().pressed.emit()
	var open: bool = menu.is_open()
	menu.resume()
	assert_bool(open).is_true()
	await assert_signal(monitor).is_emitted("building_placement_cancelled")

func test_escape_still_belongs_to_an_open_window_first() -> void:
	var menu := _menu()
	var w := _window()
	w.open()
	assert_bool(menu.can_pause()).is_false()
	w._toggle_panel()
	assert_bool(menu.can_pause()).is_true()

func test_the_button_again_closes_and_resumes() -> void:
	var menu := _menu()
	menu.menu_button().pressed.emit()
	menu.request_open()
	assert_bool(menu.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()

# ── COLONIA ──────────────────────────────────────────────────────────

func test_a_colony_entry_closes_the_menu_unpauses_and_opens_the_panel() -> void:
	var menu := _menu()
	var objectives := _add("res://scenes/ui/ObjectivePanel.tscn", "ObjectivePanel")
	menu.open_pause()
	menu.entry("Colony_objectives").pressed.emit()
	var opened: bool = objectives.get("_is_open")
	assert_bool(menu.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_bool(opened).is_true()
	objectives.toggle()

func test_colony_entries_only_show_what_is_available() -> void:
	var menu := _menu()
	for n in ["ObjectivePanel", "MarketPanel", "ArmyPanel", "SandboxPanel"]:
		var stub := CanvasLayer.new()
		stub.name = n
		_root.add_child(stub)
	ProgressionManager.current_phase = GameConfig.Phase.FOUNDATION
	GameMode.current = GameMode.Mode.CAMPAIGN
	menu.open_pause()
	var market_early: bool = menu.entry("Colony_market").visible
	var sandbox_campaign: bool = menu.entry("Colony_sandbox").visible
	var objectives: bool = menu.entry("Colony_objectives").visible
	var tech_missing: bool = menu.entry("Colony_tech").visible   # no hay TechTreePanel
	menu.resume()
	ProgressionManager.current_phase = GameConfig.Phase.ECONOMY
	GameMode.current = GameMode.Mode.SANDBOX
	menu.open_pause()
	var market_later: bool = menu.entry("Colony_market").visible
	var sandbox_mode: bool = menu.entry("Colony_sandbox").visible
	menu.resume()
	assert_bool(objectives).is_true()
	assert_bool(market_early).is_false()
	assert_bool(market_later).is_true()
	assert_bool(sandbox_campaign).is_false()
	assert_bool(sandbox_mode).is_true()
	assert_bool(tech_missing).is_false()

func test_army_needs_a_barracks() -> void:
	assert_bool(MenuScript.is_colony_entry_available("army")).is_equal(ArmyManager.barracks_count() > 0)
	assert_bool(MenuScript.is_colony_entry_available("skirmish")).is_equal(ArmyManager.barracks_count() > 0)

# ── AYUDA (contrato con el frente de ayudas) ──────────────────────────

func test_help_is_hidden_without_the_help_index() -> void:
	var menu := _menu()
	menu.open_pause()
	var shown: bool = menu.entry("Game_Help").visible
	menu.resume()
	assert_bool(shown).is_false()

func test_help_opens_the_help_index() -> void:
	var script := GDScript.new()
	script.source_code = "extends CanvasLayer\nvar opened := 0\nfunc open():\n\topened += 1\nfunc is_open() -> bool:\n\treturn opened > 0\n"
	script.reload()
	var help := CanvasLayer.new()
	help.set_script(script)
	help.name = "HelpIndexPanel"
	help.add_to_group("help_index")
	_root.add_child(help)
	var menu := _menu()
	menu.open_pause()
	var shown: bool = menu.entry("Game_Help").visible
	menu.entry("Game_Help").pressed.emit()
	var opened: int = help.get("opened")
	var layer: int = help.layer
	menu.resume()
	assert_bool(shown).is_true()
	assert_int(opened).is_equal(1)
	assert_int(layer).is_greater(menu.layer)

# ── ESC y atras de Android ────────────────────────────────────────────

func test_android_back_does_not_quit_the_app() -> void:
	assert_bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)).is_false()

func test_escape_opens_and_closes() -> void:
	var menu := _menu()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	menu._unhandled_input(esc)
	var open: bool = menu.is_open()
	menu._unhandled_input(esc)
	assert_bool(open).is_true()
	assert_bool(menu.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()

# ── Ganchos del tutorial guiado (frente de ayudas) ────────────────────

func test_the_menu_button_is_in_its_hook_group() -> void:
	var menu := _menu()
	assert_bool(menu.menu_button().is_in_group("hud_menu_button")).is_true()

func test_the_build_button_is_in_its_hook_group() -> void:
	var build := _add("res://scenes/ui/ConstructionMenu.tscn", "ConstructionMenu")
	assert_bool(build.build_button().is_in_group("hud_build_button")).is_true()
