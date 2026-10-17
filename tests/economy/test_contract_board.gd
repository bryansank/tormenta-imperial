extends GdUnitTestSuite
## El tablon de encargos (ContractBoard): modelo puro, sin escena. Tres huecos
## (Regencia, vecinos, contrabandista), plazos que corren, premios fijos desde
## que el encargo aparece, la reputacion solo en Gobernador y un guardado que
## vuelve igual.
##
## Sin escribir en user://: solo el modelo y GameConfig (que se deja como estaba).

const BoardScript := preload("res://scripts/economy/ContractBoard.gd")

const SEED := 20261014

var _dev_saved: bool

func before_test() -> void:
	# Tiempos reales: el modelo pasa sus plazos por GameConfig.get_duration.
	_dev_saved = GameConfig.dev_mode
	GameConfig.dev_mode = false

func after_test() -> void:
	GameConfig.dev_mode = _dev_saved

func _ctx(era: int = 1, extra: Dictionary = {}) -> Dictionary:
	var unlocked := ["gold", "wood", "food"]
	if era >= 2:
		unlocked.append_array(["steel", "planks", "ingots", "beams"])
	if era >= 3:
		unlocked.append_array(["oil", "fuel"])
	var ctx := {"era": era, "unlocked": unlocked, "colonists_ok": false, "morale_ok": true,
		"tithe_discount_ok": true, "reputation": false}
	ctx.merge(extra, true)
	return ctx

func _board():
	return BoardScript.create(SEED)

## Avanza hasta que la fuente tenga encargo (o se agote el tiempo).
func _until_offered(board, source: String, ctx: Dictionary, max_seconds: float = 3600.0) -> Dictionary:
	var t := 0.0
	while t < max_seconds and not board.has_contract(source):
		board.advance(1.0, ctx)
		t += 1.0
	return board.get_contract(source)

func test_a_new_board_has_three_empty_slots() -> void:
	var board = _board()
	for source in BoardScript.SOURCES:
		assert_bool(board.has_contract(source)).is_false()
		assert_float(float(board.cooldowns[source])).is_greater(0.0)
	assert_int(BoardScript.SOURCES.size()).is_equal(3)

func test_the_regency_waits_for_era_2() -> void:
	var board = _board()
	for i in range(3600):
		board.advance(1.0, _ctx(1))
	assert_bool(board.has_contract("regency")).is_false()
	var contract := _until_offered(board, "regency", _ctx(2))
	assert_bool(contract.is_empty()).is_false()

func test_an_offered_contract_has_ask_reward_and_a_clock() -> void:
	var board = _board()
	var events: Array = []
	var t := 0.0
	while t < 600.0 and not board.has_contract("neighbors"):
		events.append_array(board.advance(1.0, _ctx(1)))
		t += 1.0
	var contract: Dictionary = board.get_contract("neighbors")
	assert_bool((contract["ask"] as Dictionary).is_empty()).is_false()
	assert_bool((contract["reward"] as Dictionary).is_empty()).is_false()
	assert_float(float(contract["seconds_left"])).is_equal(float(contract["seconds_total"]))
	var offered := events.filter(func(e): return e["type"] == "offered" and e["source"] == "neighbors")
	assert_int(offered.size()).is_equal(1)

func test_the_reward_does_not_change_while_the_clock_runs() -> void:
	var board = _board()
	var contract := _until_offered(board, "smuggler", _ctx(1))
	var reward: Dictionary = (contract["reward"] as Dictionary).duplicate()
	board.advance(30.0, _ctx(1))
	assert_dict(board.get_contract("smuggler")["reward"]).is_equal(reward)

func test_a_contract_not_delivered_in_time_expires_and_frees_the_slot() -> void:
	var board = _board()
	var contract := _until_offered(board, "neighbors", _ctx(1))
	var events: Array = board.advance(float(contract["seconds_total"]) + 1.0, _ctx(1))
	var expired := events.filter(func(e): return e["type"] == "expired")
	assert_int(expired.size()).is_equal(1)
	assert_bool(board.has_contract("neighbors")).is_false()
	assert_float(float(board.cooldowns["neighbors"])).is_equal(GameConfig.get_duration(GameConfig.contract_cooldown))
	assert_int(board.failed_total).is_equal(1)

func test_colonist_failing_does_not_touch_reputation() -> void:
	var board = _board()
	var contract := _until_offered(board, "neighbors", _ctx(1))
	board.advance(float(contract["seconds_total"]) + 1.0, _ctx(1))
	assert_int(int(board.reputation["neighbors"])).is_equal(0)

func test_governor_failing_lowers_reputation_and_the_next_reward() -> void:
	var gov := _ctx(1, {"reputation": true})
	var board = _board()
	var first := _until_offered(board, "smuggler", gov)
	board.advance(float(first["seconds_total"]) + 1.0, gov)
	assert_int(int(board.reputation["smuggler"])).is_equal(-1)
	assert_float(board.reward_mult("smuggler")).is_equal_approx(1.0 - GameConfig.contract_reputation_step, 0.001)
	# Mismo encargo sorteado a mano: con reputacion -1 paga menos.
	var template: Dictionary = GameConfig.contract_templates["smuggler"][0]
	var cut: Dictionary = board.build_contract("smuggler", template, gov)
	var full: Dictionary = board.build_contract("smuggler", template, _ctx(1))
	assert_int(int(cut["reward"]["gold"])).is_less(int(full["reward"]["gold"]))

func test_reputation_has_a_floor_and_delivering_recovers_it() -> void:
	var gov := _ctx(1, {"reputation": true})
	var board = _board()
	for i in range(6):
		_until_offered(board, "smuggler", gov)
		board.discard("smuggler", gov)
	assert_int(int(board.reputation["smuggler"])).is_equal(GameConfig.contract_reputation_min)
	_until_offered(board, "smuggler", gov)
	var events: Array = board.deliver("smuggler", gov)
	assert_str(String(events[0]["type"])).is_equal("delivered")
	assert_int(int(board.reputation["smuggler"])).is_equal(GameConfig.contract_reputation_min + 1)

func test_delivering_returns_the_reward_that_was_shown() -> void:
	var board = _board()
	var contract := _until_offered(board, "smuggler", _ctx(1))
	var events: Array = board.deliver("smuggler", _ctx(1))
	assert_int(events.size()).is_equal(1)
	assert_dict(events[0]["reward"]).is_equal(contract["reward"])
	assert_bool(board.has_contract("smuggler")).is_false()
	assert_int(board.delivered_total).is_equal(1)
	assert_array(board.deliver("smuggler", _ctx(1))).is_empty()

func test_without_a_tithe_the_regency_pays_gold() -> void:
	var board = _board()
	var contract := _until_offered(board, "regency", _ctx(2, {"tithe_discount_ok": false}))
	assert_bool((contract["reward"] as Dictionary).has("tithe_discount")).is_false()
	assert_int(int(contract["reward"].get("gold", 0))).is_greater(0)

func test_with_a_tithe_the_regency_offers_a_discount() -> void:
	var board = _board()
	var contract := _until_offered(board, "regency", _ctx(2))
	assert_int(int(contract["reward"].get("tithe_discount", 0))).is_greater(0)

func test_nothing_is_asked_that_is_still_locked() -> void:
	var ctx := _ctx(1)
	for source in BoardScript.SOURCES:
		for template in BoardScript.fitting_templates(source, ctx):
			for res in template["ask"]:
				assert_bool(String(res) in ctx["unlocked"]).is_true()

func test_no_colonists_or_morale_rewards_when_they_cannot_be_paid() -> void:
	var ctx := _ctx(1, {"colonists_ok": false, "morale_ok": false})
	for template in BoardScript.fitting_templates("neighbors", ctx):
		assert_bool((template["reward"] as Dictionary).has("colonists")).is_false()
		assert_bool((template["reward"] as Dictionary).has("morale")).is_false()

func test_a_later_era_asks_and_pays_more() -> void:
	var board = _board()
	var template: Dictionary = GameConfig.contract_templates["smuggler"][1]
	var early: Dictionary = board.build_contract("smuggler", template, _ctx(2))
	var late: Dictionary = board.build_contract("smuggler", template, _ctx(3))
	var res: String = String(template["ask"].keys()[0])
	assert_int(int(late["ask"][res])).is_greater(int(early["ask"][res]))

func test_the_same_seed_gives_the_same_board() -> void:
	var a = BoardScript.create(SEED)
	var b = BoardScript.create(SEED)
	for i in range(1200):
		a.advance(1.0, _ctx(2))
		b.advance(1.0, _ctx(2))
	assert_dict(a.to_dict()).is_equal(b.to_dict())

func test_save_round_trip() -> void:
	var board = _board()
	for i in range(900):
		board.advance(1.0, _ctx(2))
	var data: Dictionary = JSON.parse_string(JSON.stringify(board.to_dict()))
	var loaded = BoardScript.from_dict(data)
	assert_dict(loaded.to_dict()).is_equal(board.to_dict())

func test_an_old_or_broken_save_gives_a_fresh_board() -> void:
	var fresh = BoardScript.from_dict({})
	for source in BoardScript.SOURCES:
		assert_bool(fresh.has_contract(source)).is_false()
	var broken = BoardScript.from_dict({"slots": {"neighbors": {"ask": "x"}}, "reputation": {"smuggler": -99}})
	assert_bool(broken.has_contract("neighbors")).is_false()
	assert_int(int(broken.reputation["smuggler"])).is_equal(GameConfig.contract_reputation_min)
