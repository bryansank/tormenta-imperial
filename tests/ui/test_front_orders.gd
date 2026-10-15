extends GdUnitTestSuite
## Las ordenes de la vista frontal (FrontOrders, docs/15 §3 "Las dos vistas"):
## "acercate y dispara" y AVANZAR se traducen a las MISMAS acciones del
## Encounter (mover, atacar). Puro: sin pantalla, sin EventBus.

const Orders := preload("res://scripts/combat_view/FrontOrders.gd")
const EncounterScript := preload("res://scripts/combat/Encounter.gd")
const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")

const PLAYER := 0
const ENEMY := 1

var _uid := 0

func before_test() -> void:
	_uid = 0

func _unit(unit_id: String, side: int) -> CombatUnit:
	_uid += 1
	return CombatUnitScript.create(_uid, unit_id, side, 1.0)

func _encounter(units: Array) -> Encounter:
	var e: Encounter = EncounterScript.create(units, 0, false)
	e.start()
	return e

func test_a_target_already_in_range_needs_no_move() -> void:
	var me := _unit("infantry", PLAYER)
	var foe := _unit("infantry", ENEMY)
	var e := _encounter([me, foe])
	me.position = Vector2i(3, 4)
	foe.position = Vector2i(3, 3)
	assert_vector(Orders.approach_cell(e, me.uid, foe.uid)).is_equal(me.position)

func test_the_approach_cell_is_reachable_and_puts_the_target_in_range() -> void:
	var me := _unit("infantry", PLAYER)
	var foe := _unit("infantry", ENEMY)
	var e := _encounter([me, foe])
	me.position = Vector2i(3, 6)
	foe.position = Vector2i(3, 3)
	var cell: Vector2i = Orders.approach_cell(e, me.uid, foe.uid)
	assert_vector(cell).is_not_equal(Orders.NO_CELL)
	assert_bool(e.valid_moves(me.uid).has(cell)).is_true()
	var dist: int = Rules.manhattan(cell, foe.position)
	assert_int(dist).is_between(me.min_range(), me.attack_range())
	# El camino mas corto: ninguna otra casilla valida esta mas cerca de la unidad.
	for other in e.valid_moves(me.uid):
		var d: int = Rules.manhattan(other, foe.position)
		if d >= me.min_range() and d <= me.attack_range():
			assert_int(Rules.manhattan(me.position, other)).is_greater_equal(Rules.manhattan(me.position, cell))

func test_artillery_never_approaches_to_point_blank() -> void:
	var gun := _unit("artillery", PLAYER)
	var foe := _unit("infantry", ENEMY)
	var e := _encounter([gun, foe])
	gun.position = Vector2i(3, 7)
	foe.position = Vector2i(3, 1)
	var cell: Vector2i = Orders.approach_cell(e, gun.uid, foe.uid)
	if cell != Orders.NO_CELL:
		assert_int(Rules.manhattan(cell, foe.position)).is_greater_equal(gun.min_range())

func test_an_unreachable_target_gives_no_cell_and_is_not_marked() -> void:
	var me := _unit("infantry", PLAYER)
	var foe := _unit("infantry", ENEMY)
	var e := _encounter([me, foe])
	me.position = Vector2i(0, 7)
	foe.position = Vector2i(7, 0)
	assert_vector(Orders.approach_cell(e, me.uid, foe.uid)).is_equal(Orders.NO_CELL)
	assert_array(Orders.reachable_targets(e, me.uid)).is_empty()

func test_a_unit_that_already_moved_only_hits_what_is_in_range() -> void:
	var me := _unit("infantry", PLAYER)
	var foe := _unit("infantry", ENEMY)
	var e := _encounter([me, foe])
	me.position = Vector2i(3, 6)
	foe.position = Vector2i(3, 3)
	me.moved_this_turn = true
	assert_vector(Orders.approach_cell(e, me.uid, foe.uid)).is_equal(Orders.NO_CELL)
	assert_vector(Orders.advance_cell(e, me.uid)).is_equal(Orders.NO_CELL)

func test_advance_is_the_move_the_ai_would_make() -> void:
	var me := _unit("infantry", PLAYER)
	var foe := _unit("infantry", ENEMY)
	var e := _encounter([me, foe])
	me.position = Vector2i(0, 7)
	foe.position = Vector2i(7, 0)
	var cell: Vector2i = Orders.advance_cell(e, me.uid)
	assert_bool(e.valid_moves(me.uid).has(cell)).is_true()
	var plan: Array = CombatAI.plan_turn(e, me.uid)
	assert_str(String(plan[0]["action"])).is_equal("move")
	assert_vector(plan[0]["to"]).is_equal(cell)
	# Se acerca.
	assert_int(Rules.manhattan(cell, foe.position)).is_less(Rules.manhattan(me.position, foe.position))

func test_orders_never_touch_the_encounter() -> void:
	var me := _unit("infantry", PLAYER)
	var foe := _unit("infantry", ENEMY)
	var e := _encounter([me, foe])
	me.position = Vector2i(3, 6)
	foe.position = Vector2i(3, 3)
	var before := [me.position, me.moved_this_turn, me.has_acted, foe.hp]
	Orders.approach_cell(e, me.uid, foe.uid)
	Orders.reachable_targets(e, me.uid)
	Orders.advance_cell(e, me.uid)
	assert_array([me.position, me.moved_this_turn, me.has_acted, foe.hp]).is_equal(before)

func test_executing_an_order_is_a_legal_move_then_attack() -> void:
	var me := _unit("infantry", PLAYER)
	var foe := _unit("infantry", ENEMY)
	var e := _encounter([me, foe])
	me.position = Vector2i(3, 6)
	foe.position = Vector2i(3, 3)
	var hp_before := foe.hp
	var cell: Vector2i = Orders.approach_cell(e, me.uid, foe.uid)
	# Mismas llamadas que el tablero: mover (si hace falta) y atacar.
	if cell != me.position:
		assert_array(e.move_unit(me.uid, cell)).is_not_empty()
	if e.active_unit() != null and e.active_unit().uid == me.uid:
		assert_array(e.attack(me.uid, foe.uid)).is_not_empty()
		assert_int(foe.hp).is_less(hp_before)
