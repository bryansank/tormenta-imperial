extends GdUnitTestSuite
## Incursion (1 combate) y expedicion corta (3 combates), doc 21 §3.3 (D3 = A):
## el mapa sale entero de la oferta, se ve antes de lanzar y se rehace igual al
## cargar; botin exclusivo en los nodos; 30 % de cura entre combates; retirada
## enemiga por debajo del 30 % (D7 = B) y "resolver solo" con fuerza doble (D6).
##
## Escrito SIN EJECUTAR (regla de Bryan: un solo pase de pruebas al final).

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const ExpeditionScript := preload("res://scripts/combat/Expedition.gd")
const EncounterScript := preload("res://scripts/combat/Encounter.gd")
const UnitScript := preload("res://scripts/combat/CombatUnit.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")

func _raid(seed_value: int = 77, flavor: String = "bandits") -> Dictionary:
	return {"id": 1, "kind": Generator.KIND_RAID, "flavor": flavor, "seed": seed_value, "era": 2, "blueprint": ""}

func _expedition_offer(seed_value: int = 4242, blueprint: String = "") -> Dictionary:
	return {"id": 2, "kind": Generator.KIND_EXPEDITION, "flavor": "", "seed": seed_value, "era": 2, "blueprint": blueprint}

# ── Mapas ────────────────────────────────────────────────────────────

func test_a_raid_is_one_fight_with_exclusive_loot() -> void:
	var map: Array = Generator.sortie_map(_raid())
	assert_int(map.size()).is_equal(1)
	assert_int(Generator.fights_on_path(map)).is_equal(1)
	var loot: Dictionary = map[0]["loot"]
	# Una incursion de piratas (costa, aire y mar) trae un repuesto de mas.
	var extra: int = GameConfig.combat_loot_coastal_parts if Generator.offer_is_coastal(_raid()) else 0
	assert_int(int(loot.get("parts", 0))).is_between(GameConfig.combat_loot_raid_parts.x + extra, GameConfig.combat_loot_raid_parts.y + extra)
	assert_int(int(loot.get("colonists", 0))).is_between(GameConfig.combat_loot_raid_colonists.x, GameConfig.combat_loot_raid_colonists.y)

func test_the_outpost_pays_a_tithe_discount() -> void:
	var map: Array = Generator.sortie_map(_raid(5, Generator.FLAVOR_OUTPOST))
	assert_int(int(map[0]["loot"].get("tithe_pct", 0))).is_greater(0)
	assert_bool(map[0]["loot"].has("colonists")).is_false()

func test_the_short_expedition_is_three_fights_and_reaches_the_boss() -> void:
	for seed_value in [1, 2, 3, 99, 4242]:
		var map: Array = Generator.sortie_map(_expedition_offer(seed_value))
		assert_int(Generator.fights_on_path(map)).is_equal(3)
		assert_bool(Generator.every_node_reaches_boss(map)).is_true()

func test_the_same_offer_gives_the_same_map() -> void:
	var a: Array = Generator.sortie_map(_expedition_offer(31337))
	var b: Array = Generator.sortie_map(_expedition_offer(31337))
	assert_str(JSON.stringify(a)).is_equal(JSON.stringify(b))

func test_the_boss_carries_the_blueprint_and_the_big_loot() -> void:
	var map: Array = Generator.sortie_map(_expedition_offer(8, "infirmary"))
	var boss: Dictionary = map[Generator.boss_index(map)]
	assert_str(String(boss["loot"].get("blueprint", ""))).is_equal("infirmary")
	assert_int(int(boss["loot"].get("parts", 0))).is_equal(GameConfig.combat_loot_expedition_boss_parts)
	var path: Dictionary = Generator.path_loot(map)
	assert_array(path.get("blueprints", [])).is_equal(["infirmary"])

func test_sortie_gold_is_half_the_old_curve() -> void:
	var map: Array = Generator.sortie_map(_raid())
	var node: Dictionary = map[0].duplicate(true)
	var fixed: Dictionary = Generator.node_rewards(node, 2)
	node.erase("rewards")
	var curve: Dictionary = Generator.node_rewards(node, 2)
	assert_int(int(fixed["gold"])).is_less(int(curve["gold"]))

# ── Expedicion corta ─────────────────────────────────────────────────

func test_the_party_heals_between_fights_of_a_short_expedition() -> void:
	var run: Expedition = ExpeditionScript.create_sortie(1, _expedition_offer(), {"infantry": 3}, 50.0)
	for unit in run.party:
		unit.take_damage(int(unit.max_hp / 2))
	var before: int = run.party[0].hp
	var events: Array = run.mark_cleared()
	var kinds: Array = events.map(func(e): return String(e["e"]))
	assert_array(kinds).contains(["party_healed"])
	assert_int(run.party[0].hp).is_greater(before)
	assert_int(int(run.loot.get("parts", 0))).is_equal(GameConfig.combat_loot_expedition_node_parts)

func test_the_old_expedition_still_does_not_heal() -> void:
	var run: Expedition = ExpeditionScript.create(1, 4242, {"infantry": 3}, 50.0, 1)
	for unit in run.party:
		unit.take_damage(10)
	var before: int = run.party[0].hp
	run.mark_cleared()
	assert_int(run.party[0].hp).is_equal(before)

func test_a_sortie_survives_save_and_load_with_its_map_and_loot() -> void:
	var run: Expedition = ExpeditionScript.create_sortie(3, _expedition_offer(555, "scrapyard"), {"infantry": 2}, 60.0)
	run.mark_cleared()
	var data: Dictionary = JSON.parse_string(JSON.stringify(run.to_dict()))
	var loaded: Expedition = ExpeditionScript.from_dict(data, 2)
	assert_str(loaded.kind).is_equal(Generator.KIND_EXPEDITION)
	assert_int(loaded.map.size()).is_equal(run.map.size())
	assert_int(int(loaded.loot.get("parts", 0))).is_equal(int(run.loot.get("parts", 0)))
	assert_bool(bool(loaded.map[0]["cleared"])).is_true()

func test_an_old_save_without_kind_rebuilds_the_old_map() -> void:
	var run: Expedition = ExpeditionScript.create(1, 4242, {"infantry": 2}, 60.0, 1)
	var data: Dictionary = run.to_dict()
	data.erase("kind")
	data.erase("offer")
	data.erase("loot")
	var loaded: Expedition = ExpeditionScript.from_dict(data, 1)
	assert_str(loaded.kind).is_equal("")
	assert_int(loaded.map.size()).is_equal(run.map.size())

# ── Retirada y resolver solo ─────────────────────────────────────────

func _units(enemy_hp_frac: float) -> Array:
	var units: Array = []
	units.append(UnitScript.create(1, "infantry", EncounterScript.PLAYER, 1.0))
	units.append(UnitScript.create(2, "infantry", EncounterScript.PLAYER, 1.0))
	var e1 = UnitScript.create(3, "infantry", EncounterScript.ENEMY, 1.0)
	var e2 = UnitScript.create(4, "infantry", EncounterScript.ENEMY, 1.0)
	units.append(e1)
	units.append(e2)
	return units

func test_the_enemy_routs_below_the_ratio_on_an_expedition_board() -> void:
	var units: Array = _units(1.0)
	var encounter: Encounter = EncounterScript.create(units, 0, false, false, [], true)
	encounter.start()
	# Se hunde la vida enemiga por debajo del 30 % y se pasa el turno.
	for unit in encounter.living(EncounterScript.ENEMY):
		unit.hp = maxi(1, int(float(unit.max_hp) * 0.1))
	var events: Array = encounter.end_turn()
	var kinds: Array = events.map(func(e): return String(e.get("e", "")))
	assert_array(kinds).contains(["enemy_routed", "encounter_ended"])
	assert_bool(encounter.player_won()).is_true()
	assert_bool(encounter.routed).is_true()

func test_a_defence_never_routs() -> void:
	var units: Array = _units(1.0)
	var encounter: Encounter = EncounterScript.create(units, 0, false, true, [], true)
	assert_bool(encounter.enemy_can_rout).is_false()
	encounter.start()
	for unit in encounter.living(EncounterScript.ENEMY):
		unit.hp = 1
	assert_bool(encounter.should_rout()).is_false()

func test_rout_is_off_by_default() -> void:
	var encounter: Encounter = EncounterScript.create(_units(1.0), 0, false)
	assert_bool(encounter.enemy_can_rout).is_false()

func test_auto_resolve_needs_double_strength() -> void:
	assert_bool(Rules.can_auto_resolve(200.0, 100.0)).is_true()
	assert_bool(Rules.can_auto_resolve(199.0, 100.0)).is_false()
	assert_bool(Rules.can_auto_resolve(0.0, 0.0)).is_false()

func test_odds_labels() -> void:
	assert_str(Rules.odds_label(130.0, 100.0)).is_equal("favorable")
	assert_str(Rules.odds_label(100.0, 100.0)).is_equal("even")
	assert_str(Rules.odds_label(80.0, 100.0)).is_equal("hard")

func test_side_strength_counts_wounds_and_scale() -> void:
	var fresh = UnitScript.create(1, "infantry", EncounterScript.ENEMY, 1.0)
	var tough = UnitScript.create(2, "infantry", EncounterScript.ENEMY, 2.0)
	assert_float(Rules.side_strength([tough], EncounterScript.ENEMY)).is_greater(Rules.side_strength([fresh], EncounterScript.ENEMY))
	fresh.take_damage(int(fresh.max_hp / 2))
	assert_float(Rules.side_strength([fresh], EncounterScript.ENEMY)).is_less(float(fresh.power()))
