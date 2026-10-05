extends GdUnitTestSuite
## El rango del gobernador (RankManager): XP por cada fuente, la curva, lo que
## desbloquea, los bonos (idempotentes al cargar), los cosmeticos, el reset y
## un guardado anterior al rango = rango 1.
##
## RankManager, ProgressionManager y TutorialManager son autoloads compartidos:
## se aparta su estado antes de cada test y se devuelve despues.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")

var _rank_saved: Dictionary = {}
var _progress_saved: Dictionary = {}
var _tutorial_saved: Dictionary = {}
var _mode_saved: Dictionary = {}
var _placed: Array = []
var _rank_ups: Array = []
var _cosmetics: Array = []

func before_test() -> void:
	_rank_saved = RankManager.get_save_data()
	_progress_saved = ProgressionManager.get_save_data()
	_tutorial_saved = TutorialManager.get_save_data()
	_mode_saved = GameMode.get_save_data()
	RankManager.reset()
	_placed.clear()
	_rank_ups.clear()
	_cosmetics.clear()
	EventBus.governor_rank_up.connect(_on_rank_up)
	EventBus.colony_cosmetics_changed.connect(_on_cosmetics)

func after_test() -> void:
	EventBus.governor_rank_up.disconnect(_on_rank_up)
	EventBus.colony_cosmetics_changed.disconnect(_on_cosmetics)
	for node in _placed:
		if is_instance_valid(node):
			GridManager.remove_building(node)
	_placed.clear()
	GameMode.load_save_data(_mode_saved)
	ProgressionManager.load_save_data(_progress_saved)
	TutorialManager.load_save_data(_tutorial_saved)
	RankManager.reset()
	RankManager.load_save_data(_rank_saved)

func _on_rank_up(rank: int, rewards: Dictionary) -> void:
	_rank_ups.append([rank, rewards])

func _on_cosmetics(flag_id: String, color_id: String) -> void:
	_cosmetics.append([flag_id, color_id])

func _xp_of(source: String) -> int:
	return int(GameConfig.rank_xp_sources[source])

func _build(id: String, cell: Vector2i) -> Node3D:
	var data: BuildingData = load("res://data/buildings/%s.tres" % id)
	var node: Node3D = auto_free(Node3D.new())
	assert_bool(GridManager.place_building(cell, data, node)).is_true()
	_placed.append(node)
	return node

# ── XP por fuente ────────────────────────────────────────────────────

func test_signals_without_side_effects_give_their_xp() -> void:
	var dummy: Node = auto_free(Node.new())
	var cases := [
		["production", func(): EventBus.production_tick.emit(dummy)],
		["process", func(): EventBus.process_completed.emit(dummy, "planks")],
		["mining", func(): EventBus.mining_completed.emit(dummy, "forest")],
		["trade", func(): EventBus.market_trade_completed.emit("wood", 10, true, 30)],
		["train", func(): EventBus.unit_trained.emit("infantry")],
		["upgrade", func(): EventBus.building_upgrade_completed.emit(dummy, 2)],
		["milestone", func(): EventBus.milestone_completed.emit("test_milestone")],
	]
	for c in cases:
		var before := RankManager.get_xp()
		(c[1] as Callable).call()
		assert_int(RankManager.get_xp() - before) \
			.override_failure_message("la fuente %s no da su XP" % c[0]) \
			.is_equal(_xp_of(String(c[0])))

func test_named_handlers_are_wired_to_the_event_bus() -> void:
	assert_bool(EventBus.construction_completed.is_connected(RankManager._on_construction_completed)).is_true()
	assert_bool(EventBus.encounter_ended.is_connected(RankManager._on_encounter_ended)).is_true()
	assert_bool(EventBus.expedition_ended.is_connected(RankManager._on_expedition_ended)).is_true()
	assert_bool(EventBus.storm_ended.is_connected(RankManager._on_storm_ended)).is_true()

func test_a_finished_building_gives_xp_but_roads_and_the_core_do_not() -> void:
	var house := _build("house", Vector2i(2, 2))
	var garden := _build("garden", Vector2i(4, 2))
	var road := _build("road", Vector2i(6, 2))
	RankManager._on_construction_completed(house)
	assert_int(RankManager.get_xp()).is_equal(_xp_of("build"))
	RankManager._on_construction_completed(garden)
	assert_int(RankManager.get_xp()).is_equal(_xp_of("build") + _xp_of("build_decoration"))
	RankManager._on_construction_completed(road)
	assert_int(RankManager.get_xp()).is_equal(_xp_of("build") + _xp_of("build_decoration"))
	# Un nodo que no esta en la rejilla no cuenta.
	RankManager._on_construction_completed(auto_free(Node3D.new()))
	assert_int(RankManager.get_xp()).is_equal(_xp_of("build") + _xp_of("build_decoration"))

func test_fights_only_pay_when_won() -> void:
	RankManager._on_encounter_ended(false, 5)
	RankManager._on_expedition_ended(1, {}, {})
	RankManager._on_expedition_ended(2, {}, {})
	assert_int(RankManager.get_xp()).is_equal(0)
	RankManager._on_encounter_ended(true, 5)
	assert_int(RankManager.get_xp()).is_equal(_xp_of("fight_won"))
	RankManager._on_expedition_ended(0, {}, {})
	assert_int(RankManager.get_xp()).is_equal(_xp_of("fight_won") + _xp_of("expedition_won"))

func test_a_harder_storm_is_worth_more() -> void:
	RankManager._on_storm_ended(1)
	var mild := RankManager.get_xp()
	RankManager.reset()
	RankManager._on_storm_ended(4)
	assert_int(mild).is_equal(_xp_of("storm") + _xp_of("storm_per_severity"))
	assert_int(RankManager.get_xp()).is_equal(_xp_of("storm") + 4 * _xp_of("storm_per_severity"))

# ── Curva ────────────────────────────────────────────────────────────

func test_the_curve_has_15_to_20_ranks_and_always_climbs() -> void:
	var t: Array = GameConfig.rank_xp_thresholds
	assert_int(t.size()).is_between(15, 20)
	assert_int(int(t[0])).is_equal(0)
	for i in range(1, t.size()):
		assert_int(int(t[i])).is_greater(int(t[i - 1]))
		# Cada rango cuesta al menos lo que el anterior: la curva no se abarata.
		if i >= 2:
			assert_int(int(t[i]) - int(t[i - 1])).is_greater_equal(int(t[i - 1]) - int(t[i - 2]))

func test_rank_is_derived_from_xp_at_the_thresholds() -> void:
	var t: Array = GameConfig.rank_xp_thresholds
	assert_int(RankManager.rank_for_xp(0)).is_equal(1)
	assert_int(RankManager.rank_for_xp(int(t[1]) - 1)).is_equal(1)
	assert_int(RankManager.rank_for_xp(int(t[1]))).is_equal(2)
	assert_int(RankManager.rank_for_xp(int(t[t.size() - 1]))).is_equal(t.size())
	assert_int(RankManager.rank_for_xp(int(t[t.size() - 1]) * 10)).is_equal(t.size())

func test_every_rank_has_a_title_in_both_languages() -> void:
	var locale := Tr.get_locale()
	for lang in ["es", "en"]:
		Tr.set_locale(lang)
		for r in range(1, RankManager.max_rank() + 1):
			var key := GameConfig.rank_title_key(r)
			assert_str(Tr.t(key)).override_failure_message("%s sin titulo en %s" % [key, lang]).is_not_equal(key)
	Tr.set_locale(locale)

func test_a_big_jump_ranks_up_once_with_everything_it_crossed() -> void:
	RankManager.add_xp(int(GameConfig.rank_xp_thresholds[3]))
	assert_int(RankManager.get_rank()).is_equal(4)
	assert_int(_rank_ups.size()).is_equal(1)
	var rewards: Dictionary = _rank_ups[0][1]
	assert_int(int(_rank_ups[0][0])).is_equal(4)
	assert_array(rewards.get("buildings", [])).contains(["garden"])
	assert_array(rewards.get("flags", [])).contains(["cross"])
	assert_float(float(rewards.get("production", 0.0))).is_equal_approx(0.01, 0.0001)
	assert_float(float(rewards.get("storage", 0.0))).is_equal_approx(0.02, 0.0001)

func test_progress_inside_a_rank_and_at_the_top() -> void:
	var t: Array = GameConfig.rank_xp_thresholds
	RankManager.add_xp((int(t[1]) + int(t[2])) / 2)
	assert_float(RankManager.get_rank_progress()).is_between(0.4, 0.6)
	assert_int(RankManager.xp_to_next()).is_equal(int(t[2]) - RankManager.get_xp())
	RankManager.add_xp(int(t[t.size() - 1]))
	assert_bool(RankManager.is_max_rank()).is_true()
	assert_float(RankManager.get_rank_progress()).is_equal(1.0)
	assert_int(RankManager.xp_to_next()).is_equal(0)

# ── Desbloqueos ──────────────────────────────────────────────────────

func test_decorations_wait_for_their_rank() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	var garden: BuildingData = load("res://data/buildings/garden.tres")
	assert_int(RankManager.building_rank("garden")).is_greater(1)
	assert_bool(Rules.check_rank("garden")).is_false()
	assert_str(Rules.purchase_block_message(garden)).is_equal(Rules.rank_lock_text("garden"))
	assert_array(Rules.block_reasons(garden)).contains_exactly([Rules.rank_lock_text("garden")])
	RankManager.add_xp(RankManager.xp_for_rank(RankManager.building_rank("garden")))
	assert_bool(Rules.check_rank("garden")).is_true()
	assert_array(Rules.block_reasons(garden)).not_contains([Rules.rank_lock_text("garden")])

func test_basic_buildings_are_never_locked_by_rank() -> void:
	# La linea jugable no se toca: lo basico sigue abriendose por era.
	for id in ["house", "sawmill", "gold_mine", "warehouse", "market", "laboratory",
			"foundry", "barracks", "refinery", "tower", "headquarters", "road"]:
		assert_int(RankManager.building_rank(id)).override_failure_message("%s bloqueado por rango" % id).is_equal(0)

func test_sandbox_has_every_rank_unlock_open() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	assert_bool(Rules.check_rank("statue")).is_true()
	assert_bool(RankManager.is_flag_unlocked("chevron")).is_true()
	assert_bool(RankManager.is_color_unlocked("copper")).is_true()

# ── Bonos ────────────────────────────────────────────────────────────

func _bonus_snapshot() -> Dictionary:
	return {
		"production": GameConfig.rank_production_bonus,
		"storage": GameConfig.rank_storage_bonus,
		"limit": GameConfig.rank_limit_bonus.duplicate(),
		"cap": GameConfig.get_storage_cap(5, 3),
		"houses": GameConfig.get_building_limit("house"),
	}

func test_bonuses_follow_the_rank() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	var base := _bonus_snapshot()
	assert_float(float(base["production"])).is_equal(0.0)
	assert_float(float(base["storage"])).is_equal(0.0)
	RankManager.load_save_data({"xp": RankManager.xp_for_rank(12)})
	var high := _bonus_snapshot()
	var expected: Dictionary = RankManager.rewards_up_to(12)
	assert_float(float(high["production"])).is_equal_approx(float(expected["production"]), 0.0001)
	assert_float(float(high["storage"])).is_equal_approx(float(expected["storage"]), 0.0001)
	assert_int(int(high["cap"])).is_greater(int(base["cap"]))
	assert_int(int(high["houses"])).is_equal(int(base["houses"]) + int(expected["limit"]["house"]))
	# Pequenos: nunca mas de un 10 % de produccion ni de almacen en toda la curva.
	var all: Dictionary = RankManager.rewards_up_to(RankManager.max_rank())
	assert_float(float(all["production"])).is_less_equal(0.1)
	assert_float(float(all["storage"])).is_less_equal(0.1)

func test_loading_twice_gives_the_same_bonuses_as_loading_once() -> void:
	var data := {"xp": RankManager.xp_for_rank(16) + 5, "flag": "cross", "color": "steel"}
	RankManager.load_save_data(data.duplicate())
	var once := _bonus_snapshot()
	var rank_once := RankManager.get_rank()
	RankManager.load_save_data(data.duplicate())
	assert_dict(_bonus_snapshot()).is_equal(once)
	assert_int(RankManager.get_rank()).is_equal(rank_once)
	assert_int(RankManager.get_xp()).is_equal(int(data["xp"]))

func test_loading_a_lower_rank_drops_the_bonuses() -> void:
	RankManager.load_save_data({"xp": RankManager.xp_for_rank(18)})
	RankManager.load_save_data({"xp": 0})
	var loaded_low := _bonus_snapshot()
	RankManager.reset()
	assert_dict(loaded_low).is_equal(_bonus_snapshot())

# ── Cosmeticos ───────────────────────────────────────────────────────

func test_a_locked_flag_or_colour_cannot_be_picked() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	assert_bool(RankManager.set_flag("chevron")).is_false()
	assert_bool(RankManager.set_color("copper")).is_false()
	assert_str(RankManager.get_flag()).is_equal(GameConfig.COLONY_DEFAULT_FLAG)
	assert_array(_cosmetics).is_empty()

func test_an_unlocked_flag_and_colour_are_picked_saved_and_announced() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	RankManager.add_xp(RankManager.xp_for_rank(RankManager.flag_rank("cross")))
	RankManager.add_xp(RankManager.xp_for_rank(RankManager.color_rank("steel")))
	assert_bool(RankManager.set_flag("cross")).is_true()
	assert_bool(RankManager.set_color("steel")).is_true()
	assert_array(_cosmetics.back()).is_equal(["cross", "steel"])
	var saved := RankManager.get_save_data()
	assert_str(String(saved["flag"])).is_equal("cross")
	assert_str(String(saved["color"])).is_equal("steel")
	RankManager.reset()
	RankManager.load_save_data(saved)
	assert_str(RankManager.get_flag()).is_equal("cross")
	assert_str(RankManager.get_color_id()).is_equal("steel")
	assert_bool(RankManager.get_color() == GameConfig.colony_colors["steel"]).is_true()

func test_a_save_with_a_cosmetic_above_its_rank_falls_back() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	RankManager.load_save_data({"xp": 0, "flag": "chevron", "color": "nonsense"})
	assert_str(RankManager.get_flag()).is_equal(GameConfig.COLONY_DEFAULT_FLAG)
	assert_str(RankManager.get_color_id()).is_equal(GameConfig.COLONY_DEFAULT_COLOR)

func test_every_flag_design_is_drawn_and_they_differ() -> void:
	var seen := {}
	for flag_id in GameConfig.COLONY_FLAGS:
		var img: Image = ColonyFlag.make_image(flag_id, GameConfig.colony_colors["crimson"])
		assert_int(img.get_width()).is_equal(ColonyFlag.W)
		assert_int(img.get_height()).is_equal(ColonyFlag.H)
		var key := Marshalls.raw_to_base64(img.get_data())
		assert_bool(seen.has(key)).override_failure_message("%s repite el dibujo de %s" % [flag_id, seen.get(key, "")]).is_false()
		seen[key] = flag_id
	# Cada bandera y cada color se desbloquea en algun rango.
	for flag_id in GameConfig.COLONY_FLAGS:
		assert_int(RankManager.flag_rank(flag_id)).is_greater(0)
	for color_id in GameConfig.COLONY_COLOR_ORDER:
		assert_int(RankManager.color_rank(color_id)).is_greater(0)
	assert_int(GameConfig.COLONY_FLAGS.size()).is_between(3, 6)

# ── Reset y guardados viejos ─────────────────────────────────────────

func test_reset_forgets_xp_rank_bonuses_and_cosmetics() -> void:
	RankManager.load_save_data({"xp": RankManager.xp_for_rank(10), "flag": "cross", "color": "steel"})
	RankManager.reset()
	assert_int(RankManager.get_xp()).is_equal(0)
	assert_int(RankManager.get_rank()).is_equal(1)
	assert_str(RankManager.get_flag()).is_equal(GameConfig.COLONY_DEFAULT_FLAG)
	assert_str(RankManager.get_color_id()).is_equal(GameConfig.COLONY_DEFAULT_COLOR)
	assert_float(GameConfig.rank_production_bonus).is_equal(0.0)
	assert_float(GameConfig.rank_storage_bonus).is_equal(0.0)
	assert_dict(GameConfig.rank_limit_bonus).is_empty()
	# Sin avisos: una partida nueva no anuncia lo que perdio.
	assert_array(_rank_ups).is_empty()

func test_an_old_save_without_rank_is_rank_one() -> void:
	RankManager.add_xp(RankManager.xp_for_rank(5))
	RankManager.load_save_data({})
	assert_int(RankManager.get_xp()).is_equal(0)
	assert_int(RankManager.get_rank()).is_equal(1)
	assert_str(RankManager.get_flag()).is_equal(GameConfig.COLONY_DEFAULT_FLAG)

func test_every_fresh_game_path_resets_the_rank_and_the_save_carries_it() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/services/GameManager.gd")
	for fn in ["func _new_game", "func clear_save()", "func clear_save_and_reload_from"]:
		var start: int = src.find(fn)
		assert_int(start).is_greater(-1)
		var end: int = src.find("\nfunc ", start + 1)
		var body: String = src.substr(start, end - start)
		assert_bool(body.contains("RankManager.reset()")).override_failure_message(
			"%s no llama a RankManager.reset()" % fn).is_true()
	assert_bool(src.contains("data[\"rank\"] = RankManager.get_save_data()")).is_true()
	assert_bool(src.contains("RankManager.load_save_data(")).is_true()
