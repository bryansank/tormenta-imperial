extends GdUnitTestSuite
## El HUD usable con el dedo y sin sorpresas con el raton:
## - Construir: pasar el raton por una tarjeta NO cambia la seleccion (A14).
## - Colocar: hay un boton CANCELAR en pantalla que usa la misma senal que ESC.
## - Ejercito: por que no se puede entrenar se lee sin tooltip.
## - Recursos y mercado: nada que se pulse baja de UITheme.MIN_BTN_H en tactil.
##
## Toca GameConfig.ui_touch_controls en memoria (sin guardar) y lo restaura.

var _saved_touch := "auto"

func before_test() -> void:
	_saved_touch = GameConfig.ui_touch_controls

func after_test() -> void:
	GameConfig.ui_touch_controls = _saved_touch

func _instance(path: String) -> CanvasLayer:
	var node: CanvasLayer = auto_free(load(path).instantiate())
	add_child(node)
	return node

func _click(control: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	control.gui_input.emit(ev)

## Las tarjetas desbloqueadas: son las que escuchan el raton.
func _unlocked_cards(menu: CanvasLayer) -> Array:
	var cards: Array = []
	for card in menu._grid_container.get_children():
		if (card as Control).mouse_entered.get_connections().size() > 0 and not card.is_queued_for_deletion():
			cards.append(card)
	return cards

# ── A14: hover solo resalta ──────────────────────────────────────────

func test_hovering_a_card_does_not_select_it() -> void:
	var menu := _instance("res://scenes/ui/ConstructionMenu.tscn")
	menu._refresh_grid()
	var cards := _unlocked_cards(menu)
	assert_int(cards.size()).is_greater(1)
	(cards[0] as Control).mouse_entered.emit()
	assert_object(menu._selected_data).is_null()

func test_the_click_selects_and_a_later_hover_keeps_it() -> void:
	var menu := _instance("res://scenes/ui/ConstructionMenu.tscn")
	menu._refresh_grid()
	var cards := _unlocked_cards(menu)
	_click(cards[0])
	var chosen: BuildingData = menu._selected_data
	assert_object(chosen).is_not_null()
	(cards[1] as Control).mouse_entered.emit()
	(cards[1] as Control).mouse_exited.emit()
	assert_object(menu._selected_data).is_same(chosen)
	_click(cards[1])
	assert_object(menu._selected_data).is_not_same(chosen)

# ── Cancelar la colocacion con el dedo ───────────────────────────────

func test_the_cancel_button_shows_only_while_placing() -> void:
	GameConfig.ui_touch_controls = "always"
	var controls := _instance("res://scenes/ui/OnScreenControls.tscn")
	assert_bool(controls.is_placing_shown()).is_false()
	EventBus.building_selected_for_placement.emit(null)
	assert_bool(controls.is_placing_shown()).is_true()
	EventBus.building_placement_cancelled.emit()
	assert_bool(controls.is_placing_shown()).is_false()

func test_the_cancel_button_emits_the_shared_cancel_signal() -> void:
	GameConfig.ui_touch_controls = "always"
	var controls := _instance("res://scenes/ui/OnScreenControls.tscn")
	var fired: Array = []
	var listener := func(): fired.append(true)
	EventBus.building_placement_cancelled.connect(listener)
	var btn := controls.find_child("CancelPlacement", true, false) as Button
	btn.pressed.emit()
	EventBus.building_placement_cancelled.disconnect(listener)
	assert_int(fired.size()).is_equal(1)

func test_moving_a_building_also_offers_cancel() -> void:
	GameConfig.ui_touch_controls = "always"
	var controls := _instance("res://scenes/ui/OnScreenControls.tscn")
	EventBus.request_move_building.emit(null)
	assert_bool(controls.is_placing_shown()).is_true()
	# building_moved no se emite aqui: GameManager autoguarda con el.
	EventBus.building_placement_cancelled.emit()
	assert_bool(controls.is_placing_shown()).is_false()

func test_no_movement_controls_on_a_pc_by_default() -> void:
	# Peticion del dueno: en PC no hay controles de movimiento en pantalla.
	if GameConfig.is_mobile_os():
		return
	GameConfig.ui_touch_controls = "auto"
	var saved_seen: bool = GameConfig._real_touch_seen
	GameConfig._real_touch_seen = false
	var controls := _instance("res://scenes/ui/OnScreenControls.tscn")
	assert_bool(controls.visible).is_false()
	GameConfig._real_touch_seen = saved_seen

# ── Ejercito: el motivo, a la vista ──────────────────────────────────

func test_the_reason_a_unit_cannot_train_is_visible_text() -> void:
	var panel := _instance("res://scenes/ui/ArmyPanel.tscn")
	panel._refresh()
	await await_idle_frame()  # las filas viejas se liberan en diferido
	var blocked := 0
	for unit_id in GameConfig.get_unit_ids():
		if not ArmyManager.can_train(unit_id)["ok"]:
			blocked += 1
	var labels := panel.find_children("BlockedReason", "Label", true, false)
	var shown := 0
	for l in labels:
		if not l.is_queued_for_deletion():
			shown += 1
			assert_str((l as Label).text).is_not_empty()
	assert_int(shown).is_equal(blocked)

# ── Tamano dedo ──────────────────────────────────────────────────────

func test_touch_px_grows_small_targets_only_on_touch() -> void:
	GameConfig.ui_touch_controls = "always"
	assert_float(UITheme.touch_px(22.0)).is_equal(float(UITheme.MIN_BTN_H))
	assert_float(UITheme.touch_px(60.0)).is_equal(60.0)
	GameConfig.ui_touch_controls = "never"
	assert_float(UITheme.touch_px(22.0)).is_equal(22.0)

func test_the_resource_toggle_is_finger_sized_on_touch() -> void:
	GameConfig.ui_touch_controls = "always"
	var hud := _instance("res://scenes/ui/ResourceHUD.tscn")
	var btn: Button = hud.get_toggle_button()
	assert_float(btn.custom_minimum_size.x).is_greater_equal(float(UITheme.MIN_BTN_H))
	assert_float(btn.custom_minimum_size.y).is_greater_equal(float(UITheme.MIN_BTN_H))

func test_the_resource_toggle_expands_the_named_rows() -> void:
	var hud := _instance("res://scenes/ui/ResourceHUD.tscn")
	assert_bool(hud.is_expanded()).is_false()
	hud.get_toggle_button().pressed.emit()
	assert_bool(hud.is_expanded()).is_true()

func test_every_resource_has_an_icon_on_disk() -> void:
	for res_id in ["gold", "wood", "steel", "oil"]:
		assert_bool(ResourceLoader.exists(UITheme.icon_path(res_id))).override_failure_message("falta el icono de %s" % res_id).is_true()

func test_no_hud_font_below_the_small_theme_size() -> void:
	# Antes el panel de recursos forzaba 10-13 px a mano. Todo sale del tema.
	var hud := _instance("res://scenes/ui/ResourceHUD.tscn")
	for node in hud.find_children("*", "Control", true, false):
		var c := node as Control
		if c.has_theme_font_size_override("font_size"):
			assert_int(c.get_theme_font_size("font_size")).is_greater_equal(UITheme.FONT_SMALL)

func test_market_steppers_are_finger_sized() -> void:
	var market := _instance("res://scenes/ui/MarketPanel.tscn")
	var small := 0
	for node in market.find_children("*", "Button", true, false):
		var b := node as Button
		if b.text == "+" or b.text == "-":
			if b.custom_minimum_size.x < UITheme.MIN_BTN_H or b.custom_minimum_size.y < UITheme.MIN_BTN_H:
				small += 1
	assert_int(small).is_equal(0)
