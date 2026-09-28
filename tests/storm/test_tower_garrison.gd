extends GdUnitTestSuite
## Las torres no solo frenan la tormenta: el dia que los Tasadores se bajan del
## carro, las que siguen en pie arman sus posiciones y pelean.
##
## Es la otra mitad de por que una torre en ruinas duele. Deja de mitigar y deja
## de disparar a la vez, asi que repararla entre tormentas es la decision que
## todo esto existe para provocar.
##
## Toca los autoloads de verdad (GridManager, ArmyManager, PopulationManager,
## CombatManager) porque el recuento de torres en pie lee el grid: un doble no
## probaria nada de lo que puede romperse.

## La torre se arma aqui en vez de cargar `data/buildings/tower.tres` a proposito:
## ese .tres arrastra el modelo 3D, y un test de reglas que necesita importar un
## GLB para correr deja de ser un test de reglas.
const TOWER_MAX_HEALTH := 250

const PLAYER := 0
const ENEMY := 1

var _saved_army: Dictionary = {}
var _saved_population: Dictionary = {}
var _towers: Array = []

func before_test() -> void:
	_saved_army = ArmyManager.get_save_data()
	_saved_population = PopulationManager.get_save_data()
	_towers = []
	ArmyManager.reset()
	# Moral fija y alta: la iniciativa del jugador depende de ella, y estos tests
	# necesitan saber quien abre el tablero para poder cerrarlo a mano.
	PopulationManager.load_save_data({"morale": 100})

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()
	for node in _towers:
		GridManager.remove_building(node)
		node.free()
	_towers.clear()
	ArmyManager.load_save_data(_saved_army)
	PopulationManager.load_save_data(_saved_population)

# ── Utillaje ─────────────────────────────────────────────────────────

func _given_army(units: Dictionary) -> void:
	ArmyManager.load_save_data({"units": units, "training": [], "upkeep_accum": 0.0})

func _tower_data() -> BuildingData:
	var data := BuildingData.new()
	data.id = GameConfig.storm_tower_building_id
	data.grid_size = Vector2i(1, 1)
	data.max_health = TOWER_MAX_HEALTH
	return data

## Una torre en el grid de verdad, con su salud en el nodo como en partida: el
## recuento lee GridManager, asi que plantarla de mentira no probaria nada.
func _given_towers(count: int, ruined: bool = false) -> void:
	for i in count:
		var node := Node3D.new()
		node.set_meta("health", 0 if ruined else TOWER_MAX_HEALTH)
		assert_bool(GridManager.place_building(Vector2i(_towers.size(), 0), _tower_data(), node)).is_true()
		_towers.append(node)

func _crews() -> Dictionary:
	return CombatManager.get_tower_crews(CombatManager.get_garrison())

func _crew_count() -> int:
	return CombatManager.roster_size(_crews())

func _units_of_side(side: int) -> Array:
	var result: Array = []
	for unit in CombatManager.get_units():
		if unit.side == side:
			result.append(unit)
	return result

func _wipe(side: int, unit_id: String = "") -> void:
	for unit in _units_of_side(side):
		if unit_id.is_empty() or unit.unit_id == unit_id:
			unit.take_damage(unit.max_hp * 10)

## Cierra el turno del jugador, que es lo que hace al tablero mirar si ya acabo.
func _let_the_board_settle() -> void:
	assert_bool(CombatManager.end_turn()).is_true()

# ── Que pone una torre en el tablero ─────────────────────────────────

func test_a_standing_tower_mans_a_position() -> void:
	_given_army({"infantry": 2})
	_given_towers(1)
	assert_int(_crew_count()).is_equal(1)

func test_a_ruined_tower_mans_nothing() -> void:
	# Igual que no mitiga: una ruina no dispara.
	_given_army({"infantry": 2})
	_given_towers(1, true)
	assert_bool(_crews().is_empty()).is_true()

func test_only_the_towers_still_standing_are_counted() -> void:
	_given_towers(2)
	_given_towers(3, true)
	assert_int(CombatManager.count_standing_towers()).is_equal(2)

func test_the_crew_is_a_gun_because_a_tower_does_not_manoeuvre() -> void:
	# Una torre es una posicion fija con un reflector: ve venir al enemigo de
	# lejos y no se mueve de ahi. Eso es artilleria, no infanteria.
	_given_army({"infantry": 1})
	_given_towers(1)
	assert_bool(_crews().has(GameConfig.storm_tower_garrison_unit)).is_true()
	var gun: Dictionary = GameConfig.get_combat_stats(GameConfig.storm_tower_garrison_unit)
	var foot: Dictionary = GameConfig.get_combat_stats("infantry")
	assert_int(int(gun["range"])).is_greater(int(foot["range"]))
	assert_int(int(gun["move"])).is_less(int(foot["move"]))

func test_more_towers_man_more_positions() -> void:
	_given_army({"infantry": 1})
	_given_towers(1)
	var one: int = _crew_count()
	_given_towers(1)
	assert_int(_crew_count()).is_greater(one)

# ── Ademas del tope, no dentro ───────────────────────────────────────

func test_towers_add_to_the_garrison_instead_of_taking_its_place() -> void:
	# Si contaran dentro del tope de despliegue, construir una torre seria
	# cambiar un soldado entrenado por una dotacion: la torre no aportaria nada
	# al tablero, que es justo lo que venia a arreglar.
	_given_army({"infantry": GameConfig.combat_deploy_cap})
	_given_towers(1)
	var garrison := CombatManager.get_garrison()
	assert_int(CombatManager.roster_size(garrison)).is_equal(GameConfig.combat_deploy_cap)
	assert_int(CombatManager.roster_size(garrison) + _crew_count()) \
		.is_greater(GameConfig.combat_deploy_cap)

func test_the_crews_have_a_ceiling_of_their_own() -> void:
	# Por lo mismo que la mitigacion lo tiene: una fila de torres no puede
	# convertir el Diezmo en un tramite.
	_given_army({"infantry": 1})
	_given_towers(GameConfig.building_limits[GameConfig.storm_tower_building_id])
	assert_int(_crew_count()).is_equal(GameConfig.storm_tower_garrison_max)

# ── El tablero no se desborda ────────────────────────────────────────

func test_the_defence_never_outgrows_a_rank() -> void:
	_given_army({"infantry": 20})
	_given_towers(GameConfig.building_limits[GameConfig.storm_tower_building_id])
	var garrison := CombatManager.get_garrison()
	assert_int(CombatManager.roster_size(garrison) + _crew_count()) \
		.is_less_equal(GameConfig.combat_board_size.x)

func test_the_towers_yield_the_space_before_overflowing_it() -> void:
	# Si alguien sube el tope de despliegue, las dotaciones ceden el sitio antes
	# que dejar unidades fuera del tablero.
	assert_int(GameConfig.get_tower_garrison(99, GameConfig.combat_board_size.x)).is_equal(0)
	assert_int(GameConfig.get_tower_garrison(99, GameConfig.combat_board_size.x + 5)).is_equal(0)
	assert_int(GameConfig.get_tower_garrison(-3, 0)).is_equal(0)

func test_every_defender_gets_its_own_cell_in_the_player_rows() -> void:
	_given_army({"infantry": GameConfig.combat_deploy_cap})
	_given_towers(GameConfig.building_limits[GameConfig.storm_tower_building_id])
	assert_bool(CombatManager.start_defense({"infantry": 2})).is_true()

	var board: Vector2i = GameConfig.combat_board_size
	var taken: Dictionary = {}
	for unit in _units_of_side(PLAYER):
		assert_bool(unit.position.x >= 0 and unit.position.x < board.x).is_true()
		assert_bool(unit.position.y >= board.y - 2 and unit.position.y < board.y).is_true()
		assert_bool(taken.has(unit.position)).is_false()
		taken[unit.position] = true
	assert_int(taken.size()) \
		.is_equal(GameConfig.combat_deploy_cap + GameConfig.storm_tower_garrison_max)

# ── Quien puede plantarse ────────────────────────────────────────────

func test_without_towers_the_defence_is_the_one_it_always_was() -> void:
	_given_army({"infantry": 3})
	assert_bool(_crews().is_empty()).is_true()
	assert_bool(CombatManager.start_defense({"infantry": 2})).is_true()
	assert_int(_units_of_side(PLAYER).size()).is_equal(3)

func test_the_towers_can_hold_the_line_with_the_barracks_empty() -> void:
	# La posicion se defiende sola: eso es lo que una torre es.
	_given_army({})
	_given_towers(1)
	assert_bool(CombatManager.start_defense({"infantry": 2})).is_true()
	assert_int(_units_of_side(PLAYER).size()).is_equal(1)

func test_with_every_tower_in_ruins_and_nobody_home_the_tithe_goes_through() -> void:
	_given_army({})
	_given_towers(3, true)
	assert_bool(CombatManager.start_defense({"infantry": 2})).is_false()

# ── Las dotaciones no salen del cuartel ──────────────────────────────

func test_a_fallen_crew_does_not_cost_the_player_a_gun() -> void:
	# El fallo que esto vigila: las dotaciones entran al tablero como artilleria,
	# y si sus bajas pasaran por ArmyManager una defensa cara le borraria al
	# jugador canones que nunca saco del cuartel.
	_given_army({"infantry": GameConfig.combat_deploy_cap, "artillery": 2})
	_given_towers(1)
	# El cuartel llena el tope con infanteria, asi que la unica artilleria que
	# pisa el tablero es la de la torre.
	assert_int(int(CombatManager.get_garrison().get("artillery", 0))).is_equal(0)
	assert_bool(CombatManager.start_defense({"infantry": 1})).is_true()

	_wipe(PLAYER, GameConfig.storm_tower_garrison_unit)
	_wipe(ENEMY)
	_let_the_board_settle()

	assert_int(ArmyManager.get_count("artillery")).is_equal(2)
	var result := CombatManager.get_last_result()
	assert_int(int(result["tower_crews_lost"])).is_equal(1)
	assert_bool(result["casualties"].has("artillery")).is_false()

func test_a_surviving_crew_does_not_come_home_as_army() -> void:
	_given_army({"infantry": 2})
	_given_towers(1)
	assert_bool(CombatManager.start_defense({"infantry": 1})).is_true()
	_wipe(ENEMY)
	_let_the_board_settle()

	var result := CombatManager.get_last_result()
	assert_bool(result["victory"]).is_true()
	assert_int(int(result["tower_crews"])).is_equal(1)
	assert_int(int(result["survivors"]["infantry"])).is_equal(2)
	assert_bool(result["survivors"].has("artillery")).is_false()
	assert_int(ArmyManager.get_count("artillery")).is_equal(0)

# ── Una defensa no siempre empieza de cero ───────────────────────────

func test_a_defence_can_open_with_a_side_that_is_already_on_its_feet() -> void:
	# Encadenar defensas solo significa algo si los supervivientes entran a la
	# siguiente con lo que traen: recomponer la guarnicion borraria el desgaste.
	_given_army({"infantry": 2})
	_given_towers(1)
	assert_bool(CombatManager.start_defense({"infantry": 1})).is_true()
	var survivors: Array = _units_of_side(PLAYER)
	for unit in survivors:
		unit.take_damage(1)
	CombatManager.end_encounter()

	assert_bool(CombatManager.start_defense({"infantry": 1}, survivors)).is_true()
	assert_int(_units_of_side(PLAYER).size()).is_equal(survivors.size())
	for unit in _units_of_side(PLAYER):
		assert_int(unit.hp).is_less(unit.max_hp)

func test_a_crew_that_survives_a_wave_is_still_not_army_in_the_next() -> void:
	_given_army({"infantry": GameConfig.combat_deploy_cap, "artillery": 2})
	_given_towers(1)
	assert_bool(CombatManager.start_defense({"infantry": 1})).is_true()
	var survivors: Array = _units_of_side(PLAYER)
	CombatManager.end_encounter()

	assert_bool(CombatManager.start_defense({"infantry": 1}, survivors)).is_true()
	_wipe(PLAYER, GameConfig.storm_tower_garrison_unit)
	_wipe(ENEMY)
	_let_the_board_settle()

	assert_int(ArmyManager.get_count("artillery")).is_equal(2)
	assert_int(int(CombatManager.get_last_result()["tower_crews_lost"])).is_equal(1)

func test_winning_a_defence_with_towers_still_pays_nothing() -> void:
	# La recompensa de una defensa es conservar lo tuyo. Que las torres ayuden a
	# ganarla no le anade botin: eso seria cobrar dos veces por la misma pelea.
	_given_army({"infantry": 2})
	_given_towers(2)
	assert_bool(CombatManager.start_defense({"infantry": 1})).is_true()
	_wipe(ENEMY)
	_let_the_board_settle()

	var result := CombatManager.get_last_result()
	assert_bool(result["victory"]).is_true()
	assert_bool(result["defense"]).is_true()
	assert_bool(result["rewards"].is_empty()).is_true()
