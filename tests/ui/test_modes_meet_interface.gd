extends GdUnitTestSuite
## Donde se cruzan los modos de juego (docs/20) y la interfaz configurable
## (docs/21):
##   - la pestana SANDBOX pasa por HudRegistry y UILayoutManager: se oculta
##     desde Ajustes y se mueve en "Editar disposicion", y su tarjeta la sigue;
##   - el selector de "Nueva partida" se construye con los tokens vivos de
##     UITheme (paleta, alto contraste, tamano de texto y lado tactil);
##   - "Nueva partida" de la pestana Juego de Ajustes abre ese selector.
##
## settings.cfg y el estado de GameConfig vuelven intactos (SettingsParking), y
## UITheme queda de serie (UITheme.configure()).

const SettingsParking := preload("res://tests/save/settings_parking.gd")
const DialogScript := preload("res://scripts/ui/NewGameDialog.gd")

var _parked: Dictionary

func before_test() -> void:
	_parked = SettingsParking.park()
	GameConfig.ui_layout = {}
	GameConfig.ui_hud_hidden = []
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	get_tree().paused = false

func after_test() -> void:
	UILayoutManager.stop_layout_edit()
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	UITheme.configure()
	SettingsParking.restore(_parked)
	UILayoutManager._reapply_all()
	for child in GameManager.get_children():
		if child.get_script() == DialogScript:
			child.queue_free()
	get_tree().paused = false
	await await_idle_frame()

func _sandbox() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/SandboxPanel.tscn").instantiate())
	add_child(panel)
	panel.refresh()
	return panel

func _settle() -> void:
	for i in 4:
		await await_idle_frame()

# ── Sandbox en el HUD configurable ───────────────────────────────────

func test_the_sandbox_tab_is_a_registered_movable_hideable_element() -> void:
	assert_bool("SandboxPanel" in HudRegistry.hideable_ids()).is_true()
	assert_bool("SandboxPanel" in HudRegistry.movable_ids()).is_true()
	assert_str(String(UILayoutConfig.PANEL_SLOTS.get("SandboxPanel", ""))).is_equal("sandbox_tab")
	var panel := _sandbox()
	await _settle()
	var dock := HudRegistry.control_of("SandboxPanel")
	assert_object(dock).is_not_null()
	assert_object(UILayoutManager.placed_control("SandboxPanel")).is_same(dock)
	assert_bool(dock.is_ancestor_of(panel.tab_button())).is_true()
	assert_bool(dock.is_ancestor_of(panel.get("_card"))).is_true()

func test_hiding_the_sandbox_tab_hides_its_card_too() -> void:
	var panel := _sandbox()
	panel.open()
	await _settle()
	assert_bool(panel.is_open()).is_true()
	HudRegistry.set_hidden("SandboxPanel", true, false)
	await _settle()
	assert_bool(panel.tab_button().is_visible_in_tree()).is_false()
	assert_bool((panel.get("_card") as Control).is_visible_in_tree()).is_false()
	HudRegistry.set_hidden("SandboxPanel", false, false)
	await _settle()
	assert_bool(panel.tab_button().is_visible_in_tree()).is_true()

func test_moving_the_sandbox_tab_carries_the_card_and_keeps_it_on_screen() -> void:
	var panel := _sandbox()
	panel.open()
	await _settle()
	var dock := HudRegistry.control_of("SandboxPanel")
	var before := dock.get_global_rect()
	UILayoutManager.set_user_offset("SandboxPanel", Vector2(40, 120), false)
	await _settle()
	var after := dock.get_global_rect()
	assert_float(after.position.x - before.position.x).is_equal_approx(40.0, 0.5)
	assert_float(after.position.y - before.position.y).is_equal_approx(120.0, 0.5)
	var vp: Rect2 = panel.get_viewport().get_visible_rect()
	var card: Rect2 = panel.card_rect()
	assert_bool(vp.encloses(card)).override_failure_message("tarjeta %s fuera de %s" % [card, vp]).is_true()
	# Junto a la pestana y sin taparla.
	assert_bool(card.intersects(after)).is_false()
	assert_float(card.position.y).is_equal_approx(after.position.y, 0.5)

func test_the_sandbox_tab_sits_below_the_left_column() -> void:
	var panel := _sandbox()
	await _settle()
	var dock := HudRegistry.control_of("SandboxPanel")
	var tab_top := dock.get_global_rect().position.y
	for id in ["ResourceHUD", "NotificationPanel.status", "HelperPanel.tip_resources"]:
		var c := UILayoutManager.placed_control(id)
		if c != null and c.is_visible_in_tree():
			assert_float(tab_top).override_failure_message("la pestana pisa %s" % id) \
				.is_greater_equal(c.get_global_rect().end.y)
	assert_object(panel).is_not_null()

# ── El selector de modo y la accesibilidad ──────────────────────────

func test_the_mode_picker_uses_the_live_palette_contrast_and_touch_size() -> void:
	var default_danger := UITheme.DANGER
	UITheme.configure("red_green", true, 1.0, "large", 56)
	assert_bool(UITheme.DANGER != default_danger).is_true()
	var dialog: CanvasLayer = GameManager.request_new_game(false)
	await _settle()
	assert_that(DialogScript.mode_color(GameMode.Mode.SURVIVAL)).is_equal(UITheme.DANGER)
	for mode in GameMode.ORDER:
		assert_float(dialog.mode_card(mode).size.y).is_greater_equal(float(UITheme.MIN_BTN_H))
	var probe := UITheme.make_label("x", "title")
	var title := _first_label(dialog)
	assert_int(title.get_theme_font_size("font_size")).is_equal(probe.get_theme_font_size("font_size"))
	probe.free()
	var start := _find_button(dialog, Tr.t("BTN_MODE_START"))
	assert_float(start.get_combined_minimum_size().y).is_greater_equal(float(UITheme.MIN_BTN_H))
	dialog.cancel()

func test_new_game_in_the_settings_game_tab_opens_the_mode_picker() -> void:
	var settings: CanvasLayer = auto_free(load("res://scenes/ui/SettingsPanel.tscn").instantiate())
	add_child(settings)
	await _settle()
	var btn := _find_button(settings, Tr.t("BTN_NEW_GAME"))
	assert_object(btn).is_not_null()
	btn.pressed.emit()
	await _settle()
	var found: CanvasLayer = null
	for child in GameManager.get_children():
		if child.get_script() == DialogScript:
			found = child
	assert_object(found).is_not_null()
	found.cancel()

func _first_label(node: Node) -> Label:
	if node is Label:
		return node
	for child in node.get_children():
		var hit := _first_label(child)
		if hit != null:
			return hit
	return null

func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var hit := _find_button(child, text)
		if hit != null:
			return hit
	return null
