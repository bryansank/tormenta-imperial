extends GdUnitTestSuite
## Los partes de guerra sin tablero: la defensa resuelta a ciegas
## (defense_auto_resolved, que hasta ahora nadie escuchaba) y el Diezmo con su
## sello. Salen en cola, de uno en uno, y nunca encima de un tablero abierto.

var _audit_saved = null

func before_test() -> void:
	_audit_saved = ProgressionManager.final_audit
	CombatManager.reset()

func after_test() -> void:
	ProgressionManager.final_audit = _audit_saved
	CombatManager.end_encounter()
	CombatManager.reset()

func _screen() -> CanvasLayer:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/WarReportScreen.tscn").instantiate())
	add_child(screen)
	# La cola se vacia en _process; aqui se maneja a mano con try_show_next().
	screen.set_process(false)
	return screen

func _script() -> GDScript:
	return load("res://scripts/ui/WarReportScreen.gd")

const SUMMARY := {
	"casualties": {"infantry": 2},
	"enemy_casualties": {"infantry": 3, "artillery": 1},
	"tower_crews": 1,
	"tower_crews_lost": 0,
	"morale_delta": -4,
}

# ── Parte de defensa ─────────────────────────────────────────────────

func test_the_defense_report_counts_both_sides_and_the_rounds() -> void:
	var text := "\n".join(_script().defense_lines(true, 9, SUMMARY))
	assert_str(text).contains(Tr.t("LBL_REPORT_ROUNDS") % 9)
	assert_str(text).contains(Tr.t("LBL_REPORT_OUR_LOSSES"))
	assert_str(text).contains(Tr.t("LBL_REPORT_THEIR_LOSSES"))
	assert_str(text).contains("3 %s" % Tr.t(GameConfig.get_unit_def("infantry").get("name", "infantry")))
	assert_str(text).contains(Tr.t("LBL_REPORT_TOWER_CREWS") % [1, 0])
	assert_str(text).contains(Tr.t("STORM_TITHE_REPELLED"))

func test_a_lost_defense_says_the_tithe_was_collected() -> void:
	var text := "\n".join(_script().defense_lines(false, 4, {}))
	assert_str(text).contains(Tr.t("STORM_TITHE_PAID"))
	# Sin bajas se dice, no se deja la linea en blanco.
	assert_str(text).contains(Tr.t("LBL_REPORT_NONE"))

func test_the_signal_nobody_listened_to_now_opens_a_report() -> void:
	var screen := _screen()
	EventBus.defense_auto_resolved.emit(false, 6, SUMMARY)
	assert_int(screen.pending_count()).is_equal(1)
	assert_bool(screen.try_show_next()).is_true()
	assert_int(screen.current_kind()).is_equal(0)  # Kind.DEFENSE
	assert_str(screen.title_text()).is_equal(Tr.t("LBL_REPORT_DEFENSE_LOST"))

# ── Diezmo ───────────────────────────────────────────────────────────

func test_the_tithe_report_reads_the_taken_dictionary() -> void:
	var text := "\n".join(_script().tithe_lines(false, {"gold": 50, "steel": 10, "buildings": 1, "workers": 2}))
	assert_str(text).contains(Tr.amount_list({"gold": 50, "steel": 10}))
	assert_str(text).contains(Tr.t("LBL_TITHE_SEIZED_N") % 1)
	assert_str(text).contains(Tr.t("LBL_TITHE_WORKERS_N") % 2)

func test_a_repelled_tithe_gets_the_repelled_stamp() -> void:
	var screen := _screen()
	screen._enqueue_tithe(true, {}, -99)
	screen.try_show_next()
	assert_str(screen.stamp_text()).is_equal(Tr.t("LBL_STAMP_REPELLED"))
	assert_str(screen.title_text()).is_equal(Tr.t("LBL_REPORT_TITHE_REPELLED"))

func test_a_collected_tithe_gets_the_collected_stamp() -> void:
	var screen := _screen()
	screen._enqueue_tithe(false, {"wood": 30}, -99)
	screen.try_show_next()
	assert_str(screen.stamp_text()).is_equal(Tr.t("LBL_STAMP_COLLECTED"))
	assert_str(screen.body_text()).contains(Tr.amount_list({"wood": 30}))

func test_the_tithe_of_a_lost_siege_is_left_to_the_defeat_screen() -> void:
	var screen := _screen()
	var frame: int = Engine.get_process_frames()
	screen._audit_lost_frame = frame
	screen._enqueue_tithe(false, {"gold": 400}, frame)
	assert_int(screen.pending_count()).is_equal(0)

func test_no_tithe_report_while_the_siege_is_being_fought() -> void:
	var audit := FinalAudit.create(3, {"infantry": 2}, 1, 50.0)
	audit.begin()
	ProgressionManager.final_audit = audit
	var screen := _screen()
	screen._on_tithe_resolved(true, {})
	await await_idle_frame()
	assert_int(screen.pending_count()).is_equal(0)

func test_reports_come_one_at_a_time_in_order() -> void:
	# Una defensa perdida trae su Diezmo detras: primero la pelea, luego la cuenta.
	var screen := _screen()
	screen._on_defense_auto_resolved(false, 5, SUMMARY)
	screen._enqueue_tithe(false, {"gold": 20}, -99)
	screen.try_show_next()
	var first: int = screen.current_kind()
	var blocked: bool = screen.try_show_next()  # hay uno en pantalla
	screen.close_current()
	screen.try_show_next()
	var second: int = screen.current_kind()
	assert_int(first).is_equal(0)
	assert_bool(blocked).is_false()
	assert_int(second).is_equal(1)

func test_a_report_waits_for_the_board_to_close() -> void:
	var screen := _screen()
	CombatManager.start_encounter({"infantry": 1}, {"infantry": 1})
	screen._on_defense_auto_resolved(true, 3, SUMMARY)
	var shown_over_board: bool = screen.try_show_next()
	CombatManager.end_encounter()
	var shown_after: bool = screen.try_show_next()
	assert_bool(shown_over_board).is_false()
	assert_bool(shown_after).is_true()
