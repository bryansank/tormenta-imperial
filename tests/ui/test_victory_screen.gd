extends GdUnitTestSuite
## La pantalla de victoria: "Nueva partida" pide confirmacion como en Ajustes
## (antes borraba la partida al primer clic), y nunca se abre encima del parte
## de progreso offline, que comparte con ella la capa 20.

const STATS := {"time_played": 3700.0, "buildings_built": 30, "trades_completed": 12, "milestones": 9}

func after_test() -> void:
	GameManager._offline_canvas = null
	for child in GameManager.get_children():
		if child is ConfirmationDialog:
			child.queue_free()

func _screen() -> CanvasLayer:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/VictoryScreen.tscn").instantiate())
	add_child(screen)
	return screen

func _dialogs() -> Array:
	var found: Array = []
	for child in GameManager.get_children():
		if child is ConfirmationDialog and not child.is_queued_for_deletion():
			found.append(child)
	return found

func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var hit := _find_button(child, text)
		if hit != null:
			return hit
	return null

func test_new_game_asks_before_wiping_the_save() -> void:
	var screen := _screen()
	screen._on_victory_achieved(STATS)
	var btn := _find_button(screen, Tr.t("BTN_NEW_GAME"))
	assert_object(btn).is_not_null()
	btn.pressed.emit()
	# Solo el dialogo: nada se ha borrado todavia.
	assert_int(_dialogs().size()).is_equal(1)

func test_it_waits_for_the_offline_report_to_close() -> void:
	var fake: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(fake)
	GameManager._offline_canvas = fake
	var screen := _screen()
	screen._on_victory_achieved(STATS)
	assert_bool(screen.is_showing()).is_false()
	GameManager._offline_canvas = null
	GameManager.offline_report_closed.emit()
	assert_bool(screen.is_showing()).is_true()

func test_without_an_offline_report_it_opens_at_once() -> void:
	var screen := _screen()
	screen._on_victory_achieved(STATS)
	assert_bool(screen.is_showing()).is_true()
