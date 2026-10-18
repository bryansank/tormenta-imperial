extends GdUnitTestSuite
## Aire y mar (feat/aire-mar-reglas): las salidas de costa (agua en el tablero y
## barcos enemigos segun la era) y los dirigibles de la Regencia en la ultima
## oleada del Ataque Final. Todo puro y con semilla: la misma oferta es la misma
## costa, el mismo asedio es el mismo asedio.

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const AuditScript := preload("res://scripts/combat/FinalAudit.gd")
const ExpeditionScript := preload("res://scripts/combat/Expedition.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")

const SHIPS := ["torpedo_boat", "gunboat", "dreadnought"]

## Una expedicion al Puerto: la semilla multiplo de 5 da SORTIE_DEST_DOCK.
func _dock_offer(era: int, seed_value: int = 10) -> Dictionary:
	return {"id": 1, "kind": Generator.KIND_EXPEDITION, "seed": seed_value, "era": era, "blueprint": ""}

func _ships_in(roster: Dictionary) -> int:
	var total := 0
	for id in SHIPS:
		total += int(roster.get(id, 0))
	return total

# ── Que oferta es de costa ───────────────────────────────────────────

func test_the_dock_expedition_is_coastal_from_era_two() -> void:
	assert_str(Generator.offer_name_key(_dock_offer(2))).is_equal("SORTIE_DEST_DOCK")
	assert_bool(Generator.offer_is_coastal(_dock_offer(1))).is_false()
	assert_bool(Generator.offer_is_coastal(_dock_offer(2))).is_true()
	assert_bool(Generator.offer_is_coastal(_dock_offer(3))).is_true()

func test_other_expeditions_and_the_outpost_are_never_coastal() -> void:
	var factory := {"id": 2, "kind": Generator.KIND_EXPEDITION, "seed": 11, "era": 3, "blueprint": ""}
	assert_bool(Generator.offer_is_coastal(factory)).is_false()
	for seed_value in range(1, 40):
		var outpost := {"id": 3, "kind": Generator.KIND_RAID, "flavor": Generator.FLAVOR_OUTPOST, "seed": seed_value, "era": 3}
		assert_bool(Generator.offer_is_coastal(outpost)).is_false()

func test_some_bandit_raids_are_pirates_and_it_is_decided_by_the_seed() -> void:
	var coastal := 0
	for seed_value in range(1, 200):
		var raid := {"id": 4, "kind": Generator.KIND_RAID, "flavor": Generator.FLAVOR_BANDITS, "seed": seed_value, "era": 2}
		var first: bool = Generator.offer_is_coastal(raid)
		assert_bool(Generator.offer_is_coastal(raid)).is_equal(first)
		if first:
			coastal += 1
	assert_int(coastal).is_greater(0)
	assert_int(coastal).is_less(199)

# ── El mapa de costa ─────────────────────────────────────────────────

func test_every_node_of_a_coastal_map_has_water_and_ships() -> void:
	for era in [2, 3]:
		var map: Array = Generator.sortie_map(_dock_offer(era))
		assert_bool(Generator.map_has_water(map)).is_true()
		for node in map:
			assert_bool(Generator.node_is_coastal(node)).is_true()
			assert_bool(Rules.has_water(Generator.node_terrain(node, GameConfig.combat_board_size))).is_true()
			var roster: Dictionary = node["enemy_roster"]
			assert_int(_ships_in(roster)).is_greater(0)
			assert_int(Generator.roster_size(roster)).is_less_equal(GameConfig.combat_deploy_cap)
			# Siempre queda algo en tierra que pelear en la playa.
			assert_int(Generator.roster_size(roster) - _ships_in(roster)).is_greater_equal(1)

func test_era_three_boss_brings_a_dreadnought_and_era_two_does_not() -> void:
	var map3: Array = Generator.sortie_map(_dock_offer(3))
	var boss3: Dictionary = map3[Generator.boss_index(map3)]
	assert_int(int(boss3["enemy_roster"].get("dreadnought", 0))).is_greater(0)
	var map2: Array = Generator.sortie_map(_dock_offer(2))
	for node in map2:
		assert_int(int(node["enemy_roster"].get("dreadnought", 0))).is_equal(0)

func test_the_same_offer_is_the_same_coast() -> void:
	var a: Array = Generator.sortie_map(_dock_offer(3, 25))
	var b: Array = Generator.sortie_map(_dock_offer(3, 25))
	assert_int(a.size()).is_equal(b.size())
	for i in range(a.size()):
		assert_int(int(a[i]["terrain_seed"])).is_equal(int(b[i]["terrain_seed"]))
		assert_dict(a[i]["enemy_roster"]).is_equal(b[i]["enemy_roster"])

func test_a_coastal_map_pays_one_more_part_on_its_last_fight() -> void:
	var map: Array = Generator.sortie_map(_dock_offer(2))
	var plain: Array = Generator.short_expedition_map(10, 2, "")
	var last: int = Generator.boss_index(map)
	assert_int(int(map[last]["loot"].get("parts", 0))).is_equal(
		int(plain[last]["loot"].get("parts", 0)) + GameConfig.combat_loot_coastal_parts)

func test_land_maps_are_untouched() -> void:
	var factory := {"id": 2, "kind": Generator.KIND_EXPEDITION, "seed": 11, "era": 3, "blueprint": ""}
	for node in Generator.sortie_map(factory):
		assert_bool(node.has("coastal")).is_false()
		assert_int(_ships_in(node["enemy_roster"])).is_equal(0)
		assert_dict(Generator.node_terrain(node, GameConfig.combat_board_size)).is_empty()
	# El jefe de siempre lleva un tanque, no un barco ni un avion.
	assert_str(Generator.top_tier_unit(3)).is_equal("vehicle")
	assert_str(Generator.top_tier_unit(2)).is_equal("artillery")

func test_the_expedition_hands_its_node_terrain_to_the_board() -> void:
	var run: Expedition = ExpeditionScript.create_sortie(1, _dock_offer(2), {"infantry": 2, "gunboat": 1}, 50.0)
	assert_bool(run.has_water()).is_true()
	assert_bool(Rules.has_water(run.current_terrain(GameConfig.combat_board_size))).is_true()

# ── El Ataque Final ──────────────────────────────────────────────────

func test_the_last_wave_of_an_era_three_siege_brings_airships() -> void:
	for seed_value in [3, 77, 501, 4242]:
		var audit: FinalAudit = AuditScript.create(seed_value, {"vehicle": 6}, 3)
		var last: int = audit.wave_count() - 1
		assert_int(int(audit.wave_at(last)["roster"].get("airship", 0))).is_equal(GameConfig.final_audit_airships_last_wave)
		for i in range(last):
			assert_int(int(audit.wave_at(i)["roster"].get("airship", 0))).is_equal(0)
		for wave in audit.waves:
			var bodies := 0
			for count in wave["roster"].values():
				bodies += int(count)
			assert_int(bodies).is_less_equal(GameConfig.combat_deploy_cap)

func test_no_airships_before_era_three() -> void:
	var audit: FinalAudit = AuditScript.create(4242, {"vehicle": 6}, 2)
	for wave in audit.waves:
		assert_int(int(wave["roster"].get("airship", 0))).is_equal(0)

func test_fighters_escort_the_last_wave_only_if_you_have_planes() -> void:
	var ground: FinalAudit = AuditScript.create(4242, {"vehicle": 6}, 3)
	assert_bool(ground.air_escort).is_false()
	var last: int = ground.wave_count() - 1
	assert_int(int(ground.wave_at(last)["roster"].get("fighter", 0))).is_equal(0)
	var flying: FinalAudit = AuditScript.create(4242, {"vehicle": 4, "fighter": 2}, 3)
	assert_bool(flying.air_escort).is_true()
	assert_int(int(flying.wave_at(flying.wave_count() - 1)["roster"].get("fighter", 0))).is_greater(0)

func test_the_escort_follows_who_is_home_when_the_gate_opens() -> void:
	var audit: FinalAudit = AuditScript.create(4242, {"vehicle": 6}, 3)
	audit.begin({"vehicle": 4, "fighter": 2}, 60.0)
	assert_bool(audit.air_escort).is_true()
	assert_int(int(audit.wave_at(audit.wave_count() - 1)["roster"].get("fighter", 0))).is_greater(0)

func test_the_escort_survives_a_save() -> void:
	var audit: FinalAudit = AuditScript.create(4242, {"vehicle": 4, "fighter": 2}, 3)
	var back: FinalAudit = AuditScript.from_dict(audit.to_dict())
	assert_bool(back.air_escort).is_true()
	var last: int = back.wave_count() - 1
	assert_dict(back.wave_at(last)["roster"]).is_equal(audit.wave_at(last)["roster"])
	# Un guardado viejo (sin la clave) no tiene escolta.
	var old: Dictionary = audit.to_dict()
	old.erase("air_escort")
	assert_bool(AuditScript.from_dict(old).air_escort).is_false()
