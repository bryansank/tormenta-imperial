extends GdUnitTestSuite
## Integridad del estado de combate: que el ledger de ArmyManager, el tablero, la
## expedicion y el asedio cuenten siempre la misma historia, tambien a traves de
## un guardado y de dos tableros que se pisan.
##
## Toca los autoloads de verdad; cada caso los deja como estaban.

var _storm_saved: Dictionary = {}
var _army_saved: Dictionary = {}
var _population_saved: Dictionary = {}
var _resources_saved: Dictionary = {}
var _progression_saved: Dictionary = {}

var _audit_lost: int = 0
var _encounters_ended: int = 0

func before_test() -> void:
	_storm_saved = StormManager.get_save_data()
	_army_saved = ArmyManager.get_save_data()
	_population_saved = PopulationManager.get_save_data()
	_resources_saved = _resource_amounts()
	_progression_saved = ProgressionManager.get_save_data()
	StormManager.reset()
	CombatManager.reset()
	ArmyManager.reset()
	ProgressionManager.final_audit = null
	PopulationManager.load_save_data({"morale": 100})
	ResourceManager.set_amounts({"gold": 400, "wood": 200, "steel": 0, "oil": 0})
	_audit_lost = 0
	_encounters_ended = 0
	EventBus.final_audit_lost.connect(_on_audit_lost)
	EventBus.encounter_ended.connect(_on_encounter_ended)

func after_test() -> void:
	EventBus.final_audit_lost.disconnect(_on_audit_lost)
	EventBus.encounter_ended.disconnect(_on_encounter_ended)
	CombatManager.reset()
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_progression_saved)
	StormManager.load_save_data(_storm_saved)
	ArmyManager.load_save_data(_army_saved)
	PopulationManager.load_save_data(_population_saved)
	ResourceManager.set_amounts(_resources_saved)

func _on_audit_lost(_wave: int) -> void:
	_audit_lost += 1

func _on_encounter_ended(_victory: bool, _rounds: int) -> void:
	_encounters_ended += 1

func _resource_amounts() -> Dictionary:
	return {
		"gold": ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"wood": ResourceManager.get_amount(ResourceManager.Type.WOOD),
		"steel": ResourceManager.get_amount(ResourceManager.Type.STEEL),
		"oil": ResourceManager.get_amount(ResourceManager.Type.OIL),
	}

func _given_army(units: Dictionary) -> void:
	ArmyManager.load_save_data({"units": units, "training": [], "upkeep_accum": 0.0})

func _enemy_roster_on_board() -> Dictionary:
	var counts: Dictionary = {}
	for unit in CombatManager.get_units():
		if unit.side == Encounter.ENEMY:
			counts[unit.unit_id] = int(counts.get(unit.unit_id, 0)) + 1
	return counts

## Mata a un bando entero sin pasar por el modelo y cierra el turno para que el
## encuentro mire si ya acabo. No emite unit_died: es el camino "a ciegas".
func _resolve_open_board(player_wins: bool) -> void:
	var loser: int = Encounter.ENEMY if player_wins else Encounter.PLAYER
	for unit in CombatManager.get_units():
		if unit.side == loser and unit.is_alive():
			unit.take_damage(unit.max_hp * 10)
	CombatManager.end_turn()

# ── 8. La escaramuza usa el generador con semilla ────────────────────

func test_a_skirmish_fields_the_seeded_roster_of_the_first_node() -> void:
	_given_army({"infantry": 3})
	assert_bool(CombatManager.start_skirmish({"infantry": 2}, 1234)).is_true()
	var expected: Dictionary = ExpeditionGenerator.enemy_roster(
		ExpeditionGenerator.make_rng(1234), 0, ProgressionManager.current_era, 0)
	assert_dict(_enemy_roster_on_board()).is_equal(expected)

func test_the_same_seed_fields_the_same_skirmish() -> void:
	_given_army({"infantry": 3})
	CombatManager.start_skirmish({"infantry": 2}, 77)
	var first: Dictionary = _enemy_roster_on_board()
	CombatManager.reset()
	CombatManager.start_skirmish({"infantry": 2}, 77)
	assert_dict(_enemy_roster_on_board()).is_equal(first)

func test_the_provisional_unseeded_roster_is_gone() -> void:
	assert_bool(CombatManager.has_method("build_enemy_roster")).is_false()

# ── 5. Un solo bucle enemigo por tablero ─────────────────────────────

var _enemy_actions: int = 0

func _count_enemy_action(_a = null, _b = null, _c = null) -> void:
	_enemy_actions += 1

## Tablero A con la IA pensando (paso corto); se cierra y se abre B, tambien con
## el enemigo moviendo primero pero con un paso muy largo. Si el bucle de A
## despierta y se cree el dueño de B, suelta la bandera y relanza un bucle nuevo
## que ya lee el paso corto: el enemigo de B actuaria mucho antes de su tiempo.
func test_a_stale_enemy_turn_never_drives_the_next_board() -> void:
	var saved_delay: float = GameConfig.combat_ai_step_delay
	var saved_dev: bool = GameConfig.dev_mode
	GameConfig.dev_mode = false
	_enemy_actions = 0
	# Artilleria (iniciativa 3) contra infanteria (5): abre el enemigo. Con la
	# moral a tope la artilleria empataria y el empate es del jugador.
	PopulationManager.load_save_data({"morale": 0})
	GameConfig.combat_ai_step_delay = 0.15
	CombatManager.start_encounter({"artillery": 2}, {"infantry": 2})
	assert_bool(CombatManager.is_enemy_thinking()).is_true()
	CombatManager.end_encounter()

	GameConfig.combat_ai_step_delay = 4.0
	CombatManager.start_encounter({"artillery": 2}, {"infantry": 2})
	assert_bool(CombatManager.is_enemy_thinking()).is_true()
	GameConfig.combat_ai_step_delay = 0.02

	EventBus.unit_moved.connect(_count_enemy_action)
	EventBus.unit_attacked.connect(_count_enemy_action)
	EventBus.unit_defended.connect(_count_enemy_action)
	await get_tree().create_timer(0.6).timeout
	EventBus.unit_moved.disconnect(_count_enemy_action)
	EventBus.unit_attacked.disconnect(_count_enemy_action)
	EventBus.unit_defended.disconnect(_count_enemy_action)

	GameConfig.combat_ai_step_delay = saved_delay
	GameConfig.dev_mode = saved_dev
	assert_int(_enemy_actions).is_equal(0)
	assert_bool(CombatManager.is_enemy_thinking()).is_true()
