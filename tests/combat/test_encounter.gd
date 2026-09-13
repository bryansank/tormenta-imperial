extends GdUnitTestSuite
## Plays whole encounters headless. This is the file that proves the board works
## without ever opening a window: deployment, turn flow, the move-then-attack
## rule, the win conditions and the round limit.

const EncounterScript := preload("res://scripts/combat/Encounter.gd")
const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")

const PLAYER := 0
const ENEMY := 1

var _uid := 0

func before_test() -> void:
	_uid = 0

func _unit(unit_id: String, side: int) -> CombatUnit:
	_uid += 1
	return CombatUnitScript.create(_uid, unit_id, side, 1.0)

func _encounter(player_ids: Array, enemy_ids: Array) -> Encounter:
	var units: Array = []
	for id in player_ids:
		units.append(_unit(id, PLAYER))
	for id in enemy_ids:
		units.append(_unit(id, ENEMY))
	return EncounterScript.create(units, 0, false)

func _events_of(events: Array, kind: String) -> Array:
	var found: Array = []
	for event in events:
		if event.get("e", "") == kind:
			found.append(event)
	return found

# ── Deployment ───────────────────────────────────────────────────────

func test_player_deploys_on_the_bottom_rows_and_enemy_on_the_top() -> void:
	var e := _encounter(["infantry", "vehicle"], ["infantry", "artillery"])
	var board: Vector2i = e.board_size
	for unit in e.units:
		if unit.side == PLAYER:
			assert_bool(unit.position.y >= board.y - 2).is_true()
		else:
			assert_bool(unit.position.y <= 1).is_true()

func test_no_two_units_share_a_cell_after_deployment() -> void:
	var e := _encounter(["infantry", "infantry", "vehicle"], ["infantry", "infantry", "artillery"])
	var seen: Array = []
	for unit in e.units:
		assert_array(seen).not_contains([unit.position])
		seen.append(unit.position)

func test_every_unit_deploys_inside_the_board() -> void:
	var e := _encounter(["infantry", "infantry", "infantry"], ["infantry"])
	for unit in e.units:
		assert_bool(unit.position.x >= 0 and unit.position.x < e.board_size.x).is_true()
		assert_bool(unit.position.y >= 0 and unit.position.y < e.board_size.y).is_true()

func test_a_small_squad_opens_as_a_line_on_its_front_row() -> void:
	# Four units and eight columns: they belong shoulder to shoulder facing the
	# enemy, not scattered across both rows.
	var e := _encounter(["infantry", "infantry", "infantry", "artillery"], ["infantry"])
	var front: int = e.board_size.y - 2
	for unit in e.living(PLAYER):
		assert_int(unit.position.y).is_equal(front)

func test_the_line_is_centred_on_the_board() -> void:
	var e := _encounter(["infantry", "infantry"], ["infantry"])
	var columns: Array = []
	for unit in e.living(PLAYER):
		columns.append(unit.position.x)
	columns.sort()
	# Two units on an eight-wide board sit in the middle, not against an edge.
	assert_array(columns).is_equal([3, 4])

func test_an_oversized_squad_overflows_to_the_back_row() -> void:
	var ids: Array = []
	for i in range(10):
		ids.append("infantry")
	var e := _encounter(ids, ["infantry"])
	var rows := {}
	for unit in e.living(PLAYER):
		rows[unit.position.y] = int(rows.get(unit.position.y, 0)) + 1
	assert_int(rows.get(e.board_size.y - 2, 0)).is_equal(8)
	assert_int(rows.get(e.board_size.y - 1, 0)).is_equal(2)

func test_encounter_opens_in_deploying_state() -> void:
	var e := _encounter(["infantry"], ["infantry"])
	assert_int(e.state).is_equal(Encounter.State.DEPLOYING)
	assert_bool(e.is_active()).is_true()

# ── Turn flow ────────────────────────────────────────────────────────

func test_start_hands_the_turn_to_the_highest_initiative() -> void:
	# Infantry (initiative 5) outruns artillery (3).
	var e := _encounter(["infantry"], ["artillery"])
	var events := e.start()
	var started := _events_of(events, "turn_started")
	assert_int(started.size()).is_equal(1)
	assert_int(started[0]["side"]).is_equal(PLAYER)
	assert_int(e.state).is_equal(Encounter.State.PLAYER_TURN)

func test_ending_a_turn_passes_the_board_to_the_other_side() -> void:
	var e := _encounter(["infantry"], ["artillery"])
	e.start()
	var events := e.end_turn()
	var started := _events_of(events, "turn_started")
	assert_int(started[0]["side"]).is_equal(ENEMY)

func test_a_spent_order_rolls_into_the_next_round() -> void:
	var e := _encounter(["infantry"], ["artillery"])
	e.start()
	assert_int(e.round_number).is_equal(1)
	e.end_turn()          # player done
	e.end_turn()          # enemy done -> new round
	assert_int(e.round_number).is_equal(2)

# ── The move-then-attack rule ────────────────────────────────────────

func test_a_unit_may_move_and_then_attack_in_the_same_turn() -> void:
	var e := _encounter(["infantry"], ["infantry"])
	var player: CombatUnit = e.living(PLAYER)[0]
	var enemy: CombatUnit = e.living(ENEMY)[0]
	e.start()
	# Put them a short walk apart so one move brings them into contact.
	player.position = Vector2i(4, 4)
	enemy.position = Vector2i(4, 2)
	var moved := e.move_unit(player.uid, Vector2i(4, 3))
	assert_int(_events_of(moved, "unit_moved").size()).is_equal(1)
	var attacked := e.attack(player.uid, enemy.uid)
	assert_int(_events_of(attacked, "unit_attacked").size()).is_equal(1)

func test_a_unit_cannot_move_twice_in_one_turn() -> void:
	var e := _encounter(["infantry"], ["artillery"])
	var player: CombatUnit = e.living(PLAYER)[0]
	e.start()
	player.position = Vector2i(4, 4)
	assert_array(e.move_unit(player.uid, Vector2i(4, 5))).is_not_empty()
	assert_array(e.move_unit(player.uid, Vector2i(4, 6))).is_empty()

func test_attacking_ends_the_turn() -> void:
	var e := _encounter(["infantry"], ["infantry"])
	var player: CombatUnit = e.living(PLAYER)[0]
	var enemy: CombatUnit = e.living(ENEMY)[0]
	e.start()
	player.position = Vector2i(4, 4)
	enemy.position = Vector2i(4, 3)
	var events := e.attack(player.uid, enemy.uid)
	assert_bool(player.has_acted).is_true()
	assert_int(_events_of(events, "turn_started").size()).is_equal(1)

func test_moving_onto_an_occupied_cell_is_rejected() -> void:
	var e := _encounter(["infantry", "infantry"], ["artillery"])
	var a: CombatUnit = e.living(PLAYER)[0]
	var b: CombatUnit = e.living(PLAYER)[1]
	e.start()
	a.position = Vector2i(4, 6)
	b.position = Vector2i(4, 5)
	assert_array(e.move_unit(a.uid, b.position)).is_empty()

func test_attacking_out_of_range_is_rejected() -> void:
	var e := _encounter(["infantry"], ["infantry"])
	var player: CombatUnit = e.living(PLAYER)[0]
	var enemy: CombatUnit = e.living(ENEMY)[0]
	e.start()
	player.position = Vector2i(0, 7)
	enemy.position = Vector2i(7, 0)
	assert_array(e.attack(player.uid, enemy.uid)).is_empty()

# ── Defending ────────────────────────────────────────────────────────

func test_defending_ends_the_turn_and_raises_defense() -> void:
	var e := _encounter(["vehicle"], ["artillery"])
	var player: CombatUnit = e.living(PLAYER)[0]
	e.start()
	var base_def: int = player.defense()
	var events := e.defend(player.uid)
	assert_int(_events_of(events, "unit_defended").size()).is_equal(1)
	assert_int(player.defense()).is_equal(base_def * 2)
	assert_bool(player.has_acted).is_true()

func test_defending_wears_off_on_the_next_round() -> void:
	var e := _encounter(["vehicle"], ["artillery"])
	var player: CombatUnit = e.living(PLAYER)[0]
	e.start()
	e.defend(player.uid)
	e.end_turn()          # enemy acts, round rolls over
	assert_bool(player.defending).is_false()

# ── Resolution ───────────────────────────────────────────────────────

func test_killing_the_last_enemy_wins_the_encounter() -> void:
	var e := _encounter(["artillery"], ["artillery"])
	var player: CombatUnit = e.living(PLAYER)[0]
	var enemy: CombatUnit = e.living(ENEMY)[0]
	e.start()
	player.position = Vector2i(4, 4)
	enemy.position = Vector2i(4, 2)
	enemy.hp = 1
	var events := e.attack(player.uid, enemy.uid)
	assert_int(_events_of(events, "unit_died").size()).is_equal(1)
	var ended := _events_of(events, "encounter_ended")
	assert_int(ended.size()).is_equal(1)
	assert_bool(ended[0]["victory"]).is_true()
	assert_int(e.state).is_equal(Encounter.State.WON)

func test_losing_the_last_unit_loses_the_encounter() -> void:
	var e := _encounter(["artillery"], ["artillery"])
	var player: CombatUnit = e.living(PLAYER)[0]
	var enemy: CombatUnit = e.living(ENEMY)[0]
	e.start()
	player.position = Vector2i(4, 4)
	enemy.position = Vector2i(4, 2)
	player.hp = 1
	e.end_turn()                                  # hand over to the enemy
	var events := e.attack(enemy.uid, player.uid)
	assert_int(e.state).is_equal(Encounter.State.LOST)
	assert_bool(_events_of(events, "encounter_ended")[0]["victory"]).is_false()

func test_a_resolved_encounter_refuses_further_actions() -> void:
	var e := _encounter(["artillery"], ["artillery"])
	var player: CombatUnit = e.living(PLAYER)[0]
	var enemy: CombatUnit = e.living(ENEMY)[0]
	e.start()
	player.position = Vector2i(4, 4)
	enemy.position = Vector2i(4, 2)
	enemy.hp = 1
	e.attack(player.uid, enemy.uid)
	assert_bool(e.is_active()).is_false()
	assert_array(e.move_unit(player.uid, Vector2i(4, 5))).is_empty()
	assert_array(e.end_turn()).is_empty()

func test_running_out_of_rounds_resolves_by_total_hp() -> void:
	var e := _encounter(["vehicle"], ["infantry"])   # 60 hp vs 30 hp
	e.turn_limit = 1
	e.start()
	e.end_turn()
	var events := e.end_turn()                        # order spent, round 2 > limit
	var ended := _events_of(events, "encounter_ended")
	assert_int(ended.size()).is_equal(1)
	assert_bool(ended[0]["victory"]).is_true()
	assert_int(e.state).is_equal(Encounter.State.TIMEOUT)

func test_timeout_reports_the_rounds_actually_played() -> void:
	var e := _encounter(["vehicle"], ["infantry"])
	e.turn_limit = 1
	e.start()
	e.end_turn()
	var ended := _events_of(e.end_turn(), "encounter_ended")
	assert_int(ended[0]["rounds"]).is_equal(1)

# ── Between encounters ───────────────────────────────────────────────

func test_survivors_leave_the_board_but_keep_their_damage() -> void:
	var e := _encounter(["infantry"], ["artillery"])
	var player: CombatUnit = e.living(PLAYER)[0]
	e.start()
	player.take_damage(7)
	var wounded: int = player.hp
	e.release_survivors()
	assert_vector(player.position).is_equal(Vector2i(-1, -1))
	assert_int(player.hp).is_equal(wounded)
	assert_bool(player.hp < player.max_hp).is_true()

func test_casualties_are_reported_per_side() -> void:
	var e := _encounter(["infantry", "infantry"], ["artillery"])
	var fallen: CombatUnit = e.living(PLAYER)[0]
	fallen.take_damage(fallen.max_hp)
	assert_int(e.casualties(PLAYER).size()).is_equal(1)
	assert_int(e.survivors().size()).is_equal(1)
