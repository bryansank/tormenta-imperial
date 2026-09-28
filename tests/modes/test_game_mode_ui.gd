extends GdUnitTestSuite
## Lo que el jugador ve de los modos: el selector de "Nueva partida" (tematico,
## tactil, con confirmacion solo si hay algo que perder), el modo en el menu de
## pausa, la pestana de Sandbox y la derrota final de Supervivencia.

const DialogScript := preload("res://scripts/ui/NewGameDialog.gd")

var _prog_saved: Dictionary = {}

func before_test() -> void:
	_prog_saved = ProgressionManager.get_save_data()
	get_tree().paused = false

func after_test() -> void:
	get_tree().paused = false
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_prog_saved)
	for child in GameManager.get_children():
		if child.get_script() == DialogScript:
			child.queue_free()

func _dialog(ask_confirm: bool, current: int = GameMode.Mode.CAMPAIGN) -> CanvasLayer:
	var dialog: CanvasLayer = auto_free(DialogScript.new())
	dialog.setup(ask_confirm, current)
	add_child(dialog)
	return dialog

func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var hit := _find_button(child, text)
		if hit != null:
			return hit
	return null

# ── El selector ──────────────────────────────────────────────────────

func test_it_offers_the_four_modes_as_touch_sized_cards() -> void:
	var dialog := _dialog(true)
	for mode in GameMode.ORDER:
		var card: Button = dialog.mode_card(mode)
		assert_object(card).is_not_null()
		assert_float(card.custom_minimum_size.y).is_greater_equal(float(UITheme.MIN_BTN_H))
		assert_int(card.focus_mode).is_equal(Control.FOCUS_ALL)

func test_it_works_while_the_tree_is_paused() -> void:
	var dialog := _dialog(true)
	assert_int(dialog.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)

func test_it_starts_on_the_mode_being_played() -> void:
	var dialog := _dialog(true, GameMode.Mode.SURVIVAL)
	assert_int(dialog.chosen_mode).is_equal(GameMode.Mode.SURVIVAL)
	assert_bool(dialog.mode_card(GameMode.Mode.SURVIVAL).button_pressed).is_true()
	assert_bool(dialog.mode_card(GameMode.Mode.CAMPAIGN).button_pressed).is_false()

func test_tapping_a_card_selects_it_and_only_it() -> void:
	var dialog := _dialog(true)
	dialog.mode_card(GameMode.Mode.SANDBOX).pressed.emit()
	assert_int(dialog.chosen_mode).is_equal(GameMode.Mode.SANDBOX)
	var pressed := 0
	for mode in GameMode.ORDER:
		if dialog.mode_card(mode).button_pressed:
			pressed += 1
	assert_int(pressed).is_equal(1)

func test_the_grid_folds_for_tablet_laptop_and_phone() -> void:
	# 1280x800 y 1024x768 en horizontal: cuatro en fila. Movil en vertical: una.
	assert_int(DialogScript.columns_for(minf(DialogScript.MAX_WIDTH, 1280.0 - 32.0))).is_equal(4)
	assert_int(DialogScript.columns_for(minf(DialogScript.MAX_WIDTH, 1024.0 - 32.0))).is_equal(4)
	assert_int(DialogScript.columns_for(700.0)).is_equal(2)
	assert_int(DialogScript.columns_for(400.0 - 32.0)).is_equal(1)

func test_with_something_to_lose_it_asks_before_confirming() -> void:
	var dialog := _dialog(true)
	var confirmed: Array = []
	dialog.confirmed.connect(func(): confirmed.append(dialog.chosen_mode))
	dialog.pick(GameMode.Mode.BUILDER)
	assert_bool(dialog.is_confirming()).is_true()
	assert_array(confirmed).is_empty()
	# El aviso dice que se pierde y en que se empieza.
	assert_str(dialog._confirm_label.text).contains(GameMode.display_name(GameMode.Mode.CAMPAIGN))
	assert_str(dialog._confirm_label.text).contains(GameMode.display_name(GameMode.Mode.BUILDER))
	_find_button(dialog, Tr.t("BTN_MODE_WIPE_START")).pressed.emit()
	assert_array(confirmed).contains_exactly([GameMode.Mode.BUILDER])

func test_back_returns_to_the_cards_without_confirming() -> void:
	var dialog := _dialog(true)
	var confirmed: Array = []
	dialog.confirmed.connect(func(): confirmed.append(true))
	dialog.pick(GameMode.Mode.SURVIVAL)
	_find_button(dialog, Tr.t("BTN_MODE_BACK")).pressed.emit()
	assert_bool(dialog.is_confirming()).is_false()
	assert_array(confirmed).is_empty()

func test_with_nothing_to_lose_it_starts_at_once() -> void:
	var dialog := _dialog(false)
	var confirmed: Array = []
	dialog.confirmed.connect(func(): confirmed.append(dialog.chosen_mode))
	dialog.pick(GameMode.Mode.SANDBOX)
	assert_array(confirmed).contains_exactly([GameMode.Mode.SANDBOX])

func test_cancel_says_so() -> void:
	var dialog := _dialog(true)
	var canceled: Array = []
	dialog.canceled.connect(func(): canceled.append(true))
	_find_button(dialog, Tr.t("BTN_CANCEL")).pressed.emit()
	assert_int(canceled.size()).is_equal(1)

func test_game_manager_opens_it_themed_and_it_frees_itself_on_cancel() -> void:
	var before: int = GameManager.get_child_count()
	var dialog: CanvasLayer = GameManager.request_new_game(false)
	assert_object(dialog.get_script()).is_equal(DialogScript)
	assert_int(GameManager.get_child_count()).is_equal(before + 1)
	dialog.cancel()
	await await_idle_frame()
	assert_bool(is_instance_valid(dialog)).is_false()
	assert_int(GameManager.get_child_count()).is_equal(before)

func test_start_new_game_is_what_confirm_calls() -> void:
	# Sin disparar la recarga: se mira el cableado, no se borra nada.
	var dialog: CanvasLayer = GameManager.request_new_game(true)
	var calls_start := false
	for c in dialog.confirmed.get_connections():
		var cb: Callable = c["callable"]
		if cb.get_object() == dialog and cb.get_method() == "queue_free":
			continue
		calls_start = true
	dialog.cancel()
	await await_idle_frame()
	assert_bool(calls_start).is_true()

# ── El modo a la vista ───────────────────────────────────────────────

func test_the_pause_menu_names_the_mode() -> void:
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/PauseMenu.tscn").instantiate())
	add_child(menu)
	menu.open_pause()
	var text: String = menu._mode_label.text
	menu.resume()
	assert_str(text).contains(GameMode.display_name(GameMode.Mode.SURVIVAL))

func test_the_title_menu_does_not_offer_to_continue_a_finished_run() -> void:
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/TitleMenu.tscn").instantiate())
	add_child(menu)
	var loaded: bool = GameManager.loaded_from_save
	GameManager.loaded_from_save = true
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	GameMode.finish_run(GameMode.RESULT_DEFEAT)
	var offered: bool = menu.has_game_to_continue()
	GameManager.loaded_from_save = loaded
	load("res://scripts/ui/TitleMenu.gd").set_dismissed_for_tests(false)
	assert_bool(offered).is_false()

func test_the_sandbox_tab_only_exists_in_sandbox() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/SandboxPanel.tscn").instantiate())
	add_child(panel)
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	panel.refresh()
	var in_campaign: bool = panel.visible
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	panel.refresh()
	assert_bool(in_campaign).is_false()
	assert_bool(panel.visible).is_true()

func test_the_victory_of_builder_speaks_of_the_work_not_the_storm() -> void:
	GameMode.begin_run(GameMode.Mode.BUILDER)
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/VictoryScreen.tscn").instantiate())
	add_child(screen)
	screen._on_victory_achieved({"time_played": 60.0, "mode": "builder"})
	assert_bool(_has_label(screen, Tr.t("LBL_VICTORY_TITLE_BUILDER"))).is_true()
	assert_bool(_has_label(screen, GameMode.display_name(GameMode.Mode.BUILDER))).is_true()

func test_a_lost_survival_audit_shows_the_end_and_cannot_be_closed() -> void:
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/AuditDefeatScreen.tscn").instantiate())
	add_child(screen)
	GameMode.finish_run(GameMode.RESULT_DEFEAT)
	screen._show(1, -1)
	assert_bool(screen.is_run_over_variant()).is_true()
	assert_bool(screen._rebuild_btn.visible).is_false()
	assert_bool(screen._end_row.visible).is_true()
	assert_object(_find_button(screen, Tr.t("BTN_NEW_GAME"))).is_not_null()
	screen.close()
	assert_bool(screen.visible).is_true()

func test_a_campaign_defeat_still_offers_to_rebuild() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/AuditDefeatScreen.tscn").instantiate())
	add_child(screen)
	screen._show(1, -1)
	assert_bool(screen._rebuild_btn.visible).is_true()
	assert_bool(screen._end_row.visible).is_false()
	screen.close()
	assert_bool(screen.visible).is_false()

func _has_label(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for child in node.get_children():
		if _has_label(child, text):
			return true
	return false
