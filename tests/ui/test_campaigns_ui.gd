extends GdUnitTestSuite
## Tres campanas (feat/tres-campanas): el panel de MISIONES con sus pestanas
## Tierra / Mar / Aire / Ataques rapidos, el candado con su razon, y el mapa de
## una mision con el agua o el cielo que toca. Escritas sin correr.

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const ExpeditionScript := preload("res://scripts/combat/Expedition.gd")
const Objectives := preload("res://scripts/services/Objectives.gd")

var _saved_first: bool = false
var _saved_campaigns: Dictionary = {}

func before_test() -> void:
	_saved_first = TutorialManager.first_sortie_done
	_saved_campaigns = CombatManager.get_campaigns_save_data()
	TutorialManager.first_sortie_done = true
	CombatManager.load_campaigns_save_data({})

func after_test() -> void:
	TutorialManager.first_sortie_done = _saved_first
	CombatManager.load_campaigns_save_data(_saved_campaigns)

func _panel() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/SkirmishPanel.tscn").instantiate())
	add_child(panel)
	return panel

func test_the_panel_has_the_three_campaign_tabs_and_the_raids() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel.open()
	await await_idle_frame()
	for tab_name in ["CampaignTab_land", "CampaignTab_sea", "CampaignTab_air", "CampaignTab_raids"]:
		assert_object(panel._sortie_box.find_child(tab_name, true, false)).override_failure_message(
			"falta la pestana %s" % tab_name).is_not_null()

func test_a_campaign_tab_offers_its_next_mission() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel.select_tab("sea")
	var offer: Dictionary = panel.current_offer()
	assert_str(String(offer.get("kind", ""))).is_equal(Generator.KIND_CAMPAIGN)
	assert_str(String(offer.get("domain", ""))).is_equal("sea")
	assert_int(int(offer.get("mission", -1))).is_equal(0)

func test_a_locked_campaign_says_what_to_build() -> void:
	if ArmyManager.building_count("aerodrome") > 0:
		return
	var text: String = Objectives.campaign_lock_text("air")
	assert_str(text).contains(Tr.t("BLD_AERODROME_NAME"))

func test_the_raids_tab_is_not_a_campaign() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel.select_tab(panel.TAB_RAIDS)
	assert_str(panel.current_campaign()).is_empty()

func test_the_mission_map_paints_the_sea_and_names_the_mission() -> void:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	await await_idle_frame()
	var run: Expedition = ExpeditionScript.create_sortie(1,
		Generator.campaign_offer("sea", 0, 4242, 2), {"gunboat": 2}, 60.0)
	screen.open_map(run)
	await await_idle_frame()
	assert_str(screen.map_domain()).is_equal("sea")
	assert_bool(screen._map_sky.visible).is_true()
	assert_str(screen._map_title.text).contains(Tr.t("CAMP_NAME_SEA"))

func test_a_normal_expedition_map_has_no_sky() -> void:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	await await_idle_frame()
	screen.open_map(Expedition.create(1, 4242, {"infantry": 2}, 70.0, 1))
	await await_idle_frame()
	assert_str(screen.map_domain()).is_empty()
	assert_bool(screen._map_sky.visible).is_false()

func test_the_help_index_has_the_three_campaigns_page() -> void:
	var catalog = load("res://scripts/ui/HelpCatalog.gd")
	assert_bool(catalog.ENTRIES.has("guide_campaigns")).is_true()
	assert_bool(catalog.ENTRIES.has("final_gate")).is_true()
	assert_bool(TutorialManager.TIPS.has("campaigns")).is_true()
	assert_bool(TutorialManager.TIPS.has("final_gate")).is_true()
