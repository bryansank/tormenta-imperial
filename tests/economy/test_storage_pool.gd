extends GdUnitTestSuite
## Storage is one shared bag, not a cap per resource. That single rule is what makes
## the market worth using, what makes spending before the Storm the right play, and
## what makes arriving full at the Tithe a decision instead of an oversight. If it
## quietly goes back to per-resource caps, none of those choices exist any more and
## nothing else in the game fails loudly enough to notice.
##
## Touches the real ResourceManager and GameConfig autoloads, so every test puts them
## back the way it found them.

const GOLD := ResourceManager.Type.GOLD
const STEEL := ResourceManager.Type.STEEL
const OIL := ResourceManager.Type.OIL
const WOOD := ResourceManager.Type.WOOD

var _saved_amounts: Dictionary = {}
var _saved_unlocks: Dictionary = {}
var _saved_warehouses := 0
var _saved_era := 1
var _saved_tech_bonus := 0

func before_test() -> void:
	_saved_amounts = {}
	for type in ResourceManager.get_all():
		_saved_amounts[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	_saved_unlocks = ResourceManager.get_unlock_state()
	_saved_warehouses = ResourceManager.get_warehouse_count()
	_saved_era = ResourceManager.get_era()
	_saved_tech_bonus = GameConfig.tech_storage_bonus
	GameConfig.tech_storage_bonus = 0

func after_test() -> void:
	GameConfig.tech_storage_bonus = _saved_tech_bonus
	ResourceManager.set_warehouse_count(_saved_warehouses)
	ResourceManager.set_era(_saved_era)
	ResourceManager.set_amounts(_saved_amounts)
	ResourceManager.set_unlock_state(_saved_unlocks)

## Puts the pool in a known state: era, warehouses and an exact stock of each resource.
func _given(era: int, warehouses: int, stock: Dictionary = {}) -> void:
	ResourceManager.set_era(era)
	ResourceManager.set_warehouse_count(warehouses)
	ResourceManager.set_amounts({
		"gold": int(stock.get("gold", 0)),
		"steel": int(stock.get("steel", 0)),
		"oil": int(stock.get("oil", 0)),
		"wood": int(stock.get("wood", 0)),
	})

# ── The cap scales with the era ──────────────────────────────────────

func test_each_era_widens_the_bag() -> void:
	assert_int(GameConfig.get_storage_cap(0, 1)).is_equal(600)
	assert_int(GameConfig.get_storage_cap(0, 2)).is_equal(800)
	assert_int(GameConfig.get_storage_cap(0, 3)).is_equal(1000)

func test_the_bag_never_shrinks_as_the_game_advances() -> void:
	var previous := 0
	for era in [1, 2, 3]:
		var cap: int = GameConfig.get_storage_cap(0, era)
		assert_int(cap).is_greater(previous)
		previous = cap

func test_an_era_outside_the_table_falls_back_instead_of_leaving_no_storage() -> void:
	# A corrupt save must not hand the player a zero-capacity warehouse.
	assert_int(GameConfig.get_storage_cap(0, 0)).is_equal(600)
	assert_int(GameConfig.get_storage_cap(0, -5)).is_equal(600)
	assert_int(GameConfig.get_storage_cap(0, 99)).is_equal(1000)

func test_the_manager_uses_the_era_it_was_told_about() -> void:
	_given(1, 0)
	assert_int(ResourceManager.get_storage_cap()).is_equal(600)
	ResourceManager.set_era(3)
	assert_int(ResourceManager.get_storage_cap()).is_equal(1000)

func test_the_era_advancing_widens_the_bag_without_anyone_asking() -> void:
	_given(1, 0)
	EventBus.era_advanced.emit(2)
	assert_int(ResourceManager.get_era()).is_equal(2)
	assert_int(ResourceManager.get_storage_cap()).is_equal(800)

# ── The cap scales with warehouses ───────────────────────────────────

func test_every_warehouse_adds_its_share() -> void:
	assert_int(GameConfig.get_storage_cap(1, 1)).is_equal(600 + 500)
	assert_int(GameConfig.get_storage_cap(3, 2)).is_equal(800 + 1500)
	assert_int(GameConfig.get_storage_cap(5, 3)).is_equal(1000 + 2500)

func test_research_stacks_on_top_of_era_and_warehouses() -> void:
	GameConfig.tech_storage_bonus = 200
	assert_int(GameConfig.get_storage_cap(1, 2)).is_equal(800 + 500 + 200)

## The whole endgame rests on this number: the biggest bag you can build in Era 3 is
## exactly what the HQ's level 3 upgrade costs, so winning means standing there full,
## with all five warehouses up — which is precisely when you have the most to lose.
func test_the_fullest_bag_is_exactly_the_price_of_victory() -> void:
	var max_warehouses: int = int(GameConfig.building_limits["warehouse"])
	var cap: int = GameConfig.get_storage_cap(max_warehouses, 3)
	var hq_final: Dictionary = GameConfig.hq_upgrade_costs[3]
	var price := 0
	for res_name in hq_final:
		price += int(hq_final[res_name])
	assert_int(cap).is_equal(3500)
	assert_int(price).is_equal(3500)
	assert_int(cap).is_equal(price)

# ── Era 1 has to hold the opening ────────────────────────

## The Era 1 cap is 600 for one reason: the opening has to be playable. The game
## hands out 300 gold + 200 wood and then asks for a sawmill (80/50) and a gold mine
## (120/80), 330 between them. At 300 the player started 200 over the limit and was
## losing harvest before making a single decision, which reads as a broken game
## rather than as pressure.
func test_a_brand_new_game_fits_in_the_bag_it_starts_with() -> void:
	var starting := 0
	for res_name in GameConfig.starting_resources:
		starting += int(GameConfig.starting_resources[res_name])
	assert_int(starting).is_equal(500)
	assert_int(GameConfig.get_storage_cap(0, 1)).is_equal(600)
	assert_int(GameConfig.get_storage_cap(0, 1)).is_greater(starting)

func test_a_new_game_is_not_trimmed_the_moment_it_loads() -> void:
	_given(1, 0, {"gold": 300, "wood": 200})
	assert_bool(ResourceManager.clamp_to_storage()).is_false()
	assert_int(ResourceManager.get_amount(GOLD)).is_equal(300)
	assert_int(ResourceManager.get_amount(WOOD)).is_equal(200)
	assert_bool(ResourceManager.is_storage_full()).is_false()
	assert_int(ResourceManager.get_free_space()).is_equal(100)

func test_the_first_two_buildings_are_paid_without_losing_anything() -> void:
	_given(1, 0, {"gold": 300, "wood": 200})
	# Sawmill 80g/50w, then gold mine 120g/80w.
	assert_bool(ResourceManager.spend_cost({GOLD: 80, WOOD: 50})).is_true()
	assert_bool(ResourceManager.spend_cost({GOLD: 120, WOOD: 80})).is_true()
	assert_int(ResourceManager.get_amount(GOLD)).is_equal(100)
	assert_int(ResourceManager.get_amount(WOOD)).is_equal(70)

func test_no_storage_warning_greets_the_player_on_the_first_ticks() -> void:
	# A "storage full" toast in the first minute would teach exactly the wrong lesson.
	_given(1, 0, {"gold": 300, "wood": 200})
	var notices := [0]
	var probe := func(_m: String, _c: String, _col: Color): notices[0] += 1
	EventBus.notification_posted.connect(probe)
	ResourceManager.clamp_to_storage()
	ResourceManager.add(WOOD, 6)   # first sawmill tick
	ResourceManager.add(GOLD, 8)   # first gold mine tick
	EventBus.notification_posted.disconnect(probe)
	assert_int(notices[0]).is_equal(0)
	assert_int(ResourceManager.get_amount(WOOD)).is_equal(206)
	assert_int(ResourceManager.get_amount(GOLD)).is_equal(308)

# ── add() competes against the shared free space ─────────────────────

func test_what_you_store_is_room_someone_else_loses() -> void:
	_given(1, 0)  # cap 600
	ResourceManager.add(GOLD, 500)
	assert_int(ResourceManager.get_free_space()).is_equal(100)
	ResourceManager.add(WOOD, 200)
	assert_int(ResourceManager.get_amount(WOOD)).is_equal(100)
	assert_int(ResourceManager.get_total_stored()).is_equal(600)

func test_a_single_resource_can_fill_the_whole_bag() -> void:
	_given(1, 0)
	ResourceManager.add(GOLD, 600)
	assert_int(ResourceManager.get_amount(GOLD)).is_equal(600)
	assert_bool(ResourceManager.is_storage_full()).is_true()
	assert_int(ResourceManager.get_free_space()).is_equal(0)

func test_a_full_bag_accepts_nothing_at_all() -> void:
	_given(1, 0, {"gold": 600})
	ResourceManager.add(WOOD, 50)
	assert_int(ResourceManager.get_amount(WOOD)).is_equal(0)
	assert_int(ResourceManager.get_total_stored()).is_equal(600)

func test_the_total_never_creeps_past_the_cap() -> void:
	_given(1, 0)
	for type in [GOLD, STEEL, OIL, WOOD]:
		ResourceManager.add(type, 500)
	assert_int(ResourceManager.get_total_stored()).is_equal(600)

func test_spending_makes_room_for_something_else() -> void:
	_given(1, 0, {"gold": 600})
	ResourceManager.spend(GOLD, 100)
	assert_int(ResourceManager.get_free_space()).is_equal(100)
	ResourceManager.add(WOOD, 250)
	assert_int(ResourceManager.get_amount(WOOD)).is_equal(100)

func test_a_new_warehouse_gives_back_the_room_that_was_being_wasted() -> void:
	_given(1, 0, {"gold": 600})
	assert_bool(ResourceManager.is_storage_full()).is_true()
	ResourceManager.set_warehouse_count(1)
	assert_int(ResourceManager.get_free_space()).is_equal(500)
	ResourceManager.add(WOOD, 400)
	assert_int(ResourceManager.get_amount(WOOD)).is_equal(400)

func test_losses_do_not_compete_for_room_and_still_stop_at_zero() -> void:
	_given(1, 0, {"wood": 50})
	ResourceManager.add(WOOD, -20)
	assert_int(ResourceManager.get_amount(WOOD)).is_equal(30)
	ResourceManager.add(WOOD, -999)
	assert_int(ResourceManager.get_amount(WOOD)).is_equal(0)

func test_adding_nothing_changes_nothing() -> void:
	_given(1, 0, {"wood": 50})
	ResourceManager.add(WOOD, 0)
	assert_int(ResourceManager.get_amount(WOOD)).is_equal(50)

# ── The overflow is lost, and the player is told ─────────────────────

func test_the_overflow_is_lost_not_queued() -> void:
	_given(1, 0, {"gold": 590})
	ResourceManager.add(WOOD, 100)
	assert_int(ResourceManager.get_amount(WOOD)).is_equal(10)
	assert_int(ResourceManager.get_total_stored()).is_equal(600)
	# And it does not reappear once room opens up again.
	ResourceManager.spend(GOLD, 590)
	assert_int(ResourceManager.get_amount(WOOD)).is_equal(10)

## Connected by hand on purpose: gdUnit's monitor_signals() frees the object it
## watches at teardown, and EventBus is an autoload — monitoring it kills the bus for
## every suite that runs afterwards, which fails them far away from the real cause.
func test_losing_harvest_announces_itself_with_how_much_was_lost() -> void:
	_given(1, 0, {"gold": 600})
	var seen := []
	var probe := func(res: String, lost: int, cap: int): seen.append([res, lost, cap])
	EventBus.storage_overflow.connect(probe)
	ResourceManager.add(WOOD, 40)
	EventBus.storage_overflow.disconnect(probe)
	assert_int(seen.size()).is_equal(1)
	assert_str(str(seen[0][0])).is_equal("wood")
	assert_int(int(seen[0][1])).is_equal(40)
	assert_int(int(seen[0][2])).is_equal(600)

func test_a_full_bag_still_reports_the_resource_so_the_hud_can_go_red() -> void:
	# Without this the counter would freeze on the last value that fit and the player
	# would never see that the bag stopped accepting anything.
	_given(1, 0, {"gold": 600})
	var fired := [0]
	var probe := func(_r: String, _n: int, _d: int): fired[0] += 1
	EventBus.resource_changed.connect(probe)
	ResourceManager.add(WOOD, 40)
	EventBus.resource_changed.disconnect(probe)
	assert_int(fired[0]).is_equal(1)

func test_the_player_is_warned_once_per_game_not_once_per_tick() -> void:
	# A toast on every production tick is noise, and noise gets ignored.
	_given(1, 0, {"gold": 600})
	var notices := [0]
	var probe := func(_m: String, _c: String, _col: Color): notices[0] += 1
	EventBus.notification_posted.connect(probe)
	for i in range(5):
		ResourceManager.add(WOOD, 10)
	EventBus.notification_posted.disconnect(probe)
	assert_int(notices[0]).is_equal(1)

func test_nothing_is_announced_while_everything_still_fits() -> void:
	_given(1, 0)
	var notices := [0]
	var probe := func(_m: String, _c: String, _col: Color): notices[0] += 1
	EventBus.notification_posted.connect(probe)
	ResourceManager.add(GOLD, 100)
	ResourceManager.add(WOOD, 100)
	EventBus.notification_posted.disconnect(probe)
	assert_int(notices[0]).is_equal(0)

# ── Old saves load trimmed, never corrupt ────────────────────────────

func test_a_save_that_still_fits_is_left_exactly_as_it_was() -> void:
	_given(3, 5, {"gold": 500, "steel": 400, "oil": 300, "wood": 200})
	assert_bool(ResourceManager.clamp_to_storage()).is_false()
	assert_int(ResourceManager.get_amount(GOLD)).is_equal(500)
	assert_int(ResourceManager.get_total_stored()).is_equal(1400)

func test_a_save_from_the_per_resource_days_loads_trimmed() -> void:
	# 800 of each was legal when every resource had its own 800-wide shelf.
	_given(1, 0, {"gold": 800, "steel": 800, "oil": 800, "wood": 800})
	assert_bool(ResourceManager.clamp_to_storage()).is_true()
	assert_int(ResourceManager.get_total_stored()).is_equal(600)

func test_the_trim_is_proportional_so_nobody_loses_a_whole_resource() -> void:
	# Emptying whatever the dictionary listed first would wipe this player's oil and
	# leave their gold untouched — a balance decision taken by iteration order.
	_given(1, 0, {"gold": 800, "wood": 400})
	ResourceManager.clamp_to_storage()
	assert_int(ResourceManager.get_amount(GOLD)).is_equal(400)
	assert_int(ResourceManager.get_amount(WOOD)).is_equal(200)
	assert_int(ResourceManager.get_total_stored()).is_equal(600)

func test_the_trim_lands_on_the_cap_exactly_even_with_awkward_rounding() -> void:
	# Truncating four shares leaves crumbs; dropping them would silently shrink the bag.
	# 333 x 600 / 1332 truncates to 149 apiece, four units short of the cap.
	_given(1, 0, {"gold": 333, "steel": 333, "oil": 333, "wood": 333})
	ResourceManager.clamp_to_storage()
	assert_int(ResourceManager.get_total_stored()).is_equal(600)

func test_a_trimmed_save_is_still_a_consistent_one() -> void:
	_given(1, 0, {"gold": 800, "steel": 800, "oil": 800, "wood": 800})
	ResourceManager.clamp_to_storage()
	for type in [GOLD, STEEL, OIL, WOOD]:
		assert_int(ResourceManager.get_amount(type)).is_greater_equal(0)
	assert_int(ResourceManager.get_free_space()).is_equal(0)
	assert_bool(ResourceManager.is_storage_full()).is_true()
	# And the pool accepts nothing more until something is spent.
	ResourceManager.add(GOLD, 100)
	assert_int(ResourceManager.get_total_stored()).is_equal(600)

func test_a_veteran_save_keeps_more_because_their_base_is_bigger() -> void:
	# The same old save on a finished Era 3 base loses nothing: the trim is about what
	# fits today, not a punishment for having played.
	_given(3, 5, {"gold": 800, "steel": 800, "oil": 800, "wood": 800})
	assert_bool(ResourceManager.clamp_to_storage()).is_false()
	assert_int(ResourceManager.get_total_stored()).is_equal(3200)

func test_the_player_is_told_when_a_load_costs_them_something() -> void:
	_given(1, 0, {"gold": 800, "steel": 800, "oil": 800, "wood": 800})
	var notices := [0]
	var probe := func(_m: String, _c: String, _col: Color): notices[0] += 1
	EventBus.notification_posted.connect(probe)
	ResourceManager.clamp_to_storage()
	EventBus.notification_posted.disconnect(probe)
	assert_int(notices[0]).is_equal(1)

func test_trimming_reports_every_resource_it_touched() -> void:
	# The HUD only repaints on this signal; a silent trim would show stale numbers.
	_given(1, 0, {"gold": 800, "wood": 400})
	var changed := []
	var probe := func(res: String, _n: int, _d: int): changed.append(res)
	EventBus.resource_changed.connect(probe)
	ResourceManager.clamp_to_storage()
	EventBus.resource_changed.disconnect(probe)
	assert_bool(changed.has("gold")).is_true()
	assert_bool(changed.has("wood")).is_true()

# ── Spending never changed meaning ───────────────────────────────────

func test_affording_something_still_only_asks_about_the_cost() -> void:
	_given(1, 0, {"gold": 100, "wood": 50})
	assert_bool(ResourceManager.can_afford({GOLD: 100, WOOD: 50})).is_true()
	assert_bool(ResourceManager.can_afford({GOLD: 101})).is_false()
	assert_bool(ResourceManager.spend_cost({GOLD: 100, WOOD: 50})).is_true()
	assert_int(ResourceManager.get_total_stored()).is_equal(0)

func test_a_full_bag_does_not_stop_you_from_paying() -> void:
	_given(1, 0, {"gold": 600})
	assert_bool(ResourceManager.spend(GOLD, 120)).is_true()
	assert_int(ResourceManager.get_amount(GOLD)).is_equal(480)
