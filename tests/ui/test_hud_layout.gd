extends GdUnitTestSuite
## HUD configurable (docs/21): ocultar elementos desde el registro central,
## mover paneles con desplazamientos guardados por perfil y proporcion, recorte
## a pantalla, ajuste a rejilla y bordes, el editor de disposicion y la columna
## central en tablet 4:3 (960x720 y 1024x768).
##
## Toca UILayoutManager y GameConfig (autoloads) con paneles de prueba; el
## settings.cfg y el estado de GameConfig vuelven intactos (SettingsParking).
## No se usa monitor_signals sobre autoloads.

const SettingsParking := preload("res://tests/save/settings_parking.gd")
const LayoutEditor := preload("res://scripts/ui/LayoutEditor.gd")

var _parked: Dictionary
var _saved_vp: Vector2
var _saved_sidebar := false

func before_test() -> void:
	_parked = SettingsParking.park()
	_saved_vp = UILayoutManager._viewport_size
	_saved_sidebar = UILayoutManager.is_sidebar_expanded()
	GameConfig.ui_layout = {}
	GameConfig.ui_hud_hidden = []

func after_test() -> void:
	UILayoutManager.stop_layout_edit()
	SettingsParking.restore(_parked)
	UILayoutManager._viewport_size = _saved_vp
	UILayoutManager._reapply_all()
	EventBus.sidebar_toggled.emit(_saved_sidebar)
	await await_idle_frame()

func _panel(lines: int = 2) -> PanelContainer:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	for i in lines:
		vbox.add_child(UITheme.make_label("linea %d" % i, "body"))
	return panel

## Coloca un panel de prueba como lo hace su panel real: layout, arbol, registro.
func _place(panel_id: String, lines: int = 2, register := false) -> PanelContainer:
	var holder: Control = auto_free(Control.new())
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	var panel := _panel(lines)
	UILayoutManager.apply_layout(panel_id, panel)
	holder.add_child(panel)
	if register:
		HudRegistry.register(panel_id, panel)
	return panel

func _settle() -> void:
	for i in 4:
		await await_idle_frame()

func _rect(c: Control) -> Rect2:
	return c.get_global_rect()

# ── Registro ─────────────────────────────────────────────────────────

func test_the_registry_is_consistent() -> void:
	for id in HudRegistry.ELEMENTS:
		assert_bool(id in HudRegistry.ORDER).override_failure_message(id).is_true()
		if HudRegistry.ELEMENTS[id]["movable"]:
			assert_bool(UILayoutConfig.PANEL_SLOTS.has(id)).override_failure_message("%s sin slot" % id).is_true()
		for locale in Tr.LOCALES:
			assert_bool(Tr._STRINGS[locale].has(HudRegistry.label_key(id))).override_failure_message("%s/%s" % [locale, id]).is_true()
	assert_int(HudRegistry.ORDER.size()).is_equal(HudRegistry.ELEMENTS.size())

func test_essential_controls_are_not_in_the_registry() -> void:
	for id in ["MarketPanel.sidebar_toggle", "PauseMenu", "SettingsPanel.button"]:
		assert_bool(HudRegistry.ELEMENTS.has(id)).is_false()

func test_hiding_wraps_the_panel_and_leaves_its_own_visibility_alone() -> void:
	var panel := _place("ResourceHUD", 2, true)
	var holder := HudRegistry.holder_of("ResourceHUD")
	assert_object(holder).is_not_null()
	assert_object(panel.get_parent()).is_same(holder)
	HudRegistry.set_hidden("ResourceHUD", true)
	assert_bool(panel.is_visible_in_tree()).is_false()
	assert_bool(panel.visible).is_true()
	assert_bool("ResourceHUD" in GameConfig.ui_hud_hidden).is_true()
	HudRegistry.set_hidden("ResourceHUD", false)
	assert_bool(panel.is_visible_in_tree()).is_true()

func test_a_panel_that_hides_itself_stays_hidden_when_the_hud_shows_it() -> void:
	# La poblacion se esconde sola hasta la fase de asentamiento: mostrarla
	# desde Ajustes no la adelanta.
	var panel := _place("NotificationPanel.status", 2, true)
	panel.visible = false
	HudRegistry.set_hidden("NotificationPanel.status", true)
	HudRegistry.set_hidden("NotificationPanel.status", false)
	assert_bool(panel.visible).is_false()

func test_hidden_state_survives_a_save_and_a_load() -> void:
	HudRegistry.set_hidden("StormHUD", true)
	GameConfig.ui_hud_hidden = []
	GameConfig.load_user_settings()
	assert_bool(HudRegistry.is_hidden("StormHUD")).is_true()

func test_a_new_panel_registered_later_starts_hidden_if_the_player_hid_it() -> void:
	GameConfig.ui_hud_hidden = ["NotificationPanel.objective"]
	var panel := _place("NotificationPanel.objective", 1, true)
	assert_bool(panel.is_visible_in_tree()).is_false()

func test_the_help_entry_is_the_ayuda_switch() -> void:
	var got: Array = []
	var listener := func(v: bool): got.append(v)
	EventBus.helper_visibility_changed.connect(listener)
	HudRegistry.set_hidden("HelperPanel.callouts", true)
	var off := GameConfig.ui_helper_visible
	HudRegistry.set_hidden("HelperPanel.callouts", false)
	EventBus.helper_visibility_changed.disconnect(listener)
	assert_bool(off).is_false()
	assert_bool(GameConfig.ui_helper_visible).is_true()
	assert_array(got).is_equal([false, true])

func test_non_hideable_entries_cannot_be_hidden() -> void:
	HudRegistry.set_hidden("ConstructionMenu.button", true)
	assert_bool(HudRegistry.is_hidden("ConstructionMenu.button")).is_false()

func test_hiding_the_panel_above_compacts_the_column() -> void:
	UILayoutManager._viewport_size = Vector2(1280, 720)
	var resources := _place("ResourceHUD", 3, true)
	var status := _place("NotificationPanel.status", 2)
	await _settle()
	var stacked_top := _rect(status).position.y
	HudRegistry.set_hidden("ResourceHUD", true)
	await _settle()
	assert_float(_rect(status).position.y).is_less(stacked_top)
	assert_float(_rect(status).position.y).is_equal_approx(float(UILayoutConfig.SLOTS["top_left"]["margin"]["top"]), 1.0)
	assert_bool(resources.visible).is_true()

# ── Paneles movibles ─────────────────────────────────────────────────

func test_a_user_offset_moves_the_panel_and_reset_brings_it_back() -> void:
	UILayoutManager._viewport_size = Vector2(1280, 720)
	var panel := _place("ResourceHUD")
	await _settle()
	var home := _rect(panel).position
	UILayoutManager.set_user_offset("ResourceHUD", Vector2(200, 96))
	await _settle()
	assert_vector(_rect(panel).position - home).is_equal_approx(Vector2(200, 96), Vector2(0.5, 0.5))
	UILayoutManager.reset_user_layout()
	await _settle()
	assert_vector(_rect(panel).position).is_equal_approx(home, Vector2(0.5, 0.5))

func test_offsets_are_saved_per_profile_and_aspect() -> void:
	GameConfig.ui_device_profile = "pc"
	UILayoutManager.set_user_offset("StormHUD", Vector2(40, 16))
	var pc_key := UILayoutManager.layout_key()
	GameConfig.ui_device_profile = "tablet"
	var tablet_offset := UILayoutManager.get_user_offset("StormHUD")
	GameConfig.ui_device_profile = "pc"
	assert_vector(tablet_offset).is_equal(Vector2.ZERO)
	assert_vector(UILayoutManager.get_user_offset("StormHUD")).is_equal(Vector2(40, 16))
	assert_bool(GameConfig.ui_layout.has(pc_key)).is_true()
	# Y viajan en settings.cfg, no en la partida.
	GameConfig.ui_layout = {}
	GameConfig.load_user_settings()
	assert_vector(UILayoutManager.get_user_offset("StormHUD")).is_equal(Vector2(40, 16))

func test_a_moved_panel_never_leaves_the_screen() -> void:
	UILayoutManager._viewport_size = Vector2(1280, 720)
	var panel := _place("NotificationPanel.objective", 2)
	UILayoutManager.set_user_offset("NotificationPanel.objective", Vector2(5000, 5000))
	await _settle()
	var r := _rect(panel)
	assert_float(r.end.x).is_less_equal(1280.0 - UILayoutManager.EDGE_MARGIN + 0.5)
	assert_float(r.end.y).is_less_equal(720.0 - UILayoutManager.EDGE_MARGIN + 0.5)
	assert_float(r.position.x).is_greater_equal(0.0)

func test_moving_a_panel_out_of_its_column_lets_the_next_one_move_up() -> void:
	UILayoutManager._viewport_size = Vector2(1280, 720)
	var resources := _place("ResourceHUD", 3)
	var status := _place("NotificationPanel.status", 2)
	await _settle()
	UILayoutManager.set_user_offset("ResourceHUD", Vector2(400, 300))
	await _settle()
	assert_float(_rect(status).position.y).is_equal_approx(float(UILayoutConfig.SLOTS["top_left"]["margin"]["top"]), 1.0)
	assert_bool(_rect(status).intersects(_rect(resources))).is_false()

func test_snap_to_grid_and_edges() -> void:
	var vp := Vector2(1280, 720)
	# A la rejilla de 8.
	var snapped := UILayoutManager.snap_offset(Vector2(203, 101), Rect2(400, 300, 200, 60), vp)
	assert_float(fmod(snapped.x, UILayoutManager.SNAP_GRID)).is_equal(0.0)
	assert_float(fmod(snapped.y, UILayoutManager.SNAP_GRID)).is_equal(0.0)
	# Cerca del borde derecho, pegado a EDGE_MARGIN.
	var rect := Rect2(1280 - 200 - 18, 300, 200, 60)
	var edge := UILayoutManager.snap_offset(Vector2(0, 0), rect, vp)
	assert_float(rect.end.x + edge.x).is_equal_approx(1280.0 - UILayoutManager.EDGE_MARGIN, 0.01)

func test_clamp_rect_to_pushes_back_inside() -> void:
	var vp := Vector2(1280, 720)
	assert_vector(UILayoutManager.clamp_rect_to(Rect2(-50, 10, 100, 40), vp)).is_equal(Vector2(58, 0))
	assert_vector(UILayoutManager.clamp_rect_to(Rect2(1250, 700, 100, 40), vp)).is_equal(Vector2(-78, -28))
	assert_vector(UILayoutManager.clamp_rect_to(Rect2(100, 100, 100, 40), vp)).is_equal(Vector2.ZERO)

func test_a_drag_result_is_snapped_and_on_screen() -> void:
	var vp := Vector2(1280, 720)
	var r0 := Rect2(10, 8, 300, 80)
	var out := LayoutEditor.drag_result(Vector2.ZERO, r0, Vector2(-500, 3000), vp)
	var final_rect := Rect2(r0.position + out, r0.size)
	assert_bool(Rect2(Vector2.ZERO, vp).encloses(final_rect)).is_true()

# ── Editor de disposicion ────────────────────────────────────────────

func test_the_editor_frames_the_movable_panels_and_drags_them() -> void:
	UILayoutManager._viewport_size = Vector2(1280, 720)
	var scene: Node = auto_free(Node.new())
	add_child(scene)
	var panel := _place("NotificationPanel.objective", 1)
	await _settle()
	var editor: CanvasLayer = auto_free(LayoutEditor.new())
	scene.add_child(editor)
	await _settle()
	var frame: Control = editor.frame_of("NotificationPanel.objective")
	assert_object(frame).is_not_null()
	assert_bool(frame.visible).is_true()
	assert_vector(frame.global_position).is_equal_approx(_rect(panel).position, Vector2(1, 1))
	# Arrastre simulado: pulsar, mover 100 px abajo, soltar.
	editor._drag_id = "NotificationPanel.objective"
	editor._drag_mouse0 = Vector2(600, 80)
	editor._drag_off0 = Vector2.ZERO
	editor._drag_rect0 = _rect(panel)
	editor._drag_to(Vector2(600, 180), true)
	await _settle()
	var off := UILayoutManager.get_user_offset("NotificationPanel.objective")
	assert_float(off.y).is_equal_approx(96.0, 8.1)
	editor.finish()

func test_the_editor_hides_upper_layers_and_gives_them_back() -> void:
	var scene: Node = auto_free(Node.new())
	add_child(scene)
	var modal: CanvasLayer = auto_free(CanvasLayer.new())
	modal.layer = 20
	scene.add_child(modal)
	var hud: CanvasLayer = auto_free(CanvasLayer.new())
	hud.layer = 10
	scene.add_child(hud)
	var editor: CanvasLayer = LayoutEditor.new()
	scene.add_child(editor)
	var hidden_during := not modal.visible
	var hud_during := hud.visible
	editor.finish()
	assert_bool(hidden_during).is_true()
	assert_bool(hud_during).is_true()
	assert_bool(modal.visible).is_true()

# ── Tablet 4:3: la columna central no pisa la izquierda ─────────────

@warning_ignore("unused_parameter")
func test_the_center_column_never_overlaps_the_left_one(width: float, height: float, test_parameters := [
		[960.0, 720.0], [1024.0, 768.0], [1002.0, 626.0], [1100.0, 720.0], [1280.0, 720.0], [1280.0, 960.0], [1706.0, 720.0]]) -> void:
	UILayoutManager._viewport_size = Vector2(width, height)
	UILayoutManager._reapply_all()
	var resources := _place("ResourceHUD", 2)
	var status := _place("NotificationPanel.status", 4)
	var storm := _place("StormHUD", 1)
	var objective := _place("NotificationPanel.objective", 2)
	await _settle()
	for left in [resources, status]:
		for center in [storm, objective]:
			assert_bool(_rect(left).intersects(_rect(center))) \
				.override_failure_message("%dx%d: %s pisa %s" % [width, height, _rect(left), _rect(center)]).is_false()
	for c in [resources, status, storm, objective]:
		assert_float(_rect(c).end.x).is_less_equal(width)
	# Y lo centrado no se mete bajo el menu ☰ (176 px a la derecha).
	for center in [storm, objective]:
		assert_float(_rect(center).end.x).is_less_equal(width - UILayoutConfig.SIDEBAR_BTN_WIDTH - 10.0)

func test_a_4_3_tablet_moves_only_the_column_not_the_build_button() -> void:
	UILayoutManager._viewport_size = Vector2(1024, 768)
	assert_bool(UILayoutManager.is_column_narrow()).is_true()
	assert_bool(UILayoutManager.is_narrow()).is_false()
	assert_str(String(UILayoutManager.get_slot("storm_banner").get("stack_after", ""))).is_equal("NotificationPanel.status")
	assert_int(int(UILayoutManager.get_slot("bottom_center")["margin"]["bottom"])).is_equal(int(UILayoutConfig.SLOTS["bottom_center"]["margin"]["bottom"]))

func test_a_help_tip_follows_the_panel_it_explains() -> void:
	UILayoutManager._viewport_size = Vector2(1280, 720)
	var objective := _place("NotificationPanel.objective", 1)
	var tip := _place("HelperPanel.tip_objective", 1)
	await _settle()
	UILayoutManager.set_user_offset("NotificationPanel.objective", Vector2(0, 320))
	await _settle()
	assert_float(_rect(tip).position.y).is_greater_equal(_rect(objective).end.y)
	assert_float(_rect(tip).position.y - _rect(objective).end.y).is_less_equal(9.0)

func test_toasts_are_capped_so_they_do_not_climb_over_the_column() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/NotificationPanel.tscn").instantiate())
	add_child(panel)
	for i in 6:
		panel._show_toast("aviso %d" % i, UITheme.INFO)
	var alive: Array = panel._toast_container.get_children().filter(func(c): return not c.is_queued_for_deletion())
	assert_int(alive.size()).is_equal(panel.MAX_TOASTS)
	UILayoutManager._viewport_size = Vector2(400, 720)
	panel._show_toast("uno mas", UITheme.INFO)
	alive = panel._toast_container.get_children().filter(func(c): return not c.is_queued_for_deletion())
	assert_int(alive.size()).is_equal(panel.MAX_TOASTS_NARROW)

## Era 3 / Sandbox: los cuatro recursos y el LIMPIAR de desarrollo ensanchan la
## barra por encima de sus 300 px. La pausa va a la derecha del ancho REAL y la
## Tormenta y el objetivo no la pisan (bajan a la izquierda si no caben).
@warning_ignore("unused_parameter")
func test_four_resources_push_the_pause_and_the_center_column_aside(width: float, height: float, test_parameters := [
		[1280.0, 720.0], [1024.0, 768.0], [960.0, 720.0]]) -> void:
	var unlock_state := ResourceManager.get_unlock_state()
	var saved_dev := GameConfig.dev_mode
	GameConfig.dev_mode = true
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": true})
	UILayoutManager._viewport_size = Vector2(width, height)
	UILayoutManager._reapply_all()
	var hud: CanvasLayer = auto_free(load("res://scenes/ui/ResourceHUD.tscn").instantiate())
	add_child(hud)
	var status := _place("NotificationPanel.status", 4)
	var storm := _place("StormHUD", 1)
	var objective := _place("NotificationPanel.objective", 2)
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/PauseMenu.tscn").instantiate())
	add_child(menu)
	await _settle()
	await _settle()
	var res_rect := _rect(hud._panel)
	var pause_rect := _rect(menu.pause_button())
	ResourceManager.set_unlock_state(unlock_state)
	GameConfig.dev_mode = saved_dev
	var tag := "%dx%d res=%s pausa=%s" % [width, height, res_rect, pause_rect]
	assert_bool(pause_rect.intersects(res_rect)).override_failure_message(tag).is_false()
	assert_float(pause_rect.end.x).override_failure_message(tag).is_less_equal(width)
	for c in [storm, objective]:
		assert_bool(_rect(c).intersects(pause_rect)).override_failure_message("%s centro=%s" % [tag, _rect(c)]).is_false()
		assert_bool(_rect(c).intersects(res_rect)).override_failure_message("%s centro=%s" % [tag, _rect(c)]).is_false()
		assert_bool(_rect(c).intersects(_rect(status))).override_failure_message("%s centro=%s" % [tag, _rect(c)]).is_false()

func test_on_a_4_3_tablet_toasts_leave_the_left_column() -> void:
	UILayoutManager._viewport_size = Vector2(960, 720)
	var slot := UILayoutManager.get_slot("toast_area")
	assert_float((slot["anchor"] as Rect2).position.x).is_equal(0.5)
	UILayoutManager._viewport_size = Vector2(1280, 720)
	assert_float((UILayoutManager.get_slot("toast_area")["anchor"] as Rect2).position.x).is_equal(0.0)
