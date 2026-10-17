extends GdUnitTestSuite
## El tablon de salidas (SortieBoard, doc 21 §3): modelo puro. Cuando aparece
## una incursion o una expedicion, que pasa al lanzarla y al volver, la
## avanzadilla que se va con el Diezmo y el guardado (idempotente, con valores
## por defecto para los guardados viejos).
##
## Escrito en la rama feat/escaramuzas SIN EJECUTAR (regla de Bryan: un solo pase
## de pruebas al final).

const BoardScript := preload("res://scripts/combat/SortieBoard.gd")
const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")

func _ctx(raids: bool = true, expeditions: bool = true, outpost: bool = false, era: int = 2) -> Dictionary:
	return {"raids": raids, "expeditions": expeditions, "outpost": outpost, "era": era,
		"blueprint": "", "raid_out": false, "expedition_out": false}

func test_nothing_appears_while_the_board_is_closed() -> void:
	var board: SortieBoard = BoardScript.new()
	var events: Array = board.refresh(0.0, _ctx(false, false), 123)
	assert_array(events).is_empty()
	assert_array(board.offers).is_empty()

func test_one_raid_and_one_expedition_appear_and_no_more() -> void:
	var board: SortieBoard = BoardScript.new()
	assert_array(board.refresh(0.0, _ctx(), 123)).is_not_empty()
	assert_int(board.offers.size()).is_equal(2)
	assert_bool(board.has_kind(Generator.KIND_RAID)).is_true()
	assert_bool(board.has_kind(Generator.KIND_EXPEDITION)).is_true()
	# Un segundo tic no duplica nada.
	assert_array(board.refresh(10.0, _ctx(), 456)).is_empty()
	assert_int(board.offers.size()).is_equal(2)

func test_no_expedition_before_its_era() -> void:
	var board: SortieBoard = BoardScript.new()
	board.refresh(0.0, _ctx(true, false), 123)
	assert_bool(board.has_kind(Generator.KIND_EXPEDITION)).is_false()
	assert_bool(board.has_kind(Generator.KIND_RAID)).is_true()

func test_new_offers_light_the_dot_until_seen() -> void:
	var board: SortieBoard = BoardScript.new()
	board.refresh(0.0, _ctx(), 123)
	assert_bool(board.has_unseen()).is_true()
	board.mark_all_seen()
	assert_bool(board.has_unseen()).is_false()

func test_the_first_raid_with_the_storm_armed_is_the_outpost() -> void:
	var board: SortieBoard = BoardScript.new()
	board.refresh(0.0, _ctx(true, false, true), 123)
	assert_bool(board.has_outpost()).is_true()

func test_the_outpost_leaves_with_the_tithe() -> void:
	var board: SortieBoard = BoardScript.new()
	board.refresh(0.0, _ctx(true, false, true), 123)
	assert_array(board.on_tithe_resolved()).is_not_empty()
	assert_bool(board.has_outpost()).is_false()

func test_taking_an_offer_blocks_its_kind_until_it_comes_back() -> void:
	var board: SortieBoard = BoardScript.new()
	board.refresh(0.0, _ctx(true, false), 123)
	var offer: Dictionary = board.take(int(board.offers[0]["id"]))
	assert_dict(offer).is_not_empty()
	var ctx := _ctx(true, false)
	ctx["raid_out"] = true
	board.refresh(5000.0, ctx, 99)
	assert_bool(board.has_kind(Generator.KIND_RAID)).is_false()

func test_a_won_raid_waits_its_cooldown() -> void:
	var board: SortieBoard = BoardScript.new()
	board.refresh(0.0, _ctx(true, false), 123)
	var offer: Dictionary = board.take(int(board.offers[0]["id"]))
	board.finish(offer, true, 100.0, 240.0)
	board.refresh(200.0, _ctx(true, false), 7)
	assert_bool(board.has_kind(Generator.KIND_RAID)).is_false()
	board.refresh(341.0, _ctx(true, false), 7)
	assert_bool(board.has_kind(Generator.KIND_RAID)).is_true()

func test_a_lost_raid_puts_the_same_offer_back() -> void:
	var board: SortieBoard = BoardScript.new()
	board.refresh(0.0, _ctx(true, false), 123)
	var offer: Dictionary = board.take(int(board.offers[0]["id"]))
	board.finish(offer, false, 100.0, 240.0)
	assert_int(board.offers.size()).is_equal(1)
	assert_int(int(board.offers[0]["seed"])).is_equal(int(offer["seed"]))

func test_banked_loot_keeps_blueprints_and_the_tithe_note() -> void:
	var board: SortieBoard = BoardScript.new()
	var events: Array = board.bank_loot({"blueprints": ["infirmary"], "tithe_pct": 10})
	assert_bool(board.has_blueprint("infirmary")).is_true()
	assert_int(board.tithe_cut_pct).is_equal(10)
	var kinds: Array = events.map(func(e): return String(e["e"]))
	assert_array(kinds).contains(["blueprint_gained", "tithe_cut_gained"])
	# El mismo plano dos veces no se repite.
	board.bank_loot({"blueprints": ["infirmary"]})
	assert_int(board.blueprints.size()).is_equal(1)

func test_save_round_trip_is_idempotent() -> void:
	var board: SortieBoard = BoardScript.new()
	board.refresh(0.0, _ctx(), 123)
	board.take(int(board.offers[0]["id"]))
	board.bank_loot({"blueprints": ["scrapyard"], "tithe_pct": 10})
	var data: Dictionary = JSON.parse_string(JSON.stringify(board.to_dict()))
	var loaded: SortieBoard = BoardScript.from_dict(data)
	var twice: SortieBoard = BoardScript.from_dict(data)
	assert_int(loaded.offers.size()).is_equal(board.offers.size())
	assert_array(loaded.blueprints).is_equal(["scrapyard"])
	assert_int(twice.tithe_cut_pct).is_equal(10)
	# Lo que esperaba a la columna (INF) vuelve a ser INF.
	assert_bool(loaded.next_raid_at == INF or loaded.next_expedition_at == INF).is_true()

func test_an_old_save_without_the_key_is_an_empty_board() -> void:
	var board: SortieBoard = BoardScript.from_dict({})
	assert_array(board.offers).is_empty()
	assert_array(board.blueprints).is_empty()
	assert_int(board.tithe_cut_pct).is_equal(0)
