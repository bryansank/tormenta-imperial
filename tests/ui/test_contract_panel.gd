extends GdUnitTestSuite
## ENCARGOS (ContractPanel): tres tarjetas, una por fuente; la del encargo
## enseña lo pedido, el premio y ENTREGAR (apagado si falta algo); el menu ☰
## lo lista en COLONIA.

const PanelScene := preload("res://scenes/ui/ContractPanel.tscn")

var _contracts_saved: Dictionary = {}
var _res_saved: Dictionary = {}
var _mode_saved: Dictionary = {}

const SAVE := {
	"v": 1,
	"slots": {
		"neighbors": {"id": 3, "source": "neighbors", "template": "nb_wood",
			"ask": {"wood": 60}, "reward": {"morale": 8},
			"seconds_total": 240.0, "seconds_left": 120.0},
	},
	"cooldowns": {"regency": 45.0, "neighbors": 0.0, "smuggler": 90.0},
	"reputation": {"regency": 0, "neighbors": 0, "smuggler": 0},
	"next_id": 4,
}

func before_test() -> void:
	_contracts_saved = ContractManager.get_save_data()
	_mode_saved = GameMode.get_save_data()
	_res_saved = {"wood": ResourceManager.get_amount(ResourceManager.Type.WOOD)}
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.COLONIST)
	ContractManager.load_save_data(SAVE.duplicate(true))

func after_test() -> void:
	ResourceManager.set_amounts(_res_saved)
	GameMode.load_save_data(_mode_saved)
	ContractManager.load_save_data(_contracts_saved)

func _open_panel() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(PanelScene.instantiate())
	add_child(panel)
	panel.open()
	return panel

func test_three_cards_one_per_source() -> void:
	var panel := _open_panel()
	for source in ["regency", "neighbors", "smuggler"]:
		assert_object(panel.find_child("Card_" + source, true, false)).is_not_null()
	panel._close()
	assert_bool(panel.is_open()).is_false()

func test_deliver_is_off_while_something_is_missing() -> void:
	ResourceManager.set_amounts({"wood": 10})
	var panel := _open_panel()
	var card: Node = panel.find_child("Card_neighbors", true, false)
	var deliver: Button = card.find_child("Deliver", true, false)
	assert_bool(deliver.disabled).is_true()
	ResourceManager.set_amounts({"wood": 100})
	panel.refresh()
	card = panel.find_child("Card_neighbors", true, false)
	deliver = card.find_child("Deliver", true, false)
	assert_bool(deliver.disabled).is_false()
	panel._close()

func test_the_reward_is_shown_with_its_icon() -> void:
	var panel := _open_panel()
	var card: Node = panel.find_child("Card_neighbors", true, false)
	assert_object(card.find_child("Chip_morale", true, false)).is_not_null()
	# Una tarjeta vacia dice cuando llega el siguiente (o en que era).
	var regency: Node = panel.find_child("Card_regency", true, false)
	assert_object(regency.find_child("Wait", true, false)).is_not_null()
	panel._close()

func test_the_pause_menu_lists_the_contracts_entry() -> void:
	var found := false
	for entry in load("res://scripts/ui/PauseMenu.gd").COLONY_ENTRIES:
		if entry[2] == "ContractPanel":
			found = true
	assert_bool(found).is_true()
