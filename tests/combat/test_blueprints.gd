extends GdUnitTestSuite
## Planos ganados en las campanas (1.2, feat/nucleo-y-planos): la tabla
## blueprint_sources (que mision da que plano), el candado de
## PlacementRules.check_blueprint(), su frase, el mecanismo generico
## (CombatManager.grant_blueprints, guardado en el tablon) y que ganar una mision
## (o cargar una partida que ya la gano) da su plano. Compila y pasa aunque los
## .tres de los edificios con plano aun no existan (los traen otras ramas).
## Sin escena; el estado de CombatManager se deja como estaba.
##
## Escrito sin ejecutar (regla de Bryan: un solo pase de pruebas al final).

const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")

var _sorties: Dictionary = {}
var _campaigns: Dictionary = {}
var _mode := 0
var _core := 1

func before_test() -> void:
	_sorties = CombatManager.get_sorties_save_data()
	_campaigns = CombatManager.get_campaigns_save_data()
	_mode = GameMode.current
	_core = ProgressionManager.core_level
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	CombatManager.load_sorties_save_data({})
	CombatManager.load_campaigns_save_data({})

func after_test() -> void:
	CombatManager.load_sorties_save_data(_sorties)
	CombatManager.load_campaigns_save_data(_campaigns)
	GameMode.current = _mode
	ProgressionManager.core_level = _core

# ── La tabla ─────────────────────────────────────────────────────────

func test_the_contract_lists_the_five_advanced_buildings() -> void:
	assert_array(GameConfig.blueprint_required).contains_exactly_in_any_order(
		["infirmary", "smithy", "diesel_plant", "scrapyard", "exchange"])

func test_every_blueprint_comes_from_a_real_mission_of_its_era() -> void:
	for id in GameConfig.blueprint_required:
		var src: Dictionary = GameConfig.blueprint_source(String(id))
		assert_dict(src).override_failure_message(String(id)).is_not_empty()
		var domain: String = String(src["domain"])
		assert_array(GameConfig.CAMPAIGN_DOMAINS).contains([domain])
		var mission: int = int(src["mission"])
		assert_int(mission).override_failure_message(String(id)).is_between(1, GameConfig.campaign_mission_count(domain))
		# Ninguno antes de la era 2: son edificios avanzados.
		assert_int(Generator.campaign_mission_era(domain, mission - 1)).override_failure_message(String(id)) \
			.is_greater_equal(2)

func test_each_mission_gives_its_blueprint() -> void:
	assert_array(GameConfig.blueprints_for_mission("land", 2)).is_equal(["infirmary"])
	assert_array(GameConfig.blueprints_for_mission("land", 4)).is_equal(["smithy"])
	assert_array(GameConfig.blueprints_for_mission("sea", 1)).is_equal(["scrapyard"])
	assert_array(GameConfig.blueprints_for_mission("sea", 2)).is_equal(["exchange"])
	assert_array(GameConfig.blueprints_for_mission("air", 1)).is_equal(["diesel_plant"])
	assert_array(GameConfig.blueprints_for_mission("land", 0)).is_empty()

# ── El candado ───────────────────────────────────────────────────────

func test_without_the_blueprint_it_is_locked_and_says_where_to_win_it() -> void:
	assert_bool(Rules.check_blueprint("infirmary")).is_false()
	assert_str(Rules.lock_kind("infirmary")).is_equal("blueprint")
	assert_str(Rules.blueprint_lock_text("infirmary")).is_equal(
		Tr.t("LBL_BLUEPRINT_NEEDED") % [Tr.t("CAMP_NAME_LAND"), 3])

func test_a_granted_blueprint_opens_it_and_is_saved() -> void:
	CombatManager.grant_blueprints(["infirmary"])
	assert_bool(Rules.check_blueprint("infirmary")).is_true()
	assert_str(Rules.lock_kind("infirmary")).is_equal("")
	var data: Dictionary = CombatManager.get_sorties_save_data()
	assert_array(data.get("blueprints", [])).contains(["infirmary"])
	# Dos veces el mismo plano: uno.
	CombatManager.grant_blueprints(["infirmary"])
	assert_int(CombatManager.get_blueprints().count("infirmary")).is_equal(1)

func test_buildings_without_blueprint_are_never_locked_by_it() -> void:
	for id in ["sawmill", "house", "barracks", "edificio_de_2031"]:
		assert_bool(Rules.check_blueprint(id)).override_failure_message(id).is_true()

func test_sandbox_needs_no_blueprints() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	assert_bool(Rules.check_blueprint("diesel_plant")).is_true()

# ── Las campanas los dan ─────────────────────────────────────────────

func test_loading_a_won_mission_gives_its_blueprint_silently() -> void:
	# Una partida de la 1.1 que ya gano la mision 3 de Tierra recibe la Enfermeria.
	var book: Dictionary = CombatManager.get_campaigns_save_data()
	book["progress"] = {"land": 3, "sea": 0, "air": 0}
	CombatManager.load_campaigns_save_data(book)
	assert_bool(CombatManager.has_blueprint("infirmary")).is_true()
	assert_bool(CombatManager.has_blueprint("smithy")).is_false()
	# Idempotente: cargar otra vez no duplica nada.
	CombatManager.load_campaigns_save_data(book)
	assert_int(CombatManager.get_blueprints().count("infirmary")).is_equal(1)

func test_the_offer_carries_the_blueprint_only_if_the_building_exists() -> void:
	var expected := "infirmary" if ResourceLoader.exists("res://data/buildings/infirmary.tres") else ""
	assert_str(CombatManager.campaign_mission_blueprint("land", 2)).is_equal(expected)
	CombatManager.grant_blueprints(["infirmary"])
	assert_str(CombatManager.campaign_mission_blueprint("land", 2)).is_equal("")

func test_any_mission_can_carry_a_blueprint_in_its_loot() -> void:
	# Antes solo el jefe llevaba plano; ahora la mision que diga la tabla.
	var loot: Dictionary = Generator.campaign_loot("land", 2, "infirmary")
	assert_str(String(loot.get("blueprint", ""))).is_equal("infirmary")
	assert_bool(Generator.campaign_loot("land", 2).has("blueprint")).is_false()

func test_the_board_never_offers_a_blueprint_that_a_campaign_gives() -> void:
	# Las expediciones del tablon dan solo planos sin mision propia.
	var next: String = CombatManager._next_blueprint()
	if next != "":
		assert_dict(GameConfig.blueprint_source(next)).is_empty()
