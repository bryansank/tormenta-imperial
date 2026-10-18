extends GdUnitTestSuite
## Ronda final de la 1.1 (decision de Bryan): defendiendo la base, 2 de cada 3
## caidos vuelven heridos; siempre cae al menos uno; mueren primero los baratos.
## Y la prevision de fuerza cuenta cuerpos y escala al cuadrado.

const CM := preload("res://scripts/services/CombatManager.gd")
const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")

func _units(ids: Array) -> Array:
	var out: Array = []
	var uid := 1
	for id in ids:
		out.append(CombatUnit.create(uid, String(id), Encounter.PLAYER, 1.0))
		uid += 1
	return out

func test_two_of_three_come_back_and_one_always_falls() -> void:
	assert_int(CM.defense_wounded([]).size()).is_equal(0)
	assert_int(CM.defense_wounded(_units(["infantry"])).size()).is_equal(0)
	assert_int(CM.defense_wounded(_units(["infantry", "infantry"])).size()).is_equal(1)
	assert_int(CM.defense_wounded(_units(["infantry", "infantry", "infantry"])).size()).is_equal(2)
	var eight := _units(["vehicle", "vehicle", "vehicle", "vehicle", "vehicle", "dreadnought", "fighter", "fighter"])
	assert_int(CM.defense_wounded(eight).size()).is_equal(5)

func test_the_cheapest_fall_first() -> void:
	var fallen := _units(["infantry", "vehicle", "artillery"])
	var back: Array = CM.defense_wounded(fallen)
	var ids: Array = back.map(func(u): return u.unit_id)
	assert_bool(ids.has("infantry")).is_false()
	assert_bool(ids.has("vehicle")).is_true()

func test_column_strength_counts_bodies_and_scale_twice() -> void:
	var two_guns: float = Generator.column_strength({"artillery": 2})
	var three_inf_scaled: float = Generator.column_strength({"infantry": 3}, 1.5)
	# 56 x 2 = 112 contra 30 x 2,25 x 3 = 202,5: la columna de 2 ya no es favorita.
	assert_float(two_guns).is_equal_approx(112.0, 0.01)
	assert_float(three_inf_scaled).is_equal_approx(202.5, 0.01)
	assert_str(CombatRules.odds_label(two_guns, three_inf_scaled)).is_equal("hard")
