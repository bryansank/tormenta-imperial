extends GdUnitTestSuite
## El boton ESCARAMUZAS del HUD y lo que lo rodea (doc 21 §3.6, rama
## feat/escaramuzas): registrado en HudRegistry con su slot, sus textos en los
## dos idiomas, los repuestos como material y su uso en las mejoras de nivel 3.
##
## Escrito SIN EJECUTAR (regla de Bryan: un solo pase de pruebas al final).

const NEW_KEYS := ["HUD_SKIRMISH_BUTTON", "HINT_SKIRMISH_BUTTON", "SORTIE_WHY_OUTPOST",
	"SORTIE_WHY_PARTS", "SORTIE_WHY_NEW", "OBJ_DO_SORTIE", "BTN_AUTO_RESOLVE",
	"LBL_ENEMY_ROUTED", "LOOT_PARTS", "LOOT_COLONISTS", "LOOT_TITHE_CUT", "LOOT_BLUEPRINT",
	"ODDS_FAVORABLE", "ODDS_EVEN", "ODDS_HARD", "UNLOCK_HINT_PARTS"]

func test_the_button_is_a_registered_movable_hud_element() -> void:
	assert_bool(HudRegistry.ELEMENTS.has("SkirmishButton")).is_true()
	assert_array(HudRegistry.ORDER).contains(["SkirmishButton"])
	assert_str(String(UILayoutConfig.PANEL_SLOTS.get("SkirmishButton", ""))).is_equal("skirmish_button")
	assert_bool(UILayoutConfig.SLOTS.has("skirmish_button")).is_true()

func test_every_new_text_exists_in_both_languages() -> void:
	var before: String = Tr._locale
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for key in NEW_KEYS:
			assert_str(Tr.t(key)).override_failure_message("%s falta en %s" % [key, locale]).is_not_equal(key)
		assert_str(Tr.res_name("parts")).is_not_empty()
	Tr.set_locale(before)

func test_spare_parts_are_a_material_outside_the_shared_bag() -> void:
	assert_bool(ResourceManager.is_material(ResourceManager.Type.PARTS)).is_true()
	assert_str(ResourceManager.get_type_name(ResourceManager.Type.PARTS)).is_equal("parts")

func test_level_three_of_a_producer_asks_for_spare_parts() -> void:
	var data: BuildingData = load("res://data/buildings/sawmill.tres")
	var cost3: Dictionary = GameConfig.get_upgrade_cost(data, 3)
	var cost2: Dictionary = GameConfig.get_upgrade_cost(data, 2)
	assert_int(int(cost3.get(ResourceManager.Type.PARTS, 0))).is_equal(int(GameConfig.upgrade_parts_cost[3]))
	assert_bool(cost2.has(ResourceManager.Type.PARTS)).is_false()

func test_the_headquarters_keeps_its_own_table() -> void:
	var data: BuildingData = load("res://data/buildings/headquarters.tres")
	assert_bool(GameConfig.get_upgrade_cost(data, 3).has(ResourceManager.Type.PARTS)).is_false()

func test_both_scenes_carry_the_button() -> void:
	for path in ["res://scenes/main/Main.tscn", "res://scenes/main/Main2D.tscn"]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_bool(text.contains("SkirmishButton")).override_failure_message(path).is_true()
