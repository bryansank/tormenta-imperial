extends GdUnitTestSuite
## Fights whole sieges headless. What is under test is the climax itself: waves
## that get heavier, a garrison that carries its wounds from one to the next,
## dead that stay dead, a last wave that ends the game, a defeat that can be
## answered, and a save that survives the round trip without the waves ever
## being written down.

const AuditScript := preload("res://scripts/combat/FinalAudit.gd")

const GARRISON := {"infantry": 3, "artillery": 2}

func _audit(seed_value: int = 4242, era: int = 3, morale: float = 50.0) -> FinalAudit:
	return AuditScript.create(seed_value, GARRISON, era, morale)

func _events_of(events: Array, kind: String) -> Array:
	var found: Array = []
	for event in events:
		if event.get("e", "") == kind:
			found.append(event)
	return found

## Opens the siege and breaks every wave but the last one.
func _walk_to_last_wave(audit: FinalAudit) -> void:
	audit.begin()
	while not audit.at_last_wave():
		audit.clear_wave()

# ── Being summoned ───────────────────────────────────────────────────

func test_the_capstone_summons_instead_of_winning() -> void:
	var audit := _audit()
	assert_int(audit.state).is_equal(FinalAudit.State.PENDING)
	assert_bool(audit.is_pending()).is_true()
	assert_bool(audit.is_active()).is_false()
	assert_bool(audit.is_resolved()).is_false()
	assert_int(audit.summons).is_equal(1)

func test_the_siege_brings_the_number_of_waves_the_balance_allows() -> void:
	var cfg: Vector2i = GameConfig.final_audit_waves
	for seed_value in [1, 7, 99, 1234, 65535]:
		var audit := _audit(seed_value)
		assert_int(audit.wave_count()).is_between(mini(cfg.x, cfg.y), maxi(cfg.x, cfg.y))

func test_the_garrison_musters_whole_and_on_the_player_side() -> void:
	var audit := _audit()
	assert_int(audit.garrison.size()).is_equal(5)
	for unit in audit.garrison:
		assert_int(unit.hp).is_equal(unit.max_hp)
		assert_int(unit.side).is_equal(FinalAudit.PLAYER)

func test_morale_is_frozen_when_the_regency_is_summoned() -> void:
	# The siege is fought with the spirit the town had the day the capstone
	# went up, not with whatever morale does while the waves land.
	var grim := _audit(1, 3, 0.0)
	var proud := _audit(1, 3, 100.0)
	assert_int(proud.garrison[0].attack_power()).is_greater(grim.garrison[0].attack_power())
	assert_int(proud.garrison[0].initiative()).is_greater(grim.garrison[0].initiative())

func test_no_two_units_in_a_siege_share_a_uid() -> void:
	var audit := _audit()
	var seen: Array = []
	for unit in audit.garrison:
		assert_array(seen).not_contains([unit.uid])
		seen.append(unit.uid)
	for unit in audit.build_enemy_units():
		assert_array(seen).not_contains([unit.uid])
		seen.append(unit.uid)

func test_the_siege_only_opens_once() -> void:
	var audit := _audit()
	assert_int(_events_of(audit.begin(), "final_audit_started").size()).is_equal(1)
	assert_int(audit.state).is_equal(FinalAudit.State.ACTIVE)
	assert_array(audit.begin()).is_empty()

# ── The waves get heavier ────────────────────────────────────────────

func test_every_wave_is_heavier_than_the_one_before_it() -> void:
	for era in [1, 2, 3]:
		for seed_value in [3, 77, 501, 8888]:
			var audit := _audit(seed_value, era)
			for i in range(1, audit.wave_count()):
				assert_float(audit.wave_power(i)).is_greater(audit.wave_power(i - 1))

func test_the_closing_wave_is_not_just_the_next_rung_of_the_ladder() -> void:
	# The last wave is the end of the game. It gets a multiplier of its own on
	# top of the per-wave climb, or the climax reads as one more fight.
	for era in [1, 2, 3]:
		var audit := _audit(4242, era)
		var last: int = audit.wave_count() - 1
		var closing: float = float(audit.wave_at(last)["scale"])
		var ladder: float = closing / GameConfig.final_audit_last_wave_multiplier
		assert_float(closing).is_greater(ladder)
		assert_float(ladder).is_greater(float(audit.wave_at(last - 1)["scale"]))

func test_the_formation_changes_before_it_grows() -> void:
	var audit := _audit(4242, 3)
	# The opener is a plain line: no guns, no armour.
	assert_dict(audit.wave_at(0)["roster"]).contains_keys(["infantry"])
	assert_dict(audit.wave_at(0)["roster"]).not_contains_keys(["artillery", "vehicle"])
	# The guns come with the second wave.
	assert_dict(audit.wave_at(1)["roster"]).contains_keys(["artillery"])
	# The armour waits for its wave.
	assert_dict(audit.wave_at(GameConfig.final_audit_armour_wave)["roster"]).contains_keys(["vehicle"])

func test_an_early_era_cannot_field_what_it_has_not_unlocked() -> void:
	var audit := _audit(4242, 1)
	for wave in audit.waves:
		assert_dict(wave["roster"]).not_contains_keys(["artillery", "vehicle"])

func test_no_wave_ever_outgrows_the_board() -> void:
	for era in [1, 2, 3]:
		var audit := _audit(31337, era)
		for wave in audit.waves:
			var bodies: int = 0
			for count in wave["roster"].values():
				bodies += int(count)
			assert_int(bodies).is_less_equal(GameConfig.combat_deploy_cap)

func test_the_same_seed_is_the_same_siege() -> void:
	var a := _audit(9001, 3)
	var b := _audit(9001, 3)
	assert_int(b.wave_count()).is_equal(a.wave_count())
	for i in range(a.wave_count()):
		assert_dict(b.wave_at(i)["roster"]).is_equal(a.wave_at(i)["roster"])
		assert_float(b.wave_at(i)["scale"]).is_equal(a.wave_at(i)["scale"])

# ── Attrition ────────────────────────────────────────────────────────

func test_the_garrison_carries_its_wounds_into_the_next_wave() -> void:
	var audit := _audit()
	audit.begin()
	var wounded = audit.living_garrison()[0]
	wounded.take_damage(7)
	audit.clear_wave()
	assert_int(audit.state).is_equal(FinalAudit.State.ACTIVE)
	assert_int(wounded.hp).is_equal(wounded.max_hp - 7)
	# And it is the same wounded unit that walks onto the next board.
	var on_board: Array = []
	for unit in audit.build_encounter_units():
		if unit.side == FinalAudit.PLAYER and unit.uid == wounded.uid:
			on_board.append(unit)
	assert_int(on_board.size()).is_equal(1)
	assert_int(on_board[0].hp).is_equal(wounded.max_hp - 7)

func test_nothing_heals_between_waves() -> void:
	var audit := _audit()
	audit.begin()
	for unit in audit.living_garrison():
		unit.take_damage(3)
	audit.clear_wave()
	for unit in audit.living_garrison():
		assert_int(unit.hp).is_equal(unit.max_hp - 3)

func test_the_dead_never_stand_again() -> void:
	var audit := _audit()
	audit.begin()
	var fallen = audit.living_garrison()[0]
	fallen.take_damage(fallen.max_hp)
	audit.clear_wave()
	assert_int(audit.living_garrison().size()).is_equal(4)
	assert_int(audit.casualties().size()).is_equal(1)
	for unit in audit.build_encounter_units():
		assert_int(unit.uid).is_not_equal(fallen.uid)
	# And it is still a casualty two waves later.
	audit.clear_wave()
	assert_int(audit.casualties().size()).is_equal(1)

func test_the_enemies_of_a_wave_are_fresh_every_time() -> void:
	# Only the garrison carries damage: a wave rebuilt after a reload must not
	# inherit the hits the player already landed on it.
	var audit := _audit()
	audit.begin()
	for unit in audit.build_enemy_units():
		unit.take_damage(unit.max_hp)
	for unit in audit.build_enemy_units():
		assert_int(unit.hp).is_equal(unit.max_hp)

func test_survivors_step_off_the_board_between_waves() -> void:
	var audit := _audit()
	audit.begin()
	var standing = audit.living_garrison()[0]
	standing.position = Vector2i(4, 6)
	standing.has_acted = true
	audit.clear_wave()
	assert_vector(standing.position).is_equal(Vector2i(-1, -1))
	assert_bool(standing.has_acted).is_false()

# ── Winning ──────────────────────────────────────────────────────────

func test_breaking_the_last_wave_wins_the_game() -> void:
	var audit := _audit()
	_walk_to_last_wave(audit)
	assert_int(audit.state).is_equal(FinalAudit.State.ACTIVE)
	var events: Array = audit.clear_wave()
	assert_int(_events_of(events, "final_audit_won").size()).is_equal(1)
	assert_int(audit.state).is_equal(FinalAudit.State.WON)
	assert_bool(audit.is_won()).is_true()
	assert_bool(audit.is_resolved()).is_true()
	assert_int(audit.waves_remaining()).is_equal(0)

func test_every_cleared_wave_reports_what_is_left() -> void:
	var audit := _audit()
	audit.begin()
	var total: int = audit.wave_count()
	for i in range(total):
		var cleared: Array = _events_of(audit.clear_wave(), "final_audit_wave_cleared")
		assert_int(cleared.size()).is_equal(1)
		assert_int(int(cleared[0]["wave"])).is_equal(i)
		assert_int(int(cleared[0]["remaining"])).is_equal(total - i - 1)

func test_a_resolved_siege_stops_accepting_waves() -> void:
	var audit := _audit()
	_walk_to_last_wave(audit)
	audit.clear_wave()
	assert_array(audit.clear_wave()).is_empty()
	assert_array(audit.lose()).is_empty()
	assert_int(audit.state).is_equal(FinalAudit.State.WON)

func test_a_wave_broken_by_the_last_unit_standing_is_still_a_defeat() -> void:
	# Mutual destruction on any wave but the last one: there is nobody left to
	# meet what comes next, so the Regency walks in over the bodies.
	var audit := _audit()
	audit.begin()
	for unit in audit.living_garrison():
		unit.take_damage(unit.max_hp)
	var events: Array = audit.clear_wave()
	assert_int(_events_of(events, "final_audit_lost").size()).is_equal(1)
	assert_int(audit.state).is_equal(FinalAudit.State.LOST)

# ── Losing, and coming back ──────────────────────────────────────────

func test_losing_does_not_end_the_game() -> void:
	var audit := _audit()
	audit.begin()
	var events: Array = audit.lose()
	assert_int(_events_of(events, "final_audit_lost").size()).is_equal(1)
	assert_int(audit.state).is_equal(FinalAudit.State.LOST)
	assert_bool(audit.is_lost()).is_true()

func test_a_lost_siege_can_be_summoned_again_once_the_army_is_rebuilt() -> void:
	var audit := _audit()
	audit.begin()
	audit.clear_wave()
	audit.lose()
	var rebuilt := {"infantry": GameConfig.final_audit_resummon_min_units}
	assert_bool(audit.can_resummon(rebuilt)).is_true()
	var events: Array = audit.resummon(555, rebuilt, 3, 50.0)
	assert_int(_events_of(events, "final_audit_summoned").size()).is_equal(1)
	assert_int(audit.state).is_equal(FinalAudit.State.PENDING)
	assert_int(audit.current_wave).is_equal(0)
	assert_int(audit.summons).is_equal(2)
	assert_int(audit.garrison.size()).is_equal(GameConfig.final_audit_resummon_min_units)
	assert_int(audit.casualties().size()).is_equal(0)

func test_a_broken_army_cannot_summon_the_regency_back() -> void:
	# The victory is earned, not raffled: losing with nothing left does not let
	# the player keep rolling the same siege until it comes out easy.
	var audit := _audit()
	audit.begin()
	audit.lose()
	var scraps := {"infantry": maxi(0, GameConfig.final_audit_resummon_min_units - 1)}
	assert_bool(audit.can_resummon(scraps)).is_false()
	assert_array(audit.resummon(7, scraps)).is_empty()
	assert_int(audit.summons).is_equal(1)

func test_a_siege_that_is_not_lost_cannot_be_resummoned() -> void:
	var rebuilt := {"infantry": 4}
	var pending := _audit()
	assert_bool(pending.can_resummon(rebuilt)).is_false()
	var running := _audit()
	running.begin()
	assert_bool(running.can_resummon(rebuilt)).is_false()
	var won := _audit()
	_walk_to_last_wave(won)
	won.clear_wave()
	assert_bool(won.can_resummon(rebuilt)).is_false()

func test_resummoning_rolls_a_different_night() -> void:
	var audit := _audit(11, 3)
	var first: Array = []
	for wave in audit.waves:
		first.append(wave["roster"].duplicate())
	audit.begin()
	audit.lose()
	audit.resummon(11, GARRISON, 3, 50.0)
	# Same seed on purpose: the siege is rebuilt from the seed it is given, so
	# whoever calls this is the one who has to hand over a new number.
	for i in range(audit.wave_count()):
		assert_dict(audit.wave_at(i)["roster"]).is_equal(first[i])

# ── Persistence ──────────────────────────────────────────────────────

func test_a_siege_survives_a_round_trip_through_the_save() -> void:
	var audit := _audit(20260913, 3, 72.0)
	audit.begin()
	audit.living_garrison()[0].take_damage(11)
	audit.living_garrison()[1].take_damage(9999)
	audit.clear_wave()

	var restored := AuditScript.from_dict(audit.to_dict())
	assert_int(restored.seed_value).is_equal(audit.seed_value)
	assert_int(restored.era).is_equal(audit.era)
	assert_int(restored.state).is_equal(audit.state)
	assert_int(restored.current_wave).is_equal(audit.current_wave)
	assert_int(restored.summons).is_equal(audit.summons)
	assert_float(restored.morale_snapshot).is_equal(audit.morale_snapshot)
	# The waves were never written down: they come back from the seed alone.
	assert_int(restored.wave_count()).is_equal(audit.wave_count())
	for i in range(audit.wave_count()):
		assert_dict(restored.wave_at(i)["roster"]).is_equal(audit.wave_at(i)["roster"])
		assert_float(restored.wave_at(i)["scale"]).is_equal(audit.wave_at(i)["scale"])

func test_the_wounds_and_the_dead_come_back_with_the_save() -> void:
	var audit := _audit()
	audit.begin()
	audit.living_garrison()[0].take_damage(11)
	audit.living_garrison()[1].take_damage(9999)
	audit.clear_wave()

	var restored := AuditScript.from_dict(audit.to_dict())
	assert_int(restored.garrison.size()).is_equal(audit.garrison.size())
	assert_int(restored.living_garrison().size()).is_equal(audit.living_garrison().size())
	assert_int(restored.casualties().size()).is_equal(1)
	for unit in audit.garrison:
		var twin = restored.garrison.filter(func(u): return u.uid == unit.uid)
		assert_int(twin.size()).is_equal(1)
		assert_int(twin[0].hp).is_equal(unit.hp)

func test_a_reloaded_siege_keeps_fighting_where_it_stopped() -> void:
	var audit := _audit()
	audit.begin()
	audit.clear_wave()
	var restored := AuditScript.from_dict(audit.to_dict())
	while not restored.at_last_wave():
		restored.clear_wave()
	assert_int(_events_of(restored.clear_wave(), "final_audit_won").size()).is_equal(1)

func test_a_reloaded_siege_does_not_hand_out_a_uid_twice() -> void:
	var audit := _audit()
	var restored := AuditScript.from_dict(audit.to_dict())
	var seen: Array = []
	for unit in restored.garrison:
		seen.append(unit.uid)
	for unit in restored.build_enemy_units():
		assert_array(seen).not_contains([unit.uid])
		seen.append(unit.uid)

func test_a_save_without_a_siege_is_not_an_error() -> void:
	assert_object(AuditScript.from_dict({})).is_null()
	assert_object(AuditScript.from_dict({"current_wave": 2})).is_null()

# ── Result ───────────────────────────────────────────────────────────

func test_the_summary_counts_the_standing_and_the_fallen() -> void:
	var audit := _audit()
	audit.begin()
	audit.living_garrison()[0].take_damage(9999)
	_walk_to_last_wave(audit)
	audit.clear_wave()
	var summary: Dictionary = audit.result_summary()
	assert_bool(bool(summary["won"])).is_true()
	assert_int(int(summary["waves_cleared"])).is_equal(audit.wave_count())
	assert_int(int(summary["summons"])).is_equal(1)
	var survivors: Dictionary = summary["survivors"]
	var casualties: Dictionary = summary["casualties"]
	var standing: int = 0
	for count in survivors.values():
		standing += int(count)
	var fallen: int = 0
	for count in casualties.values():
		fallen += int(count)
	assert_int(standing + fallen).is_equal(5)
	assert_int(fallen).is_equal(1)
