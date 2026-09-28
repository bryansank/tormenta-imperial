extends GdUnitTestSuite
## La pantalla de victoria: "Nueva partida" pide confirmacion como en Ajustes
## (antes borraba la partida al primer clic), y nunca se abre encima del parte
## de progreso offline, que comparte con ella la capa 20.

const NewGameDialogScript := preload("res://scripts/ui/NewGameDialog.gd")

const STATS := {"time_played": 3700.0, "buildings_built": 30, "trades_completed": 12, "milestones": 9}

func after_test() -> void:
	GameManager._offline_canvas = null
	for child in GameManager.get_children():
		if child.get_script() == NewGameDialogScript:
			child.queue_free()

func _screen() -> CanvasLayer:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/VictoryScreen.tscn").instantiate())
	add_child(screen)
	return screen

func _dialogs() -> Array:
	var found: Array = []
	for child in GameManager.get_children():
		if child.get_script() == NewGameDialogScript and not child.is_queued_for_deletion():
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

## El tiempo jugado es el de partida, no la hora de la pared desde que se creo:
## una campana de tres horas repartida en una semana no son siete dias jugados.
## Y la pantalla cuenta lo que la partida fue: tormentas, Diezmos echados, asedios.
func test_victory_stats_count_played_time_and_the_storms() -> void:
	var saved: Dictionary = ProgressionManager.get_save_data()
	var saved_audit = ProgressionManager.final_audit
	var got: Array = []
	var probe := func(stats: Dictionary) -> void: got.append(stats)
	EventBus.victory_achieved.connect(probe)
	ProgressionManager.reset()
	ProgressionManager._start_time = Time.get_unix_time_from_system() - 7 * 24 * 3600.0
	ProgressionManager._played_seconds = 3 * 3600.0
	ProgressionManager._trigger_victory()
	EventBus.victory_achieved.disconnect(probe)
	ProgressionManager.load_save_data(saved)
	ProgressionManager.final_audit = saved_audit
	assert_int(got.size()).is_equal(1)
	assert_float(float(got[0]["time_played"])).is_equal(3 * 3600.0)
	for key in ["storms_survived", "tithes_repelled", "audit_summons"]:
		assert_bool(got[0].has(key)).override_failure_message("faltan '%s' en la victoria" % key).is_true()
	# Y el tiempo jugado viaja en el guardado.
	ProgressionManager._played_seconds = 1234.0
	var round_trip: Dictionary = ProgressionManager.get_save_data()
	assert_float(float(round_trip["played_seconds"])).is_equal(1234.0)
	ProgressionManager.load_save_data(saved)

func test_the_victory_screen_shows_the_storm_count() -> void:
	var screen := _screen()
	screen._on_victory_achieved(STATS.merged({"storms_survived": 11, "tithes_repelled": 9, "audit_summons": 2}))
	assert_bool(_has_label(screen, Tr.t("LBL_STAT_STORMS"))).is_true()
	assert_bool(_has_label(screen, Tr.t("LBL_VICTORY_SUBTITLE_AUDIT"))).is_true()

func _has_label(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for child in node.get_children():
		if _has_label(child, text):
			return true
	return false

func test_without_an_offline_report_it_opens_at_once() -> void:
	var screen := _screen()
	screen._on_victory_achieved(STATS)
	assert_bool(screen.is_showing()).is_true()
