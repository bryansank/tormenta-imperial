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
const HelpTargets := preload("res://scripts/ui/HelpTargets.gd")

var _saved: Dictionary = {}
var _steps: Array = []
var _finished: Array = []
var _nodes: Array = []

func before_test() -> void:
	_saved = TutorialManager.get_save_data()
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

func test_an_empty_island_starts_at_build() -> void:
	assert_str(TutorialManager.derive_step({})).is_equal("open_build")

func test_the_list_open_asks_for_the_sawmill() -> void:
	assert_str(TutorialManager.derive_step({"menu_open": true})).is_equal("pick_sawmill")

func test_holding_the_sawmill_asks_for_the_forest() -> void:
	assert_str(TutorialManager.derive_step({"placing": "sawmill"})).is_equal("place_sawmill")

func test_holding_something_else_goes_back_to_build() -> void:
	# El jugador eligio una casa primero: el tutorial no se rompe, pide CONSTRUIR
	# otra vez (y senalara el aserradero al abrir la lista).
	assert_str(TutorialManager.derive_step({"placing": "house"})).is_equal("open_build")

func test_a_sawmill_under_construction_waits() -> void:
	assert_str(TutorialManager.derive_step({"sawmills": 1})).is_equal("wait_sawmill")

func test_a_built_sawmill_asks_for_a_house() -> void:
	var f := {"sawmills": 1, "sawmills_built": 1}
	assert_str(TutorialManager.derive_step(f)).is_equal("open_house")
	f["menu_open"] = true
	assert_str(TutorialManager.derive_step(f)).is_equal("pick_house")
	f["placing"] = "house"
	assert_str(TutorialManager.derive_step(f)).is_equal("place_house")

func test_a_house_built_first_is_not_lost() -> void:
	# Fuera de orden: casa antes que aserradero. El paso sigue pidiendo el
	# aserradero, y al tenerlo ya no pide la casa.
	assert_str(TutorialManager.derive_step({"houses": 1})).is_equal("open_build")
	assert_str(TutorialManager.derive_step({"houses": 1, "sawmills": 1, "sawmills_built": 1})).is_equal("done")

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
	assert_str(TutorialManager.current_step()).is_equal("open_house")
	_place(HOUSE, Vector2i(6, 6))
	EventBus.building_placed.emit(HOUSE, Vector2i(6, 6))
	assert_str(TutorialManager.current_step()).is_equal("done")
	TutorialManager.finish_guide()
	remove_child(menu)
	menu.free()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_DONE)
	assert_array(_finished).contains_exactly([false])
	assert_array(_steps).contains(["open_build", "pick_sawmill", "place_sawmill", "wait_sawmill", "open_house", "done"])

func test_cancelling_the_placement_goes_back_one_step() -> void:
	_start()
	EventBus.building_selected_for_placement.emit(SAWMILL)
	assert_str(TutorialManager.current_step()).is_equal("place_sawmill")
	EventBus.building_placement_cancelled.emit()
	assert_str(TutorialManager.current_step()).is_equal("open_build")

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
	assert_str(TutorialManager.current_step()).is_equal("open_build")

# ── Guardado: vuelve donde estaba ────────────────────────────────────

func test_an_active_guide_resumes_on_load_at_the_derived_step() -> void:
	_start()
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
