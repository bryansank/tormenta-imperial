extends GdUnitTestSuite
## Aire y mar (feat/aire-mar-reglas, docs/15 §11): el terreno del tablero, quien
## pisa que, quien pega a quien, las dos capas (aire encima de superficie), el
## despliegue por dominio, la reserva, la tabla de ventajas ampliada y que la IA
## y AutoResolver lo respetan. Y lo mas importante: un tablero sin agua y con
## solo tierra sigue siendo exactamente el de antes.

const EncounterScript := preload("res://scripts/combat/Encounter.gd")
const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")
const AIScript := preload("res://scripts/combat/CombatAI.gd")
const AutoResolverScript := preload("res://scripts/combat/AutoResolver.gd")

const PLAYER := 0
const ENEMY := 1
const NEW_UNITS := ["torpedo_boat", "gunboat", "dreadnought", "fighter", "bomber", "airship"]

var _uid := 0

func before_test() -> void:
	_uid = 0

func _unit(unit_id: String, side: int) -> CombatUnit:
	_uid += 1
	return CombatUnitScript.create(_uid, unit_id, side, 1.0)

func _board() -> Vector2i:
	return GameConfig.combat_board_size

func _coast(seed_value: int = 2) -> Dictionary:
	return Rules.coastal_terrain(_board(), seed_value)

func _encounter(player_ids: Array, enemy_ids: Array, terrain: Dictionary = {}, defense: bool = false) -> Encounter:
	var units: Array = []
	for id in player_ids:
		units.append(_unit(id, PLAYER))
	for id in enemy_ids:
		units.append(_unit(id, ENEMY))
	return EncounterScript.create(units, 0, false, defense, [], false, terrain)

## Pone a todos fuera del tablero y a cada uno en su casilla, a mano.
func _place(e: Encounter, cells: Dictionary) -> void:
	for unit in e.units:
		unit.position = Vector2i(-1, -1)
	for uid in cells:
		e.get_unit(int(uid)).position = cells[uid]

# ── Los datos ────────────────────────────────────────────────────────

func test_the_six_new_units_exist_with_their_domain_and_building() -> void:
	for id in ["torpedo_boat", "gunboat", "dreadnought"]:
		assert_str(GameConfig.get_unit_domain(id)).is_equal("sea")
		assert_str(GameConfig.get_unit_building(id)).is_equal("shipyard")
	for id in ["fighter", "bomber", "airship"]:
		assert_str(GameConfig.get_unit_domain(id)).is_equal("air")
		assert_str(GameConfig.get_unit_building(id)).is_equal("aerodrome")
	for id in ["infantry", "artillery", "vehicle"]:
		assert_str(GameConfig.get_unit_building(id)).is_equal("barracks")
	assert_int(int(GameConfig.get_unit_def("torpedo_boat")["era"])).is_equal(2)
	assert_int(int(GameConfig.get_unit_def("gunboat")["era"])).is_equal(2)
	assert_int(int(GameConfig.get_unit_def("dreadnought")["era"])).is_equal(3)
	for id in ["fighter", "bomber", "airship"]:
		assert_int(int(GameConfig.get_unit_def(id)["era"])).is_equal(3)

func test_every_new_unit_has_a_name_and_card_in_both_languages() -> void:
	for id in NEW_UNITS:
		for locale in ["es", "en"]:
			var strings: Dictionary = Tr._STRINGS[locale]
			assert_bool(strings.has("UNIT_%s" % id.to_upper())).override_failure_message("%s/%s" % [locale, id]).is_true()
			assert_bool(strings.has("UNIT_%s_CARD_TIP" % id.to_upper())).override_failure_message("%s/%s tip" % [locale, id]).is_true()

func test_the_domain_moves_table_is_the_contract() -> void:
	assert_bool(Rules.can_stand("land", "land")).is_true()
	assert_bool(Rules.can_stand("land", "shore")).is_true()
	assert_bool(Rules.can_stand("land", "water")).is_false()
	assert_bool(Rules.can_stand("sea", "water")).is_true()
	assert_bool(Rules.can_stand("sea", "shore")).is_true()
	assert_bool(Rules.can_stand("sea", "land")).is_false()
	for kind in ["land", "water", "shore"]:
		assert_bool(Rules.can_stand("air", kind)).is_true()

# ── El terreno de costa ──────────────────────────────────────────────

func test_the_coast_is_deterministic_and_covers_the_board() -> void:
	var a := _coast(11)
	var b := _coast(11)
	assert_dict(a).is_equal(b)
	assert_int(a.size()).is_equal(_board().x * _board().y)

func test_the_coast_has_water_columns_then_a_shore_column_on_one_side() -> void:
	for seed_value in [2, 3]:
		var t := _coast(seed_value)
		var water := 0
		var shore := 0
		for cell in t:
			match String(t[cell]):
				"water":
					water += 1
				"shore":
					shore += 1
		assert_int(water).is_equal(GameConfig.combat_coast_water_columns * _board().y)
		assert_int(shore).is_equal(_board().y)
		# Una columna entera es igual de arriba abajo: los dos bandos tienen agua.
		for x in range(_board().x):
			var kind: String = String(t[Vector2i(x, 0)])
			for y in range(_board().y):
				assert_str(String(t[Vector2i(x, y)])).is_equal(kind)
	# Las dos paridades ponen el agua en lados distintos.
	assert_str(String(_coast(2)[Vector2i(0, 0)])).is_not_equal(String(_coast(3)[Vector2i(0, 0)]))

func test_an_empty_terrain_is_all_land_and_has_no_water() -> void:
	assert_str(Rules.terrain_at({}, Vector2i(3, 3))).is_equal("land")
	assert_bool(Rules.has_water({})).is_false()
	assert_bool(Rules.has_water(_coast())).is_true()

# ── Sin agua, todo igual que antes ───────────────────────────────────

func test_a_land_board_deploys_exactly_as_before_with_or_without_a_land_terrain() -> void:
	var ids_p := ["infantry", "infantry", "artillery", "vehicle"]
	var ids_e := ["infantry", "artillery", "infantry"]
	var a := _encounter(ids_p, ids_e)
	_uid = 0
	var all_land: Dictionary = {}
	for y in range(_board().y):
		for x in range(_board().x):
			all_land[Vector2i(x, y)] = "land"
	var b := _encounter(ids_p, ids_e, all_land)
	for i in range(a.units.size()):
		assert_that(b.units[i].position).is_equal(a.units[i].position)
	assert_bool(a.has_water()).is_false()
	assert_array(a.reserve).is_empty()

func test_land_units_hit_land_units_as_before() -> void:
	var e := _encounter(["artillery"], ["infantry"])
	var gun: CombatUnit = e.living(PLAYER)[0]
	var foe: CombatUnit = e.living(ENEMY)[0]
	_place(e, {gun.uid: Vector2i(3, 5), foe.uid: Vector2i(3, 3)})
	assert_bool(Rules.in_attack_range(gun, foe)).is_true()
	foe.position = Vector2i(3, 4)
	assert_bool(Rules.in_attack_range(gun, foe)).is_false()   # su alcance minimo

# ── Despliegue por dominio ───────────────────────────────────────────

func test_ships_deploy_on_water_and_soldiers_on_land() -> void:
	var t := _coast()
	var e := _encounter(["gunboat", "torpedo_boat", "infantry", "infantry"], ["gunboat", "infantry"], t)
	for unit in e.units:
		var kind: String = Rules.terrain_at(t, unit.position)
		assert_bool(Rules.can_stand(unit.domain(), kind)).override_failure_message(
			"%s en %s (%s)" % [unit.unit_id, unit.position, kind]).is_true()
		# Con sitio en el agua, ningun barco empieza varado en la orilla.
		if unit.domain() == "sea":
			assert_str(kind).override_failure_message("%s en %s" % [unit.unit_id, unit.position]).is_equal("water")
	assert_array(e.reserve).is_empty()

func test_a_ship_on_a_board_without_water_stays_in_reserve() -> void:
	var e := _encounter(["infantry", "gunboat"], ["infantry"])
	assert_int(e.reserve.size()).is_equal(1)
	assert_str(e.reserve[0].unit_id).is_equal("gunboat")
	for unit in e.units:
		assert_str(unit.unit_id).is_not_equal("gunboat")
	# Y la reserva no cuenta para nada: el tablero se juega con lo que hay.
	assert_int(e.living(PLAYER).size()).is_equal(1)

func test_planes_deploy_in_their_own_layer_and_may_sit_over_a_soldier() -> void:
	var e := _encounter(["infantry", "fighter"], ["infantry"])
	var soldier: CombatUnit = null
	var plane: CombatUnit = null
	for unit in e.living(PLAYER):
		if unit.unit_id == "fighter":
			plane = unit
		else:
			soldier = unit
	assert_bool(plane.position.x >= 0).is_true()
	assert_bool(soldier.position.x >= 0).is_true()
	assert_str(plane.layer()).is_equal("air")
	assert_str(soldier.layer()).is_equal("surface")

# ── Movimiento ───────────────────────────────────────────────────────

func test_land_cannot_enter_water_and_ships_cannot_go_ashore() -> void:
	var t := _coast()
	var e := _encounter(["infantry", "torpedo_boat"], ["infantry"], t)
	for unit in e.living(PLAYER):
		for cell in e.valid_moves(unit.uid):
			assert_bool(Rules.can_stand(unit.domain(), Rules.terrain_at(t, cell))).is_true()

func test_planes_fly_over_water() -> void:
	var t := _coast()
	var e := _encounter(["fighter"], ["infantry"], t)
	var plane: CombatUnit = e.living(PLAYER)[0]
	var over_water := false
	for cell in e.valid_moves(plane.uid):
		if Rules.terrain_at(t, cell) == "water":
			over_water = true
	assert_bool(over_water).is_true()

func test_a_plane_can_stop_over_a_soldier_but_a_soldier_cannot() -> void:
	var e := _encounter(["fighter", "infantry"], ["infantry"])
	var plane: CombatUnit = null
	var soldier: CombatUnit = null
	for unit in e.living(PLAYER):
		if unit.unit_id == "fighter":
			plane = unit
		else:
			soldier = unit
	var foe: CombatUnit = e.living(ENEMY)[0]
	_place(e, {plane.uid: Vector2i(2, 6), soldier.uid: Vector2i(3, 6), foe.uid: Vector2i(3, 5)})
	assert_array(e.valid_moves(plane.uid)).contains([Vector2i(3, 6)])
	assert_array(e.valid_moves(plane.uid)).contains([Vector2i(3, 5)])
	assert_array(e.valid_moves(soldier.uid)).not_contains([Vector2i(3, 5)])
	# get_unit_at prefiere la superficie; por capa se encuentran los dos.
	plane.position = Vector2i(3, 6)
	assert_object(e.get_unit_at(Vector2i(3, 6))).is_same(soldier)
	assert_object(e.get_unit_at_layer(Vector2i(3, 6), "air")).is_same(plane)
	assert_int(e.get_units_at(Vector2i(3, 6)).size()).is_equal(2)

# ── Quien pega a quien ───────────────────────────────────────────────

func test_soldiers_hit_planes_only_next_to_them_and_guns_never() -> void:
	var e := _encounter(["infantry", "artillery"], ["airship"])
	var soldier: CombatUnit = null
	var gun: CombatUnit = null
	for unit in e.living(PLAYER):
		if unit.unit_id == "infantry":
			soldier = unit
		else:
			gun = unit
	var ship: CombatUnit = e.living(ENEMY)[0]
	_place(e, {soldier.uid: Vector2i(3, 5), gun.uid: Vector2i(3, 6), ship.uid: Vector2i(3, 4)})
	assert_bool(Rules.in_attack_range(soldier, ship)).is_true()
	ship.position = Vector2i(3, 3)
	assert_bool(Rules.in_attack_range(soldier, ship)).is_false()
	assert_int(Rules.max_reach(gun, ship)).is_equal(0)
	assert_bool(Rules.in_attack_range(gun, ship)).is_false()

func test_a_plane_right_above_a_soldier_is_one_square_away() -> void:
	var e := _encounter(["fighter"], ["infantry"])
	var plane: CombatUnit = e.living(PLAYER)[0]
	var foe: CombatUnit = e.living(ENEMY)[0]
	_place(e, {plane.uid: Vector2i(4, 4), foe.uid: Vector2i(4, 4)})
	assert_int(Rules.strike_distance(plane, plane.position, foe)).is_equal(1)
	assert_bool(Rules.in_attack_range(plane, foe)).is_true()
	assert_bool(Rules.in_attack_range(foe, plane)).is_true()

func test_the_bomber_cannot_hit_planes_but_the_fighter_can() -> void:
	var e := _encounter(["bomber", "fighter"], ["fighter"])
	var bomber: CombatUnit = null
	var fighter: CombatUnit = null
	for unit in e.living(PLAYER):
		if unit.unit_id == "bomber":
			bomber = unit
		else:
			fighter = unit
	var foe: CombatUnit = e.living(ENEMY)[0]
	_place(e, {bomber.uid: Vector2i(3, 5), fighter.uid: Vector2i(5, 5), foe.uid: Vector2i(4, 5)})
	assert_bool(Rules.in_attack_range(bomber, foe)).is_false()
	assert_bool(Rules.in_attack_range(fighter, foe)).is_true()

func test_ships_shell_the_beach_from_the_water() -> void:
	var t := _coast()
	var e := _encounter(["gunboat"], ["infantry"], t)
	var boat: CombatUnit = e.living(PLAYER)[0]
	var foe: CombatUnit = e.living(ENEMY)[0]
	assert_str(Rules.terrain_at(t, boat.position)).is_not_equal("land")
	# A 3 casillas (su alcance) desde el agua.
	var target := boat.position + Vector2i(0, -3)
	foe.position = target
	assert_bool(Rules.in_attack_range(boat, foe)).is_true()

# ── La tabla de ventajas ─────────────────────────────────────────────

func test_no_matchup_goes_both_ways() -> void:
	var ids: Array = GameConfig.get_unit_ids()
	for a in ids:
		for b in ids:
			if a == b:
				continue
			var m: int = Rules.type_matchup(a, b)
			assert_int(Rules.type_matchup(b, a)).override_failure_message("%s/%s" % [a, b]).is_equal(-m)

func test_every_new_unit_beats_something_and_fears_something() -> void:
	for a in NEW_UNITS:
		var wins := 0
		var losses := 0
		for b in GameConfig.get_unit_ids():
			var m: int = Rules.type_matchup(a, b)
			if m > 0:
				wins += 1
			elif m < 0:
				losses += 1
		assert_int(wins).override_failure_message("%s no gana a nadie" % a).is_greater(0)
		assert_int(losses).override_failure_message("%s no teme a nadie" % a).is_greater(0)

func test_the_sea_circle_and_the_fighter() -> void:
	assert_int(Rules.type_matchup("torpedo_boat", "dreadnought")).is_equal(1)
	assert_int(Rules.type_matchup("dreadnought", "gunboat")).is_equal(1)
	assert_int(Rules.type_matchup("gunboat", "torpedo_boat")).is_equal(1)
	assert_int(Rules.type_matchup("fighter", "bomber")).is_equal(1)
	assert_int(Rules.type_matchup("fighter", "airship")).is_equal(1)
	assert_int(Rules.type_matchup("bomber", "vehicle")).is_equal(1)

func test_the_land_circle_is_untouched() -> void:
	assert_int(Rules.type_matchup("artillery", "vehicle")).is_equal(1)
	assert_int(Rules.type_matchup("vehicle", "infantry")).is_equal(1)
	assert_int(Rules.type_matchup("infantry", "artillery")).is_equal(1)

# ── La IA y AutoResolver ─────────────────────────────────────────────

func test_a_dreadnought_with_only_planes_around_never_attacks_them() -> void:
	# Tope 1 contra el aire y alcance minimo 2: no le llega nunca.
	var t := _coast()
	var e := _encounter(["dreadnought"], ["fighter"], t)
	e.start()
	var boat: CombatUnit = e.living(PLAYER)[0]
	assert_int(Rules.max_reach(boat, e.living(ENEMY)[0])).is_equal(0)
	var plan: Array = AIScript.plan_turn(e, boat.uid)
	for step in plan:
		assert_str(String(step.get("action", ""))).is_not_equal("attack")

func test_the_ai_only_moves_where_its_domain_can_stand() -> void:
	var t := _coast()
	var e := _encounter(["gunboat", "infantry"], ["infantry", "torpedo_boat", "fighter"], t)
	e.start()
	for unit in e.units:
		for step in AIScript.plan_turn(e, unit.uid):
			if String(step.get("action", "")) == "move":
				assert_bool(Rules.can_stand(unit.domain(), Rules.terrain_at(t, step["to"]))).is_true()

func test_a_coastal_battle_resolves_and_is_reproducible() -> void:
	var t := _coast(5)
	var a := _encounter(["gunboat", "infantry", "fighter"], ["torpedo_boat", "infantry", "airship"], t, true)
	var ra: Dictionary = AutoResolverScript.resolve(a)
	_uid = 0
	var b := _encounter(["gunboat", "infantry", "fighter"], ["torpedo_boat", "infantry", "airship"], t, true)
	var rb: Dictionary = AutoResolverScript.resolve(b)
	assert_bool(a.is_resolved()).is_true()
	assert_bool(bool(ra["victory"])).is_equal(bool(rb["victory"]))
	assert_int(int(ra["rounds"])).is_equal(int(rb["rounds"]))

func test_a_plane_and_a_ship_survive_the_save_round_trip_with_their_domain() -> void:
	for id in ["gunboat", "bomber"]:
		var unit := _unit(id, PLAYER)
		var data: Dictionary = unit.to_dict()
		assert_str(String(data["domain"])).is_equal(GameConfig.get_unit_domain(id))
		var back: CombatUnit = CombatUnitScript.from_dict(data)
		assert_str(back.domain()).is_equal(unit.domain())
	# Un guardado viejo sin la clave sigue siendo de tierra.
	var old := CombatUnitScript.from_dict({"uid": 1, "unit_id": "infantry", "side": 0, "hp": 10, "max_hp": 10})
	assert_str(old.domain()).is_equal("land")
