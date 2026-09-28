extends GdUnitTestSuite
## Las ayudas en pantalla (docs/07 bug 6): de UNA en una, cada una con ✕ y con
## un reloj que la cierra sola y se para con el dedo encima; cerrada, vista; y
## se callan cuando estorban (ventana abierta, pausa, Tormenta), para volver
## despues sin contar como vistas.
##
## Toca GameConfig.ui_helper_visible en memoria (sin guardar) y el estado de
## TutorialManager, y los restaura.

var _saved_helper := true
var _saved_tutorial: Dictionary = {}

func before_test() -> void:
	_saved_helper = GameConfig.ui_helper_visible
	GameConfig.ui_helper_visible = true
	_saved_tutorial = TutorialManager.get_save_data()
	# Tutorial hecho, nada visto todavia.
	TutorialManager.load_save_data({"intro_seen": true, "guide_state": "done"})

func after_test() -> void:
	GameConfig.ui_helper_visible = _saved_helper
	EventBus.sidebar_toggled.emit(false)
	get_tree().paused = false
	TutorialManager.load_save_data(_saved_tutorial)

func _helper() -> CanvasLayer:
	var helper: CanvasLayer = auto_free(load("res://scenes/ui/HelperPanel.tscn").instantiate())
	add_child(helper)
	return helper

## Los globos basicos, como al terminar el tutorial.
func _queue_basics(helper: CanvasLayer) -> void:
	EventBus.tutorial_guide_finished.emit(false)
	helper.skip_gap()

func _clear_stack() -> bool:
	# Otra suite pudo dejar una ventana abierta en este proceso.
	return not UIManager.is_any_window_open()

# ── Una a la vez ─────────────────────────────────────────────────────

func test_nothing_shows_by_itself_at_first() -> void:
	# Antes nacian seis globos a la vez. Ahora nada sale sin motivo.
	var helper := _helper()
	await await_idle_frame()
	assert_int(helper.visible_help_count()).is_equal(0)

func test_the_basics_come_one_at_a_time_after_the_tutorial() -> void:
	var helper := _helper()
	await await_idle_frame()
	if not _clear_stack():
		return
	_queue_basics(helper)
	assert_int(helper.visible_help_count()).is_equal(1)
	assert_str(helper.current_help()).is_equal("callout_objective")
	assert_array(helper.queued_ids()).is_not_empty()

func test_closing_one_marks_it_seen_and_the_next_waits_a_breath() -> void:
	var helper := _helper()
	await await_idle_frame()
	if not _clear_stack():
		return
	_queue_basics(helper)
	var first: String = helper.current_help()
	(helper.current_box().close_button() as Button).pressed.emit()
	assert_bool(TutorialManager.has_seen_help(first)).is_true()
	# Respiro entre dos: en ese hueco no hay ninguna.
	assert_int(helper.visible_help_count()).is_equal(0)
	helper.skip_gap()
	assert_int(helper.visible_help_count()).is_equal(1)
	assert_str(helper.current_help()).is_not_equal(first)

func test_a_seen_help_does_not_come_back_by_itself() -> void:
	TutorialManager.mark_help_seen("callout_objective")
	var helper := _helper()
	await await_idle_frame()
	if not _clear_stack():
		return
	_queue_basics(helper)
	assert_str(helper.current_help()).is_not_equal("callout_objective")
	assert_array(helper.queued_ids()).not_contains(["callout_objective"])

func test_it_closes_itself_when_the_timer_runs_out() -> void:
	var helper := _helper()
	await await_idle_frame()
	if not _clear_stack():
		return
	_queue_basics(helper)
	var box: PanelContainer = helper.current_box()
	var id: String = helper.current_help()
	var secs: float = box.duration()
	assert_float(secs).is_between(6.0, 12.0)
	box.tick(secs + 0.1)
	assert_bool(box.visible).is_false()
	assert_bool(TutorialManager.has_seen_help(id)).is_true()

func test_the_timer_waits_while_the_finger_is_on_it() -> void:
	var helper := _helper()
	await await_idle_frame()
	if not _clear_stack():
		return
	_queue_basics(helper)
	var box: PanelContainer = helper.current_box()
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	box._gui_input(touch)
	box.tick(60.0)
	var still_there: bool = box.visible
	touch = InputEventScreenTouch.new()
	touch.pressed = false
	box._gui_input(touch)
	box.tick(60.0)
	assert_bool(still_there).is_true()
	assert_bool(box.visible).is_false()

func test_the_time_grows_with_the_text() -> void:
	var HC := load("res://scripts/ui/HelpCatalog.gd")
	assert_float(HC.auto_close_seconds("")).is_equal(6.0)
	assert_float(HC.auto_close_seconds("x".repeat(2000))).is_equal(12.0)
	var mid: float = HC.auto_close_seconds("x".repeat(100))
	assert_float(mid).is_between(6.1, 11.9)

func test_every_help_box_has_a_close_button_and_a_timer_bar() -> void:
	var helper := _helper()
	await await_idle_frame()
	for box in helper._all_boxes():
		assert_object((box as Node).find_child("CloseButton", true, false)).is_not_null()
		assert_object((box as Node).find_child("TimerBar", true, false)).is_not_null()

# ── Prioridad y contexto ─────────────────────────────────────────────

func test_a_tip_about_what_just_happened_goes_first() -> void:
	var helper := _helper()
	await await_idle_frame()
	if not _clear_stack():
		return
	GameConfig.ui_helper_visible = true
	# Los basicos esperan detras del respiro; llega un consejo.
	EventBus.tutorial_guide_finished.emit(false)
	(helper.current_box() as PanelContainer).call("finish", "close")
	EventBus.tutorial_tip_requested.emit("overflow", "t", "b")
	helper.skip_gap()
	assert_str(helper.current_help()).is_equal("overflow")
	assert_bool(helper.is_tip_showing()).is_true()
	assert_int(helper.visible_help_count()).is_equal(1)

func test_nothing_shows_by_itself_during_the_guided_tutorial() -> void:
	TutorialManager.load_save_data({"intro_seen": true, "guide_state": "active"})
	var helper := _helper()
	await await_idle_frame()
	EventBus.tutorial_tip_requested.emit("overflow", "t", "b")
	helper.skip_gap()
	assert_int(helper.visible_help_count()).is_equal(0)

func test_skipping_the_tutorial_brings_the_build_help_first() -> void:
	var helper := _helper()
	await await_idle_frame()
	if not _clear_stack():
		return
	EventBus.tutorial_guide_finished.emit(true)
	helper.skip_gap()
	assert_str(helper.current_help()).is_equal("callout_build")

# ── Callarse y volver ────────────────────────────────────────────────

func test_a_window_puts_it_aside_without_counting_it_as_seen() -> void:
	var helper := _helper()
	await await_idle_frame()
	if not _clear_stack():
		return
	_queue_basics(helper)
	var id: String = helper.current_help()
	var window: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(window)
	UIManager.open_window(window)
	var during: int = helper.visible_help_count()
	UIManager.close_window(window)
	assert_int(during).is_equal(0)
	assert_bool(TutorialManager.has_seen_help(id)).is_false()
	assert_str(helper.current_help()).is_equal(id)

func test_callouts_hide_while_any_window_is_open_and_return_after() -> void:
	var helper := _helper()
	await await_idle_frame()
	var window: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(window)
	UIManager.open_window(window)
	await await_idle_frame()
	assert_bool(helper.is_showing_callouts()).is_false()
	UIManager.close_window(window)
	await await_idle_frame()
	if not UIManager.is_any_window_open():
		assert_bool(helper.is_showing_callouts()).is_true()

func test_the_storm_silences_them_and_the_tithe_brings_them_back() -> void:
	var helper := _helper()
	await await_idle_frame()
	helper._set_storm_silenced(true)
	assert_bool(helper.is_showing_callouts()).is_false()
	helper._set_storm_silenced(false)
	if not UIManager.is_any_window_open():
		assert_bool(helper.is_showing_callouts()).is_true()

func test_a_player_who_switched_help_off_does_not_get_it_back_after_the_storm() -> void:
	GameConfig.ui_helper_visible = false
	var helper := _helper()
	await await_idle_frame()
	helper._set_storm_silenced(true)
	helper._set_storm_silenced(false)
	assert_bool(helper.is_showing_callouts()).is_false()

func test_help_off_stops_the_automatic_ones_but_a_requested_one_still_shows() -> void:
	GameConfig.ui_helper_visible = false
	var helper := _helper()
	await await_idle_frame()
	if not _clear_stack():
		return
	_queue_basics(helper)
	assert_int(helper.visible_help_count()).is_equal(0)
	TutorialManager.reopen_help("callout_resources")
	assert_str(helper.current_help()).is_equal("callout_resources")
	assert_int(helper.visible_help_count()).is_equal(1)

func test_the_menus_tip_steps_aside_while_the_sidebar_is_unfolded() -> void:
	# Se dibuja justo donde el menu desplegado pone sus botones.
	var helper := _helper()
	await await_idle_frame()
	EventBus.sidebar_toggled.emit(true)
	await await_idle_frame()
	assert_bool(helper._slot_allowed("HelperPanel.tip_menus")).is_false()
	EventBus.sidebar_toggled.emit(false)
	await await_idle_frame()
	if not UILayoutManager.is_narrow() and DeviceProfile.layout_variant() != "compact":
		assert_bool(helper._slot_allowed("HelperPanel.tip_menus")).is_true()

# ── El menu y el indice ──────────────────────────────────────────────

func test_the_help_entry_appears_with_the_sidebar() -> void:
	var helper := _helper()
	await await_idle_frame()
	assert_bool(helper._help_btn.visible).is_false()
	EventBus.sidebar_toggled.emit(true)
	await await_idle_frame()
	assert_bool(helper._help_btn.visible).is_true()
	# Y queda debajo del ultimo boton del menu, sin taparlo.
	var order := UILayoutConfig.SIDEBAR_BUTTON_ORDER
	var prev_y := UILayoutManager.get_sidebar_button_offset(order[order.size() - 2])
	assert_float(helper._help_btn.offset_top).is_greater_equal(prev_y + UILayoutConfig.SIDEBAR_BTN_HEIGHT)

func test_the_help_entry_opens_the_index() -> void:
	var helper := _helper()
	await await_idle_frame()
	helper._help_btn.pressed.emit()
	var idx: CanvasLayer = helper.help_index()
	var open: bool = idx.is_open()
	idx.close()
	assert_bool(open).is_true()

func test_the_old_floating_question_mark_is_gone() -> void:
	var helper := _helper()
	await await_idle_frame()
	for b in helper.find_children("*", "Button", true, false):
		assert_str((b as Button).text).is_not_equal("?")

func test_the_help_entry_lives_in_the_sidebar_order() -> void:
	# A6: la ayuda es una entrada del menu, no un boton flotante.
	assert_array(UILayoutConfig.SIDEBAR_BUTTON_ORDER).contains(["HelperPanel.button"])
	assert_str(Tr.t("BTN_HELP")).is_not_equal("BTN_HELP")
