extends GdUnitTestSuite
## Las reglas de cada modo, tal como las leen los servicios: la tabla de
## GameConfig, las consultas de GameMode y los getters de balance que las
## aplican. Sin escena: todo es estado estatico y funciones.
##
## Cada caso deja el modo en Campana, que es lo que el resto de suites supone.

func after_test() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)

# ── Estado y guardado ────────────────────────────────────────────────

func test_the_default_mode_is_the_campaign() -> void:
	GameMode.begin_run(GameMode.DEFAULT)
	assert_int(GameMode.current).is_equal(GameMode.Mode.CAMPAIGN)
	assert_str(GameMode.current_key()).is_equal("campaign")

func test_a_save_without_the_key_loads_as_campaign() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	GameMode.load_save_data({})
	assert_int(GameMode.current).is_equal(GameMode.Mode.CAMPAIGN)
	assert_bool(GameMode.is_run_over()).is_false()

func test_an_unknown_mode_key_falls_back_to_campaign() -> void:
	GameMode.load_save_data({"mode": "modo_de_2031", "result": 42})
	assert_int(GameMode.current).is_equal(GameMode.Mode.CAMPAIGN)
	assert_bool(GameMode.is_run_over()).is_false()

func test_every_mode_round_trips_through_the_save() -> void:
	for mode in GameMode.ORDER:
		GameMode.begin_run(mode)
		var data: Dictionary = JSON.parse_string(JSON.stringify(GameMode.get_save_data()))
		GameMode.begin_run(GameMode.Mode.CAMPAIGN)
		GameMode.load_save_data(data)
		assert_int(GameMode.current).is_equal(mode)

func test_a_finished_run_travels_in_the_save_and_a_new_run_clears_it() -> void:
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	GameMode.finish_run(GameMode.RESULT_DEFEAT)
	var data := GameMode.get_save_data()
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	assert_bool(GameMode.is_run_over()).is_false()
	GameMode.load_save_data(data)
	assert_bool(GameMode.is_run_over()).is_true()
	assert_str(GameMode.run_result).is_equal(GameMode.RESULT_DEFEAT)

func test_every_mode_has_its_texts_in_both_languages() -> void:
	var before: String = Tr.get_locale()
	for locale in Tr.LOCALES:
		Tr.set_locale(locale)
		for mode in GameMode.ORDER:
			for key in [GameMode.name_key(mode), GameMode.desc_key(mode), GameMode.tag_key(mode), GameMode.goal_key(mode)]:
				assert_str(Tr.t(key)).override_failure_message("%s sin texto en %s" % [key, locale]).is_not_equal(key)
	Tr.set_locale(before)

# ── La tabla ─────────────────────────────────────────────────────────

func test_campaign_is_the_game_as_it_was() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	assert_bool(GameMode.storm_enabled()).is_true()
	assert_bool(GameMode.tithe_enabled()).is_true()
	assert_bool(GameMode.audit_enabled()).is_true()
	assert_bool(GameMode.capstone_wins()).is_false()
	assert_bool(GameMode.resummon_allowed()).is_true()
	assert_bool(GameMode.offline_enabled()).is_true()
	assert_bool(GameMode.danger_events_enabled()).is_true()
	assert_bool(GameMode.infinite_resources()).is_false()
	assert_bool(GameMode.all_unlocked()).is_false()
	assert_float(GameMode.storm_interval_mult()).is_equal(1.0)
	assert_int(GameMode.storm_severity_bonus()).is_equal(0)
	assert_dict(GameMode.starting_resources()).is_equal(GameConfig.starting_resources)

func test_builder_has_no_storm_no_tithe_no_siege_and_wins_on_the_capstone() -> void:
	GameMode.begin_run(GameMode.Mode.BUILDER)
	assert_bool(GameMode.storm_enabled()).is_false()
	assert_bool(GameMode.tithe_enabled()).is_false()
	assert_bool(GameMode.audit_enabled()).is_false()
	assert_bool(GameMode.capstone_wins()).is_true()
	assert_bool(GameMode.victory_enabled()).is_true()
	assert_bool(GameMode.random_events_enabled()).is_true()
	assert_bool(GameMode.danger_events_enabled()).is_false()

func test_survival_is_harsher_and_has_a_single_audit() -> void:
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	assert_bool(GameMode.storm_enabled()).is_true()
	assert_bool(GameMode.resummon_allowed()).is_false()
	assert_bool(GameMode.offline_enabled()).is_false()
	assert_float(GameMode.storm_interval_mult()).is_less(1.0)
	assert_int(GameMode.storm_severity_bonus()).is_greater(0)
	assert_float(GameMode.storm_damage_mult()).is_greater(1.0)
	assert_float(GameMode.tithe_mult()).is_greater(1.0)
	var start := GameMode.starting_resources()
	assert_int(int(start["gold"])).is_less(int(GameConfig.starting_resources["gold"]))
	assert_int(int(start["wood"])).is_less(int(GameConfig.starting_resources["wood"]))

func test_survival_still_affords_the_era_one_opening() -> void:
	# Aserradero + Mina de oro (lo que el diseño da por hecho que se levanta
	# primero) tiene que caber en lo que Supervivencia da al empezar.
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	var start := GameMode.starting_resources()
	var sawmill: BuildingData = load("res://data/buildings/sawmill.tres")
	var mine: BuildingData = load("res://data/buildings/gold_mine.tres")
	assert_int(int(start["gold"])).is_greater_equal(sawmill.cost_gold + mine.cost_gold)
	assert_int(int(start["wood"])).is_greater_equal(sawmill.cost_wood + mine.cost_wood)

func test_sandbox_opens_everything_and_calls_nothing_by_itself() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	assert_bool(GameMode.storm_enabled()).is_false()
	assert_bool(GameMode.audit_enabled()).is_false()
	assert_bool(GameMode.capstone_wins()).is_false()
	assert_bool(GameMode.victory_enabled()).is_false()
	assert_bool(GameMode.random_events_enabled()).is_false()
	assert_bool(GameMode.infinite_resources()).is_true()
	assert_bool(GameMode.all_unlocked()).is_true()
	assert_bool(GameMode.sandbox_tools()).is_true()
	# Una tormenta invocada si cobra: es lo que se quiere probar.
	assert_bool(GameMode.tithe_enabled()).is_true()

func test_only_sandbox_has_the_tools() -> void:
	for mode in GameMode.ORDER:
		GameMode.begin_run(mode)
		assert_bool(GameMode.sandbox_tools()).is_equal(mode == GameMode.Mode.SANDBOX)

# ── Los getters de balance aplican el modo ───────────────────────────

func test_survival_brings_the_storms_closer() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	var calm_min: float = GameConfig.get_storm_interval_min()
	var calm_max: float = GameConfig.get_storm_interval_max()
	var first: float = GameConfig.get_storm_first_interval()
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	assert_float(GameConfig.get_storm_interval_min()).is_equal_approx(calm_min * GameMode.storm_interval_mult(), 0.001)
	assert_float(GameConfig.get_storm_interval_max()).is_equal_approx(calm_max * GameMode.storm_interval_mult(), 0.001)
	assert_float(GameConfig.get_storm_first_interval()).is_less(first)

func test_survival_storms_hit_harder_and_the_tithe_costs_more() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	var dmg: int = GameConfig.get_storm_damage(2, 100, 0)
	var debt: int = GameConfig.get_tithe_debt(2, 2, 500)
	var sev: int = StormCycle.compute_severity(6, 2)
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	assert_int(GameConfig.get_storm_damage(2, 100, 0)).is_greater(dmg)
	assert_int(GameConfig.get_tithe_debt(2, 2, 500)).is_greater(debt)
	assert_int(StormCycle.compute_severity(6, 2)).is_equal(mini(sev + 1, GameConfig.storm_severity_max))

func test_survival_first_storm_is_already_one_step_harder() -> void:
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	var cycle := StormCycle.create(1)
	assert_int(cycle.severity).is_equal(GameConfig.storm_first_severity + 1)

func test_sandbox_lifts_limits_prerequisites_and_the_storage_cap() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	assert_int(GameConfig.get_building_limit("headquarters")).is_equal(-1)
	assert_int(GameConfig.get_building_limit("warehouse")).is_equal(-1)
	assert_array(GameConfig.get_prerequisites("foundry")).is_empty()
	assert_int(GameConfig.get_storage_cap(0, 1)).is_equal(GameConfig.sandbox_storage_cap)
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	assert_int(GameConfig.get_building_limit("headquarters")).is_equal(1)
	assert_array(GameConfig.get_prerequisites("foundry")).is_not_empty()

# ── Eventos y tutorial ───────────────────────────────────────────────

func test_builder_only_rolls_the_good_events() -> void:
	GameMode.begin_run(GameMode.Mode.BUILDER)
	var pool: Array = RandomEventManager.get_active_event_pool()
	assert_array(pool).is_not_empty()
	for event in pool:
		assert_str(String(event["category"])).is_not_equal("danger")
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	var has_danger := false
	for event in RandomEventManager.get_active_event_pool():
		if event["category"] == "danger":
			has_danger = true
	assert_bool(has_danger).is_true()

func test_builder_never_shows_a_storm_or_audit_tip() -> void:
	var saved := TutorialManager.get_save_data()
	TutorialManager.reset()
	GameMode.begin_run(GameMode.Mode.BUILDER)
	var shown: Array = []
	var probe := func(id: String, _t: String, _b: String): shown.append(id)
	EventBus.tutorial_tip_requested.connect(probe)
	for tip in ["storm_incoming", "storm_ash", "storm_started", "tithe", "ruined", "final_audit", "market"]:
		TutorialManager.offer_tip(tip)
	EventBus.tutorial_tip_requested.disconnect(probe)
	# Los ocultos ni salen ni se marcan como vistos; el resto sale como siempre.
	var storm_seen: bool = TutorialManager.has_seen_tip("storm_incoming")
	TutorialManager.load_save_data(saved)
	assert_array(shown).contains_exactly(["market"])
	assert_bool(storm_seen).is_false()

func test_sandbox_hides_the_audit_tip_but_not_the_storm_ones() -> void:
	# En Sandbox la tormenta se puede invocar: sus consejos siguen teniendo sentido.
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	assert_bool(GameMode.tip_allowed("final_audit")).is_false()
	assert_bool(GameMode.tip_allowed("storm_incoming")).is_true()
