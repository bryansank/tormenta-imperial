extends GdUnitTestSuite
## The only path that ever shrinks the army. If it miscounts, the player loses
## units they still had — or keeps units that died — and Military Power lies.
##
## Touches the real ArmyManager autoload, so every test restores it afterwards.

var _saved: Dictionary = {}

func before_test() -> void:
	_saved = ArmyManager.get_save_data()
	ArmyManager.reset()

func after_test() -> void:
	ArmyManager.load_save_data(_saved)

func _given(units: Dictionary) -> void:
	ArmyManager.load_save_data({"units": units, "training": [], "upkeep_accum": 0.0})

# ── The normal case ──────────────────────────────────────────────────

func test_removing_units_subtracts_them_from_the_roster() -> void:
	_given({"infantry": 5, "artillery": 2})
	ArmyManager.remove_units({"infantry": 2})
	assert_int(ArmyManager.get_count("infantry")).is_equal(3)
	assert_int(ArmyManager.get_count("artillery")).is_equal(2)

func test_it_reports_what_actually_died() -> void:
	_given({"infantry": 5})
	var removed := ArmyManager.remove_units({"infantry": 2})
	assert_int(int(removed["infantry"])).is_equal(2)

func test_several_kinds_at_once() -> void:
	_given({"infantry": 4, "artillery": 3, "vehicle": 1})
	ArmyManager.remove_units({"infantry": 1, "vehicle": 1})
	assert_int(ArmyManager.get_count("infantry")).is_equal(3)
	assert_int(ArmyManager.get_count("artillery")).is_equal(3)
	assert_int(ArmyManager.get_count("vehicle")).is_equal(0)

# ── Where it would go wrong ──────────────────────────────────────────

func test_you_cannot_lose_more_than_you_had() -> void:
	_given({"infantry": 2})
	var removed := ArmyManager.remove_units({"infantry": 5})
	assert_int(ArmyManager.get_count("infantry")).is_equal(0)
	assert_int(int(removed["infantry"])).is_equal(2)   # not 5

func test_the_count_never_goes_negative() -> void:
	_given({"infantry": 1})
	ArmyManager.remove_units({"infantry": 99})
	assert_int(ArmyManager.get_count("infantry")).is_equal(0)
	assert_int(ArmyManager.get_total_units()).is_equal(0)

func test_losing_a_kind_you_never_had_changes_nothing() -> void:
	_given({"infantry": 3})
	var removed := ArmyManager.remove_units({"vehicle": 2})
	assert_bool(removed.is_empty()).is_true()
	assert_int(ArmyManager.get_count("infantry")).is_equal(3)

func test_zero_and_negative_losses_are_ignored() -> void:
	_given({"infantry": 3})
	assert_bool(ArmyManager.remove_units({"infantry": 0}).is_empty()).is_true()
	assert_bool(ArmyManager.remove_units({"infantry": -2}).is_empty()).is_true()
	assert_int(ArmyManager.get_count("infantry")).is_equal(3)

func test_an_empty_loss_list_is_harmless() -> void:
	_given({"infantry": 3})
	assert_bool(ArmyManager.remove_units({}).is_empty()).is_true()
	assert_int(ArmyManager.get_count("infantry")).is_equal(3)

# ── Military Power has to follow ─────────────────────────────────────

func test_military_power_drops_with_the_casualties() -> void:
	_given({"infantry": 3})
	var before: int = ArmyManager.get_power()
	ArmyManager.remove_units({"infantry": 1})
	var after: int = ArmyManager.get_power()
	assert_int(after).is_less(before)
	assert_int(after).is_equal(before - int(GameConfig.get_unit_def("infantry").get("power", 0)))

func test_wiping_the_army_leaves_zero_power() -> void:
	_given({"infantry": 2, "artillery": 1})
	ArmyManager.remove_units({"infantry": 2, "artillery": 1})
	assert_int(ArmyManager.get_power()).is_equal(0)
	assert_int(ArmyManager.get_total_units()).is_equal(0)

# ── The roster stays clean ───────────────────────────────────────────

func test_a_wiped_out_kind_leaves_no_leftover_entry() -> void:
	# A lingering "infantry: 0" would show an empty row in the army panel.
	_given({"infantry": 2})
	ArmyManager.remove_units({"infantry": 2})
	assert_bool(ArmyManager.get_save_data()["units"].has("infantry")).is_false()

func test_casualties_announce_themselves() -> void:
	# The army panel and Military Power only refresh on this signal.
	_given({"infantry": 2})
	var monitor := monitor_signals(EventBus)
	ArmyManager.remove_units({"infantry": 1})
	await assert_signal(monitor).is_emitted("army_changed")
