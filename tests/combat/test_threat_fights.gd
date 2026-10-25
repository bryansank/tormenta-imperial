extends GdUnitTestSuite
## El combate y el botin de las amenazas de costa (ExpeditionGenerator.threat_*,
## feat/amenazas-costa): un solo combate de DOMINIO PURO, el mismo al rehacerlo
## de la oferta, botin fijo y a la vista; y que la columna solo sale con tropa
## del medio de la amenaza (CombatManager.can_launch_to).
##
## Escrito SIN EJECUTAR (regla de Bryan: un solo pase de pruebas al final).

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const BoardScript := preload("res://scripts/combat/ThreatBoard.gd")
const ExpeditionScript := preload("res://scripts/combat/Expedition.gd")

func _offer(threat_type: String, domain: String = "land", era: int = 2, seed_value: int = 4242) -> Dictionary:
	return {"id": ThreatBoard.OFFER_ID_BASE + 1, "kind": Generator.KIND_THREAT, "threat_id": 1,
		"threat_type": threat_type, "seed": seed_value, "era": era, "domain": domain, "blueprint": ""}

func test_a_threat_is_one_fight() -> void:
	var map: Array = Generator.sortie_map(_offer(Generator.THREAT_RAIDERS))
	assert_int(map.size()).is_equal(1)
	assert_bool(bool(map[0].get("raid", false))).is_true()
	assert_int(Generator.fights_on_path(map)).is_equal(1)

func test_land_threat_brings_only_land_enemies() -> void:
	for seed_value in [1, 7, 99, 1234]:
		var map: Array = Generator.threat_map(_offer(Generator.THREAT_VANGUARD, "land", 3, seed_value))
		for unit_id in map[0]["enemy_roster"]:
			assert_str(GameConfig.get_unit_domain(String(unit_id))).is_equal("land")
		assert_bool(Generator.map_has_water(map)).is_false()

func test_sea_threat_is_ships_on_open_sea() -> void:
	var map: Array = Generator.threat_map(_offer(Generator.THREAT_RAIDERS, "sea", 2))
	for unit_id in map[0]["enemy_roster"]:
		assert_str(GameConfig.get_unit_domain(String(unit_id))).is_equal("sea")
	assert_str(String(map[0].get("terrain_kind", ""))).is_equal(Generator.TERRAIN_KIND_SEA)
	assert_bool(Generator.map_has_water(map)).is_true()

func test_the_wreck_has_no_fight() -> void:
	assert_array(Generator.threat_map(_offer(Generator.THREAT_WRECK))).is_empty()
	assert_bool(Generator.threat_is_fight(Generator.THREAT_WRECK)).is_false()

func test_same_offer_same_fight_and_loot() -> void:
	var a: Array = Generator.threat_map(_offer(Generator.THREAT_RAIDERS))
	var b: Array = Generator.threat_map(_offer(Generator.THREAT_RAIDERS))
	assert_dict(a[0]["enemy_roster"]).is_equal(b[0]["enemy_roster"])
	assert_dict(a[0]["rewards"]).is_equal(b[0]["rewards"])
	assert_dict(a[0]["loot"]).is_equal(b[0]["loot"])
	assert_dict(Generator.threat_loot(_offer(Generator.THREAT_WRECK))).is_equal(Generator.threat_loot(_offer(Generator.THREAT_WRECK)))

func test_loot_is_inside_the_tables() -> void:
	for seed_value in range(1, 40):
		var offer: Dictionary = _offer(Generator.THREAT_VANGUARD, "land", 2, seed_value)
		var loot: Dictionary = Generator.threat_loot(offer)
		var parts_range: Vector2i = GameConfig.threat_parts["vanguard"]
		assert_int(int(loot.get("parts", 0))).is_between(parts_range.x, parts_range.y)
		for key in loot:
			if key == "parts":
				continue
			assert_bool(String(key) in GameConfig.threat_rare_by_era[2]).is_true()
		var rewards: Dictionary = Generator.threat_rewards(offer)
		assert_bool(rewards.has("gold")).is_true()

func test_rewards_grow_with_the_era() -> void:
	var low: Dictionary = Generator.threat_rewards(_offer(Generator.THREAT_RAIDERS, "land", 1, 5))
	var high: Dictionary = Generator.threat_rewards(_offer(Generator.THREAT_RAIDERS, "land", 3, 5))
	assert_int(int(high["gold"])).is_greater(int(low["gold"]))

func test_sea_fight_pays_an_extra_part() -> void:
	var land: Dictionary = Generator.threat_loot(_offer(Generator.THREAT_RAIDERS, "land", 2, 77))
	var sea: Dictionary = Generator.threat_loot(_offer(Generator.THREAT_RAIDERS, "sea", 2, 77))
	assert_int(int(sea.get("parts", 0))).is_equal(int(land.get("parts", 0)) + GameConfig.threat_sea_extra_parts)

func test_the_expedition_rebuilds_the_same_map_from_its_save() -> void:
	var run: Expedition = ExpeditionScript.create_sortie(1, _offer(Generator.THREAT_RAIDERS), {"infantry": 2}, 60.0)
	assert_bool(run.is_threat()).is_true()
	assert_bool(run.is_raid()).is_true()
	var back: Expedition = ExpeditionScript.from_dict(run.to_dict(), 2)
	assert_int(back.map.size()).is_equal(1)
	assert_dict(back.map[0]["enemy_roster"]).is_equal(run.map[0]["enemy_roster"])

func test_names_have_translations() -> void:
	for threat_type in Generator.THREAT_TYPES:
		var key: String = Generator.threat_name_key(String(threat_type))
		assert_str(Tr.t(key)).is_not_equal(key)
	assert_str(Tr.t("THREAT_NAME_RAIDERS_SEA")).is_not_equal("THREAT_NAME_RAIDERS_SEA")

func test_pure_domain_rule() -> void:
	# Dominio puro: a la orilla no salen barcos; al agua, solo barcos. Es la
	# misma regla que usa can_launch_to() con la oferta de amenaza (la prueba de
	# integracion la mira con tropa de verdad: test_threat_manager.gd).
	assert_str(CombatManager.campaign_unit_block("gunboat", "land")).is_not_empty()
	assert_str(CombatManager.campaign_unit_block("infantry", "sea")).is_not_empty()
	assert_str(CombatManager.campaign_unit_block("infantry", "land")).is_empty()
	assert_str(CombatManager.campaign_unit_block("gunboat", "sea")).is_empty()
