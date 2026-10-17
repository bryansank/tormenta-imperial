extends RefCounted
## Recursos y trabajadores de sobra para las suites que prueban el ORDEN del
## tutorial, no lo que cuesta. Desde 2026-10-17 (docs/23 §2.7) un edificio que
## no se puede pagar cambia el paso a "consigue lo que falta" (need_<id>), asi
## que esas suites no pueden depender de lo que dejo la suite anterior.
##
##   var _plenty := Plenty.new()
##   before_test(): _plenty.park()      after_test(): _plenty.restore()

var _res: Dictionary = {}
var _pop: Dictionary = {}
var _floor := 0

func park() -> void:
	_res = {}
	var all: Dictionary = ResourceManager.get_all()
	for type in all:
		_res[ResourceManager.get_type_name(type)] = all[type]
	_pop = PopulationManager.get_save_data()
	ResourceManager.set_amounts({"gold": 5000, "wood": 5000, "food": 500})
	PopulationManager._population = 40
	PopulationManager._max_population = 40
	PopulationManager._used_workers = 0
	# Cada building_placed recuenta la poblacion desde las casas de la rejilla
	# (sin Nucleo en estas escenas, cero): el suelo la mantiene en 40.
	_floor = GameConfig.population_floor
	GameConfig.population_floor = 40

func restore() -> void:
	GameConfig.population_floor = _floor
	ResourceManager.set_amounts(_res)
	PopulationManager.load_save_data(_pop)
