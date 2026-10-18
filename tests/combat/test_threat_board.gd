extends GdUnitTestSuite
## Las amenazas de costa (ThreatBoard, feat/amenazas-costa, docs/15 §14): modelo
## puro. Cuando aparecen, que se van solas, que pasa al atacarlas y al explorar
## el pecio, tocar la marca y el guardado (idempotente, tipos desconocidos fuera).
##
## Escrito SIN EJECUTAR (regla de Bryan: un solo pase de pruebas al final).

const BoardScript := preload("res://scripts/combat/ThreatBoard.gd")
const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")

func _ctx(enabled: bool = true, weights: Dictionary = {"raiders": 1}, sea_ok: bool = false, sea_chance: float = 0.0) -> Dictionary:
	return {
		"enabled": enabled, "era": 2, "sea_ok": sea_ok, "max": 2,
		"first_delay": 10.0, "interval": Vector2(100.0, 100.0),
		"lifetimes": {"raiders": 200.0, "vanguard": 300.0, "wreck": 300.0},
		"weights": weights, "sea_chance": sea_chance, "spacing": 3,
	}

func _spots() -> Dictionary:
	var land: Array = []
	for x in range(0, 40, 2):
		land.append(Vector2i(x, 0))
	return {"land": land, "sea": [Vector2i(5, 5), Vector2i(20, 5)]}

## Arma el primer plazo y saca una marca.
func _board_with_one(weights: Dictionary = {"raiders": 1}) -> ThreatBoard:
	var board: ThreatBoard = BoardScript.new()
	board.refresh(0.0, _ctx(true, weights), {}, 11)
	board.refresh(10.0, _ctx(true, weights), _spots(), 12)
	return board

func test_nothing_appears_while_closed() -> void:
	var board: ThreatBoard = BoardScript.new()
	assert_array(board.refresh(0.0, _ctx(false), _spots(), 1)).is_empty()
	assert_array(board.refresh(500.0, _ctx(false), _spots(), 2)).is_empty()
	assert_int(board.count()).is_equal(0)

func test_the_first_waits_its_delay() -> void:
	var board: ThreatBoard = BoardScript.new()
	board.refresh(0.0, _ctx(), {}, 1)
	assert_bool(board.spawn_due(5.0, _ctx())).is_false()
	assert_bool(board.spawn_due(10.0, _ctx())).is_true()
	var events: Array = board.refresh(10.0, _ctx(), _spots(), 2)
	assert_int(board.count()).is_equal(1)
	assert_str(String(events[0]["e"])).is_equal("appeared")

func test_never_more_than_max_at_once() -> void:
	var board: ThreatBoard = _board_with_one()
	board.refresh(110.0, _ctx(), _spots(), 3)
	assert_int(board.count()).is_equal(2)
	# Lleno: aunque toque, no sale otra.
	assert_bool(board.spawn_due(210.0, _ctx())).is_false()

func test_they_leave_on_their_own_without_harm() -> void:
	var board: ThreatBoard = _board_with_one()
	var id: int = int(board.threats[0]["id"])
	var events: Array = board.refresh(10.0 + 200.0, _ctx(false), {}, 4)
	assert_int(board.count()).is_equal(0)
	var left := false
	for e in events:
		if String(e["e"]) == "left" and int(e["id"]) == id:
			left = true
	assert_bool(left).is_true()

func test_no_free_coast_no_mark() -> void:
	var board: ThreatBoard = BoardScript.new()
	board.refresh(0.0, _ctx(), {}, 1)
	board.refresh(10.0, _ctx(), {"land": [], "sea": []}, 2)
	assert_int(board.count()).is_equal(0)
	# Y no se reintenta cada tic: espera su plazo.
	assert_bool(board.spawn_due(11.0, _ctx())).is_false()

func test_marks_keep_their_distance() -> void:
	var board: ThreatBoard = BoardScript.new()
	board.refresh(0.0, _ctx(), {}, 1)
	var crowded := {"land": [Vector2i(0, 0), Vector2i(1, 0)], "sea": []}
	board.refresh(10.0, _ctx(), crowded, 2)
	board.refresh(110.0, _ctx(), crowded, 3)
	assert_int(board.count()).is_equal(1)

func test_sea_raiders_only_with_ships() -> void:
	var board: ThreatBoard = BoardScript.new()
	board.refresh(0.0, _ctx(true, {"raiders": 1}, false, 1.0), {}, 1)
	board.refresh(10.0, _ctx(true, {"raiders": 1}, false, 1.0), _spots(), 2)
	assert_bool(bool(board.threats[0]["water"])).is_false()
	var with_ships: ThreatBoard = BoardScript.new()
	with_ships.refresh(0.0, _ctx(true, {"raiders": 1}, true, 1.0), {}, 1)
	with_ships.refresh(10.0, _ctx(true, {"raiders": 1}, true, 1.0), _spots(), 2)
	assert_bool(bool(with_ships.threats[0]["water"])).is_true()
	assert_str(String(BoardScript.offer_for(with_ships.threats[0])["domain"])).is_equal("sea")

func test_wrecks_are_never_on_the_water() -> void:
	var board: ThreatBoard = BoardScript.new()
	board.refresh(0.0, _ctx(true, {"wreck": 1}, true, 1.0), {}, 1)
	board.refresh(10.0, _ctx(true, {"wreck": 1}, true, 1.0), _spots(), 2)
	assert_bool(bool(board.threats[0]["water"])).is_false()

func test_engage_and_win_clears_it() -> void:
	var board: ThreatBoard = _board_with_one()
	var id: int = int(board.threats[0]["id"])
	var offer: Dictionary = board.engage(id)
	assert_str(String(offer["kind"])).is_equal(Generator.KIND_THREAT)
	assert_int(int(offer["id"])).is_equal(ThreatBoard.OFFER_ID_BASE + id)
	assert_int(board.engaged_id()).is_equal(id)
	# Atacada no se va aunque se le acabe el tiempo.
	board.refresh(10.0 + 500.0, _ctx(false), {}, 5)
	assert_int(board.count()).is_equal(1)
	var events: Array = board.finish_engagement(true, 600.0)
	assert_str(String(events[0]["e"])).is_equal("cleared")
	assert_int(board.count()).is_equal(0)

func test_lost_fight_leaves_it_on_the_shore() -> void:
	var board: ThreatBoard = _board_with_one()
	var id: int = int(board.threats[0]["id"])
	board.engage(id)
	board.finish_engagement(false, 20.0)
	assert_int(board.count()).is_equal(1)
	assert_str(String(board.get_threat(id)["state"])).is_equal(ThreatBoard.STATE_IDLE)
	# Pero si ya se le habia acabado el tiempo, se va.
	board.engage(id)
	var events: Array = board.finish_engagement(false, 10.0 + 999.0)
	assert_str(String(events[0]["e"])).is_equal("left")
	assert_int(board.count()).is_equal(0)

func test_wreck_is_explored_not_fought() -> void:
	var board: ThreatBoard = _board_with_one({"wreck": 1})
	var id: int = int(board.threats[0]["id"])
	assert_dict(board.engage(id)).is_empty()
	assert_array(board.start_explore(id, 20.0, 60.0)).is_not_empty()
	assert_int(board.exploring_count()).is_equal(1)
	# Explorandose no se va por tiempo.
	assert_array(board.refresh(70.0, _ctx(false), {}, 6)).is_empty()
	var events: Array = board.refresh(80.0, _ctx(false), {}, 7)
	assert_str(String(events[0]["e"])).is_equal("explored")
	assert_str(String(events[0]["offer"]["threat_type"])).is_equal(Generator.THREAT_WRECK)
	assert_int(board.count()).is_equal(0)

func test_threat_at_finds_the_mark_and_its_neighbours() -> void:
	var board: ThreatBoard = _board_with_one()
	var cell: Vector2i = board.threats[0]["cell"]
	var id: int = int(board.threats[0]["id"])
	assert_int(board.threat_at(cell)).is_equal(id)
	assert_int(board.threat_at(cell + Vector2i(1, 1))).is_equal(id)
	assert_int(board.threat_at(cell + Vector2i(3, 0))).is_equal(0)

func test_seen_turns_off_the_suggestion() -> void:
	var board: ThreatBoard = _board_with_one()
	assert_bool(board.has_unseen()).is_true()
	board.mark_all_seen()
	assert_bool(board.has_unseen()).is_false()

func test_save_round_trip_is_idempotent() -> void:
	var board: ThreatBoard = _board_with_one()
	board.refresh(110.0, _ctx(true, {"wreck": 1}), _spots(), 9)
	board.start_explore(int(board.threats[1]["id"]), 120.0, 60.0)
	var data: Dictionary = board.to_dict()
	var copy: ThreatBoard = BoardScript.from_dict(JSON.parse_string(JSON.stringify(data)))
	assert_int(copy.count()).is_equal(2)
	assert_that(copy.threats[0]["cell"]).is_equal(board.threats[0]["cell"])
	assert_str(String(copy.threats[1]["state"])).is_equal(ThreatBoard.STATE_EXPLORING)
	assert_float(copy.next_spawn_at).is_equal(board.next_spawn_at)
	# Cargar dos veces da lo mismo.
	var again: ThreatBoard = BoardScript.from_dict(copy.to_dict())
	assert_dict(again.to_dict()).is_equal(copy.to_dict())

func test_old_save_and_unknown_types() -> void:
	var empty: ThreatBoard = BoardScript.from_dict({})
	assert_int(empty.count()).is_equal(0)
	assert_float(empty.next_spawn_at).is_equal(-1.0)
	var odd: ThreatBoard = BoardScript.from_dict({"threats": [{"id": 3, "type": "kraken", "x": 1, "y": 1}]})
	assert_int(odd.count()).is_equal(0)

func test_ids_never_repeat_after_loading() -> void:
	var board: ThreatBoard = _board_with_one()
	var copy: ThreatBoard = BoardScript.from_dict(board.to_dict())
	copy.refresh(110.0, _ctx(), _spots(), 21)
	assert_int(int(copy.threats[1]["id"])).is_greater(int(copy.threats[0]["id"]))
