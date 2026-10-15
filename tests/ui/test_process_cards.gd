extends GdUnitTestSuite
## Las tarjetas de proceso (fix/partidas-bryan, 2026-10-14): iconos y cifras,
## botones x1 / x5 / MAX del tamano de un dedo, y el Nucleo en tres grupos.
## Escrito sin ejecutar (regla del dueno: un solo pase de pruebas al final).

const ProcessCard := preload("res://scripts/ui/ProcessCard.gd")

var _saved_resources: Dictionary = {}

func before_test() -> void:
	_saved_resources = {}
	for type in ResourceManager.get_all():
		_saved_resources[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)

func after_test() -> void:
	ResourceManager.set_amounts(_saved_resources)

func _proc() -> Dictionary:
	return {"id": "wood_planks", "name": "PROC_WOOD_PLANKS", "duration": 30.0,
		"cost": {"wood": 20}, "produces": {"wood": 35}}

func _card(proc: Dictionary) -> PanelContainer:
	var card: PanelContainer = auto_free(ProcessCard.new())
	card.setup(proc, ProcessCard.Kind.PROCESS, null, UITheme.ACCENT)
	add_child(card)
	return card

func test_a_card_shows_cost_output_time_and_batch_buttons() -> void:
	ResourceManager.set_amounts({"wood": 200, "food": 0})
	var card := _card(_proc())
	assert_object(card.find_child("Cost", true, false)).is_not_null()
	assert_object(card.find_child("Produces", true, false)).is_not_null()
	assert_object(card.find_child("Time", true, false)).is_not_null()
	assert_int(card.batch_buttons().size()).is_equal(GameConfig.process_batch_sizes.size() + 1)

func test_busy_disables_every_batch_button() -> void:
	ResourceManager.set_amounts({"wood": 200, "food": 0})
	var card := _card(_proc())
	card.refresh(true)
	for btn in card.batch_buttons():
		assert_bool((btn as Button).disabled).is_true()

func test_x5_is_off_when_only_two_can_be_paid() -> void:
	ResourceManager.set_amounts({"wood": 45, "food": 0})
	var card := _card(_proc())
	card.refresh(false)
	var x1: Button = card.find_child("Batch_1", true, false)
	var x5: Button = card.find_child("Batch_5", true, false)
	var mx: Button = card.find_child("BatchMax", true, false)
	assert_bool(x1.disabled).is_false()
	assert_bool(x5.disabled).is_true()
	assert_str(mx.text).contains("2")

func test_the_plain_text_keeps_workers_for_hand_mining() -> void:
	var mining := {"name": "PROC_MINE_GOLD", "produces": {"gold": 12}, "duration": 45.0}
	var text: String = ProcessCard.card_text(mining, 2)
	assert_str(text).contains(Tr.t("LBL_WORKERS_SHORT") % 2)
