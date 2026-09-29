extends GdUnitTestSuite
## Atasco de la linea jugable: una isla sin pozo de petroleo no tiene era 3 ni
## final, y una sin bosque no tiene apertura. El sorteo viejo elegia el tipo de
## cada yacimiento al azar y sin mirar los demas, asi que pasaba (~2 de cada 100
## mapas). Desde el mapa aleatorio (2026-09-28) cada tipo sortea su propio numero
## entre `GameConfig.deposit_per_type_min` y `deposit_per_type_max`, y cada
## yacimiento deja hueco a su extractor. docs/22-linea-jugable.md, atasco A1.

const MapGen := preload("res://scripts/map/MapGenerator.gd")
const MAPS := 60

var _map: Node = null
var _nucleo: Node3D = null
var _saved_min := 3
var _saved_max := 6

func before_test() -> void:
	_saved_min = GameConfig.deposit_per_type_min
	_saved_max = GameConfig.deposit_per_type_max
	GridManager.clear_all()
	GridManager.reset_size()
	_map = auto_free(MapGen.new())
	add_child(_map)
	_nucleo = auto_free(Node3D.new())

func after_test() -> void:
	GameConfig.deposit_per_type_min = _saved_min
	GameConfig.deposit_per_type_max = _saved_max
	if is_instance_valid(_map):
		_map.clear_all_deposits()
	GridManager.clear_all()
	GridManager.reset_size()

func _new_map(map_seed: int) -> void:
	_map.clear_all_deposits()
	GridManager.clear_all()
	seed(map_seed)
	GridManager.roll_new_map()
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
	for deposit_id in MapGen.DEPOSIT_IDS:
		assert_int(_count(deposit_id)).override_failure_message(
			"%s: %d de %s, hacen falta %d" % [label, _count(deposit_id), deposit_id,
				GameConfig.deposit_per_type_min]
		).is_greater_equal(GameConfig.deposit_per_type_min)
	assert_bool(_map.has_buildable_spot_near("forest", Vector2i(2, 2), 1)).override_failure_message(
		"%s: ningun bosque deja sitio a un aserradero" % label).is_true()
	assert_bool(_map.has_buildable_spot_near("gold_vein", Vector2i(2, 2), 1)).override_failure_message(
		"%s: ninguna veta deja sitio a una mina" % label).is_true()
	assert_bool(_map.has_buildable_spot_near("iron_deposit", Vector2i(2, 2), 1)).override_failure_message(
		"%s: ningun hierro deja sitio a una fundicion" % label).is_true()

func test_every_generated_island_can_reach_the_third_era() -> void:
	for i in range(MAPS):
		_new_map(1000 + i)
		_assert_the_map_can_be_finished("semilla %d" % (1000 + i))

## El caso extremo: un solo yacimiento por tipo. Los cuatro tipos llegan igual.
func test_even_one_per_type_brings_all_four_types() -> void:
	GameConfig.deposit_per_type_min = 1
	GameConfig.deposit_per_type_max = 1
	for i in range(10):
		_new_map(77 + i)
		for deposit_id in MapGen.DEPOSIT_IDS:
			assert_int(_count(deposit_id)).is_equal(1)

## El tope se respeta aunque sobre sitio: nunca mas de `deposit_per_type_max`.
func test_the_maximum_is_a_ceiling() -> void:
	for i in range(10):
		_new_map(500 + i)
		for deposit_id in MapGen.DEPOSIT_IDS:
			assert_int(_count(deposit_id)).is_less_equal(GameConfig.deposit_per_type_max)
