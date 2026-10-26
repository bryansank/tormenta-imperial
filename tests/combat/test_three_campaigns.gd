extends GdUnitTestSuite
## Las tres campanas (feat/tres-campanas, docs/15 §13): Tierra, Mar y Aire.
## Modelo puro (CampaignBook), generacion de cada mision por dominio, mar abierto,
## la oferta en Expedition y el servicio (candados, dominio puro, guardado).
## Escritas sin correr (regla de Bryan: una sola ronda de pruebas al final).

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const BookScript := preload("res://scripts/combat/CampaignBook.gd")
const ExpeditionScript := preload("res://scripts/combat/Expedition.gd")
const EncounterScript := preload("res://scripts/combat/Encounter.gd")
const UnitScript := preload("res://scripts/combat/CombatUnit.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")

const DOMAINS := ["land", "sea", "air"]

var _saved_campaigns: Dictionary = {}
var _saved_era := 1

func before_test() -> void:
	_saved_campaigns = CombatManager.get_campaigns_save_data()
	_saved_era = ProgressionManager.current_era

func after_test() -> void:
	CombatManager.load_campaigns_save_data(_saved_campaigns)
	ProgressionManager.current_era = _saved_era

func _book() -> CampaignBook:
	var book: CampaignBook = BookScript.new()
	book.ensure_seed(4242)
	return book

func _offer(domain: String, mission: int, era: int = 3) -> Dictionary:
	return Generator.campaign_offer(domain, mission, 4242, era)

# ── El libro (CampaignBook) ──────────────────────────────────────────

func test_each_campaign_has_its_missions_and_a_boss_at_the_end() -> void:
	for domain in DOMAINS:
		var total: int = BookScript.base_total(domain)
		assert_int(total).override_failure_message("%s sin misiones" % domain).is_greater_equal(4)
		assert_bool(Generator.campaign_is_boss_mission(domain, total - 1)).is_true()
		assert_bool(Generator.campaign_is_boss_mission(domain, 0)).is_false()
		assert_int((GameConfig.campaign_defs[domain]["fights"] as Array).size()).is_equal(total)

## feat/ritmo-colono: Colono juega Tierra 4, Mar 2 y Aire 2 (el jefe siempre);
## Gobernador, la tabla entera.
func test_colonist_plays_fewer_missions_and_always_the_boss() -> void:
	var saved_tier: int = GameMode.tier
	GameMode.tier = GameMode.Tier.COLONIST
	assert_array(GameConfig.campaign_mission_list("land")).is_equal([0, 2, 4, 5])
	assert_array(GameConfig.campaign_mission_list("sea")).is_equal([0, 4])
	assert_array(GameConfig.campaign_mission_list("air")).is_equal([0, 4])
	assert_int(BookScript.total("land")).is_equal(4)
	assert_int(BookScript.number_of("land", 4)).is_equal(3)
	assert_int(BookScript.number_of("land", 1)).is_equal(-1)
	GameMode.tier = GameMode.Tier.GOVERNOR
	for domain in DOMAINS:
		assert_int(BookScript.total(domain)).is_equal(BookScript.base_total(domain))
	GameMode.tier = saved_tier

func test_colonist_skips_the_missions_it_does_not_play() -> void:
	var saved_tier: int = GameMode.tier
	GameMode.tier = GameMode.Tier.COLONIST
	var book := _book()
	book.finish("land", 0, true, 0.0, 0.0)
	assert_int(book.next_mission("land")).is_equal(2)
	assert_int(book.won("land")).is_equal(1)
	# La 1 de la tabla no cuenta en Colono: no es la que toca.
	book.finish("land", 1, true, 0.0, 0.0)
	assert_int(book.won("land")).is_equal(1)
	GameMode.tier = saved_tier

## Una sola llave: la pieza del CG nivel 3 es haber ganado al jefe.
func test_the_boss_hands_over_the_piece() -> void:
	var book := _book()
	assert_array(book.missing_pieces()).is_equal(["land", "sea", "air"])
	var seen: Array = []
	for m in GameConfig.campaign_mission_list("sea"):
		for e in book.finish("sea", int(m), true, 0.0, 0.0):
			seen.append(String(e["e"]))
	assert_bool(book.has_piece("sea")).is_true()
	assert_int(seen.count("campaign_piece_won")).is_equal(1)
	assert_array(book.missing_pieces()).is_equal(["land", "air"])
	assert_int(book.pieces_count()).is_equal(1)

## Un guardado de antes de los niveles (progreso contado en la tabla entera): la
## pieza sale de si gano al jefe; sin el jefe, la campana sigue en Colono por la
## siguiente mision que juega.
func test_an_old_save_derives_its_pieces_from_the_bosses_it_beat() -> void:
	var saved_tier: int = GameMode.tier
	GameMode.tier = GameMode.Tier.COLONIST
	var book: CampaignBook = BookScript.from_dict({"seed": 9, "progress": {"land": 6, "sea": 4, "air": 1}})
	assert_bool(book.has_piece("land")).is_true()
	assert_bool(book.has_piece("sea")).is_false()
	assert_int(book.next_mission("sea")).is_equal(4)
	assert_int(book.won("sea")).is_equal(1)
	assert_int(book.next_mission("air")).is_equal(4)
	GameMode.tier = saved_tier

func test_a_new_book_has_nothing_won() -> void:
	var book := _book()
	for domain in DOMAINS:
		assert_int(book.won(domain)).is_equal(0)
		assert_int(book.next_mission(domain)).is_equal(0)
		assert_bool(book.is_complete(domain)).is_false()
	assert_bool(book.all_complete()).is_false()

func test_only_a_won_mission_moves_the_campaign() -> void:
	var book := _book()
	var events: Array = book.finish("sea", 0, false, 10.0, 100.0)
	assert_int(book.won("sea")).is_equal(0)
	assert_int(int(book.setbacks["sea"])).is_equal(1)
	events = book.finish("sea", 0, true, 10.0, 100.0)
	assert_int(book.won("sea")).is_equal(1)
	assert_str(String(events[0]["e"])).is_equal("campaign_mission_won")
	# Rest: the next one waits.
	assert_float(book.cooldown_left("sea", 50.0)).is_equal(60.0)
	assert_float(book.cooldown_left("sea", 200.0)).is_equal(0.0)

func test_a_mission_that_is_not_the_next_one_does_not_count() -> void:
	var book := _book()
	book.finish("land", 3, true, 0.0, 0.0)
	assert_int(book.won("land")).is_equal(0)

func test_beating_the_three_bosses_completes_everything() -> void:
	var book := _book()
	var seen: Array = []
	for domain in DOMAINS:
		for m in GameConfig.campaign_mission_list(domain):
			for e in book.finish(domain, int(m), true, 0.0, 0.0):
				seen.append(String(e["e"]))
		assert_bool(book.is_complete(domain)).is_true()
		assert_int(book.next_mission(domain)).is_equal(-1)
	assert_bool(book.all_complete()).is_true()
	assert_int(seen.count("campaign_completed")).is_equal(3)
	assert_int(seen.count("campaigns_all_completed")).is_equal(1)

func test_the_book_round_trips_and_loading_twice_does_not_add() -> void:
	var book := _book()
	var played: Array = GameConfig.campaign_mission_list("land")
	book.finish("land", int(played[0]), true, 5.0, 30.0)
	book.finish("land", int(played[1]), true, 6.0, 30.0)
	var data: Dictionary = JSON.parse_string(JSON.stringify(book.to_dict()))
	var once: CampaignBook = BookScript.from_dict(data)
	var twice: CampaignBook = BookScript.from_dict(data)
	assert_int(once.won("land")).is_equal(2)
	assert_int(twice.won("land")).is_equal(2)
	assert_int(once.seed_value).is_equal(book.seed_value)
	assert_float(once.cooldown_left("land", 0.0)).is_equal(36.0)

func test_an_old_save_without_campaigns_has_none_started_and_a_wild_number_is_clamped() -> void:
	var empty: CampaignBook = BookScript.from_dict({})
	assert_int(empty.won("air")).is_equal(0)
	var wild: CampaignBook = BookScript.from_dict({"progress": {"air": 99}})
	assert_int(wild.won("air")).is_equal(BookScript.total("air"))

func test_the_seed_is_set_once_and_never_moves() -> void:
	var book: CampaignBook = BookScript.new()
	book.ensure_seed(77)
	book.ensure_seed(99)
	assert_int(book.seed_value).is_equal(77)

# ── Las misiones: dominio puro ───────────────────────────────────────

func test_every_mission_only_fields_enemies_of_its_own_domain() -> void:
	for domain in DOMAINS:
		for m in range(BookScript.base_total(domain)):
			for era in [Generator.campaign_mission_era(domain, m), 3]:
				var map: Array = Generator.campaign_mission_map(_offer(domain, m, era))
				assert_array(map).is_not_empty()
				for node in map:
					for unit_id in node["enemy_roster"]:
						assert_str(GameConfig.get_unit_domain(String(unit_id))).override_failure_message(
							"%s m%d era %d trae %s" % [domain, m, era, unit_id]).is_equal(domain)
					assert_int(Generator.roster_size(node["enemy_roster"])).is_between(1, GameConfig.combat_deploy_cap)

func test_the_same_offer_is_the_same_mission() -> void:
	var a: Array = Generator.campaign_mission_map(_offer("sea", 2))
	var b: Array = Generator.campaign_mission_map(_offer("sea", 2))
	assert_int(a.size()).is_equal(b.size())
	for i in range(a.size()):
		assert_dict(a[i]["enemy_roster"]).is_equal(b[i]["enemy_roster"])
		assert_array(a[i]["exits"]).is_equal(b[i]["exits"])

func test_the_number_of_fights_follows_the_config() -> void:
	for domain in DOMAINS:
		for m in range(BookScript.base_total(domain)):
			var map: Array = Generator.campaign_mission_map(_offer(domain, m))
			assert_int(Generator.fights_on_path(map)).is_equal(Generator.campaign_mission_fights(domain, m))
			if map.size() > 1:
				assert_bool(Generator.every_node_reaches_boss(map)).is_true()

func test_only_the_last_fight_pays() -> void:
	var map: Array = Generator.campaign_mission_map(_offer("land", 3))
	var last: int = map.size() - 1
	for node in map:
		if int(node["index"]) == last:
			assert_dict(node["rewards"]).is_not_empty()
			assert_int(int((node["loot"] as Dictionary).get("parts", 0))).is_greater(0)
		else:
			assert_dict(node["rewards"]).is_empty()
			assert_dict(node["loot"]).is_empty()

func test_the_campaign_boss_is_stronger_than_the_mission_before() -> void:
	for domain in DOMAINS:
		var total: int = BookScript.base_total(domain)
		var boss_map: Array = Generator.campaign_mission_map(_offer(domain, total - 1))
		var prev_map: Array = Generator.campaign_mission_map(_offer(domain, total - 2))
		var boss_node: Dictionary = boss_map[boss_map.size() - 1]
		assert_bool(bool(boss_node.get("campaign_boss", false))).is_true()
		assert_float(Generator.hardest_node_power(boss_map, 3)).override_failure_message(
			"el jefe de %s no es el mas duro" % domain).is_greater(Generator.hardest_node_power(prev_map, 3))

func test_sea_and_air_rewards_bring_their_resource() -> void:
	assert_int(int(Generator.campaign_rewards("sea", 1, 2).get("steel", 0))).is_greater(0)
	assert_int(int(Generator.campaign_rewards("air", 1, 3).get("oil", 0))).is_greater(0)
	assert_int(int(Generator.campaign_rewards("land", 1, 2).get("steel", 0))).is_equal(0)

func test_the_bomber_stays_home_from_the_air_campaign() -> void:
	assert_bool(GameConfig.campaign_unit_allowed("air", "bomber")).is_false()
	assert_bool(GameConfig.campaign_unit_allowed("air", "fighter")).is_true()
	assert_bool(GameConfig.campaign_unit_allowed("air", "airship")).is_true()
	assert_bool(GameConfig.campaign_unit_allowed("sea", "gunboat")).is_true()
	assert_bool(GameConfig.campaign_unit_allowed("sea", "infantry")).is_false()
	assert_bool(GameConfig.campaign_unit_allowed("land", "fighter")).is_false()

# ── El tablero de cada medio ─────────────────────────────────────────

func test_the_open_sea_is_water_with_rocks_only_in_the_middle_rows() -> void:
	var board: Vector2i = GameConfig.combat_board_size
	var terrain: Dictionary = Rules.open_sea_terrain(board, 1234, 3)
	assert_int(terrain.size()).is_equal(board.x * board.y)
	var rocks := 0
	for cell in terrain:
		if String(terrain[cell]) == Rules.TERRAIN_LAND:
			rocks += 1
			assert_int((cell as Vector2i).y).is_between(2, board.y - 3)
	assert_int(rocks).is_between(1, 3)
	assert_dict(Rules.open_sea_terrain(board, 1234, 3)).is_equal(terrain)

func test_a_sea_mission_board_is_water_and_ships_all_deploy() -> void:
	var map: Array = Generator.campaign_mission_map(_offer("sea", 0, 2))
	var terrain: Dictionary = Generator.node_terrain(map[0], GameConfig.combat_board_size)
	assert_bool(Rules.has_water(terrain)).is_true()
	assert_bool(Generator.map_has_water(map)).is_true()
	var units: Array = [UnitScript.create(1, "gunboat", 0), UnitScript.create(2, "torpedo_boat", 0)]
	var uid := 10
	for unit_id in map[0]["enemy_roster"]:
		for i in range(int(map[0]["enemy_roster"][unit_id])):
			units.append(UnitScript.create(uid, String(unit_id), 1))
			uid += 1
	var encounter: Encounter = EncounterScript.create(units, 0, false, false, [], true, terrain)
	encounter.start()
	assert_array(encounter.reserve).override_failure_message("barcos sin sitio en mar abierto").is_empty()

func test_an_air_mission_flies_over_a_coast() -> void:
	var map: Array = Generator.campaign_mission_map(_offer("air", 0))
	assert_str(String(map[0].get("terrain_kind", ""))).is_equal(Generator.TERRAIN_KIND_AIR)
	assert_dict(Generator.node_terrain(map[0], GameConfig.combat_board_size)).is_not_empty()

func test_a_land_mission_is_all_land() -> void:
	var map: Array = Generator.campaign_mission_map(_offer("land", 0, 1))
	assert_dict(Generator.node_terrain(map[0], GameConfig.combat_board_size)).is_empty()

# ── Mixtas apagadas ──────────────────────────────────────────────────

func test_mixed_coast_missions_are_off_by_default() -> void:
	var saved: bool = GameConfig.combat_mixed_missions_enabled
	GameConfig.combat_mixed_missions_enabled = false
	var dock := {"id": 1, "kind": Generator.KIND_EXPEDITION, "seed": 10, "era": 3, "blueprint": ""}
	assert_bool(Generator.offer_is_coastal(dock)).is_false()
	GameConfig.combat_mixed_missions_enabled = true
	assert_bool(Generator.offer_is_coastal(dock)).is_true()
	GameConfig.combat_mixed_missions_enabled = saved

# ── La expedicion de una mision ──────────────────────────────────────

func test_a_campaign_expedition_rebuilds_from_its_offer() -> void:
	var offer := _offer("sea", 1, 2)
	var run: Expedition = ExpeditionScript.create_sortie(3, offer, {"gunboat": 2}, 60.0)
	assert_bool(run.is_campaign()).is_true()
	assert_str(run.campaign_domain()).is_equal("sea")
	assert_int(run.campaign_mission()).is_equal(1)
	assert_float(run.heal_between_pct()).is_equal(GameConfig.campaign_heal_between)
	var loaded: Expedition = ExpeditionScript.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())))
	assert_bool(loaded.is_campaign()).is_true()
	assert_int(loaded.map.size()).is_equal(run.map.size())
	assert_dict(loaded.map[0]["enemy_roster"]).is_equal(run.map[0]["enemy_roster"])
	assert_bool(Rules.has_water(loaded.current_terrain(GameConfig.combat_board_size))).is_true()

# ── El servicio ──────────────────────────────────────────────────────

func test_only_units_of_the_campaign_domain_may_launch() -> void:
	var sea := _offer("sea", 0, 2)
	assert_str(CombatManager.campaign_unit_block("infantry", "sea")).is_equal("CAMP_UNIT_WRONG_DOMAIN")
	assert_str(CombatManager.campaign_unit_block("bomber", "air")).is_equal("CAMP_UNIT_CANT_HIT")
	assert_str(CombatManager.campaign_unit_block("gunboat", "sea")).is_empty()
	# can_launch_to dice el motivo del dominio solo si lo demas vale; aqui basta
	# que nunca diga "ok" con un infante en la de mar.
	assert_bool(bool(CombatManager.can_launch_to({"infantry": 1}, sea).get("ok", false))).is_false()

func test_a_campaign_without_its_building_is_locked() -> void:
	# Sin escena con edificios: ningun Astillero en pie.
	if ArmyManager.building_count("shipyard") == 0:
		assert_str(CombatManager.campaign_lock_reason("sea")).is_equal("CAMP_LOCK_BUILDING")

func test_reset_starts_with_no_campaign_and_a_seed() -> void:
	# El progreso del guardado cuenta misiones de la tabla: 3 son las 0, 1 y 2,
	# de las que este nivel juega las que diga su lista.
	CombatManager.load_campaigns_save_data({"progress": {"land": 3}})
	var played := 0
	for m in GameConfig.campaign_mission_list("land"):
		if int(m) < 3:
			played += 1
	assert_int(CombatManager.campaign_won("land")).is_equal(played)
	CombatManager.load_campaigns_save_data({})
	assert_int(CombatManager.campaign_won("land")).is_equal(0)
	assert_int(CombatManager.get_campaign_book().seed_value).is_not_equal(0)

func test_the_save_keeps_the_campaigns() -> void:
	CombatManager.load_campaigns_save_data({"seed": 55, "progress": {"land": 3, "sea": 1}})
	var land_won: int = CombatManager.campaign_won("land")
	var sea_won: int = CombatManager.campaign_won("sea")
	var data: Dictionary = CombatManager.get_campaigns_save_data()
	CombatManager.load_campaigns_save_data({})
	CombatManager.load_campaigns_save_data(data)
	assert_int(CombatManager.campaign_won("land")).is_equal(land_won)
	assert_int(CombatManager.campaign_won("sea")).is_equal(sea_won)
	assert_int(int(data["progress"]["land"])).is_equal(3)
	assert_int(CombatManager.get_campaign_book().seed_value).is_equal(55)

func test_the_campaign_key_is_written_and_read_by_the_game_manager() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/services/GameManager.gd")
	assert_bool(src.contains("data[\"campaigns\"] = CombatManager.get_campaigns_save_data()")).is_true()
	assert_bool(src.contains("CombatManager.load_campaigns_save_data(")).is_true()

func test_the_texts_exist_in_both_languages() -> void:
	var keys: Array = ["CAMP_NAME_LAND", "CAMP_NAME_SEA", "CAMP_NAME_AIR", "AUDIT_GATE_LINE",
		"AUDIT_NEEDS_HQ3", "HELP_T_CAMPAIGNS", "HELP_B_CAMPAIGNS", "HELP_T_FINAL_GATE", "HELP_B_FINAL_GATE",
		"OBJ_DO_CAMPAIGN", "OBJ_ROUTE_CAMPAIGNS", "CAMP_LOCK_BUILDING", "CAMP_LOCK_REST", "CAMP_LOCK_ERA"]
	for domain in DOMAINS:
		for m in range(BookScript.base_total(domain)):
			keys.append(Generator.campaign_mission_name_key(domain, m))
		keys.append("PIECE_" + domain.to_upper())
		keys.append("PIECE_SHORT_" + domain.to_upper())
		keys.append("CAMP_BLURB_" + domain.to_upper())
		keys.append("CAMP_WHERE_" + domain.to_upper())
		keys.append("CAMP_NO_UNITS_" + domain.to_upper())
	var saved: String = Tr.get_locale()
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for key in keys:
			assert_str(Tr.t(String(key))).override_failure_message("%s sin %s" % [locale, key]).is_not_equal(String(key))
	Tr.set_locale(saved)

## Ronda final de la 1.1 (docs/15 §13 "Medido"): una escala por mision, el jefe
## con un pesado y su propia escala, y el mapa la aplica.
func test_each_mission_has_its_calibrated_scale() -> void:
	for domain in GameConfig.CAMPAIGN_DOMAINS:
		var row: Array = GameConfig.campaign_enemy_mult[domain]
		assert_int(row.size()).is_equal(GameConfig.campaign_base_count(domain))
		for m in range(row.size()):
			assert_float(ExpeditionGenerator.campaign_mission_mult(domain, m)).is_equal(float(row[m]))
		assert_int(int(GameConfig.campaign_boss_heavies[domain])).is_equal(1)
		assert_bool(GameConfig.campaign_boss_extra_scale.has(domain)).is_true()
	# Una mision de en medio: su escala es la de la curva por su cifra.
	var offer: Dictionary = ExpeditionGenerator.campaign_offer("sea", 1, 4242, 2)
	var map: Array = ExpeditionGenerator.campaign_mission_map(offer)
	var node: Dictionary = map[0]
	var depth: int = 1 * GameConfig.campaign_level_step + int(node["depth"])
	var base: float = ExpeditionGenerator.enemy_scale(depth, 2, int(node["risk"]), bool(node["is_boss"]))
	assert_float(float(node["enemy_scale"])).is_equal_approx(base * float(GameConfig.campaign_enemy_mult["sea"][1]), 0.0001)

## Ronda final de la 1.1: cada derrota en la mision que toca debilita a su
## enemigo (mismo mapa); al ganarla se vuelve a empezar.
func test_each_failure_eases_the_same_mission() -> void:
	var book = BookScript.new()
	book.ensure_seed(4242)
	var first: Dictionary = book.offer_for("air", 3)
	assert_int(int(first.get("retries", -1))).is_equal(0)
	book.finish("air", 0, false, 0.0, 0.0)
	book.finish("air", 0, false, 0.0, 0.0)
	var again: Dictionary = book.offer_for("air", 3)
	assert_int(int(again["retries"])).is_equal(2)
	assert_int(int(again["seed"])).is_equal(int(first["seed"]))
	var easy: Array = Generator.campaign_mission_map(again)
	var hard: Array = Generator.campaign_mission_map(first)
	assert_float(float(easy[0]["enemy_scale"])).is_less(float(hard[0]["enemy_scale"]))
	assert_dict(easy[0]["enemy_roster"]).is_equal(hard[0]["enemy_roster"])
	# Ganarla pone el contador a cero; se guarda y se carga.
	book.finish("air", 0, true, 0.0, 0.0)
	assert_int(int(book.fails["air"])).is_equal(0)
	book.finish("air", book.next_mission("air"), false, 0.0, 0.0)
	var loaded = BookScript.from_dict(book.to_dict())
	assert_int(int(loaded.fails["air"])).is_equal(1)
