extends GdUnitTestSuite
## Ventaja por tipo (piedra-papel-tijera, GameConfig.combat_type_advantage):
## artilleria > vehiculo > infanteria > artilleria. Regla del modelo puro
## (CombatRules.damage) que aplican igual el jugador, la IA y AutoResolver.

const Rules := preload("res://scripts/combat/CombatRules.gd")
const AIScript := preload("res://scripts/combat/CombatAI.gd")
const ResolverScript := preload("res://scripts/combat/AutoResolver.gd")
const EncounterScript := preload("res://scripts/combat/Encounter.gd")
const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")

const PLAYER := 0
const ENEMY := 1
const TYPES := ["infantry", "artillery", "vehicle"]

var _uid := 0
var _saved: Dictionary

func before_test() -> void:
	_uid = 0
	_saved = GameConfig.combat_type_advantage.duplicate(true)

func after_test() -> void:
	GameConfig.combat_type_advantage = _saved

func _unit(unit_id: String, side: int) -> CombatUnit:
	_uid += 1
	return CombatUnitScript.create(_uid, unit_id, side, 1.0)

# ── El circulo ───────────────────────────────────────────────────────

func test_the_circle_is_artillery_vehicle_infantry() -> void:
	assert_int(Rules.type_matchup("artillery", "vehicle")).is_equal(1)
	assert_int(Rules.type_matchup("vehicle", "infantry")).is_equal(1)
	assert_int(Rules.type_matchup("infantry", "artillery")).is_equal(1)

func test_every_type_beats_one_and_loses_to_one() -> void:
	for a in TYPES:
		var wins := 0
		var losses := 0
		for b in TYPES:
			var m: int = Rules.type_matchup(a, b)
			# Simetrico: si a gana a b, b pierde contra a.
			assert_int(Rules.type_matchup(b, a)).is_equal(-m)
			if m > 0:
				wins += 1
			elif m < 0:
				losses += 1
		assert_int(wins).is_equal(1)
		assert_int(losses).is_equal(1)
		assert_int(Rules.type_matchup(a, a)).is_equal(0)

func test_unknown_types_have_no_edge() -> void:
	# Un tipo sin fila en la tabla es neutro (mar y aire ya tienen la suya).
	assert_int(Rules.type_matchup("no_such_unit", "infantry")).is_equal(0)
	assert_float(Rules.type_multiplier("no_such_unit", "vehicle")).is_equal(1.0)

# ── Multiplicadores ──────────────────────────────────────────────────

func test_advantage_and_disadvantage_scale_the_net_damage() -> void:
	# Neto (atk - def) por 1,5 o 0,75, redondeado.
	var cases := [
		["artillery", "vehicle", 14],   # (14-5) x1,5 = 13,5
		["vehicle", "infantry", 15],    # (12-2) x1,5
		["infantry", "artillery", 11],  # (8-1) x1,5 = 10,5
		["vehicle", "artillery", 8],    # (12-1) x0,75 = 8,25
		["infantry", "vehicle", 2],     # (8-5) x0,75 = 2,25
		["artillery", "infantry", 9],   # (14-2) x0,75
		["infantry", "infantry", 6],    # sin ventaja
	]
	for c in cases:
		var a := _unit(c[0], PLAYER)
		var t := _unit(c[1], ENEMY)
		assert_int(Rules.damage(a, t)).override_failure_message("%s -> %s" % [c[0], c[1]]).is_equal(c[2])

func test_the_multipliers_live_in_game_config() -> void:
	GameConfig.combat_type_advantage["advantage"] = 2.0
	GameConfig.combat_type_advantage["disadvantage"] = 0.5
	assert_int(Rules.damage(_unit("artillery", PLAYER), _unit("vehicle", ENEMY))).is_equal(18)
	assert_int(Rules.damage(_unit("vehicle", PLAYER), _unit("artillery", ENEMY))).is_equal(6)

func test_damage_never_drops_below_one_even_at_a_disadvantage() -> void:
	var a := _unit("infantry", PLAYER)
	var t := _unit("vehicle", ENEMY)
	t.defending = true                     # def 10: neto 1, x0,75
	assert_int(Rules.damage(a, t)).is_equal(1)

func test_without_the_circle_damage_is_attack_minus_defense() -> void:
	GameConfig.combat_type_advantage["beats"] = {}
	assert_int(Rules.damage(_unit("artillery", PLAYER), _unit("vehicle", ENEMY))).is_equal(9)

# ── La IA ────────────────────────────────────────────────────────────

func test_the_ai_counts_the_type_edge_in_the_damage_it_does() -> void:
	# Un blindado enemigo con dos rivales al lado: infanteria (su buen objetivo) y
	# artilleria (su mal objetivo). Mirando solo el dano (peso de la amenaza 0),
	# la ventaja por tipo decide: 15 de 100 a la infanteria pesa mas que 8 de 75
	# al canon. Sin el circulo, el canon (11 de 75) vuelve a ser el mejor golpe.
	var saved_w: float = GameConfig.combat_ai_threat_weight
	GameConfig.combat_ai_threat_weight = 0.0
	var tank := _unit("vehicle", ENEMY)
	var foot := _unit("infantry", PLAYER)
	var gun := _unit("artillery", PLAYER)
	var e: Encounter = EncounterScript.create([foot, gun, tank], 0, false)
	e.start()
	tank.position = Vector2i(4, 4)
	foot.position = Vector2i(3, 4)
	gun.position = Vector2i(5, 4)
	var plan: Array = AIScript.plan_turn(e, tank.uid)
	assert_int(plan[plan.size() - 1]["target"]).is_equal(foot.uid)
	GameConfig.combat_type_advantage["beats"] = {}
	plan = AIScript.plan_turn(e, tank.uid)
	assert_int(plan[plan.size() - 1]["target"]).is_equal(gun.uid)
	GameConfig.combat_ai_threat_weight = saved_w

func test_with_threat_the_ai_breaks_the_gun_that_counters_it() -> void:
	# El mismo tablero con la amenaza pesando (la serie, 1.1): el canon le hace 14
	# al blindado y la infanteria 2, asi que el blindado va a por el canon aunque
	# le pegue con desventaja. Es lo que impide que la guarnicion se deje romper
	# por los canones del asedio (docs/15 §8 "La IA").
	var saved_w: float = GameConfig.combat_ai_threat_weight
	GameConfig.combat_ai_threat_weight = 1.0
	var tank := _unit("vehicle", ENEMY)
	var foot := _unit("infantry", PLAYER)
	var gun := _unit("artillery", PLAYER)
	var e: Encounter = EncounterScript.create([foot, gun, tank], 0, false)
	e.start()
	tank.position = Vector2i(4, 4)
	foot.position = Vector2i(3, 4)
	gun.position = Vector2i(5, 4)
	var plan: Array = AIScript.plan_turn(e, tank.uid)
	assert_int(plan[plan.size() - 1]["target"]).is_equal(gun.uid)
	GameConfig.combat_ai_threat_weight = saved_w

func test_a_kill_still_comes_before_the_type_edge() -> void:
	# Rematar sigue mandando: un canon casi muerto cae antes que la infanteria.
	var tank := _unit("vehicle", ENEMY)
	var foot := _unit("infantry", PLAYER)
	var gun := _unit("artillery", PLAYER)
	var e: Encounter = EncounterScript.create([foot, gun, tank], 0, false)
	e.start()
	tank.position = Vector2i(4, 4)
	foot.position = Vector2i(3, 4)
	gun.position = Vector2i(5, 4)
	gun.hp = 3
	var plan: Array = AIScript.plan_turn(e, tank.uid)
	assert_int(plan[plan.size() - 1]["target"]).is_equal(gun.uid)

# ── AutoResolver: la misma regla ─────────────────────────────────────

func test_auto_resolver_hits_with_the_same_multipliers() -> void:
	var units: Array = [_unit("artillery", PLAYER), _unit("vehicle", ENEMY)]
	var e: Encounter = EncounterScript.create(units, 0, false, true)
	var gun_uid: int = units[0].uid
	var result: Dictionary = ResolverScript.resolve(e)
	var hits: Array = []
	for ev in result["events"]:
		if ev.get("e", "") == "unit_attacked" and int(ev["attacker"]) == gun_uid:
			hits.append(int(ev["damage"]))
	assert_array(hits).is_not_empty()
	# Con ventaja: 14 al blindado a pecho descubierto, 6 si esta en guardia; con
	# el azar del dano (feat/ritmo-colono), dentro de su rango.
	var s: float = GameConfig.combat_damage_spread
	for d in hits:
		var open_hit: bool = d >= roundi(14.0 * (1.0 - s)) and d <= roundi(14.0 * (1.0 + s))
		var guard_hit: bool = d >= roundi(6.0 * (1.0 - s)) and d <= roundi(6.0 * (1.0 + s))
		assert_bool(open_hit or guard_hit).override_failure_message("dano %d" % d).is_true()
