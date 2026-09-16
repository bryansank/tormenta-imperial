extends GdUnitTestSuite
## El Diezmo cae con el jugador de expedicion: el tablero esta ocupado, asi que
## la guarnicion que quedo en casa pelea sola (AutoResolver) y el Diezmo se
## resuelve con ese resultado. Lo que hay que vigilar es que la pelea a ciegas
## no toque el tablero abierto ni emita sus senales, y que las consecuencias
## (bajas, Diezmo) sigan siendo las de una defensa jugada.
##
## Toca los autoloads de verdad (StormManager, CombatManager, ArmyManager,
## PopulationManager, ResourceManager, GridManager); cada caso los deja como
## estaban.

const TOWER_MAX_HEALTH := 250

var _storm_saved: Dictionary = {}
var _army_saved: Dictionary = {}
var _population_saved: Dictionary = {}
var _resources_saved: Dictionary = {}
var _mult_saved: float = 1.0
var _towers: Array = []

var _auto: Array = []          # [victory, rounds, summary] por emision
var _started: int = 0
var _ended: int = 0
var _tithes: Array = []        # [repelled, taken] por emision

func before_test() -> void:
	_storm_saved = StormManager.get_save_data()
	_army_saved = ArmyManager.get_save_data()
	_population_saved = PopulationManager.get_save_data()
	_resources_saved = _resource_amounts()
	_mult_saved = GameConfig.event_production_multiplier
	StormManager.reset()
	CombatManager.reset()
	ArmyManager.reset()
	# Moral fija y alta: la iniciativa del jugador depende de ella, y el tablero
	# abierto tiene que quedarse esperando al jugador, no a un timer de la IA.
	PopulationManager.load_save_data({"morale": 100})
	ResourceManager.set_amounts({"gold": 400, "wood": 200, "steel": 0, "oil": 0})
	_auto = []
	_started = 0
	_ended = 0
	_tithes = []
	_towers = []
	EventBus.defense_auto_resolved.connect(_on_auto)
	EventBus.encounter_started.connect(_on_started)
	EventBus.encounter_ended.connect(_on_ended)
	EventBus.tithe_resolved.connect(_on_tithe)

func after_test() -> void:
	EventBus.defense_auto_resolved.disconnect(_on_auto)
	EventBus.encounter_started.disconnect(_on_started)
	EventBus.encounter_ended.disconnect(_on_ended)
	EventBus.tithe_resolved.disconnect(_on_tithe)
	CombatManager.end_encounter()
	CombatManager.reset()
	for node in _towers:
		GridManager.remove_building(node)
		node.free()
	_towers.clear()
	StormManager.load_save_data(_storm_saved)
	ArmyManager.load_save_data(_army_saved)
	PopulationManager.load_save_data(_population_saved)
	ResourceManager.set_amounts(_resources_saved)
	GameConfig.event_production_multiplier = _mult_saved

func _on_auto(victory: bool, rounds: int, summary: Dictionary) -> void:
	_auto.append([victory, rounds, summary])

func _on_started(_index: int, _boss: bool) -> void:
	_started += 1

func _on_ended(_victory: bool, _turns: int) -> void:
	_ended += 1

func _on_tithe(repelled: bool, taken: Dictionary) -> void:
	_tithes.append([repelled, taken])

# ── Utillaje ─────────────────────────────────────────────────────────

func _resource_amounts() -> Dictionary:
	return {
		"gold": ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"wood": ResourceManager.get_amount(ResourceManager.Type.WOOD),
		"steel": ResourceManager.get_amount(ResourceManager.Type.STEEL),
		"oil": ResourceManager.get_amount(ResourceManager.Type.OIL),
	}

func _given_army(units: Dictionary) -> void:
	ArmyManager.load_save_data({"units": units, "training": [], "upkeep_accum": 0.0})

func _tower_data() -> BuildingData:
	var data := BuildingData.new()
	data.id = GameConfig.storm_tower_building_id
	data.grid_size = Vector2i(1, 1)
	data.max_health = TOWER_MAX_HEALTH
	return data

func _given_towers(count: int) -> void:
	for i in count:
		var node := Node3D.new()
		node.set_meta("health", TOWER_MAX_HEALTH)
		assert_bool(GridManager.place_building(Vector2i(_towers.size(), 0), _tower_data(), node)).is_true()
		_towers.append(node)

## Una expedicion a medias: el tablero queda abierto y esperando al jugador.
func _given_the_board_busy() -> void:
	assert_bool(CombatManager.start_skirmish({"infantry": 1})).is_true()
	assert_bool(CombatManager.is_in_encounter()).is_true()
	assert_bool(CombatManager.is_player_turn()).is_true()
	_started = 0

## Los Tasadores bajan del carro con el reloj en TITHE.
func _drop_the_tithe(severity: int = 1) -> void:
	StormManager.get_cycle().phase = StormCycle.Phase.TITHE
	StormManager._begin_tithe(severity)

func _snapshot_board() -> Array:
	var shot: Array = []
	for unit in CombatManager.get_units():
		shot.append([unit.uid, unit.unit_id, unit.side, unit.hp, unit.position, unit.has_acted])
	return shot

# ── Con el tablero ocupado, la guarnicion pelea sola ─────────────────

func test_with_the_board_busy_the_garrison_fights_alone_and_repels_the_tithe() -> void:
	_given_army({"infantry": 4, "artillery": 2})
	_given_the_board_busy()
	_drop_the_tithe(1)
	assert_int(_auto.size()).is_equal(1)
	assert_bool(_auto[0][0]).override_failure_message("seis contra tres deberia ganarse").is_true()
	assert_int(int(_auto[0][1])).is_greater(0)
	# El Diezmo se resolvio en el acto, sin esperar a que el tablero abierto termine.
	assert_int(_tithes.size()).is_equal(1)
	assert_bool(_tithes[0][0]).is_true()
	assert_bool((_tithes[0][1] as Dictionary).is_empty()).is_true()
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.CALM)

func test_the_headless_fight_emits_no_board_signals() -> void:
	# El tablero abierto tomaria encounter_started/ended como suyos y cerraria la
	# expedicion del jugador con el resultado de otra pelea.
	_given_army({"infantry": 4, "artillery": 2})
	_given_the_board_busy()
	_drop_the_tithe(1)
	assert_int(_started).is_equal(0)
	assert_int(_ended).is_equal(0)

func test_the_open_encounter_is_left_exactly_as_it_was() -> void:
	_given_army({"infantry": 4, "artillery": 2})
	_given_the_board_busy()
	var encounter_before: Encounter = CombatManager.get_encounter()
	var board_before: Array = _snapshot_board()
	var morale_before: float = CombatManager.get_morale_snapshot()
	_drop_the_tithe(1)
	assert_bool(CombatManager.is_in_encounter()).is_true()
	assert_bool(CombatManager.is_defending()).is_false()
	assert_object(CombatManager.get_encounter()).is_same(encounter_before)
	assert_array(_snapshot_board()).is_equal(board_before)
	assert_float(CombatManager.get_morale_snapshot()).is_equal(morale_before)
	assert_bool(CombatManager.is_player_turn()).is_true()

func test_the_summary_carries_the_last_result_of_the_headless_fight() -> void:
	_given_army({"infantry": 4, "artillery": 2})
	_given_the_board_busy()
	_drop_the_tithe(1)
	var summary: Dictionary = _auto[0][2]
	assert_bool(bool(summary.get("defense", false))).is_true()
	assert_bool((summary.get("rewards", {"x": 1}) as Dictionary).is_empty()).is_true()
	assert_dict(summary).is_equal(CombatManager.get_last_result())

# ── Perder a ciegas cuesta lo mismo que perder jugando ───────────────

func test_a_lost_headless_defense_pays_the_tithe() -> void:
	_given_army({"infantry": 1})
	_given_the_board_busy()
	var gold_before: int = ResourceManager.get_amount(ResourceManager.Type.GOLD)
	_drop_the_tithe(GameConfig.storm_severity_max)
	assert_int(_auto.size()).is_equal(1)
	assert_bool(_auto[0][0]).override_failure_message("uno contra la columna entera no se gana").is_false()
	assert_int(_tithes.size()).is_equal(1)
	assert_bool(_tithes[0][0]).is_false()
	assert_bool((_tithes[0][1] as Dictionary).is_empty()).is_false()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_less(gold_before)
	# Y el tablero del jugador sigue abierto, ajeno a todo.
	assert_bool(CombatManager.is_in_encounter()).is_true()
	assert_int(_ended).is_equal(0)

func test_garrison_casualties_leave_the_army_but_tower_crews_do_not() -> void:
	_given_army({"infantry": 1, "artillery": 1})
	_given_towers(2)
	assert_int(CombatManager.roster_size(CombatManager.get_tower_crews(CombatManager.get_garrison()))).is_equal(2)
	_given_the_board_busy()
	var army_before: int = ArmyManager.get_total_units()
	_drop_the_tithe(GameConfig.storm_severity_max)
	var summary: Dictionary = _auto[0][2]
	assert_int(int(summary.get("tower_crews", 0))).is_equal(2)
	var casualties: int = 0
	for count in (summary.get("casualties", {}) as Dictionary).values():
		casualties += int(count)
	# Solo las bajas del roster salen del ejercito; las dotaciones, aunque caigan,
	# nunca estuvieron en el.
	assert_int(casualties).is_less_equal(2)
	assert_int(army_before - ArmyManager.get_total_units()).is_equal(casualties)
	assert_int(int(summary.get("tower_crews_lost", 0))).is_less_equal(2)

# ── Sin nadie en casa, cobran igual ──────────────────────────────────

func test_nobody_home_lets_the_tithe_through_without_a_headless_fight() -> void:
	_given_army({})
	_given_the_board_busy()
	_drop_the_tithe(1)
	assert_int(_auto.size()).is_equal(0)
	assert_int(_tithes.size()).is_equal(1)
	assert_bool(_tithes[0][0]).is_false()
	assert_int(_started).is_equal(0)

func test_auto_resolve_defense_says_why_when_it_cannot_fight() -> void:
	_given_army({})
	var undefended: Dictionary = CombatManager.auto_resolve_defense({"infantry": 2})
	assert_bool(bool(undefended.get("fought", true))).is_false()
	assert_bool(bool(undefended.get("victory", true))).is_false()
	assert_str(String(undefended.get("reason", ""))).is_equal("undefended")
	_given_army({"infantry": 2})
	var nobody: Dictionary = CombatManager.auto_resolve_defense({})
	assert_bool(bool(nobody.get("fought", true))).is_false()
	assert_str(String(nobody.get("reason", ""))).is_equal("no_attackers")
	assert_int(_auto.size()).is_equal(0)

# ── Con el tablero libre, todo sigue como siempre ────────────────────

func test_with_the_board_free_the_defense_still_opens_the_board() -> void:
	_given_army({"infantry": 2})
	_drop_the_tithe(1)
	assert_bool(CombatManager.is_in_encounter()).is_true()
	assert_bool(CombatManager.is_defending()).is_true()
	assert_int(_started).is_equal(1)
	assert_int(_auto.size()).is_equal(0)
	# El Diezmo espera al tablero.
	assert_int(_tithes.size()).is_equal(0)
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.TITHE)
