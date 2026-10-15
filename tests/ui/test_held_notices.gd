extends GdUnitTestSuite
## Los avisos de la colonia esperan a que termine el combate (2026-10-14,
## docs/15 §1 "Layer 3"): con un tablero abierto (pelea o parte) los toasts de
## NotificationPanel, las placas de hito/era de ProgressPanel y el ascenso de
## RankPanel no salen; van al registro (los toasts) y aparecen al cerrarse el
## tablero (EventBus.encounter_closed). Si en esa misma llamada se abre otro
## tablero (la oleada siguiente del asedio), siguen esperando.

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
	return panel._toast_container.get_children().filter(func(c): return not c.is_queued_for_deletion()).size()

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
		EventBus.notification_posted.emit("Aviso %d" % i, "danger", UITheme.DANGER)
	assert_int(panel.held_count()).is_equal(7)
	CombatManager.end_encounter()
	var cap: int = panel.MAX_TOASTS_NARROW if UILayoutManager.is_narrow() else panel.MAX_TOASTS
	assert_int(_alive_toasts(panel)).is_less_equal(cap)
	# El ultimo dice cuantos quedan en el registro.
	var last: Node = panel._toast_container.get_child(panel._toast_container.get_child_count() - 1)
	var label := last.get_child(0) as Label
	var extra: int = 7 - (cap - 1)
	assert_str(label.text).is_equal(Tr.t("MSG_HELD_NOTICES") % extra)

func test_a_new_game_drops_what_was_held() -> void:
	var panel := _notifications()
	await await_idle_frame()
	_open_board()
	EventBus.notification_posted.emit("De la partida vieja", "warning", UITheme.WARNING)
	assert_int(panel.held_count()).is_equal(1)
	EventBus.game_load_completed.emit()
	assert_int(panel.held_count()).is_equal(0)

func test_milestone_plates_wait_for_the_board() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/ProgressPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	_open_board()
	panel._show_toast("Hito", UITheme.ACCENT)
	assert_int(panel.pending_toasts()).is_equal(1)
	assert_object(panel.find_child("MilestoneToast", true, false)).is_null()
	CombatManager.end_encounter()
	assert_object(panel.find_child("MilestoneToast", true, false)).is_not_null()

func test_a_rank_up_in_battle_shows_after_it() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/RankPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	_open_board()
	EventBus.governor_rank_up.emit(3, {})
	assert_int(panel.held_rank()).is_equal(3)
	assert_object(panel.find_child("RankToast", true, false)).is_null()
	CombatManager.end_encounter()
	assert_int(panel.held_rank()).is_equal(0)
	assert_object(panel.find_child("RankToast", true, false)).is_not_null()

func test_closing_the_board_announces_it() -> void:
	var monitor := monitor_signals(EventBus, false)
	_open_board()
	CombatManager.end_encounter()
	await assert_signal(monitor).is_emitted("encounter_closed")

func test_combat_notices_still_show_during_the_fight() -> void:
	var panel := _notifications()
	await await_idle_frame()
	_open_board()
	var before := _alive_toasts(panel)
	EventBus.notification_posted.emit("La columna sale", "combat", UITheme.ACCENT)
	assert_int(panel.held_count()).is_equal(0)
	assert_int(_alive_toasts(panel)).is_equal(before + 1)

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
