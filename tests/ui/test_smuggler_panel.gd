extends GdUnitTestSuite
## EL BARCO (SmugglerPanel, feat/edificios-economia): una tarjeta por oferta,
## el boton apagado cuando falta oro, "Hecho" en lo vendido y el reloj sin
## barco. El panel solo lee EconomyManager.
##
## Escrita sin correr (regla de Bryan: un solo pase de pruebas al final).

const PanelScript := preload("res://scripts/ui/SmugglerPanel.gd")

var _panel: CanvasLayer
var _saved_economy: Dictionary = {}
var _saved_amounts: Dictionary = {}

func before_test() -> void:
	_saved_economy = EconomyManager.get_save_data()
	_saved_amounts = {}
	for type in ResourceManager.get_all():
		_saved_amounts[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	_panel = PanelScript.new()
	add_child(_panel)

func after_test() -> void:
	if is_instance_valid(_panel):
		_panel.close()
		_panel.free()
	EconomyManager.load_save_data(_saved_economy)
	ResourceManager.set_amounts(_saved_amounts)

func _dock(offers: Array) -> void:
	EconomyManager.load_save_data({"ship": {"wait_left": 300.0, "docked_left": 60.0,
		"offers": offers, "visits": 1}})

func _cards() -> Array:
	var list := _panel.find_child("Offers", true, false)
	return list.get_children() if list != null else []

func test_one_card_per_offer() -> void:
	ResourceManager.set_amounts({"gold": 1000, "wood": 100})
	_dock([
		{"kind": "parts", "give": {"parts": 2}, "price": 120, "sold": false},
		{"kind": "material", "give": {"planks": 8}, "price": 104, "sold": false},
		{"kind": "buy", "ask": {"wood": 40}, "pay": 130, "sold": false},
	])
	_panel.open()
	await get_tree().process_frame
	assert_int(_cards().size()).is_equal(3)
	for card in _cards():
		var take := (card as Node).find_child("Take", true, false) as Button
		assert_object(take).is_not_null()
		assert_bool(take.disabled).is_false()

func test_short_of_gold_greys_the_deal_and_sold_says_done() -> void:
	ResourceManager.set_amounts({"gold": 10})
	_dock([
		{"kind": "material", "give": {"planks": 8}, "price": 104, "sold": false},
		{"kind": "material", "give": {"beams": 4}, "price": 208, "sold": true},
	])
	_panel.open()
	await get_tree().process_frame
	var cards := _cards()
	var first := (cards[0] as Node).find_child("Take", true, false) as Button
	var second := (cards[1] as Node).find_child("Take", true, false) as Button
	assert_bool(first.disabled).is_true()
	assert_bool(second.disabled).is_true()
	assert_str(second.text).is_equal(Tr.t("BTN_SMUGGLER_DONE"))

func test_without_a_ship_it_says_so() -> void:
	EconomyManager.load_save_data({})
	_panel.open()
	await get_tree().process_frame
	assert_int(_cards().size()).is_equal(1)
	assert_str((_cards()[0] as Node).name).is_equal("Empty")
