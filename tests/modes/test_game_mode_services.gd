extends GdUnitTestSuite
## Los servicios obedecen al modo: la Tormenta que no corre en Constructor, la
## que se invoca en Sandbox, el Cuartel General que gana sin asedio, la
## Auditoria que en Supervivencia no se repite, los recursos que no se acaban.
##
## Toca autoloads de verdad; cada caso los deja como los encontro y el modo en
## Campana.

var _storm_saved: Dictionary = {}
var _army_saved: Dictionary = {}
var _res_saved: Dictionary = {}
var _unlock_saved: Dictionary = {}
var _pop_saved: Dictionary = {}
var _prog_saved: Dictionary = {}
var _tech_saved: Dictionary = {}
var _era_saved: int = 1
var _mult_saved: float = 1.0

var _victories: Array = []
var _run_ends: Array = []

func before_test() -> void:
	_storm_saved = StormManager.get_save_data()
	_army_saved = ArmyManager.get_save_data()
	_res_saved = {}
	for type in ResourceManager.get_all():
		_res_saved[ResourceManager.get_type_name(type)] = ResourceManager.get_all()[type]
	_unlock_saved = ResourceManager.get_unlock_state()
	_era_saved = ResourceManager.get_era()
	_pop_saved = PopulationManager.get_save_data()
	_prog_saved = ProgressionManager.get_save_data()
	_tech_saved = TechTreeManager.get_save_data()
	_mult_saved = GameConfig.event_production_multiplier
	_victories = []
	_run_ends = []
	EventBus.victory_achieved.connect(_on_victory)
	EventBus.run_ended.connect(_on_run_ended)
	StormManager.reset()
	CombatManager.reset()
	ArmyManager.reset()

func after_test() -> void:
	EventBus.victory_achieved.disconnect(_on_victory)
	EventBus.run_ended.disconnect(_on_run_ended)
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	CombatManager.end_encounter()
	CombatManager.reset()
	StormManager.load_save_data(_storm_saved)
	ArmyManager.load_save_data(_army_saved)
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_prog_saved)
	TechTreeManager.reset()
	TechTreeManager.load_save_data(_tech_saved)
	ResourceManager.set_unlock_state(_unlock_saved)
	ResourceManager.set_era(_era_saved)
	ResourceManager.set_amounts(_res_saved)
	PopulationManager.load_save_data(_pop_saved)
	GameConfig.event_production_multiplier = _mult_saved

func _on_victory(stats: Dictionary) -> void:
	_victories.append(stats)

func _on_run_ended(result: String) -> void:
	_run_ends.append(result)

## Avanza el reloj de la Tormenta a mano, en pasos, como lo haria el motor.
func _run_storm(seconds: float, step: float = 1.0) -> void:
	var left := seconds
	while left > 0.0:
		StormManager._process(step)
		left -= step

# ── La Tormenta ──────────────────────────────────────────────────────

func test_builder_never_runs_the_storm_even_once_armed() -> void:
	GameMode.begin_run(GameMode.Mode.BUILDER)
	StormManager.reset()
	StormManager._armed = true
	_run_storm(GameConfig.get_storm_first_interval() * 3.0, 5.0)
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.CALM)
	assert_bool(StormManager.is_armed()).is_false()

func test_campaign_runs_the_storm_once_armed() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	StormManager.reset()
	StormManager._armed = true
	_run_storm(GameConfig.get_storm_first_interval() + 1.0, 1.0)
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.WARNING)

func test_a_mode_without_tithe_lets_the_storm_pass_without_collecting() -> void:
	GameMode.begin_run(GameMode.Mode.BUILDER)
	StormManager.reset()
	ResourceManager.set_amounts({"gold": 400, "wood": 300})
	var cycle: StormCycle = StormManager.get_cycle()
	cycle.phase = StormCycle.Phase.TITHE
	var resolved: Array = []
	var probe := func(repelled: bool, taken: Dictionary): resolved.append([repelled, taken])
	EventBus.tithe_resolved.connect(probe)
	StormManager._begin_tithe(3)
	EventBus.tithe_resolved.disconnect(probe)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(400)
	assert_int(resolved.size()).is_equal(1)
	assert_bool(resolved[0][0]).is_true()
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.CALM)

func test_sandbox_summons_a_whole_storm_on_demand_and_it_stops_after() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	StormManager.reset()
	# Dormida: el reloj no corre por si solo.
	_run_storm(GameConfig.get_storm_first_interval() * 2.0, 5.0)
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.CALM)

	assert_bool(StormManager.invoke_storm()).is_true()
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.WARNING)
	assert_bool(StormManager.is_armed()).is_true()
	# Una segunda invocacion con la tormenta en marcha no hace nada.
	assert_bool(StormManager.invoke_storm()).is_false()

	# La Advertencia invocada nunca es falsa alarma: siempre llega la ceniza.
	var phases: Array = []
	var probe := func(phase: int, _left: float): phases.append(phase)
	EventBus.storm_phase_changed.connect(probe)
	var guard := 0
	while StormManager.get_phase() != StormCycle.Phase.CALM and guard < 2000:
		StormManager._process(1.0)
		guard += 1
	EventBus.storm_phase_changed.disconnect(probe)
	assert_int(guard).override_failure_message("la tormenta invocada no volvio a la calma").is_less(2000)
	assert_array(phases).contains([StormCycle.Phase.ASH, StormCycle.Phase.STORM])
	# Vuelta a la calma: se para sola.
	assert_bool(StormManager.is_on_demand()).is_false()
	assert_bool(StormManager.is_armed()).is_false()
	_run_storm(GameConfig.get_storm_interval_max() * 2.0, 5.0)
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.CALM)

func test_only_sandbox_can_summon_a_storm() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	StormManager.reset()
	assert_bool(StormManager.invoke_storm()).is_false()
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.CALM)

func test_a_summoned_storm_survives_a_save() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	StormManager.reset()
	StormManager.invoke_storm()
	var data: Dictionary = JSON.parse_string(JSON.stringify(StormManager.get_save_data()))
	StormManager.reset()
	StormManager.load_save_data(data)
	assert_bool(StormManager.is_on_demand()).is_true()
	assert_bool(StormManager.get_cycle().forced).is_true()

# ── El final de la partida ───────────────────────────────────────────

func test_builder_wins_on_the_capstone_without_a_siege() -> void:
	GameMode.begin_run(GameMode.Mode.BUILDER)
	ProgressionManager.reset()
	ProgressionManager._complete_milestone("hq_max")
	assert_object(ProgressionManager.final_audit).is_null()
	assert_int(_victories.size()).is_equal(1)
	assert_str(String(_victories[0].get("mode", ""))).is_equal("builder")

func test_campaign_capstone_summons_the_audit_and_does_not_win() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	ProgressionManager.reset()
	ProgressionManager._complete_milestone("hq_max")
	assert_object(ProgressionManager.final_audit).is_not_null()
	assert_int(_victories.size()).is_equal(0)

func test_sandbox_capstone_does_nothing() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	ProgressionManager.reset()
	ProgressionManager._complete_milestone("hq_max")
	assert_object(ProgressionManager.final_audit).is_null()
	assert_int(_victories.size()).is_equal(0)

func test_sandbox_summons_the_audit_pending_and_only_once_at_a_time() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	ProgressionManager.reset()
	assert_bool(ProgressionManager.invoke_final_audit()).is_true()
	assert_bool(ProgressionManager.is_final_audit_pending()).is_true()
	assert_bool(ProgressionManager.invoke_final_audit()).is_false()

func test_only_sandbox_can_summon_the_audit_by_hand() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	ProgressionManager.reset()
	assert_bool(ProgressionManager.invoke_final_audit()).is_false()
	assert_object(ProgressionManager.final_audit).is_null()

func test_winning_a_sandbox_audit_is_not_a_victory_and_keeps_the_storm() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	ProgressionManager.reset()
	var halts: Array = []
	var probe := func(): halts.append(true)
	EventBus.storm_halted_forever.connect(probe)
	ProgressionManager._publish_audit([{"e": "final_audit_won"}])
	EventBus.storm_halted_forever.disconnect(probe)
	assert_int(_victories.size()).is_equal(0)
	assert_int(halts.size()).is_equal(0)
	assert_bool(StormManager.is_halted()).is_false()

func test_survival_loses_the_audit_once_and_the_run_is_over() -> void:
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	ProgressionManager.reset()
	ProgressionManager.summon_final_audit()
	ProgressionManager._publish_audit([{"e": "final_audit_lost", "wave": 1}])
	assert_bool(GameMode.is_run_over()).is_true()
	assert_array(_run_ends).contains_exactly([GameMode.RESULT_DEFEAT])
	assert_bool(ProgressionManager.can_resummon_final_audit()).is_false()
	assert_bool(ProgressionManager.resummon_final_audit()).is_false()

func test_campaign_loses_the_audit_and_the_run_goes_on() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	ProgressionManager.reset()
	ProgressionManager.summon_final_audit()
	ProgressionManager._publish_audit([{"e": "final_audit_lost", "wave": 1}])
	assert_bool(GameMode.is_run_over()).is_false()
	assert_array(_run_ends).is_empty()

# ── Sandbox: todo abierto, recursos que no se acaban ─────────────────

func test_sandbox_starts_in_the_third_era_with_everything_unlocked() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	ProgressionManager.reset()
	ResourceManager.reset()
	assert_int(ProgressionManager.current_era).is_equal(3)
	assert_int(ResourceManager.get_era()).is_equal(3)
	for type in [ResourceManager.Type.GOLD, ResourceManager.Type.STEEL, ResourceManager.Type.OIL, ResourceManager.Type.WOOD]:
		assert_bool(ResourceManager.is_unlocked(type)).is_true()
		assert_int(ResourceManager.get_amount(type)).is_greater_equal(GameConfig.sandbox_resource_floor)

func test_sandbox_resources_refill_after_spending() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	ResourceManager.reset()
	assert_bool(ResourceManager.spend(ResourceManager.Type.GOLD, 15000)).is_true()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(GameConfig.sandbox_resource_floor)
	assert_bool(ResourceManager.spend_cost({ResourceManager.Type.STEEL: 19999, ResourceManager.Type.OIL: 5})).is_true()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.STEEL)).is_equal(GameConfig.sandbox_resource_floor)
	ResourceManager.add(ResourceManager.Type.WOOD, -20000)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.WOOD)).is_equal(GameConfig.sandbox_resource_floor)

func test_outside_sandbox_spending_is_spending() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	ResourceManager.reset()
	ResourceManager.spend(ResourceManager.Type.GOLD, 100)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(int(GameConfig.starting_resources["gold"]) - 100)

func test_survival_starts_with_less() -> void:
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	ResourceManager.reset()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(int(GameMode.starting_resources()["gold"]))
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_less(int(GameConfig.starting_resources["gold"]))

func test_unlock_all_researches_every_tech_with_its_bonus() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	TechTreeManager.reset()
	TechTreeManager.unlock_all()
	assert_int(TechTreeManager.get_researched_count()).is_equal(GameConfig.tech_definitions.size())
	assert_float(GameConfig.tech_production_bonus).is_greater(0.0)
	# Dos veces no suma dos veces.
	var bonus: float = GameConfig.tech_production_bonus
	TechTreeManager.unlock_all()
	assert_float(GameConfig.tech_production_bonus).is_equal(bonus)
