extends GdUnitTestSuite
## El tutorial ya no se salta (decision de Bryan, 2026-10-04). A cambio, ningun
## paso puede quedarse pidiendo algo imposible: lo que no se puede cumplir en esta
## isla se pasa de largo, y lo que falta (recursos, obreros) se dice en una linea
## corta. Un test por caso, mas el hueco para los pasos que vienen (granja y
## recoger, rama feat/comida-granja-recoger).

const SAWMILL := preload("res://data/buildings/sawmill.tres")
const HOUSE := preload("res://data/buildings/house.tres")
const FARM := preload("res://data/buildings/farm.tres")
const BARRACKS := preload("res://data/buildings/barracks.tres")
const HelpTargets := preload("res://scripts/ui/HelpTargets.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const Objectives := preload("res://scripts/services/Objectives.gd")

## Un generador de mapa de mentira: dice que yacimientos hay y si alguno esta al
## alcance (find_deposit_near_cells es lo que mira PlacementRules).
class FakeMap extends Node:
	var deposits: Array = []
	var reachable := true
	func get_all_deposits() -> Array:
		return deposits
	func find_deposit_near_cells(_id: String, _cells: Array, _reach: int) -> Node:
		return self if reachable else null

var _saved: Dictionary = {}
var _saved_pop: Dictionary = {}
var _saved_res: Dictionary = {}
var _saved_map: Node = null
var _saved_dev := true
var _saved_touch := ""
var _nodes: Array = []
var _map: FakeMap = null

func before_test() -> void:
	_saved = TutorialManager.get_save_data()
	_saved_pop = PopulationManager.get_save_data()
	_saved_res = {
		"gold": ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"wood": ResourceManager.get_amount(ResourceManager.Type.WOOD),
		"planks": ResourceManager.get_amount(ResourceManager.Type.PLANKS),
	}
	_saved_map = GameManager._map_gen
	_saved_dev = GameConfig.dev_mode
	_saved_touch = GameConfig.ui_touch_controls
	TutorialManager.reset()
	GridManager.clear_all()
	_nodes.clear()
	_map = FakeMap.new()
	_map.deposits = [{"id": "forest", "cell_x": 20, "cell_y": 20, "size_x": 2, "size_y": 2}]
	# Se pone a mano: register_map_generator() arrancaria una partida.
	GameManager._map_gen = _map
	# Los tablones del Cuartel (cuartel temprano, 2026-10-17).
	ResourceManager.set_amounts({"gold": 300, "wood": 200, "planks": 10})
	PopulationManager._population = 5
	PopulationManager._used_workers = 0

func after_test() -> void:
	GameManager._map_gen = _saved_map
	GameConfig.dev_mode = _saved_dev
	GameConfig.ui_touch_controls = _saved_touch
	GridManager.clear_all()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	if is_instance_valid(_map):
		_map.free()
	ResourceManager.set_amounts(_saved_res)
	PopulationManager.load_save_data(_saved_pop)
	TutorialManager.load_save_data(_saved)

func _place(data: BuildingData, cell: Vector2i, built: bool = true) -> Node:
	var n := Node3D.new()
	_nodes.append(n)
	if not built:
		n.set_meta("under_construction", true)
	GridManager.place_building(cell, data, n)
	return n

func _start() -> void:
	TutorialManager.intro_seen = true
	TutorialManager.start_guide(false)
	_read()

## Las dos tarjetas de leer del principio (la meta y el Nucleo) y los tres
## manejos (girar, mover, derribar), 2026-10-16: aqui se prueba lo demas.
func _read() -> void:
	for fact in ["goal_seen", "core_seen", "rotated", "moved", "road_placed", "demolished"]:
		TutorialManager.note_guide_fact(fact)

func _words(text: String) -> int:
	return text.strip_edges().split(" ", false).size()

# ── Sin "Saltar tutorial" ────────────────────────────────────────────

func test_skip_is_an_internal_api_that_does_nothing_outside_dev_mode() -> void:
	_start()
	GameConfig.dev_mode = false
	TutorialManager.skip_guide()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_ACTIVE)
	GameConfig.dev_mode = true
	TutorialManager.skip_guide()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_SKIPPED)

func test_replaying_from_help_is_not_a_way_to_skip_it() -> void:
	# Con el tutorial de verdad en marcha, "Repetir tutorial" no hace nada (si no,
	# daria "Terminar repaso", que es salir).
	_start()
	TutorialManager.replay_guide()
	assert_bool(TutorialManager.is_replay()).is_false()
	TutorialManager.stop_replay()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_ACTIVE)

func test_a_replay_asked_for_can_be_left_half_way() -> void:
	TutorialManager.guide_state = TutorialManager.GUIDE_DONE
	TutorialManager.replay_guide()
	assert_bool(TutorialManager.is_replay()).is_true()
	TutorialManager.stop_replay()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_DONE)

func test_a_save_with_the_tutorial_skipped_loads_the_same() -> void:
	TutorialManager.load_save_data({"intro_seen": true, "guide_state": "skipped"})
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_SKIPPED)
	assert_str(TutorialManager.current_step()).is_equal("")
	TutorialManager.load_save_data({"intro_seen": true, "guide_state": "done"})
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_DONE)

# ── Casos de atasco ──────────────────────────────────────────────────

func test_no_reachable_forest_skips_the_sawmill() -> void:
	_map.reachable = false
	assert_bool(TutorialManager.has_reachable_deposit(SAWMILL, _map)).is_false()
	assert_str(TutorialManager.goal_impossible_reason("sawmill")).is_equal("deposit")
	_start()
	# Sin aserradero tampoco hay que recoger, ni Cuartel (lo pide: 2026-10-17):
	# el siguiente es la Granja.
	assert_str(TutorialManager.current_step()).is_equal("open_farm")
	assert_array(TutorialManager.blocked_goals()).contains_exactly(["sawmill", "collect", "barracks"])

func test_no_forest_at_all_skips_the_sawmill() -> void:
	_map.deposits = [{"id": "gold_vein", "cell_x": 5, "cell_y": 5, "size_x": 2, "size_y": 2}]
	_start()
	assert_str(TutorialManager.current_step()).is_equal("open_farm")

func test_a_map_not_drawn_yet_skips_nothing() -> void:
	# Sin yacimientos sorteados aun, el mapa no esta listo: no se salta a ciegas.
	_map.deposits = []
	assert_bool(TutorialManager.has_reachable_deposit(SAWMILL, _map)).is_true()
	assert_bool(TutorialManager.has_reachable_deposit(SAWMILL, null)).is_true()
	_start()
	assert_str(TutorialManager.current_step()).is_equal("open_build")

func test_a_forest_lost_mid_guide_moves_on_by_itself() -> void:
	_start()
	assert_str(TutorialManager.current_step()).is_equal("open_build")
	_map.reachable = false
	TutorialManager._process(TutorialManager.GUIDE_CHECK_SECONDS + 0.1)
	assert_str(TutorialManager.current_step()).is_equal("open_farm")
	# Y si vuelve a haber sitio, el paso sale otra vez de lo que hay.
	_map.reachable = true
	TutorialManager._process(TutorialManager.GUIDE_CHECK_SECONDS + 0.1)
	assert_str(TutorialManager.current_step()).is_equal("open_build")

func test_the_building_limit_reached_skips_that_goal() -> void:
	# Un repaso con los cinco aserraderos del tope: no se puede pedir otro.
	for i in GameConfig.get_building_limit("sawmill"):
		_place(SAWMILL, Vector2i(0, i * 3))
	TutorialManager.guide_state = TutorialManager.GUIDE_DONE
	TutorialManager.replay_guide()
	_read()
	assert_str(TutorialManager.goal_impossible_reason("sawmill")).is_equal("limit")
	# Sin aserradero nuevo no hay que recoger; el Cuartel si se puede (2026-10-17).
	assert_str(TutorialManager.current_step()).is_equal("open_barracks")
	# El Cuartel no tiene tope (2026-10-18): nunca se salta por "limit". Puesto
	# uno, la meta queda cumplida y sigue la Granja.
	assert_int(GameConfig.get_building_limit("barracks")).is_equal(-1)
	assert_str(TutorialManager.goal_impossible_reason("barracks")).is_equal("")
	_place(BARRACKS, Vector2i(4, 0))
	TutorialManager._process(TutorialManager.GUIDE_CHECK_SECONDS + 0.1)
	assert_str(TutorialManager.current_step()).is_equal("open_farm")

func test_a_replay_with_many_barracks_still_asks_for_one() -> void:
	# Un repaso con los aserraderos al tope y varios Cuarteles: el Aserradero se
	# salta (tope), el Cuartel no (no tiene tope desde 2026-10-18), asi que el
	# repaso lo pide.
	for i in GameConfig.get_building_limit("sawmill"):
		_place(SAWMILL, Vector2i(0, i * 3))
	for i in 4:
		_place(BARRACKS, Vector2i(4, i * 3))
	TutorialManager.guide_state = TutorialManager.GUIDE_DONE
	TutorialManager.replay_guide()
	_read()
	assert_array(TutorialManager.blocked_goals()).contains(["sawmill"])
	assert_array(TutorialManager.blocked_goals()).not_contains(["barracks"])
	assert_str(TutorialManager.current_step()).is_equal("open_barracks")

func test_a_step_already_done_before_getting_there_is_not_asked() -> void:
	# La casa primero: el tutorial pide el aserradero y despues ya no pide la casa.
	_place(HOUSE, Vector2i(6, 6))
	_start()
	assert_str(TutorialManager.current_step()).is_equal("open_build")
	var saw := _place(SAWMILL, Vector2i(2, 2), false)
	EventBus.building_placed.emit(SAWMILL, Vector2i(2, 2))
	assert_str(TutorialManager.current_step()).is_equal("wait_sawmill")
	saw.remove_meta("under_construction")
	EventBus.construction_completed.emit(saw)
	# Recoger, el Cuartel y la Granja siguen; la casa ya estaba.
	assert_str(TutorialManager.current_step()).is_equal("collect")
	TutorialManager.note_guide_fact("collected")
	assert_str(TutorialManager.current_step()).is_equal("open_barracks")
	# El Cuartel tiene paso de espera (wait_barracks): al ponerlo empieza su obra
	# (ProductionManager la marca al oir building_placed) y hasta acabarla no se
	# pide la Granja.
	var barracks := _place(BARRACKS, Vector2i(2, 10), false)
	EventBus.building_placed.emit(BARRACKS, Vector2i(2, 10))
	assert_str(TutorialManager.current_step()).is_equal("wait_barracks")
	barracks.remove_meta("under_construction")
	EventBus.construction_completed.emit(barracks)
	assert_str(TutorialManager.current_step()).is_equal("open_farm")
	_place(FARM, Vector2i(10, 2))
	EventBus.building_placed.emit(FARM, Vector2i(10, 2))
	# La casa ya estaba. En este mapa de mentira no hay veta de oro: la Mina se
	# pasa de largo, y el Mercado (que la pide) tambien. Sigue el Almacen.
	assert_str(TutorialManager.current_step()).is_equal("open_warehouse")
	assert_array(TutorialManager.blocked_goals()).contains_exactly(["gold_mine", "market"])

func test_a_sawmill_built_before_the_guide_starts_asks_to_collect() -> void:
	_place(SAWMILL, Vector2i(2, 2))
	_start()
	assert_str(TutorialManager.current_step()).is_equal("collect")

func test_short_of_resources_says_what_is_missing_in_eight_words_or_less() -> void:
	ResourceManager.set_amounts({"gold": 10, "wood": 0})
	for step in ["open_build", "pick_sawmill", "place_sawmill", "open_house", "pick_house", "place_house"]:
		var hint := TutorialManager.step_hint(step)
		assert_str(hint).is_not_empty()
		assert_int(_words(hint)).is_less_equal(8)
	assert_str(TutorialManager.step_hint("open_build")).contains("70")
	# Con todo pagado, nada que decir; ni en los pasos que no son de construir.
	ResourceManager.set_amounts({"gold": 300, "wood": 200})
	assert_str(TutorialManager.step_hint("open_build")).is_empty()
	assert_str(TutorialManager.step_hint("wait_sawmill")).is_empty()
	assert_str(TutorialManager.step_hint("done")).is_empty()

func test_short_of_workers_says_so_in_eight_words_or_less() -> void:
	PopulationManager._population = 1
	var hint := TutorialManager.step_hint("pick_sawmill")
	assert_str(hint).is_equal(Tr.t("GUIDE_NEED_WORKERS") % 1)
	assert_int(_words(hint)).is_less_equal(8)
	# La casa no pide obreros: es justo lo que lo arregla.
	assert_str(TutorialManager.step_hint("pick_house")).is_empty()
	var saved := Tr.get_locale()
	Tr.set_locale("en")
	assert_int(_words(Tr.t("GUIDE_NEED_WORKERS") % 3)).is_less_equal(8)
	Tr.set_locale(saved)

func test_the_panel_shows_the_missing_line_under_the_step() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/TutorialPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	ResourceManager.set_amounts({"gold": 0, "wood": 0})
	_start()
	await await_idle_frame()
	panel._process(0.016)
	# Sin oro ni madera el paso es "consigue lo que falta": la tarjeta lleva el
	# objetivo y debajo sus pasos con su marca (2026-10-19).
	var step: String = panel.current_step()
	assert_bool(TutorialManager.is_need_step(step)).is_true()
	for line in TutorialManager.step_hint(step).split("\n", false):
		assert_str(panel.coach_text()).contains(line)

func test_touch_steps_all_resolve_and_the_hint_is_the_same() -> void:
	GameConfig.ui_touch_controls = "always"
	for step in TutorialManager.GUIDE_STEPS:
		var key: String = TutorialManager.GUIDE_STEPS[step]["text"]
		var text := TutorialManager.step_text(step)
		assert_str(text).is_not_equal(key)
		assert_str(text).is_not_empty()
	assert_str(TutorialManager.step_text("place_sawmill")).contains("✓")
	ResourceManager.set_amounts({"gold": 0, "wood": 0})
	assert_str(TutorialManager.step_hint("place_sawmill")).is_not_empty()

func test_the_2d_view_finds_the_forest_too() -> void:
	# MapGenerator2D hereda la consulta de yacimientos, y el punto en pantalla se
	# calcula sin Camera3D (la camara 2D del lienzo).
	var gen2d: Node = load("res://scripts/view2d/MapGenerator2D.gd").new()
	var has_it := gen2d.has_method("get_all_deposits") and gen2d.has_method("find_deposit_near_cells")
	gen2d.free()
	assert_bool(has_it).is_true()
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/TutorialPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	var p: Dictionary = panel._forest_point(Vector2(1280, 720))
	assert_bool(p.has("point")).is_true()
	var sp := HelpTargets.cell_screen_point(get_viewport(), Vector2i(20, 20), Vector2i(2, 2))
	assert_bool(sp.has("ok")).is_true()

# ── El hueco para los pasos que vienen ───────────────────────────────

func test_guide_total_is_the_highest_step_number() -> void:
	var top := 0
	for step in TutorialManager.GUIDE_STEPS:
		top = maxi(top, TutorialManager.step_number(step))
	assert_int(TutorialManager.GUIDE_TOTAL).is_equal(top)

func test_every_goal_step_is_a_known_step() -> void:
	for g in TutorialManager.GUIDE_GOALS:
		if String(g.get("kind", "build")) == "fact":
			assert_bool(TutorialManager.GUIDE_STEPS.has(String(g["step"]))).is_true()
			continue
		for k in g["steps"]:
			assert_bool(TutorialManager.GUIDE_STEPS.has(String(g["steps"][k]))).is_true()

func test_the_collect_and_farm_goals_sit_between_sawmill_and_house() -> void:
	# feat/comida-granja-recoger metio sus dos metas en el hueco de la lista. Lo
	# de despues de la casa (2026-10-16) se da por hecho aqui.
	var f := {"goal_seen": true, "core_seen": true, "rotated": true, "moved": true, "road_placed": true,
		"demolished": true, "sawmills": 1, "sawmills_built": 1, "houses": 1,
		"barrackss": 1, "barrackss_built": 1,
		"gold_mines": 1, "markets": 1, "warehouses": 1, "laboratorys": 1}
	assert_str(TutorialManager.derive_step(f)).is_equal("collect")
	f["collected"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("open_farm")
	f["menu_open"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("pick_farm")
	f["placing"] = "farm"
	assert_str(TutorialManager.derive_step(f)).is_equal("place_farm")
	f["farms"] = 1
	assert_str(TutorialManager.derive_step(f)).is_equal("done")
	# Y una meta imposible se pasa de largo igual.
	var skipped := f.duplicate()
	skipped.erase("farms")
	skipped["skip"] = ["farm"]
	assert_str(TutorialManager.derive_step(skipped)).is_equal("done")
	# Una meta mas sigue entrando en la lista sin reescribir derive_step.
	var goals: Array = TutorialManager.GUIDE_GOALS.duplicate(true)
	goals.append({"goal": "extra", "kind": "fact", "fact": "extra_fact", "step": "collect"})
	assert_str(TutorialManager.derive_step(f, goals)).is_equal("collect")
	f["extra_fact"] = true
	assert_str(TutorialManager.derive_step(f, goals)).is_equal("done")

# ── Tutorial claro (2026-10-16) ──────────────────────────────────────

func test_a_reading_card_only_moves_on_with_its_own_button() -> void:
	TutorialManager.intro_seen = true
	TutorialManager.start_guide(false)
	assert_str(TutorialManager.current_step()).is_equal("goal")
	assert_bool(TutorialManager.step_has_ok("goal")).is_true()
	# El boton de otro paso no adelanta nada.
	TutorialManager.confirm_step("core")
	assert_str(TutorialManager.current_step()).is_equal("goal")
	TutorialManager.confirm_step("goal")
	assert_str(TutorialManager.current_step()).is_equal("core")
	assert_str(TutorialManager.step_target("core")).is_equal("core")
	TutorialManager.confirm_step("core")
	assert_str(TutorialManager.current_step()).is_equal("open_build")

func test_an_old_island_with_sawmill_and_house_still_skips_the_new_goals() -> void:
	# Partida vieja sin la marca: aserradero y casa. No se le piden la meta ni
	# los edificios que entraron despues en el tutorial.
	_place(SAWMILL, Vector2i(2, 2))
	_place(HOUSE, Vector2i(6, 6))
	TutorialManager.intro_seen = true
	TutorialManager.start_guide(false)
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_DONE)

func test_every_starting_building_shows_its_numbers() -> void:
	# "Iconos y cifras antes que frases": cada edificio del principio que da o
	# pide algo tiene su fila de cifras, sacada de sus datos.
	for b in ["nucleo", "sawmill", "barracks", "farm", "house", "gold_mine", "market", "warehouse", "laboratory"]:
		assert_array(TutorialManager.building_facts(b)).override_failure_message(b).is_not_empty()
	var saw: Array = TutorialManager.building_facts("sawmill")
	assert_str(String(saw[0]["icon"])).is_equal("wood")
	assert_str(String(saw[0]["text"])).contains(str(SAWMILL.produces_wood))
	var house: Array = TutorialManager.building_facts("house")
	assert_str(String(house[0]["text"])).contains(str(HOUSE.population_capacity))
	var wh: Array = TutorialManager.building_facts("warehouse")
	var texts := ""
	for f in wh:
		texts += String(f["text"]) + " "
	assert_str(texts).contains(str(GameConfig.warehouse_storage_bonus))
	assert_array(TutorialManager.building_facts("")).is_empty()

func test_every_build_step_names_what_its_building_is_for() -> void:
	# La frase de "para que sirve" va en el paso de abrir CONSTRUIR de cada
	# edificio, en los dos idiomas y con su variante de dedo.
	var saved := Tr.get_locale()
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		for key in ["GUIDE_OPEN_BUILD", "GUIDE_OPEN_BARRACKS", "GUIDE_OPEN_FARM", "GUIDE_OPEN_HOUSE", "GUIDE_OPEN_GOLD_MINE",
				"GUIDE_OPEN_MARKET", "GUIDE_OPEN_WAREHOUSE", "GUIDE_OPEN_LABORATORY"]:
			assert_str(Tr.t(key)).is_not_equal(key)
			assert_str(Tr.t(key + "_TOUCH")).is_not_equal(key + "_TOUCH")
			assert_str(Tr.t(key + "_TOUCH")).is_not_equal(Tr.t(key))
		for key in ["GUIDE_GOAL", "GUIDE_CORE", "GUIDE_WAIT_SAWMILL", "GUIDE_DONE"]:
			assert_str(Tr.t(key)).is_not_equal(key)
		# La meta, al empezar y al terminar: las 3 eras y el nivel 3.
		for key in ["GUIDE_GOAL", "GUIDE_DONE", "HELP_B_GOAL"]:
			assert_str(Tr.t(key)).contains("3")
	Tr.set_locale(saved)

func test_short_of_resources_also_says_how_to_get_them() -> void:
	ResourceManager.set_amounts({"gold": 0, "wood": 0})
	# Sin Aserradero aun, la madera se corta a mano en un bosque.
	var how := TutorialManager.step_how("open_build")
	assert_str(how).contains(Tr.ti("GUIDE_HOW_WOOD_HAND"))
	assert_str(how).contains(Tr.ti("GUIDE_HOW_GOLD_HAND"))
	# Con Aserradero, se recoge de el.
	_place(SAWMILL, Vector2i(2, 2))
	assert_str(TutorialManager.step_how("open_house")).contains(Tr.ti("GUIDE_HOW_WOOD"))
	ResourceManager.set_amounts({"gold": 300, "wood": 200})
	assert_str(TutorialManager.step_how("open_build")).is_empty()
	assert_str(TutorialManager.step_how("done")).is_empty()

func test_short_of_workers_with_room_in_the_houses_says_to_wait() -> void:
	PopulationManager._population = 1
	PopulationManager._max_population = 11
	assert_str(TutorialManager.step_how("pick_gold_mine")).is_equal(Tr.t("GUIDE_HOW_WORKERS_WAIT"))

# ── La leccion de reparar (2026-10-16) ───────────────────────────────

func test_the_first_damage_teaches_repairing_once() -> void:
	TutorialManager.guide_state = TutorialManager.GUIDE_DONE
	TutorialManager.intro_seen = true
	var saw := _place(SAWMILL, Vector2i(2, 2))
	saw.set_meta("health", 50)
	EventBus.building_damaged.emit(saw, 50, 100)
	assert_str(TutorialManager.current_step()).is_equal(TutorialManager.REPAIR_STEP)
	assert_bool(TutorialManager.is_coach_active()).is_true()
	assert_bool(TutorialManager.step_has_ok(TutorialManager.REPAIR_STEP)).is_true()
	assert_object(TutorialManager.repair_target()).is_same(saw)
	# Entendido la cierra, y no vuelve a salir.
	TutorialManager.confirm_step(TutorialManager.REPAIR_STEP)
	assert_str(TutorialManager.current_step()).is_equal("")
	assert_bool(TutorialManager.repair_lesson_done).is_true()
	EventBus.building_damaged.emit(saw, 40, 100)
	assert_str(TutorialManager.current_step()).is_equal("")
	# Va en la partida, y reset() la olvida.
	var data := TutorialManager.get_save_data()
	TutorialManager.reset()
	assert_bool(TutorialManager.repair_lesson_done).is_false()
	TutorialManager.load_save_data(data)
	assert_bool(TutorialManager.repair_lesson_done).is_true()

func test_repairing_also_closes_the_repair_lesson() -> void:
	TutorialManager.guide_state = TutorialManager.GUIDE_DONE
	var saw := _place(SAWMILL, Vector2i(2, 2))
	saw.set_meta("health", 50)
	EventBus.building_damaged.emit(saw, 50, 100)
	saw.set_meta("health", 100)
	EventBus.building_repaired.emit(saw)
	assert_str(TutorialManager.current_step()).is_equal("")
	assert_bool(TutorialManager.repair_lesson_done).is_true()

func test_the_repair_lesson_waits_for_the_guided_tutorial() -> void:
	_start()
	var saw := _place(SAWMILL, Vector2i(2, 2))
	saw.set_meta("health", 50)
	EventBus.building_damaged.emit(saw, 50, 100)
	assert_str(TutorialManager.current_step()).is_not_equal(TutorialManager.REPAIR_STEP)
	TutorialManager.guide_state = TutorialManager.GUIDE_DONE
	EventBus.tutorial_guide_finished.emit(false)
	await await_idle_frame()
	assert_str(TutorialManager.current_step()).is_equal(TutorialManager.REPAIR_STEP)
	TutorialManager.confirm_step(TutorialManager.REPAIR_STEP)

func test_a_fact_travels_in_the_save_and_reset_forgets_it() -> void:
	TutorialManager.note_guide_fact("collected")
	var data: Dictionary = TutorialManager.get_save_data()
	TutorialManager.reset()
	assert_bool(TutorialManager.guide_flags.has("collected")).is_false()
	TutorialManager.load_save_data(data)
	assert_bool(bool(TutorialManager.guide_flags.get("collected", false))).is_true()
	TutorialManager.load_save_data({"guide_flags": "basura"})
	assert_bool(TutorialManager.guide_flags.is_empty()).is_true()

# ── Consigue lo que falta (2026-10-17, fix/tutorial-materiales) ──────
#
# Bug de la 1.0: el tutorial pedia "Toca CONSTRUIR" para un edificio que aun no
# se podia pagar (el boton apagado), y lo que faltaba quedaba en una linea
# pequena o ni salia (con pocos trabajadores se callaba el resto). Ahora el paso
# es "consigue lo que falta" y vuelve solo al de construir.

func test_derive_step_asks_to_get_what_is_missing_before_building() -> void:
	var f := {"goal_seen": true, "core_seen": true, "short": ["sawmill"]}
	assert_str(TutorialManager.derive_step(f)).is_equal("need_sawmill")
	# Con la lista abierta tambien: elegir algo que no se puede pagar no sirve.
	f["menu_open"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("need_sawmill")
	# Ya en la mano (lo pago al elegirlo): se coloca.
	f["placing"] = "sawmill"
	assert_str(TutorialManager.derive_step(f)).is_equal("place_sawmill")
	# Con todo pagado, el paso de siempre.
	f = {"goal_seen": true, "core_seen": true, "short": []}
	assert_str(TutorialManager.derive_step(f)).is_equal("open_build")

func test_the_rotate_and_road_goals_also_wait_for_what_they_pick() -> void:
	var f := {"goal_seen": true, "core_seen": true, "sawmills": 1, "sawmills_built": 1,
		"collected": true, "barrackss": 1, "barrackss_built": 1, "farms": 1, "short": ["house"]}
	assert_str(TutorialManager.derive_step(f)).is_equal("need_house")
	f.merge({"rotated": true, "houses": 1, "moved": true, "short": ["road"]}, true)
	assert_str(TutorialManager.derive_step(f)).is_equal("need_road")

func test_short_of_resources_the_guide_waits_and_comes_back_by_itself() -> void:
	ResourceManager.set_amounts({"gold": 10, "wood": 0})
	_start()
	assert_str(TutorialManager.current_step()).is_equal("need_sawmill")
	var text := TutorialManager.step_text("need_sawmill")
	assert_str(text).contains(SAWMILL.get_display_name())
	# Los pasos con su cuenta (2026-10-19): "● Junta 80 de oro (10/80)".
	assert_str(TutorialManager.step_hint("need_sawmill")).contains("(10/80)")
	assert_str(TutorialManager.step_how("need_sawmill")).is_not_empty()
	# Llega lo que faltaba: vuelve al paso de construir sin tocar nada mas.
	ResourceManager.set_amounts({"gold": 300, "wood": 200})
	TutorialManager._refresh_guide()
	assert_str(TutorialManager.current_step()).is_equal("open_build")

func test_short_of_workers_and_resources_says_both() -> void:
	PopulationManager._population = 1
	ResourceManager.set_amounts({"gold": 0, "wood": 0})
	var hint := TutorialManager.step_hint("need_sawmill")
	# Una lista corta de pasos (2026-10-19): lo que falta de la bolsa, con su
	# cuenta, y como mucho NEED_PLAN_ITEMS lineas de pocas palabras.
	assert_str(hint).contains(Tr.t("OBJ_STEP_GATHER") % [80, Tr.res_name("gold"), 0, 80])
	assert_int(hint.split("\n", false).size()).is_less_equal(TutorialManager.NEED_PLAN_ITEMS)
	for line in hint.split("\n"):
		assert_int(_words(line)).is_less_equal(8)
	# Solo trabajadores: el paso de ahora es esperarlos (hay sitio en las casas).
	ResourceManager.set_amounts({"gold": 300, "wood": 200})
	PopulationManager._max_population = 5
	assert_str(TutorialManager.step_hint("need_sawmill")).contains("● " + Tr.t("OBJ_STEP_WORKERS_WAIT") % 1)

func test_no_room_in_the_houses_says_to_build_another() -> void:
	ResourceManager.set_amounts({"gold": 300, "wood": 200})
	PopulationManager._population = 1
	PopulationManager._max_population = 1
	var house: BuildingData = Rules.load_building_data("house")
	assert_str(TutorialManager.step_hint("need_sawmill")).contains("● " + Tr.t("OBJ_STEP_HOUSE") % house.population_capacity)
	assert_str(TutorialManager.step_how("need_sawmill")).is_equal(Tr.ti("OBJ_STEP_PLACE_HOW") % Objectives.building_the("house"))
	assert_str(TutorialManager.need_target("sawmill")).is_equal("build_button")

func test_the_need_step_points_where_to_get_it() -> void:
	ResourceManager.set_amounts({"gold": 300, "wood": 0})
	# Madera sin Aserradero: el bosque.
	assert_str(TutorialManager.need_target("house")).is_equal("forest")
	_place(SAWMILL, Vector2i(2, 2))
	assert_str(TutorialManager.need_target("house")).is_equal("built:sawmill|building:sawmill")
	# Oro sin Mina: la veta, para sacarlo a mano.
	ResourceManager.set_amounts({"gold": 0, "wood": 200})
	assert_str(TutorialManager.need_target("house")).is_equal("deposit:gold_vein")
	assert_str(TutorialManager.step_target("need_house")).is_equal("deposit:gold_vein")

func test_every_need_step_belongs_to_a_goal_building() -> void:
	var goal_buildings: Array = []
	for g in TutorialManager.GUIDE_GOALS:
		if g.has("building") and (String(g.get("kind", "build")) == "build" or g.has("menu_step")):
			goal_buildings.append(String(g["building"]))
	for b in goal_buildings:
		var step: String = TutorialManager.NEED_PREFIX + b
		assert_bool(TutorialManager.GUIDE_STEPS.has(step)).override_failure_message(
			"falta el paso %s" % step).is_true()
		assert_str(TutorialManager.building_for_step(step)).is_equal(b)
		assert_str(TutorialManager.step_text(step)).is_not_empty()
		assert_str(TutorialManager.step_text(step)).not_contains("%s")

func test_the_panel_shows_the_need_step_with_what_is_missing() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/TutorialPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	ResourceManager.set_amounts({"gold": 0, "wood": 0})
	_start()
	await await_idle_frame()
	panel._process(0.016)
	assert_str(panel.current_step()).is_equal("need_sawmill")
	assert_str(panel.coach_text()).contains(TutorialManager.step_text("need_sawmill"))
	assert_str(panel.coach_text()).contains(TutorialManager.step_hint("need_sawmill"))
	assert_str(panel.coach_text()).contains(Tr.ti("GUIDE_HOW_GOLD_HAND"))

# ── Cuartel temprano (2026-10-17, feat/cuartel-temprano) ─────────────

## Sin tablones para el Cuartel, el paso dice que falta y senala el Aserradero
## (alli se sierran), y vuelve solo al tenerlos.
func test_short_of_planks_the_barracks_step_points_at_the_sawmill() -> void:
	ResourceManager.unlock(ResourceManager.Type.PLANKS)
	ResourceManager.set_amounts({"planks": 0, "gold": 1000, "wood": 300})
	_place(SAWMILL, Vector2i(2, 2))
	_start()
	TutorialManager.note_guide_fact("collected")
	assert_str(TutorialManager.current_step()).is_equal("need_barracks")
	assert_str(TutorialManager.step_target("need_barracks")).is_equal("built:sawmill|building:sawmill")
	assert_str(TutorialManager.step_hint("need_barracks")).contains(Tr.res_name("planks"))
	assert_str(TutorialManager.step_how("need_barracks")).contains(Tr.t("PROC_MAKE_PLANKS"))
	ResourceManager.set_amounts({"planks": 10})
	TutorialManager._refresh_guide()
	assert_str(TutorialManager.current_step()).is_equal("open_barracks")

## Un paso que se pasa de largo lo dice una vez, en una linea (no deja al
## jugador perdido); en un repaso no.
func test_a_skipped_goal_says_why_once() -> void:
	var notes: Array = []
	var grab := func(text: String, _type: String, _color: Color) -> void: notes.append(text)
	EventBus.notification_posted.connect(grab)
	_map.reachable = false
	_start()
	TutorialManager._process(TutorialManager.GUIDE_CHECK_SECONDS + 0.1)
	TutorialManager._process(TutorialManager.GUIDE_CHECK_SECONDS + 0.1)
	EventBus.notification_posted.disconnect(grab)
	# El nombre va dentro de la frase, con su articulo (2026-10-19).
	var saw_note: String = Tr.t("GUIDE_SKIP_DEPOSIT") % Objectives.building_the("sawmill")
	var barracks_note: String = Tr.t("GUIDE_SKIP_PREREQ") % Objectives.building_the("barracks")
	assert_int(notes.count(saw_note)).is_equal(1)
	assert_int(notes.count(barracks_note)).is_equal(1)
	for key in ["GUIDE_SKIP_DEPOSIT", "GUIDE_SKIP_LIMIT", "GUIDE_SKIP_PREREQ", "GUIDE_SKIP_RANK"]:
		for loc in ["es", "en"]:
			assert_str(String(Tr._STRINGS[loc].get(key, ""))).contains("%s")
