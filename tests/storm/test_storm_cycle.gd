extends GdUnitTestSuite
## The storm is the clock the whole game is measured against. If the clock drifts,
## skips a phase or forgets to re-arm, the pressure the game is built on quietly
## disappears — and nothing else fails loudly enough to notice.

const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")

func _cycle() -> StormCycle:
	return StormCycleScript.create()

func _kinds(events: Array) -> Array:
	var names: Array = []
	for event in events:
		names.append(event.get("e", ""))
	return names

## Runs the clock forward in small steps, collecting everything it emits.
func _run(cycle: StormCycle, seconds: float, step: float = 0.5) -> Array:
	var collected: Array = []
	var elapsed := 0.0
	while elapsed < seconds:
		collected.append_array(cycle.advance(step))
		elapsed += step
	return collected

# ── It starts quiet ──────────────────────────────────────────────────

func test_a_new_cycle_starts_calm() -> void:
	var cycle := _cycle()
	assert_int(cycle.phase).is_equal(StormCycle.Phase.CALM)
	assert_bool(cycle.is_threatening()).is_false()

func test_the_first_storm_has_the_long_fuse() -> void:
	# The first one has to teach the cycle, not end the run.
	var cycle := _cycle()
	assert_float(cycle.seconds_left).is_equal_approx(GameConfig.get_storm_interval(true), 0.01)
	assert_bool(GameConfig.storm_first_interval > GameConfig.storm_interval).is_true()

func test_the_first_storm_is_the_gentlest() -> void:
	assert_int(_cycle().severity).is_equal(GameConfig.storm_first_severity)

# ── The phases run in order ──────────────────────────────────────────

func test_calm_gives_way_to_a_warning_before_the_storm() -> void:
	var cycle := _cycle()
	var events := _run(cycle, GameConfig.get_storm_interval(true) + 1.0)
	assert_array(_kinds(events)).contains(["incoming"])
	assert_int(cycle.phase).is_equal(StormCycle.Phase.WARNING)

func test_the_warning_always_comes_first() -> void:
	# The warning IS the mechanic. A storm that lands with no notice is a random
	# event, and the player cannot prepare for those.
	var cycle := _cycle()
	var events := _run(cycle, GameConfig.get_storm_interval(true) + GameConfig.get_storm_warning() + 1.0)
	var order := _kinds(events)
	assert_int(order.find("incoming")).is_less(order.find("storm_started"))

func test_the_storm_lands_after_the_warning_runs_out() -> void:
	var cycle := _cycle()
	_run(cycle, GameConfig.get_storm_interval(true) + GameConfig.get_storm_warning() + 1.0)
	assert_int(cycle.phase).is_equal(StormCycle.Phase.STORM)
	assert_bool(cycle.is_storming()).is_true()

func test_the_assessors_come_after_the_ash_not_during() -> void:
	# Ruin first, bill second — always in that order.
	var cycle := _cycle()
	var total: float = GameConfig.get_storm_interval(true) + GameConfig.get_storm_warning() \
		+ GameConfig.get_storm_duration() + 1.0
	var order := _kinds(_run(cycle, total))
	assert_int(order.find("storm_started")).is_less(order.find("tithe"))
	assert_int(order.find("storm_ended")).is_less_equal(order.find("tithe"))
	assert_int(cycle.phase).is_equal(StormCycle.Phase.TITHE)

# ── The player can see it coming ─────────────────────────────────────

func test_the_countdown_to_impact_shrinks() -> void:
	var cycle := _cycle()
	var first: float = cycle.seconds_until_impact()
	_run(cycle, 10.0)
	assert_float(cycle.seconds_until_impact()).is_less(first)

func test_the_countdown_spans_calm_and_warning() -> void:
	# During calm it must already include the warning window, or the number would
	# jump when the warning opens.
	var cycle := _cycle()
	assert_float(cycle.seconds_until_impact()).is_equal_approx(
		GameConfig.get_storm_interval(true) + GameConfig.get_storm_warning(), 0.01)

func test_impact_reads_zero_once_it_is_overhead() -> void:
	var cycle := _cycle()
	_run(cycle, GameConfig.get_storm_interval(true) + GameConfig.get_storm_warning() + 1.0)
	assert_float(cycle.seconds_until_impact()).is_equal(0.0)

# ── While it is overhead ─────────────────────────────────────────────

func test_the_storm_bites_repeatedly_while_it_lasts() -> void:
	var cycle := _cycle()
	_run(cycle, GameConfig.get_storm_interval(true) + GameConfig.get_storm_warning() + 0.6)
	var ticks := 0
	for event in _run(cycle, GameConfig.get_storm_duration() * 0.8):
		if event.get("e", "") == "storm_tick":
			ticks += 1
	assert_int(ticks).is_greater(0)

func test_nothing_bites_during_the_calm() -> void:
	var cycle := _cycle()
	assert_array(_kinds(_run(cycle, 20.0))).not_contains(["storm_tick"])

# ── The clock holds for the fight, then re-arms ───────────────────────

func test_the_clock_stops_while_the_assessors_are_on_the_board() -> void:
	var cycle := _cycle()
	var total: float = GameConfig.get_storm_interval(true) + GameConfig.get_storm_warning() \
		+ GameConfig.get_storm_duration() + 1.0
	_run(cycle, total)
	assert_bool(cycle.is_collecting()).is_true()
	# Time passes and nothing happens: the world waits for the fight.
	assert_array(_run(cycle, 120.0)).is_empty()
	assert_int(cycle.phase).is_equal(StormCycle.Phase.TITHE)

func test_settling_the_tithe_rearms_the_clock() -> void:
	var cycle := _cycle()
	var total: float = GameConfig.get_storm_interval(true) + GameConfig.get_storm_warning() \
		+ GameConfig.get_storm_duration() + 1.0
	_run(cycle, total)
	cycle.settle_tithe(0, 1)
	assert_int(cycle.phase).is_equal(StormCycle.Phase.CALM)
	assert_float(cycle.seconds_left).is_equal_approx(GameConfig.get_storm_interval(false), 0.01)

func test_surviving_one_is_counted() -> void:
	var cycle := _cycle()
	var total: float = GameConfig.get_storm_interval(true) + GameConfig.get_storm_warning() \
		+ GameConfig.get_storm_duration() + 1.0
	_run(cycle, total)
	cycle.settle_tithe(0, 1)
	assert_int(cycle.storms_survived).is_equal(1)

func test_settling_outside_the_collection_does_nothing() -> void:
	var cycle := _cycle()
	assert_array(cycle.settle_tithe(0, 1)).is_empty()
	assert_int(cycle.storms_survived).is_equal(0)

func test_the_second_storm_uses_the_short_fuse() -> void:
	var cycle := _cycle()
	var total: float = GameConfig.get_storm_interval(true) + GameConfig.get_storm_warning() \
		+ GameConfig.get_storm_duration() + 1.0
	_run(cycle, total)
	cycle.settle_tithe(0, 1)
	assert_bool(cycle.seconds_left < GameConfig.get_storm_interval(true)).is_true()

# ── Severity: growing is what puts you in the ledger ─────────────────

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

# ── Persistence ──────────────────────────────────────────────────────

func test_a_cycle_survives_a_round_trip() -> void:
	var cycle := _cycle()
	_run(cycle, GameConfig.get_storm_interval(true) + 1.0)   # into the warning
	var restored: StormCycle = StormCycleScript.from_dict(cycle.to_dict())
	assert_int(restored.phase).is_equal(cycle.phase)
	assert_float(restored.seconds_left).is_equal_approx(cycle.seconds_left, 0.01)
	assert_int(restored.severity).is_equal(cycle.severity)

func test_saving_mid_collection_forgives_the_fight() -> void:
	# The board is gone when the save reloads, so the tithe cannot be resumed.
	var cycle := _cycle()
	var total: float = GameConfig.get_storm_interval(true) + GameConfig.get_storm_warning() \
		+ GameConfig.get_storm_duration() + 1.0
	_run(cycle, total)
	var restored: StormCycle = StormCycleScript.from_dict(cycle.to_dict())
	assert_int(restored.phase).is_equal(StormCycle.Phase.CALM)
	assert_bool(restored.seconds_left > 0.0).is_true()

func test_an_empty_save_starts_a_fresh_cycle() -> void:
	var restored: StormCycle = StormCycleScript.from_dict({})
	assert_int(restored.phase).is_equal(StormCycle.Phase.CALM)
	assert_bool(restored.seconds_left > 0.0).is_true()
