extends GdUnitTestSuite
## Cargar en mitad de la Tormenta no es una forma de saltarsela.
##
## Antes, load_save_data() ponia el multiplicador de produccion a 1.0 fuera cual
## fuera la fase (cargar con ceniza la limpiaba), y StormCycle.from_dict()
## convertia un Diezmo guardado en una calma nueva (salir durante el Diezmo era
## no pagarlo).

var _saved_storm: Dictionary = {}
var _saved_army: Dictionary = {}
var _saved_progression: Dictionary = {}
var _saved_mult: float = 1.0
var _saved_resources: Dictionary = {}
var _tithes: Array = []
var _demands: Array = []

func before_test() -> void:
	_saved_storm = StormManager.get_save_data()
	_saved_army = ArmyManager.get_save_data()
	_saved_progression = ProgressionManager.get_save_data()
	_saved_mult = GameConfig.event_production_multiplier
	_saved_resources = {}
	for type in ResourceManager.get_all():
		_saved_resources[ResourceManager.get_type_name(type)] = int(ResourceManager.get_all()[type])
	CombatManager.reset()
	ArmyManager.reset()
	ProgressionManager.final_audit = null
	_tithes = []
	_demands = []
	EventBus.tithe_resolved.connect(_on_tithe)
	EventBus.tithe_demanded.connect(_on_demand)

func after_test() -> void:
	EventBus.tithe_resolved.disconnect(_on_tithe)
	EventBus.tithe_demanded.disconnect(_on_demand)
	CombatManager.end_encounter()
	CombatManager.reset()
	StormManager.load_save_data(_saved_storm)
	StormManager._tithe_to_resume = false
	ArmyManager.load_save_data(_saved_army)
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_saved_progression)
	GameConfig.event_production_multiplier = _saved_mult
	ResourceManager.set_amounts(_saved_resources)

func _on_tithe(repelled: bool, taken: Dictionary) -> void:
	_tithes.append([repelled, taken])

func _on_demand(severity: int) -> void:
	_demands.append(severity)

func _saved_in(phase: int) -> Dictionary:
	var cycle := StormCycle.create(7)
	cycle.phase = phase
	cycle.seconds_left = 0.0 if phase == StormCycle.Phase.TITHE else 30.0
	var data: Dictionary = cycle.to_dict()
	data["armed"] = true
	data["halted"] = false
	return data

# ── El modelo ────────────────────────────────────────────────────────

func test_a_saved_tithe_comes_back_as_a_tithe() -> void:
	var cycle := StormCycle.from_dict(_saved_in(StormCycle.Phase.TITHE))
	assert_int(cycle.phase).is_equal(StormCycle.Phase.TITHE)
	assert_bool(cycle.is_collecting()).is_true()
	# Y el reloj sigue quieto hasta que se liquide, como en partida.
	assert_array(cycle.advance(100.0)).is_empty()

func test_a_legacy_tithe_is_also_kept() -> void:
	var cycle := StormCycle.from_dict({"v": 1, "phase": 3, "seconds_left": 0.0})
	assert_int(cycle.phase).is_equal(StormCycle.Phase.TITHE)

# ── El multiplicador ─────────────────────────────────────────────────

func test_loading_during_the_ash_keeps_the_ash_penalty() -> void:
	GameConfig.event_production_multiplier = 1.0
	StormManager.load_save_data(_saved_in(StormCycle.Phase.ASH))
	assert_float(GameConfig.event_production_multiplier).is_equal(
		GameConfig.storm_ash_production_multiplier)

func test_loading_during_the_storm_keeps_the_storm_penalty() -> void:
	GameConfig.event_production_multiplier = 1.0
	StormManager.load_save_data(_saved_in(StormCycle.Phase.STORM))
	assert_float(GameConfig.event_production_multiplier).is_equal(
		GameConfig.storm_production_multiplier)

func test_loading_in_calm_lifts_any_penalty() -> void:
	GameConfig.event_production_multiplier = 0.1
	StormManager.load_save_data(_saved_in(StormCycle.Phase.CALM))
	assert_float(GameConfig.event_production_multiplier).is_equal(1.0)

func test_a_halted_storm_never_taxes_on_load() -> void:
	var data := _saved_in(StormCycle.Phase.STORM)
	data["halted"] = true
	GameConfig.event_production_multiplier = 0.1
	StormManager.load_save_data(data)
	assert_float(GameConfig.event_production_multiplier).is_equal(1.0)

# ── El Diezmo reanudado ──────────────────────────────────────────────

func test_a_tithe_left_pending_is_demanded_again_once_loading_ends() -> void:
	# Sin guarnicion: el Diezmo se cobra directo, que es lo que haria en partida.
	ResourceManager.set_amounts({"gold": 500, "wood": 500, "steel": 0, "oil": 0})
	StormManager.load_save_data(_saved_in(StormCycle.Phase.TITHE))
	assert_array(_tithes).is_empty()
	EventBus.game_load_completed.emit()
	await await_idle_frame()
	assert_array(_demands).has_size(1)
	assert_array(_tithes).has_size(1)
	assert_bool(bool(_tithes[0][0])).is_false()
	# Liquidado, el reloj vuelve a correr.
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.CALM)

func test_a_tithe_with_a_garrison_at_home_reopens_the_defense() -> void:
	ArmyManager.load_save_data({"units": {"infantry": 3}, "training": [], "upkeep_accum": 0.0})
	StormManager.load_save_data(_saved_in(StormCycle.Phase.TITHE))
	EventBus.game_load_completed.emit()
	await await_idle_frame()
	assert_bool(CombatManager.is_in_encounter()).override_failure_message(
		"el Diezmo cargado no volvio a poner la defensa en el tablero").is_true()
	assert_bool(CombatManager.is_defending()).is_true()
	assert_array(_tithes).is_empty()

## El menu principal sale al arrancar con el arbol en pausa, antes de que la
## partida cargue. Un Diezmo pendiente abria la defensa DETRAS del menu: el
## tablero debe esperar a que el jugador lo suelte.
## Sin esperar frames con el arbol en pausa: el runner de gdUnit se pararia.
func test_a_tithe_left_pending_waits_for_the_title_menu() -> void:
	ArmyManager.load_save_data({"units": {"infantry": 3}, "training": [], "upkeep_accum": 0.0})
	StormManager.load_save_data(_saved_in(StormCycle.Phase.TITHE))
	get_tree().paused = true
	# Lo que haria el call_deferred de game_load_completed, con el menu encima.
	StormManager._resume_tithe()
	var opened_behind: bool = CombatManager.is_in_encounter()
	var demanded_behind: int = _demands.size()
	get_tree().paused = false
	assert_bool(opened_behind).override_failure_message(
		"la defensa se abrio detras del menu principal").is_false()
	assert_int(demanded_behind).is_equal(0)
	# Suelto el menu, el Diezmo se reclama en el primer frame con el juego en marcha.
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(CombatManager.is_in_encounter()).is_true()
	assert_bool(CombatManager.is_defending()).is_true()
	assert_array(_demands).has_size(1)

func test_the_resume_happens_once() -> void:
	StormManager.load_save_data(_saved_in(StormCycle.Phase.TITHE))
	EventBus.game_load_completed.emit()
	await await_idle_frame()
	EventBus.game_load_completed.emit()
	await await_idle_frame()
	assert_array(_demands).has_size(1)

func test_reset_forgets_a_pending_resume() -> void:
	StormManager.load_save_data(_saved_in(StormCycle.Phase.TITHE))
	StormManager.reset()
	EventBus.game_load_completed.emit()
	await await_idle_frame()
	assert_array(_demands).is_empty()
