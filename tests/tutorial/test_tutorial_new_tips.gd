extends GdUnitTestSuite
## Los consejos de primera vez que faltaban: Cuartel, mercado, arbol
## tecnologico, mapa de expedicion, sueldo de la tropa, consumo de la gente y la
## Auditoria Final. Misma regla que los demas: cada uno sale UNA vez por partida,
## y lo visto viaja en el guardado (TutorialManager.get_save_data()).
##
## EventBus se escucha conectando a mano: monitor_signals() libera lo que vigila.

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

const NEW_TIPS := ["barracks", "market", "tech_tree", "expedition_map", "upkeep", "consumption", "final_audit"]

func test_every_new_tip_exists_with_translated_text() -> void:
	for tip_id in NEW_TIPS:
		assert_bool(TutorialManager.TIPS.has(tip_id)).override_failure_message(tip_id).is_true()
		var keys: Dictionary = TutorialManager.TIPS[tip_id]
		assert_str(Tr.t(keys["title"])).is_not_equal(keys["title"])
		assert_str(Tr.t(keys["body"])).is_not_equal(keys["body"])

func test_the_first_barracks_explains_the_army_once() -> void:
	var barracks: Resource = load("res://data/buildings/barracks.tres")
	var house: Resource = load("res://data/buildings/house.tres")
	TutorialManager._on_building_placed(house, Vector2i(1, 1))
	assert_array(_tips).is_empty()
	TutorialManager._on_building_placed(barracks, Vector2i(2, 2))
	TutorialManager._on_building_placed(barracks, Vector2i(5, 5))
	assert_array(_tips).contains_exactly(["barracks"])

func test_opening_the_market_and_the_tech_tree_explains_them() -> void:
	var market := CanvasLayer.new()
	market.name = "MarketPanel"
	var tech := CanvasLayer.new()
	tech.name = "TechTreePanel"
	var other := CanvasLayer.new()
	other.name = "SettingsPanel"
	UIManager.window_opened.emit(other)
	UIManager.window_opened.emit(market)
	UIManager.window_opened.emit(market)
	UIManager.window_opened.emit(tech)
	market.free()
	tech.free()
	other.free()
	assert_array(_tips).contains_exactly(["market", "tech_tree"])

func test_the_first_expedition_explains_the_map() -> void:
	EventBus.expedition_started.emit(1, 12)
	EventBus.expedition_started.emit(2, 12)
	assert_array(_tips).contains_exactly(["expedition_map"])

func test_the_first_trained_unit_explains_upkeep_before_it_bites() -> void:
	EventBus.unit_trained.emit("infantry")
	EventBus.army_upkeep_unpaid.emit(10)
	assert_array(_tips).contains_exactly(["upkeep"])

func test_unpaid_upkeep_explains_it_if_nothing_did_first() -> void:
	EventBus.army_upkeep_unpaid.emit(10)
	assert_array(_tips).contains_exactly(["upkeep"])

func test_the_first_shortage_explains_consumption() -> void:
	EventBus.consumption_failed.emit("wood")
	EventBus.consumption_failed.emit("gold")
	assert_array(_tips).contains_exactly(["consumption"])

func test_summoning_the_audit_explains_it() -> void:
	EventBus.final_audit_summoned.emit(4, 1)
	EventBus.final_audit_summoned.emit(4, 2)
	assert_array(_tips).contains_exactly(["final_audit"])

func test_the_new_tips_travel_in_the_save() -> void:
	for tip_id in NEW_TIPS:
		TutorialManager.offer_tip(tip_id)
	var data: Dictionary = TutorialManager.get_save_data()
	TutorialManager.reset()
	TutorialManager.load_save_data(data)
	for tip_id in NEW_TIPS:
		assert_bool(TutorialManager.has_seen_tip(tip_id)).is_true()
