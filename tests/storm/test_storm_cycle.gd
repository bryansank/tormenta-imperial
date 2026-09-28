extends GdUnitTestSuite
## The storm is the clock the whole game is measured against. If the clock drifts,
## skips a phase or forgets to re-arm, the pressure the game is built on quietly
## disappears — and nothing else fails loudly enough to notice.
##
## The cycle rolls dice now (when the calm ends, and whether a warning amounts to
## anything), so every test here either seeds the cycle or pins the odds. A test
## that leaves either to chance is a test that fails once a fortnight.

const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")

## Any fixed seed does; this one is just a date.
const SEED := 20260913

var _saved_false_alarm: float = 0.0

func before_test() -> void:
	_saved_false_alarm = GameConfig.storm_false_alarm_chance

func after_test() -> void:
	GameConfig.storm_false_alarm_chance = _saved_false_alarm

# ── Helpers ──────────────────────────────────────────────────────────

func _cycle(rng_seed: int = SEED) -> StormCycle:
	return StormCycleScript.create(rng_seed)

## A cycle whose warning is guaranteed to turn into weather. Most tests here are
## about what happens after the warning, not about the coin flip itself.
func _real_storm_cycle(rng_seed: int = SEED) -> StormCycle:
	GameConfig.storm_false_alarm_chance = 0.0
	return _cycle(rng_seed)

## A cycle whose warning is guaranteed to come to nothing.
func _false_alarm_cycle(rng_seed: int = SEED) -> StormCycle:
	GameConfig.storm_false_alarm_chance = 1.0
	return _cycle(rng_seed)

func _kinds(events: Array) -> Array:
	var names: Array = []
	for event in events:
		names.append(event.get("e", ""))
	return names

func _first_of(events: Array, kind: String) -> Dictionary:
	for event in events:
		if event.get("e", "") == kind:
			return event
	return {}

## Runs the clock forward in small steps, collecting everything it emits.
func _run(cycle: StormCycle, seconds: float, step: float = 0.5) -> Array:
	var collected: Array = []
	var elapsed := 0.0
	while elapsed < seconds:
		collected.append_array(cycle.advance(step))
		elapsed += step
	return collected

## Seconds from a fresh cycle to each phase, with a margin to land inside it.
func _to_warning() -> float:
	return GameConfig.get_storm_first_interval() + 1.0

func _to_ash() -> float:
	return _to_warning() + GameConfig.get_storm_warning()

func _to_storm() -> float:
	return _to_ash() + GameConfig.get_storm_ash_duration()

func _to_tithe() -> float:
	return _to_storm() + GameConfig.get_storm_duration()

# ── It starts quiet ──────────────────────────────────────────────────

func test_a_new_cycle_starts_calm() -> void:
	var cycle := _cycle()
	assert_int(cycle.phase).is_equal(StormCycle.Phase.CALM)
	assert_bool(cycle.is_threatening()).is_false()

func test_the_first_storm_has_the_long_fuse() -> void:
	# The first one has to teach the cycle, not end the run: no calm that comes
	# later is ever allowed to be longer than this one.
	var cycle := _cycle()
	assert_float(cycle.seconds_left).is_equal_approx(GameConfig.get_storm_first_interval(), 0.01)
	assert_bool(GameConfig.storm_first_interval >= GameConfig.storm_interval_max).is_true()
	assert_bool(GameConfig.storm_first_interval > GameConfig.storm_interval_min).is_true()

func test_the_first_storm_is_the_gentlest() -> void:
	assert_int(_cycle().severity).is_equal(GameConfig.storm_first_severity)

# ── The five phases run in order ─────────────────────────────────────

func test_calm_gives_way_to_a_warning_before_anything_falls() -> void:
	var cycle := _real_storm_cycle()
	var events := _run(cycle, _to_warning())
	assert_array(_kinds(events)).contains(["incoming"])
	assert_int(cycle.phase).is_equal(StormCycle.Phase.WARNING)

func test_the_warning_always_comes_first() -> void:
	# The warning IS the mechanic. Ash that lands with no notice is a random
	# event, and the player cannot prepare for those.
	var cycle := _real_storm_cycle()
	var order := _kinds(_run(cycle, _to_ash()))
	assert_int(order.find("incoming")).is_less(order.find("ash_started"))

func test_the_ash_falls_before_the_storm() -> void:
	# The new middle phase: dirty air first, and only then the thing that breaks
	# roofs. It is the ramp that makes the storm readable while it happens.
	var cycle := _real_storm_cycle()
	_run(cycle, _to_ash())
	assert_int(cycle.phase).is_equal(StormCycle.Phase.ASH)
	assert_bool(cycle.is_ashfall()).is_true()
	assert_bool(cycle.is_storming()).is_false()

func test_the_storm_follows_the_ash() -> void:
	var cycle := _real_storm_cycle()
	var order := _kinds(_run(cycle, _to_storm()))
	assert_int(order.find("ash_started")).is_less(order.find("storm_started"))
	assert_int(cycle.phase).is_equal(StormCycle.Phase.STORM)
	assert_bool(cycle.is_storming()).is_true()

func test_the_assessors_come_after_the_storm_not_during() -> void:
	# Ruin first, bill second — always in that order.
	var cycle := _real_storm_cycle()
	var order := _kinds(_run(cycle, _to_tithe()))
	assert_int(order.find("storm_started")).is_less(order.find("tithe"))
	assert_int(order.find("storm_ended")).is_less_equal(order.find("tithe"))
	assert_int(cycle.phase).is_equal(StormCycle.Phase.TITHE)

func test_each_phase_lasts_exactly_what_it_says() -> void:
	# Arrival is uncertain; the shape of the thing once it starts never is.
	var cycle := _real_storm_cycle()
	_run(cycle, _to_warning())
	assert_float(cycle.seconds_left).is_less_equal(GameConfig.get_storm_warning())
	_run(cycle, GameConfig.get_storm_warning())
	assert_float(cycle.seconds_left).is_less_equal(GameConfig.get_storm_ash_duration())
	_run(cycle, GameConfig.get_storm_ash_duration())
	assert_float(cycle.seconds_left).is_less_equal(GameConfig.get_storm_duration())

# ── The warning costs nothing ────────────────────────────────────────

func test_nothing_bites_during_the_calm() -> void:
	assert_array(_kinds(_run(_real_storm_cycle(), 20.0))).not_contains(["storm_tick"])

func test_the_warning_does_not_bite() -> void:
	# No morale, no production, no roofs. It is the one clean window in which to
	# decide, and a warning that already hurts is just the storm starting early.
	var cycle := _real_storm_cycle()
	_run(cycle, _to_warning())
	assert_int(cycle.phase).is_equal(StormCycle.Phase.WARNING)
	var during := _run(cycle, GameConfig.get_storm_warning() * 0.5)
	assert_array(_kinds(during)).not_contains(["storm_tick"])
	assert_int(cycle.phase).is_equal(StormCycle.Phase.WARNING)

# ── While it is overhead ─────────────────────────────────────────────

func test_the_ash_bites_repeatedly_while_it_lasts() -> void:
	var cycle := _real_storm_cycle()
	_run(cycle, _to_ash())
	var ticks := 0
	for event in _run(cycle, GameConfig.get_storm_ash_duration() * 0.8):
		if event.get("e", "") == "storm_tick":
			ticks += 1
	assert_int(ticks).is_greater(0)

func test_the_storm_bites_repeatedly_while_it_lasts() -> void:
	var cycle := _real_storm_cycle()
	_run(cycle, _to_storm())
	var ticks := 0
	for event in _run(cycle, GameConfig.get_storm_duration() * 0.8):
		if event.get("e", "") == "storm_tick":
			ticks += 1
	assert_int(ticks).is_greater(0)

func test_every_bite_says_which_phase_it_came_from() -> void:
	# This tag is the whole reason StormManager can tell the two apart: ash costs
	# morale and production, the storm also takes buildings down. Untagged ticks
	# would quietly demolish the base during the ashfall.
	var ashfall := _real_storm_cycle()
	_run(ashfall, _to_ash())
	assert_int(ashfall.phase).is_equal(StormCycle.Phase.ASH)
	for event in _run(ashfall, GameConfig.get_storm_ash_duration() * 0.5):
		if event.get("e", "") == "storm_tick":
			assert_int(int(event["phase"])).is_equal(StormCycle.Phase.ASH)

	var overhead := _real_storm_cycle()
	_run(overhead, _to_storm())
	assert_int(overhead.phase).is_equal(StormCycle.Phase.STORM)
	for event in _run(overhead, GameConfig.get_storm_duration() * 0.5):
		if event.get("e", "") == "storm_tick":
			assert_int(int(event["phase"])).is_equal(StormCycle.Phase.STORM)

func test_only_the_storm_is_allowed_to_break_things() -> void:
	# Written as a claim about the cycle, since the demolition itself lives in
	# StormManager: no tick outside STORM may ever be tagged STORM, and that tag
	# is the only thing StormManager consults before reaching for a building.
	# Ash dirties, it does not demolish — that is what keeps the ashfall the last
	# window in which repairing a roof is worth the steel.
	var cycle := _real_storm_cycle()
	_run(cycle, _to_ash())
	for event in _run(cycle, GameConfig.get_storm_ash_duration() * 0.5):
		if event.get("e", "") == "storm_tick":
			assert_int(int(event["phase"])).is_not_equal(StormCycle.Phase.STORM)

func test_the_storm_costs_strictly_more_than_the_ash() -> void:
	# The two steps have to be genuinely different, or the middle phase is just
	# a longer storm with extra words.
	assert_float(GameConfig.storm_ash_production_multiplier).is_greater(
		GameConfig.storm_production_multiplier)
	assert_float(GameConfig.storm_morale_storm_multiplier).is_greater(1.0)

# ── The false alarm ──────────────────────────────────────────────────

func test_a_false_alarm_sends_the_sky_back_to_calm() -> void:
	var cycle := _false_alarm_cycle()
	var events := _run(cycle, _to_ash())
	assert_array(_kinds(events)).contains(["false_alarm"])
	assert_int(cycle.phase).is_equal(StormCycle.Phase.CALM)

func test_a_false_alarm_never_reaches_the_ash() -> void:
	var cycle := _false_alarm_cycle()
	var kinds := _kinds(_run(cycle, _to_ash()))
	assert_array(kinds).not_contains(["ash_started"])
	assert_array(kinds).not_contains(["storm_started"])

func test_a_false_alarm_defers_the_assessment_instead_of_forgiving_it() -> void:
	var cycle := _false_alarm_cycle()
	var before: int = cycle.effective_severity()
	_run(cycle, _to_ash())
	assert_int(cycle.deferred_severity).is_equal(GameConfig.storm_false_alarm_carry)
	assert_int(cycle.effective_severity()).is_greater(before)

func test_deferred_assessments_pile_up() -> void:
	# Two warnings that came to nothing are not two free passes.
	var cycle := _false_alarm_cycle()
	_run(cycle, _to_ash())
	_run(cycle, cycle.seconds_left + GameConfig.get_storm_warning() + 1.0)
	assert_int(cycle.deferred_severity).is_equal(GameConfig.storm_false_alarm_carry * 2)

func test_the_deferred_assessment_rides_the_next_real_storm() -> void:
	var cycle := _false_alarm_cycle()
	_run(cycle, _to_ash())
	var base: int = cycle.severity
	GameConfig.storm_false_alarm_chance = 0.0
	var events := _run(cycle, cycle.seconds_left + GameConfig.get_storm_warning()
		+ GameConfig.get_storm_ash_duration() + 2.0)
	var landed: Dictionary = _first_of(events, "storm_started")
	assert_dict(landed).is_not_empty()
	assert_int(int(landed["severity"])).is_equal(base + GameConfig.storm_false_alarm_carry)

func test_settling_the_tithe_squares_the_deferred_books() -> void:
	var cycle := _false_alarm_cycle()
	_run(cycle, _to_ash())
	GameConfig.storm_false_alarm_chance = 0.0
	_run(cycle, cycle.seconds_left + GameConfig.get_storm_warning()
		+ GameConfig.get_storm_ash_duration() + GameConfig.get_storm_duration() + 2.0)
	assert_bool(cycle.is_collecting()).is_true()
	cycle.settle_tithe(0, 1)
	assert_int(cycle.deferred_severity).is_equal(0)

func test_a_false_alarm_still_rearms_the_clock() -> void:
	var cycle := _false_alarm_cycle()
	_run(cycle, _to_ash())
	assert_bool(cycle.seconds_left > 0.0).is_true()

func test_both_outcomes_happen_at_the_stated_odds() -> void:
	# With the real odds restored: over a hundred seeds the sky must do both
	# things. If it only ever did one, the coin is not being flipped at all.
	var false_alarms := 0
	var real_storms := 0
	for rng_seed in range(100):
		var cycle := _cycle(rng_seed)
		var kinds := _kinds(_run(cycle, _to_ash()))
		if kinds.has("false_alarm"):
			false_alarms += 1
		if kinds.has("ash_started"):
			real_storms += 1
	assert_int(false_alarms).is_greater(0)
	assert_int(real_storms).is_greater(false_alarms)

# ── The calm is a range, not a metronome ─────────────────────────────

func test_the_next_calm_lands_inside_its_range() -> void:
	var cycle := _real_storm_cycle()
	_run(cycle, _to_tithe())
	cycle.settle_tithe(0, 1)
	assert_float(cycle.seconds_left).is_greater_equal(GameConfig.get_storm_interval_min())
	assert_float(cycle.seconds_left).is_less_equal(GameConfig.get_storm_interval_max())

func test_a_false_alarm_also_rolls_inside_the_range() -> void:
	var cycle := _false_alarm_cycle()
	_run(cycle, _to_ash())
	assert_float(cycle.seconds_left).is_greater_equal(GameConfig.get_storm_interval_min())
	assert_float(cycle.seconds_left).is_less_equal(GameConfig.get_storm_interval_max())

func test_the_calm_is_not_always_the_same_length() -> void:
	# A fixed interval turns the cycle into a spreadsheet column.
	var lengths := {}
	for rng_seed in range(20):
		var cycle := _real_storm_cycle(rng_seed)
		_run(cycle, _to_tithe())
		cycle.settle_tithe(0, 1)
		lengths[snappedf(cycle.seconds_left, 0.01)] = true
	assert_int(lengths.size()).is_greater(1)

func test_the_same_seed_gives_the_same_cycle() -> void:
	# The randomness lives in the cycle's own generator, never in the global
	# `randf()`. Reproducibility is the only reason a hundred headless cycles
	# are worth running at all.
	GameConfig.storm_false_alarm_chance = 0.25
	var left := StormCycleScript.create(4242)
	var right := StormCycleScript.create(4242)
	var a := _kinds(_run(left, _to_tithe()))
	var b := _kinds(_run(right, _to_tithe()))
	assert_array(a).is_equal(b)
	assert_float(left.seconds_left).is_equal_approx(right.seconds_left, 0.0001)

# ── Severity: the bill is not shown in advance ───────────────────────

func test_the_warning_does_not_say_how_hard_it_will_hit() -> void:
	# Knowing the size in advance turns preparing into arithmetic. The player is
	# meant to prepare for the worst, not to price it.
	var cycle := _real_storm_cycle()
	var warning: Dictionary = _first_of(_run(cycle, _to_warning()), "incoming")
	assert_dict(warning).is_not_empty()
	assert_bool(warning.has("severity")).is_false()

func test_the_severity_arrives_with_the_storm() -> void:
	var cycle := _real_storm_cycle()
	var landed: Dictionary = _first_of(_run(cycle, _to_storm()), "storm_started")
	assert_dict(landed).is_not_empty()
	assert_int(int(landed["severity"])).is_equal(cycle.effective_severity())

func test_a_bigger_base_draws_a_harder_storm() -> void:
	var small := StormCycleScript.compute_severity(0, 1)
	var big := StormCycleScript.compute_severity(GameConfig.storm_buildings_per_severity * 3, 1)
	assert_int(big).is_greater(small)

func test_a_later_era_draws_a_harder_storm() -> void:
	assert_int(StormCycleScript.compute_severity(0, 3)).is_greater(StormCycleScript.compute_severity(0, 1))

func test_severity_never_drops_below_one() -> void:
	assert_int(StormCycleScript.compute_severity(-50, 0)).is_equal(1)

func test_severity_is_capped() -> void:
	var huge := StormCycleScript.compute_severity(10000, 99)
	assert_int(huge).is_equal(GameConfig.storm_severity_max)

func test_deferred_severity_cannot_break_the_cap() -> void:
	var cycle := _cycle()
	cycle.severity = GameConfig.storm_severity_max
	cycle.deferred_severity = 99
	assert_int(cycle.effective_severity()).is_equal(GameConfig.storm_severity_max)

# ── The clock holds for the fight, then re-arms ───────────────────────

func test_the_clock_stops_while_the_assessors_are_on_the_board() -> void:
	var cycle := _real_storm_cycle()
	_run(cycle, _to_tithe())
	assert_bool(cycle.is_collecting()).is_true()
	# Time passes and nothing happens: the world waits for the fight.
	assert_array(_run(cycle, 120.0)).is_empty()
	assert_int(cycle.phase).is_equal(StormCycle.Phase.TITHE)

func test_settling_the_tithe_rearms_the_clock() -> void:
	var cycle := _real_storm_cycle()
	_run(cycle, _to_tithe())
	cycle.settle_tithe(0, 1)
	assert_int(cycle.phase).is_equal(StormCycle.Phase.CALM)
	assert_bool(cycle.seconds_left > 0.0).is_true()

func test_surviving_one_is_counted() -> void:
	var cycle := _real_storm_cycle()
	_run(cycle, _to_tithe())
	cycle.settle_tithe(0, 1)
	assert_int(cycle.storms_survived).is_equal(1)

func test_settling_outside_the_collection_does_nothing() -> void:
	var cycle := _cycle()
	assert_array(cycle.settle_tithe(0, 1)).is_empty()
	assert_int(cycle.storms_survived).is_equal(0)

func test_the_second_storm_uses_the_short_fuse() -> void:
	var cycle := _real_storm_cycle()
	_run(cycle, _to_tithe())
	cycle.settle_tithe(0, 1)
	assert_bool(cycle.seconds_left <= GameConfig.get_storm_first_interval()).is_true()

# ── Persistence ──────────────────────────────────────────────────────

func test_a_cycle_survives_a_round_trip() -> void:
	var cycle := _real_storm_cycle()
	_run(cycle, _to_warning())   # into the warning
	var restored: StormCycle = StormCycleScript.from_dict(cycle.to_dict())
	assert_int(restored.phase).is_equal(cycle.phase)
	assert_float(restored.seconds_left).is_equal_approx(cycle.seconds_left, 0.01)
	assert_int(restored.severity).is_equal(cycle.severity)

func test_a_deferred_assessment_survives_a_save() -> void:
	# Otherwise quitting after a false alarm would be a way to wipe the debt,
	# and the false alarm would cost nothing after all.
	var cycle := _false_alarm_cycle()
	_run(cycle, _to_ash())
	assert_int(cycle.deferred_severity).is_greater(0)
	var restored: StormCycle = StormCycleScript.from_dict(cycle.to_dict())
	assert_int(restored.deferred_severity).is_equal(cycle.deferred_severity)
	assert_int(restored.effective_severity()).is_equal(cycle.effective_severity())

func test_the_ashfall_survives_a_save() -> void:
	var cycle := _real_storm_cycle()
	_run(cycle, _to_ash())
	var restored: StormCycle = StormCycleScript.from_dict(cycle.to_dict())
	assert_int(restored.phase).is_equal(StormCycle.Phase.ASH)

func test_saving_mid_collection_forgives_the_fight() -> void:
	# The board is gone when the save reloads, so the tithe cannot be resumed.
	var cycle := _real_storm_cycle()
	_run(cycle, _to_tithe())
	var restored: StormCycle = StormCycleScript.from_dict(cycle.to_dict())
	assert_int(restored.phase).is_equal(StormCycle.Phase.CALM)
	assert_bool(restored.seconds_left > 0.0).is_true()

func test_an_empty_save_starts_a_fresh_cycle() -> void:
	var restored: StormCycle = StormCycleScript.from_dict({})
	assert_int(restored.phase).is_equal(StormCycle.Phase.CALM)
	assert_int(restored.deferred_severity).is_equal(0)
	assert_bool(restored.seconds_left > 0.0).is_true()

func test_a_save_from_before_the_ashfall_still_reloads_in_the_right_phase() -> void:
	# Phase 2 used to mean STORM and now means ASH. An unversioned save has to be
	# remapped, or an existing player reloads into the wrong half of the storm.
	var restored: StormCycle = StormCycleScript.from_dict({
		"phase": 2, "seconds_left": 12.0, "severity": 3, "storms_survived": 2, "first": false,
	})
	assert_int(restored.phase).is_equal(StormCycle.Phase.STORM)
	assert_int(restored.severity).is_equal(3)
	assert_int(restored.deferred_severity).is_equal(0)
