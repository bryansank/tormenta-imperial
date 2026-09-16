extends GdUnitTestSuite
## Riesgo medido de A2: exigir un bosque adyacente deja menos sitios validos,
## y la apertura de Era 1 (500 recursos, aserradero 80/50 + mina 120/80) tiene
## que poder jugarse en cualquier mapa nuevo.
##
## Se generan mapas reales con el MapGenerator (Nucleo 3x3 en el centro como en
## GameManager._new_game) y se pregunta si queda un hueco legal para un
## aserradero (2x1, cualquier orientacion) tocando un bosque, y para una mina
## (2x2) tocando una veta. Lo que no se puede garantizar desde aqui —que el
## mapa traiga al menos un bosque— se mide y se imprime para el informe.
##
## Toca GridManager y GameConfig reales: cada caso los deja como estaban.

const MapGen := preload("res://scripts/map/MapGenerator.gd")
const MAPS := 40

var _map: Node = null
var _nucleo: Node3D = null

func before_test() -> void:
	GridManager.clear_all()
	_map = auto_free(MapGen.new())
	add_child(_map)
	_nucleo = auto_free(Node3D.new())

func after_test() -> void:
	if is_instance_valid(_map):
		_map.clear_all_deposits()
	GridManager.clear_all()

## Un mapa como el de GameManager._new_game: Nucleo en el centro y yacimientos.
func _new_map() -> void:
	_map.clear_all_deposits()
	GridManager.clear_all()
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	GridManager.place_obstacle(center, _nucleo, Vector2i(3, 3))
	_map.generate_new_map()

func _count(deposit_id: String) -> int:
	var n := 0
	for d in _map.get_all_deposits():
		if d["id"] == deposit_id:
			n += 1
	return n

func test_whenever_there_is_a_forest_a_sawmill_can_stand_next_to_it() -> void:
	var without_forest := 0
	var without_vein := 0
	var forest_but_no_spot := 0
	var vein_but_no_spot := 0
	for i in range(MAPS):
		_new_map()
		if _count("forest") == 0:
			without_forest += 1
		elif not _map.has_buildable_spot_near("forest", Vector2i(2, 1), 1):
			forest_but_no_spot += 1
		if _count("gold_vein") == 0:
			without_vein += 1
		elif not _map.has_buildable_spot_near("gold_vein", Vector2i(2, 2), 1):
			vein_but_no_spot += 1
	print("[era1] %d mapas: sin bosque %d, bosque sin hueco %d | sin veta %d, veta sin hueco %d" % [MAPS, without_forest, forest_but_no_spot, without_vein, vein_but_no_spot])
	# Lo que la regla de alcance SI puede romper: un bosque rodeado sin hueco.
	assert_int(forest_but_no_spot).is_equal(0)
	assert_int(vein_but_no_spot).is_equal(0)

func test_a_forest_hemmed_in_on_every_side_has_no_spot() -> void:
	# Control del buscador: si el anillo alrededor esta ocupado, dice que no.
	_map.spawn_deposit("forest", Vector2i(10, 10), -1, Vector2i(2, 2))
	var wall: Node3D = auto_free(Node3D.new())
	for x in range(8, 14):
		for y in range(8, 14):
			var c := Vector2i(x, y)
			if GridManager.is_cell_free(c):
				GridManager.place_obstacle(c, wall)
	assert_bool(_map.has_buildable_spot_near("forest", Vector2i(2, 1), 1)).is_false()

func test_a_lonely_forest_offers_spots_in_both_orientations() -> void:
	_map.spawn_deposit("forest", Vector2i(10, 10), -1, Vector2i(2, 2))
	var spots: Array = _map.buildable_spots_near("forest", Vector2i(2, 1), 1)
	var horizontal := 0
	var vertical := 0
	for s in spots:
		if s["size"] == Vector2i(2, 1):
			horizontal += 1
		else:
			vertical += 1
	assert_int(horizontal).is_greater(0)
	assert_int(vertical).is_greater(0)
	# Y cada hueco devuelto es legal de verdad.
	for s in spots:
		assert_bool(GridManager.can_place(s["origin"], s["size"])).is_true()
		assert_bool(MapGen.deposit_within_reach(Vector2i(10, 10), Vector2i(2, 2), GridManager.cells_for(s["origin"], s["size"]), 1)).is_true()

func test_the_opening_is_affordable_with_the_starting_purse() -> void:
	# 300 oro + 200 madera cubren aserradero (80/50) y mina (120/80) juntos.
	var sawmill: BuildingData = load("res://data/buildings/sawmill.tres")
	var mine: BuildingData = load("res://data/buildings/gold_mine.tres")
	var gold: int = int(GameConfig.starting_resources.get("gold", 0))
	var wood: int = int(GameConfig.starting_resources.get("wood", 0))
	assert_int(sawmill.cost_gold + mine.cost_gold).is_less_equal(gold)
	assert_int(sawmill.cost_wood + mine.cost_wood).is_less_equal(wood)
