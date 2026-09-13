extends GdUnitTestSuite
## The enemy has to be worth beating. These tests pin the three behaviours that
## make a fight read as deliberate rather than random: it shoots when it can, it
## focuses the weakest target, and it keeps its artillery at range.

const AIScript := preload("res://scripts/combat/CombatAI.gd")
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

func _encounter(units: Array) -> Encounter:
	var e: Encounter = EncounterScript.create(units, 0, false)
	e.start()
	return e

func _actions(plan: Array) -> Array:
	var names: Array = []
	for step in plan:
		names.append(step.get("action", ""))
	return names

# ── Attacking ────────────────────────────────────────────────────────

func test_it_attacks_a_target_already_in_range() -> void:
	var enemy := _unit("infantry", ENEMY)
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, enemy])
	enemy.position = Vector2i(4, 3)
	player.position = Vector2i(4, 4)
	var plan := AIScript.plan_turn(e, enemy.uid)
	assert_array(_actions(plan)).contains(["attack"])
	assert_int(plan[0]["target"]).is_equal(player.uid)

func test_it_focuses_the_weakest_reachable_target() -> void:
	var enemy := _unit("infantry", ENEMY)
	var healthy := _unit("infantry", PLAYER)
	var wounded := _unit("infantry", PLAYER)
	var e := _encounter([healthy, wounded, enemy])
	enemy.position = Vector2i(4, 4)
	healthy.position = Vector2i(4, 5)
	wounded.position = Vector2i(3, 4)
	wounded.take_damage(20)
	var plan := AIScript.plan_turn(e, enemy.uid)
	var attack: Dictionary = plan[plan.size() - 1]
	assert_int(attack["target"]).is_equal(wounded.uid)

func test_it_closes_in_when_nothing_is_in_range() -> void:
	var enemy := _unit("infantry", ENEMY)
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, enemy])
	enemy.position = Vector2i(4, 0)
	player.position = Vector2i(4, 7)
	var plan := AIScript.plan_turn(e, enemy.uid)
	assert_array(_actions(plan)).contains(["move"])
	# It walks towards the player, never away.
	assert_bool(plan[0]["to"].y > enemy.position.y).is_true()

func test_it_moves_and_then_attacks_when_one_step_is_enough() -> void:
	var enemy := _unit("infantry", ENEMY)     # move 3, range 1
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, enemy])
	enemy.position = Vector2i(4, 2)
	player.position = Vector2i(4, 4)
	var plan := AIScript.plan_turn(e, enemy.uid)
	assert_array(_actions(plan)).is_equal(["move", "attack"])
	assert_int(plan[1]["target"]).is_equal(player.uid)

# ── Artillery keeps its distance ─────────────────────────────────────

func test_artillery_does_not_walk_into_its_own_minimum_range() -> void:
	var gunner := _unit("artillery", ENEMY)   # move 1, range 3, min_range 2
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, gunner])
	gunner.position = Vector2i(4, 2)
	player.position = Vector2i(4, 4)          # distance 2: already a firing solution
	var plan := AIScript.plan_turn(e, gunner.uid)
	# It should shoot from where it stands rather than close the gap.
	assert_array(_actions(plan)).is_equal(["attack"])

func test_artillery_prefers_a_firing_position_over_walking_closer() -> void:
	var gunner := _unit("artillery", ENEMY)
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, gunner])
	gunner.position = Vector2i(4, 0)
	player.position = Vector2i(4, 4)          # distance 4, one step out of range
	var plan := AIScript.plan_turn(e, gunner.uid)
	assert_array(_actions(plan)).is_equal(["move", "attack"])

# ── Degenerate cases ─────────────────────────────────────────────────

func test_it_waits_when_there_is_nobody_left_to_fight() -> void:
	var enemy := _unit("infantry", ENEMY)
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, enemy])
	player.take_damage(player.max_hp)
	assert_array(_actions(AIScript.plan_turn(e, enemy.uid))).is_equal(["wait"])

func test_a_dead_unit_plans_nothing() -> void:
	var enemy := _unit("infantry", ENEMY)
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, enemy])
	enemy.take_damage(enemy.max_hp)
	assert_array(_actions(AIScript.plan_turn(e, enemy.uid))).is_equal(["wait"])

# ── The loop actually terminates ─────────────────────────────────────

func test_two_ai_sides_resolve_the_encounter_without_stalling() -> void:
	# Both sides driven by the AI. If the AI ever refused to close, this would
	# run to the round limit instead of a clean kill — which is exactly the
	# failure mode worth catching.
	var units: Array = [_unit("infantry", PLAYER), _unit("infantry", ENEMY)]
	var e := _encounter(units)
	var guard := 0
	while e.is_active() and guard < 400:
		guard += 1
		var active: CombatUnit = e.active_unit()
		if active == null:
			break
		var uid: int = active.uid
		for step in AIScript.plan_turn(e, uid):
			match step.get("action", "wait"):
				"move":
					e.move_unit(uid, step["to"])
				"attack":
					e.attack(uid, step["target"])
				_:
					e.wait_unit(uid)
			if not e.is_active():
				break
		if e.is_active() and e.active_unit() != null and e.active_unit().uid == uid:
			e.end_turn()
	assert_bool(e.is_resolved()).is_true()
	assert_int(e.state).is_not_equal(Encounter.State.TIMEOUT)
