extends GdUnitTestSuite
## Carretera larga en los colocadores de 3D y 2D (feat/carretera-arrastrar).
##
## Raton: pulsar, arrastrar y soltar tiende el tramo; un clic sin arrastrar sigue
## poniendo un solo tramo; R cambia el codo. Dedo: tocar el inicio, tocar el
## final (vista previa) y tocarlo otra vez (o ✓) lo tiende; el final es el inicio
## del siguiente. Sin oro para todo se ponen los que se pueden pagar, desde la red.
##
## El movimiento del raton con el boton pulsado se da con
## PlacementAssist.mouse_line_move (lo que el colocador hace en _process con el
## cursor): en headless no hay cursor que mover.
##
## Toca GridManager, ResourceManager, TutorialManager y GameManager reales: cada
## caso los deja como estaban.

const Placer3D := preload("res://scripts/buildings/BuildingPlacer.gd")
const Placer2D := preload("res://scripts/view2d/BuildingPlacer2D.gd")
const MapGen3D := preload("res://scripts/map/MapGenerator.gd")
const MapGen2D := preload("res://scripts/view2d/MapGenerator2D.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const SaveParking := preload("res://tests/save/save_parking.gd")
const BACKUP_PATH := "user://save_game.road_line.bak"
const ROAD := preload("res://data/buildings/road.tres")

func before(do_skip := SaveParking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

var _placer: Node = null
var _map: Node = null
var _cam: Node = null
var _gm: Dictionary = {}
var _resources: Dictionary = {}
var _touch_mode := "auto"
var _tutorial: Dictionary = {}

func before_test() -> void:
	SaveParking.park(BACKUP_PATH)
	_gm = {"placer": GameManager._placer, "map": GameManager._map_gen, "camera": GameManager._camera,
		"started": GameManager._started, "hold": GameManager._hold_start}
	_resources = ResourceManager.get_all().duplicate()
	_touch_mode = GameConfig.ui_touch_controls
	_tutorial = TutorialManager.get_save_data()
	# La ayuda de la carretera larga ya vista: que no salga en medio de las pruebas.
	if not TutorialManager.tips_seen.has("road_drag"):
		TutorialManager.tips_seen.append("road_drag")
	GridManager.clear_all()
	GridManager.reset_size()
	GameManager._started = false
	GameManager.hold_start()
	InputService._purge_touch_state()
	ResourceManager.set_amounts({"gold": 500, "wood": 0, "steel": 0, "oil": 0})

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
	if is_instance_valid(_cam):
		_cam.queue_free()
	GridManager.clear_all()
	InputService._purge_touch_state()
	GameConfig.ui_touch_controls = _touch_mode
	TutorialManager.load_save_data(_tutorial)
	var by_name := {}
	for type in _resources:
		by_name[ResourceManager.get_type_name(type)] = _resources[type]
	ResourceManager.set_amounts(by_name)
	GameManager._placer = _alive(_gm["placer"])
	GameManager._map_gen = _alive(_gm["map"])
	GameManager._camera = _alive(_gm["camera"])
	GameManager._started = _gm["started"]
	GameManager._hold_start = _gm["hold"]
	SaveParking.restore(BACKUP_PATH)

func _alive(v: Variant) -> Node:
	return v if is_instance_valid(v) else null

## Monta la vista con el Nucleo en (10,10) y su acera (de (9,9) a (13,13)).
func _setup(view: String, touch: bool) -> void:
	GameConfig.ui_touch_controls = "always" if touch else "never"
	if view == "3d":
		var cam := Camera3D.new()
		add_child(cam)
		cam.position = Vector3(0, 60, 0.01)
		cam.look_at(Vector3.ZERO, Vector3.UP)
		cam.current = true
		_cam = cam
		_map = MapGen3D.new()
		_placer = Placer3D.new()
	else:
		_map = MapGen2D.new()
		_placer = Placer2D.new()
	_map.name = "MapGenerator"
	add_child(_map)
	_placer.name = "BuildingPlacer"
	add_child(_placer)
	_placer.place_building_at(load("res://data/buildings/nucleo.tres"), Vector2i(10, 10))
	for y in range(9, 14):
		for x in range(9, 14):
			if x < 10 or x > 12 or y < 10 or y > 12:
				_placer.place_building_at(ROAD, Vector2i(x, y))
	EventBus.building_selected_for_placement.emit(ROAD)

func _assist() -> Node:
	return _placer.get_assist()

func _roads() -> int:
	return Rules.count_building("road")

func _gold() -> int:
	return ResourceManager.get_amount(ResourceManager.Type.GOLD)

func _screen(c: Vector2i) -> Vector2:
	return _placer.assist_cell_to_screen(c, Vector2i.ONE)

func _mouse(c: Vector2i, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _screen(c)
	_placer._unhandled_input(ev)

## Pulsar en `from`, llevar el cursor por `path` y soltar en el ultimo.
func _mouse_drag(from: Vector2i, path: Array) -> void:
	_mouse(from, true)
	for c in path:
		_assist().mouse_line_move(c)
	_mouse(path[-1], false)

func _send(ev: InputEvent) -> void:
	if not _assist().handle_touch(ev):
		InputService._unhandled_input(ev)

func _tap(c: Vector2i) -> void:
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = _screen(c)
		ev.pressed = pressed
		_send(ev)

# ── Raton ─────────────────────────────────────────────────────────────

func _check_mouse_drag_lays_the_whole_line(view: String) -> void:
	_setup(view, false)
	var before := _roads()
	var gold := _gold()
	# De la acera (13,11) a (20,11), pasando por las celdas de en medio.
	_mouse_drag(Vector2i(13, 11), [Vector2i(15, 11), Vector2i(18, 11), Vector2i(20, 11)])
	assert_int(_roads() - before).is_equal(7)
	assert_int(gold - _gold()).is_equal(7)
	for x in range(14, 21):
		assert_bool(Rules.is_road_at(Vector2i(x, 11))).is_true()
	# Se sigue con la carretera en la mano, sin tramo pendiente.
	assert_bool(_placer.is_idle()).is_false()
	assert_bool(_assist().line_active()).is_false()

func test_3d_dragging_the_mouse_lays_a_long_road() -> void:
	_check_mouse_drag_lays_the_whole_line("3d")

func test_2d_dragging_the_mouse_lays_a_long_road() -> void:
	_check_mouse_drag_lays_the_whole_line("2d")

func _check_click_without_drag(view: String) -> void:
	_setup(view, false)
	var before := _roads()
	_mouse(Vector2i(14, 11), true)
	# Al pulsar aun no se pone nada: puede ser el principio de un arrastre.
	assert_int(_roads()).is_equal(before)
	_mouse(Vector2i(14, 11), false)
	assert_int(_roads() - before).is_equal(1)
	assert_bool(Rules.is_road_at(Vector2i(14, 11))).is_true()

func test_3d_a_click_without_dragging_still_lays_one_tile() -> void:
	_check_click_without_drag("3d")

func test_2d_a_click_without_dragging_still_lays_one_tile() -> void:
	_check_click_without_drag("2d")

func test_the_preview_shows_green_tiles_and_the_cost() -> void:
	_setup("2d", false)
	_mouse(Vector2i(13, 11), true)
	_assist().mouse_line_move(Vector2i(17, 13))
	var cells: Array = _placer.get_line_cells()
	assert_int((cells[0] as Array).size()).is_equal(6)
	assert_array(cells[1]).is_empty()
	assert_bool(_placer.get_line_preview().visible).is_true()
	assert_bool(_placer.get_ghost().visible).is_false()
	var label: Label = _assist().line_label()
	assert_bool(label.visible).is_true()
	assert_str(label.text).is_equal(Tr.t("LBL_ROAD_LINE_COST") % [6, 6])
	# R (o ↻) cambia el codo: mismo numero de tramos, otra esquina.
	var corner_before: bool = (_assist().line_plan["cells"] as Array).has(Vector2i(17, 11))
	EventBus.building_rotate_requested.emit()
	var corner_after: bool = (_assist().line_plan["cells"] as Array).has(Vector2i(17, 11))
	assert_bool(corner_before).is_not_equal(corner_after)
	_mouse(Vector2i(17, 13), false)
	assert_bool(label.visible).is_false()
	assert_bool(_placer.get_ghost().visible).is_true()

func test_3d_the_preview_is_drawn_and_the_ghost_hidden() -> void:
	_setup("3d", false)
	_mouse(Vector2i(13, 11), true)
	_assist().mouse_line_move(Vector2i(19, 11))
	var mm: MultiMeshInstance3D = _placer.get_line_preview()
	assert_object(mm).is_not_null()
	assert_bool(mm.visible).is_true()
	assert_int(mm.multimesh.instance_count).is_equal(6)
	EventBus.building_placement_cancelled.emit()
	assert_bool(mm.visible).is_false()

func test_existing_road_is_skipped_and_not_charged() -> void:
	_setup("2d", false)
	var gold := _gold()
	var before := _roads()
	# De (5,9) a (16,9) cruzando la acera de arriba (x 9..13 ya son carretera).
	_mouse_drag(Vector2i(5, 9), [Vector2i(16, 9)])
	assert_int(_roads() - before).is_equal(12 - 5)
	assert_int(gold - _gold()).is_equal(7)

func _check_partial_gold(view: String) -> void:
	_setup(view, false)
	ResourceManager.set_amounts({"gold": 3, "wood": 0, "steel": 0, "oil": 0})
	var before := _roads()
	# Se dibuja desde fuera hacia la red: aun asi lo que se pone es lo pegado a ella.
	_mouse_drag(Vector2i(20, 11), [Vector2i(14, 11)])
	assert_int(_roads() - before).is_equal(3)
	assert_int(_gold()).is_equal(0)
	for x in [14, 15, 16]:
		assert_bool(Rules.is_road_at(Vector2i(x, 11))).is_true()
	assert_bool(Rules.is_road_at(Vector2i(17, 11))).is_false()
	# Y todo lo puesto queda unido a la red.
	assert_bool(Rules.network_view().has(Vector2i(16, 11))).is_true()

func test_3d_without_enough_gold_it_lays_what_it_can_from_the_network() -> void:
	_check_partial_gold("3d")

func test_2d_without_enough_gold_it_lays_what_it_can_from_the_network() -> void:
	_check_partial_gold("2d")

func test_with_no_gold_nothing_is_laid() -> void:
	_setup("2d", false)
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 0})
	var before := _roads()
	_mouse_drag(Vector2i(13, 11), [Vector2i(20, 11)])
	assert_int(_roads()).is_equal(before)

func test_a_line_away_from_the_network_lays_nothing() -> void:
	_setup("2d", false)
	var before := _roads()
	var gold := _gold()
	_mouse_drag(Vector2i(20, 3), [Vector2i(26, 3)])
	assert_int(_roads()).is_equal(before)
	assert_int(_gold()).is_equal(gold)

# ── Dedo ──────────────────────────────────────────────────────────────

func _check_touch_start_then_end(view: String) -> void:
	_setup(view, true)
	var before := _roads()
	# Primer toque: el inicio (el fantasma va ahi; no se pone nada).
	_tap(Vector2i(14, 11))
	assert_int(_roads()).is_equal(before)
	# Segundo toque en otra casilla: vista previa del tramo, sin cobrar.
	_tap(Vector2i(20, 11))
	assert_int(_roads()).is_equal(before)
	assert_bool(_assist().line_active()).is_true()
	assert_bool(_assist().confirm_button().visible).is_true()
	# Tocar el final otra vez lo tiende: 14..20 = 7 tramos.
	_tap(Vector2i(20, 11))
	assert_int(_roads() - before).is_equal(7)
	assert_bool(_assist().line_active()).is_false()
	# El final es el inicio del siguiente: tocar mas abajo y confirmar con ✓.
	_tap(Vector2i(20, 15))
	assert_bool(_assist().line_active()).is_true()
	_assist().confirm_button().pressed.emit()
	assert_int(_roads() - before).is_equal(7 + 4)

func test_3d_touch_start_then_end_lays_a_long_road() -> void:
	_check_touch_start_then_end("3d")

func test_2d_touch_start_then_end_lays_a_long_road() -> void:
	_check_touch_start_then_end("2d")

func test_touch_one_tile_at_a_time_still_works() -> void:
	# Lo de siempre en serie: tocar la casilla y luego el fantasma.
	_setup("2d", true)
	var before := _roads()
	_tap(Vector2i(14, 11))
	_tap(Vector2i(14, 11))
	assert_int(_roads() - before).is_equal(1)
	# La siguiente pegada: tocarla dibuja un tramo de 1 y tocarla otra vez lo pone.
	_tap(Vector2i(15, 11))
	_tap(Vector2i(15, 11))
	assert_int(_roads() - before).is_equal(2)

func test_touch_tapping_the_start_drops_the_line() -> void:
	_setup("2d", true)
	_tap(Vector2i(14, 11))
	_tap(Vector2i(20, 11))
	assert_bool(_assist().line_active()).is_true()
	_tap(Vector2i(14, 11))
	assert_bool(_assist().line_active()).is_false()
	assert_bool(_placer.get_ghost().visible).is_true()

# ── Tutorial ──────────────────────────────────────────────────────────

func test_the_practice_road_step_counts_a_long_road() -> void:
	_setup("2d", false)
	# En el paso de practicar carretera de la guia, con la carretera en la mano.
	TutorialManager.guide_state = TutorialManager.GUIDE_ACTIVE
	TutorialManager._step = "road_place"
	TutorialManager._placing_id = "road"
	_mouse_drag(Vector2i(13, 11), [Vector2i(17, 11)])
	# El tramo de practicar es el primero que se tendio (el pegado a la acera).
	assert_bool(TutorialManager.practice_road_cell == Vector2i(14, 11)).is_true()
