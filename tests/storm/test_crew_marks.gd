extends GdUnitTestSuite
## Quien es dotacion de torre, y quien lo decide.
##
## Las dotaciones pelean del lado del jugador pero no salen del cuartel: sus
## bajas no pueden pasar por ArmyManager, o una defensa perdida le borraria al
## jugador canones que nunca envio. La marca vivia en `_tower_crew_uids`, un
## conjunto que solo se limpiaba al ABRIR tablero, asi que una defensa que
## recibia su bando ya montado preguntaba por sus dotaciones al tablero anterior.
##
## Parecia inofensivo porque los uids de CombatManager son monotonos. No lo es:
## la Auditoria Final numera SU guarnicion desde 1 por su cuenta, asi que sus
## infantes chocan de frente con los uids que dejo cualquier defensa anterior.
##
## Toca los autoloads de verdad (GridManager, ArmyManager, ProgressionManager,
## CombatManager): el fallo es precisamente la costura entre ellos.

## La torre se arma aqui en vez de cargar `data/buildings/tower.tres` a proposito:
## ese .tres arrastra el modelo 3D, y un test de reglas que necesita importar un
## GLB para correr deja de ser un test de reglas.
const TOWER_MAX_HEALTH := 250

const PLAYER := 0
const ENEMY := 1

var _saved_army: Dictionary = {}
var _saved_population: Dictionary = {}
var _saved_progression: Dictionary = {}
var _towers: Array = []

func before_test() -> void:
	_saved_army = ArmyManager.get_save_data()
	_saved_population = PopulationManager.get_save_data()
	_saved_progression = ProgressionManager.get_save_data()
	_towers = []
	ArmyManager.reset()
	CombatManager.reset()
	ProgressionManager.final_audit = null
	# Moral fija y alta: la iniciativa del jugador depende de ella, y estos casos
	# necesitan saber quien abre el tablero para poder cerrarlo a mano.
	PopulationManager.load_save_data({"morale": 100})

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_saved_progression)
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
func _given_towers(count: int) -> void:
	for i in count:
		var node := Node3D.new()
		node.set_meta("health", TOWER_MAX_HEALTH)
		assert_bool(GridManager.place_building(Vector2i(_towers.size(), 0), _tower_data(), node)).is_true()
		_towers.append(node)

func _units_of_side(side: int) -> Array:
	var result: Array = []
	for unit in CombatManager.get_units():
		if unit.side == side:
			result.append(unit)
	return result

func _wipe(side: int) -> void:
	for unit in _units_of_side(side):
		unit.take_damage(unit.max_hp * 10)

## Cierra el turno del jugador, que es lo que hace al tablero mirar si ya acabo.
func _let_the_board_settle() -> void:
	CombatManager.end_turn()

## Uids de las unidades del bando del jugador que hay ahora mismo en el tablero.
func _player_uids() -> Array:
	var uids: Array = []
	for unit in _units_of_side(PLAYER):
		uids.append(unit.uid)
	return uids

# ── Una oleada del asedio no pregunta al tablero anterior ────────────

func test_the_siege_does_not_inherit_crew_marks_from_an_old_board() -> void:
	# Una defensa chica: un infante de guarnicion (uid 1) y la dotacion de la
	# torre (uid 2). Al cerrarla, el 2 queda apuntado como "dotacion".
	_given_army({"infantry": 1})
	_given_towers(1)
	assert_bool(CombatManager.start_defense({"infantry": 2})).is_true()
	assert_array(_player_uids()).contains([1, 2])
	CombatManager.end_encounter()

	# Pasan las semanas y el jugador levanta ejercito. La Auditoria numera su
	# guarnicion desde 1 por su cuenta: su SEGUNDO infante nace con el uid 2, el
	# mismo que tenia aquella dotacion.
	_given_army({"infantry": 4})
	assert_bool(ProgressionManager.summon_final_audit()).is_true()
	assert_bool(ProgressionManager.begin_final_audit()).is_true()
	assert_bool(CombatManager.is_in_encounter()).is_true()

	# La oleada arrasa la guarnicion. Los cuatro infantes tienen que salir del
	# cuartel: si el uid 2 se hubiera contado como dotacion de torre, uno se
	# habria quedado dentro, vivo en el recuento y muerto en el tablero.
	_wipe(PLAYER)
	_let_the_board_settle()

	assert_int(ArmyManager.get_count("infantry")).is_equal(0)
	assert_int(int(CombatManager.get_last_result()["casualties"].get("infantry", 0))).is_equal(4)

func test_a_wave_counts_exactly_the_crews_it_fielded() -> void:
	# El mismo relevo, mirado desde el otro lado del parte: las dotaciones que
	# cuenta la oleada son las que ella misma fabrico, ni una mas.
	_given_army({"infantry": 1})
	_given_towers(1)
	assert_bool(CombatManager.start_defense({"infantry": 2})).is_true()
	CombatManager.end_encounter()

	_given_army({"infantry": 4})
	assert_bool(ProgressionManager.summon_final_audit()).is_true()
	assert_bool(ProgressionManager.begin_final_audit()).is_true()

	# No basta con que el numero cuadre: tienen que ser ESAS unidades. Un uid
	# heredado de la defensa anterior tambien suma uno, y el parte saldria igual
	# de bonito mientras un infante del cuartel se cuela por dotacion.
	var crew_uids: Array = []
	for crew in CombatManager._audit_crews:
		crew_uids.append(crew.uid)
	assert_array(CombatManager._tower_crew_uids.keys()).contains_exactly_in_any_order(crew_uids)

	_wipe(PLAYER)
	_let_the_board_settle()

	assert_int(int(CombatManager.get_last_result()["tower_crews"])).is_equal(crew_uids.size())
	assert_int(int(CombatManager.get_last_result()["tower_crews_lost"])).is_equal(crew_uids.size())

func test_closing_a_board_stops_its_crew_marks_from_answering_for_the_next() -> void:
	# La regla de fondo: en cuanto el tablero se cierra, sus marcas dejan de ser
	# "las del tablero" y no vuelven a decidir nada por si solas.
	_given_army({"infantry": 2})
	_given_towers(1)
	assert_bool(CombatManager.start_defense({"infantry": 2})).is_true()
	assert_dict(CombatManager._tower_crew_uids).is_not_empty()

	CombatManager.end_encounter()

	assert_dict(CombatManager._tower_crew_uids).is_empty()

func test_a_crew_that_survives_still_carries_over_when_nobody_says_otherwise() -> void:
	# Y la contraparte: quien encadena una defensa con los supervivientes del
	# tablero que acaba de cerrar sigue sin tener que declarar nada. Son las
	# mismas unidades y los mismos uids, asi que no hay nada que confundir.
	_given_army({"infantry": GameConfig.combat_deploy_cap, "artillery": 2})
	_given_towers(1)
	assert_bool(CombatManager.start_defense({"infantry": 1})).is_true()
	var survivors: Array = _units_of_side(PLAYER)
	CombatManager.end_encounter()

	assert_bool(CombatManager.start_defense({"infantry": 1}, survivors)).is_true()
	_wipe(PLAYER)
	_wipe(ENEMY)
	_let_the_board_settle()

	# La artilleria del cuartel sigue entera: la que cayo era la de la torre.
	assert_int(ArmyManager.get_count("artillery")).is_equal(2)
	assert_int(int(CombatManager.get_last_result()["tower_crews_lost"])).is_equal(1)

# ── Cargar deja el servicio limpio ───────────────────────────────────

func test_loading_a_save_leaves_nothing_of_the_session_before() -> void:
	# Hoy la carga solo ocurre con los autoloads recien arrancados, asi que esto
	# no cambia una sola partida. Lo que cierra es el camino minado para el dia
	# que se cargue en caliente —guardado en la nube, ranuras de partida—: sin
	# esto, la partida nueva empezaria con el parte de la anterior, un asedio a
	# medias y unas marcas de dotacion que no son de ningun tablero.
	_given_army({"infantry": 2})
	_given_towers(1)
	assert_bool(CombatManager.start_defense({"infantry": 2})).is_true()
	_wipe(ENEMY)
	_let_the_board_settle()

	# Un servicio bien sucio: tablero sin cerrar, parte puesto, marcas vivas,
	# uids gastados y el asedio a medio contar.
	CombatManager._audit_wave_active = true
	CombatManager._audit_wave_won = true
	CombatManager._audit_crew_losses = 3
	CombatManager._last_board_crew_uids = {99: true}
	assert_bool(CombatManager.is_board_open()).is_true()
	assert_dict(CombatManager.get_last_result()).is_not_empty()
	assert_dict(CombatManager._tower_crew_uids).is_not_empty()
	assert_int(CombatManager._next_uid).is_greater(1)

	CombatManager.load_save_data({})

	assert_bool(CombatManager.is_board_open()).is_false()
	assert_bool(CombatManager.has_active_expedition()).is_false()
	assert_dict(CombatManager.get_last_result()).is_empty()
	assert_dict(CombatManager._tower_crew_uids).is_empty()
	assert_dict(CombatManager._last_board_crew_uids).is_empty()
	assert_int(CombatManager._next_uid).is_equal(1)
	assert_bool(CombatManager._result_applied).is_false()
	assert_bool(CombatManager._audit_wave_active).is_false()
	assert_bool(CombatManager._audit_wave_won).is_false()
	assert_int(CombatManager._audit_crew_losses).is_equal(0)
	assert_array(CombatManager._audit_crews).is_empty()
	assert_bool(CombatManager._enemy_turn_running).is_false()

func test_the_cleanup_does_not_eat_the_campaign_it_is_loading() -> void:
	# La limpieza corre ANTES de reconstruir, no despues: una carga con campana
	# dentro sigue devolviendo la campana.
	_given_army({"infantry": 3})
	assert_bool(CombatManager.launch_expedition({"infantry": 3})).is_true()
	var save: Dictionary = CombatManager.get_save_data()
	assert_dict(save).is_not_empty()
	CombatManager.reset()

	CombatManager.load_save_data(save)

	assert_bool(CombatManager.has_active_expedition()).is_true()
	assert_int(CombatManager.get_expedition().id).is_equal(int(save["id"]))
