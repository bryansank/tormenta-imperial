extends GdUnitTestSuite
## Proves the generator's promises: the map is always winnable, the same seed
## always builds the same run, difficulty climbs, and the draft never wastes the
## player's click on an upgrade that does nothing.

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")

## The spec asks for 200 seeds on the connectivity invariant; the cheaper checks
## reuse the same sweep.
const SEEDS := 200

var _uid := 0

func before_test() -> void:
	_uid = 0

func _map(seed_value: int, era: int = 1) -> Array:
	return Generator.generate_map(Generator.make_rng(seed_value), Vector2i.ZERO, Vector2i.ZERO, era)

func _unit(unit_id: String) -> CombatUnit:
	_uid += 1
	return CombatUnitScript.create(_uid, unit_id, 0, 1.0)

func _party(unit_ids: Array) -> Array:
	var party: Array = []
	for id in unit_ids:
		party.append(_unit(id))
	return party

func _max_depth(map: Array) -> int:
	var deepest: int = 0
	for node in map:
		deepest = maxi(deepest, int(node["depth"]))
	return deepest

# ── The invariant ────────────────────────────────────────────────────

func test_every_node_reaches_the_boss_across_200_seeds() -> void:
	# This is the one that matters: a map with a dead end is a run the player
	# cannot finish, and no amount of UI polish saves it.
	var failed: Array = []
	for s in range(SEEDS):
		if not Generator.every_node_reaches_boss(_map(s)):
			failed.append(s)
	assert_array(failed).is_empty()

func test_no_node_is_an_orphan() -> void:
	# Unreachable nodes are the other half of the invariant: everything the
	# generator draws has to be walkable from the start.
	for s in range(SEEDS):
		var map: Array = _map(s)
		var reachable: Array = Generator.reachable_from(map, 0)
		assert_int(reachable.size()).is_equal(map.size())

func test_only_the_boss_has_no_exits() -> void:
	for s in range(SEEDS):
		var map: Array = _map(s)
		for node in map:
			if bool(node["is_boss"]):
				assert_array(node["exits"]).is_empty()
			else:
				assert_array(node["exits"]).is_not_empty()

func test_exits_only_ever_point_one_layer_forward() -> void:
	for s in range(50):
		var map: Array = _map(s)
		for node in map:
			for exit_index in node["exits"]:
				assert_int(int(map[exit_index]["depth"])).is_equal(int(node["depth"]) + 1)

func test_the_last_node_is_the_boss_and_it_is_the_only_one() -> void:
	for s in range(50):
		var map: Array = _map(s)
		var bosses: int = 0
		for node in map:
			if bool(node["is_boss"]):
				bosses += 1
		assert_int(bosses).is_equal(1)
		assert_bool(bool(map[map.size() - 1]["is_boss"])).is_true()

# ── Shape ────────────────────────────────────────────────────────────

func test_depth_stays_inside_the_configured_range() -> void:
	var cfg: Vector2i = GameConfig.combat_map_depth
	for s in range(SEEDS):
		var deepest: int = _max_depth(_map(s))
		# The boss sits one layer past the configured run of nodes.
		assert_int(deepest).is_greater_equal(cfg.x + 1)
		assert_int(deepest).is_less_equal(cfg.y + 1)

func test_the_run_opens_on_a_single_low_risk_node() -> void:
	for s in range(50):
		var map: Array = _map(s)
		assert_int(int(map[0]["depth"])).is_equal(0)
		assert_int(int(map[0]["risk"])).is_equal(0)
		var at_depth_zero: int = 0
		for node in map:
			if int(node["depth"]) == 0:
				at_depth_zero += 1
		assert_int(at_depth_zero).is_equal(1)

func test_risk_stays_inside_its_three_steps() -> void:
	for s in range(50):
		for node in _map(s):
			assert_int(int(node["risk"])).is_between(0, 2)

# ── Determinism ──────────────────────────────────────────────────────

func test_the_same_seed_rebuilds_the_same_map() -> void:
	# The save stores a seed, not a map. If this breaks, reloading a run drops
	# the player into a different expedition.
	for s in [1, 42, 918273645, -7]:
		assert_str(JSON.stringify(_map(s))).is_equal(JSON.stringify(_map(s)))

func test_two_seeds_build_two_different_maps() -> void:
	var shapes: Dictionary = {}
	for s in range(SEEDS):
		shapes[JSON.stringify(_map(s))] = true
	# Collisions are possible in principle; a generator worth having produces
	# far more variety than this floor.
	assert_int(shapes.size()).is_greater(SEEDS / 2)

func test_the_era_changes_the_rosters_but_not_the_shape() -> void:
	var early: Array = _map(99, 1)
	var late: Array = _map(99, 3)
	assert_int(early.size()).is_equal(late.size())
	for i in range(early.size()):
		assert_array(early[i]["exits"]).is_equal(late[i]["exits"])
	assert_str(JSON.stringify(early)).is_not_equal(JSON.stringify(late))

# ── Difficulty ───────────────────────────────────────────────────────

func test_enemy_scale_climbs_with_depth_risk_and_era() -> void:
	assert_float(Generator.enemy_scale(1, 1, 0)).is_greater(Generator.enemy_scale(0, 1, 0))
	assert_float(Generator.enemy_scale(0, 1, 2)).is_greater(Generator.enemy_scale(0, 1, 0))
	assert_float(Generator.enemy_scale(0, 3, 0)).is_greater(Generator.enemy_scale(0, 1, 0))
	assert_float(Generator.enemy_scale(4, 1, 0, true)).is_greater(Generator.enemy_scale(4, 1, 0, false))

func test_rosters_grow_with_depth() -> void:
	var rng := Generator.make_rng(1234)
	var shallow: int = Generator.roster_size(Generator.enemy_roster(rng, 0, 1, 0))
	var deep: int = Generator.roster_size(Generator.enemy_roster(rng, 8, 1, 0))
	assert_int(deep).is_greater(shallow)

func test_a_node_never_fields_more_than_the_deploy_cap() -> void:
	for s in range(SEEDS):
		for node in _map(s, 3):
			assert_int(Generator.roster_size(node["enemy_roster"])).is_less_equal(GameConfig.combat_deploy_cap)
			assert_int(Generator.roster_size(node["enemy_roster"])).is_greater(0)

func test_early_eras_never_field_units_the_player_has_not_met() -> void:
	# Enemies mirror the player's own unit types (research D10), so an era-1 run
	# must not run into vehicles.
	for s in range(50):
		for node in _map(s, 1):
			assert_bool(node["enemy_roster"].has("vehicle")).is_false()
			assert_bool(node["enemy_roster"].has("artillery")).is_false()

func test_the_boss_is_the_hardest_node_on_the_map() -> void:
	for era in [1, 2, 3]:
		for s in range(60):
			var map: Array = _map(s, era)
			var boss: Dictionary = map[Generator.boss_index(map)]
			var toughest: float = 0.0
			for node in map:
				if not bool(node["is_boss"]):
					toughest = maxf(toughest, Generator.node_power(node, era))
			assert_float(Generator.node_power(boss, era)).is_greater(toughest)

func test_deeper_nodes_are_harder_than_the_opening_fight() -> void:
	for s in range(60):
		var map: Array = _map(s, 2)
		var opener: float = Generator.node_power(map[0], 2)
		var deepest: int = _max_depth(map)
		for node in map:
			if int(node["depth"]) == deepest:
				assert_float(Generator.node_power(node, 2)).is_greater(opener)

# ── Rewards ──────────────────────────────────────────────────────────

func test_risk_pays_for_itself() -> void:
	var safe: Dictionary = Generator.node_rewards({"depth": 2, "risk": 0, "is_boss": false}, 1)
	var risky: Dictionary = Generator.node_rewards({"depth": 2, "risk": 2, "is_boss": false}, 1)
	for res_name in safe:
		assert_int(int(risky[res_name])).is_greater(int(safe[res_name]))

func test_deeper_and_later_pays_more() -> void:
	var shallow: Dictionary = Generator.node_rewards({"depth": 0, "risk": 1, "is_boss": false}, 1)
	var deep: Dictionary = Generator.node_rewards({"depth": 5, "risk": 1, "is_boss": false}, 1)
	var late: Dictionary = Generator.node_rewards({"depth": 0, "risk": 1, "is_boss": false}, 3)
	var boss: Dictionary = Generator.node_rewards({"depth": 5, "risk": 2, "is_boss": true}, 1)
	for res_name in shallow:
		assert_int(int(deep[res_name])).is_greater(int(shallow[res_name]))
		assert_int(int(late[res_name])).is_greater(int(shallow[res_name]))
		assert_int(int(boss[res_name])).is_greater(int(deep[res_name]))

# ── Drafts ───────────────────────────────────────────────────────────

func test_the_draft_always_offers_at_least_two_applicable_options() -> void:
	# SC-009. Offering a card that changes nothing is the same as offering two.
	var parties: Array = [
		["infantry"],
		["infantry", "infantry"],
		["infantry", "artillery", "vehicle"],
	]
	for party_ids in parties:
		for s in range(SEEDS):
			var party: Array = _party(party_ids)
			var options: Array = Generator.draft_options(Generator.make_rng(s), party)
			assert_int(options.size()).is_greater_equal(2)
			for option in options:
				assert_bool(Generator.is_applicable(option, party)).is_true()

func test_the_draft_offers_exactly_the_configured_number_of_options() -> void:
	for s in range(50):
		var party: Array = _party(["infantry", "artillery"])
		var options: Array = Generator.draft_options(Generator.make_rng(s), party)
		assert_int(options.size()).is_equal(GameConfig.combat_draft_options)

func test_options_never_repeat_inside_one_draft() -> void:
	for s in range(50):
		var seen: Array = []
		for option in Generator.draft_options(Generator.make_rng(s), _party(["infantry", "vehicle"])):
			assert_array(seen).not_contains([option["id"]])
			seen.append(option["id"])

func test_healing_is_not_offered_to_a_party_at_full_health() -> void:
	for s in range(SEEDS):
		for option in Generator.draft_options(Generator.make_rng(s), _party(["infantry", "artillery"])):
			assert_str(String(option["id"])).is_not_equal("draft_hp_heal")

func test_healing_comes_back_once_somebody_is_wounded() -> void:
	var party: Array = _party(["infantry"])
	party[0].take_damage(10)
	var offered := false
	for s in range(SEEDS):
		for option in Generator.draft_options(Generator.make_rng(s), party):
			if String(option["id"]) == "draft_hp_heal":
				offered = true
	assert_bool(offered).is_true()

func test_a_wounded_party_is_the_only_one_a_field_station_applies_to() -> void:
	var healthy: Array = _party(["infantry"])
	var wounded: Array = _party(["infantry"])
	wounded[0].take_damage(10)
	var heal: Dictionary = {
		"id": "draft_hp_heal", "label_key": "DRAFT_HP_HEAL",
		"effect": {"heal_pct": 0.3}, "applies_to": "all",
	}
	assert_bool(Generator.is_applicable(heal, healthy)).is_false()
	assert_bool(Generator.is_applicable(heal, wounded)).is_true()

func test_the_same_seed_offers_the_same_cards() -> void:
	var first: Array = Generator.draft_options(Generator.make_rng(77), _party(["infantry", "artillery"]))
	var second: Array = Generator.draft_options(Generator.make_rng(77), _party(["infantry", "artillery"]))
	assert_str(JSON.stringify(first)).is_equal(JSON.stringify(second))

func test_every_option_carries_the_fields_the_ui_needs() -> void:
	for option in Generator.draft_options(Generator.make_rng(5), _party(["infantry", "vehicle"])):
		assert_bool(option.has("id")).is_true()
		assert_bool(option.has("label_key")).is_true()
		assert_bool(option.has("effect")).is_true()
		assert_bool(option.has("applies_to")).is_true()
		assert_str(String(option["label_key"])).starts_with("DRAFT_")

func test_a_stat_draft_raises_the_stat_it_names() -> void:
	var party: Array = _party(["infantry"])
	var before: int = party[0].attack_power()
	Generator.apply_option({"effect": {"stat": "atk", "delta": 3}, "applies_to": "all"}, party)
	assert_int(party[0].attack_power()).is_equal(before + 3)

func test_a_focused_draft_skips_the_units_it_is_not_for() -> void:
	var party: Array = _party(["infantry", "vehicle"])
	var vehicle_before: int = party[1].attack_power()
	Generator.apply_option({"effect": {"stat": "atk", "delta": 3}, "applies_to": "infantry"}, party)
	assert_int(party[1].attack_power()).is_equal(vehicle_before)

func test_a_draft_never_helps_the_dead() -> void:
	var party: Array = _party(["infantry", "infantry"])
	party[1].take_damage(party[1].max_hp)
	Generator.apply_option({"effect": {"stat": "atk", "delta": 3}, "applies_to": "all"}, party)
	assert_int(int(party[1].draft_bonuses.get("atk", 0))).is_equal(0)
	assert_int(int(party[0].draft_bonuses.get("atk", 0))).is_equal(3)

func test_an_empty_party_is_offered_nothing() -> void:
	assert_array(Generator.draft_options(Generator.make_rng(1), [])).is_empty()
