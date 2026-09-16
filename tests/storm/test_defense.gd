extends GdUnitTestSuite
## Defending the base is not an expedition with worse stakes: the attackers form
## up further away, the player does not choose who fights, and winning pays
## nothing because keeping what you own is the reward.

const EncounterScript := preload("res://scripts/combat/Encounter.gd")
const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")

const PLAYER := 0
const ENEMY := 1

var _uid := 0
var _saved_army: Dictionary = {}

func before_test() -> void:
	_uid = 0
	_saved_army = ArmyManager.get_save_data()
	ArmyManager.reset()

func after_test() -> void:
	ArmyManager.load_save_data(_saved_army)

func _unit(unit_id: String, side: int) -> CombatUnit:
	_uid += 1
	return CombatUnitScript.create(_uid, unit_id, side, 1.0)

func _encounter(player_ids: Array, enemy_ids: Array, is_defense: bool) -> Encounter:
	var units: Array = []
	for id in player_ids:
		units.append(_unit(id, PLAYER))
	for id in enemy_ids:
		units.append(_unit(id, ENEMY))
	return EncounterScript.create(units, 0, false, is_defense)

func _given_army(units: Dictionary) -> void:
	ArmyManager.load_save_data({"units": units, "training": [], "upkeep_accum": 0.0})

# ── The home-ground advantage ────────────────────────────────────────

func test_attackers_form_up_on_the_far_edge_when_defending() -> void:
	var e := _encounter(["infantry"], ["infantry", "infantry"], true)
	for unit in e.living(ENEMY):
		assert_int(unit.position.y).is_equal(0)

func test_attackers_start_closer_on_an_expedition() -> void:
	# The same roster, marching out: they hold the near row instead.
	var e := _encounter(["infantry"], ["infantry", "infantry"], false)
	for unit in e.living(ENEMY):
		assert_int(unit.position.y).is_equal(1)

func test_defending_buys_the_player_a_row_of_distance() -> void:
	var defending := _encounter(["infantry"], ["infantry"], true)
	var attacking := _encounter(["infantry"], ["infantry"], false)
	var d_gap: int = absi(defending.living(PLAYER)[0].position.y - defending.living(ENEMY)[0].position.y)
	var a_gap: int = absi(attacking.living(PLAYER)[0].position.y - attacking.living(ENEMY)[0].position.y)
	assert_int(d_gap).is_greater(a_gap)

func test_the_player_still_holds_their_own_rows() -> void:
	var e := _encounter(["infantry", "artillery"], ["infantry"], true)
	for unit in e.living(PLAYER):
		assert_bool(unit.position.y >= e.board_size.y - 2).is_true()

func test_a_defence_knows_it_is_one() -> void:
	assert_bool(_encounter(["infantry"], ["infantry"], true).is_defense).is_true()
	assert_bool(_encounter(["infantry"], ["infantry"], false).is_defense).is_false()

# ── The garrison is whoever is home ──────────────────────────────────

func test_the_garrison_is_everything_trained() -> void:
	_given_army({"infantry": 3, "artillery": 1})
	var garrison := CombatManager.get_garrison()
	assert_int(int(garrison.get("infantry", 0))).is_equal(3)
	assert_int(int(garrison.get("artillery", 0))).is_equal(1)

func test_the_garrison_respects_the_board_cap() -> void:
	_given_army({"infantry": 20})
	var total := 0
	for count in CombatManager.get_garrison().values():
		total += int(count)
	assert_int(total).is_equal(GameConfig.combat_deploy_cap)

func test_an_empty_army_leaves_no_garrison() -> void:
	_given_army({})
	assert_bool(CombatManager.get_garrison().is_empty()).is_true()

func test_a_defence_cannot_start_with_nobody_home() -> void:
	# This is the case that has to let the Tithe through instead of crashing.
	_given_army({})
	assert_bool(CombatManager.start_defense({"infantry": 2})).is_false()

func test_a_defence_cannot_start_against_nobody() -> void:
	_given_army({"infantry": 2})
	assert_bool(CombatManager.start_defense({})).is_false()

# ── Who they send ────────────────────────────────────────────────────

func test_the_assessors_grow_with_severity() -> void:
	var mild := StormManager.assessor_roster(1)
	var harsh := StormManager.assessor_roster(GameConfig.storm_severity_max)
	assert_int(_total(harsh)).is_greater(_total(mild))

func test_they_never_come_alone_and_never_overflow_the_board() -> void:
	for severity in range(1, GameConfig.storm_severity_max + 2):
		var force: int = _total(StormManager.assessor_roster(severity))
		assert_int(force).is_greater(0)
		assert_int(force).is_less_equal(GameConfig.combat_deploy_cap)

func test_they_always_field_a_line() -> void:
	for severity in range(1, GameConfig.storm_severity_max + 1):
		assert_int(int(StormManager.assessor_roster(severity).get("infantry", 0))).is_greater(0)

func _total(roster: Dictionary) -> int:
	var sum := 0
	for count in roster.values():
		sum += int(count)
	return sum

# ── La retaguardia ───────────────────────────────────────────────────

func test_tower_crews_hold_the_back_row() -> void:
	# Artillería con alcance mínimo 2: en cabeza se queda muda en cuanto el
	# enemigo llega a contacto, que es justo cuando hace falta.
	var crew := _unit("artillery", PLAYER)
	var units: Array = [_unit("infantry", PLAYER), _unit("infantry", PLAYER), crew]
	var e: Encounter = EncounterScript.create(units, 0, false, true, [crew.uid])
	assert_int(crew.position.y).is_equal(e.board_size.y - 1)

func test_the_line_still_forms_in_front_of_the_crews() -> void:
	var crew := _unit("artillery", PLAYER)
	var line_a := _unit("infantry", PLAYER)
	var line_b := _unit("infantry", PLAYER)
	var e: Encounter = EncounterScript.create([line_a, line_b, crew], 0, false, true, [crew.uid])
	assert_int(line_a.position.y).is_equal(e.board_size.y - 2)
	assert_int(line_b.position.y).is_equal(e.board_size.y - 2)

func test_a_full_board_still_puts_the_crews_behind() -> void:
	# El caso que motivó todo esto: 6 de guarnición + 2 dotaciones son
	# exactamente el ancho del tablero, así que sin reparto explícito la fila de
	# atrás no se tocaría nunca y las dotaciones formarían en cabeza.
	var units: Array = []
	for i in range(6):
		units.append(_unit("infantry", PLAYER))
	var crews: Array = [_unit("artillery", PLAYER), _unit("artillery", PLAYER)]
	units.append_array(crews)
	units.append(_unit("infantry", ENEMY))
	var e: Encounter = EncounterScript.create(units, 0, false, true, [crews[0].uid, crews[1].uid])
	for crew in crews:
		assert_int(crew.position.y).is_equal(e.board_size.y - 1)

func test_nobody_shares_a_cell_with_a_crew() -> void:
	var units: Array = []
	for i in range(8):
		units.append(_unit("infantry", PLAYER))
	var crew := _unit("artillery", PLAYER)
	units.append(crew)
	var e: Encounter = EncounterScript.create(units, 0, false, true, [crew.uid])
	var seen: Array = []
	for unit in e.living(PLAYER):
		assert_array(seen).not_contains([unit.position])
		seen.append(unit.position)

func test_without_crews_the_formation_is_unchanged() -> void:
	# La red que impide que esto cambie el despliegue de siempre.
	var units: Array = [_unit("infantry", PLAYER), _unit("infantry", PLAYER)]
	var e: Encounter = EncounterScript.create(units, 0, false, true, [])
	var columns: Array = []
	for unit in e.living(PLAYER):
		assert_int(unit.position.y).is_equal(e.board_size.y - 2)
		columns.append(unit.position.x)
	columns.sort()
	assert_array(columns).is_equal([3, 4])
