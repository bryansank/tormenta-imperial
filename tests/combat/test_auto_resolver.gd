extends GdUnitTestSuite
## La defensa que se pelea sola. AutoResolver juega un Encounter con la IA en
## los dos bandos; aqui se fija que termina siempre, que el resultado sigue a la
## fuerza de cada bando, que es determinista y que ambos lados de verdad actuan.
##
## Modelo puro: sin autoloads que dejar como estaban.

const ResolverScript := preload("res://scripts/combat/AutoResolver.gd")
const EncounterScript := preload("res://scripts/combat/Encounter.gd")
const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")

const PLAYER := 0
const ENEMY := 1

var _uid := 0

func before_test() -> void:
	_uid = 0

func _unit(unit_id: String, side: int) -> CombatUnit:
	_uid += 1
	return CombatUnitScript.create(_uid, unit_id, side, 1.0)

func _encounter(player_ids: Array, enemy_ids: Array, is_defense: bool = true) -> Encounter:
	var units: Array = []
	for id in player_ids:
		units.append(_unit(id, PLAYER))
	for id in enemy_ids:
		units.append(_unit(id, ENEMY))
	return EncounterScript.create(units, 0, false, is_defense)

func _events_named(events: Array, name: String) -> Array:
	var found: Array = []
	for event in events:
		if event.get("e", "") == name:
			found.append(event)
	return found

func _last_name(events: Array) -> String:
	return String(events[events.size() - 1].get("e", "")) if not events.is_empty() else ""

# ── Termina siempre ──────────────────────────────────────────────────

func test_it_plays_the_encounter_to_the_end() -> void:
	var e := _encounter(["infantry", "infantry"], ["infantry", "artillery"])
	var result: Dictionary = ResolverScript.resolve(e)
	assert_bool(e.is_resolved()).is_true()
	assert_str(_last_name(result["events"])).is_equal("encounter_ended")
	assert_bool(result.has("victory")).is_true()

func test_it_never_runs_past_the_encounter_turn_limit() -> void:
	# Dos artillerias a la maxima distancia, que se persiguen a paso de 1: si algo
	# se quedara colgado seria esto. El limite de rondas del propio tablero manda.
	var e := _encounter(["artillery"], ["artillery"])
	var result: Dictionary = ResolverScript.resolve(e)
	assert_bool(e.is_resolved()).is_true()
	assert_int(int(result["rounds"])).is_less_equal(e.turn_limit)
	assert_int(e.round_number).is_less_equal(e.turn_limit + 1)

func test_it_starts_an_encounter_that_arrives_unstarted_and_accepts_one_already_started() -> void:
	var fresh := _encounter(["infantry"], ["infantry"])
	assert_int(fresh.state).is_equal(Encounter.State.DEPLOYING)
	assert_bool(ResolverScript.resolve(fresh).has("victory")).is_true()

	var started := _encounter(["infantry"], ["infantry"])
	started.start()
	assert_bool(ResolverScript.resolve(started).has("victory")).is_true()
	assert_bool(started.is_resolved()).is_true()

func test_the_rounds_reported_match_the_final_event() -> void:
	var e := _encounter(["infantry"], ["infantry"])
	var result: Dictionary = ResolverScript.resolve(e)
	var ended: Array = _events_named(result["events"], "encounter_ended")
	assert_int(ended.size()).is_equal(1)
	assert_int(int(result["rounds"])).is_equal(int(ended[0]["rounds"]))
	assert_bool(bool(result["victory"])).is_equal(bool(ended[0]["victory"]))

# ── El resultado sigue a la fuerza ───────────────────────────────────

func test_an_overwhelming_garrison_wins() -> void:
	var e := _encounter(
		["infantry", "infantry", "infantry", "infantry", "artillery", "artillery"], ["infantry"])
	var result: Dictionary = ResolverScript.resolve(e)
	assert_bool(bool(result["victory"])).is_true()
	assert_int(e.state).is_equal(Encounter.State.WON)
	assert_bool(e.living(ENEMY).is_empty()).is_true()

func test_a_lone_defender_against_a_column_loses() -> void:
	var e := _encounter(
		["infantry"], ["infantry", "infantry", "infantry", "infantry", "artillery", "artillery"])
	var result: Dictionary = ResolverScript.resolve(e)
	assert_bool(bool(result["victory"])).is_false()
	assert_bool(e.living(PLAYER).is_empty()).is_true()

# ── Determinista ─────────────────────────────────────────────────────

func test_the_same_board_always_resolves_the_same_way() -> void:
	_uid = 0
	var first: Dictionary = ResolverScript.resolve(
		_encounter(["infantry", "infantry", "artillery"], ["infantry", "infantry", "artillery"]))
	_uid = 0
	var second: Dictionary = ResolverScript.resolve(
		_encounter(["infantry", "infantry", "artillery"], ["infantry", "infantry", "artillery"]))
	assert_bool(bool(first["victory"])).is_equal(bool(second["victory"]))
	assert_int(int(first["rounds"])).is_equal(int(second["rounds"]))
	assert_array(first["events"]).is_equal(second["events"])

# ── Los dos bandos pelean ────────────────────────────────────────────

func test_both_sides_attack() -> void:
	var e := _encounter(["infantry", "infantry", "infantry"], ["infantry", "infantry", "infantry"])
	var result: Dictionary = ResolverScript.resolve(e)
	var sides: Dictionary = {}
	for event in _events_named(result["events"], "unit_attacked"):
		sides[e.get_unit(int(event["attacker"])).side] = true
	assert_bool(sides.has(PLAYER)).override_failure_message("el jugador nunca ataco").is_true()
	assert_bool(sides.has(ENEMY)).override_failure_message("el enemigo nunca ataco").is_true()

func test_a_unit_that_cannot_reach_anyone_defends_instead_of_waiting() -> void:
	# En una defensa los bandos arrancan a cinco filas: en la primera ronda nadie
	# llega a tiro, asi que la primera accion de cada uno tiene que ser cubrirse.
	var e := _encounter(["infantry"], ["infantry"])
	var result: Dictionary = ResolverScript.resolve(e)
	var defended: Array = _events_named(result["events"], "unit_defended")
	assert_int(defended.size()).is_greater(0)
	var first_attack_index: int = result["events"].size()
	var first_defend_index: int = result["events"].size()
	for i in range(result["events"].size()):
		var name: String = String(result["events"][i].get("e", ""))
		if name == "unit_attacked":
			first_attack_index = mini(first_attack_index, i)
		elif name == "unit_defended":
			first_defend_index = mini(first_defend_index, i)
	assert_int(first_defend_index).is_less(first_attack_index)

func test_apply_step_understands_every_action_the_ai_can_plan() -> void:
	var e := _encounter(["infantry"], ["infantry"])
	e.start()
	var active: CombatUnit = e.active_unit()
	var moves: Array = e.valid_moves(active.uid)
	assert_bool(ResolverScript.apply_step(e, active.uid, {"action": "move", "to": moves[0]}).is_empty()).is_false()
	assert_bool(ResolverScript.apply_step(e, active.uid, {"action": "defend"}).is_empty()).is_false()
	assert_bool(active.defending).is_true()
