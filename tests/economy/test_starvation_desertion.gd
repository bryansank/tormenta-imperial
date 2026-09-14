extends GdUnitTestSuite
## Hambruna, desercion y suelo de ruina.
##
## Hasta ahora el impago solo restaba moral y avisaba: una amenaza que nunca se
## cumple deja de leerse, y el jugador aprende a ignorarla. Ahora hay dos tics de
## gracia y al tercero se paga con gente y con tropa — pero nunca con la partida:
## siempre queda un habitante en pie.

var _saved_resources: Dictionary = {}
var _saved_army: Dictionary = {}

func before_test() -> void:
	_saved_resources = _resource_snapshot()
	_saved_army = ArmyManager.get_save_data()
	ArmyManager.reset()
	PopulationManager.reset()

func after_test() -> void:
	PopulationManager.reset()
	ArmyManager.load_save_data(_saved_army)
	ResourceManager.set_amounts(_saved_resources)

# ── Ayudas ───────────────────────────────────────────────────────────

func _resource_snapshot() -> Dictionary:
	var snap := {}
	for type in ResourceManager.get_all():
		snap[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	return snap

func _broke() -> void:
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 0})

func _rich() -> void:
	ResourceManager.set_amounts({"gold": 600, "wood": 600, "steel": 600, "oil": 600})

func _army(units: Dictionary) -> void:
	ArmyManager.load_save_data({"units": units, "training": [], "upkeep_accum": 0.0})

func _grace() -> int:
	return GameConfig.unpaid_grace_ticks

# ── La regla de la gracia ────────────────────────────────────────────

func test_the_grace_is_forgiving_until_it_is_not() -> void:
	assert_bool(GameConfig.unpaid_hurts(0)).is_false()
	assert_bool(GameConfig.unpaid_hurts(_grace())).is_false()
	assert_bool(GameConfig.unpaid_hurts(_grace() + 1)).is_true()

func test_there_really_are_two_ticks_of_grace() -> void:
	# Si esto cambia, cambia el ritmo del juego entero: dos tics es el margen
	# para reaccionar sin que el impago se pueda ignorar para siempre.
	assert_int(_grace()).is_equal(2)

# ── Hambruna ─────────────────────────────────────────────────────────

func test_the_first_two_hungry_ticks_only_hurt_morale() -> void:
	_broke()
	var before := PopulationManager.get_population()
	for i in range(_grace()):
		PopulationManager._tick_consumption()
	assert_int(PopulationManager.get_population()).is_equal(before)
	assert_int(PopulationManager.get_unpaid_ticks()).is_equal(_grace())

func test_the_third_hungry_tick_kills() -> void:
	_broke()
	var before := PopulationManager.get_population()
	for i in range(_grace() + 1):
		PopulationManager._tick_consumption()
	assert_int(PopulationManager.get_population()).is_equal(before - GameConfig.starvation_deaths_per_tick)

func test_hunger_keeps_killing_every_tick_after_that() -> void:
	_broke()
	var before := PopulationManager.get_population()
	for i in range(_grace() + 2):
		PopulationManager._tick_consumption()
	assert_int(PopulationManager.get_population()).is_equal(before - 2 * GameConfig.starvation_deaths_per_tick)

func test_paying_again_wipes_the_slate() -> void:
	_broke()
	for i in range(_grace()):
		PopulationManager._tick_consumption()
	assert_int(PopulationManager.get_unpaid_ticks()).is_equal(_grace())

	_rich()
	PopulationManager._tick_consumption()
	assert_int(PopulationManager.get_unpaid_ticks()).is_equal(0)

	# Y la gracia vuelve entera: el siguiente impago no mata de golpe.
	_broke()
	var before := PopulationManager.get_population()
	PopulationManager._tick_consumption()
	assert_int(PopulationManager.get_population()).is_equal(before)

func test_a_hungry_tick_announces_itself() -> void:
	# Conectado a mano a proposito: monitor_signals() de gdUnit libera el objeto
	# que vigila al terminar, y EventBus es un autoload — vigilarlo mata el bus
	# para todas las suites que corran despues.
	_broke()
	for i in range(_grace()):
		PopulationManager._tick_consumption()
	var deaths := [0]
	var probe := func(dead: int, _pop: int): deaths[0] += dead
	EventBus.population_starved.connect(probe)
	PopulationManager._tick_consumption()
	EventBus.population_starved.disconnect(probe)
	assert_int(deaths[0]).is_equal(GameConfig.starvation_deaths_per_tick)

# ── El suelo de ruina ────────────────────────────────────────────────

func test_the_last_citizen_never_dies() -> void:
	PopulationManager.remove_population(9999)
	assert_int(PopulationManager.get_population()).is_equal(GameConfig.population_floor)

func test_starving_forever_still_leaves_someone() -> void:
	_broke()
	for i in range(50):
		PopulationManager._tick_consumption()
	assert_int(PopulationManager.get_population()).is_equal(GameConfig.population_floor)

func test_the_floor_is_a_living_person() -> void:
	# La decision de diseno: se puede caer hasta el fondo, pero no se pierde la
	# partida. Un suelo de cero seria una pantalla de derrota con otro nombre.
	assert_int(GameConfig.population_floor).is_greater(0)

# ── Desercion ────────────────────────────────────────────────────────

func test_the_first_two_unpaid_wages_lose_nobody() -> void:
	_army({"infantry": 2})
	_broke()
	for i in range(_grace()):
		ArmyManager._pay_upkeep()
	assert_int(ArmyManager.get_total_units()).is_equal(2)
	assert_int(ArmyManager.get_unpaid_ticks()).is_equal(_grace())

func test_the_third_unpaid_wage_empties_a_bunk() -> void:
	_army({"infantry": 2})
	_broke()
	for i in range(_grace() + 1):
		ArmyManager._pay_upkeep()
	assert_int(ArmyManager.get_total_units()).is_equal(2 - GameConfig.desertion_units_per_tick)

func test_the_costliest_unit_walks_out_first() -> void:
	# La que mas cuesta mantener es justo la que el jugador no quiere perder, y
	# por eso es la que se va: la consecuencia tiene que morder donde importa.
	_army({"infantry": 2, "artillery": 1})
	_broke()
	for i in range(_grace() + 1):
		ArmyManager._pay_upkeep()
	assert_int(ArmyManager.get_count("artillery")).is_equal(0)
	assert_int(ArmyManager.get_count("infantry")).is_equal(2)

func test_desertion_walks_down_the_payroll() -> void:
	_army({"infantry": 1, "artillery": 1})
	_broke()
	for i in range(_grace() + 2):
		ArmyManager._pay_upkeep()
	# Primero la cara, despues la barata.
	assert_int(ArmyManager.get_count("artillery")).is_equal(0)
	assert_int(ArmyManager.get_count("infantry")).is_equal(0)

func test_paying_the_wages_forgives_the_debt() -> void:
	_army({"infantry": 2})
	_broke()
	for i in range(_grace()):
		ArmyManager._pay_upkeep()
	assert_int(ArmyManager.get_unpaid_ticks()).is_equal(_grace())

	_rich()
	ArmyManager._pay_upkeep()
	assert_int(ArmyManager.get_unpaid_ticks()).is_equal(0)

	_broke()
	ArmyManager._pay_upkeep()
	assert_int(ArmyManager.get_total_units()).is_equal(2)

func test_an_army_that_deserted_to_nothing_stops_there() -> void:
	_army({"infantry": 1})
	_broke()
	for i in range(20):
		ArmyManager._pay_upkeep()
	assert_int(ArmyManager.get_total_units()).is_equal(0)

func test_desertion_announces_itself() -> void:
	# Conectado a mano, por lo mismo que en la hambruna: EventBus es un autoload.
	_army({"infantry": 2})
	_broke()
	for i in range(_grace()):
		ArmyManager._pay_upkeep()
	var gone := {"id": "", "count": 0}
	var probe := func(unit_id: String, count: int):
		gone["id"] = unit_id
		gone["count"] = count
	EventBus.army_deserted.connect(probe)
	ArmyManager._pay_upkeep()
	EventBus.army_deserted.disconnect(probe)
	assert_str(str(gone["id"])).is_equal("infantry")
	assert_int(int(gone["count"])).is_equal(GameConfig.desertion_units_per_tick)

func test_the_unpaid_counter_travels_in_the_save() -> void:
	_army({"infantry": 2})
	_broke()
	for i in range(_grace()):
		ArmyManager._pay_upkeep()
	var save := ArmyManager.get_save_data()
	assert_int(int(save["unpaid_ticks"])).is_equal(_grace())

	ArmyManager.reset()
	assert_int(ArmyManager.get_unpaid_ticks()).is_equal(0)
	ArmyManager.load_save_data(save)
	assert_int(ArmyManager.get_unpaid_ticks()).is_equal(_grace())

	# Y una partida guardada antes de que existiera la desercion carga igual.
	ArmyManager.load_save_data({"units": {"infantry": 1}, "training": [], "upkeep_accum": 0.0})
	assert_int(ArmyManager.get_unpaid_ticks()).is_equal(0)

func test_the_hunger_counter_travels_in_the_save() -> void:
	_broke()
	for i in range(_grace()):
		PopulationManager._tick_consumption()
	var save := PopulationManager.get_save_data()
	assert_int(int(save["unpaid_ticks"])).is_equal(_grace())

	PopulationManager.reset()
	assert_int(PopulationManager.get_unpaid_ticks()).is_equal(0)
	PopulationManager.load_save_data(save)
	assert_int(PopulationManager.get_unpaid_ticks()).is_equal(_grace())

	# Un guardado viejo sin contador se carga sin deuda pendiente.
	PopulationManager.load_save_data({"population": 4, "morale": 50})
	assert_int(PopulationManager.get_unpaid_ticks()).is_equal(0)
