extends GdUnitTestSuite
## La Cuota Mínima y la escolta que la trae.
##
## El Diezmo era un porcentaje de lo almacenado, y por eso no servía: con el
## almacén en cero se llevaban cero, así que vaciar la bolsa en la cola antes de
## que bajaran convertía la tasación en un trámite gratis. Era la jugada
## dominante del juego.
##
## Ahora hay una deuda que existe tengas lo que tengas, y lo que no se cubre con
## recursos se cobra en carne — con dos suelos que no se tocan nunca: el Núcleo
## y el último habitante. Se puede caer hasta el fondo, no se puede perder.

const SPOTS: Array[Vector2i] = [
	Vector2i(3, 3), Vector2i(7, 3), Vector2i(11, 3), Vector2i(15, 3), Vector2i(19, 3),
	Vector2i(3, 9), Vector2i(7, 9), Vector2i(11, 9), Vector2i(15, 9), Vector2i(19, 9),
]

const TYPES: Array = [
	ResourceManager.Type.GOLD, ResourceManager.Type.STEEL,
	ResourceManager.Type.OIL, ResourceManager.Type.WOOD,
]

var _placed: Array = []
var _next: int = 0
var _saved_resources: Dictionary = {}
var _saved_population: Dictionary = {}
var _saved_storm: Dictionary = {}
var _saved_era: int = 1

func before_test() -> void:
	_placed = []
	_next = 0
	_saved_resources = _snapshot_resources()
	_saved_population = PopulationManager.get_save_data()
	_saved_storm = StormManager.get_save_data()
	_saved_era = ProgressionManager.current_era

func after_test() -> void:
	for node in _placed:
		if is_instance_valid(node):
			GridManager.remove_building(node)
	_placed.clear()
	ResourceManager.set_amounts(_saved_resources)
	PopulationManager.load_save_data(_saved_population)
	StormManager.load_save_data(_saved_storm)
	ProgressionManager.current_era = _saved_era

# ── Utillería ────────────────────────────────────────────────────────

func _snapshot_resources() -> Dictionary:
	var out: Dictionary = {}
	for type in TYPES:
		out[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	return out

func _given_stores(gold: int, steel: int, oil: int, wood: int) -> void:
	ResourceManager.set_amounts({"gold": gold, "steel": steel, "oil": oil, "wood": wood})

## Primero el techo y después la gente: `PopulationManager` recorta la población
## al aforo, así que sin casas plantadas cualquier cifra se hunde hasta el suelo.
## Las casas no son embargables ni esenciales, así que no enturbian lo que se
## está midiendo.
func _given_population(count: int) -> void:
	var house: BuildingData = load("res://data/buildings/house.tres")
	var per_house: int = maxi(1, house.population_capacity)
	for i in ceili(float(count) / float(per_house)):
		_build("house")
	PopulationManager.load_save_data({"population": count, "morale": 75, "unpaid_ticks": 0})
	assert_int(PopulationManager.get_population()).is_equal(count)

func _given_storms_survived(count: int) -> void:
	var cycle: StormCycle = StormManager.get_cycle()
	cycle.storms_survived = count

func _build(id: String) -> Node3D:
	var data: BuildingData = load("res://data/buildings/%s.tres" % id)
	var node: Node3D = auto_free(Node3D.new())
	node.name = "%s_%d" % [id, _next]
	assert_bool(GridManager.place_building(SPOTS[_next], data, node)).is_true()
	_next += 1
	_placed.append(node)
	return node

func _total_of(taken: Dictionary, keys: Array) -> int:
	var sum: int = 0
	for key in keys:
		sum += int(taken.get(key, 0))
	return sum

func _roster_size(severity: int) -> int:
	var sum: int = 0
	for count in StormManager.assessor_roster(severity).values():
		sum += int(count)
	return sum

# ── La deuda ─────────────────────────────────────────────────────────

func test_the_debt_exists_with_an_empty_store() -> void:
	# El suelo entero del 2.4 en una línea: esconder la bolsa deja de ser gratis.
	assert_int(GameConfig.get_tithe_debt(1, 1, 0)).is_greater(0)

func test_a_harsher_assessment_costs_more() -> void:
	assert_int(GameConfig.get_tithe_debt(GameConfig.storm_severity_max, 1, 0)) \
		.is_greater(GameConfig.get_tithe_debt(1, 1, 0))

func test_a_richer_era_is_assessed_higher() -> void:
	# Crecer es lo que te pone en el libro: la era es parte de la factura.
	assert_int(GameConfig.get_tithe_debt(1, 3, 0)).is_greater(GameConfig.get_tithe_debt(1, 1, 0))

func test_the_floor_never_undercuts_the_percentage() -> void:
	# El suelo existe para quien llega con la bolsa vacía, no para abaratarle el
	# Diezmo a quien llega lleno.
	var stored: int = 4000
	var share: int = int(float(stored) * GameConfig.get_tithe_ratio(3))
	assert_int(GameConfig.get_tithe_debt(3, 3, stored)).is_equal(share)
	assert_int(share).is_greater(GameConfig.get_tithe_debt(3, 3, 0))

func test_hoarding_into_a_storm_is_still_the_mistake() -> void:
	assert_int(GameConfig.get_tithe_debt(2, 2, 3000)) \
		.is_greater(GameConfig.get_tithe_debt(2, 2, 300))

# ── Cobrar con la bolsa vacía ────────────────────────────────────────

func test_an_empty_store_is_paid_in_flesh() -> void:
	# El caso que el porcentaje dejaba pasar: sin recursos no pasaba nada.
	_given_stores(0, 0, 0, 0)
	_given_population(8)
	var taken: Dictionary = StormManager._collect_tithe(1)
	assert_int(_total_of(taken, ["buildings", "workers"])).is_greater(0)

func test_they_take_the_statues_before_the_people() -> void:
	# Primero el lujo, después la gente: los Tasadores embargan bienes y solo
	# cuando no quedan bienes anotan personas.
	_given_stores(0, 0, 0, 0)
	_given_population(10)
	for i in 5:
		_build("statue")
	var before: int = PopulationManager.get_population()
	var taken: Dictionary = StormManager._collect_tithe(1)
	assert_int(int(taken.get("buildings", 0))).is_greater(0)
	assert_int(int(taken.get("workers", 0))).is_equal(0)
	assert_int(PopulationManager.get_population()).is_equal(before)

func test_a_seized_holding_is_left_in_ruins_not_erased() -> void:
	# Un edificio dañado no se destruye nunca: lo que se llevan es el uso, y
	# recuperarlo cuesta una reparación.
	_given_stores(0, 0, 0, 0)
	_given_population(10)
	var statue := _build("statue")
	StormManager._collect_tithe(1)
	assert_bool(BuildingHealth.is_ruined(statue)).is_true()
	assert_bool(GridManager.get_building_info(statue).is_empty()).is_false()

func test_with_nothing_left_to_seize_they_take_workers() -> void:
	_given_stores(0, 0, 0, 0)
	_given_population(12)
	var before: int = PopulationManager.get_population()
	var taken: Dictionary = StormManager._collect_tithe(GameConfig.storm_severity_max)
	assert_int(int(taken.get("workers", 0))).is_greater(0)
	assert_int(PopulationManager.get_population()).is_less(before)

# ── Cobrar con la bolsa llena ────────────────────────────────────────

func test_a_full_store_settles_the_bill_on_its_own() -> void:
	_given_stores(2000, 0, 0, 2000)
	_given_population(10)
	var before: int = PopulationManager.get_population()
	var statue := _build("statue")
	var taken: Dictionary = StormManager._collect_tithe(2)
	assert_int(_total_of(taken, ["gold", "wood"])).is_greater(0)
	assert_int(_total_of(taken, ["buildings", "workers"])).is_equal(0)
	assert_bool(BuildingHealth.is_damaged(statue)).is_false()
	assert_int(PopulationManager.get_population()).is_equal(before)

func test_the_bill_is_collected_to_the_last_unit() -> void:
	# Un Tasador no deja pendiente un resto de redondeo: lo cobrado cuadra con
	# lo debido mientras haya con qué.
	_given_stores(500, 300, 200, 400)
	ProgressionManager.current_era = 2
	var debt: int = GameConfig.get_tithe_debt(3, 2, ResourceManager.get_total_stored())
	var taken: Dictionary = StormManager._collect_tithe(3)
	assert_int(_total_of(taken, ["gold", "steel", "oil", "wood"])).is_equal(debt)

func test_the_cut_falls_on_every_column() -> void:
	# A prorrata y no una columna cada vez: el recorte tiene que verse en las
	# cuatro a la vez para que se lea como una tasación.
	_given_stores(800, 800, 800, 800)
	ProgressionManager.current_era = 3
	var taken: Dictionary = StormManager._collect_tithe(GameConfig.storm_severity_max)
	for key in ["gold", "steel", "oil", "wood"]:
		assert_int(int(taken.get(key, 0))).is_greater(0)

func test_they_never_take_more_than_there_is() -> void:
	_given_stores(20, 0, 0, 10)
	_given_population(10)
	StormManager._collect_tithe(GameConfig.storm_severity_max)
	for type in TYPES:
		assert_int(ResourceManager.get_amount(type)).is_greater_equal(0)

# ── Los suelos ───────────────────────────────────────────────────────

func test_the_last_inhabitant_is_never_taken() -> void:
	# Se puede caer hasta el fondo, no se puede perder: sin nadie a quien volver
	# a cobrarle, la provincia deja de servir para lo único que sirve.
	_given_stores(0, 0, 0, 0)
	_given_population(GameConfig.population_floor)
	ProgressionManager.current_era = 3
	StormManager._collect_tithe(GameConfig.storm_severity_max)
	assert_int(PopulationManager.get_population()).is_equal(GameConfig.population_floor)

func test_the_core_is_never_seized() -> void:
	_given_stores(0, 0, 0, 0)
	_given_population(10)
	var core := _build("nucleo")
	ProgressionManager.current_era = 3
	StormManager._collect_tithe(GameConfig.storm_severity_max)
	assert_bool(BuildingHealth.is_damaged(core)).is_false()

func test_the_lifelines_are_not_collateral_either() -> void:
	# El embargo solo alcanza lujo y fuerza. La fundición y el aserradero no
	# entran: el Diezmo cobra, no arrasa — una colonia arrasada no paga el año
	# que viene.
	_given_stores(0, 0, 0, 0)
	_given_population(10)
	var sawmill := _build("sawmill")
	var foundry := _build("foundry")
	ProgressionManager.current_era = 3
	StormManager._collect_tithe(GameConfig.storm_severity_max)
	assert_bool(BuildingHealth.is_damaged(sawmill)).is_false()
	assert_bool(BuildingHealth.is_damaged(foundry)).is_false()

# ── La carrera armamentística ────────────────────────────────────────

func test_the_first_assessment_brings_the_plain_escort() -> void:
	assert_float(GameConfig.get_assessor_escalation(0)).is_equal(1.0)

func test_every_storm_survived_pays_for_more_guns() -> void:
	assert_float(GameConfig.get_assessor_escalation(4)) \
		.is_greater(GameConfig.get_assessor_escalation(1))

func test_the_escalation_has_a_ceiling() -> void:
	# Con techo porque el tablero también lo tiene: sin tope la escalada dejaría
	# de leerse en cuanto desbordara el despliegue.
	assert_float(GameConfig.get_assessor_escalation(999)) \
		.is_equal(GameConfig.storm_assessor_growth_max)

func test_the_roster_grows_with_the_storms_you_beat() -> void:
	# Ganarles hoy no quita el problema: lo encarece.
	_given_storms_survived(0)
	var fresh: int = _roster_size(1)
	_given_storms_survived(6)
	assert_int(_roster_size(1)).is_greater(fresh)

func test_a_veteran_base_still_faces_a_board_that_fits() -> void:
	_given_storms_survived(500)
	for severity in range(1, GameConfig.storm_severity_max + 1):
		var force: int = _roster_size(severity)
		assert_int(force).is_greater(0)
		assert_int(force).is_less_equal(GameConfig.combat_deploy_cap)

func test_they_always_field_a_line_however_veteran_you_are() -> void:
	_given_storms_survived(20)
	for severity in range(1, GameConfig.storm_severity_max + 1):
		assert_int(int(StormManager.assessor_roster(severity).get("infantry", 0))).is_greater(0)
