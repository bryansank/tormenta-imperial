extends GdUnitTestSuite
## El tutorial guiado avanza cuando el jugador HACE la cosa, y el paso sale de
## lo que hay (TutorialManager.derive_step), no de un contador. Por eso aguanta
## que el jugador haga las cosas fuera de orden, que cargue a medias o que lo
## salte, y por eso vuelve donde estaba tras cargar.
##
## Se usa GridManager de verdad con BuildingData de verdad: es lo que cuenta el
## manager. Se limpia al terminar.

const SAWMILL := preload("res://data/buildings/sawmill.tres")
const HOUSE := preload("res://data/buildings/house.tres")
const FARM := preload("res://data/buildings/farm.tres")
const BARRACKS := preload("res://data/buildings/barracks.tres")
const GOLD_MINE := preload("res://data/buildings/gold_mine.tres")
const MARKET := preload("res://data/buildings/market.tres")
const WAREHOUSE := preload("res://data/buildings/warehouse.tres")
const LABORATORY := preload("res://data/buildings/laboratory.tres")
const ROAD := preload("res://data/buildings/road.tres")
const HelpTargets := preload("res://scripts/ui/HelpTargets.gd")

var _saved: Dictionary = {}
const Plenty := preload("res://tests/tutorial/plenty.gd")
var _plenty := Plenty.new()
var _steps: Array = []
var _finished: Array = []
var _nodes: Array = []

func before_test() -> void:
	_saved = TutorialManager.get_save_data()
	_plenty.park()
	TutorialManager.reset()
	GridManager.clear_all()
	_steps.clear()
	_finished.clear()
	_nodes.clear()
	EventBus.tutorial_step_changed.connect(_on_step)
	EventBus.tutorial_guide_finished.connect(_on_finished)

func after_test() -> void:
	EventBus.tutorial_step_changed.disconnect(_on_step)
	EventBus.tutorial_guide_finished.disconnect(_on_finished)
	GridManager.clear_all()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	TutorialManager.load_save_data(_saved)
	_plenty.restore()

func _on_step(step: String) -> void:
	_steps.append(step)

func _on_finished(skipped: bool) -> void:
	_finished.append(skipped)

## Un edificio en la rejilla. `building` false = obra en curso.
func _place(data: BuildingData, cell: Vector2i, built: bool = true) -> Node:
	var n := Node3D.new()
	_nodes.append(n)
	if not built:
		n.set_meta("under_construction", true)
	GridManager.place_building(cell, data, n)
	return n

# ── derive_step: la regla pura ───────────────────────────────────────

## Los hechos con las dos tarjetas de leer ya leidas (la meta y el Nucleo) y los
## tres manejos ya hechos (girar, mover, derribar; 2026-10-16), mas `extra`. Los
## manejos tienen su propia prueba.
## El Cuartel (2026-10-17) tambien va hecho salvo en las pruebas que lo miran.
func _f(extra: Dictionary = {}) -> Dictionary:
	var f := {"goal_seen": true, "core_seen": true, "rotated": true, "moved": true,
		"road_placed": true, "demolished": true, "barrackss": 1, "barrackss_built": 1,
		"trained": true}
	f.merge(extra, true)
	return f

func test_an_empty_island_starts_with_the_goal_then_the_core() -> void:
	assert_str(TutorialManager.derive_step({})).is_equal("goal")
	assert_str(TutorialManager.derive_step({"goal_seen": true})).is_equal("core")
	assert_str(TutorialManager.derive_step(_f())).is_equal("open_build")

func test_the_list_open_asks_for_the_sawmill() -> void:
	assert_str(TutorialManager.derive_step(_f({"menu_open": true}))).is_equal("pick_sawmill")

func test_holding_the_sawmill_asks_for_the_forest() -> void:
	assert_str(TutorialManager.derive_step(_f({"placing": "sawmill"}))).is_equal("place_sawmill")

func test_holding_something_else_goes_back_to_build() -> void:
	# El jugador eligio una casa primero: el tutorial no se rompe, pide CONSTRUIR
	# otra vez (y senalara el aserradero al abrir la lista).
	assert_str(TutorialManager.derive_step(_f({"placing": "house"}))).is_equal("open_build")

func test_a_sawmill_under_construction_waits() -> void:
	assert_str(TutorialManager.derive_step(_f({"sawmills": 1}))).is_equal("wait_sawmill")

func test_a_built_sawmill_asks_for_a_house() -> void:
	# Ya recogido y con su Granja: lo siguiente es la casa.
	var f := _f({"sawmills": 1, "sawmills_built": 1, "collected": true, "farms": 1})
	assert_str(TutorialManager.derive_step(f)).is_equal("open_house")
	f["menu_open"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("pick_house")
	f["placing"] = "house"
	assert_str(TutorialManager.derive_step(f)).is_equal("place_house")

## Tras la casa, el resto de edificios del principio, en este orden (2026-10-16).
func test_after_the_house_come_mine_market_warehouse_and_laboratory() -> void:
	var f := _f({"sawmills": 1, "sawmills_built": 1, "collected": true, "farms": 1, "houses": 1})
	for b in ["gold_mine", "market", "warehouse", "laboratory"]:
		assert_str(TutorialManager.derive_step(f)).is_equal("open_" + b)
		f["menu_open"] = true
		assert_str(TutorialManager.derive_step(f)).is_equal("pick_" + b)
		f["placing"] = b
		assert_str(TutorialManager.derive_step(f)).is_equal("place_" + b)
		f["menu_open"] = false
		f["placing"] = ""
		f[b + "s"] = 1
	assert_str(TutorialManager.derive_step(f)).is_equal("done")

## Girar con la Casa en la mano, mover, y derribar un tramo de carretera puesto
## para eso (2026-10-16): entre la Granja y la Mina, cada uno con su paso.
func test_rotate_move_and_demolish_sit_around_the_house() -> void:
	var f := _f({"sawmills": 1, "sawmills_built": 1, "collected": true, "farms": 1})
	for k in ["rotated", "moved", "road_placed", "demolished"]:
		f.erase(k)
	assert_str(TutorialManager.derive_step(f)).is_equal("rotate")
	f["menu_open"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("rotate_pick")
	f["menu_open"] = false
	f["placing"] = "house"
	assert_str(TutorialManager.derive_step(f)).is_equal("rotate_now")
	f["rotated"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("place_house")
	f["placing"] = ""
	f["houses"] = 1
	assert_str(TutorialManager.derive_step(f)).is_equal("move")
	f["placing"] = "__move__"
	assert_str(TutorialManager.derive_step(f)).is_equal("move_place")
	f["placing"] = ""
	f["moved"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("road_open")
	f["menu_open"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("road_pick")
	f["placing"] = "road"
	assert_str(TutorialManager.derive_step(f)).is_equal("road_place")
	f["placing"] = ""
	f["menu_open"] = false
	f["road_placed"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("demolish")
	f["demolished"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("open_gold_mine")

func test_the_handling_steps_have_mouse_and_touch_text() -> void:
	var saved := Tr.get_locale()
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		for key in ["GUIDE_ROTATE", "GUIDE_ROTATE_NOW", "GUIDE_MOVE", "GUIDE_MOVE_PLACE",
				"GUIDE_ROAD_OPEN", "GUIDE_ROAD_PLACE", "GUIDE_DEMOLISH", "GUIDE_REPAIR"]:
			assert_str(Tr.t(key)).is_not_equal(key)
			assert_str(Tr.t(key + "_TOUCH")).is_not_equal(Tr.t(key))
	Tr.set_locale(saved)
	# Girar dice la tecla en PC y el boton en tablet; derribar, lo que se recupera.
	assert_str(Tr._STRINGS["es"]["GUIDE_ROTATE_NOW"]).contains("R")
	assert_str(Tr._STRINGS["es"]["GUIDE_ROTATE_NOW_TOUCH"]).contains("↻")
	assert_str(Tr._STRINGS["es"]["GUIDE_DEMOLISH"]).contains("mitad")

func test_a_built_sawmill_asks_to_collect_then_for_a_farm() -> void:
	var f := _f({"sawmills": 1, "sawmills_built": 1, "collected": false, "farms": 0})
	assert_str(TutorialManager.derive_step(f)).is_equal("collect")
	f["collected"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("open_farm")
	f["menu_open"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("pick_farm")
	f["placing"] = "farm"
	assert_str(TutorialManager.derive_step(f)).is_equal("place_farm")
	f["farms"] = 1
	f["placing"] = ""
	f["menu_open"] = false
	assert_str(TutorialManager.derive_step(f)).is_equal("open_house")

## Cuartel temprano (2026-10-17): despues de recoger la madera, el Cuartel
## (abrir, elegir, colocar y esperar la obra), y luego la Granja.
func test_after_collecting_comes_the_barracks_then_the_farm() -> void:
	var f := _f({"sawmills": 1, "sawmills_built": 1, "collected": true, "farms": 0})
	f.erase("barrackss")
	f.erase("barrackss_built")
	assert_str(TutorialManager.derive_step(f)).is_equal("open_barracks")
	f["menu_open"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("pick_barracks")
	f["placing"] = "barracks"
	assert_str(TutorialManager.derive_step(f)).is_equal("place_barracks")
	f["placing"] = ""
	f["menu_open"] = false
	f["barrackss"] = 1
	assert_str(TutorialManager.derive_step(f)).is_equal("wait_barracks")
	f["barrackss_built"] = 1
	assert_str(TutorialManager.derive_step(f)).is_equal("open_farm")
	# Sin poder pagarlo (los tablones): consigue lo que falta.
	f["barrackss"] = 0
	f["barrackss_built"] = 0
	f["short"] = ["barracks"]
	assert_str(TutorialManager.derive_step(f)).is_equal("need_barracks")
	# Imposible en esta isla (sin aserradero, tope...): se pasa de largo.
	f["short"] = []
	f["skip"] = ["barracks"]
	assert_str(TutorialManager.derive_step(f)).is_equal("open_farm")

func test_the_barracks_step_numbers_and_texts() -> void:
	assert_int(TutorialManager.GUIDE_TOTAL).is_equal(13)
	for step in ["open_barracks", "pick_barracks", "place_barracks", "wait_barracks", "need_barracks"]:
		assert_int(TutorialManager.step_number(step)).is_equal(5)
	assert_int(TutorialManager.step_number("open_farm")).is_equal(6)
	assert_int(TutorialManager.step_number("done")).is_equal(13)
	assert_str(TutorialManager.step_target("pick_barracks")).is_equal("card:barracks")
	assert_str(TutorialManager.step_target("wait_barracks")).is_equal("building:barracks")
	var saved := Tr.get_locale()
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		for key in ["GUIDE_OPEN_BARRACKS", "GUIDE_PICK_BARRACKS", "GUIDE_PLACE_BARRACKS"]:
			assert_str(Tr.t(key)).is_not_equal(key)
			assert_str(Tr.t(key + "_TOUCH")).is_not_equal(Tr.t(key))
		assert_str(Tr.t("GUIDE_WAIT_BARRACKS")).is_not_equal("GUIDE_WAIT_BARRACKS")
	Tr.set_locale(saved)
	# Para que sirve, en una linea: los Cobradores; y donde se entrena, de verdad.
	assert_str(Tr._STRINGS["es"]["GUIDE_OPEN_BARRACKS"]).contains("Cobradores")
	assert_str(Tr._STRINGS["es"]["GUIDE_WAIT_BARRACKS"]).contains(Tr._STRINGS["es"]["BTN_ARMY"])
	assert_str(Tr._STRINGS["es"]["GUIDE_WAIT_BARRACKS"]).contains(Tr._STRINGS["es"]["LBL_MENU_GROUP_COLONY"])
	# Sus cifras: un trabajador y sitio para soldados.
	var facts: Array = TutorialManager.building_facts("barracks")
	var texts := ""
	for fact in facts:
		texts += String(fact["text"]) + " "
	assert_str(texts).contains(str(GameConfig.army_capacity_per_barracks))

func test_collecting_is_remembered_with_the_game() -> void:
	_start()
	EventBus.production_collected.emit(auto_free(Node.new()), {"wood": 1})
	assert_bool(bool(TutorialManager.guide_flags.get("collected", false))).is_true()
	var saved := TutorialManager.get_save_data()
	TutorialManager.reset()
	assert_bool(TutorialManager.guide_flags.has("collected")).is_false()
	TutorialManager.load_save_data(saved)
	assert_bool(bool(TutorialManager.guide_flags.get("collected", false))).is_true()

func test_a_save_from_before_the_goal_list_keeps_its_collect() -> void:
	# Los guardados de la rama de comida anteriores a GUIDE_GOALS traian
	# `guide_collected`; se leen como la meta "collected".
	TutorialManager.load_save_data({"intro_seen": true, "guide_state": "active", "guide_collected": true})
	assert_bool(bool(TutorialManager.guide_flags.get("collected", false))).is_true()
	TutorialManager.load_save_data({"intro_seen": true, "guide_state": "active", "guide_collected": false})
	assert_bool(TutorialManager.guide_flags.has("collected")).is_false()

func test_a_house_built_first_is_not_lost() -> void:
	# Fuera de orden: casa antes que aserradero. El paso sigue pidiendo el
	# aserradero, y al tenerlo ya no pide la casa: sigue con la mina.
	assert_str(TutorialManager.derive_step(_f({"houses": 1}))).is_equal("open_build")
	assert_str(TutorialManager.derive_step(_f({"houses": 1, "sawmills": 1, "sawmills_built": 1,
		"collected": true, "farms": 1}))).is_equal("open_gold_mine")

func test_every_step_has_text_in_both_languages_and_both_devices() -> void:
	var saved := Tr.get_locale()
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		for step in TutorialManager.GUIDE_STEPS:
			var key: String = TutorialManager.GUIDE_STEPS[step]["text"]
			assert_str(Tr.t(key)).is_not_equal(key)
			assert_int(TutorialManager.step_number(step)).is_between(1, TutorialManager.GUIDE_TOTAL)
	Tr.set_locale(saved)

func test_touch_steps_speak_of_tapping() -> void:
	# Las variantes _TOUCH existen para lo que se hace con el dedo.
	for key in ["GUIDE_OPEN_BUILD", "GUIDE_PICK_SAWMILL", "GUIDE_PLACE_SAWMILL"]:
		assert_str(Tr.t(key + "_TOUCH")).is_not_equal(key + "_TOUCH")
		assert_str(Tr.t(key + "_TOUCH")).is_not_equal(Tr.t(key))

# ── El manager sigue lo que pasa ─────────────────────────────────────

func _start() -> void:
	TutorialManager.intro_seen = true
	TutorialManager.start_guide(false)

func test_the_guide_walks_the_whole_opening() -> void:
	_start()
	# Las dos tarjetas de leer: la meta y el Nucleo, cada una con su boton.
	assert_str(TutorialManager.current_step()).is_equal("goal")
	TutorialManager.confirm_step("core")
	assert_str(TutorialManager.current_step()).is_equal("goal")
	TutorialManager.confirm_step("goal")
	assert_str(TutorialManager.current_step()).is_equal("core")
	TutorialManager.confirm_step("core")
	assert_str(TutorialManager.current_step()).is_equal("open_build")
	var menu := CanvasLayer.new()
	menu.name = "ConstructionMenu"
	add_child(menu)
	UIManager.open_window(menu)
	assert_str(TutorialManager.current_step()).is_equal("pick_sawmill")
	EventBus.building_selected_for_placement.emit(SAWMILL)
	UIManager.close_window(menu)
	assert_str(TutorialManager.current_step()).is_equal("place_sawmill")
	var node := _place(SAWMILL, Vector2i(2, 2), false)
	EventBus.building_placed.emit(SAWMILL, Vector2i(2, 2))
	assert_str(TutorialManager.current_step()).is_equal("wait_sawmill")
	node.remove_meta("under_construction")
	EventBus.construction_completed.emit(node)
	# Recoger lo que hizo el aserradero (2026-10-04).
	assert_str(TutorialManager.current_step()).is_equal("collect")
	EventBus.production_collected.emit(node, {"wood": 6})
	# El Cuartel (2026-10-17): justo despues de la madera, con su obra.
	assert_str(TutorialManager.current_step()).is_equal("open_barracks")
	var barracks := _place(BARRACKS, Vector2i(2, 10), false)
	EventBus.building_placed.emit(BARRACKS, Vector2i(2, 10))
	assert_str(TutorialManager.current_step()).is_equal("wait_barracks")
	barracks.remove_meta("under_construction")
	EventBus.construction_completed.emit(barracks)
	# Entrenar en el Cuartel (2026-10-19): su ficha y ENTRENAR.
	assert_str(TutorialManager.current_step()).is_equal("train")
	EventBus.unit_training_started.emit("infantry", 20.0)
	# La Granja: la gente come.
	assert_str(TutorialManager.current_step()).is_equal("open_farm")
	_place(FARM, Vector2i(10, 2))
	EventBus.building_placed.emit(FARM, Vector2i(10, 2))
	# Girar: con la Casa en la mano, R o ↻ (la senal es la misma).
	assert_str(TutorialManager.current_step()).is_equal("rotate")
	EventBus.building_selected_for_placement.emit(HOUSE)
	assert_str(TutorialManager.current_step()).is_equal("rotate_now")
	EventBus.building_rotate_requested.emit()
	assert_str(TutorialManager.current_step()).is_equal("place_house")
	var house := _place(HOUSE, Vector2i(6, 6))
	EventBus.building_placed.emit(HOUSE, Vector2i(6, 6))
	# Mover: MOVER en su ficha y otro sitio.
	assert_str(TutorialManager.current_step()).is_equal("move")
	EventBus.request_move_building.emit(house)
	assert_str(TutorialManager.current_step()).is_equal("move_place")
	EventBus.building_moved.emit(Vector2i(6, 6), Vector2i(6, 10))
	# Derribar: un tramo de carretera puesto a mano, y DEMOLER.
	assert_str(TutorialManager.current_step()).is_equal("road_open")
	EventBus.building_selected_for_placement.emit(ROAD)
	assert_str(TutorialManager.current_step()).is_equal("road_place")
	var road := _place(ROAD, Vector2i(9, 9))
	EventBus.building_placed.emit(ROAD, Vector2i(9, 9))
	assert_str(TutorialManager.current_step()).is_equal("demolish")
	assert_bool(TutorialManager.practice_road_cell == Vector2i(9, 9)).is_true()
	EventBus.building_demolished.emit(road, Vector2i(9, 9))
	# El resto de edificios del principio (2026-10-16).
	var rest := [[GOLD_MINE, "open_gold_mine", Vector2i(14, 2)], [MARKET, "open_market", Vector2i(14, 6)],
		[WAREHOUSE, "open_warehouse", Vector2i(14, 10)], [LABORATORY, "open_laboratory", Vector2i(18, 2)]]
	for r in rest:
		assert_str(TutorialManager.current_step()).is_equal(String(r[1]))
		_place(r[0], r[2])
		EventBus.building_placed.emit(r[0], r[2])
	assert_str(TutorialManager.current_step()).is_equal("done")
	TutorialManager.finish_guide()
	remove_child(menu)
	menu.free()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_DONE)
	assert_array(_finished).contains_exactly([false])
	assert_array(_steps).contains(["goal", "core", "open_build", "pick_sawmill", "place_sawmill", "wait_sawmill",
		"collect", "open_barracks", "wait_barracks", "open_farm", "rotate", "rotate_now", "place_house", "move", "move_place", "road_open",
		"road_place", "demolish", "open_gold_mine", "open_market", "open_warehouse", "open_laboratory", "done"])

func test_cancelling_the_placement_goes_back_one_step() -> void:
	_start()
	# Las dos tarjetas de leer van primero (tutorial de 13 pasos desde 2026-10-17).
	TutorialManager.confirm_step("goal")
	TutorialManager.confirm_step("core")
	assert_str(TutorialManager.current_step()).is_equal("open_build")
	EventBus.building_selected_for_placement.emit(SAWMILL)
	assert_str(TutorialManager.current_step()).is_equal("place_sawmill")
	EventBus.building_placement_cancelled.emit()
	assert_str(TutorialManager.current_step()).is_equal("open_build")

## skip_guide() ya no esta en la interfaz (2026-10-04): es API interna para
## sondas y pruebas, en modo dev (las pruebas corren con el editor: dev).
func test_skipping_finishes_it_and_says_so() -> void:
	_start()
	TutorialManager.skip_guide()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_SKIPPED)
	assert_str(TutorialManager.current_step()).is_equal("")
	assert_array(_finished).contains_exactly([true])
	# Hecho o saltado, lo que pase despues ya no mueve pasos.
	_steps.clear()
	EventBus.building_selected_for_placement.emit(SAWMILL)
	assert_array(_steps).is_empty()

func test_an_island_that_already_has_it_all_skips_the_guide_silently() -> void:
	# Partida vieja sin la marca: tiene aserradero y casa. No se le ensena nada.
	_place(SAWMILL, Vector2i(2, 2))
	_place(HOUSE, Vector2i(6, 6))
	_start()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_DONE)
	assert_array(_finished).contains_exactly([false])

func test_replaying_asks_for_a_new_sawmill() -> void:
	# "Repetir tutorial" con una isla hecha: cuenta desde lo que hay.
	_place(SAWMILL, Vector2i(2, 2))
	_place(HOUSE, Vector2i(6, 6))
	TutorialManager.start_guide(true)
	# Un repaso empieza otra vez por la meta.
	assert_str(TutorialManager.current_step()).is_equal("goal")
	TutorialManager.confirm_step("goal")
	TutorialManager.confirm_step("core")
	assert_str(TutorialManager.current_step()).is_equal("open_build")

# ── Guardado: vuelve donde estaba ────────────────────────────────────

func test_an_active_guide_resumes_on_load_at_the_derived_step() -> void:
	_start()
	TutorialManager.confirm_step("goal")
	TutorialManager.confirm_step("core")
	var data: Dictionary = TutorialManager.get_save_data()
	TutorialManager.reset()
	# Se guardo con el aserradero en obra.
	_place(SAWMILL, Vector2i(2, 2), false)
	TutorialManager.load_save_data(data)
	EventBus.game_load_completed.emit()
	await await_idle_frame()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_ACTIVE)
	assert_str(TutorialManager.current_step()).is_equal("wait_sawmill")

func test_the_guide_state_travels_in_the_save() -> void:
	_start()
	TutorialManager.skip_guide()
	TutorialManager.mark_help_seen("callout_objective")
	var data: Dictionary = TutorialManager.get_save_data()
	TutorialManager.reset()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_PENDING)
	assert_array(TutorialManager.helps_seen).is_empty()
	TutorialManager.load_save_data(data)
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_SKIPPED)
	assert_array(TutorialManager.helps_seen).contains_exactly(["callout_objective"])

func test_an_old_save_that_saw_the_old_intro_does_not_repeat_the_guide() -> void:
	# La intro vieja traia "Como se juega": quien la vio no repite el tutorial.
	TutorialManager.load_save_data({"intro_seen": true, "tips_seen": []})
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_DONE)
	TutorialManager.load_save_data({"intro_seen": false})
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_PENDING)

func test_reset_forgets_the_guide_and_the_seen_helps() -> void:
	_start()
	TutorialManager.mark_help_seen("callout_resources")
	TutorialManager.reset()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_PENDING)
	assert_array(TutorialManager.helps_seen).is_empty()
	assert_str(TutorialManager.current_step()).is_equal("")
	assert_bool(TutorialManager.is_prologue_pending()).is_false()

## Integracion #31 + #32: CONSTRUIR es un boton grande siempre visible (grupo
## hud_build_button), asi que el paso 1 senala ese boton y nunca el ☰ MENÚ.
func test_step_one_points_at_the_always_visible_build_button() -> void:
	assert_str(TutorialManager.step_target("open_build")).is_equal("build_button")
	var menu: CanvasLayer = load("res://scenes/ui/ConstructionMenu.tscn").instantiate()
	add_child(menu)
	_nodes.append(menu)
	var target: Control = HelpTargets.control(get_tree(), "build_button")
	assert_object(target).is_not_null()
	assert_bool(target.is_in_group("hud_build_button")).is_true()
	assert_bool(menu.is_ancestor_of(target)).is_true()
	assert_bool(Tr._STRINGS["es"].has("GUIDE_OPEN_MENU")).is_false()

func test_garbage_in_the_guide_keys_is_harmless() -> void:
	TutorialManager.load_save_data({"intro_seen": true, "guide_state": 7, "guide_baseline": "x", "helps_seen": "y"})
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_DONE)
	assert_array(TutorialManager.helps_seen).is_empty()

## Se entrena en el Cuartel (2026-10-19): con el Cuartel en pie y sin haber
## entrenado, el paso senala ENTRENAR en su ficha (o el Cuartel en el mapa).
func test_a_built_barracks_asks_to_train_in_it() -> void:
	var f := _f({"sawmills": 1, "sawmills_built": 1, "collected": true, "trained": false})
	assert_str(TutorialManager.derive_step(f)).is_equal("train")
	assert_str(TutorialManager.step_target("train")).contains("info_train")
	assert_bool("train" in TutorialManager.INFO_PANEL_STEPS).is_true()
