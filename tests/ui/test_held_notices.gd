extends GdUnitTestSuite
## Los avisos de la colonia esperan a que termine el combate (2026-10-14,
## docs/15 §1 "Layer 3"): con un tablero abierto (pelea o parte) los avisos de
## NotificationPanel (y con ellos hitos, eras y ascensos, que desde 2026-10-18
## son avisos "achievement") no salen; van al registro y aparecen al cerrarse
## el tablero (EventBus.encounter_closed). Solo uno de peligro se ve, pequeno.
## Si en esa misma llamada se abre otro tablero, siguen esperando.

func before_test() -> void:
	CombatManager.reset()

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()

func _notifications() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/NotificationPanel.tscn").instantiate())
	add_child(panel)
	return panel

func _open_board() -> void:
	var units: Array = [CombatUnit.create(701, "infantry", Encounter.PLAYER)]
	CombatManager.start_encounter_with_units(units, {"infantry": 1})
	assert_bool(CombatManager.is_board_open()).is_true()

func _alive_toasts(panel) -> int:
	return panel.shown_toasts().size()

func test_toasts_wait_for_the_board_to_close_but_reach_the_log_at_once() -> void:
	var panel := _notifications()
	await await_idle_frame()
	_open_board()
	var before := _alive_toasts(panel)
	var log_before: int = panel._log_entries.size()
	EventBus.notification_posted.emit("Sin madera", "warning", UITheme.WARNING)
	assert_int(_alive_toasts(panel)).is_equal(before)
	assert_int(panel.held_count()).is_equal(1)
	assert_int(panel._log_entries.size()).is_equal(log_before + 1)
	CombatManager.end_encounter()
	assert_bool(CombatManager.is_board_open()).is_false()
	assert_int(panel.held_count()).is_equal(0)
	assert_int(_alive_toasts(panel)).is_equal(before + 1)

func test_without_a_board_toasts_show_at_once() -> void:
	var panel := _notifications()
	await await_idle_frame()
	var before := _alive_toasts(panel)
	EventBus.notification_posted.emit("Sin madera", "warning", UITheme.WARNING)
	assert_int(_alive_toasts(panel)).is_equal(before + 1)
	assert_int(panel.held_count()).is_equal(0)

func test_many_held_notices_collapse_into_a_count() -> void:
	var panel := _notifications()
	await await_idle_frame()
	_open_board()
	for i in 7:
		EventBus.notification_posted.emit("Aviso %d" % i, "warning", UITheme.WARNING)
	# Nada en pantalla; la cola no crece sin fin: lo de mas, en un resumen.
	assert_int(_alive_toasts(panel)).is_equal(0)
	assert_int(panel.held_count()).is_equal(7)
	assert_int(panel.alerts().waiting.size()).is_less_equal(panel.alerts().MAX_WAITING)
	CombatManager.end_encounter()
	assert_int(_alive_toasts(panel)).is_less_equal(panel.capacity())
	assert_int(_alive_toasts(panel)).is_greater(0)

func test_one_danger_shows_small_during_the_fight() -> void:
	var panel := _notifications()
	await await_idle_frame()
	_open_board()
	EventBus.notification_posted.emit("Sin madera", "warning", UITheme.WARNING)
	EventBus.notification_posted.emit("¡La ceniza llega!", "danger", UITheme.DANGER)
	EventBus.notification_posted.emit("¡Otra cosa arde!", "danger", UITheme.DANGER)
	assert_int(_alive_toasts(panel)).is_equal(1)
	var text: Label = panel.shown_toasts()[0].find_child("Text", true, false)
	assert_str(text.text).is_equal("¡La ceniza llega!")
	# Pequeno: una linea.
	assert_int(text.max_lines_visible).is_equal(1)

func test_a_new_game_drops_what_was_held() -> void:
	var panel := _notifications()
	await await_idle_frame()
	_open_board()
	EventBus.notification_posted.emit("De la partida vieja", "warning", UITheme.WARNING)
	assert_int(panel.held_count()).is_equal(1)
	EventBus.game_load_completed.emit()
	assert_int(panel.held_count()).is_equal(0)

func test_milestones_and_rank_ups_wait_for_the_board() -> void:
	var notes := _notifications()
	var progress: CanvasLayer = auto_free(load("res://scenes/ui/ProgressPanel.tscn").instantiate())
	add_child(progress)
	var rank: CanvasLayer = auto_free(load("res://scenes/ui/RankPanel.tscn").instantiate())
	add_child(rank)
	await await_idle_frame()
	_open_board()
	progress._show_toast("Hito", UITheme.ACCENT)
	EventBus.governor_rank_up.emit(3, {})
	assert_int(_alive_toasts(notes)).is_equal(0)
	assert_int(notes.held_count()).is_equal(2)
	CombatManager.end_encounter()
	assert_int(_alive_toasts(notes)).is_greater(0)

func test_closing_the_board_announces_it() -> void:
	var monitor := monitor_signals(EventBus, false)
	_open_board()
	CombatManager.end_encounter()
	await assert_signal(monitor).is_emitted("encounter_closed")

func test_combat_notices_wait_like_the_rest() -> void:
	# La salida y vuelta de la columna no es peligro: espera al tablero y sale
	# despues (2026-10-18; antes se pintaba encima de la pelea).
	var panel := _notifications()
	await await_idle_frame()
	_open_board()
	EventBus.notification_posted.emit("La columna sale", "combat", UITheme.ACCENT)
	assert_int(_alive_toasts(panel)).is_equal(0)
	assert_int(panel.held_count()).is_equal(1)
	CombatManager.end_encounter()
	assert_int(_alive_toasts(panel)).is_equal(1)

func test_helper_tips_go_quiet_while_a_board_is_open() -> void:
	var helper: CanvasLayer = auto_free(load("res://scenes/ui/HelperPanel.tscn").instantiate())
	add_child(helper)
	await await_idle_frame()
	_open_board()
	assert_bool(helper.is_quiet()).is_true()
	# Una ayuda de la colonia espera; la del propio combate puede salir.
	assert_bool(helper._can_show({"id": "overflow", "forced": true})).is_false()
	CombatManager.end_encounter()
	assert_bool(helper.is_quiet()).is_false()
