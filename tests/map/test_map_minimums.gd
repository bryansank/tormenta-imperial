extends GdUnitTestSuite
## Atasco de la linea jugable: una isla sin pozo de petroleo no tiene era 3 ni
## final, y una sin bosque no tiene apertura. El sorteo de MapGenerator elegia el
## tipo de cada yacimiento al azar y sin mirar los demas, asi que pasaba (~2 de
## cada 100 mapas). Ahora `_guarantee_minimums()` completa hasta
## `GameConfig.deposit_min_per_type` y exige un hueco legal para el extractor.
## docs/22-linea-jugable.md, atasco A1.

const MapGen := preload("res://scripts/map/MapGenerator.gd")
const MAPS := 60

var _map: Node = null
var _nucleo: Node3D = null
var _saved_min := 18
var _saved_max := 28

func before_test() -> void:
	_saved_min = GameConfig.deposit_count_min
	_saved_max = GameConfig.deposit_count_max
	GridManager.clear_all()
	_map = auto_free(MapGen.new())
	add_child(_map)
	_nucleo = auto_free(Node3D.new())

func after_test() -> void:
	GameConfig.deposit_count_min = _saved_min
	GameConfig.deposit_count_max = _saved_max
	if is_instance_valid(_map):
		_map.clear_all_deposits()
	GridManager.clear_all()

func _new_map(map_seed: int) -> void:
	_map.clear_all_deposits()
	GridManager.clear_all()
	seed(map_seed)
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	GridManager.place_obstacle(center, _nucleo, Vector2i(3, 3))
	_map.generate_new_map()

func _count(deposit_id: String) -> int:
	var n := 0
	for d in _map.get_all_deposits():
		if d["id"] == deposit_id:
			n += 1
	return n

func _assert_the_map_can_be_finished(label: String) -> void:
	for deposit_id in GameConfig.deposit_min_per_type:
		assert_int(_count(deposit_id)).override_failure_message(
			"%s: %d de %s, hacen falta %d" % [label, _count(deposit_id), deposit_id,
				int(GameConfig.deposit_min_per_type[deposit_id])]
		).is_greater_equal(int(GameConfig.deposit_min_per_type[deposit_id]))
	assert_bool(_map.has_buildable_spot_near("forest", Vector2i(2, 1), 1)).override_failure_message(
		"%s: ningun bosque deja sitio a un aserradero" % label).is_true()
	assert_bool(_map.has_buildable_spot_near("gold_vein", Vector2i(2, 2), 1)).override_failure_message(
		"%s: ninguna veta deja sitio a una mina" % label).is_true()
	assert_bool(_map.has_buildable_spot_near("iron_deposit", Vector2i(2, 1), 1)).override_failure_message(
		"%s: ningun hierro deja sitio a una fundicion" % label).is_true()

func test_every_generated_island_can_reach_the_third_era() -> void:
	for i in range(MAPS):
		_new_map(1000 + i)
		_assert_the_map_can_be_finished("semilla %d" % (1000 + i))

## El caso extremo: un sorteo de un solo yacimiento. Antes salia una isla con un
## unico tipo; ahora trae los cuatro igual.
func test_even_a_one_deposit_roll_brings_all_four_types() -> void:
	GameConfig.deposit_count_min = 1
	GameConfig.deposit_count_max = 1
	for i in range(10):
		_new_map(77 + i)
		_assert_the_map_can_be_finished("sorteo de uno, semilla %d" % (77 + i))

## Completar solo AÑADE: el sorteo de siempre queda intacto delante, asi que un
## mapa que ya traia de todo sale identico al de antes de este arreglo.
func test_completing_only_adds_after_the_usual_roll() -> void:
	var saved: Dictionary = GameConfig.deposit_min_per_type
	var none: Dictionary = {}
	for key in saved:
		none[key] = 0
	for i in range(10):
		GameConfig.deposit_min_per_type = none
		_new_map(500 + i)
		var without: Array = _map.get_all_deposits()
		GameConfig.deposit_min_per_type = saved
		_new_map(500 + i)
		var with_minimums: Array = _map.get_all_deposits()
		assert_int(with_minimums.size()).is_greater_equal(without.size())
		assert_array(with_minimums.slice(0, without.size())).is_equal(without)
	GameConfig.deposit_min_per_type = saved
