extends GdUnitTestSuite
## Integracion de la 1.2 sin planos ni Nucleo 1-5 (decision de Bryan,
## 2026-10-25): los edificios que pedian plano se abren por era, requisitos y
## rango; el barco del contrabandista no vende planos; nadie ofrece como botin
## el plano de un edificio de la 1.2. Ver GameConfig, bloque "Integracion de la
## 1.2", y docs/03.

const V12_BUILDINGS := ["bastion", "scrapyard", "telegraph", "trade_port", "exchange", "diesel_plant"]

func test_the_old_blueprint_buildings_open_by_rank() -> void:
	assert_int(RankManager.building_rank("scrapyard")).is_equal(4)
	assert_int(RankManager.building_rank("exchange")).is_equal(6)
	assert_int(RankManager.building_rank("diesel_plant")).is_equal(9)
	# El Puerto, el Bastion y el Telegrafo: solo era y requisitos.
	for id in ["trade_port", "bastion", "telegraph"]:
		assert_int(RankManager.building_rank(id)).override_failure_message(id).is_equal(0)

func test_their_era_requisites_stay() -> void:
	assert_array(GameConfig.building_prerequisites["scrapyard"]).contains(["foundry"])
	assert_array(GameConfig.building_prerequisites["exchange"]).contains(["market", "foundry"])
	assert_array(GameConfig.building_prerequisites["trade_port"]).contains(["market", "foundry"])
	assert_array(GameConfig.building_prerequisites["diesel_plant"]).contains(["refinery"])

func test_no_v12_building_is_a_mission_blueprint() -> void:
	for id in V12_BUILDINGS:
		assert_bool(id in GameConfig.combat_blueprint_buildings).override_failure_message(id).is_false()

func test_the_smuggler_sells_no_blueprints() -> void:
	assert_float(GameConfig.smuggler_plan_chance).is_equal(0.0)

func test_every_v12_building_has_a_cap_row() -> void:
	for id in V12_BUILDINGS:
		assert_bool(GameConfig.building_limits.has(id)).override_failure_message(id).is_true()

func test_the_neighbourhood_beauty_and_the_core_levels_are_not_here() -> void:
	assert_bool("beauty_levels" in GameConfig).is_false()
	assert_bool("core_level_unlocks" in GameConfig).is_false()
