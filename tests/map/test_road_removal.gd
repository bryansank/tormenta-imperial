extends GdUnitTestSuite
## "Si quito un camino, primero me hace mover los edificios" (2026-10-04).
##
## Quitar (o mover) un tramo de carretera que deja algun edificio sin conexion al
## Nucleo no se deja: la regla devuelve esos edificios, el aviso los nombra y los
## dos colocadores (3D y 2D) los resaltan. Las decoraciones y lo que ya estaba
## suelto no bloquean; un edificio en obras si.
##
## La primera parte solo toca GridManager con nodos de mentira; la ultima monta
## los dos colocadores de verdad, con GameManager retenido (hold_start) y la
## partida del jugador aparcada por si alguna senal la escribiera.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const Placer3D := preload("res://scripts/buildings/BuildingPlacer.gd")
const Placer2D := preload("res://scripts/view2d/BuildingPlacer2D.gd")
const SaveParking := preload("res://tests/save/save_parking.gd")
const BACKUP_PATH := "user://save_game.road_removal.bak"

func before(do_skip := SaveParking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

var _nodes: Array = []

func before_test() -> void:
	GridManager.clear_all()
	_nodes.clear()

func after_test() -> void:
	GridManager.clear_all()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id)

func _put(id: String, cell: Vector2i) -> Node:
	var n := Node.new()
	_nodes.append(n)
	assert_bool(GridManager.place_building(cell, _data(id), n)).is_true()
	return n

## Nucleo 3x3 en (10,10) con su acera: la vuelta de carreteras de (9,9) a (13,13).
func _core_with_ring() -> void:
	_put("nucleo", Vector2i(10, 10))
	for y in range(9, 14):
		for x in range(9, 14):
			if x >= 10 and x <= 12 and y >= 10 and y <= 12:
				continue
			_put("road", Vector2i(x, y))

# ── La regla ──────────────────────────────────────────────────────────

func test_a_road_nobody_needs_is_removed() -> void:
	_core_with_ring()
	_put("sawmill", Vector2i(7, 10))  # pegado a la acera (x=9 toca x=8)
	var corner: Node = GridManager.get_building_at(Vector2i(13, 13))
	assert_array(Rules.road_removal_stranded(corner)).is_empty()

func test_the_bridge_of_a_sawmill_is_not_removed_and_the_message_names_it() -> void:
	_core_with_ring()
	var bridge := _put("road", Vector2i(8, 10))
	var saw := _put("sawmill", Vector2i(6, 10))  # x=6..7: solo lo une (8,10)
	var stranded := Rules.road_removal_stranded(bridge)
	assert_array(stranded).contains_exactly([saw])
	var msg := Rules.move_first_message(stranded)
	assert_str(msg).contains(_data("sawmill").get_display_name())
	assert_int(msg.split(" ", false).size()).is_less_equal(8)
	# Y demoler de verdad no lo quita: devuelve el aviso y la lista.
	var result := Rules.demolish(bridge)
	assert_bool(result.has("blocked")).is_true()
	assert_array(result["stranded"]).contains_exactly([saw])
	assert_object(GridManager.get_building_at(Vector2i(8, 10))).is_same(bridge)

func test_a_loop_lets_one_side_go() -> void:
	_core_with_ring()
	# Aserradero en x=6..7, y=10..11 con dos caminos a la acera: (8,10) y (8,11).
	var top := _put("road", Vector2i(8, 10))
	var bottom := _put("road", Vector2i(8, 11))
	_put("sawmill", Vector2i(6, 10))
	assert_array(Rules.road_removal_stranded(top)).is_empty()
	assert_array(Rules.road_removal_stranded(bottom)).is_empty()
	# Quitado uno, el otro ya es el unico puente.
	GridManager.remove_building(top)
	assert_int(Rules.road_removal_stranded(bottom).size()).is_equal(1)

func test_a_building_under_construction_counts() -> void:
	_core_with_ring()
	var bridge := _put("road", Vector2i(8, 10))
	var house := _put("house", Vector2i(6, 10))
	house.set_meta("under_construction", true)
	assert_array(Rules.road_removal_stranded(bridge)).contains_exactly([house])

func test_decorations_do_not_count() -> void:
	_core_with_ring()
	var bridge := _put("road", Vector2i(8, 10))
	_put("garden", Vector2i(6, 10))
	assert_array(Rules.road_removal_stranded(bridge)).is_empty()

func test_a_building_already_loose_does_not_block() -> void:
	_core_with_ring()
	_put("sawmill", Vector2i(2, 2))  # suelto desde una partida vieja
	var corner: Node = GridManager.get_building_at(Vector2i(13, 13))
	assert_array(Rules.road_removal_stranded(corner)).is_empty()

func test_moving_a_road_checks_its_new_spot() -> void:
	_core_with_ring()
	var spur := _put("road", Vector2i(8, 11))
	var house := _put("house", Vector2i(6, 11))  # x=6..7, y=11..12
	# A (8,12) sigue tocando la casa y la acera: vale.
	assert_array(Rules.road_removal_stranded(spur, [Vector2i(8, 12)])).is_empty()
	# Lejos ya no une nada: la casa se quedaria suelta.
	assert_array(Rules.road_removal_stranded(spur, [Vector2i(8, 14)])).contains_exactly([house])

# ── Los dos colocadores ───────────────────────────────────────────────

var _gm: Dictionary = {}

func _hold_game_manager() -> void:
	SaveParking.park(BACKUP_PATH)
	_gm = {"placer": GameManager._placer, "started": GameManager._started, "hold": GameManager._hold_start}
	GameManager._started = false
	GameManager.hold_start()

func _release_game_manager(placer: Node) -> void:
	for info in GridManager.get_all_buildings():
		ProductionManager.unregister(info["node"])
	placer.clear_all_buildings()
	remove_child(placer)
	placer.free()
	GameManager._placer = _gm["placer"] if is_instance_valid(_gm["placer"]) else null
	GameManager._started = _gm["started"]
	GameManager._hold_start = _gm["hold"]
	SaveParking.restore(BACKUP_PATH)

## Monta la misma escena con `placer` y prueba quitar el puente y una esquina.
func _check_placer(placer: Node) -> void:
	placer.name = "BuildingPlacer"
	add_child(placer)
	placer.place_building_at(_data("nucleo"), Vector2i(10, 10))
	for y in range(9, 14):
		for x in range(9, 14):
			if not (x >= 10 and x <= 12 and y >= 10 and y <= 12):
				placer.place_building_at(_data("road"), Vector2i(x, y))
	var bridge: Node = placer.place_building_at(_data("road"), Vector2i(8, 10))
	var saw: Node = placer.place_building_at(_data("sawmill"), Vector2i(6, 10))
	placer._on_demolish_requested(bridge)
	assert_object(GridManager.get_building_at(Vector2i(8, 10))).is_same(bridge)
	assert_array(placer.get_flash_nodes()).contains_exactly([saw])
	var corner: Node = GridManager.get_building_at(Vector2i(13, 13))
	placer._on_demolish_requested(corner)
	assert_object(GridManager.get_building_at(Vector2i(13, 13))).is_null()

func test_the_3d_placer_uses_the_rule() -> void:
	_hold_game_manager()
	var placer: Node = Placer3D.new()
	_check_placer(placer)
	_release_game_manager(placer)

func test_the_2d_placer_uses_the_rule() -> void:
	_hold_game_manager()
	var placer: Node = Placer2D.new()
	_check_placer(placer)
	_release_game_manager(placer)
