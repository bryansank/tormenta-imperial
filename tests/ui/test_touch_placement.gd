extends GdUnitTestSuite
## Construir con el dedo, en 3D y en 2D (bug 10, PlacementAssist).
##
## En tablet no se podia plantar el aserradero: el fantasma seguia al raton
## emulado (que se queda donde fue el ultimo toque), un temblor de 12 px fisicos
## convertia el toque en arrastre y la regla del bosque no se veia hasta fallar.
## Ahora: tocar lleva el fantasma bajo el dedo, tocar el fantasma (o ✓) planta,
## las casillas junto al bosque salen en verde y un toque lejos dice por que no.
##
## Los eventos van a PlacementAssist.handle_touch y, si no son suyos, a
## InputService, en el orden del motor (la escena antes que los autoloads).
## Toca GridManager, ResourceManager, PopulationManager y GameManager reales:
## cada caso los deja como estaban.

const Placer3D := preload("res://scripts/buildings/BuildingPlacer.gd")
const Placer2D := preload("res://scripts/view2d/BuildingPlacer2D.gd")
const MapGen3D := preload("res://scripts/map/MapGenerator.gd")
const MapGen2D := preload("res://scripts/view2d/MapGenerator2D.gd")
const Assist := preload("res://scripts/buildings/PlacementAssist.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const SaveParking := preload("res://tests/save/save_parking.gd")
const BACKUP_PATH := "user://save_game.touch_placement.bak"
const FOREST := Vector2i(20, 20)

func before(do_skip := SaveParking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

var _placer: Node = null
var _map: Node = null
var _cam: Node = null
var _gm: Dictionary = {}
var _resources: Dictionary = {}
var _pop: Array = []
var _touch_mode := "auto"
var _notes: Array = []
var _warehouses := 0

func before_test() -> void:
	SaveParking.park(BACKUP_PATH)
	_gm = {"placer": GameManager._placer, "map": GameManager._map_gen, "camera": GameManager._camera,
		"started": GameManager._started, "hold": GameManager._hold_start}
	_resources = ResourceManager.get_all().duplicate()
	_pop = [PopulationManager._population, PopulationManager._used_workers]
	_touch_mode = GameConfig.ui_touch_controls
	# Un dispositivo tactil: el fantasma lo apunta el dedo desde el principio.
	GameConfig.ui_touch_controls = "always"
	GridManager.clear_all()
	GameManager._started = false
	GameManager.hold_start()
	InputService._purge_touch_state()
	_notes = []
	EventBus.notification_posted.connect(_on_note)
	# Cantidades fijas: otra suite puede haber dejado la bolsa llena o vacia.
	_warehouses = ResourceManager.get_warehouse_count()
	ResourceManager.set_warehouse_count(5)
	ResourceManager.set_amounts({"gold": 600, "wood": 400, "steel": 0, "oil": 0})
	PopulationManager._population = 12
	PopulationManager._used_workers = 0

func after_test() -> void:
	EventBus.notification_posted.disconnect(_on_note)
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
	PopulationManager._population = _pop[0]
	PopulationManager._used_workers = _pop[1]
	var by_name := {}
	for type in _resources:
		by_name[ResourceManager.get_type_name(type)] = _resources[type]
	ResourceManager.set_warehouse_count(_warehouses)
	ResourceManager.set_amounts(by_name)
	GameManager._placer = _alive(_gm["placer"])
	GameManager._map_gen = _alive(_gm["map"])
	GameManager._camera = _alive(_gm["camera"])
	GameManager._started = _gm["started"]
	GameManager._hold_start = _gm["hold"]
	SaveParking.restore(BACKUP_PATH)

func _alive(v: Variant) -> Node:
	return v if is_instance_valid(v) else null

func _on_note(msg, _t = "", _c = null) -> void:
	_notes.append(str(msg))

func _setup(view: String) -> void:
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
	_map.spawn_deposit("forest", FOREST, -1, Vector2i(2, 2))

func _assist() -> Node:
	return _placer.get_assist()

func _sawmills() -> int:
	return Rules.count_building("sawmill")

func _start() -> void:
	EventBus.building_selected_for_placement.emit(load("res://data/buildings/sawmill.tres"))

## Un evento como lo reparte el motor: primero la escena; si no era suyo, InputService.
func _send(ev: InputEvent) -> void:
	if not _assist().handle_touch(ev):
		InputService._unhandled_input(ev)

func _touch(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = pressed
	_send(ev)

func _drag(from: Vector2, to: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = to
	ev.relative = to - from
	_send(ev)

## Un toque con `tremor` px de temblor entre apoyar y levantar.
func _tap(pos: Vector2, tremor := Vector2.ZERO) -> void:
	_touch(pos, true)
	if tremor != Vector2.ZERO:
		_drag(pos, pos + tremor)
	_touch(pos + tremor, false)

## Punto de pantalla en el centro de la casilla `c`.
func _screen(c: Vector2i) -> Vector2:
	return _placer.assist_cell_to_screen(c, Vector2i.ONE)

## Un origen valido que no se solape con el del fantasma de ahora.
func _other_spot() -> Vector2i:
	var ghost: Vector2i = _assist().cell
	for o in _assist().spots:
		var s: Vector2i = o
		if absi(s.x - ghost.x) > 2 or absi(s.y - ghost.y) > 1:
			return s
	return _assist().spots[0]

# ── La regla se ve antes de colocar ───────────────────────────────────

func _check_highlight(view: String) -> void:
	_setup(view)
	_start()
	var spots: Array = _assist().spots
	assert_array(spots).is_not_empty()
	for o in spots:
		assert_bool(Rules.evaluate_placement("sawmill", o, Vector2i(2, 1), _map)["ok"]).is_true()
	# El fantasma sale ya en un sitio valido, verde, con ✓ a mano.
	assert_bool(_assist().is_valid(_assist().cell)).is_true()
	assert_bool(_assist().confirm_button().visible).is_true()
	var hl = _placer.get_spot_highlight()
	assert_object(hl).is_not_null()
	assert_bool(hl.visible).is_true()
	EventBus.building_placement_cancelled.emit()
	assert_bool(hl.visible).is_false()

func test_3d_the_valid_cells_are_highlighted_when_placing_starts() -> void:
	_check_highlight("3d")

func test_2d_the_valid_cells_are_highlighted_when_placing_starts() -> void:
	_check_highlight("2d")

func test_a_building_without_a_deposit_rule_has_no_highlight() -> void:
	_setup("2d")
	EventBus.building_selected_for_placement.emit(load("res://data/buildings/house.tres"))
	assert_array(_assist().spots).is_empty()

# ── Tocar para apuntar, tocar el fantasma para plantar ────────────────

func _check_tap_then_confirm(view: String) -> void:
	_setup(view)
	_start()
	var target := _other_spot()
	var p := _screen(target)
	_tap(p)
	# El primer toque solo lleva el fantasma: no se cobra ni se planta nada.
	assert_int(_sawmills()).is_equal(0)
	assert_bool(_assist().is_valid(_assist().cell)).is_true()
	var cells: Array = GridManager.cells_for(_assist().cell, Vector2i(2, 1))
	assert_bool(cells.has(target)).is_true()
	# Tocar el fantasma lo planta.
	var gold := ResourceManager.get_amount(ResourceManager.Type.GOLD)
	var why := "block='%s' ghost=%s target=%s p=%s cell_at_p=%s valid=%s" % [
		Rules.purchase_block_message(load("res://data/buildings/sawmill.tres")), _assist().cell, target, p,
		_placer.assist_screen_to_cell(p), _assist().is_valid(_assist().cell)]
	_tap(p)
	assert_int(_sawmills()).override_failure_message(why).is_equal(1)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(gold - 80)

func test_3d_tap_aims_and_a_tap_on_the_ghost_builds_the_sawmill() -> void:
	_check_tap_then_confirm("3d")

func test_2d_tap_aims_and_a_tap_on_the_ghost_builds_the_sawmill() -> void:
	_check_tap_then_confirm("2d")

func test_the_confirm_button_builds_too() -> void:
	_setup("2d")
	_start()
	var btn: Button = _assist().confirm_button()
	assert_str(btn.text).contains(Tr.t("BTN_PLACE_HERE"))
	btn.pressed.emit()
	assert_int(_sawmills()).is_equal(1)

func _check_tremor(view: String) -> void:
	_setup(view)
	_start()
	var slop: float = InputService.touch_slop_px()
	var shake := Vector2(slop * 0.6, slop * 0.3)
	var target := _other_spot()
	_tap(_screen(target), shake)
	assert_bool(InputService.touch_pan_consumed_click()).is_false()
	assert_bool(GridManager.cells_for(_assist().cell, Vector2i(2, 1)).has(target)).is_true()
	# Y el toque tembloroso sobre el fantasma sigue plantando.
	_tap(_screen(target), shake)
	assert_int(_sawmills()).is_equal(1)

func test_3d_a_tremor_under_the_threshold_still_places() -> void:
	_check_tremor("3d")

func test_2d_a_tremor_under_the_threshold_still_places() -> void:
	_check_tremor("2d")

func _check_far_tap(view: String) -> void:
	_setup(view)
	_start()
	_tap(_screen(Vector2i(4, 4)))
	assert_int(_sawmills()).is_equal(0)
	# Se dice por que, en el acto, y ✓ no se ofrece sobre un sitio rojo.
	assert_array(_notes).contains([Tr.t("LBL_NEEDS_FOREST_NEAR")])
	assert_bool(_assist().confirm_button().visible).is_false()
	# Tocar el fantasma rojo tampoco planta nada.
	_tap(_screen(Vector2i(4, 4)))
	assert_int(_sawmills()).is_equal(0)

func test_3d_a_far_tap_says_why() -> void:
	_check_far_tap("3d")

func test_2d_a_far_tap_says_why() -> void:
	_check_far_tap("2d")

# ── Arrastrar: el fantasma si se agarra, el mapa si no ────────────────

func test_dragging_the_ghost_moves_it_and_does_not_pan() -> void:
	_setup("2d")
	_start()
	var pans: Array = []
	var listener := func(d: Vector2): pans.append(d)
	EventBus.camera_drag_world_requested.connect(listener)
	var start_cell: Vector2i = _assist().cell
	var from := _screen(start_cell)
	var to := _screen(start_cell + Vector2i(0, 3))
	_touch(from, true)
	_drag(from, from.lerp(to, 0.5))
	_drag(from.lerp(to, 0.5), to)
	_touch(to, false)
	EventBus.camera_drag_world_requested.disconnect(listener)
	assert_array(pans).is_empty()
	assert_vector(Vector2(_assist().cell)).is_equal(Vector2(start_cell + Vector2i(0, 3)))
	# Soltarlo no planta: se planta con un toque o con ✓.
	assert_int(_sawmills()).is_equal(0)

func test_dragging_elsewhere_pans_the_map_and_leaves_the_ghost() -> void:
	_setup("2d")
	_start()
	var pans: Array = []
	var listener := func(d: Vector2): pans.append(d)
	EventBus.camera_drag_world_requested.connect(listener)
	var ghost: Vector2i = _assist().cell
	var from := _screen(Vector2i(4, 4))
	var to := from + Vector2(120, 0)
	_touch(from, true)
	_drag(from, to)
	_touch(to, false)
	EventBus.camera_drag_world_requested.disconnect(listener)
	assert_array(pans).is_not_empty()
	assert_vector(Vector2(_assist().cell)).is_equal(Vector2(ghost))
	assert_int(_sawmills()).is_equal(0)

func test_a_tap_releases_the_finger_in_input_service() -> void:
	# Si el colocador se quedara el soltar, InputService no olvidaria el dedo y
	# el toque siguiente seria un "segundo dedo" (pellizco en vez de paneo).
	_setup("2d")
	_start()
	_tap(_screen(Vector2i(4, 4)))
	assert_bool(InputService.is_touch_gesture_active()).is_false()

func test_the_emulated_mouse_click_does_not_place_while_touch_aiming() -> void:
	_setup("2d")
	_start()
	var p := _screen(_assist().cell)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.device = InputEvent.DEVICE_ID_EMULATION
	press.position = p
	press.pressed = true
	_placer._handle_left_button(press)
	var rel := press.duplicate()
	rel.pressed = false
	_placer._handle_left_button(rel)
	assert_int(_sawmills()).is_equal(0)

# ── Ficha del menu ────────────────────────────────────────────────────

func test_the_rule_text_names_the_deposit() -> void:
	assert_str(Assist.rule_text("sawmill")).is_equal(Tr.t("LBL_RULE_FOREST"))
	assert_str(Assist.rule_text("gold_mine")).is_equal(Tr.t("LBL_RULE_GOLD_VEIN"))
	assert_str(Assist.rule_text("foundry")).is_equal(Tr.t("LBL_RULE_IRON_DEPOSIT"))
	assert_str(Assist.rule_text("refinery")).is_equal(Tr.t("LBL_RULE_OIL_WELL"))
	assert_str(Assist.rule_text("house")).is_equal("")
	for id in GameConfig.building_deposit_rules:
		var key := "LBL_RULE_" + String(GameConfig.building_deposit_rules[id]["deposit"]).to_upper()
		for locale in ["es", "en"]:
			assert_bool(Tr._STRINGS[locale].has(key)).override_failure_message("%s en %s" % [key, locale]).is_true()

func test_placing_closes_the_sidebar() -> void:
	_setup("2d")
	var seen: Array = []
	var listener := func(v: bool): seen.append(v)
	EventBus.sidebar_toggled.emit(true)
	EventBus.sidebar_toggled.connect(listener)
	_start()
	EventBus.sidebar_toggled.disconnect(listener)
	assert_array(seen).is_equal([false])
