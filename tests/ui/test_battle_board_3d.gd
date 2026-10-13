extends GdUnitTestSuite
## El tablero 3D (docs/15 §3, "El tablero 3D"): la maqueta que cuenta la pelea
## con unidades de juguete. Lo que se vigila aqui es lo que la hace segura:
##
##   * que es VISTA: las reglas no cambian y lo que ensena acaba siempre donde
##     dice el modelo;
##   * que mientras anima no se puede jugar ni sale el parte (nunca se actua
##     sobre algo que aun no se ha visto);
##   * que elige 2D donde toca (sin pantalla, vista 2D del mapa);
##   * el presupuesto de las piezas horneadas y el campo `domain` para mar/aire.
##
## En headless el estilo automatico es "2d"; aqui se fuerza "3d" a proposito
## (el SubViewport y los tweens corren igual sin GPU).

const Layout := preload("res://scripts/combat_view/BoardLayout3D.gd")
const Models := preload("res://scripts/combat_view/UnitModels3D.gd")
const BattleScreenScript := preload("res://scripts/ui/BattleScreen.gd")
const BoardScript := preload("res://scripts/combat_view/Board3D.gd")

var _delay: float

func before_test() -> void:
	CombatManager.reset()
	_delay = GameConfig.combat_ai_step_delay
	GameConfig.combat_ai_step_delay = 0.01

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()
	GameConfig.combat_ai_step_delay = _delay
	get_tree().root.disable_3d = false

# ── Utilidades ───────────────────────────────────────────────────────

func _screen_3d() -> CanvasLayer:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	screen.force_board_style("3d")
	return screen

## Abre una pelea pequena: dos infanterias nuestras contra una suya.
func _open_fight() -> void:
	var units: Array = [CombatUnit.create(501, "infantry", Encounter.PLAYER), CombatUnit.create(502, "infantry", Encounter.PLAYER)]
	CombatManager.start_encounter_with_units(units, {"infantry": 1})

func _until_idle(board, frames := 900) -> void:
	var guard := 0
	while board.is_busy() and guard < frames:
		guard += 1
		await get_tree().process_frame

## Espera a que el enemigo termine y la maqueta lo cuente: turno del jugador quieto.
func _until_player_ready(screen, frames := 1500) -> void:
	var guard := 0
	while guard < frames and (not CombatManager.is_player_turn() or screen.board3d().board.is_busy()):
		guard += 1
		await get_tree().process_frame

# ── Reglas puras de la vista ─────────────────────────────────────────

func test_the_board_is_3d_except_headless_and_in_the_2d_map_view() -> void:
	assert_str(BattleScreenScript.pick_board_style("headless", "3d", "high")).is_equal("2d")
	assert_str(BattleScreenScript.pick_board_style("Windows", "2d", "high")).is_equal("2d")
	for q in ["high", "low", "minimal"]:
		assert_str(BattleScreenScript.pick_board_style("Windows", "3d", q)).is_equal("3d")
		assert_str(BattleScreenScript.pick_board_style("Android", "3d", q)).is_equal("3d")

func test_cells_and_world_points_round_trip() -> void:
	var board := Vector2i(8, 8)
	for y in board.y:
		for x in board.x:
			var c := Vector2i(x, y)
			var p := Layout.cell_to_world(c, board)
			assert_vector(Layout.world_to_cell(p, board)).is_equal(c)
			assert_vector(Layout.world_to_cell(p + Vector3(0.9, 0, -0.9), board)).is_equal(c)
	assert_vector(Layout.world_to_cell(Vector3(100, 0, 0), board)).is_equal(Vector2i(-1, -1))
	# El jugador (filas de abajo) queda delante de la camara, la Regencia al fondo.
	assert_float(Layout.cell_to_world(Vector2i(0, 7), board).z).is_greater(Layout.cell_to_world(Vector2i(0, 0), board).z)

func test_the_drawn_route_steps_one_cell_at_a_time_around_units() -> void:
	var board := Vector2i(8, 8)
	var blocked := {Vector2i(1, 0): true}
	var route: Array = Layout.path(Vector2i(0, 0), Vector2i(2, 0), blocked, board)
	assert_vector(route[0]).is_equal(Vector2i(0, 0))
	assert_vector(route[route.size() - 1]).is_equal(Vector2i(2, 0))
	assert_bool(route.has(Vector2i(1, 0))).is_false()
	for i in range(1, route.size()):
		assert_int(Layout.cell_distance(route[i - 1], route[i])).is_equal(1)
	# Sin hueco (no deberia pasar: el modelo ya movio) se salta directo.
	var walled := {Vector2i(1, 0): true, Vector2i(0, 1): true}
	assert_array(Layout.path(Vector2i(0, 0), Vector2i(2, 0), walled, board)).is_equal([Vector2i(0, 0), Vector2i(2, 0)])

func test_attack_animation_follows_the_unit_kind() -> void:
	assert_str(BoardScript.attack_kind("artillery", 3)).is_equal("shell")
	assert_str(BoardScript.attack_kind("infantry", 1)).is_equal("melee")
	assert_str(BoardScript.attack_kind("vehicle", 1)).is_equal("shot")

# ── Dominio (mar y aire, mas adelante) ───────────────────────────────

func test_every_unit_today_is_a_land_unit() -> void:
	for unit_id in ["infantry", "artillery", "vehicle"]:
		assert_str(String(GameConfig.get_combat_stats(unit_id).get("domain", ""))).is_equal("land")
		assert_str(CombatUnit.create(1, unit_id, 0).domain()).is_equal("land")
	# Una unidad sin la clave (o sin fila) es de tierra: nada cambia de formato.
	assert_str(CombatUnit.create(1, "no_such_unit", 0).domain()).is_equal(CombatUnit.DOMAIN_LAND)

func test_the_view_places_each_domain_at_its_height() -> void:
	assert_float(Layout.domain_height("land")).is_equal(0.0)
	assert_float(Layout.domain_height("air")).is_greater(1.0)
	assert_float(Layout.domain_height("sea")).is_less(0.0)
	assert_bool(Layout.domain_bobs("land")).is_false()
	assert_bool(Layout.domain_bobs("air")).is_true()
	assert_float(Layout.domain_height("algo_nuevo")).is_equal(0.0)

func test_domain_does_not_change_any_rule() -> void:
	# Mismo dano, mismo alcance, misma iniciativa con o sin el campo.
	var stats: Dictionary = GameConfig.combat_unit_stats["infantry"]
	var before := CombatUnit.create(1, "infantry", 0)
	var atk := before.attack_power()
	var rng := before.attack_range()
	stats.erase("domain")
	var without := CombatUnit.create(1, "infantry", 0)
	assert_int(without.attack_power()).is_equal(atk)
	assert_int(without.attack_range()).is_equal(rng)
	assert_str(without.domain()).is_equal("land")
	stats["domain"] = "land"

# ── Las piezas horneadas ─────────────────────────────────────────────

func test_every_unit_has_a_baked_toy_for_both_sides_within_budget() -> void:
	for unit_id in ["infantry", "artillery", "vehicle"]:
		for side in [0, 1]:
			var path := Models.scene_path(unit_id, side)
			assert_str(path).override_failure_message("falta %s del bando %d" % [unit_id, side]).is_not_empty()
			var node: MeshInstance3D = load(path).instantiate()
			assert_int(Models.tri_count(node.mesh)).is_less_equal(800)
			# Las nuestras llevan la superficie del color de la colonia; las de la
			# Regencia, su morado horneado.
			var team: int = node.mesh.surface_find_by_name(Models.TEAM_SURFACE)
			if side == 0:
				assert_int(team).is_greater_equal(0)
			else:
				assert_int(team).is_equal(-1)
			node.free()

func test_the_colony_color_is_one_shared_material_per_color() -> void:
	var a := Models.instantiate("infantry", 0, Color(0.3, 0.45, 0.62))
	var b := Models.instantiate("vehicle", 0, Color(0.3, 0.45, 0.62))
	var ia: int = (a as MeshInstance3D).mesh.surface_find_by_name(Models.TEAM_SURFACE)
	var ib: int = (b as MeshInstance3D).mesh.surface_find_by_name(Models.TEAM_SURFACE)
	assert_object((a as MeshInstance3D).get_surface_override_material(ia)).is_same((b as MeshInstance3D).get_surface_override_material(ib))
	a.free()
	b.free()

# ── La maqueta en la pantalla ────────────────────────────────────────

func test_a_3d_board_spawns_one_toy_per_living_unit() -> void:
	var screen := _screen_3d()
	_open_fight()
	assert_str(screen.board_style()).is_equal("3d")
	assert_object(screen.board3d()).is_not_null()
	var board = screen.board3d().board
	assert_int(board.toy_count()).is_equal(3)
	for unit in CombatManager.get_units():
		assert_vector(board.shown_cell(unit.uid)).is_equal(unit.position)
	# El 8x8 de botones no se usa: la maqueta lo sustituye.
	assert_bool(screen._grid_center.visible).is_false()

func test_nothing_can_be_played_while_the_board_is_animating() -> void:
	var screen := _screen_3d()
	_open_fight()
	var board = screen.board3d().board
	# Recien abierto la maqueta esta desplegando las piezas.
	assert_bool(board.is_busy()).is_true()
	assert_bool(screen._defend_btn.disabled).is_true()
	await _until_player_ready(screen)
	assert_bool(screen._defend_btn.disabled).is_false()
	var active := CombatManager.get_active_unit()
	var moves: Array = CombatManager.get_valid_moves(active.uid)
	assert_array(moves).is_not_empty()
	var to: Vector2i = moves[0]
	screen._on_cell_pressed(to)
	assert_vector(active.position).is_equal(to)
	assert_bool(board.is_busy()).is_true()
	# Un toque durante el salto no hace nada (ni mover ni atacar).
	for cell in CombatManager.get_valid_moves(active.uid):
		screen._on_cell_pressed(cell)
	assert_vector(active.position).is_equal(to)
	assert_bool(screen._wait_btn.disabled).is_true()

func test_the_toy_ends_where_the_model_says() -> void:
	var screen := _screen_3d()
	_open_fight()
	var board = screen.board3d().board
	await _until_player_ready(screen)
	var active := CombatManager.get_active_unit()
	var to: Vector2i = CombatManager.get_valid_moves(active.uid)[0]
	CombatManager.move_unit(active.uid, to)
	await _until_idle(board)
	var toy: Node3D = board.toy(active.uid)
	assert_vector(board.shown_cell(active.uid)).is_equal(to)
	assert_float(toy.position.distance_to(Layout.cell_to_world(to, CombatManager.get_board_size()))).is_less(0.01)

func test_the_report_waits_until_the_board_has_shown_the_fight() -> void:
	var screen := _screen_3d()
	_open_fight()
	var board = screen.board3d().board
	# El modelo resuelve: encounter_ended llega con la maqueta aun desplegando.
	assert_bool(board.is_busy()).is_true()
	screen._on_encounter_ended(true, 3)
	assert_bool(screen._result_panel.visible).is_false()
	await _until_idle(board)
	await get_tree().process_frame
	assert_bool(screen._result_panel.visible).is_true()

func test_hp_bar_counts_down_hit_by_hit() -> void:
	var screen := _screen_3d()
	_open_fight()
	var board = screen.board3d().board
	await _until_idle(board)
	var enemy: CombatUnit = null
	for u in CombatManager.get_units():
		if u.side == Encounter.ENEMY:
			enemy = u
	var toy = board.toy(enemy.uid)
	board.push({"e": "attack", "attacker": 501, "target": enemy.uid, "damage": 25})
	# La barra baja cuando el golpe LLEGA en la animacion, no antes.
	assert_int(toy.shown_hp).is_equal(enemy.hp)
	var guard := 0
	while toy.shown_hp == enemy.hp and guard < 600:
		guard += 1
		await get_tree().process_frame
	assert_int(toy.shown_hp).is_equal(enemy.hp - 25)
	await _until_idle(board, 900)
	# Tras la cola manda el modelo (que no ha recibido ese golpe): reconcilia.
	assert_int(toy.shown_hp).is_equal(enemy.hp)

func test_the_map_stops_drawing_3d_while_the_3d_board_covers_it() -> void:
	var screen := _screen_3d()
	_open_fight()
	assert_bool(get_viewport().disable_3d).is_true()
	screen._close_all()
	assert_bool(get_viewport().disable_3d).is_false()

func test_a_2d_board_keeps_the_classic_grid_and_the_map_3d() -> void:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	# Sin forzar, en headless: el tablero 2D de siempre.
	_open_fight()
	assert_str(screen.board_style()).is_equal("2d")
	assert_bool(screen._grid_center.visible).is_true()
	assert_int(screen._cells.size()).is_equal(64)
	assert_bool(get_viewport().disable_3d).is_false()
