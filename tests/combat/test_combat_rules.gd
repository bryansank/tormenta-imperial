extends GdUnitTestSuite
## Locks the combat maths in place. These formulas are the contract between the
## base and the battlefield: if they drift, balance drifts silently and nobody
## notices until a run feels wrong.
##
## Pure functions only — no nodes, no scene tree. Runs headless.

const Rules := preload("res://scripts/combat/CombatRules.gd")
const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")

const PLAYER := 0
const ENEMY := 1

func _unit(unit_id: String, side: int, uid: int = 1, scale: float = 1.0) -> CombatUnit:
	return CombatUnitScript.create(uid, unit_id, side, scale)

# ── Damage ───────────────────────────────────────────────────────────

func test_damage_is_attack_minus_defense() -> void:
	var attacker := _unit("infantry", PLAYER, 1)    # atk 8
	var target := _unit("infantry", ENEMY, 2)       # def 2
	assert_int(Rules.damage(attacker, target)).is_equal(6)

func test_damage_never_drops_below_one() -> void:
	# A dug-in tank still takes a scratch: a fight must never stall.
	var attacker := _unit("infantry", PLAYER, 1)    # atk 8
	var target := _unit("vehicle", ENEMY, 2)        # def 5
	target.defending = true                          # def 10 > atk 8
	assert_int(Rules.damage(attacker, target)).is_equal(1)

func test_defending_doubles_defense() -> void:
	var target := _unit("vehicle", ENEMY, 1)        # def 5
	assert_int(target.defense()).is_equal(5)
	target.defending = true
	assert_int(target.defense()).is_equal(10)

func test_defending_cuts_incoming_artillery_damage() -> void:
	var attacker := _unit("artillery", PLAYER, 1)   # atk 14
	var target := _unit("vehicle", ENEMY, 2)        # def 5
	assert_int(Rules.damage(attacker, target)).is_equal(9)
	target.defending = true                          # def 10
	assert_int(Rules.damage(attacker, target)).is_equal(4)

# ── Morale: the differentiator ───────────────────────────────────────

func test_morale_attack_modifier_spans_the_configured_range() -> void:
	var range_cfg: Vector2 = GameConfig.combat_morale_attack_range
	assert_float(Rules.morale_attack_mod(0.0)).is_equal_approx(range_cfg.x, 0.001)
	assert_float(Rules.morale_attack_mod(50.0)).is_equal_approx(1.0, 0.001)
	assert_float(Rules.morale_attack_mod(100.0)).is_equal_approx(range_cfg.y, 0.001)

func test_morale_attack_modifier_clamps_outside_zero_hundred() -> void:
	var range_cfg: Vector2 = GameConfig.combat_morale_attack_range
	assert_float(Rules.morale_attack_mod(-40.0)).is_equal_approx(range_cfg.x, 0.001)
	assert_float(Rules.morale_attack_mod(180.0)).is_equal_approx(range_cfg.y, 0.001)

func test_morale_initiative_bonus_is_symmetric_around_fifty() -> void:
	var span: int = GameConfig.combat_morale_initiative_bonus
	assert_int(Rules.morale_initiative_bonus(0.0)).is_equal(-span)
	assert_int(Rules.morale_initiative_bonus(50.0)).is_equal(0)
	assert_int(Rules.morale_initiative_bonus(100.0)).is_equal(span)

func test_morale_reaches_the_unit_attack_power() -> void:
	var low := _unit("infantry", PLAYER, 1)
	var high := _unit("infantry", PLAYER, 2)
	low.morale_attack_mod = Rules.morale_attack_mod(0.0)
	high.morale_attack_mod = Rules.morale_attack_mod(100.0)
	assert_int(high.attack_power()).is_greater(low.attack_power())

# ── Range: why positioning matters ───────────────────────────────────

func test_artillery_cannot_fire_at_an_adjacent_target() -> void:
	var gunner := _unit("artillery", PLAYER, 1)     # range 3, min_range 2
	var target := _unit("infantry", ENEMY, 2)
	gunner.position = Vector2i(3, 3)
	target.position = Vector2i(3, 4)                 # distance 1
	assert_bool(Rules.in_attack_range(gunner, target)).is_false()

func test_artillery_reaches_between_min_and_max_range() -> void:
	var gunner := _unit("artillery", PLAYER, 1)
	var target := _unit("infantry", ENEMY, 2)
	gunner.position = Vector2i(3, 3)
	for distance in [2, 3]:
		target.position = Vector2i(3, 3 + distance)
		assert_bool(Rules.in_attack_range(gunner, target)).is_true()
	target.position = Vector2i(3, 7)                 # distance 4, out of range
	assert_bool(Rules.in_attack_range(gunner, target)).is_false()

func test_infantry_only_reaches_adjacent_targets() -> void:
	var soldier := _unit("infantry", PLAYER, 1)     # range 1, min_range 1
	var target := _unit("infantry", ENEMY, 2)
	soldier.position = Vector2i(2, 2)
	target.position = Vector2i(2, 3)
	assert_bool(Rules.in_attack_range(soldier, target)).is_true()
	target.position = Vector2i(2, 4)
	assert_bool(Rules.in_attack_range(soldier, target)).is_false()

func test_manhattan_ignores_diagonals() -> void:
	assert_int(Rules.manhattan(Vector2i(0, 0), Vector2i(3, 4))).is_equal(7)
	assert_int(Rules.manhattan(Vector2i(2, 2), Vector2i(2, 2))).is_equal(0)

# ── Movement: BFS ────────────────────────────────────────────────────

func test_reachable_cells_stay_inside_the_board() -> void:
	var board := Vector2i(8, 8)
	var cells := Rules.reachable_cells(Vector2i(0, 0), 2, board, [])
	for cell in cells:
		assert_bool(Rules.in_board(cell, board)).is_true()
	# From a corner with move 2: 5 cells, origin excluded.
	assert_int(cells.size()).is_equal(5)

func test_reachable_cells_excludes_the_origin() -> void:
	var cells := Rules.reachable_cells(Vector2i(4, 4), 3, Vector2i(8, 8), [])
	assert_array(cells).not_contains([Vector2i(4, 4)])

func test_bfs_does_not_walk_through_units() -> void:
	# A wall across the row traps the unit in its half of the board.
	var board := Vector2i(8, 8)
	var wall: Array = []
	for x in range(board.x):
		wall.append(Vector2i(x, 3))
	var cells := Rules.reachable_cells(Vector2i(4, 4), 6, board, wall)
	for cell in cells:
		assert_bool(cell.y > 3).is_true()

func test_blocked_cells_are_never_returned_as_destinations() -> void:
	var blocked: Array = [Vector2i(4, 3), Vector2i(5, 4)]
	var cells := Rules.reachable_cells(Vector2i(4, 4), 3, Vector2i(8, 8), blocked)
	for cell in blocked:
		assert_array(cells).not_contains([cell])

func test_zero_move_range_reaches_nothing() -> void:
	assert_array(Rules.reachable_cells(Vector2i(4, 4), 0, Vector2i(8, 8), [])).is_empty()

# ── Turn order ───────────────────────────────────────────────────────

func test_turn_order_is_initiative_descending() -> void:
	var fast := _unit("infantry", PLAYER, 1)        # initiative 5
	var mid := _unit("vehicle", PLAYER, 2)          # initiative 4
	var slow := _unit("artillery", PLAYER, 3)       # initiative 3
	var order := Rules.build_turn_order([slow, mid, fast])
	assert_array(order).is_equal([1, 2, 3])

func test_turn_order_breaks_ties_in_favour_of_the_player() -> void:
	var enemy := _unit("infantry", ENEMY, 1)
	var player := _unit("infantry", PLAYER, 2)
	var order := Rules.build_turn_order([enemy, player])
	assert_int(order[0]).is_equal(2)                 # player first despite higher uid

func test_turn_order_skips_the_dead() -> void:
	var alive := _unit("infantry", PLAYER, 1)
	var dead := _unit("infantry", PLAYER, 2)
	dead.take_damage(dead.max_hp)
	var order := Rules.build_turn_order([alive, dead])
	assert_array(order).is_equal([1])

# ── Timeout: stalling is punished ────────────────────────────────────

func test_timeout_is_won_by_the_side_with_more_total_hp() -> void:
	var player := _unit("infantry", PLAYER, 1)
	var enemy := _unit("infantry", ENEMY, 2)
	enemy.take_damage(10)
	assert_int(Rules.resolve_timeout([player, enemy])).is_equal(PLAYER)

func test_timeout_tie_is_a_player_defeat() -> void:
	# Equal HP on both sides: the expedition punishes stalling, never rewards it.
	var player := _unit("infantry", PLAYER, 1)
	var enemy := _unit("infantry", ENEMY, 2)
	assert_int(Rules.resolve_timeout([player, enemy])).is_equal(ENEMY)

func test_timeout_ignores_dead_units() -> void:
	var player := _unit("infantry", PLAYER, 1)
	var dead_ally := _unit("vehicle", PLAYER, 2)
	dead_ally.take_damage(dead_ally.max_hp)
	var enemy := _unit("infantry", ENEMY, 3)
	enemy.take_damage(5)
	assert_int(Rules.resolve_timeout([player, dead_ally, enemy])).is_equal(PLAYER)

# ── Helpers ──────────────────────────────────────────────────────────

func test_living_units_filters_by_side_and_health() -> void:
	var alive := _unit("infantry", PLAYER, 1)
	var dead := _unit("infantry", PLAYER, 2)
	dead.take_damage(dead.max_hp)
	var enemy := _unit("infantry", ENEMY, 3)
	assert_int(Rules.living_units([alive, dead, enemy], PLAYER).size()).is_equal(1)
	assert_int(Rules.living_units([alive, dead, enemy], ENEMY).size()).is_equal(1)

func test_occupied_cells_skips_the_unit_being_moved() -> void:
	var mover := _unit("infantry", PLAYER, 1)
	var ally := _unit("infantry", PLAYER, 2)
	mover.position = Vector2i(2, 6)
	ally.position = Vector2i(3, 6)
	var cells := Rules.occupied_cells([mover, ally], mover.uid)
	assert_array(cells).is_equal([Vector2i(3, 6)])

func test_occupied_cells_skips_units_off_board() -> void:
	var on_board := _unit("infantry", PLAYER, 1)
	var off_board := _unit("infantry", PLAYER, 2)
	on_board.position = Vector2i(2, 6)
	off_board.position = Vector2i(-1, -1)
	assert_array(Rules.occupied_cells([on_board, off_board])).is_equal([Vector2i(2, 6)])
