extends GdUnitTestSuite
## Los autoloads sobreviven a la recarga de escena; los nodos de la escena, no.
##
## ProductionManager y UIManager guardan nodos de la escena como clave. Tras
## "Partida nueva" (clear_save recarga la escena) esas claves apuntan a objetos
## liberados. Antes: ProductionManager pasaba el nodo liberado a un parametro
## tipado, la llamada reventaba antes de borrarlo y el mismo error se repetia cada
## fotograma; UIManager reasignaba `layer` a un CanvasLayer muerto.

var _saved_constructing: Dictionary = {}
var _saved_producing: Dictionary = {}
var _saved_stack: Array = []
var _saved_ids: Dictionary = {}

func before_test() -> void:
	_saved_constructing = ProductionManager._constructing.duplicate()
	_saved_producing = ProductionManager._producing.duplicate()
	ProductionManager._constructing.clear()
	ProductionManager._producing.clear()
	_saved_stack = (UIManager._window_stack as Array).duplicate()
	_saved_ids = UIManager._panel_ids.duplicate()
	UIManager.reset()

func after_test() -> void:
	ProductionManager._constructing = _saved_constructing
	ProductionManager._producing = _saved_producing
	UIManager.reset()
	for w in _saved_stack:
		if is_instance_valid(w):
			UIManager._window_stack.append(w)
	for k in _saved_ids:
		if is_instance_valid(k):
			UIManager._panel_ids[k] = _saved_ids[k]

func _building() -> Node3D:
	var node := Node3D.new()
	var mesh := MeshInstance3D.new()
	node.add_child(mesh)
	add_child(node)
	return node

# ── ProductionManager ────────────────────────────────────────────────

func test_a_freed_node_under_construction_is_dropped_on_the_next_tick() -> void:
	var node := _building()
	ProductionManager._constructing[node] = {"remaining": 5.0, "duration": 5.0}
	node.free()
	ProductionManager._tick_construction(0.1)
	assert_int(ProductionManager._constructing.size()).override_failure_message(
		"el nodo liberado sigue en _constructing: el error se repetiria cada fotograma"
	).is_equal(0)

func test_completing_a_freed_node_erases_it_instead_of_failing() -> void:
	var node := _building()
	ProductionManager._constructing[node] = {"remaining": 0.0, "duration": 5.0}
	node.free()
	var stale = ProductionManager._constructing.keys()[0]
	ProductionManager._complete_construction(stale)
	assert_int(ProductionManager._constructing.size()).is_equal(0)

func test_reset_forgets_every_building() -> void:
	var a := _building()
	var b := _building()
	ProductionManager._constructing[a] = {"remaining": 5.0, "duration": 5.0}
	ProductionManager._producing[b] = {"timer": 0.0, "data": null}
	ProductionManager.reset()
	assert_int(ProductionManager._constructing.size()).is_equal(0)
	assert_int(ProductionManager._producing.size()).is_equal(0)
	a.free()
	b.free()

func test_every_fresh_game_path_resets_production() -> void:
	# Las tres listas duplicadas de GameManager: si una se olvida del reset, la
	# partida nueva hereda obras de la vieja. Se comprueba en el propio codigo.
	var src: String = FileAccess.get_file_as_string("res://scripts/services/GameManager.gd")
	for fn in ["func _new_game", "func clear_save()", "func clear_save_and_reload_from"]:
		var start: int = src.find(fn)
		assert_int(start).is_greater(-1)
		var end: int = src.find("\nfunc ", start + 1)
		var body: String = src.substr(start, end - start)
		assert_bool(body.contains("ProductionManager.reset()")).override_failure_message(
			"%s no llama a ProductionManager.reset()" % fn).is_true()

# ── UIManager ────────────────────────────────────────────────────────

func test_a_freed_panel_does_not_break_the_window_stack() -> void:
	var dead := CanvasLayer.new()
	add_child(dead)
	UIManager.register_panel(dead, "ArmyPanel.modal")
	UIManager.open_window(dead)
	dead.free()

	var alive := CanvasLayer.new()
	add_child(alive)
	UIManager.register_panel(alive, "SkirmishPanel.modal")
	UIManager.open_panel(alive)

	assert_int(UIManager._window_stack.size()).is_equal(1)
	assert_int(UIManager._panel_ids.size()).is_equal(1)
	assert_int(alive.layer).is_equal(UIManager._base_layer + 1)
	UIManager.close_window(alive)
	assert_bool(UIManager.is_any_window_open()).is_false()
	alive.free()

func test_reset_empties_the_stack_and_the_registry() -> void:
	var panel := CanvasLayer.new()
	add_child(panel)
	UIManager.register_panel(panel, "ArmyPanel.modal")
	UIManager.open_window(panel)
	UIManager.reset()
	assert_bool(UIManager.is_any_window_open()).is_false()
	assert_int(UIManager._panel_ids.size()).is_equal(0)
	panel.free()
