extends GdUnitTestSuite
## The enemy has to be worth beating. These tests pin the three behaviours that
## make a fight read as deliberate rather than random: it shoots when it can, it
## focuses the weakest target, and it keeps its artillery at range.

const AIScript := preload("res://scripts/combat/CombatAI.gd")
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

func _actions(plan: Array) -> Array:
	var names: Array = []
	for step in plan:
		names.append(step.get("action", ""))
	return names

# ── Attacking ────────────────────────────────────────────────────────

func test_it_attacks_a_target_already_in_range() -> void:
	var enemy := _unit("infantry", ENEMY)
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, enemy])
	enemy.position = Vector2i(4, 3)
	player.position = Vector2i(4, 4)
	var plan := AIScript.plan_turn(e, enemy.uid)
	assert_array(_actions(plan)).contains(["attack"])
	assert_int(plan[0]["target"]).is_equal(player.uid)

func test_it_focuses_the_weakest_reachable_target() -> void:
	var enemy := _unit("infantry", ENEMY)
	var healthy := _unit("infantry", PLAYER)
	var wounded := _unit("infantry", PLAYER)
	var e := _encounter([healthy, wounded, enemy])
	enemy.position = Vector2i(4, 4)
	healthy.position = Vector2i(4, 5)
	wounded.position = Vector2i(3, 4)
	wounded.take_damage(20)
	var plan := AIScript.plan_turn(e, enemy.uid)
	var attack: Dictionary = plan[plan.size() - 1]
	assert_int(attack["target"]).is_equal(wounded.uid)

func test_it_closes_in_when_nothing_is_in_range() -> void:
	var enemy := _unit("infantry", ENEMY)
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, enemy])
	enemy.position = Vector2i(4, 0)
	player.position = Vector2i(4, 7)
	var plan := AIScript.plan_turn(e, enemy.uid)
	assert_array(_actions(plan)).contains(["move"])
	# It walks towards the player, never away.
	assert_bool(plan[0]["to"].y > enemy.position.y).is_true()

func test_it_moves_and_then_attacks_when_one_step_is_enough() -> void:
	var enemy := _unit("infantry", ENEMY)     # move 3, range 1
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, enemy])
	enemy.position = Vector2i(4, 2)
	player.position = Vector2i(4, 4)
	var plan := AIScript.plan_turn(e, enemy.uid)
	assert_array(_actions(plan)).is_equal(["move", "attack"])
	assert_int(plan[1]["target"]).is_equal(player.uid)

# ── Prioridad de objetivo (T038) ─────────────────────────

func test_it_finishes_off_a_rival_it_can_kill_this_turn() -> void:
	# El tablero esta montado para que rematar sea la unica razon de elegir a la
	# infanteria: el vehiculo vale mas (poder 65 contra 10) **y** esta mas tocado
	# (4 HP contra 6). Lo que decide es que la infanteria cae este turno y el
	# vehiculo, con su blindaje, aguanta el golpe.
	var enemy := _unit("infantry", ENEMY)          # atk 8
	var armour := _unit("vehicle", PLAYER)         # def 5 -> recibe 3
	var dying := _unit("infantry", PLAYER)         # def 2 -> recibe 6
	var e := _encounter([armour, dying, enemy])
	enemy.position = Vector2i(4, 4)
	armour.position = Vector2i(4, 5)
	dying.position = Vector2i(3, 4)
	armour.hp = 4                                  # 3 < 4: sobrevive
	dying.hp = 6                                   # 6 >= 6: cae
	assert_bool(Rules.damage(enemy, dying) >= dying.hp).is_true()
	assert_bool(Rules.damage(enemy, armour) >= armour.hp).is_false()
	var plan := AIScript.plan_turn(e, enemy.uid)
	assert_array(_actions(plan)).is_equal(["attack"])
	assert_int(plan[0]["target"]).is_equal(dying.uid)

func test_the_target_guard_counts_before_calling_it_a_kill() -> void:
	# El mismo tablero, pero la moribunda esta en guardia: la defensa se dobla,
	# el dano ya no la mata y la IA vuelve a morder al vehiculo, que es lo caro.
	var enemy := _unit("infantry", ENEMY)
	var armour := _unit("vehicle", PLAYER)
	var dying := _unit("infantry", PLAYER)
	var e := _encounter([armour, dying, enemy])
	enemy.position = Vector2i(4, 4)
	armour.position = Vector2i(4, 5)
	dying.position = Vector2i(3, 4)
	dying.hp = 5
	dying.defending = true                         # dano 8-4 = 4 < 5: sobrevive
	var plan := AIScript.plan_turn(e, enemy.uid)
	assert_int(plan[plan.size() - 1]["target"]).is_equal(armour.uid)

func test_without_a_finishing_blow_it_bites_the_most_valuable_rival() -> void:
	# Nadie cae este turno: entonces pesa el poder. El vehiculo tiene mas HP que
	# la infanteria, asi que "el mas debil" habria elegido lo contrario.
	var enemy := _unit("infantry", ENEMY)
	var armour := _unit("vehicle", PLAYER)
	var escort := _unit("infantry", PLAYER)
	var e := _encounter([armour, escort, enemy])
	enemy.position = Vector2i(4, 4)
	armour.position = Vector2i(4, 5)
	escort.position = Vector2i(3, 4)
	var plan := AIScript.plan_turn(e, enemy.uid)
	assert_array(_actions(plan)).is_equal(["attack"])
	assert_int(plan[0]["target"]).is_equal(armour.uid)

func test_at_equal_value_it_picks_the_one_with_less_hp() -> void:
	var enemy := _unit("infantry", ENEMY)
	var healthy := _unit("infantry", PLAYER)
	var wounded := _unit("infantry", PLAYER)       # uid mayor: solo gana por HP
	var e := _encounter([healthy, wounded, enemy])
	enemy.position = Vector2i(4, 4)
	healthy.position = Vector2i(4, 5)
	wounded.position = Vector2i(3, 4)
	wounded.take_damage(15)                        # 15 HP: el dano 6 no la mata
	var plan := AIScript.plan_turn(e, enemy.uid)
	assert_int(plan[plan.size() - 1]["target"]).is_equal(wounded.uid)

func test_at_equal_hp_it_picks_the_closest() -> void:
	# Artilleria (alcance 2-3) con dos infanterias identicas a tiro. La cercana
	# se crea la segunda, asi que tiene el uid mayor: si mandase el desempate de
	# uid elegiria a la lejana, y no lo hace.
	var gunner := _unit("artillery", ENEMY)
	var far := _unit("infantry", PLAYER)
	var near := _unit("infantry", PLAYER)
	var e := _encounter([far, near, gunner])
	gunner.position = Vector2i(4, 0)
	far.position = Vector2i(4, 3)
	near.position = Vector2i(4, 2)
	var plan := AIScript.plan_turn(e, gunner.uid)
	assert_array(_actions(plan)).is_equal(["attack"])
	assert_int(plan[0]["target"]).is_equal(near.uid)

func test_a_dead_heat_goes_to_the_lowest_uid_and_the_plan_never_wavers() -> void:
	# Dos rivales indistinguibles: mismo tipo, mismos HP, misma distancia. El
	# unico desempate que queda es el uid, y por eso el plan es reproducible.
	var enemy := _unit("infantry", ENEMY)
	var first := _unit("infantry", PLAYER)
	var second := _unit("infantry", PLAYER)
	var e := _encounter([first, second, enemy])
	enemy.position = Vector2i(4, 4)
	first.position = Vector2i(4, 5)
	second.position = Vector2i(3, 4)
	var once := AIScript.plan_turn(e, enemy.uid)
	var twice := AIScript.plan_turn(e, enemy.uid)
	assert_int(once[0]["target"]).is_equal(first.uid)
	assert_array(once).is_equal(twice)

# ── Artillery keeps its distance ─────────────────────────────────────

func test_artillery_does_not_walk_into_its_own_minimum_range() -> void:
	var gunner := _unit("artillery", ENEMY)   # move 1, range 3, min_range 2
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, gunner])
	gunner.position = Vector2i(4, 2)
	player.position = Vector2i(4, 4)          # distance 2: already a firing solution
	var plan := AIScript.plan_turn(e, gunner.uid)
	# It should shoot from where it stands rather than close the gap.
	assert_array(_actions(plan)).is_equal(["attack"])

func test_artillery_prefers_a_firing_position_over_walking_closer() -> void:
	var gunner := _unit("artillery", ENEMY)
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, gunner])
	gunner.position = Vector2i(4, 0)
	player.position = Vector2i(4, 4)          # distance 4, one step out of range
	var plan := AIScript.plan_turn(e, gunner.uid)
	assert_array(_actions(plan)).is_equal(["move", "attack"])

func test_artillery_pinned_at_contact_backs_off_to_a_firing_cell() -> void:
	# Pegada a un rival, la artilleria no tiene tiro: esta por dentro de su
	# alcance minimo. Antes aguantaba ahi; ahora se retira a una casilla desde la
	# que si dispara y dispara desde ella (T038).
	var gunner := _unit("artillery", ENEMY)        # move 1, range 3, min_range 2
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, gunner])
	gunner.position = Vector2i(4, 4)
	player.position = Vector2i(4, 5)               # distancia 1: a bocajarro
	var plan := AIScript.plan_turn(e, gunner.uid)
	assert_array(_actions(plan)).is_equal(["move", "attack"])
	var gap: int = Rules.manhattan(plan[0]["to"], player.position)
	assert_int(gap).is_greater_equal(gunner.min_range())
	assert_int(gap).is_less_equal(gunner.attack_range())
	assert_int(plan[1]["target"]).is_equal(player.uid)

func test_artillery_with_nowhere_to_back_off_to_digs_in_instead() -> void:
	# Acorralada en la esquina y con los dos huecos ocupados: sin casilla de tiro
	# no inventa un disparo imposible, se atrinchera (ahi sigue mandando T039).
	var gunner := _unit("artillery", ENEMY)
	var a := _unit("infantry", PLAYER)
	var b := _unit("infantry", PLAYER)
	var e := _encounter([a, b, gunner])
	gunner.position = Vector2i(0, 0)
	a.position = Vector2i(1, 0)
	b.position = Vector2i(0, 1)
	assert_array(_actions(AIScript.plan_turn(e, gunner.uid))).is_equal(["defend"])

# ── Defender en vez de esperar (T039) ────────────────────────────────

func test_it_digs_in_after_closing_when_nothing_is_reachable_this_turn() -> void:
	# Infanteria (mueve 3, alcance 1) a siete filas: ni tras moverse llega. Antes
	# el plan era solo "move" y CombatManager cerraba el turno con la unidad
	# mirando; ahora se atrinchera en la casilla nueva.
	var enemy := _unit("infantry", ENEMY)
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, enemy])
	enemy.position = Vector2i(4, 0)
	player.position = Vector2i(4, 7)
	var plan := AIScript.plan_turn(e, enemy.uid)
	assert_array(_actions(plan)).is_equal(["move", "defend"])

func test_a_unit_that_cannot_move_and_cannot_reach_defends_in_place() -> void:
	var enemy := _unit("infantry", ENEMY)
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, enemy])
	enemy.position = Vector2i(4, 0)
	player.position = Vector2i(4, 7)
	enemy.moved_this_turn = true   # ya gasto su movimiento: no hay celda nueva
	assert_array(_actions(AIScript.plan_turn(e, enemy.uid))).is_equal(["defend"])

func test_a_unit_already_defending_with_nothing_to_hit_only_waits() -> void:
	# El unico caso en que "wait" sigue siendo la respuesta: ya esta en guardia
	# y no hay a quien disparar.
	var enemy := _unit("infantry", ENEMY)
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, enemy])
	enemy.position = Vector2i(4, 0)
	player.position = Vector2i(4, 7)
	enemy.moved_this_turn = true
	enemy.defending = true
	assert_array(_actions(AIScript.plan_turn(e, enemy.uid))).is_equal(["wait"])

func test_the_defend_plan_is_executable_by_the_board() -> void:
	# El plan no vale nada si el modelo lo rechaza: defend() tras move() tiene
	# que cerrar el turno con la unidad en guardia. Hay un segundo jugador sin
	# actuar para que la ronda no termine ahi mismo (begin_turn quita la guardia).
	var enemy := _unit("infantry", ENEMY)
	var player := _unit("infantry", PLAYER)
	var reserve := _unit("infantry", PLAYER)
	var e := _encounter([player, reserve, enemy])
	enemy.position = Vector2i(4, 0)
	player.position = Vector2i(4, 7)
	reserve.position = Vector2i(0, 7)
	for step in AIScript.plan_turn(e, enemy.uid):
		_apply(e, enemy.uid, step)
	assert_bool(enemy.defending).is_true()
	assert_bool(enemy.has_acted).is_true()
	assert_int(enemy.position.y).is_equal(3)

func test_it_never_plans_no_action_with_a_reachable_target() -> void:
	# SC-007: desde cualquier casilla a tiro (moviendo si hace falta) el plan
	# termina en ataque y nunca en "wait" ni en "defend".
	var player := _unit("infantry", PLAYER)
	var enemy := _unit("infantry", ENEMY)
	var e := _encounter([player, enemy])
	player.position = Vector2i(4, 4)
	var reach: int = enemy.move_range() + enemy.attack_range()
	for x in range(e.board_size.x):
		for y in range(e.board_size.y):
			var cell := Vector2i(x, y)
			if cell == player.position or Rules.manhattan(cell, player.position) > reach:
				continue
			enemy.position = cell
			enemy.begin_turn()
			var actions := _actions(AIScript.plan_turn(e, enemy.uid))
			assert_array(actions).override_failure_message(
				"desde %s el plan fue %s" % [cell, actions]).contains(["attack"])
			assert_array(actions).not_contains(["wait", "defend"])

func test_the_same_ai_drives_the_player_side_against_the_enemy() -> void:
	# El "rival" es el bando contrario, no "el jugador": la guarnicion que pelea
	# sola (AutoResolver) usa exactamente esta IA.
	var enemy := _unit("infantry", ENEMY)
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, enemy])
	enemy.position = Vector2i(4, 3)
	player.position = Vector2i(4, 4)
	var plan := AIScript.plan_turn(e, player.uid)
	assert_array(_actions(plan)).is_equal(["attack"])
	assert_int(plan[0]["target"]).is_equal(enemy.uid)
	assert_int(AIScript.rival_side(PLAYER)).is_equal(ENEMY)
	assert_int(AIScript.rival_side(ENEMY)).is_equal(PLAYER)

func _apply(e: Encounter, uid: int, step: Dictionary) -> void:
	match step.get("action", "wait"):
		"move":
			e.move_unit(uid, step["to"])
		"attack":
			e.attack(uid, step["target"])
		"defend":
			e.defend(uid)
		_:
			e.wait_unit(uid)

# ── Degenerate cases ─────────────────────────────────────────────────

func test_it_waits_when_there_is_nobody_left_to_fight() -> void:
	var enemy := _unit("infantry", ENEMY)
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, enemy])
	player.take_damage(player.max_hp)
	assert_array(_actions(AIScript.plan_turn(e, enemy.uid))).is_equal(["wait"])

func test_a_dead_unit_plans_nothing() -> void:
	var enemy := _unit("infantry", ENEMY)
	var player := _unit("infantry", PLAYER)
	var e := _encounter([player, enemy])
	enemy.take_damage(enemy.max_hp)
	assert_array(_actions(AIScript.plan_turn(e, enemy.uid))).is_equal(["wait"])

# ── The loop actually terminates ─────────────────────────────────────

func test_two_ai_sides_resolve_the_encounter_without_stalling() -> void:
	# Both sides driven by the AI. If the AI ever refused to close, this would
	# run to the round limit instead of a clean kill — which is exactly the
	# failure mode worth catching.
	var units: Array = [_unit("infantry", PLAYER), _unit("infantry", ENEMY)]
	var e := _encounter(units)
	var guard := 0
	while e.is_active() and guard < 400:
		guard += 1
		var active: CombatUnit = e.active_unit()
		if active == null:
			break
		var uid: int = active.uid
		for step in AIScript.plan_turn(e, uid):
			_apply(e, uid, step)
			if not e.is_active():
				break
		if e.is_active() and e.active_unit() != null and e.active_unit().uid == uid:
			e.end_turn()
	assert_bool(e.is_resolved()).is_true()
	assert_int(e.state).is_not_equal(Encounter.State.TIMEOUT)
