extends GdUnitTestSuite
## Camino de acceso alrededor de un yacimiento (2026-10-04): el primer extractor
## que se planta junto a un yacimiento tiende gratis un anillo de carretera a
## `extractor + 1` casillas, que deja libre la franja pegada al yacimiento para
## mas extractores. Solo se tiende lo que queda unido a la red del Nucleo.
##
## Monta los colocadores de verdad (2D y 3D) con GameManager retenido
## (hold_start) y la partida del jugador aparcada.

const Placer2D := preload("res://scripts/view2d/BuildingPlacer2D.gd")
const Placer3D := preload("res://scripts/buildings/BuildingPlacer.gd")
const MapGen2D := preload("res://scripts/view2d/MapGenerator2D.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const SaveParking := preload("res://tests/save/save_parking.gd")
const BACKUP_PATH := "user://save_game.access_ring.bak"

func before(do_skip := SaveParking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

var _placer: Node = null
var _map: Node = null
var _gm: Dictionary = {}
var _resources: Dictionary = {}
var _population := 0
var _mode: int = 0

func before_test() -> void:
	SaveParking.park(BACKUP_PATH)
	_gm = {"placer": GameManager._placer, "map": GameManager._map_gen, "started": GameManager._started, "hold": GameManager._hold_start}
	_resources = ResourceManager.get_all().duplicate()
	_population = PopulationManager._population
	_mode = GameMode.current
	GameMode.current = GameMode.Mode.CAMPAIGN
	GridManager.clear_all()
	GameManager._started = false
	GameManager.hold_start()
	_map = MapGen2D.new()
	_map.name = "MapGenerator"
	add_child(_map)

func after_test() -> void:
	EventBus.building_placement_cancelled.emit()
	for info in GridManager.get_all_buildings():
		ProductionManager.unregister(info["node"])
	if is_instance_valid(_placer):
		_placer.clear_all_buildings()
		remove_child(_placer)
		_placer.free()
	if is_instance_valid(_map):
		_map.clear_all_deposits()
		remove_child(_map)
		_map.free()
	GridManager.clear_all()
	var by_name := {}
	for type in _resources:
		by_name[ResourceManager.get_type_name(type)] = _resources[type]
	ResourceManager.set_amounts(by_name)
	PopulationManager._population = _population
	PopulationManager._recalculate_all()
	GameMode.current = _mode
	GameManager._placer = _gm["placer"] if is_instance_valid(_gm["placer"]) else null
	GameManager._map_gen = _gm["map"] if is_instance_valid(_gm["map"]) else null
	GameManager._started = _gm["started"]
	GameManager._hold_start = _gm["hold"]
	SaveParking.restore(BACKUP_PATH)

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id) as BuildingData

## Colocador `script` con el Nucleo en (10,10) y su acera, un bosque 2x2 en
## (20,10), recursos y obreros de sobra.
func _scene(script: GDScript) -> Node:
	_placer = script.new()
	_placer.name = "BuildingPlacer"
	add_child(_placer)
	_placer.place_building_at(_data("nucleo"), Vector2i(10, 10))
	for y in range(9, 14):
		for x in range(9, 14):
			if not (x >= 10 and x <= 12 and y >= 10 and y <= 12):
				_placer.place_building_at(_data("road"), Vector2i(x, y))
	ResourceManager.set_amounts({"gold": 300, "wood": 200, "steel": 0, "oil": 0})
	PopulationManager._population = 40
	PopulationManager._recalculate_all()
	return _map.spawn_deposit("forest", Vector2i(20, 10), -1, Vector2i(2, 2))

func _roads() -> int:
	return Rules.count_building("road")

func _buy_sawmill(cell: Vector2i) -> Node:
	EventBus.building_selected_for_placement.emit(_data("sawmill"))
	if _placer.has_method("try_place"):
		return _placer.try_place(cell)
	_placer._try_place(cell)
	return GridManager.get_building_at(cell)

## El anillo de un bosque 2x2 en (20,10): el borde de x 17..24, y 7..14.
func _ring_border() -> Array:
	var out: Array = []
	for y in range(7, 15):
		for x in range(17, 25):
			if x == 17 or x == 24 or y == 7 or y == 14:
				out.append(Vector2i(x, y))
	return out

func test_the_first_sawmill_lays_the_ring_for_free() -> void:
	var forest := _scene(Placer2D)
	var roads_before := _roads()
	var gold_before := ResourceManager.get_amount(ResourceManager.Type.GOLD)
	var wood_before := ResourceManager.get_amount(ResourceManager.Type.WOOD)
	# Aserradero en x 18..19 (toca el bosque en x 20). Su carretera automatica va
	# de (17,10) a (14,10): 4 tramos, 1 oro cada uno.
	var saw := _buy_sawmill(Vector2i(18, 10))
	assert_object(saw).is_not_null()
	for c in _ring_border():
		assert_bool(Rules.is_road_at(c)).override_failure_message("sin camino en %s" % c).is_true()
	assert_int(_roads() - roads_before).is_equal(4 + _ring_border().size() - 1)
	var saw_data := _data("sawmill")
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(gold_before - saw_data.cost_gold - 4)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.WOOD)).is_equal(wood_before - saw_data.cost_wood)
	assert_bool(bool(forest.get_meta(Rules.ACCESS_RING_META, false))).is_true()
	# Y viaja con el guardado del yacimiento.
	assert_bool(bool(_map.get_all_deposits()[0].get("access_ring", false))).is_true()

func test_the_second_sawmill_does_not_repeat_it_and_fits_in_the_gap() -> void:
	_scene(Placer2D)
	_buy_sawmill(Vector2i(18, 10))
	var roads := _roads()
	var gold := ResourceManager.get_amount(ResourceManager.Type.GOLD)
	# Al otro lado del bosque (x 22..23): pegado al bosque y al anillo (x 24).
	var second := _buy_sawmill(Vector2i(22, 10))
	assert_object(second).is_not_null()
	assert_int(_roads()).is_equal(roads)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(gold - _data("sawmill").cost_gold)
	# La franja pegada al bosque sigue sin carretera: queda para extractores.
	for y in range(9, 13):
		for x in range(19, 23):
			assert_bool(Rules.is_road_at(Vector2i(x, y))).is_false()

func test_the_ring_steps_around_what_is_there() -> void:
	_scene(Placer2D)
	# Una casa sobre el borde del anillo y otro yacimiento pisandolo arriba.
	var house: Node = _placer.place_building_at(_data("house"), Vector2i(17, 13))
	var iron: Node = _map.spawn_deposit("iron_deposit", Vector2i(20, 6), -1, Vector2i(2, 2))
	_buy_sawmill(Vector2i(18, 10))
	assert_object(GridManager.get_building_at(Vector2i(17, 14))).is_same(house)
	assert_object(GridManager.get_building_at(Vector2i(21, 7))).is_same(iron)
	# Lo que no toca la red no se tiende, y todo lo tendido esta unido.
	var network := Rules.connected_roads()
	for c in _ring_border():
		if Rules.is_road_at(c):
			assert_bool(network.has(c)).override_failure_message("tramo suelto en %s" % c).is_true()

func test_the_ring_is_a_normal_road_and_obeys_move_first() -> void:
	_scene(Placer2D)
	var saw := _buy_sawmill(Vector2i(18, 10))
	# (17,10) es el tramo que une el anillo (y el aserradero) con la red.
	var link: Node = GridManager.get_building_at(Vector2i(17, 10))
	assert_array(Rules.road_removal_stranded(link)).contains_exactly([saw])
	# Una esquina del anillo se quita sin mas.
	var corner: Node = GridManager.get_building_at(Vector2i(24, 14))
	_placer._on_demolish_requested(corner)
	assert_bool(Rules.is_road_at(Vector2i(24, 14))).is_false()

func test_the_refinery_well_gets_no_ring() -> void:
	_scene(Placer2D)
	var well: Node = _map.spawn_deposit("oil_well", Vector2i(16, 16), -1, Vector2i(2, 2))
	var verdict := {"deposit": well}
	assert_bool(Rules.wants_access_ring(_data("refinery"), verdict, null)).is_false()

func test_the_3d_placer_lays_it_too() -> void:
	_scene(Placer3D)
	_buy_sawmill(Vector2i(18, 10))
	assert_bool(Rules.is_road_at(Vector2i(24, 7))).is_true()
	assert_bool(Rules.is_road_at(Vector2i(17, 14))).is_true()
