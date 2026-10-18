extends GdUnitTestSuite
## El Astillero se orienta solo al agua al colocarlo (aire y mar, 1.1).
##
## Su darsena esta en el lado de delante del edificio: +Z del modelo 3D y +y
## local del dibujo 2D. Al colocarlo, el fantasma se gira para que ese lado mire
## al agua mas cercana; si el jugador lo gira a mano, deja de girarse solo hasta
## el proximo edificio. Los dos colocadores guardan el giro con el convenio de
## la vista 3D; el dibujo 2D lo invierte (Building2D.view_steps()), asi que el
## mismo guardado mira al mismo lado del mundo en las dos vistas.
##
## La rejilla de siempre (reset_size), toda tierra: fuera de ella es mar, asi
## que una huella pegada a un borde tiene el agua a ese lado.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const Placer3D := preload("res://scripts/buildings/BuildingPlacer.gd")
const Placer2D := preload("res://scripts/view2d/BuildingPlacer2D.gd")
const SaveParking := preload("res://tests/save/save_parking.gd")
const BACKUP_PATH := "user://save_game.shipyard_faces_water.bak"
const SIZE := Vector2i(2, 2)

func before(do_skip := SaveParking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

func before_test() -> void:
	GridManager.clear_all()
	GridManager.reset_size()

func after_test() -> void:
	GridManager.clear_all()
	GridManager.reset_size()

func _bottom() -> Vector2i:
	return Vector2i(10, GridManager.grid_height - SIZE.y)

func _right() -> Vector2i:
	return Vector2i(GridManager.grid_width - SIZE.x, 10)

func _top() -> Vector2i:
	return Vector2i(10, 0)

func _left() -> Vector2i:
	return Vector2i(0, 10)

# ── La regla pura ─────────────────────────────────────────────────────

func test_the_water_side_is_the_edge_the_footprint_touches() -> void:
	assert_int(Rules.water_side(_top(), SIZE)).is_equal(0)
	assert_int(Rules.water_side(_right(), SIZE)).is_equal(1)
	assert_int(Rules.water_side(_bottom(), SIZE)).is_equal(2)
	assert_int(Rules.water_side(_left(), SIZE)).is_equal(3)

func test_far_from_water_there_is_no_side_and_no_turn() -> void:
	assert_int(Rules.water_side(Vector2i(18, 18), SIZE)).is_equal(-1)
	assert_int(Rules.steps_facing_water("shipyard", Vector2i(18, 18), SIZE, false)).is_equal(-1)

func test_water_a_few_cells_away_still_counts() -> void:
	# Dos celdas de tierra entre la huella y el borde de abajo.
	var origin := Vector2i(10, GridManager.grid_height - SIZE.y - 2)
	assert_int(Rules.water_side(origin, SIZE)).is_equal(2)

func test_the_nearest_water_wins_over_a_farther_one() -> void:
	# Pegado al borde de la derecha y a tres de abajo: gana la derecha.
	var origin := Vector2i(GridManager.grid_width - SIZE.x, GridManager.grid_height - SIZE.y - 3)
	assert_int(Rules.water_side(origin, SIZE)).is_equal(1)

func test_only_the_shipyard_turns_itself() -> void:
	assert_bool(Rules.faces_water("shipyard")).is_true()
	assert_int(Rules.steps_facing_water("house", _right(), SIZE, false)).is_equal(-1)

func test_the_steps_point_the_front_at_the_water_in_both_views() -> void:
	var dirs := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	for side in 4:
		# 3D: el delante es +Z; girar `steps` cuartos sobre +Y.
		var s3 := Rules.steps_to_face(side, false)
		var front3: Vector3 = Basis(Vector3.UP, s3 * PI * 0.5) * Vector3(0, 0, 1)
		assert_vector(Vector2(front3.x, front3.z)).is_equal_approx(dirs[side], Vector2(0.001, 0.001))
		# 2D: el delante es +y local; el giro de un Node2D.
		var s2 := Rules.steps_to_face(side, true)
		assert_vector(Vector2(0, 1).rotated(s2 * PI * 0.5)).is_equal_approx(dirs[side], Vector2(0.001, 0.001))

# ── Los dos colocadores ───────────────────────────────────────────────

var _gm: Dictionary = {}

func _hold() -> void:
	SaveParking.park(BACKUP_PATH)
	_gm = {"placer": GameManager._placer, "started": GameManager._started, "hold": GameManager._hold_start}
	GameManager._started = false
	GameManager.hold_start()

func _release(placer: Node) -> void:
	EventBus.building_placement_cancelled.emit()
	placer.clear_all_buildings()
	remove_child(placer)
	placer.free()
	GameManager._placer = _gm["placer"] if is_instance_valid(_gm["placer"]) else null
	GameManager._started = _gm["started"]
	GameManager._hold_start = _gm["hold"]
	SaveParking.restore(BACKUP_PATH)

func _shipyard() -> BuildingData:
	return load("res://data/buildings/shipyard.tres") as BuildingData

func test_the_3d_ghost_turns_to_the_water_until_the_player_turns_it() -> void:
	_hold()
	var placer: Node = Placer3D.new()
	placer.name = "BuildingPlacer"
	add_child(placer)
	EventBus.building_selected_for_placement.emit(_shipyard())
	placer._set_preview_cell(_right())
	assert_int(placer._rotation_steps).is_equal(Rules.steps_to_face(1, false))
	assert_float(placer._preview_node.rotation.y).is_equal_approx(placer._rotation_steps * PI * 0.5, 0.001)
	placer._set_preview_cell(_left())
	assert_int(placer._rotation_steps).is_equal(Rules.steps_to_face(3, false))
	# A mano manda el jugador: ya no se gira solo.
	EventBus.building_rotate_requested.emit()
	var chosen: int = placer._rotation_steps
	placer._set_preview_cell(_bottom())
	assert_int(placer._rotation_steps).is_equal(chosen)
	# El proximo Astillero vuelve a girarse solo.
	EventBus.building_selected_for_placement.emit(_shipyard())
	placer._set_preview_cell(_top())
	assert_int(placer._rotation_steps).is_equal(Rules.steps_to_face(0, false))
	_release(placer)

func test_the_2d_ghost_turns_to_the_water_until_the_player_turns_it() -> void:
	_hold()
	var placer: Node = Placer2D.new()
	placer.name = "BuildingPlacer"
	add_child(placer)
	EventBus.building_selected_for_placement.emit(_shipyard())
	placer.update_ghost(_right())
	assert_int(placer._rotation_steps).is_equal(Rules.steps_to_face(1, false))
	assert_int(int(placer.get_ghost().get_meta("rotation_steps", -1))).is_equal(placer._rotation_steps)
	# Y el dibujo 2D gira de modo que el delante (+y local) mira al agua (+x).
	var drawn: int = placer.get_ghost().view_steps()
	assert_vector(Vector2(0, 1).rotated(drawn * PI * 0.5)).is_equal_approx(Vector2(1, 0), Vector2(0.001, 0.001))
	EventBus.building_rotate_requested.emit()
	var chosen: int = placer._rotation_steps
	placer.update_ghost(_bottom())
	assert_int(placer._rotation_steps).is_equal(chosen)
	_release(placer)

func test_a_house_keeps_its_turn() -> void:
	_hold()
	var placer: Node = Placer2D.new()
	placer.name = "BuildingPlacer"
	add_child(placer)
	EventBus.building_selected_for_placement.emit(load("res://data/buildings/house.tres"))
	placer.update_ghost(_right())
	assert_int(placer._rotation_steps).is_equal(0)
	_release(placer)
