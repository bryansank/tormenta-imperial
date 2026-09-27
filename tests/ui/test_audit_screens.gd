extends GdUnitTestSuite
## Las dos pantallas de la Auditoria Final que no son el tablero:
##
##   * el cartel "Oleada X de N", que por fin escucha final_audit_wave_cleared;
##   * el parte del asedio perdido, que cuenta lo que se llevaron y que NO es el
##     final de la partida.
##
## Los handlers se llaman a mano en vez de emitir final_audit_lost por EventBus:
## StormManager tambien la escucha y cobraria un Diezmo de verdad.

var _audit_saved = null

func before_test() -> void:
	_audit_saved = ProgressionManager.final_audit

func after_test() -> void:
	ProgressionManager.final_audit = _audit_saved

func _banner() -> CanvasLayer:
	var banner: CanvasLayer = auto_free(load("res://scenes/ui/AuditWaveBanner.tscn").instantiate())
	add_child(banner)
	return banner

func _defeat() -> CanvasLayer:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/AuditDefeatScreen.tscn").instantiate())
	add_child(screen)
	return screen

## Un asedio perdido de verdad, con el modelo puro.
func _lost_audit(garrison: Dictionary = {"infantry": 2}) -> FinalAudit:
	var audit := FinalAudit.create(11, garrison, 2, 60.0)
	audit.begin()
	audit.lose()
	return audit

# ── Cartel de oleada ─────────────────────────────────────────────────

func test_the_banner_says_which_wave_of_how_many() -> void:
	var banner := _banner()
	banner.show_wave(1, 4)
	assert_bool(banner.is_showing()).is_true()
	assert_str(banner.wave_text()).is_equal(Tr.t("AUDIT_WAVE") % [2, 4])

func test_the_first_wave_warns_there_are_no_reliefs() -> void:
	assert_str(_banner_script().note_for(0, 4)).is_equal(Tr.t("AUDIT_ATTRITION"))

func test_the_last_wave_says_it_is_the_last() -> void:
	assert_str(_banner_script().note_for(3, 4)).is_equal(Tr.t("AUDIT_LAST_WAVE"))
	# Un asedio de una sola oleada: la primera ya es la ultima, y eso manda.
	assert_str(_banner_script().note_for(0, 1)).is_equal(Tr.t("AUDIT_LAST_WAVE"))
	assert_str(_banner_script().note_for(1, 4)).is_empty()

func test_a_cleared_wave_is_written_over_the_next_one() -> void:
	# La cadena real: se rompe una oleada y en la misma llamada baja la siguiente.
	ProgressionManager.final_audit = FinalAudit.create(5, {"infantry": 3}, 1, 50.0)
	var total: int = ProgressionManager.final_audit.wave_count()
	var banner := _banner()
	banner._on_wave_cleared(0, total - 1)
	banner._on_wave_ready(1, {"infantry": 2}, 1.2)
	assert_str(banner.cleared_text()).is_equal(Tr.t("AUDIT_WAVE_CLEARED") % (total - 1))
	assert_str(banner.wave_text()).is_equal(Tr.t("AUDIT_WAVE") % [2, total])

func test_breaking_the_last_wave_leaves_no_banner_behind() -> void:
	# Lo cuenta la pantalla de victoria.
	var banner := _banner()
	banner._on_wave_cleared(3, 0)
	assert_str(banner._pending_cleared).is_empty()
	banner.show_wave(2, 4)
	banner.hide_banner()
	assert_bool(banner.is_showing()).is_false()

func test_the_banner_never_takes_a_click() -> void:
	var banner := _banner()
	banner.show_wave(0, 3)
	assert_int(banner._panel.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(banner.layer).is_greater(18)  # sobre el tablero
	assert_int(banner.layer).is_less(20)     # bajo la victoria

# ── Asedio perdido ───────────────────────────────────────────────────

func test_the_defeat_report_lists_what_was_taken() -> void:
	var lines: Array = _defeat_script().loss_lines(
		{"gold": 120, "wood": 0, "buildings": 2, "workers": 3}, 4, 1, {"infantry": 2})
	var text := "\n".join(lines)
	assert_str(text).contains(Tr.amount_list({"gold": 120}))
	assert_str(text).contains(Tr.t("LBL_TITHE_SEIZED_N") % 2)
	assert_str(text).contains(Tr.t("LBL_TITHE_WORKERS_N") % 3)
	assert_str(text).contains(Tr.t("LBL_AUDIT_DAMAGE") % [4, 1])
	assert_str(text).contains(Tr.t("LBL_CASUALTIES"))
	# Cero de madera no es una perdida.
	assert_str(text).not_contains(Tr.res_name("wood"))

func test_an_empty_loss_still_says_something() -> void:
	var lines: Array = _defeat_script().loss_lines({}, 0, 0, {})
	assert_array(lines).contains_exactly([Tr.t("LBL_AUDIT_NOTHING_LOST")])

func test_it_opens_on_a_lost_siege_with_the_tithe_of_that_same_frame() -> void:
	ProgressionManager.final_audit = _lost_audit()
	var screen := _defeat()
	# Orden real: StormManager cobra al oir final_audit_lost y publica el Diezmo
	# en la misma cadena. Aqui llega antes, que es el caso que mas se da.
	screen._on_tithe_resolved(false, {"gold": 90})
	screen._on_final_audit_lost(1)
	assert_bool(screen.is_showing()).is_false()  # diferido: aun no
	await await_idle_frame()
	assert_bool(screen.is_showing()).is_true()
	assert_str(screen._lost_label.text).contains(Tr.amount_list({"gold": 90}))
	assert_str(screen._wave_label.text).contains(Tr.t("AUDIT_WAVE") % [2, ProgressionManager.final_audit.wave_count()])

func test_an_old_tithe_is_not_blamed_on_the_siege() -> void:
	ProgressionManager.final_audit = _lost_audit()
	var screen := _defeat()
	screen._on_tithe_resolved(false, {"gold": 999})
	await await_idle_frame()
	screen._on_final_audit_lost(0)
	await await_idle_frame()
	assert_str(screen._lost_label.text).not_contains("999")

func test_it_says_the_siege_can_be_called_back_and_what_it_takes() -> void:
	# Por debajo del minimo: dice cuantas hacen falta.
	ProgressionManager.final_audit = _lost_audit()
	var need: int = GameConfig.final_audit_resummon_min_units
	var text: String = _defeat_script().resummon_text()
	if ProgressionManager.can_resummon_final_audit():
		assert_str(text).is_equal(Tr.t("LBL_AUDIT_RESUMMON_READY"))
	else:
		assert_str(text).contains(Tr.t("AUDIT_RESUMMON_LOCKED") % need)

func test_losing_is_not_a_game_over() -> void:
	# El parte se cierra y la partida sigue: nada de recargar ni de borrar.
	ProgressionManager.final_audit = _lost_audit()
	var screen := _defeat()
	screen._show(0, -1)
	screen.close()
	assert_bool(screen.is_showing()).is_false()
	assert_bool(ProgressionManager.is_final_audit_lost()).is_true()

func _banner_script() -> GDScript:
	return load("res://scripts/ui/AuditWaveBanner.gd")

func _defeat_script() -> GDScript:
	return load("res://scripts/ui/AuditDefeatScreen.gd")
