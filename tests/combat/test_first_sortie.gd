extends GdUnitTestSuite
## La primera escaramuza de la partida (docs/15-combat.md §4): un solo nodo, sin
## mapa ni jefe, contra un enemigo debil y con un botin que se nota. Es lo que
## pide ¿QUE HACER? en cuanto sale del cuartel la primera unidad.
##
## Lo que se fija: la forma del mapa, que se gana con un solo infante a cualquier
## moral (medido con AutoResolver, la misma IA en los dos bandos), que cobra lo
## que dice GameConfig, que sobrevive a guardar y cargar, que la expedicion normal
## no cambia, y el cableado en CombatManager y TutorialManager.

const ExpeditionScript := preload("res://scripts/combat/Expedition.gd")
const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const EncounterScript := preload("res://scripts/combat/Encounter.gd")
const ResolverScript := preload("res://scripts/combat/AutoResolver.gd")

## Cuantas semillas se miden y que fraccion tiene que ganarse.
const SEEDS := 50
const MIN_WIN_RATE := 0.8

var _saved_army: Dictionary = {}
var _saved_population: Dictionary = {}
var _saved_resources: Dictionary = {}
var _saved_era: int = 1
var _saved_warehouses: int = 0
var _saved_storm: Dictionary = {}
var _saved_progression: Dictionary = {}
var _saved_tutorial: Dictionary = {}

func before_test() -> void:
	_saved_army = ArmyManager.get_save_data()
	_saved_population = PopulationManager.get_save_data()
	_saved_storm = StormManager.get_save_data()
	_saved_progression = ProgressionManager.get_save_data()
	_saved_tutorial = TutorialManager.get_save_data()
	_saved_era = ResourceManager.get_era()
	_saved_warehouses = ResourceManager.get_warehouse_count()
	_saved_resources = {}
	for type in ResourceManager.get_all():
		_saved_resources[ResourceManager.get_type_name(type)] = int(ResourceManager.get_all()[type])
	StormManager.reset()
	CombatManager.reset()
	ArmyManager.reset()
	TutorialManager.reset()
	ProgressionManager.final_audit = null
	PopulationManager.load_save_data({"morale": 75})
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 0})
	ResourceManager.set_era(1)
	ResourceManager.set_warehouse_count(5)

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_saved_progression)
	StormManager.load_save_data(_saved_storm)
	ArmyManager.load_save_data(_saved_army)
	PopulationManager.load_save_data(_saved_population)
	TutorialManager.load_save_data(_saved_tutorial)
	ResourceManager.set_era(_saved_era)
	ResourceManager.set_warehouse_count(_saved_warehouses)
	ResourceManager.set_amounts(_saved_resources)

# ── Utillaje ─────────────────────────────────────────────────────────

## Juega el nodo actual de `run` con la IA en los dos bandos y lo da por ganado o
## perdido en el modelo. Devuelve si se gano.
func _play_current_node(run: Expedition) -> bool:
	var board: Encounter = EncounterScript.create(run.build_encounter_units(), run.current_node, run.at_boss())
	var outcome: Dictionary = ResolverScript.resolve(board)
	board.release_survivors()
	if bool(outcome["victory"]):
		run.mark_cleared()
	else:
		run.mark_defeated()
	return bool(outcome["victory"])

## Una moral de salida por semilla, de 0 a 100: es lo unico que cambia de una
## primera escaramuza a otra (el tablero no tira dados).
func _morale_for(seed_value: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.randf_range(0.0, 100.0)

## Fraccion de `SEEDS` primeras escaramuzas ganadas con `party` en `era`.
func _first_sortie_win_rate(party: Dictionary, era: int) -> float:
	var won := 0
	for i in range(SEEDS):
		var seed_value: int = 1000 + i * 7
		var run: Expedition = ExpeditionScript.create(1, seed_value, party, _morale_for(seed_value), era, true)
		if _play_current_node(run):
			won += 1
	return float(won) / float(SEEDS)

# ── El mapa ──────────────────────────────────────────────────────────

func test_the_first_sortie_is_a_single_easy_node() -> void:
	var map: Array = Generator.first_sortie_map()
	assert_int(map.size()).is_equal(1)
	var node: Dictionary = map[0]
	assert_bool(bool(node["is_boss"])).is_false()
	assert_array(node["exits"]).is_empty()
	assert_int(int(node["risk"])).is_equal(0)
	assert_dict(node["enemy_roster"]).is_equal(GameConfig.combat_first_sortie_roster)
	assert_float(Generator.node_scale(node, 3)).is_equal(GameConfig.combat_first_sortie_enemy_scale)
	assert_dict(Generator.node_rewards(node, 3)).is_equal(GameConfig.combat_first_sortie_rewards)
	assert_bool(Generator.every_node_reaches_boss(map)).is_true()

## Mas facil que el nodo 0 de cualquier expedicion normal de era 1, y con mas
## botin: es la razon de que exista.
func test_it_is_easier_and_pays_more_than_a_normal_opening() -> void:
	var first: Dictionary = Generator.first_sortie_map()[0]
	for seed_value in [1, 2, 3, 42, 424242]:
		var normal: Dictionary = Generator.generate_map(Generator.make_rng(seed_value), Vector2i.ZERO, Vector2i.ZERO, 1)[0]
		assert_float(Generator.node_power(first, 1)).is_less(Generator.node_power(normal, 1))
		var first_loot: Dictionary = Generator.node_rewards(first, 1)
		var normal_loot: Dictionary = Generator.node_rewards(normal, 1)
		for res_name in normal_loot:
			assert_int(int(first_loot.get(res_name, 0))).is_greater(int(normal_loot[res_name]))

## El enemigo sale con la escala de la primera escaramuza, no con la de la era.
func test_its_enemy_is_scaled_down_in_every_era() -> void:
	for era in [1, 2, 3]:
		var run: Expedition = ExpeditionScript.create(1, 7, {"infantry": 1}, 50.0, era, true)
		var enemies: Array = run.build_enemy_units()
		assert_int(enemies.size()).is_equal(Generator.roster_size(GameConfig.combat_first_sortie_roster))
		for unit in enemies:
			assert_float(unit.scale).is_equal(GameConfig.combat_first_sortie_enemy_scale)

# ── Se gana ──────────────────────────────────────────────────────────

## La medida que pide el diseno: un infante recien salido del cuartel gana la
## primera escaramuza en la mayoria de semillas (>= 80% de 50), a cualquier moral.
func test_one_infantry_wins_the_first_sortie_in_most_seeds() -> void:
	var rate: float = _first_sortie_win_rate({"infantry": 1}, 1)
	assert_float(rate).override_failure_message(
		"un infante gana la primera escaramuza en el %d%% de %d semillas" % [roundi(rate * 100.0), SEEDS]
	).is_greater_equal(MIN_WIN_RATE)

func test_two_infantry_win_it_too() -> void:
	assert_float(_first_sortie_win_rate({"infantry": 2}, 1)).is_greater_equal(MIN_WIN_RATE)

## La razon de todo esto: la expedicion normal se come a ese mismo infante en el
## nodo 0 (dos infantes enteros). Si un dia deja de ser asi, la primera
## escaramuza sobra y esta prueba lo dice.
func test_a_lone_infantry_loses_the_normal_opening() -> void:
	var won := 0
	for i in range(SEEDS):
		var seed_value: int = 1000 + i * 7
		var run: Expedition = ExpeditionScript.create(1, seed_value, {"infantry": 1}, _morale_for(seed_value), 1, false)
		if _play_current_node(run):
			won += 1
	assert_float(float(won) / float(SEEDS)).is_less(MIN_WIN_RATE)

## Ganar su unico nodo termina la campana ganada, sin carta y con el botin fijo.
func test_winning_its_node_ends_the_run_won_with_the_fixed_loot() -> void:
	var run: Expedition = ExpeditionScript.create(1, 99, {"infantry": 1}, 75.0, 1, true)
	assert_bool(_play_current_node(run)).is_true()
	assert_bool(run.is_finished()).is_true()
	assert_int(run.result_code()).is_equal(Expedition.RESULT_WON)
	assert_dict(run.rewards).is_equal(GameConfig.combat_first_sortie_rewards)
	assert_bool(run.boss_defeated()).is_false()
	assert_int(run.nodes_cleared()).is_equal(1)

# ── Guardado ─────────────────────────────────────────────────────────

func test_it_survives_a_save_and_load_mid_run() -> void:
	var run: Expedition = ExpeditionScript.create(4, 1234, {"infantry": 2}, 60.0, 2, true)
	var data: Variant = JSON.parse_string(JSON.stringify(run.to_dict()))
	var back: Expedition = ExpeditionScript.from_dict(data)
	assert_bool(back.first_sortie).is_true()
	assert_int(back.map.size()).is_equal(1)
	assert_dict(back.map[0]["enemy_roster"]).is_equal(GameConfig.combat_first_sortie_roster)
	assert_bool(back.needs_fight()).is_true()

func test_an_old_save_without_the_key_is_a_normal_expedition() -> void:
	var run: Expedition = ExpeditionScript.create(4, 1234, {"infantry": 2}, 60.0, 1, false)
	var data: Dictionary = run.to_dict()
	data.erase("first_sortie")
	var back: Expedition = ExpeditionScript.from_dict(data)
	assert_bool(back.first_sortie).is_false()
	assert_int(back.map.size()).is_equal(run.map.size())
	assert_bool(back.map.size() > 1).is_true()

# ── La expedicion normal no cambia ───────────────────────────────────

func test_a_normal_expedition_keeps_its_map() -> void:
	var a: Expedition = ExpeditionScript.create(1, 424242, {"infantry": 2}, 50.0, 1)
	var b: Array = Generator.generate_map(Generator.make_rng(424242), Vector2i.ZERO, Vector2i.ZERO, 1)
	assert_bool(a.first_sortie).is_false()
	assert_int(a.map.size()).is_equal(b.size())
	for i in range(b.size()):
		assert_dict(a.map[i]["enemy_roster"]).is_equal(b[i]["enemy_roster"])
		assert_bool(a.map[i].has("rewards")).is_false()

# ── El cableado ──────────────────────────────────────────────────────

func test_combat_manager_launches_it_and_pays_it_once() -> void:
	ArmyManager.load_save_data({"units": {"infantry": 1}, "training": [], "upkeep_accum": 0.0})
	assert_bool(CombatManager.is_first_sortie_due()).is_true()
	assert_bool(CombatManager.launch_expedition({"infantry": 1}, 77, CombatManager.is_first_sortie_due())).is_true()
	var run: Expedition = CombatManager.get_expedition()
	assert_bool(run.first_sortie).is_true()
	assert_bool(CombatManager.is_board_open()).is_true()
	# El tablero se juega solo, como lo juega la sonda de la linea.
	var outcome: Dictionary = ResolverScript.resolve(CombatManager.get_encounter())
	CombatManager._emit_events(outcome["events"])
	CombatManager.end_encounter()
	assert_bool(bool(outcome["victory"])).is_true()
	assert_bool(CombatManager.has_active_expedition()).is_false()
	assert_bool(CombatManager.has_pending_draft()).is_false()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(int(GameConfig.combat_first_sortie_rewards["gold"]))
	assert_int(ResourceManager.get_amount(ResourceManager.Type.WOOD)).is_equal(int(GameConfig.combat_first_sortie_rewards["wood"]))
	assert_int(ArmyManager.get_count("infantry")).is_equal(1)
	# Ganada: la siguiente salida ya es una expedicion de verdad.
	assert_bool(TutorialManager.is_first_sortie_done()).is_true()
	assert_bool(CombatManager.is_first_sortie_due()).is_false()

## Sin el tercer argumento, launch_expedition() lanza la expedicion de siempre:
## es lo que usan los tests y las sondas con semilla.
func test_launch_without_the_flag_is_a_normal_expedition() -> void:
	ArmyManager.load_save_data({"units": {"infantry": 2}, "training": [], "upkeep_accum": 0.0})
	assert_bool(CombatManager.launch_expedition({"infantry": 2}, 77)).is_true()
	assert_bool(CombatManager.get_expedition().first_sortie).is_false()
	assert_bool(CombatManager.get_expedition().map.size() > 1).is_true()

## A mitad de la primera escaramuza, guardar y cargar devuelve el mismo nodo.
func test_combat_manager_save_and_load_keep_the_first_sortie() -> void:
	ArmyManager.load_save_data({"units": {"infantry": 1}, "training": [], "upkeep_accum": 0.0})
	CombatManager.launch_expedition({"infantry": 1}, 77, true)
	var data: Variant = JSON.parse_string(JSON.stringify(CombatManager.get_save_data()))
	CombatManager.end_encounter()
	CombatManager.reset()
	CombatManager.load_save_data(data)
	var run: Expedition = CombatManager.get_expedition()
	assert_object(run).is_not_null()
	assert_bool(run.first_sortie).is_true()
	assert_int(run.map.size()).is_equal(1)
