extends GdUnitTestSuite
## La tormenta de prueba de la era 1 (decision de Bryan, 2026-10-04).
##
## Hacia el minuto 5 de partida pasa una tormenta suave y guionizada: Aviso,
## Ceniza, Tormenta y calma, con los consejos del Aviso, pero sin Diezmo, sin
## romper nada y con poca moral. Una vez por partida, guardada, y sin armar el
## reloj de verdad. En Constructor y Sandbox no sale.

var _saved_storm: Dictionary = {}
var _saved_progression: Dictionary = {}
var _saved_population: Dictionary = {}
var _saved_mult: float = 1.0
var _saved_mode: int = GameMode.DEFAULT
var _events: Array = []

func before_test() -> void:
	_saved_storm = StormManager.get_save_data()
	_saved_progression = ProgressionManager.get_save_data()
	_saved_population = PopulationManager.get_save_data()
	_saved_mult = GameConfig.event_production_multiplier
	_saved_mode = GameMode.current
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	StormManager.reset()
	ProgressionManager.current_era = 1
	ProgressionManager._played_seconds = 0.0
	_events = []
	EventBus.storm_incoming.connect(_on_incoming)
	EventBus.storm_ash_started.connect(_on_ash)
	EventBus.storm_started.connect(_on_started)
	EventBus.storm_ended.connect(_on_ended)
	EventBus.tithe_demanded.connect(_on_tithe_demanded)
	EventBus.tithe_resolved.connect(_on_tithe_resolved)
	EventBus.building_damaged.connect(_on_damaged)

func after_test() -> void:
	EventBus.storm_incoming.disconnect(_on_incoming)
	EventBus.storm_ash_started.disconnect(_on_ash)
	EventBus.storm_started.disconnect(_on_started)
	EventBus.storm_ended.disconnect(_on_ended)
	EventBus.tithe_demanded.disconnect(_on_tithe_demanded)
	EventBus.tithe_resolved.disconnect(_on_tithe_resolved)
	EventBus.building_damaged.disconnect(_on_damaged)
	GameMode.begin_run(_saved_mode)
	StormManager.reset()
	StormManager.load_save_data(_saved_storm)
	StormManager._tithe_to_resume = false
	ProgressionManager.load_save_data(_saved_progression)
	PopulationManager.load_save_data(_saved_population)
	GameConfig.event_production_multiplier = _saved_mult

func _on_incoming(_s: float) -> void: _events.append("incoming")
func _on_ash() -> void: _events.append("ash")
func _on_started(_sev: int) -> void: _events.append("storm")
func _on_ended(_sev: int) -> void: _events.append("ended")
func _on_tithe_demanded(_sev: int) -> void: _events.append("tithe")
func _on_tithe_resolved(_r: bool, _t: Dictionary) -> void: _events.append("tithe_resolved")
func _on_damaged(_n: Node, _h: int, _m: int) -> void: _events.append("damaged")

func _run_trial_out() -> void:
	for i in 2000:
		if not StormManager.is_trial_running():
			return
		StormManager._tick_trial(0.25)

# ── El modelo ────────────────────────────────────────────────────────

func test_the_trial_cycle_walks_every_phase_and_never_collects() -> void:
	var cycle := StormCycle.create_trial(3)
	var seen: Array = []
	for event in cycle.summon_now():
		seen.append(String(event["e"]))
	for i in 2000:
		if cycle.finished:
			break
		for event in cycle.advance(0.5):
			seen.append(String(event["e"]))
	assert_bool(cycle.finished).is_true()
	assert_int(cycle.phase).is_equal(StormCycle.Phase.CALM)
	assert_array(seen).contains(["incoming", "ash_started", "storm_started", "storm_ended"])
	assert_array(seen).not_contains(["tithe", "false_alarm"])
	assert_int(cycle.storms_survived).is_equal(0)
	# Terminada, no vuelve: ni el reloj ni una segunda invocacion la mueven.
	assert_array(cycle.advance(10000.0)).is_empty()
	assert_array(cycle.summon_now()).is_empty()

# ── Cuando sale ──────────────────────────────────────────────────────

func test_it_waits_for_its_minute_of_play() -> void:
	ProgressionManager._played_seconds = GameConfig.get_storm_trial_at() - 1.0
	assert_bool(StormManager.check_trial()).is_false()
	assert_bool(StormManager.is_trial_running()).is_false()
	ProgressionManager._played_seconds = GameConfig.get_storm_trial_at()
	assert_bool(StormManager.check_trial()).is_true()
	assert_bool(StormManager.is_trial_running()).is_true()
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.WARNING)
	assert_array(_events).contains(["incoming"])

func test_the_minute_is_game_time_scaled_by_dev_mode() -> void:
	assert_float(GameConfig.get_storm_trial_at()).is_equal(GameConfig.get_duration(GameConfig.storm_trial_at))
	assert_float(GameConfig.storm_trial_at).is_equal(300.0)

func test_it_does_not_arm_the_real_storm() -> void:
	ProgressionManager._played_seconds = GameConfig.get_storm_trial_at()
	StormManager.check_trial()
	_run_trial_out()
	assert_bool(StormManager.is_armed()).is_false()
	assert_int(StormManager.get_cycle().phase).is_equal(StormCycle.Phase.CALM)
	assert_int(StormManager.storms_survived()).is_equal(0)

func test_a_whole_trial_has_no_tithe_no_damage_and_little_morale() -> void:
	# La moral solo se mueve desde la fase de Economia (y sin el suelo de las
	# primeras fases desde Supervivencia, el primer Almacen): a los 5 minutos el
	# jugador de la sonda ya tiene almacen.
	ProgressionManager.current_phase = GameConfig.Phase.SURVIVAL
	PopulationManager._morale_bonus = 0
	PopulationManager._morale = 80
	ProgressionManager._played_seconds = GameConfig.get_storm_trial_at()
	StormManager.check_trial()
	var mult_in_ash := -1.0
	for i in 2000:
		if not StormManager.is_trial_running():
			break
		StormManager._tick_trial(0.25)
		if StormManager.is_ashfall():
			mult_in_ash = GameConfig.event_production_multiplier
	assert_array(_events).contains_exactly(["incoming", "ash", "storm", "ended"])
	assert_float(mult_in_ash).is_equal(GameConfig.storm_trial_production_multiplier)
	assert_float(GameConfig.event_production_multiplier).is_equal(1.0)
	# Severidad 1: 12 puntos en una de verdad, una cuarta parte en la de prueba.
	assert_int(80 - PopulationManager.get_morale()).is_between(1, 4)
	assert_bool(StormManager.is_trial_done()).is_true()
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.CALM)

func test_only_once_per_game() -> void:
	ProgressionManager._played_seconds = GameConfig.get_storm_trial_at()
	StormManager.check_trial()
	_run_trial_out()
	ProgressionManager._played_seconds = GameConfig.get_storm_trial_at() * 3.0
	assert_bool(StormManager.check_trial()).is_false()
	assert_bool(StormManager.start_trial()).is_false()

func test_the_foundry_first_makes_it_moot() -> void:
	ProgressionManager.current_era = 2
	ProgressionManager._played_seconds = GameConfig.get_storm_trial_at()
	assert_bool(StormManager.check_trial()).is_false()
	assert_bool(StormManager.is_trial_done()).is_true()

func test_builder_and_sandbox_never_get_it() -> void:
	for mode in [GameMode.Mode.BUILDER, GameMode.Mode.SANDBOX]:
		GameMode.begin_run(mode)
		StormManager.reset()
		ProgressionManager._played_seconds = GameConfig.get_storm_trial_at() * 2.0
		assert_bool(GameMode.storm_trial_enabled()).is_false()
		assert_bool(StormManager.check_trial()).is_false()
		assert_bool(StormManager.is_trial_running()).is_false()
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	assert_bool(GameMode.storm_trial_enabled()).is_true()
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	assert_bool(GameMode.storm_trial_enabled()).is_true()

func test_it_does_not_eat_the_queue() -> void:
	var node: Node = auto_free(Node.new())
	ProcessManager._active[node] = {"id": "wood_planks", "cost": {"wood": 20}, "elapsed": 0.0, "duration": 10.0}
	ProgressionManager._played_seconds = GameConfig.get_storm_trial_at()
	StormManager.check_trial()
	_run_trial_out()
	var kept: bool = ProcessManager._active.has(node)
	ProcessManager._active.erase(node)
	assert_bool(kept).is_true()

# ── Guardado ─────────────────────────────────────────────────────────

func test_a_save_in_the_middle_comes_back_in_the_middle() -> void:
	ProgressionManager._played_seconds = GameConfig.get_storm_trial_at()
	StormManager.check_trial()
	for i in 2000:
		if StormManager.is_ashfall():
			break
		StormManager._tick_trial(0.25)
	var data: Dictionary = StormManager.get_save_data()
	StormManager.reset()
	GameConfig.event_production_multiplier = 1.0
	StormManager.load_save_data(data)
	StormManager.load_save_data(data)  # idempotente
	assert_bool(StormManager.is_trial_running()).is_true()
	assert_bool(StormManager.is_ashfall()).is_true()
	assert_float(GameConfig.event_production_multiplier).is_equal(GameConfig.storm_trial_production_multiplier)
	_run_trial_out()
	assert_bool(StormManager.is_trial_done()).is_true()

func test_done_is_saved_and_reset_clears_it() -> void:
	ProgressionManager._played_seconds = GameConfig.get_storm_trial_at()
	StormManager.check_trial()
	_run_trial_out()
	var data: Dictionary = StormManager.get_save_data()
	StormManager.reset()
	assert_bool(StormManager.is_trial_done()).is_false()
	StormManager.load_save_data(data)
	assert_bool(StormManager.is_trial_done()).is_true()
	assert_bool(StormManager.check_trial()).is_false()

func test_an_old_save_without_the_keys_still_gets_it() -> void:
	var data: Dictionary = StormManager.get_save_data()
	data.erase("trial_storm")
	data.erase("trial_done")
	StormManager.load_save_data(data)
	assert_bool(StormManager.is_trial_done()).is_false()
	ProgressionManager._played_seconds = GameConfig.get_storm_trial_at()
	assert_bool(StormManager.check_trial()).is_true()
