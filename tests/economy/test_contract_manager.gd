extends GdUnitTestSuite
## ContractManager: cobra lo pedido y paga el premio, carga idempotente, reset,
## guardado viejo sin clave "contracts", Sandbox sin tablon y el paso de
## ¿QUE HACER?. Los autoloads tocados se apartan y se devuelven.

const Objectives := preload("res://scripts/services/Objectives.gd")

var _contracts_saved: Dictionary = {}
var _rank_saved: Dictionary = {}
var _mode_saved: Dictionary = {}
var _res_saved: Dictionary = {}
var _delivered: Array = []

## Un tablon guardado con un encargo del contrabandista: 10 de madera -> 50 de oro.
const SMUGGLER_SAVE := {
	"v": 1,
	"slots": {
		"smuggler": {"id": 7, "source": "smuggler", "template": "sm_wood",
			"ask": {"wood": 10}, "reward": {"gold": 50},
			"seconds_total": 240.0, "seconds_left": 200.0},
	},
	"cooldowns": {"regency": 45.0, "neighbors": 30.0, "smuggler": 0.0},
	"reputation": {"regency": 0, "neighbors": 0, "smuggler": 0},
	"next_id": 8,
}

func before_test() -> void:
	_contracts_saved = ContractManager.get_save_data()
	_rank_saved = RankManager.get_save_data()
	_mode_saved = GameMode.get_save_data()
	_res_saved = {
		"gold": ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"wood": ResourceManager.get_amount(ResourceManager.Type.WOOD),
	}
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.COLONIST)
	_delivered.clear()
	EventBus.contract_delivered.connect(_on_delivered)

func after_test() -> void:
	EventBus.contract_delivered.disconnect(_on_delivered)
	ResourceManager.set_amounts(_res_saved)
	GameMode.load_save_data(_mode_saved)
	RankManager.load_save_data(_rank_saved)
	ContractManager.load_save_data(_contracts_saved)

func _on_delivered(source: String, _contract: Dictionary, reward: Dictionary) -> void:
	_delivered.append([source, reward])

func test_loading_twice_is_the_same_as_loading_once() -> void:
	ContractManager.load_save_data(SMUGGLER_SAVE.duplicate(true))
	var once: Dictionary = ContractManager.get_save_data()
	ContractManager.load_save_data(SMUGGLER_SAVE.duplicate(true))
	assert_dict(ContractManager.get_save_data()).is_equal(once)

func test_an_old_save_without_contracts_is_a_fresh_board() -> void:
	ContractManager.load_save_data(SMUGGLER_SAVE.duplicate(true))
	ContractManager.load_save_data({})
	for source in ["regency", "neighbors", "smuggler"]:
		assert_bool(ContractManager.get_contract(source).is_empty()).is_true()

func test_reset_throws_the_board_away() -> void:
	ContractManager.load_save_data(SMUGGLER_SAVE.duplicate(true))
	ContractManager.reset()
	assert_bool(ContractManager.get_contract("smuggler").is_empty()).is_true()

func test_delivering_takes_what_they_ask_and_pays_the_reward() -> void:
	ResourceManager.set_amounts({"gold": 0, "wood": 100})
	ContractManager.load_save_data(SMUGGLER_SAVE.duplicate(true))
	assert_bool(ContractManager.can_deliver("smuggler")).is_true()
	assert_bool(ContractManager.deliver("smuggler")).is_true()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.WOOD)).is_equal(90)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(50)
	assert_bool(ContractManager.get_contract("smuggler").is_empty()).is_true()
	assert_int(_delivered.size()).is_equal(1)
	assert_dict(_delivered[0][1]).is_equal({"gold": 50})

func test_without_enough_nothing_moves() -> void:
	ResourceManager.set_amounts({"gold": 0, "wood": 4})
	ContractManager.load_save_data(SMUGGLER_SAVE.duplicate(true))
	assert_dict(ContractManager.missing_for("smuggler")).is_equal({"wood": 6})
	assert_bool(ContractManager.deliver("smuggler")).is_false()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.WOOD)).is_equal(4)
	assert_bool(ContractManager.get_contract("smuggler").is_empty()).is_false()

func test_discarding_frees_the_slot_without_paying() -> void:
	ResourceManager.set_amounts({"gold": 0, "wood": 100})
	ContractManager.load_save_data(SMUGGLER_SAVE.duplicate(true))
	assert_bool(ContractManager.discard("smuggler")).is_true()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(0)
	assert_int(_delivered.size()).is_equal(0)

func test_sandbox_has_no_board_and_campaign_does() -> void:
	assert_bool(GameMode.contracts_enabled()).is_true()
	GameMode.begin_run(GameMode.Mode.SANDBOX, GameMode.Tier.COLONIST)
	assert_bool(GameMode.contracts_enabled()).is_false()
	ContractManager.load_save_data(SMUGGLER_SAVE.duplicate(true))
	ResourceManager.set_amounts({"wood": 100})
	assert_bool(ContractManager.can_deliver("smuggler")).is_false()
	assert_dict(Objectives.contract_step()).is_empty()

func test_what_to_do_points_at_a_deliverable_contract() -> void:
	ResourceManager.set_amounts({"gold": 0, "wood": 100})
	ContractManager.load_save_data(SMUGGLER_SAVE.duplicate(true))
	var step: Dictionary = Objectives.contract_step()
	assert_str(String(step.get("kind", ""))).is_equal("contract")
	assert_str(String(step.get("id", ""))).is_equal("smuggler")
	var text: Dictionary = Objectives.describe(step)
	assert_str(String(text["title"])).contains(Tr.t("CONTRACT_SRC_SMUGGLER"))

func test_the_context_follows_the_game() -> void:
	var ctx: Dictionary = ContractManager.context()
	assert_bool("gold" in ctx["unlocked"]).is_true()
	assert_bool(bool(ctx["reputation"])).is_false()
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	assert_bool(bool(ContractManager.context()["reputation"])).is_true()
