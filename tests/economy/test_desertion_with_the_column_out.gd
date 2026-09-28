extends GdUnitTestSuite
## Quien deserta cuando la nomina no se paga y hay columna fuera.
##
## La desercion se llevaba la unidad mas cara del ejercito entero, sin mirar si
## esa unidad estaba en casa o a dos dias de marcha. El total nunca se descuadra
## —la columna se liquida entera al volver— pero la identidad si: un caido en
## campana "desertaba" en el cuartel y, al liquidar la expedicion, quien se
## borraba del recuento era un superviviente. El jugador veia irse una artilleria
## que no estaba, y volver una que ya habia perdido.
##
## Toca los autoloads de verdad (ArmyManager, CombatManager, ResourceManager):
## el fallo vive justo en la costura entre dos servicios, y un doble de cualquiera
## de los dos lo taparia.

var _saved_resources: Dictionary = {}
var _saved_army: Dictionary = {}
var _saved_progression: Dictionary = {}

var _deserted: Array = []     # [unit_id, count] por emision
var _unpaid: Array = []       # falta de oro por emision

func before_test() -> void:
	_saved_resources = _resource_snapshot()
	_saved_army = ArmyManager.get_save_data()
	_saved_progression = ProgressionManager.get_save_data()
	ArmyManager.reset()
	CombatManager.reset()
	ProgressionManager.final_audit = null
	# Moral fija: la expedicion la congela al salir, y sin fijarla el tablero de
	# salida depende de lo que haya dejado otra suite.
	PopulationManager.load_save_data({"morale": 100})
	_deserted = []
	_unpaid = []
	# EventBus es un autoload: conectado a mano y desconectado al salir.
	EventBus.army_deserted.connect(_on_deserted)
	EventBus.army_upkeep_unpaid.connect(_on_unpaid)

func after_test() -> void:
	EventBus.army_deserted.disconnect(_on_deserted)
	EventBus.army_upkeep_unpaid.disconnect(_on_unpaid)
	CombatManager.reset()
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_saved_progression)
	ArmyManager.load_save_data(_saved_army)
	ResourceManager.set_amounts(_saved_resources)

func _on_deserted(unit_id: String, count: int) -> void:
	_deserted.append([unit_id, count])

func _on_unpaid(missing: int) -> void:
	_unpaid.append(missing)

# ── Utillaje ─────────────────────────────────────────────────────────

func _resource_snapshot() -> Dictionary:
	var snap := {}
	for type in ResourceManager.get_all():
		snap[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	return snap

func _army(units: Dictionary) -> void:
	ArmyManager.load_save_data({"units": units, "training": [], "upkeep_accum": 0.0})

func _broke() -> void:
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 0})

func _grace() -> int:
	return GameConfig.unpaid_grace_ticks

## Tantas nominas impagadas como hagan falta para que la gracia se agote y la
## siguiente muerda.
func _miss_the_payroll(times: int) -> void:
	for i in range(times):
		ArmyManager._pay_upkeep()

# ── Solo deserta quien esta en casa ──────────────────────────────────

func test_the_column_cannot_desert_from_a_barracks_it_is_not_in() -> void:
	# La artilleria es lo mas caro de mantener, asi que seria la primera en irse
	# de estar en casa. Esta de expedicion: se va un infante, que es quien queda.
	_army({"infantry": 2, "artillery": 1})
	assert_bool(CombatManager.launch_expedition({"artillery": 1})).is_true()
	assert_int(int(CombatManager.get_units_on_expedition().get("artillery", 0))).is_equal(1)

	_broke()
	_miss_the_payroll(_grace() + 1)

	assert_int(ArmyManager.get_count("artillery")).is_equal(1)
	assert_int(ArmyManager.get_count("infantry")).is_equal(2 - GameConfig.desertion_units_per_tick)
	assert_array(_deserted).has_size(1)
	assert_str(str(_deserted[0][0])).is_equal("infantry")

func test_a_barracks_emptied_by_the_expedition_loses_nobody() -> void:
	# Todo el ejercito esta fuera. No queda nadie a quien se le pueda dar la baja:
	# los de la columna no estan aqui para largarse.
	_army({"infantry": 2})
	assert_bool(CombatManager.launch_expedition({"infantry": 2})).is_true()

	_broke()
	_miss_the_payroll(_grace() + 4)

	assert_int(ArmyManager.get_total_units()).is_equal(2)
	assert_array(_deserted).is_empty()

func test_the_wage_warning_still_goes_out_with_nobody_at_home() -> void:
	# Que no deserte nadie no quiere decir que no pase nada: la nomina sigue sin
	# pagarse y el jugador tiene que enterarse igual, o la deuda le crece a
	# espaldas mientras mira el mapa de la expedicion.
	_army({"infantry": 2})
	assert_bool(CombatManager.launch_expedition({"infantry": 2})).is_true()

	_broke()
	_miss_the_payroll(_grace() + 1)

	assert_array(_unpaid).has_size(_grace() + 1)
	assert_int(ArmyManager.get_unpaid_ticks()).is_equal(_grace() + 1)

func test_desertion_never_takes_more_than_what_stayed_behind() -> void:
	# Un solo infante en casa y el resto fuera: la cuota no puede morder a la
	# columna por desbordarse, ni siquiera cuando el cuartel se queda a cero.
	_army({"infantry": 3})
	assert_bool(CombatManager.launch_expedition({"infantry": 2})).is_true()

	_broke()
	_miss_the_payroll(_grace() + 6)

	# Se va el unico que estaba en casa y ahi se para: los dos de fuera siguen
	# contando hasta que la columna vuelva.
	assert_int(ArmyManager.get_total_units()).is_equal(2)
	assert_array(_deserted).has_size(1)

# ── Sin columna fuera, nada cambia ───────────────────────────────────

func test_with_everybody_at_home_the_costliest_still_walks_out_first() -> void:
	# La regla de siempre sigue en pie: sin expedicion, el cuartel entero es "casa".
	_army({"infantry": 2, "artillery": 1})
	_broke()
	_miss_the_payroll(_grace() + 1)

	assert_int(ArmyManager.get_count("artillery")).is_equal(0)
	assert_int(ArmyManager.get_count("infantry")).is_equal(2)
