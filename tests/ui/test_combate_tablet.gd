extends GdUnitTestSuite
## QA de tablet (2026-10-26): la tarjeta del combate guiado no tapa el tablero
## y los botones del combate miden 48 px de lienzo con el dedo.

const TP := preload("res://scripts/ui/TutorialPanel.gd")
const BS := preload("res://scripts/ui/BattleScreen.gd")

## Una tarjeta de texto: a menos ancho, mas alta.
func _height(w: float) -> float:
	return 130.0 * 460.0 / w

func test_on_a_tablet_the_card_goes_beside_the_board() -> void:
	var vp := Vector2(1113, 696)
	var board := Rect2(357, 210, 400, 400)
	var focus := Rect2(400, 520, 50, 50)
	var spot := TP.combat_spot_off_board(vp, board, 200.0, 640.0, focus, [], _height)
	assert_bool(spot.is_empty()).is_false()
	var card := Rect2(spot["pos"], Vector2(spot["w"], _height(spot["w"])))
	assert_bool(card.intersects(board)).is_false()
	assert_float(card.position.y).is_greater_equal(200.0)
	assert_float(card.end.y).is_less_equal(640.0)
	assert_float(card.position.x).is_greater_equal(TP.EDGE)
	# Del lado del foco (a la izquierda del centro del tablero).
	assert_float(card.end.x).is_less_equal(board.position.x)

func test_the_unit_card_on_the_left_sends_it_to_the_right() -> void:
	var vp := Vector2(1113, 696)
	var board := Rect2(357, 210, 400, 400)
	var unit_card := Rect2(16, 200, 320, 440)
	var spot := TP.combat_spot_off_board(vp, board, 200.0, 640.0, Rect2(400, 520, 50, 50), [unit_card], _height)
	assert_bool(spot.is_empty()).is_false()
	assert_float(Vector2(spot["pos"]).x).is_greater_equal(board.end.x)

func test_on_a_wide_pc_screen_it_keeps_its_full_width() -> void:
	var spot := TP.combat_spot_off_board(Vector2(1920, 1080), Rect2(660, 240, 600, 600), 220.0, 980.0,
		Rect2(700, 700, 60, 60), [], _height)
	assert_float(float(spot["w"])).is_equal(TP.CARD_WIDTH)

func test_with_no_room_around_the_board_it_gives_up() -> void:
	# Vista Frente: el tablero ocupa toda la pantalla; se coloca junto al foco.
	var vp := Vector2(1113, 696)
	var spot := TP.combat_spot_off_board(vp, Rect2(0, 100, 1113, 560), 200.0, 640.0, Rect2(400, 300, 80, 80), [], _height)
	assert_bool(spot.is_empty()).is_true()

func test_on_a_phone_a_narrow_side_card_still_fits() -> void:
	var vp := Vector2(800, 360)
	var board := Rect2(250, 50, 300, 260)
	var spot := TP.combat_spot_off_board(vp, board, 40.0, 320.0, Rect2(260, 260, 36, 36),
		[], func(w: float) -> float: return 70.0 * 460.0 / w)
	assert_bool(spot.is_empty()).is_false()
	var card := Rect2(spot["pos"], Vector2(spot["w"], 70.0 * 460.0 / float(spot["w"])))
	assert_bool(card.intersects(board)).is_false()

func test_combat_buttons_are_48_px_with_a_finger() -> void:
	var saved := GameConfig.ui_touch_controls
	GameConfig.ui_touch_controls = "always"
	assert_int(BS.action_height(false)).is_greater_equal(48)
	assert_int(BS.action_height(true)).is_greater_equal(48)
	GameConfig.ui_touch_controls = "never"
	assert_int(BS.action_height(true)).is_greater_equal(48)
	GameConfig.ui_touch_controls = saved

# ── Telefono apaisado (QA de telefono, 2026-10-26) ───────────────────

func test_low_canvas_is_only_short_and_wide() -> void:
	assert_bool(BS.is_low_canvas(Vector2(640, 360))).is_true()
	assert_bool(BS.is_low_canvas(Vector2(800, 360))).is_true()
	assert_bool(BS.is_low_canvas(Vector2(1113, 696))).is_false()
	assert_bool(BS.is_low_canvas(Vector2(400, 720))).is_false()

func _phone_screen(size: Vector2i) -> CanvasLayer:
	var sub: SubViewport = auto_free(SubViewport.new())
	sub.size = size
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(sub)
	var screen: CanvasLayer = load("res://scenes/ui/BattleScreen.tscn").instantiate()
	sub.add_child(screen)
	return screen

func test_at_640x360_header_board_and_buttons_all_fit() -> void:
	CombatManager.reset()
	var screen := _phone_screen(Vector2i(640, 360))
	await await_idle_frame()
	var mine: Array = [CombatUnit.create(1, "infantry", Encounter.PLAYER, 1.0)]
	CombatManager.start_encounter_with_units(mine, {"infantry": 2, "artillery": 1}, false, 0, false, [1])
	for i in 4:
		await await_idle_frame()
	var vp := Rect2(Vector2.ZERO, Vector2(640, 360)).grow(1.0)
	assert_bool(screen.is_low_layout()).is_true()
	# Casillas de al menos 38 (antes 34 y fuera de la pantalla los botones).
	assert_int(screen._cell_size).is_greater_equal(38)
	var grid_rect: Rect2 = screen._grid.get_global_rect()
	assert_bool(vp.encloses(grid_rect)).override_failure_message(str(grid_rect)).is_true()
	for b in screen._actions_row.get_children():
		var btn := b as Control
		if not btn.visible:
			continue
		var r := btn.get_global_rect()
		assert_bool(vp.encloses(r)).override_failure_message("%s %s" % [btn.name, r]).is_true()
		assert_bool(r.intersects(grid_rect)).override_failure_message(String(btn.name)).is_false()
	var header: Rect2 = screen._header_margin.get_global_rect()
	assert_bool(vp.encloses(header)).override_failure_message(str(header)).is_true()
	assert_bool(header.intersects(grid_rect)).is_false()
	screen.queue_free()
	CombatManager.end_encounter()
	CombatManager.reset()
