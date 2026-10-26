extends GdUnitTestSuite
## Que las cuentas de trabajadores del tutorial cierren (2026-10-24). Queja de
## Bryan: "los trabajadores se agotan: no puedo construir la Casa porque me pones
## Cuartel y comida primero; no tiene sentido". Con 5 colonos el Aserradero (2),
## el Cuartel (1) y la Granja (2) los gastaban todos antes de la Casa: ni minar a
## mano (2) cabia, y sin minar no habia oro para la Casa.
##
## Ahora (tutorial corto, 2026-10-24): 10 colonos y sitio para 10 en el Nucleo;
## el tutorial ya no pide Casa. Si una Casa entra, llega llena al terminar
## (PopulationManager._move_in). Esta prueba
## recorre las metas del tutorial EN SU ORDEN con las cifras de verdad
## (BuildingData, GameConfig) y comprueba que ningun edificio se queda sin
## trabajadores y que siempre caben los de minar a mano.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")

## Recorre GUIDE_GOALS y devuelve [{"goal", "used", "pop"}] tras cada edificio,
## o falla en el primero que no tenga trabajadores.
func _walk() -> Array:
	var nucleo: BuildingData = Rules.load_building_data("nucleo")
	var room: int = nucleo.population_capacity
	var pop: int = mini(GameConfig.population_start, room)
	var used := 0
	var out: Array = []
	for g in TutorialManager.GUIDE_GOALS:
		if String(g.get("kind", "build")) != "build":
			continue
		var data: BuildingData = Rules.load_building_data(String(g["building"]))
		assert_int(used + data.workers_required).override_failure_message(
			"%s pide %d trabajadores y solo quedan %d de %d" % [data.id, data.workers_required, pop - used, pop]
		).is_less_equal(pop)
		used += data.workers_required
		if data.population_capacity > 0:
			# La Casa termina su obra y llega llena (si la moral deja crecer, que al
			# empezar si: GameConfig.morale_start >= morale_growth_threshold).
			room += data.population_capacity
			pop = room
		out.append({"goal": String(g["goal"]), "used": used, "pop": pop})
	return out

func test_no_tutorial_building_runs_out_of_workers() -> void:
	var walk := _walk()
	assert_int(walk.size()).is_equal(3)
	# Al acabar el tutorial aun quedan manos libres.
	assert_int(int(walk[-1]["pop"]) - int(walk[-1]["used"])).is_greater_equal(0)

func test_hand_mining_always_fits_during_the_tutorial() -> void:
	# Minar a mano es como se consigue oro o madera sin su edificio: tiene que
	# caber en cada paso, tambien al acabar el tutorial.
	for row in _walk():
		assert_int(int(row["used"]) + GameConfig.mining_workers).override_failure_message(
			"tras %s no cabe minar a mano (%d de %d)" % [row["goal"], row["used"], row["pop"]]
		).is_less_equal(int(row["pop"]))

func test_no_house_is_needed_during_the_short_guide() -> void:
	# Tutorial corto (2026-10-24): Aserradero, Mina de oro y Cuartel con la gente
	# del Nucleo, sin Casa; y detras cabe aun la Granja (2) que pide ¿QUE HACER?.
	var walk := _walk()
	var last: Dictionary = walk[-1]
	assert_int(int(last["pop"])).is_equal(GameConfig.population_start)
	var farm: BuildingData = Rules.load_building_data("farm")
	assert_int(int(last["used"]) + farm.workers_required).is_less_equal(int(last["pop"]))

func test_the_growth_rules_let_the_house_fill_at_once() -> void:
	# La Casa llega llena solo si la moral deja crecer: la de salida si.
	assert_int(GameConfig.morale_start).is_greater_equal(GameConfig.morale_growth_threshold)
	assert_int(GameConfig.population_start).is_equal(10)
	assert_int(Rules.load_building_data("nucleo").population_capacity).is_greater_equal(GameConfig.population_start)
