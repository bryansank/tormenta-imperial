extends GdUnitTestSuite
## Las dos vistas del combate (docs/15 §3, "Las dos vistas"): la frontal (por
## defecto) y el tablero 8x8. Lo que se vigila:
##
##   * la preferencia es del dispositivo: settings.cfg [interfaz] combat_view, y
##     un valor desconocido vuelve a "front";
##   * el selector de Ajustes y el boton de la cabecera la cambian, este ultimo
##     tambien con la pelea abierta, sin rehacer las piezas;
##   * el frente no pinta casillas: sitios libres con desorden y manchas en el
##     suelo; su "acercate y dispara" acaba en las mismas llamadas del modelo;
##   * en calidad minima va el tablero (la vista mas barata);
##   * jugada igual, una pelea da EXACTAMENTE lo mismo en las dos vistas.
##
## En headless el estilo automatico es "2d"; aqui se fuerza "3d".

const SettingsParking := preload("res://tests/save/settings_parking.gd")
const Orders := preload("res://scripts/combat_view/FrontOrders.gd")
const BoardScript := preload("res://scripts/combat_view/Board3D.gd")
const Layout := preload("res://scripts/combat_view/BoardLayout3D.gd")

var _parked: Dictionary
var _delay: float

func before_test() -> void:
	_parked = SettingsParking.park()
	CombatManager.reset()
	_delay = GameConfig.combat_ai_step_delay
	GameConfig.combat_ai_step_delay = 0.01
	GameConfig.set_game_speed(2.0)

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()
	GameConfig.combat_ai_step_delay = _delay
	GameConfig.set_game_speed(1.0)
	get_tree().root.disable_3d = false
	SettingsParking.restore(_parked)

func _screen(view := "") -> CanvasLayer:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	screen.force_board_style("3d")
	if view != "":
		screen.force_combat_view(view)
	return screen

func _open_fight() -> void:
	var units: Array = [CombatUnit.create(501, "infantry", Encounter.PLAYER), CombatUnit.create(502, "infantry", Encounter.PLAYER)]
	CombatManager.start_encounter_with_units(units, {"infantry": 1})

func _until_idle(board, frames := 1200) -> void:
	var guard := 0
	while board.is_busy() and guard < frames:
		guard += 1
		await get_tree().process_frame

func _until_player_ready(screen, frames := 2000) -> void:
	var guard := 0
	while guard < frames and CombatManager.is_in_encounter() and \
			(not CombatManager.is_player_turn() or screen.board3d().board.is_busy()):
		guard += 1
		await get_tree().process_frame

# ── La preferencia ───────────────────────────────────────────────────

func test_the_front_view_is_the_default() -> void:
	assert_array(GameConfig.COMBAT_VIEWS).contains(["front", "board"])
	GameConfig.ui_combat_view = "front"
	var screen := _screen()
	assert_str(screen.combat_view()).is_equal("front")

func test_the_view_persists_in_settings_cfg_and_not_in_the_save() -> void:
	GameConfig.ui_combat_view = "front"
	assert_bool(GameConfig.set_combat_view("board")).is_true()
	var cf := ConfigFile.new()
	assert_int(cf.load(GameConfig.USER_SETTINGS_PATH)).is_equal(OK)
	assert_str(String(cf.get_value("interfaz", "combat_view", ""))).is_equal("board")
	# Releerlo devuelve lo guardado.
	GameConfig.ui_combat_view = "front"
	GameConfig.load_user_settings()
	assert_str(GameConfig.ui_combat_view).is_equal("board")
	# Un valor desconocido no se acepta, y uno escrito a mano vuelve a "front".
	assert_bool(GameConfig.set_combat_view("isometrica")).is_false()
	cf.set_value("interfaz", "combat_view", "isometrica")
	cf.save(GameConfig.USER_SETTINGS_PATH)
	GameConfig.load_user_settings()
	assert_str(GameConfig.ui_combat_view).is_equal("front")
	# Nada de esto viaja en la partida.
	assert_bool(JSON.stringify(CombatManager.get_save_data()).contains("combat_view")).is_false()

func test_settings_offers_the_selector() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/SettingsPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	var row := panel.find_child("CombatViewRow", true, false)
	assert_object(row).is_not_null()
	var picker = row.find_child("Picker", true, false)
	assert_int(picker.item_count).is_equal(2)
	picker.item_selected.emit(1)
	assert_str(GameConfig.ui_combat_view).is_equal("board")
	picker.item_selected.emit(0)
	assert_str(GameConfig.ui_combat_view).is_equal("front")

func test_the_labels_exist_in_both_languages() -> void:
	for key in ["LBL_COMBAT_VIEW", "OPT_COMBAT_VIEW_FRONT", "OPT_COMBAT_VIEW_BOARD",
			"LBL_COMBAT_VIEW_TIP", "BTN_ADVANCE", "MSG_HELD_NOTICES"]:
		for locale in ["es", "en"]:
			assert_bool(Tr._STRINGS[locale].has(key)).override_failure_message("%s/%s" % [key, locale]).is_true()

# ── El frente en pantalla ────────────────────────────────────────────

func test_the_front_view_lights_spots_not_cells_and_shows_advance() -> void:
	var screen := _screen("front")
	_open_fight()
	var board = screen.board3d().board
	assert_str(board.style()).is_equal("front")
	# Las marcas son manchas (discos), no el marco cuadrado de las casillas.
	assert_object(board._marks.multimesh.mesh).is_same(BoardScript._front_spot_mesh())
	await _until_player_ready(screen)
	var active := CombatManager.get_active_unit()
	var moves: Array = CombatManager.get_valid_moves(active.uid)
	for cell in moves:
		assert_int(board.mark_at(cell)).is_equal(BoardScript.Mark.MOVE)
	# Turno y objetivos no se pintan en el suelo (los dicen los aros).
	assert_int(board.mark_at(active.position)).is_equal(BoardScript.Mark.NONE)
	assert_bool(screen.advance_button().visible).is_true()
	assert_bool(screen.view_button().visible).is_true()

func test_front_pieces_stand_on_free_spots_and_bigger() -> void:
	var screen := _screen("front")
	_open_fight()
	var board = screen.board3d().board
	await _until_idle(board)
	for unit in CombatManager.get_units():
		var toy: Node3D = board.toy(unit.uid)
		var spot: Vector3 = Layout.cell_to_world(unit.position, CombatManager.get_board_size()) 			+ Layout.spot_offset(unit.position, board._seed)
		assert_float(toy.position.distance_to(spot)).is_less(0.01)
		# El sitio sigue dentro de su casilla: tocarlo es tocar la casilla.
		assert_vector(Layout.world_to_cell(spot, CombatManager.get_board_size())).is_equal(unit.position)
		assert_float(toy.get_node("Lift").scale.x).is_equal_approx(BoardScript.FRONT_UNIT_SCALE, 0.001)

func test_minimal_quality_uses_the_board_without_touching_the_preference() -> void:
	var saved_q := GameConfig.ui_graphics_quality
	GameConfig.ui_combat_view = "front"
	GameConfig.ui_graphics_quality = "minimal"
	var screen := _screen()
	assert_str(screen.combat_view()).is_equal("board")
	assert_str(GameConfig.ui_combat_view).is_equal("front")
	GameConfig.ui_graphics_quality = saved_q

func test_the_board_view_keeps_its_cells_and_hides_advance() -> void:
	var screen := _screen("board")
	_open_fight()
	var board = screen.board3d().board
	assert_str(board.style()).is_equal("board")
	assert_bool(board._marks.visible).is_true()
	await _until_player_ready(screen)
	assert_bool(screen.advance_button().visible).is_false()

func test_the_header_button_switches_mid_fight_and_saves_the_preference() -> void:
	GameConfig.ui_combat_view = "front"
	var screen := _screen()
	_open_fight()
	var board = screen.board3d().board
	await _until_idle(board)
	var toys_before: int = board.toy_count()
	screen.view_button().pressed.emit()
	await _until_idle(board)
	assert_str(GameConfig.ui_combat_view).is_equal("board")
	assert_str(board.style()).is_equal("board")
	# Las piezas siguen donde dice el modelo: no se ha rehecho la pelea.
	assert_int(board.toy_count()).is_equal(toys_before)
	for unit in CombatManager.get_units():
		if unit.is_alive():
			assert_vector(board.shown_cell(unit.uid)).is_equal(unit.position)
	screen.view_button().pressed.emit()
	await _until_idle(board)
	assert_str(GameConfig.ui_combat_view).is_equal("front")
	assert_str(board.style()).is_equal("front")

func test_tapping_an_enemy_in_front_closes_in_and_attacks() -> void:
	var screen := _screen("front")
	_open_fight()
	await _until_player_ready(screen)
	var active := CombatManager.get_active_unit()
	var target_uid := -1
	for uid in Orders.reachable_targets(CombatManager.get_encounter(), active.uid):
		target_uid = int(uid)
	if target_uid < 0:
		# Nadie a mano: AVANZAR acerca a la unidad sin atacar.
		var from := active.position
		screen.advance_button().pressed.emit()
		assert_vector(active.position).is_not_equal(from)
		return
	var target := CombatManager.get_unit(target_uid)
	var hp_before := target.hp
	screen._on_cell_pressed(target.position)
	assert_int(target.hp).is_less(hp_before)
	assert_bool(active.has_acted).is_true()

# -- Placas y etiquetas de objetivo en el frente (2026-10-16) -----------

## Abre una artilleria nuestra contra un blindado (buen objetivo) y una
## infanteria (malo) en la vista pedida; devuelve [screen, board, gun, tank, foot].
func _open_matchup(view: String) -> Array:
	var screen := _screen(view)
	var units: Array = [CombatUnit.create(601, "artillery", Encounter.PLAYER)]
	CombatManager.start_encounter_with_units(units, {"vehicle": 1, "infantry": 1})
	var board = screen.board3d().board
	await _until_player_ready(screen)
	var tank: CombatUnit = null
	var foot: CombatUnit = null
	for u in CombatManager.get_units():
		if u.unit_id == "vehicle":
			tank = u
		elif u.unit_id == "infantry":
			foot = u
	return [screen, board, CombatManager.get_unit(601), tank, foot]

## En el frente las piezas van juntas: la etiqueta de objetivo solo sale sobre
## el enemigo bajo el puntero o el dedo, nunca en todos a la vez.
func test_front_shows_the_target_label_only_on_the_focused_enemy() -> void:
	var opened: Array = await _open_matchup("front")
	var screen = opened[0]
	var board = opened[1]
	var gun: CombatUnit = opened[2]
	var tank: CombatUnit = opened[3]
	var foot: CombatUnit = opened[4]
	var targets: Array = [tank.uid, foot.uid]
	board.show_state(gun.uid, [], targets, screen.target_hints(gun, targets), {tank.uid: "-18 de 75", foot.uid: "-6 de 100"})
	assert_str(board.toy(tank.uid).target_hint_text()).is_empty()
	assert_str(board.toy(foot.uid).target_hint_text()).is_empty()
	# Los aros y la mira siguen en todos.
	assert_bool(board.toy(tank.uid).is_targeted()).is_true()
	assert_bool(board.toy(foot.uid).is_targeted()).is_true()
	board.set_hover(board.shown_cell(tank.uid))
	assert_int(board.focus_uid()).is_equal(tank.uid)
	assert_str(board.toy(tank.uid).target_hint_text()).contains(Tr.t("LBL_GOOD_TARGET"))
	assert_str(board.toy(tank.uid).target_hint_text()).contains("-18 de 75")
	assert_str(board.toy(foot.uid).target_hint_text()).is_empty()
	board.set_hover(board.shown_cell(foot.uid))
	assert_str(board.toy(tank.uid).target_hint_text()).is_empty()
	assert_str(board.toy(foot.uid).target_hint_text()).contains(Tr.t("LBL_BAD_TARGET"))
	board.set_hover(Vector2i(-1, -1))
	assert_int(board.focus_uid()).is_equal(-1)
	assert_str(board.toy(foot.uid).target_hint_text()).is_empty()

## En el frente la placa del foco y la de la unidad activa van enteras; las
## demas, compactas. En el tablero 8x8 todas enteras, sin subir ni apagarse.
func test_front_plates_are_compact_except_the_focus_and_the_board_keeps_them() -> void:
	var opened: Array = await _open_matchup("front")
	var screen = opened[0]
	var board = opened[1]
	var gun: CombatUnit = opened[2]
	var tank: CombatUnit = opened[3]
	var foot: CombatUnit = opened[4]
	var targets: Array = [tank.uid, foot.uid]
	board.show_state(gun.uid, [], targets, screen.target_hints(gun, targets))
	assert_float(board.toy(gun.uid).plate_scale()).is_equal(1.0)
	assert_float(board.toy(tank.uid).plate_scale()).is_less(1.0)
	board.set_hover(board.shown_cell(tank.uid))
	assert_float(board.toy(tank.uid).plate_scale()).is_equal(1.0)
	assert_float(board.toy(foot.uid).plate_scale()).is_less(1.0)
	board.set_style(BoardScript.STYLE_BOARD)
	for uid in [gun.uid, tank.uid, foot.uid]:
		assert_float(board.toy(uid).plate_scale()).is_equal(1.0)
		# Resta de dos alturas en coma flotante: cero con su ruido.
		assert_float(board.toy(uid).plate_lift()).is_equal_approx(0.0, 0.0001)
		assert_bool(board.toy(uid).is_plate_dimmed()).is_false()
	# Y en el tablero vuelven las etiquetas en todos los objetivos.
	board.show_state(gun.uid, [], targets, screen.target_hints(gun, targets))
	assert_str(board.toy(tank.uid).target_hint_text()).is_equal(Tr.t("LBL_GOOD_TARGET"))
	assert_str(board.toy(foot.uid).target_hint_text()).is_equal(Tr.t("LBL_BAD_TARGET"))

# ── La misma pelea en las dos vistas ─────────────────────────────────

## Juega una pelea entera con una politica fija y devuelve el resultado. En el
## tablero se juega a toques (casilla de destino, casilla del objetivo); en el
## frente con las ordenes del frente (tocar al enemigo, AVANZAR). La politica
## es la misma: el primer enemigo al que se llega, o avanzar y defender.
func _play_fight(view: String) -> Dictionary:
	CombatManager.reset()
	var screen := _screen(view)
	_open_fight()
	var board = screen.board3d().board
	var guard := 0
	while CombatManager.is_in_encounter() and guard < 200:
		guard += 1
		await _until_player_ready(screen)
		if not CombatManager.is_in_encounter():
			break
		var active := CombatManager.get_active_unit()
		var enc := CombatManager.get_encounter()
		var targets: Array = Orders.reachable_targets(enc, active.uid)
		if not targets.is_empty():
			var target := CombatManager.get_unit(int(targets[0]))
			if view == "front":
				screen._on_cell_pressed(target.position)
			else:
				var cell: Vector2i = Orders.approach_cell(enc, active.uid, target.uid)
				if cell != active.position:
					screen._on_cell_pressed(cell)
					await _until_idle(board)
				screen._on_cell_pressed(target.position)
		else:
			var cell: Vector2i = Orders.advance_cell(enc, active.uid)
			if cell != Orders.NO_CELL:
				if view == "front":
					screen._act_advance()
				else:
					screen._on_cell_pressed(cell)
				await _until_idle(board)
			screen._act_defend()
	await _until_idle(board)
	var hp := {}
	for unit in CombatManager.get_units():
		hp[unit.uid] = unit.hp
	var out := {"won": CombatManager.get_encounter().player_won(), "round": CombatManager.get_round(), "hp": hp}
	CombatManager.end_encounter()
	return out

func test_both_views_resolve_the_same_encounter_the_same_way() -> void:
	# El azar del dano (feat/ritmo-colono) va sembrado: con la misma semilla, el
	# mismo tablero sale igual en las dos vistas.
	CombatManager.forced_fight_seed = 4242
	var on_board: Dictionary = await _play_fight("board")
	var on_front: Dictionary = await _play_fight("front")
	CombatManager.forced_fight_seed = 0
	assert_bool(on_front["won"]).is_equal(on_board["won"])
	assert_int(on_front["round"]).is_equal(on_board["round"])
	assert_dict(on_front["hp"]).is_equal(on_board["hp"])

# ── Terreno ──────────────────────────────────────────────────────────

func test_the_front_field_builds_for_every_scene() -> void:
	var terrain := preload("res://scripts/combat_view/BoardTerrain3D.gd")
	for scene in terrain.SCENES:
		for simple in [false, true]:
			var mesh: ArrayMesh = terrain.build(Vector2i(8, 8), 5, simple, scene, true)
			assert_object(mesh).is_not_null()
			assert_int(mesh.get_surface_count()).is_greater(0)
