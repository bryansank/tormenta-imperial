extends GdUnitTestSuite
## Enfermeria (feat/edificios-militares, doc 21 §6.3 n.º 10, docs/15 §14):
## las cuentas puras. De cada tres caidos vuelve uno (por abajo, los de mas
## Poder primero), -1 de moral por baja en vez de -3 y +30 % de cura entre
## combates de una mision. La conexion con el mapa (hay o no Enfermeria en
## marcha) la prueba tests/buildings/test_military_buildings.gd.
##
## Escrita sin correr (regla de Bryan: un solo pase de pruebas al final).

const Rules := preload("res://scripts/combat/CombatRules.gd")
const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")
const ExpeditionScript := preload("res://scripts/combat/Expedition.gd")
const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")

func _dead(uid: int, unit_id: String) -> CombatUnit:
	var u := CombatUnitScript.create(uid, unit_id, 0, 1.0)
	u.take_damage(u.max_hp)
	return u

# ── Cuantos vuelven ──

func test_one_in_three_comes_back_rounded_down() -> void:
	var every := GameConfig.infirmary_return_every
	assert_int(every).is_equal(3)
	assert_int(Rules.infirmary_returns(0, every)).is_equal(0)
	assert_int(Rules.infirmary_returns(2, every)).is_equal(0)
	assert_int(Rules.infirmary_returns(3, every)).is_equal(1)
	assert_int(Rules.infirmary_returns(5, every)).is_equal(1)
	assert_int(Rules.infirmary_returns(6, every)).is_equal(2)
	assert_int(Rules.infirmary_returns(6, 0)).is_equal(0)

func test_the_most_valuable_fallen_come_back_first() -> void:
	var fallen := [_dead(1, "infantry"), _dead(2, "vehicle"), _dead(3, "artillery"), _dead(4, "infantry")]
	var back := Rules.pick_recovered(fallen, 2)
	assert_int(back.size()).is_equal(2)
	assert_str(back[0].unit_id).is_equal("vehicle")
	assert_str(back[1].unit_id).is_equal("artillery")
	# No toca la lista de quien llama.
	assert_int(fallen.size()).is_equal(4)

func test_picking_more_than_there_are_returns_them_all() -> void:
	var fallen := [_dead(1, "infantry")]
	assert_int(Rules.pick_recovered(fallen, 5).size()).is_equal(1)
	assert_int(Rules.pick_recovered([], 2).size()).is_equal(0)

# ── Moral ──

func test_each_loss_costs_one_morale_instead_of_three() -> void:
	var plain := Rules.morale_delta(false, 3)
	var cared := Rules.morale_delta(false, 3, GameConfig.infirmary_morale_per_casualty)
	assert_int(plain).is_equal(-9)
	assert_int(cared).is_equal(-3)
	# -1 sigue siendo "el de siempre".
	assert_int(Rules.morale_delta(true, 2, -1.0)).is_equal(Rules.morale_delta(true, 2))

# ── Expedicion: cura y evacuados ──

func _run(kind: String) -> Expedition:
	var offer := {"id": 1, "kind": kind, "flavor": "", "seed": 4242, "era": 2, "blueprint": ""}
	var run: Expedition = ExpeditionScript.create_sortie(1, offer, {"infantry": 3}, 50.0)
	return run

func test_heal_between_fights_goes_up_thirty_percent() -> void:
	var run := _run(Generator.KIND_EXPEDITION)
	var base := run.heal_between_pct()
	assert_float(base).is_equal_approx(GameConfig.combat_expedition_heal_between, 0.0001)
	run.heal_mult = GameConfig.infirmary_heal_mult
	assert_float(run.heal_between_pct()).is_equal_approx(base * 1.3, 0.0001)

func test_a_raid_still_does_not_heal() -> void:
	var run := _run(Generator.KIND_RAID)
	run.heal_mult = GameConfig.infirmary_heal_mult
	assert_float(run.heal_between_pct()).is_equal(0.0)

func test_evacuated_leave_the_column_and_are_not_casualties() -> void:
	var run := _run(Generator.KIND_EXPEDITION)
	assert_int(run.party.size()).is_equal(3)
	var a: CombatUnit = run.party[0]
	var b: CombatUnit = run.party[1]
	a.take_damage(a.max_hp)
	b.take_damage(b.max_hp)
	var out := run.evacuate([a.uid])
	assert_dict(out).is_equal({"infantry": 1})
	assert_int(run.party.size()).is_equal(2)
	var summary := run.result_summary()
	assert_dict(summary["casualties"]).is_equal({"infantry": 1})
	assert_dict(summary["evacuated"]).is_equal({"infantry": 1})
	assert_dict(summary["survivors"]).is_equal({"infantry": 1})

func test_only_the_fallen_can_be_evacuated() -> void:
	var run := _run(Generator.KIND_EXPEDITION)
	var alive: CombatUnit = run.party[0]
	assert_dict(run.evacuate([alive.uid])).is_empty()
	assert_int(run.party.size()).is_equal(3)

func test_evacuated_travel_in_the_save() -> void:
	var run := _run(Generator.KIND_EXPEDITION)
	var a: CombatUnit = run.party[0]
	a.take_damage(a.max_hp)
	run.evacuate([a.uid])
	var back: Expedition = ExpeditionScript.from_dict(run.to_dict())
	assert_object(back).is_not_null()
	assert_dict(back.evacuated).is_equal({"infantry": 1})
	assert_int(back.party.size()).is_equal(2)

func test_an_old_save_without_evacuated_loads_with_none() -> void:
	var run := _run(Generator.KIND_EXPEDITION)
	var data := run.to_dict()
	data.erase("evacuated")
	var back: Expedition = ExpeditionScript.from_dict(data)
	assert_dict(back.evacuated).is_empty()
