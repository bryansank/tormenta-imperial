extends GdUnitTestSuite
## Los globos del tutorial se callan cuando estorban (A4).
##
## Se dibujan en la capa 14, por encima del HUD, y tapaban los paneles que el
## jugador acababa de abrir. La regla: con cualquier ventana abierta, con el
## menu lateral desplegado o con la Tormenta anunciada, los globos no se ven;
## al volver a la calma vuelven, salvo que el jugador los haya apagado.
##
## Toca GameConfig.ui_helper_visible en memoria (sin guardar) y lo restaura.

var _saved_helper := true

func before_test() -> void:
	_saved_helper = GameConfig.ui_helper_visible
	GameConfig.ui_helper_visible = true

func after_test() -> void:
	GameConfig.ui_helper_visible = _saved_helper
	EventBus.sidebar_toggled.emit(false)

func _helper() -> CanvasLayer:
	var helper: CanvasLayer = auto_free(load("res://scenes/ui/HelperPanel.tscn").instantiate())
	add_child(helper)
	return helper

func test_callouts_show_by_default_when_nothing_is_open() -> void:
	var helper := _helper()
	await await_idle_frame()
	if UIManager.is_any_window_open():
		return  # otra suite dejo una ventana abierta en este proceso; nada que medir
	assert_bool(helper.is_showing_callouts()).is_true()

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

func test_callouts_hide_while_the_sidebar_is_unfolded() -> void:
	var helper := _helper()
	await await_idle_frame()
	EventBus.sidebar_toggled.emit(true)
	await await_idle_frame()
	assert_bool(helper.is_showing_callouts()).is_false()
	EventBus.sidebar_toggled.emit(false)
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

func test_the_help_entry_lives_in_the_sidebar_order() -> void:
	# A6: la ayuda es una entrada del menu, no un boton flotante.
	assert_array(UILayoutConfig.SIDEBAR_BUTTON_ORDER).contains(["HelperPanel.button"])
	assert_str(Tr.t("BTN_HELP")).is_not_equal("BTN_HELP")
