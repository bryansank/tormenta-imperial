extends GdUnitTestSuite
## El tutorial guiado avanza cuando el jugador HACE la cosa, y el paso sale de
## lo que hay (TutorialManager.derive_step), no de un contador. Por eso aguanta
## que el jugador haga las cosas fuera de orden, que cargue a medias o que lo
## salte, y por eso vuelve donde estaba tras cargar.
##
## TUTORIAL CORTO (decision de Bryan, 2026-10-24): recursos, Aserradero (colocar
## y recoger), Mina de oro (colocar y recoger), Cuartel, entrenar y la primera
## batalla. Nada mas.
##
## Se usa GridManager de verdad con BuildingData de verdad: es lo que cuenta el
## manager. Se limpia al terminar.

const SAWMILL := preload("res://data/buildings/sawmill.tres")
const HOUSE := preload("res://data/buildings/house.tres")
const BARRACKS := preload("res://data/buildings/barracks.tres")
const GOLD_MINE := preload("res://data/buildings/gold_mine.tres")
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

## Un edificio en la rejilla. `built` false = obra en curso.
func _place(data: BuildingData, cell: Vector2i, built: bool = true) -> Node:
	var n := Node3D.new()
	_nodes.append(n)
	if not built:
		n.set_meta("under_construction", true)
	GridManager.place_building(cell, data, n)
	return n

# ── derive_step: la regla pura ───────────────────────────────────────

## Los hechos con la tarjeta de los recursos ya leida, mas `extra`.
func _f(extra: Dictionary = {}) -> Dictionary:
	var f := {"resources_seen": true, "unit_home": true}
	f.merge(extra, true)
	return f

func test_an_empty_island_starts_with_the_resources_card() -> void:
	assert_str(TutorialManager.derive_step({})).is_equal("resources")
	assert_bool(TutorialManager.step_has_ok("resources")).is_true()
	assert_str(TutorialManager.derive_step(_f())).is_equal("open_build")

func test_the_sawmill_open_pick_place_wait_and_collect() -> void:
	assert_str(TutorialManager.derive_step(_f({"menu_open": true}))).is_equal("pick_sawmill")
	assert_str(TutorialManager.derive_step(_f({"placing": "sawmill"}))).is_equal("place_sawmill")
	# Con otra cosa en la mano el tutorial no se rompe: pide CONSTRUIR otra vez.
	assert_str(TutorialManager.derive_step(_f({"placing": "house"}))).is_equal("open_build")
	assert_str(TutorialManager.derive_step(_f({"sawmills": 1}))).is_equal("wait_sawmill")
	assert_str(TutorialManager.derive_step(_f({"sawmills": 1, "sawmills_built": 1}))).is_equal("collect")

func test_then_the_gold_mine_and_its_gold() -> void:
	var f := _f({"sawmills": 1, "sawmills_built": 1, "collected": true})
	assert_str(TutorialManager.derive_step(f)).is_equal("open_gold_mine")
	f["menu_open"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("pick_gold_mine")
	f["placing"] = "gold_mine"
	assert_str(TutorialManager.derive_step(f)).is_equal("place_gold_mine")
	f.erase("placing")
	f.erase("menu_open")
	f["gold_mines"] = 1
	assert_str(TutorialManager.derive_step(f)).is_equal("wait_gold_mine")
	f["gold_mines_built"] = 1
	assert_str(TutorialManager.derive_step(f)).is_equal("collect_gold")
	f["collected_gold"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("open_barracks")

func test_then_the_barracks_training_and_the_first_battle() -> void:
	var f := _f({"sawmills": 1, "sawmills_built": 1, "collected": true, "gold_mines": 1,
		"gold_mines_built": 1, "collected_gold": true})
	f["barrackss"] = 1
	assert_str(TutorialManager.derive_step(f)).is_equal("wait_barracks")
	f["barrackss_built"] = 1
	assert_str(TutorialManager.derive_step(f)).is_equal("train")
	# Sin poder pagar el soldado: un paso de espera, no la flecha sobre ENTRENAR.
	f["short"] = [TutorialManager.UNIT_SHORT_PREFIX + "infantry"]
	assert_str(TutorialManager.derive_step(f)).is_equal("need_train")
	f["short"] = []
	f["trained"] = true
	# El soldado aun en el Cuartel: se espera.
	f["unit_home"] = false
	assert_str(TutorialManager.derive_step(f)).is_equal("wait_unit")
	f["unit_home"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("battle")
	f["missions_open"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("battle_launch")
	f["battle_done"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("done")

func test_the_short_guide_has_only_its_steps() -> void:
	# Casa, Granja, Mercado, Almacen, Laboratorio y girar/mover/derribar salieron
	# del tutorial (2026-10-24): son consejos y paginas de AYUDA.
	var goals: Array = []
	for g in TutorialManager.GUIDE_GOALS:
		goals.append(String(g["goal"]))
	assert_array(goals).contains_exactly(["resources", "sawmill", "collect", "gold_mine", "collect_gold",
		"barracks", "train", "battle"])
	for gone in ["rotate", "move", "demolish", "open_house", "open_farm", "open_market",
			"open_warehouse", "open_laboratory", "goal", "core"]:
		assert_bool(TutorialManager.GUIDE_STEPS.has(gone)).override_failure_message(gone).is_false()
	for tip in ["house", "food_low", "placing", "building_actions"]:
		assert_bool(TutorialManager.TIPS.has(tip)).override_failure_message(tip).is_true()

func test_step_numbers_and_texts() -> void:
	assert_int(TutorialManager.GUIDE_TOTAL).is_equal(8)
	var expect := {"resources": 1, "open_build": 2, "wait_sawmill": 2, "collect": 3, "open_gold_mine": 4,
		"collect_gold": 5, "open_barracks": 6, "wait_barracks": 6, "train": 7, "need_train": 7,
		"wait_unit": 8, "battle": 8, "battle_launch": 8, "done": 8}
	for step in expect:
		assert_int(TutorialManager.step_number(step)).override_failure_message(step).is_equal(int(expect[step]))
	var saved := Tr.get_locale()
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		for step in TutorialManager.GUIDE_STEPS:
			var key: String = TutorialManager.GUIDE_STEPS[step]["text"]
			assert_str(Tr.t(key)).override_failure_message(key).is_not_equal(key)
		for key in ["GUIDE_COLLECT_GOLD", "GUIDE_BATTLE"]:
			assert_str(Tr.t(key + "_TOUCH")).is_not_equal(Tr.t(key))
	Tr.set_locale(saved)
	# Donde se entrena, de verdad: en el Cuartel, nunca en un menu.
	for loc in ["es", "en"]:
		assert_str(Tr._STRINGS[loc]["GUIDE_WAIT_BARRACKS"]).contains(Tr._STRINGS[loc]["BTN_TRAIN"])
		assert_str(Tr._STRINGS[loc]["GUIDE_WAIT_BARRACKS"]).not_contains(Tr._STRINGS[loc]["BTN_ARMY"])
	# El final: lo basico, y a juntar recursos y mejorar.
	assert_str(Tr._STRINGS["es"]["GUIDE_DONE"]).contains("Junta recursos")

func test_the_resources_card_shows_every_resource_with_its_icon() -> void:
	var facts: Array = TutorialManager.resource_facts()
	var icons: Array = []
	for f in facts:
		icons.append(String(f["icon"]))
		assert_str(String(f["text"])).is_not_empty()
	assert_array(icons).contains_exactly(["gold", "wood", "food", "steel", "oil", "planks"])
	for loc in ["es", "en"]:
		assert_int(String(Tr._STRINGS[loc]["GUIDE_RESOURCES"]).split("\n").size()).is_greater_equal(4)

func test_battle_targets_find_the_missions_button_and_the_launch() -> void:
	assert_str(TutorialManager.step_target("battle")).contains("bar_missions")
	assert_str(TutorialManager.step_target("battle_launch")).is_equal("mission_launch")

# ── El manager sigue lo que pasa ─────────────────────────────────────

func _start() -> void:
	TutorialManager.intro_seen = true
	TutorialManager.start_guide(false)

func test_the_guide_walks_the_whole_short_opening() -> void:
	_start()
	assert_str(TutorialManager.current_step()).is_equal("resources")
	TutorialManager.confirm_step("collect")
	assert_str(TutorialManager.current_step()).is_equal("resources")
	TutorialManager.confirm_step("resources")
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
	assert_str(TutorialManager.current_step()).is_equal("collect")
	EventBus.production_collected.emit(node, {"wood": 6})
	# La Mina de oro: colocar, su obra y recoger el oro.
	assert_str(TutorialManager.current_step()).is_equal("open_gold_mine")
	var mine := _place(GOLD_MINE, Vector2i(10, 2), false)
	EventBus.building_placed.emit(GOLD_MINE, Vector2i(10, 2))
	assert_str(TutorialManager.current_step()).is_equal("wait_gold_mine")
	mine.remove_meta("under_construction")
	EventBus.construction_completed.emit(mine)
	assert_str(TutorialManager.current_step()).is_equal("collect_gold")
	EventBus.production_collected.emit(mine, {"gold": 8})
	# El Cuartel, con su obra.
	assert_str(TutorialManager.current_step()).is_equal("open_barracks")
	var barracks := _place(BARRACKS, Vector2i(2, 10), false)
	EventBus.building_placed.emit(BARRACKS, Vector2i(2, 10))
	assert_str(TutorialManager.current_step()).is_equal("wait_barracks")
	barracks.remove_meta("under_construction")
	EventBus.construction_completed.emit(barracks)
	assert_str(TutorialManager.current_step()).is_equal("train")
	EventBus.unit_training_started.emit("infantry", 20.0)
	assert_bool(bool(TutorialManager.guide_flags.get("trained", false))).is_true()
	# La primera batalla: cualquier pelea en el tablero la cumple.
	EventBus.encounter_ended.emit(true, 3)
	assert_str(TutorialManager.current_step()).is_equal("done")
	TutorialManager.finish_guide()
	remove_child(menu)
	menu.free()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_DONE)
	assert_array(_finished).contains_exactly([false])
	assert_array(_steps).contains(["resources", "open_build", "pick_sawmill", "place_sawmill", "wait_sawmill",
		"collect", "open_gold_mine", "wait_gold_mine", "collect_gold", "open_barracks", "wait_barracks",
		"train", "done"])

func test_missions_open_turns_the_battle_step_into_the_launch() -> void:
	_start()
	TutorialManager.guide_flags = {"resources_seen": true, "collected": true, "collected_gold": true, "trained": true}
	_place(SAWMILL, Vector2i(2, 2))
	_place(GOLD_MINE, Vector2i(10, 2))
	_place(BARRACKS, Vector2i(2, 10))
	var panel := CanvasLayer.new()
	panel.name = "SkirmishPanel"
	add_child(panel)
	UIManager.open_window(panel)
	var f := TutorialManager.guide_facts()
	assert_bool(bool(f["missions_open"])).is_true()
	UIManager.close_window(panel)
	assert_bool(bool(TutorialManager.guide_facts()["missions_open"])).is_false()
	remove_child(panel)
	panel.free()

func test_cancelling_the_placement_goes_back_one_step() -> void:
	_start()
	TutorialManager.confirm_step("resources")
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
	_place(SAWMILL, Vector2i(2, 2))
	_place(HOUSE, Vector2i(6, 6))
	TutorialManager.start_guide(true)
	assert_str(TutorialManager.current_step()).is_equal("resources")
	TutorialManager.confirm_step("resources")
	assert_str(TutorialManager.current_step()).is_equal("open_build")

# ── Guardado: vuelve donde estaba ────────────────────────────────────

func test_an_active_guide_resumes_on_load_at_the_derived_step() -> void:
	_start()
	TutorialManager.confirm_step("resources")
	var data: Dictionary = TutorialManager.get_save_data()
	TutorialManager.reset()
	_place(SAWMILL, Vector2i(2, 2), false)
	TutorialManager.load_save_data(data)
	EventBus.game_load_completed.emit()
	await await_idle_frame()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_ACTIVE)
	assert_str(TutorialManager.current_step()).is_equal("wait_sawmill")

func test_collecting_is_remembered_with_the_game() -> void:
	_start()
	EventBus.production_collected.emit(auto_free(Node.new()), {"wood": 1})
	EventBus.production_collected.emit(auto_free(Node.new()), {"gold": 1})
	assert_bool(bool(TutorialManager.guide_flags.get("collected", false))).is_true()
	assert_bool(bool(TutorialManager.guide_flags.get("collected_gold", false))).is_true()
	var saved := TutorialManager.get_save_data()
	TutorialManager.reset()
	assert_bool(TutorialManager.guide_flags.has("collected")).is_false()
	TutorialManager.load_save_data(saved)
	assert_bool(bool(TutorialManager.guide_flags.get("collected_gold", false))).is_true()

func test_the_guide_state_travels_in_the_save() -> void:
	_start()
	TutorialManager.skip_guide()
	TutorialManager.mark_help_seen("callout_objective")
	var data: Dictionary = TutorialManager.get_save_data()
	TutorialManager.reset()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_PENDING)
	TutorialManager.load_save_data(data)
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_SKIPPED)
	assert_array(TutorialManager.helps_seen).contains_exactly(["callout_objective"])

func test_an_old_save_that_saw_the_old_intro_does_not_repeat_the_guide() -> void:
	TutorialManager.load_save_data({"intro_seen": true, "tips_seen": []})
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_DONE)
	TutorialManager.load_save_data({"intro_seen": false})
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_PENDING)

func test_step_two_points_at_the_always_visible_build_button() -> void:
	assert_str(TutorialManager.step_target("open_build")).is_equal("build_button")
	var menu: CanvasLayer = load("res://scenes/ui/ConstructionMenu.tscn").instantiate()
	add_child(menu)
	_nodes.append(menu)
	var target: Control = HelpTargets.control(get_tree(), "build_button")
	assert_object(target).is_not_null()
	assert_bool(target.is_in_group("hud_build_button")).is_true()

func test_garbage_in_the_guide_keys_is_harmless() -> void:
	TutorialManager.load_save_data({"intro_seen": true, "guide_state": 7, "guide_baseline": "x", "helps_seen": "y"})
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_DONE)
	assert_array(TutorialManager.helps_seen).is_empty()
