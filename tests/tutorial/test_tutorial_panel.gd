extends GdUnitTestSuite
## El panel del tutorial pinta lo que le llega y avisa al cerrar. Se comprueba
## que la intro se abre y se pagina, que "Saltar" la cierra y la marca como
## vista, que todas las paginas traen texto traducido, y que un consejo espera
## a que la intro se cierre en vez de pintarse encima.
##
## Toca miembros privados a proposito: es la forma de simular los botones sin
## inyectar eventos de raton.

var _closed := 0

func before_test() -> void:
	_closed = 0
	EventBus.tutorial_intro_closed.connect(_count_closed)

func after_test() -> void:
	EventBus.tutorial_intro_closed.disconnect(_count_closed)

func _count_closed() -> void:
	_closed += 1

func _panel() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/TutorialPanel.tscn").instantiate())
	add_child(panel)
	return panel

func test_the_intro_opens_on_request_and_starts_at_the_first_page() -> void:
	var panel := _panel()
	await await_idle_frame()
	assert_bool(panel.is_intro_open()).is_false()
	EventBus.tutorial_intro_requested.emit()
	assert_bool(panel.is_intro_open()).is_true()
	assert_int(panel.current_page()).is_equal(0)
	assert_bool(panel._card.visible).is_true()
	assert_bool(panel._backdrop.visible).is_true()
	panel._close()

func test_next_walks_every_page_and_the_last_one_closes() -> void:
	var panel := _panel()
	await await_idle_frame()
	EventBus.tutorial_intro_requested.emit()
	var pages: int = panel.page_count()
	for i in range(pages - 1):
		panel._next_page()
		assert_int(panel.current_page()).is_equal(i + 1)
	assert_str(panel._next_btn.text).is_equal(Tr.t("BTN_TUTORIAL_START"))
	panel._next_page()
	assert_bool(panel.is_intro_open()).is_false()
	assert_int(_closed).is_equal(1)

func test_skip_closes_and_reports_the_intro_as_closed() -> void:
	var panel := _panel()
	await await_idle_frame()
	EventBus.tutorial_intro_requested.emit()
	panel._close()
	assert_bool(panel.is_intro_open()).is_false()
	assert_bool(panel._card.visible).is_false()
	assert_bool(panel._backdrop.visible).is_false()
	assert_int(_closed).is_equal(1)
	# Cerrar dos veces no avisa dos veces.
	panel._close()
	assert_int(_closed).is_equal(1)

func test_every_page_has_translated_title_and_body() -> void:
	var panel := _panel()
	await await_idle_frame()
	EventBus.tutorial_intro_requested.emit()
	for i in range(panel.page_count()):
		panel.go_to_page(i)
		assert_str(panel._title_label.text).is_not_empty()
		assert_str(panel._title_label.text).not_contains("TUT_")
		assert_str(panel._body_label.text).not_contains("TUT_")
		assert_int(panel._body_label.text.length()).is_greater(80)
		assert_str(panel._page_label.text).is_equal("%d / %d" % [i + 1, panel.page_count()])
	panel._close()

func test_the_lore_comes_before_how_to_play() -> void:
	# El orden es una decision: primero quien eres, despues que hacer.
	var panel := _panel()
	var seen_play := false
	for p in panel.PAGES:
		if p["section"] == "LBL_TUTORIAL_SECTION_PLAY":
			seen_play = true
		elif seen_play:
			fail("una pagina de lore va despues de una de como se juega")
	assert_bool(seen_play).is_true()

func test_the_skip_button_is_always_there() -> void:
	var panel := _panel()
	await await_idle_frame()
	EventBus.tutorial_intro_requested.emit()
	for i in range(panel.page_count()):
		panel.go_to_page(i)
		assert_bool(panel._skip_btn.visible).is_true()
		assert_str(panel._skip_btn.text).is_equal(Tr.t("BTN_TUTORIAL_SKIP"))
	panel._close()

func test_the_intro_sits_in_the_ui_manager_stack_while_open() -> void:
	var panel := _panel()
	await await_idle_frame()
	var before: bool = UIManager.is_any_window_open()
	EventBus.tutorial_intro_requested.emit()
	assert_bool(UIManager.is_any_window_open()).is_true()
	assert_int(panel.layer).is_equal(panel.INTRO_LAYER)
	panel._close()
	assert_bool(UIManager.is_any_window_open()).is_equal(before)

func test_the_card_never_exceeds_the_viewport() -> void:
	var panel := _panel()
	await await_idle_frame()
	EventBus.tutorial_intro_requested.emit()
	await await_idle_frame()
	var vp: Vector2 = panel.get_viewport().get_visible_rect().size
	assert_float(panel._card.size.x).is_less_equal(vp.x)
	assert_float(panel._card.size.y).is_less_equal(vp.y)
	panel._close()

# ── Consejos ─────────────────────────────────────────────────────────

func test_a_tip_shows_and_got_it_hides_it() -> void:
	var panel := _panel()
	await await_idle_frame()
	EventBus.tutorial_tip_requested.emit("storm_incoming", "Titulo", "Cuerpo")
	assert_bool(panel.is_tip_showing()).is_true()
	assert_bool(panel._tip_card.visible).is_true()
	assert_str(panel._tip_title.text).is_equal("Titulo")
	assert_str(panel._tip_body.text).is_equal("Cuerpo")
	panel._dismiss_tip()
	assert_bool(panel.is_tip_showing()).is_false()
	assert_bool(panel._tip_card.visible).is_false()

func test_a_tip_is_not_modal() -> void:
	# El juego sigue detras: sin fondo oscuro y sin entrar en la pila de modales.
	var panel := _panel()
	await await_idle_frame()
	var before: bool = UIManager.is_any_window_open()
	EventBus.tutorial_tip_requested.emit("storm_ash", "T", "B")
	assert_bool(panel._backdrop.visible).is_false()
	assert_bool(UIManager.is_any_window_open()).is_equal(before)
	panel._dismiss_tip()

func test_tips_queue_up_one_at_a_time() -> void:
	var panel := _panel()
	await await_idle_frame()
	EventBus.tutorial_tip_requested.emit("a", "Uno", "1")
	EventBus.tutorial_tip_requested.emit("b", "Dos", "2")
	assert_str(panel._tip_title.text).is_equal("Uno")
	assert_int(panel.pending_tips()).is_equal(1)
	panel._dismiss_tip()
	assert_str(panel._tip_title.text).is_equal("Dos")
	assert_int(panel.pending_tips()).is_equal(0)
	panel._dismiss_tip()
	assert_bool(panel.is_tip_showing()).is_false()

func test_a_tip_waits_for_the_intro_to_close() -> void:
	var panel := _panel()
	await await_idle_frame()
	EventBus.tutorial_intro_requested.emit()
	EventBus.tutorial_tip_requested.emit("storm_incoming", "T", "B")
	assert_bool(panel.is_tip_showing()).is_false()
	assert_int(panel.pending_tips()).is_equal(1)
	panel._close()
	assert_bool(panel.is_tip_showing()).is_true()
	panel._dismiss_tip()
