extends GdUnitTestSuite
## La interfaz de la expedicion: mapa, draft, parte final y abandono.
##
## El nucleo de la expedicion vive en `CombatManager` y lo construye otro
## servicio, asi que aqui el estado se monta a mano: una `Expedition` de verdad,
## creada en la prueba y entregada a la vista. Es exactamente lo que la pantalla
## hace en partida, solo que sin pasar por el manager.
##
## Se tocan miembros privados a proposito: es la unica forma de pulsar un boton
## sin inyectar eventos de raton, y lo que se quiere vigilar es justo el dibujo.

var _chosen_nodes: Array = []
var _chosen_drafts: Array = []
var _abandons: int = 0
var _original_size: Vector2i

func before_test() -> void:
	_chosen_nodes.clear()
	_chosen_drafts.clear()
	_abandons = 0
	_original_size = get_tree().root.size

func after_test() -> void:
	get_tree().root.size = _original_size

# ── Utilidades ───────────────────────────────────────────────────────

func _screen() -> CanvasLayer:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	screen.map_node_chosen.connect(func(index): _chosen_nodes.append(index))
	screen.draft_option_chosen.connect(func(index): _chosen_drafts.append(index))
	screen.abandon_confirmed.connect(func(): _abandons += 1)
	return screen

func _panel() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/SkirmishPanel.tscn").instantiate())
	add_child(panel)
	return panel

func _expedition(seed_value: int = 4242) -> Expedition:
	return Expedition.create(1, seed_value, {"infantry": 2, "artillery": 1}, 70.0, 1)

# ── Mapa ─────────────────────────────────────────────────────────────

func test_the_map_draws_one_node_per_entry() -> void:
	var screen := _screen()
	await await_idle_frame()
	var run := _expedition()
	screen.open_map(run)
	await await_idle_frame()
	assert_int(screen.map_button_count()).is_equal(run.map.size())
	assert_bool(screen._map_view.visible).is_true()
	assert_bool(screen._board_view.visible).is_false()

func test_only_the_exits_of_the_current_node_answer() -> void:
	# La regla entera del mapa: no se salta de rama y no se vuelve atras.
	var screen := _screen()
	await await_idle_frame()
	var run := _expedition()
	screen.open_map(run)
	await await_idle_frame()
	var exits: Array = run.current_exits()
	assert_array(exits).is_not_empty()
	for i in range(run.map.size()):
		assert_bool(screen.map_button(i).disabled).is_equal(not exits.has(i))

func test_clicking_a_valid_exit_asks_for_that_node() -> void:
	var screen := _screen()
	await await_idle_frame()
	var run := _expedition()
	screen.open_map(run)
	await await_idle_frame()
	var target: int = int(run.current_exits()[0])
	screen.map_button(target).pressed.emit()
	assert_array(_chosen_nodes).is_equal([target])

func test_a_node_off_the_route_does_nothing_even_if_pressed() -> void:
	# El boton esta apagado, pero la guardia real esta en el codigo: emitir la
	# senal a mano se salta el `disabled` y aun asi no debe pasar nada.
	var screen := _screen()
	await await_idle_frame()
	var run := _expedition()
	screen.open_map(run)
	await await_idle_frame()
	var exits: Array = run.current_exits()
	var locked: int = -1
	for i in range(run.map.size()):
		if i != run.current_node and not exits.has(i):
			locked = i
			break
	assert_int(locked).is_greater(-1)
	screen.map_button(locked).pressed.emit()
	assert_array(_chosen_nodes).is_empty()

func test_the_map_header_reports_progress_and_the_boss_is_marked() -> void:
	var screen := _screen()
	await await_idle_frame()
	var run := _expedition()
	screen.open_map(run)
	await await_idle_frame()
	assert_str(screen._map_progress.text).is_equal(
		Tr.t("LBL_EXPEDITION_PROGRESS") % [run.nodes_cleared(), run.map.size()]
	)
	var boss_seen := false
	for i in range(run.map.size()):
		if bool(run.map[i].get("is_boss", false)):
			boss_seen = true
			assert_str(screen.map_button(i).text).is_equal(Tr.t("LBL_BOSS"))
	assert_bool(boss_seen).is_true()

func test_every_node_says_its_risk_in_words_not_only_in_colour() -> void:
	var screen := _screen()
	await await_idle_frame()
	var run := _expedition()
	screen.open_map(run)
	await await_idle_frame()
	for i in range(run.map.size()):
		var tip: String = screen.map_button(i).tooltip_text
		assert_str(tip).is_not_empty()
		assert_bool(tip.contains(Tr.t("LBL_RISK_LOW"))
			or tip.contains(Tr.t("LBL_RISK_MED"))
			or tip.contains(Tr.t("LBL_RISK_HIGH"))).is_true()

func test_the_draft_bonuses_of_the_party_show_on_the_map() -> void:
	var screen := _screen()
	await await_idle_frame()
	var run := _expedition()
	assert_str(screen._draft_summary()).is_equal(Tr.t("LBL_NO_DRAFT_BONUSES"))
	run.apply_draft({"id": "draft_atk", "label_key": "DRAFT_ATK",
		"effect": {"stat": "atk", "delta": 2}, "applies_to": "all"})
	screen.open_map(run)
	await await_idle_frame()
	assert_str(screen._map_bonuses.text).contains(Tr.t("DRAFT_ATK") % 2)

# ── Draft ────────────────────────────────────────────────────────────

func test_the_draft_opens_with_one_card_per_option() -> void:
	var screen := _screen()
	await await_idle_frame()
	var run := _expedition()
	screen.open_map(run)
	await await_idle_frame()
	var options: Array = run.draft_options()
	assert_int(options.size()).is_greater(1)
	EventBus.draft_offered.emit(options)
	await await_idle_frame()
	assert_bool(screen.is_draft_open()).is_true()
	assert_int(screen.draft_card_count()).is_equal(options.size())

func test_picking_an_upgrade_closes_the_draft() -> void:
	var screen := _screen()
	await await_idle_frame()
	var run := _expedition()
	screen.open_map(run)
	await await_idle_frame()
	EventBus.draft_offered.emit(run.draft_options())
	await await_idle_frame()
	screen._draft_cards.get_child(0).pressed.emit()
	await await_idle_frame()
	assert_array(_chosen_drafts).is_equal([0])
	assert_bool(screen.is_draft_open()).is_false()

func test_every_draft_card_reads_as_a_translated_sentence() -> void:
	# Si falta la clave, Tr devuelve la clave misma y esto lo cantaria.
	var screen := _screen()
	await await_idle_frame()
	var run := _expedition()
	for option in run.draft_options():
		var text: String = screen.draft_text(option)
		assert_str(text).is_not_empty()
		assert_str(text).is_not_equal(String(option.get("label_key", "")))
		assert_bool(text.contains("%")).is_false()

# ── Parte final ──────────────────────────────────────────────────────

func test_the_final_report_names_the_spoils_and_the_fallen() -> void:
	var screen := _screen()
	await await_idle_frame()
	screen.open_map(_expedition())
	await await_idle_frame()
	EventBus.expedition_ended.emit(0, {"gold": 180}, {"infantry": 1})
	await await_idle_frame()
	assert_bool(screen._report_panel.visible).is_true()
	assert_bool(screen._map_view.visible).is_false()
	assert_str(screen._report_title.text).is_equal(Tr.t("LBL_VICTORY"))
	assert_str(screen._report_detail.text).contains(Tr.t("LBL_REWARDS"))
	assert_str(screen._report_detail.text).contains(Tr.res_name("gold"))
	assert_str(screen._report_detail.text).contains(Tr.t("LBL_CASUALTIES"))

func test_a_defeat_and_an_abandon_get_their_own_headline() -> void:
	var screen := _screen()
	await await_idle_frame()
	screen.open_map(_expedition())
	await await_idle_frame()
	EventBus.expedition_ended.emit(1, {}, {"infantry": 2})
	await await_idle_frame()
	assert_str(screen._report_title.text).is_equal(Tr.t("LBL_DEFEAT"))
	assert_str(screen._report_detail.text).contains(Tr.t("LBL_NO_REWARDS"))

	screen.open_map(_expedition())
	await await_idle_frame()
	EventBus.expedition_ended.emit(2, {"wood": 40}, {})
	await await_idle_frame()
	assert_str(screen._report_title.text).is_equal(Tr.t("LBL_ABANDONED"))
	assert_str(screen._report_detail.text).contains(Tr.t("LBL_NO_CASUALTIES"))

func test_going_back_to_base_closes_everything() -> void:
	var screen := _screen()
	await await_idle_frame()
	screen.open_map(_expedition())
	await await_idle_frame()
	EventBus.expedition_ended.emit(0, {"gold": 10}, {})
	await await_idle_frame()
	screen._close_all()
	assert_bool(screen.visible).is_false()
	assert_bool(screen._report_panel.visible).is_false()
	assert_int(screen.current_view()).is_equal(0)   # View.NONE

# ── Abandono ─────────────────────────────────────────────────────────

func test_abandoning_asks_first_and_cancelling_abandons_nothing() -> void:
	var screen := _screen()
	await await_idle_frame()
	screen.open_map(_expedition())
	await await_idle_frame()
	screen._abandon_map_btn.pressed.emit()
	await await_idle_frame()
	assert_bool(screen.is_confirming_abandon()).is_true()
	assert_int(_abandons).is_equal(0)
	screen._confirm_dialog.hide()
	assert_int(_abandons).is_equal(0)

func test_confirming_the_abandon_is_what_actually_abandons() -> void:
	var screen := _screen()
	await await_idle_frame()
	screen.open_map(_expedition())
	await await_idle_frame()
	screen._abandon_map_btn.pressed.emit()
	await await_idle_frame()
	screen._confirm_dialog.confirmed.emit()
	assert_int(_abandons).is_equal(1)

func test_the_warning_says_what_abandoning_costs() -> void:
	var screen := _screen()
	await await_idle_frame()
	screen.open_map(_expedition())
	await await_idle_frame()
	screen._abandon_map_btn.pressed.emit()
	assert_str(screen._confirm_dialog.dialog_text).is_equal(Tr.t("MSG_CONFIRM_ABANDON"))
	assert_str(screen._confirm_dialog.dialog_text).is_not_equal("MSG_CONFIRM_ABANDON")

# ── Panel lateral ────────────────────────────────────────────────────

func test_the_side_panel_blocks_the_launch_and_says_why() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel._selection = {}
	panel._refresh()
	assert_bool(panel._launch_btn.disabled).is_true()
	assert_bool(panel._reason_label.visible).is_true()
	assert_str(panel._reason_label.text).is_equal(Tr.t("MSG_NO_UNITS"))

func test_committing_more_than_the_board_holds_is_refused_with_a_reason() -> void:
	var panel := _panel()
	await await_idle_frame()
	var check: Dictionary = panel.evaluate_launch({"infantry": GameConfig.combat_deploy_cap + 3})
	assert_bool(bool(check.get("ok", true))).is_false()
	var reason: String = String(check.get("reason", ""))
	assert_str(reason).is_not_empty()
	assert_str(panel._reason_text(reason)).is_not_empty()
	assert_str(panel._reason_text(reason)).is_not_equal(reason)

func test_an_empty_party_never_launches() -> void:
	var panel := _panel()
	await await_idle_frame()
	var check: Dictionary = panel.evaluate_launch({})
	assert_bool(bool(check.get("ok", true))).is_false()

func test_the_dev_skirmish_button_only_exists_in_dev_mode() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel._selection = {}
	panel._refresh()
	assert_bool(panel._dev_btn.visible).is_equal(GameConfig.dev_mode)

# ── Avisos en la base ────────────────────────────────────────────────

func _notifications() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/NotificationPanel.tscn").instantiate())
	add_child(panel)
	return panel

func test_launching_and_closing_an_expedition_leaves_a_trace_in_the_base() -> void:
	var panel := _notifications()
	await await_idle_frame()
	var before: int = panel._log_entries.size()

	EventBus.expedition_started.emit(1, 7)
	assert_int(panel._log_entries.size()).is_equal(before + 1)
	assert_str(panel._log_entries[0]["message"]).is_equal(Tr.t("MSG_EXPEDITION_STARTED") % 7)

	EventBus.expedition_ended.emit(0, {"gold": 120}, {"infantry": 1})
	var won: String = panel._log_entries[0]["message"]
	assert_str(won).contains(Tr.res_name("gold"))
	assert_str(won).contains(Tr.t("LBL_CASUALTIES"))

func test_a_wiped_expedition_reports_how_many_did_not_come_back() -> void:
	var panel := _notifications()
	await await_idle_frame()
	EventBus.expedition_ended.emit(1, {}, {"infantry": 2, "artillery": 1})
	assert_str(panel._log_entries[0]["message"]).is_equal(Tr.t("MSG_EXPEDITION_LOST") % 3)

func test_an_abandoned_expedition_still_says_it_keeps_the_spoils() -> void:
	var panel := _notifications()
	await await_idle_frame()
	EventBus.expedition_ended.emit(2, {"wood": 40}, {})
	var message: String = panel._log_entries[0]["message"]
	assert_str(message).contains(Tr.t("MSG_EXPEDITION_ABANDONED"))
	assert_str(message).contains(Tr.res_name("wood"))

func test_the_army_panel_survives_an_expedition_coming_and_going() -> void:
	# Sin capa de expedicion en CombatManager, "en campana" es cero y el panel
	# tiene que seguir pintandose igual en vez de inventarse una columna fuera.
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/ArmyPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	assert_dict(panel._units_on_expedition()).is_empty()
	EventBus.expedition_started.emit(1, 7)
	EventBus.expedition_ended.emit(0, {}, {})
	await await_idle_frame()
	assert_str(panel._power_label.text).is_not_empty()

# ── Legibilidad tactil (T021, quickstart E9) ─────────────────────────

func test_the_map_stays_touchable_and_on_screen_on_a_phone() -> void:
	var screen := _screen()
	await await_idle_frame()
	get_tree().root.size = Vector2i(400, 720)
	await await_idle_frame()
	screen.open_map(_expedition())
	await await_idle_frame()

	# Ningun nodo baja del tamano minimo de un boton tocable.
	assert_int(screen._node_size).is_greater_equal(UITheme.MIN_BTN_H)
	for i in range(screen.map_button_count()):
		var btn: Button = screen.map_button(i)
		assert_float(btn.custom_minimum_size.x).is_greater_equal(float(UITheme.MIN_BTN_H))
		assert_float(btn.custom_minimum_size.y).is_greater_equal(float(UITheme.MIN_BTN_H))

	# Y nada se sale de la ventana: el mapa vive dentro de un scroll, que es lo
	# que evita que un mapa profundo empuje los botones fuera de pantalla.
	var viewport: Vector2 = screen.get_viewport().get_visible_rect().size
	assert_float(screen._map_scroll.global_position.x).is_greater_equal(-1.0)
	assert_float(screen._map_scroll.global_position.y).is_greater_equal(-1.0)
	assert_float(screen._map_scroll.global_position.x + screen._map_scroll.size.x) \
		.is_less_equal(viewport.x + 1.0)
	assert_float(screen._map_scroll.global_position.y + screen._map_scroll.size.y) \
		.is_less_equal(viewport.y + 1.0)
	assert_float(screen._abandon_map_btn.global_position.y + screen._abandon_map_btn.size.y) \
		.is_less_equal(viewport.y + 1.0)
