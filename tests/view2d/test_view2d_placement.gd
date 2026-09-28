extends GdUnitTestSuite
## Colocar en la vista 2D (docs/18-vista-2d.md): BuildingPlacer2D con las reglas
## compartidas de PlacementRules. Huella, giro, celdas ocupadas, fuera de la
## rejilla, regla de yacimiento en el fantasma, compra real, mover, demoler y el
## formato de guardado.
##
## Toca GridManager, ResourceManager y GameManager reales: cada caso los deja
## como estaban. GameManager se retiene (hold_start) para que registrar el
## colocador no arranque ni guarde una partida; el guardado del jugador se aparta
## igualmente por si alguna senal llegara a escribirlo.

const Placer2D := preload("res://scripts/view2d/BuildingPlacer2D.gd")
const MapGen2D := preload("res://scripts/view2d/MapGenerator2D.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")

const SAVE_PATH := "user://save_game.json"
## Aparca la partida del jugador sin perder nunca una copia varada.
const SaveParking := preload("res://tests/save/save_parking.gd")
const BACKUP_PATH := "user://save_game.view2d_placement.bak"

## Esta suite escribe user://save_game.json. Si corre en la carpeta del jugador
## (lanzada sin tools/run_tests.sh) se salta entera: no hay partida que pisar.
func before(do_skip := SaveParking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

var _placer: Node2D = null
var _map: Node = null
var _gm: Dictionary = {}
var _resources: Dictionary = {}
var _warehouses := 0

func before_test() -> void:
	SaveParking.park(BACKUP_PATH)
	_gm = {"placer": GameManager._placer, "map": GameManager._map_gen, "camera": GameManager._camera,
		"started": GameManager._started, "hold": GameManager._hold_start}
	_resources = ResourceManager.get_all().duplicate()
	_warehouses = ResourceManager.get_warehouse_count()
	GridManager.clear_all()
	GameManager._started = false
	GameManager.hold_start()
	_map = MapGen2D.new()
	_map.name = "MapGenerator"
	add_child(_map)
	_placer = Placer2D.new()
	_placer.name = "BuildingPlacer"
	add_child(_placer)

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
	ResourceManager.set_warehouse_count(_warehouses)
	ResourceManager.set_amounts(by_name)
	# Lo que dejo otro test puede estar ya liberado: se devuelve solo lo vivo.
	GameManager._placer = _alive(_gm["placer"])
	GameManager._map_gen = _alive(_gm["map"])
	GameManager._camera = _alive(_gm["camera"])
	GameManager._started = _gm["started"]
	GameManager._hold_start = _gm["hold"]
	SaveParking.restore(BACKUP_PATH)

func _alive(v: Variant) -> Node:
	return v if is_instance_valid(v) else null

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id) as BuildingData

func _rich() -> void:
	ResourceManager.set_warehouse_count(5)
	for type in [ResourceManager.Type.GOLD, ResourceManager.Type.WOOD, ResourceManager.Type.STEEL, ResourceManager.Type.OIL]:
		ResourceManager.add(type, 600)

# ── Huella y posicion ─────────────────────────────────────────────────

func test_a_house_occupies_its_cell_and_sits_on_its_centre() -> void:
	var node: Node2D = _placer.place_building_at(_data("house"), Vector2i(5, 7))
	assert_object(node).is_not_null()
	assert_object(GridManager.get_building_at(Vector2i(5, 7))).is_same(node)
	assert_object(GridManager.get_building_at(Vector2i(6, 7))).is_null()
	assert_vector(node.position).is_equal(View2D.footprint_center_px(Vector2i(5, 7), Vector2i(1, 1)))

func test_a_multi_cell_building_covers_its_whole_footprint() -> void:
	var node: Node2D = _placer.place_building_at(_data("gold_mine"), Vector2i(10, 10))
	for cell in GridManager.cells_for(Vector2i(10, 10), Vector2i(2, 2)):
		assert_object(GridManager.get_building_at(cell)).is_same(node)
	assert_vector(node.call("footprint_px")).is_equal(Vector2(2, 2) * View2D.cell_px())

func test_rotation_swaps_the_footprint() -> void:
	# Aserradero 2x1 girado 90 grados: ocupa 1x2 (hacia abajo, no a la derecha).
	var node: Node2D = _placer.place_building_at(_data("sawmill"), Vector2i(8, 8), 1)
	assert_object(GridManager.get_building_at(Vector2i(8, 9))).is_same(node)
	assert_object(GridManager.get_building_at(Vector2i(9, 8))).is_null()
	assert_int(int(node.get_meta("rotation_steps"))).is_equal(1)
	assert_vector(node.call("footprint_px")).is_equal(Vector2(1, 2) * View2D.cell_px())
	assert_vector(node.position).is_equal(View2D.footprint_center_px(Vector2i(8, 8), Vector2i(1, 2)))

func test_placing_on_an_occupied_cell_is_refused() -> void:
	assert_object(_placer.place_building_at(_data("house"), Vector2i(3, 3))).is_not_null()
	assert_object(_placer.place_building_at(_data("house"), Vector2i(3, 3))).is_null()
	# Un 2x2 que solo pisa una celda ocupada tambien se rechaza.
	assert_object(_placer.place_building_at(_data("gold_mine"), Vector2i(2, 2))).is_null()

# ── Fantasma: el mismo veredicto que el clic ──────────────────────────

func test_the_ghost_is_green_on_free_ground_and_red_on_a_building() -> void:
	_placer.place_building_at(_data("house"), Vector2i(12, 12))
	EventBus.building_selected_for_placement.emit(_data("house"))
	var ghost: Node2D = _placer.get_ghost()
	assert_object(ghost).is_not_null()
	_placer.update_ghost(Vector2i(14, 12))
	assert_bool(bool(ghost.get("ghost_valid"))).is_true()
	_placer.update_ghost(Vector2i(12, 12))
	assert_bool(bool(ghost.get("ghost_valid"))).is_false()

func test_the_ghost_is_red_outside_the_grid() -> void:
	EventBus.building_selected_for_placement.emit(_data("house"))
	_placer.update_ghost(Vector2i(-1, 5))
	assert_bool(bool(_placer.get_ghost().get("ghost_valid"))).is_false()
	_placer.update_ghost(Vector2i(GridManager.grid_width, 5))
	assert_bool(bool(_placer.get_ghost().get("ghost_valid"))).is_false()

func test_the_ghost_obeys_the_deposit_rule() -> void:
	# Aserradero 2x1: rojo lejos del bosque, verde pegado a el.
	_map.spawn_deposit("forest", Vector2i(20, 20), -1, Vector2i(2, 2))
	EventBus.building_selected_for_placement.emit(_data("sawmill"))
	_placer.update_ghost(Vector2i(5, 30))
	assert_bool(bool(_placer.get_ghost().get("ghost_valid"))).is_false()
	_placer.update_ghost(Vector2i(22, 20))
	assert_bool(bool(_placer.get_ghost().get("ghost_valid"))).is_true()

func test_rotating_while_placing_changes_the_verdict_footprint() -> void:
	# Hueco de 1 de ancho entre dos casas: el aserradero 2x1 no cabe tumbado,
	# si cabe de pie (girado).
	_map.spawn_deposit("forest", Vector2i(30, 10), -1, Vector2i(2, 2))
	_placer.place_building_at(_data("house"), Vector2i(29, 12))
	_placer.place_building_at(_data("house"), Vector2i(31, 12))
	EventBus.building_selected_for_placement.emit(_data("sawmill"))
	_placer.update_ghost(Vector2i(30, 12))
	assert_bool(bool(_placer.get_ghost().get("ghost_valid"))).is_false()
	EventBus.building_rotate_requested.emit()
	_placer.update_ghost(Vector2i(30, 12))
	assert_bool(bool(_placer.get_ghost().get("ghost_valid"))).is_true()

# ── Compra real ───────────────────────────────────────────────────────

func test_a_click_on_free_ground_buys_and_places_the_building() -> void:
	_rich()
	var gold_before := ResourceManager.get_amount(ResourceManager.Type.GOLD)
	EventBus.building_selected_for_placement.emit(_data("house"))
	var node: Node = _placer.try_place(Vector2i(6, 6))
	assert_object(node).is_not_null()
	assert_object(GridManager.get_building_at(Vector2i(6, 6))).is_same(node)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(gold_before - _data("house").cost_gold)
	# Una casa se coloca de una en una: tras colocarla se sale del modo.
	assert_bool(_placer.is_idle()).is_true()

## Las decoraciones (y los caminos) si se ponen en serie.
func test_a_decoration_keeps_the_next_one_in_hand() -> void:
	_rich()
	EventBus.building_selected_for_placement.emit(_data("garden"))
	assert_object(_placer.try_place(Vector2i(6, 6))).is_not_null()
	assert_bool(_placer.is_idle()).is_false()
	assert_object(_placer.try_place(Vector2i(8, 6))).is_not_null()

func test_only_series_buildings_keep_placing() -> void:
	assert_bool(Rules.keeps_placing(_data("garden"))).is_true()
	assert_bool(Rules.keeps_placing(_data("road"))).is_true()
	assert_bool(Rules.keeps_placing(_data("house"))).is_false()
	assert_bool(Rules.keeps_placing(_data("sawmill"))).is_false()

## Sin recursos, el aviso dice cuanto falta, no solo "insuficientes".
func test_the_block_message_names_what_is_missing() -> void:
	var saved := {
		"gold": ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"wood": ResourceManager.get_amount(ResourceManager.Type.WOOD),
	}
	ResourceManager.set_amounts({"gold": 0, "wood": 0})
	var msg := Rules.purchase_block_detail(_data("house"))
	ResourceManager.set_amounts(saved)
	assert_str(msg).contains(str(_data("house").cost_gold))
	assert_str(msg).contains(Tr.res_name("wood"))

func test_a_click_on_an_occupied_cell_does_not_charge() -> void:
	_rich()
	_placer.place_building_at(_data("house"), Vector2i(6, 6))
	var gold_before := ResourceManager.get_amount(ResourceManager.Type.GOLD)
	EventBus.building_selected_for_placement.emit(_data("house"))
	assert_object(_placer.try_place(Vector2i(6, 6))).is_null()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(gold_before)

func test_the_refinery_eats_its_well_only_when_placed() -> void:
	_rich()
	_placer.place_building_at(_data("foundry"), Vector2i(1, 1))  # requisito
	var well: Node = _map.spawn_deposit("oil_well", Vector2i(15, 15), -1, Vector2i(2, 2))
	EventBus.building_selected_for_placement.emit(_data("refinery"))
	var blocked := Rules.purchase_block_message(_data("refinery"))
	if blocked != "":
		# Sin obreros no se compra (lo decide PlacementRules); el pozo sigue ahi.
		assert_object(_placer.try_place(Vector2i(15, 15))).is_null()
		assert_bool(is_instance_valid(well) and not well.is_queued_for_deletion()).is_true()
		return
	assert_object(_placer.try_place(Vector2i(15, 15))).is_not_null()
	assert_bool(well.is_queued_for_deletion()).is_true()

# ── Mover y demoler ───────────────────────────────────────────────────

func test_moving_frees_the_old_cells_and_takes_the_new_ones() -> void:
	var node: Node2D = _placer.place_building_at(_data("warehouse"), Vector2i(4, 4))
	EventBus.request_move_building.emit(node)
	assert_bool(node.visible).is_false()
	assert_bool(_placer.try_move(Vector2i(9, 4))).is_true()
	assert_object(GridManager.get_building_at(Vector2i(4, 4))).is_null()
	assert_object(GridManager.get_building_at(Vector2i(9, 4))).is_same(node)
	assert_bool(node.visible).is_true()
	assert_vector(node.position).is_equal(View2D.footprint_center_px(Vector2i(9, 4), Vector2i(1, 1)))

func test_demolishing_frees_the_cells_and_refunds_part_of_the_cost() -> void:
	# Estado conocido: fallaba a veces en la suite completa porque otra suite dejaba
	# el modo en Sandbox (rellena recursos) o el almacen lleno (recorta el reembolso).
	var mode_before := GameMode.current
	GameMode.current = GameMode.Mode.CAMPAIGN
	ResourceManager.set_amounts({"gold": 100, "wood": 100, "steel": 0, "oil": 0})
	var data := _data("house")
	var node: Node2D = _placer.place_building_at(data, Vector2i(7, 3))
	var gold_before := ResourceManager.get_amount(ResourceManager.Type.GOLD)
	EventBus.request_demolish_building.emit(node)
	GameMode.current = mode_before
	assert_object(GridManager.get_building_at(Vector2i(7, 3))).is_null()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(gold_before + int(data.cost_gold * GameConfig.demolish_refund_ratio))

func test_the_core_cannot_be_demolished_or_moved() -> void:
	var node: Node2D = _placer.place_building_at(_data("nucleo"), Vector2i(20, 20))
	EventBus.request_demolish_building.emit(node)
	assert_object(GridManager.get_building_at(Vector2i(20, 20))).is_same(node)
	EventBus.request_move_building.emit(node)
	assert_int(_placer.get_state()).is_equal(0)

# ── Seleccion y guardado ──────────────────────────────────────────────

func test_a_click_selects_the_building_under_it() -> void:
	var node: Node2D = _placer.place_building_at(_data("house"), Vector2i(2, 9))
	var hits: Array = []
	var cb := func(n, _d): hits.append(n)
	EventBus.building_clicked.connect(cb)
	var screen := View2D.px_to_screen(get_viewport().get_canvas_transform(), View2D.footprint_center_px(Vector2i(2, 9), Vector2i.ONE))
	_placer.handle_click(screen)
	EventBus.building_clicked.disconnect(cb)
	assert_array(hits).contains([node])
	assert_bool(bool(node.call("is_selected"))).is_true()

func test_the_save_entry_is_the_shared_format() -> void:
	var node: Node2D = _placer.place_building_at(_data("sawmill"), Vector2i(11, 3), 1)
	node.set_meta("level", 2)
	node.set_meta("health", 10)
	node.set_meta("custom_name", "Sierra")
	var entries: Array = _placer.get_all_placed_buildings()
	assert_int(entries.size()).is_equal(1)
	assert_dict(entries[0]).is_equal({"id": "sawmill", "cell_x": 11, "cell_y": 3, "rotation": 1,
		"level": 2, "health": 10, "custom_name": "Sierra"})
	assert_dict(entries[0]).is_equal(Rules.serialize_building(node))
