extends GdUnitTestSuite
## El tutorial ya no se salta (decision de Bryan, 2026-10-04). A cambio, ningun
## paso puede quedarse pidiendo algo imposible: lo que no se puede cumplir en esta
## isla se pasa de largo, y lo que falta (recursos, obreros) se dice en una linea
## corta. Un test por caso, mas el hueco para los pasos que vienen (granja y
## recoger, rama feat/comida-granja-recoger).

const SAWMILL := preload("res://data/buildings/sawmill.tres")
const HOUSE := preload("res://data/buildings/house.tres")
const HelpTargets := preload("res://scripts/ui/HelpTargets.gd")

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
	ResourceManager.set_amounts({"gold": 300, "wood": 200})
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
	assert_str(TutorialManager.current_step()).is_equal("open_house")
	assert_array(TutorialManager.blocked_goals()).contains_exactly(["sawmill"])

func test_no_forest_at_all_skips_the_sawmill() -> void:
	_map.deposits = [{"id": "gold_vein", "cell_x": 5, "cell_y": 5, "size_x": 2, "size_y": 2}]
	_start()
	assert_str(TutorialManager.current_step()).is_equal("open_house")

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
	assert_str(TutorialManager.current_step()).is_equal("open_house")
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
	assert_str(TutorialManager.goal_impossible_reason("sawmill")).is_equal("limit")
	assert_str(TutorialManager.current_step()).is_equal("open_house")

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
	assert_str(TutorialManager.current_step()).is_equal("done")

func test_a_sawmill_built_before_the_guide_starts_goes_to_the_house() -> void:
	_place(SAWMILL, Vector2i(2, 2))
	_start()
	assert_str(TutorialManager.current_step()).is_equal("open_house")

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
	assert_str(hint).is_equal(Tr.t("GUIDE_NEED_WORKERS"))
	assert_int(_words(hint)).is_less_equal(8)
	# La casa no pide obreros: es justo lo que lo arregla.
	assert_str(TutorialManager.step_hint("pick_house")).is_empty()
	var saved := Tr.get_locale()
	Tr.set_locale("en")
	assert_int(_words(Tr.t("GUIDE_NEED_WORKERS"))).is_less_equal(8)
	Tr.set_locale(saved)

func test_the_panel_shows_the_missing_line_under_the_step() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/TutorialPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	ResourceManager.set_amounts({"gold": 0, "wood": 0})
	_start()
	await await_idle_frame()
	panel._process(0.016)
	assert_str(panel.coach_text()).contains(TutorialManager.step_hint("open_build"))

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

func test_a_farm_and_a_collect_goal_slot_in_without_rewriting() -> void:
	# Lo que hara feat/comida-granja-recoger: dos metas mas en la lista.
	var goals: Array = TutorialManager.GUIDE_GOALS.duplicate(true)
	goals.append({"goal": "farm", "kind": "build", "building": "farm",
		"steps": {"open": "open_farm", "pick": "pick_farm", "place": "place_farm", "wait": "wait_farm"}})
	goals.append({"goal": "collect", "kind": "fact", "fact": "collected", "step": "collect_output"})
	var f := {"sawmills": 1, "sawmills_built": 1, "houses": 1}
	assert_str(TutorialManager.derive_step(f, goals)).is_equal("open_farm")
	f["menu_open"] = true
	assert_str(TutorialManager.derive_step(f, goals)).is_equal("pick_farm")
	f["placing"] = "farm"
	assert_str(TutorialManager.derive_step(f, goals)).is_equal("place_farm")
	f["farms"] = 1
	assert_str(TutorialManager.derive_step(f, goals)).is_equal("wait_farm")
	f["farms_built"] = 1
	assert_str(TutorialManager.derive_step(f, goals)).is_equal("collect_output")
	f["collected"] = true
	assert_str(TutorialManager.derive_step(f, goals)).is_equal("done")
	# Y una meta imposible se pasa de largo igual.
	assert_str(TutorialManager.derive_step({"sawmills": 1, "sawmills_built": 1, "houses": 1, "skip": ["farm"]}, goals)).is_equal("collect_output")

func test_a_fact_travels_in_the_save_and_reset_forgets_it() -> void:
	TutorialManager.note_guide_fact("collected")
	var data: Dictionary = TutorialManager.get_save_data()
	TutorialManager.reset()
	assert_bool(TutorialManager.guide_flags.has("collected")).is_false()
	TutorialManager.load_save_data(data)
	assert_bool(bool(TutorialManager.guide_flags.get("collected", false))).is_true()
	TutorialManager.load_save_data({"guide_flags": "basura"})
	assert_bool(TutorialManager.guide_flags.is_empty()).is_true()
