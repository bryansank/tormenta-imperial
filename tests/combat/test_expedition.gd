extends GdUnitTestSuite
## Plays whole expeditions headless. What is under test here is the run itself:
## attrition between nodes, permadeath, drafts that last exactly one expedition,
## and a save that survives a round trip without the map ever being written down.

const ExpeditionScript := preload("res://scripts/combat/Expedition.gd")
const EncounterScript := preload("res://scripts/combat/Encounter.gd")
const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")

const PARTY := {"infantry": 2, "artillery": 1}

func _run(seed_value: int = 12345, era: int = 2, morale: float = 50.0) -> Expedition:
	return ExpeditionScript.create(1, seed_value, PARTY, morale, era)

func _events_of(events: Array, kind: String) -> Array:
	var found: Array = []
	for event in events:
		if event.get("e", "") == kind:
			found.append(event)
	return found

## Walks one step forward along the first available exit.
func _advance(run: Expedition) -> void:
	var exits: Array = run.current_exits()
	if not exits.is_empty():
		run.select_node(int(exits[0]))

# ── Launch ───────────────────────────────────────────────────────────

func test_launching_builds_the_party_that_was_committed() -> void:
	var run := _run()
	assert_int(run.party.size()).is_equal(3)
	assert_int(run.current_node).is_equal(0)
	assert_int(run.state).is_equal(Expedition.State.ACTIVE)
	var counts: Dictionary = {}
	for unit in run.party:
		counts[unit.unit_id] = int(counts.get(unit.unit_id, 0)) + 1
	assert_int(int(counts["infantry"])).is_equal(2)
	assert_int(int(counts["artillery"])).is_equal(1)

func test_the_party_marches_out_at_full_health_and_on_the_player_side() -> void:
	for unit in _run().party:
		assert_int(unit.hp).is_equal(unit.max_hp)
		assert_int(unit.side).is_equal(Expedition.PLAYER)

func test_morale_is_frozen_at_launch() -> void:
	# The battle is fought with the spirit the town had when the column left.
	var grim := _run(1, 2, 0.0)
	var proud := _run(1, 2, 100.0)
	assert_int(proud.party[0].attack_power()).is_greater(grim.party[0].attack_power())
	assert_int(proud.party[0].initiative()).is_greater(grim.party[0].initiative())

func test_no_two_units_in_a_run_share_a_uid() -> void:
	var run := _run()
	var seen: Array = []
	for unit in run.party:
		assert_array(seen).not_contains([unit.uid])
		seen.append(unit.uid)
	for unit in run.build_enemy_units():
		assert_array(seen).not_contains([unit.uid])
		seen.append(unit.uid)

# ── Walking the map ──────────────────────────────────────────────────

func test_only_an_exit_of_the_current_node_can_be_selected() -> void:
	var run := _run()
	var exits: Array = run.current_exits()
	assert_array(exits).is_not_empty()
	assert_bool(run.can_select(int(exits[0]))).is_true()
	assert_bool(run.can_select(0)).is_false()
	assert_bool(run.can_select(999)).is_false()
	assert_array(run.select_node(999)).is_empty()
	assert_int(run.current_node).is_equal(0)

func test_selecting_a_valid_exit_moves_the_run_and_reports_it() -> void:
	var run := _run()
	var target: int = int(run.current_exits()[0])
	var events: Array = run.select_node(target)
	assert_int(_events_of(events, "expedition_node_selected").size()).is_equal(1)
	assert_int(run.current_node).is_equal(target)

func test_a_full_route_ends_on_the_boss() -> void:
	for s in range(40):
		var run := _run(s)
		var steps: int = 0
		while not run.at_boss() and steps < 50:
			run.mark_cleared()
			_advance(run)
			steps += 1
		assert_bool(run.at_boss()).is_true()

# ── Clearing nodes ───────────────────────────────────────────────────

func test_clearing_a_node_books_its_loot() -> void:
	var run := _run()
	assert_dict(run.rewards).is_empty()
	run.mark_cleared()
	assert_dict(run.rewards).is_not_empty()
	for res_name in run.rewards:
		assert_int(int(run.rewards[res_name])).is_greater(0)

func test_loot_accumulates_along_the_route() -> void:
	var run := _run()
	run.mark_cleared()
	var first: int = int(run.rewards["gold"])
	_advance(run)
	run.mark_cleared()
	assert_int(int(run.rewards["gold"])).is_greater(first)

func test_a_node_only_pays_once() -> void:
	var run := _run()
	run.mark_cleared()
	var paid: Dictionary = run.rewards.duplicate()
	assert_array(run.mark_cleared()).is_empty()
	assert_dict(run.rewards).is_equal(paid)

func test_beating_the_boss_completes_the_expedition() -> void:
	var run := _run()
	while not run.at_boss():
		run.mark_cleared()
		_advance(run)
	var events: Array = run.mark_cleared()
	assert_int(run.state).is_equal(Expedition.State.COMPLETED)
	assert_bool(run.boss_defeated()).is_true()
	assert_bool(run.is_finished()).is_true()
	assert_int(int(_events_of(events, "expedition_ended")[0]["result"])).is_equal(Expedition.RESULT_WON)

# ── Attrition and permadeath ─────────────────────────────────────────

func test_wounds_carry_from_one_node_to_the_next() -> void:
	# FR-011: nothing heals out here. That is the whole tension of a run.
	var run := _run()
	run.party[0].take_damage(9)
	var wounded: int = run.party[0].hp
	run.mark_cleared()
	_advance(run)
	var next_units: Array = run.build_encounter_units()
	var found := false
	for unit in next_units:
		if unit.uid == run.party[0].uid:
			found = true
			assert_int(unit.hp).is_equal(wounded)
	assert_bool(found).is_true()

func test_the_fallen_never_march_again() -> void:
	# FR-010: permadeath is permanent for the rest of the run.
	var run := _run()
	var doomed: int = run.party[0].uid
	run.party[0].take_damage(run.party[0].max_hp)
	run.mark_cleared()
	_advance(run)
	for unit in run.build_encounter_units():
		assert_int(unit.uid).is_not_equal(doomed)
	assert_int(run.living_party().size()).is_equal(2)
	assert_int(run.casualties().size()).is_equal(1)

func test_losing_the_whole_party_defeats_the_expedition() -> void:
	var run := _run()
	for unit in run.party:
		unit.take_damage(unit.max_hp)
	assert_bool(run.is_party_wiped()).is_true()
	var events: Array = run.mark_defeated()
	assert_int(run.state).is_equal(Expedition.State.DEFEATED)
	assert_int(int(_events_of(events, "expedition_ended")[0]["result"])).is_equal(Expedition.RESULT_LOST)

func test_an_encounter_played_out_leaves_the_survivors_wounded_for_the_next_node() -> void:
	# The same attrition, this time through a real board instead of by hand.
	var run := _run()
	var encounter: Encounter = EncounterScript.create(run.build_encounter_units(), 0, false)
	encounter.start()
	var hero: CombatUnit = encounter.living(Encounter.PLAYER)[0]
	hero.take_damage(5)
	for enemy in encounter.living(Encounter.ENEMY):
		enemy.take_damage(enemy.max_hp)
	encounter.release_survivors()
	run.mark_cleared()
	_advance(run)
	assert_int(hero.hp).is_equal(hero.max_hp - 5)
	assert_vector(hero.position).is_equal(Vector2i(-1, -1))
	assert_array(run.living_party()).contains([hero])

func test_a_node_replayed_fields_undamaged_enemies() -> void:
	var run := _run()
	var first: Array = run.build_enemy_units()
	first[0].take_damage(first[0].max_hp)
	var second: Array = run.build_enemy_units()
	assert_int(second[0].hp).is_equal(second[0].max_hp)

# ── Drafts ───────────────────────────────────────────────────────────

func test_the_draft_offered_after_a_node_is_applicable_and_reproducible() -> void:
	var run := _run()
	var options: Array = run.draft_options()
	assert_int(options.size()).is_greater_equal(2)
	assert_str(JSON.stringify(options)).is_equal(JSON.stringify(run.draft_options()))

func test_applying_a_draft_records_it_and_buffs_the_party() -> void:
	var run := _run()
	var before: int = run.party[0].attack_power()
	var events: Array = run.apply_draft({
		"id": "draft_atk", "label_key": "DRAFT_ATK",
		"effect": {"stat": "atk", "delta": 2}, "applies_to": "all",
	})
	assert_int(_events_of(events, "draft_applied").size()).is_equal(1)
	assert_int(run.draft_picks.size()).is_equal(1)
	assert_int(run.party[0].attack_power()).is_greater(before)

func test_a_different_node_offers_a_different_draft() -> void:
	var run := _run()
	var at_start: String = JSON.stringify(run.draft_options())
	_advance(run)
	assert_str(JSON.stringify(run.draft_options())).is_not_equal(at_start)

# ── Abandoning ───────────────────────────────────────────────────────

func test_abandoning_keeps_the_loot_and_the_survivors() -> void:
	# FR-016: walking away has to be a real choice, not a forfeit.
	var run := _run()
	run.mark_cleared()
	var loot: Dictionary = run.rewards.duplicate()
	var events: Array = run.abandon()
	assert_int(run.state).is_equal(Expedition.State.ABANDONED)
	assert_dict(run.rewards).is_equal(loot)
	assert_int(run.living_party().size()).is_equal(3)
	assert_int(int(_events_of(events, "expedition_ended")[0]["result"])).is_equal(Expedition.RESULT_ABANDONED)

func test_a_finished_expedition_refuses_to_keep_going() -> void:
	var run := _run()
	run.abandon()
	assert_array(run.abandon()).is_empty()
	assert_array(run.mark_cleared()).is_empty()
	assert_array(run.mark_defeated()).is_empty()
	assert_array(run.select_node(int(run.current_node_data()["exits"][0]))).is_empty()

# ── The result handed back to the base ───────────────────────────────

func test_the_result_summary_reports_what_the_base_needs() -> void:
	var run := _run()
	run.party[0].take_damage(run.party[0].max_hp)
	run.mark_cleared()
	run.abandon()
	var summary: Dictionary = run.result_summary()
	assert_int(int(summary["result"])).is_equal(Expedition.RESULT_ABANDONED)
	assert_int(int(summary["nodes_cleared"])).is_equal(1)
	assert_bool(bool(summary["boss_defeated"])).is_false()
	assert_int(int(summary["casualties"]["infantry"])).is_equal(1)
	assert_int(int(summary["survivors"]["infantry"])).is_equal(1)
	assert_int(int(summary["survivors"]["artillery"])).is_equal(1)
	assert_dict(summary["rewards"]).is_not_empty()

# ── Persistence ──────────────────────────────────────────────────────

func test_an_expedition_survives_a_round_trip_through_the_save() -> void:
	var run := _run(918273645, 3, 72.0)
	run.mark_cleared()
	_advance(run)
	run.apply_draft({
		"id": "draft_atk", "label_key": "DRAFT_ATK",
		"effect": {"stat": "atk", "delta": 2}, "applies_to": "all",
	})
	run.party[1].take_damage(7)

	# Through JSON on purpose: this is the trip the real save file makes.
	var restored: Expedition = ExpeditionScript.from_dict(
		JSON.parse_string(JSON.stringify(run.to_dict()))
	)

	assert_int(restored.id).is_equal(run.id)
	assert_int(restored.seed_value).is_equal(run.seed_value)
	assert_int(restored.era).is_equal(run.era)
	assert_int(restored.current_node).is_equal(run.current_node)
	assert_int(restored.state).is_equal(run.state)
	assert_float(restored.morale_snapshot).is_equal(run.morale_snapshot)
	assert_dict(restored.rewards).is_equal(run.rewards)
	assert_int(restored.draft_picks.size()).is_equal(1)
	assert_array(restored.cleared_indices()).is_equal(run.cleared_indices())
	# The map is not in the save at all; it comes back out of the seed.
	assert_str(JSON.stringify(restored.map)).is_equal(JSON.stringify(run.map))

func test_the_party_comes_back_wounded_and_still_carrying_its_drafts() -> void:
	var run := _run(4242, 2, 80.0)
	run.apply_draft({
		"id": "draft_def", "label_key": "DRAFT_DEF",
		"effect": {"stat": "def", "delta": 2}, "applies_to": "all",
	})
	run.party[0].take_damage(11)
	run.party[2].take_damage(run.party[2].max_hp)

	var restored: Expedition = ExpeditionScript.from_dict(
		JSON.parse_string(JSON.stringify(run.to_dict()))
	)
	assert_int(restored.party.size()).is_equal(3)
	for i in range(run.party.size()):
		assert_int(restored.party[i].uid).is_equal(run.party[i].uid)
		assert_int(restored.party[i].hp).is_equal(run.party[i].hp)
		assert_int(restored.party[i].defense()).is_equal(run.party[i].defense())
		assert_int(restored.party[i].attack_power()).is_equal(run.party[i].attack_power())
	assert_int(restored.living_party().size()).is_equal(2)

func test_new_units_after_a_reload_never_reuse_an_old_uid() -> void:
	var run := _run()
	var restored: Expedition = ExpeditionScript.from_dict(run.to_dict())
	var taken: Array = []
	for unit in restored.party:
		taken.append(unit.uid)
	for unit in restored.build_enemy_units():
		assert_array(taken).not_contains([unit.uid])

func test_a_save_without_an_expedition_loads_as_no_expedition() -> void:
	# Backward compatibility (constitution, principle V): an old save simply has
	# no expedition key, and that must not be an error.
	assert_object(ExpeditionScript.from_dict({})).is_null()
	assert_object(ExpeditionScript.from_dict({"current_node": 2})).is_null()

func test_an_old_save_without_an_era_falls_back_to_the_one_it_is_told() -> void:
	var run := _run(555, 3)
	var data: Dictionary = run.to_dict()
	data.erase("era")
	assert_int(ExpeditionScript.from_dict(data, 3).era).is_equal(3)
	assert_int(ExpeditionScript.from_dict(data).era).is_equal(1)

func test_a_reloaded_run_keeps_walking_from_where_it_stopped() -> void:
	var run := _run(31337)
	run.mark_cleared()
	_advance(run)
	var restored: Expedition = ExpeditionScript.from_dict(run.to_dict())
	assert_array(restored.current_exits()).is_equal(run.current_exits())
	assert_bool(Generator.every_node_reaches_boss(restored.map)).is_true()
