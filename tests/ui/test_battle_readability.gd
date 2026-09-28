extends GdUnitTestSuite
## Lo que el tablero y el mapa decian solo con color o solo con tooltip:
##
##   * el riesgo de cada nodo del mapa va escrito debajo del nodo;
##   * con el dedo (sin tooltip) el primer toque arma el nodo y el segundo entra;
##   * aliado y enemigo se distinguen por FORMA, no solo por verde y rojo: marca
##     redonda arriba a la izquierda contra rombo arriba a la derecha en la
##     casilla, y ficha redonda contra cuadrada en la franja de iniciativa.

var _chosen: Array = []

func before_test() -> void:
	_chosen.clear()
	CombatManager.reset()

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()

func _screen() -> CanvasLayer:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	screen.map_node_chosen.connect(func(index): _chosen.append(index))
	return screen

## Con `start_cleared`, una columna que ya gano su primer nodo y elige el
## siguiente: desde integridad-combate no se sale de un nodo sin limpiar
## (Expedition.can_select), asi que los tests de elegir nodo lo necesitan.
func _run(start_cleared := false) -> Expedition:
	var run := Expedition.create(1, 4242, {"infantry": 2, "artillery": 1}, 70.0, 1)
	if start_cleared:
		run.current_node_data()["cleared"] = true
	return run

# ── Riesgo escrito ───────────────────────────────────────────────────

func test_every_node_writes_its_risk_under_it() -> void:
	var screen := _screen()
	await await_idle_frame()
	var run := _run()
	screen.open_map(run)
	assert_int(screen._map_risk_labels.size()).is_equal(run.map.size())
	for i in range(run.map.size()):
		var expected: String = screen._risk_text(int(run.map[i].get("risk", 0)))
		assert_str(screen._map_risk_labels[i].text).is_equal(expected)

func test_the_risk_label_sits_below_its_node() -> void:
	var screen := _screen()
	await await_idle_frame()
	screen.open_map(_run())
	var btn: Button = screen.map_button(0)
	var label: Label = screen._map_risk_labels[0]
	assert_float(label.position.y).is_greater_equal(btn.position.y + float(screen._node_size) - 0.5)
	# Y el lienzo tiene sitio para la ultima fila de etiquetas.
	assert_float(screen._map_canvas.custom_minimum_size.y).is_greater_equal(label.position.y + label.size.y - 0.5)

# ── Toque: armar y confirmar ─────────────────────────────────────────

func test_with_a_mouse_one_click_goes_in() -> void:
	var screen := _screen()
	await await_idle_frame()
	var run := _run(true)
	screen.open_map(run)
	var target: int = int(run.current_exits()[0])
	screen.map_button(target).pressed.emit()
	assert_array(_chosen).is_equal([target])

func test_with_a_finger_the_first_tap_only_arms_the_node() -> void:
	var screen := _screen()
	await await_idle_frame()
	var run := _run(true)
	screen.open_map(run)
	screen.set_touch_mode(true)
	var target: int = int(run.current_exits()[0])
	screen.map_button(target).pressed.emit()
	assert_array(_chosen).is_empty()
	assert_int(screen.armed_node()).is_equal(target)
	# La cabecera cuenta lo que diria el tooltip y pide el segundo toque.
	assert_str(screen._map_hint.text).contains(Tr.t("LBL_NODE_TAP_AGAIN"))
	assert_str(screen._map_hint.text).contains(screen._risk_text(int(run.map[target].get("risk", 0))))
	screen.map_button(target).pressed.emit()
	assert_array(_chosen).is_equal([target])
	assert_int(screen.armed_node()).is_equal(-1)

func test_tapping_another_node_moves_the_arm_instead_of_entering() -> void:
	var screen := _screen()
	await await_idle_frame()
	var run := _run(true)
	screen.open_map(run)
	var exits: Array = run.current_exits()
	if exits.size() < 2:
		return  # la semilla da una sola salida: no hay a donde cambiar
	screen.set_touch_mode(true)
	screen.map_button(int(exits[0])).pressed.emit()
	screen.map_button(int(exits[1])).pressed.emit()
	assert_array(_chosen).is_empty()
	assert_int(screen.armed_node()).is_equal(int(exits[1]))

func test_a_real_touch_switches_the_map_to_finger_mode() -> void:
	var screen := _screen()
	await await_idle_frame()
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	screen._input(touch)
	assert_bool(screen._touch_mode).is_true()
	var mouse := InputEventMouseButton.new()
	mouse.pressed = true
	mouse.device = 0
	screen._input(mouse)
	assert_bool(screen._touch_mode).is_false()

func test_the_emulated_mouse_of_a_touch_does_not_undo_finger_mode() -> void:
	var screen := _screen()
	await await_idle_frame()
	screen.set_touch_mode(true)
	var emulated := InputEventMouseButton.new()
	emulated.pressed = true
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	screen._input(emulated)
	assert_bool(screen._touch_mode).is_true()

# ── Bando sin color ──────────────────────────────────────────────────

func test_ally_and_enemy_cells_carry_different_shapes() -> void:
	var screen := _screen()
	screen._recalculate_cell_size()
	screen._build_grid()
	await await_idle_frame()
	var mark: Panel = screen.board_cell_mark(Vector2i(0, 0))
	screen._paint_side_mark(mark, CombatUnit.create(1, "infantry", 0, 1.0))
	var ally_side: String = String(mark.get_meta("side"))
	var ally_rotation: float = mark.rotation
	var ally_x: float = mark.position.x
	var ally_radius: int = (mark.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_top_left
	screen._paint_side_mark(mark, CombatUnit.create(2, "infantry", 1, 1.0))
	var enemy_radius: int = (mark.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_top_left
	assert_str(ally_side).is_equal("ally")
	assert_str(String(mark.get_meta("side"))).is_equal("enemy")
	# Circulo contra rombo, y en esquinas opuestas.
	assert_int(ally_radius).is_greater(0)
	assert_int(enemy_radius).is_equal(0)
	assert_float(ally_rotation).is_equal(0.0)
	assert_float(mark.rotation).is_not_equal(0.0)
	assert_float(mark.position.x).is_greater(ally_x)
	assert_bool(mark.visible).is_true()
	screen._paint_side_mark(mark, null)
	assert_bool(mark.visible).is_false()

func test_the_initiative_strip_uses_round_and_square_chips() -> void:
	var screen := _screen()
	await await_idle_frame()
	CombatManager.start_encounter({"infantry": 2}, {"infantry": 2})
	await await_idle_frame()
	var sides: Dictionary = {}
	for chip in screen.order_chips():
		var side: String = String(chip.get_meta("side", ""))
		var style: StyleBoxFlat = chip.get_theme_stylebox("normal")
		sides[side] = style.corner_radius_top_left
	assert_bool(sides.has("ally")).is_true()
	assert_bool(sides.has("enemy")).is_true()
	assert_int(int(sides["ally"])).is_greater(int(sides["enemy"]))
