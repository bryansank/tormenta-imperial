extends GdUnitTestSuite
## La pantalla de victoria: "Nueva partida" abre el selector de modo (antes
## borraba la partida al primer clic; hoy ya no borra nada, crea otra) y la
## pantalla se abre en el acto (el parte offline ya no existe).

const NewGameDialogScript := preload("res://scripts/ui/NewGameDialog.gd")

const STATS := {"time_played": 3700.0, "buildings_built": 30, "trades_completed": 12, "milestones": 9}

func after_test() -> void:
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

func test_new_game_opens_the_mode_picker() -> void:
	var screen := _screen()
	screen._on_victory_achieved(STATS)
	var btn := _find_button(screen, Tr.t("BTN_NEW_GAME"))
	assert_object(btn).is_not_null()
	btn.pressed.emit()
	# Solo el selector: nada se ha creado ni borrado todavia.
	assert_int(_dialogs().size()).is_equal(1)

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
	# Volverse el Imperio: en Campana (y Supervivencia) el subtitulo es el del
	# archipielago; sin la fase, el del asedio de siempre.
	var subtitle_key: String = "LBL_VICTORY_SUBTITLE_EMPIRE" if GameMode.empire_enabled() else "LBL_VICTORY_SUBTITLE_AUDIT"
	assert_bool(_has_label(screen, Tr.t(subtitle_key))).is_true()

## Constructor gana sin Tormenta, sin Diezmo y sin asedio: esas filas no salen.
func test_the_builder_victory_does_not_count_storms() -> void:
	var saved_mode: int = GameMode.current
	var saved_result: String = GameMode.run_result
	GameMode.begin_run(GameMode.Mode.BUILDER)
	var screen := _screen()
	screen._on_victory_achieved(STATS.merged({"mode": "builder"}))
	GameMode.current = saved_mode
	GameMode.run_result = saved_result
	assert_bool(_has_label(screen, Tr.t("LBL_VICTORY_SUBTITLE_BUILDER"))).is_true()
	assert_bool(_has_label(screen, Tr.t("LBL_STAT_STORMS"))).is_false()
	assert_bool(_has_label(screen, Tr.t("LBL_VICTORY_CODA"))).is_false()

func _has_label(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for child in node.get_children():
		if _has_label(child, text):
			return true
	return false

func test_it_opens_at_once() -> void:
	var screen := _screen()
	screen._on_victory_achieved(STATS)
	assert_bool(screen.is_showing()).is_true()

# ── Volverse el Imperio (feat/volverse-imperio) ──────────────────────

## En Campana la victoria dice "Ahora el Imperio eres tu" y lleva el boton del
## archipielago; en Constructor, no.
func test_the_campaign_victory_is_now_the_empire() -> void:
	var saved_mode: int = GameMode.current
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	var screen := _screen()
	screen._on_victory_achieved(STATS)
	GameMode.current = saved_mode
	assert_bool(_has_label(screen, Tr.t("LBL_VICTORY_TITLE_EMPIRE"))).is_true()
	assert_bool(_has_label(screen, Tr.t("LBL_VICTORY_CODA_EMPIRE"))).is_true()
	assert_object(screen.find_child("ArchipelagoButton", true, false)).is_not_null()

func test_the_builder_victory_has_no_archipelago() -> void:
	var saved_mode: int = GameMode.current
	GameMode.begin_run(GameMode.Mode.BUILDER)
	var screen := _screen()
	screen._on_victory_achieved(STATS.merged({"mode": "builder"}))
	GameMode.current = saved_mode
	assert_object(screen.find_child("ArchipelagoButton", true, false)).is_null()

## La pantalla monta el ArchipelagoPanel como hermano (asi ☰ MENU lo encuentra).
func test_the_victory_screen_mounts_the_archipelago_panel() -> void:
	var holder: Node = auto_free(Node.new())
	add_child(holder)
	var screen: CanvasLayer = load("res://scenes/ui/VictoryScreen.tscn").instantiate()
	holder.add_child(screen)
	await await_idle_frame()
	assert_object(holder.get_node_or_null("ArchipelagoPanel")).is_not_null()
