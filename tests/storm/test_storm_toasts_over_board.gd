extends GdUnitTestSuite
## Los avisos de la Tormenta tienen que verse con el tablero de batalla abierto:
## la ceniza, el Diezmo y la guarnicion que peleo sola llegan como toasts de
## NotificationPanel, y un aviso debajo del tablero es un aviso que no existe.
##
## Instancia los paneles de verdad y compara capas, porque el numero concreto
## importa menos que el orden: toasts sobre el tablero, tablero sobre la intro,
## y la pantalla de victoria por encima de todo.

var _intro_seen_saved := false

func before_test() -> void:
	_intro_seen_saved = TutorialManager.intro_seen

func after_test() -> void:
	TutorialManager.intro_seen = _intro_seen_saved

func _notifications() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/NotificationPanel.tscn").instantiate())
	add_child(panel)
	return panel

func _battle() -> CanvasLayer:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	return screen

func _victory() -> CanvasLayer:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/VictoryScreen.tscn").instantiate())
	add_child(screen)
	return screen

func test_toasts_draw_above_the_battle_board_and_below_the_victory_screen() -> void:
	var panel := _notifications()
	var battle := _battle()
	var victory := _victory()
	await await_idle_frame()
	assert_int(panel._toast_layer.layer).is_greater(battle.layer)
	assert_int(panel._toast_layer.layer).is_less(victory.layer)
	# El resto del panel (estado, registro) sigue donde estaba.
	assert_int(panel.layer).is_equal(11)

func test_a_toast_lands_in_the_raised_layer() -> void:
	var panel := _notifications()
	await await_idle_frame()
	var before: int = panel._toast_container.get_child_count()
	EventBus.notification_posted.emit(Tr.t("STORM_ASH_STARTED"), "warning", UITheme.WARNING)
	assert_int(panel._toast_container.get_child_count()).is_equal(before + 1)
	# El contenedor de toasts cuelga de la subcapa elevada, no del panel base.
	var holder: Node = panel._toast_container
	while holder != null and not (holder is CanvasLayer):
		holder = holder.get_parent()
	assert_object(holder).is_same(panel._toast_layer)

func test_the_window_stack_never_drags_the_toasts_down() -> void:
	# UIManager reasigna `layer` a todo lo que apila. Ni el panel ni la subcapa
	# estan en la pila, asi que abrir y cerrar ventanas no los mueve.
	var panel := _notifications()
	var battle := _battle()
	await await_idle_frame()
	var windows: Array = []
	for i in 4:
		var window: CanvasLayer = auto_free(CanvasLayer.new())
		add_child(window)
		windows.append(window)
		UIManager.open_window(window)
		assert_int(panel._toast_layer.layer).is_greater(battle.layer)
	for window in windows:
		UIManager.close_window(window)
		assert_int(panel._toast_layer.layer).is_greater(battle.layer)

func test_the_tutorial_intro_keeps_the_toasts_underneath_while_open() -> void:
	# La intro (17) es lo unico que se lee mientras esta abierta; los avisos
	# vuelven debajo y regresan arriba al cerrarla.
	var panel := _notifications()
	var battle := _battle()
	await await_idle_frame()
	EventBus.tutorial_intro_requested.emit()
	assert_int(panel._toast_layer.layer).is_less(17)
	EventBus.tutorial_intro_closed.emit()
	assert_int(panel._toast_layer.layer).is_greater(battle.layer)

func test_the_auto_defense_messages_are_translated_in_both_languages() -> void:
	var locale_saved: String = Tr._locale
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for key in ["MSG_DEFENSE_AUTO_WON", "MSG_DEFENSE_AUTO_LOST"]:
			var text: String = Tr.t(key)
			assert_str(text).is_not_equal(key)
			# Bajas y rondas.
			assert_str(text % [2, 7]).contains("2")
			assert_str(text % [2, 7]).contains("7")
	Tr.set_locale(locale_saved)
