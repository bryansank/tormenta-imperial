extends GdUnitTestSuite
## La primera escaramuza en TutorialManager (docs/15-combat.md §4): la marca
## "ya se gano una" que viaja en la partida, y el consejo que senala ☰ MENU >
## ESCARAMUZAS al salir la primera unidad del cuartel. Una vez, como todos.
##
## EventBus se escucha conectando a mano: monitor_signals() libera lo que vigila.

const HelpCatalog := preload("res://scripts/ui/HelpCatalog.gd")

var _saved: Dictionary = {}
var _tips: Array = []

func before_test() -> void:
	_saved = TutorialManager.get_save_data()
	TutorialManager.reset()
	_tips.clear()
	EventBus.tutorial_tip_requested.connect(_collect)

func after_test() -> void:
	EventBus.tutorial_tip_requested.disconnect(_collect)
	TutorialManager.load_save_data(_saved)

func _collect(tip_id: String, _title: String, _body: String) -> void:
	_tips.append(tip_id)

# ── El consejo ───────────────────────────────────────────────────────

func test_the_first_unit_points_at_the_skirmish_once_and_before_upkeep() -> void:
	EventBus.unit_trained.emit("infantry")
	EventBus.unit_trained.emit("infantry")
	assert_array(_tips).contains_exactly(["first_sortie", "upkeep"])

func test_it_is_not_offered_once_the_first_sortie_is_won() -> void:
	EventBus.expedition_ended.emit(Expedition.RESULT_WON, {}, {})
	EventBus.unit_trained.emit("infantry")
	assert_array(_tips).contains_exactly(["upkeep"])

func test_the_tip_points_at_the_menu_button_in_the_army_section() -> void:
	assert_bool(HelpCatalog.has("first_sortie")).is_true()
	assert_str(HelpCatalog.kind("first_sortie")).is_equal("tip")
	assert_str(HelpCatalog.category("first_sortie")).is_equal(HelpCatalog.CAT_ARMY)
	assert_str(HelpCatalog.target("first_sortie")).is_equal("menu_button")

func test_its_texts_exist_in_both_languages_with_a_touch_variant() -> void:
	for locale in ["es", "en"]:
		var table: Dictionary = Tr._STRINGS[locale]
		for key in ["TUT_TIP_FIRST_SORTIE_TITLE", "TUT_TIP_FIRST_SORTIE_BODY", "TUT_TIP_FIRST_SORTIE_BODY_TOUCH",
				"OBJ_DO_FIRST_SORTIE", "OBJ_WHY_FIRST_SORTIE", "OBJ_ROUTE_FIRST_SORTIE"]:
			assert_str(String(table.get(key, ""))).override_failure_message(
				"%s sin texto en %s" % [key, locale]).is_not_empty()
	assert_str(Tr._STRINGS["es"]["TUT_TIP_FIRST_SORTIE_BODY_TOUCH"]).is_not_equal(Tr._STRINGS["es"]["TUT_TIP_FIRST_SORTIE_BODY"])

## La primera escaramuza no tiene mapa: el consejo del mapa espera a la primera
## expedicion de verdad.
func test_the_map_tip_waits_for_a_real_expedition() -> void:
	var saved_army: Dictionary = ArmyManager.get_save_data()
	CombatManager.reset()
	ArmyManager.load_save_data({"units": {"infantry": 1}, "training": [], "upkeep_accum": 0.0})
	CombatManager.launch_expedition({"infantry": 1}, 5, true)
	assert_array(_tips).not_contains(["expedition_map"])
	CombatManager.end_encounter()
	CombatManager.reset()
	ArmyManager.load_save_data(saved_army)

# ── La marca ─────────────────────────────────────────────────────────

func test_only_a_won_sortie_counts() -> void:
	EventBus.expedition_ended.emit(Expedition.RESULT_LOST, {}, {})
	EventBus.expedition_ended.emit(Expedition.RESULT_ABANDONED, {}, {})
	assert_bool(TutorialManager.is_first_sortie_done()).is_false()
	EventBus.expedition_ended.emit(Expedition.RESULT_WON, {}, {})
	assert_bool(TutorialManager.is_first_sortie_done()).is_true()

func test_the_mark_survives_save_and_load_and_loading_twice() -> void:
	EventBus.expedition_ended.emit(Expedition.RESULT_WON, {}, {})
	var data: Variant = JSON.parse_string(JSON.stringify(TutorialManager.get_save_data()))
	TutorialManager.reset()
	assert_bool(TutorialManager.is_first_sortie_done()).is_false()
	TutorialManager.load_save_data(data)
	TutorialManager.load_save_data(data)
	assert_bool(TutorialManager.is_first_sortie_done()).is_true()
	# Y "no hecha" tambien se guarda como tal.
	TutorialManager.reset()
	var fresh: Dictionary = TutorialManager.get_save_data()
	TutorialManager.first_sortie_done = true
	TutorialManager.load_save_data(fresh)
	assert_bool(TutorialManager.is_first_sortie_done()).is_false()

func test_reset_forgets_it_without_telling_anyone() -> void:
	TutorialManager.first_sortie_done = true
	TutorialManager.reset()
	assert_bool(TutorialManager.is_first_sortie_done()).is_false()
	assert_array(_tips).is_empty()

## Un guardado de antes de esta marca: si ya vio el consejo del mapa es que ya
## salio de expedicion, y no se le vuelve a pedir la primera.
func test_an_old_save_derives_it_from_the_map_tip() -> void:
	TutorialManager.load_save_data({"intro_seen": true, "tips_seen": ["expedition_map"]})
	assert_bool(TutorialManager.is_first_sortie_done()).is_true()
	TutorialManager.load_save_data({"intro_seen": true, "tips_seen": ["upkeep"]})
	assert_bool(TutorialManager.is_first_sortie_done()).is_false()
	TutorialManager.load_save_data({"first_sortie_done": "si"})
	assert_bool(TutorialManager.is_first_sortie_done()).is_false()
