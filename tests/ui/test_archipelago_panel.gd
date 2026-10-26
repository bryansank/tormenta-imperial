extends GdUnitTestSuite
## Volverse el Imperio (feat/volverse-imperio, docs/06): el mapa del
## archipielago (ArchipelagoPanel), la pestana IMPERIO de MISIONES, la entrada
## de ☰ MENU y el mapa de una mision de conquista en BattleScreen.
## Escritas sin correr (regla de Bryan: una sola ronda de pruebas al final).

const PanelScript := preload("res://scripts/ui/ArchipelagoPanel.gd")
const FinalAuditScript := preload("res://scripts/combat/FinalAudit.gd")
const BookScript := preload("res://scripts/empire/Archipelago.gd")
const Gen := preload("res://scripts/empire/ConquestGenerator.gd")
const ExpeditionScript := preload("res://scripts/combat/Expedition.gd")
const PauseMenuScript := preload("res://scripts/ui/PauseMenu.gd")

var _saved_empire: Dictionary = {}
var _saved_progression: Dictionary = {}
var _saved_first: bool = false
var _saved_mode := 0

func before_test() -> void:
	_saved_empire = EmpireManager.get_save_data()
	_saved_progression = ProgressionManager.get_save_data()
	_saved_first = TutorialManager.first_sortie_done
	_saved_mode = GameMode.current
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	TutorialManager.first_sortie_done = true
	EmpireManager.reset()
	var audit: FinalAudit = FinalAuditScript.create(7, {"infantry": 3}, 3, 70.0)
	audit.state = FinalAudit.State.WON
	ProgressionManager.final_audit = audit
	# Final con eleccion (v1.2): el archipielago es de quien firmo el libro.
	EmpireManager._ending = EmpireManager.ENDING_SIGN

func after_test() -> void:
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_saved_progression)
	EmpireManager.load_save_data(_saved_empire)
	TutorialManager.first_sortie_done = _saved_first
	GameMode.current = _saved_mode

func _panel() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(PanelScript.new())
	add_child(panel)
	return panel

func test_it_opens_with_the_next_target_selected() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel.open()
	await await_idle_frame()
	assert_bool(panel.is_open()).is_true()
	assert_str(panel.selected_island()).is_equal(EmpireManager.next_target())
	assert_object(panel.find_child("ArchipelagoMap", true, false)).is_not_null()
	assert_object(panel.find_child("IslandName", true, false)).is_not_null()
	panel.close()
	assert_bool(panel.is_open()).is_false()

func test_the_first_time_the_sergeant_explains_then_points_to_a_target() -> void:
	var panel := _panel()
	await await_idle_frame()
	assert_str(panel.quote_text()).is_equal(Tr.t("EMP_QUOTE_INTRO"))
	panel.open()
	await await_idle_frame()
	assert_bool(EmpireManager.intro_seen()).is_true()
	assert_str(panel.quote_text()).is_not_equal(Tr.t("EMP_QUOTE_INTRO"))

func test_a_gated_island_cannot_be_attacked_yet() -> void:
	var gated: String = ""
	for id in BookScript.island_ids():
		if BookScript.needs(id) > 0:
			gated = id
			break
	var panel := _panel()
	await await_idle_frame()
	panel.open()
	panel.select_island(gated)
	await await_idle_frame()
	var attack: Button = panel.find_child("AttackButton", true, false)
	assert_object(attack).is_not_null()
	assert_bool(attack.disabled).is_true()
	assert_object(panel.find_child("IslandLock", true, false)).is_not_null()

func test_a_conquered_island_shows_your_flag_and_no_attack() -> void:
	for m in range(BookScript.total("gulls")):
		EmpireManager.get_book().finish("gulls", m, true, 0.0, 0.0, 100.0)
	var panel := _panel()
	await await_idle_frame()
	panel.open()
	panel.select_island("gulls")
	await await_idle_frame()
	assert_object(panel.find_child("IslandYours", true, false)).is_not_null()
	assert_object(panel.find_child("AttackButton", true, false)).is_null()

func test_the_map_finds_islands_by_position() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel.open()
	await await_idle_frame()
	var map = panel.find_child("ArchipelagoMap", true, false)
	map.size = Vector2(600, 320)
	var def: Dictionary = GameConfig.empire_island("ember")
	assert_str(map.island_at(map.to_px(def["pos"]))).is_equal("ember")
	assert_str(map.island_at(Vector2(-500, -500))).is_equal("")

func test_the_pause_menu_offers_the_archipelago_only_in_the_phase() -> void:
	assert_bool(PauseMenuScript.is_colony_entry_available("archipelago")).is_true()
	ProgressionManager.final_audit = null
	assert_bool(PauseMenuScript.is_colony_entry_available("archipelago")).is_false()

func test_the_missions_panel_has_the_empire_tab() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/SkirmishPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	panel.open()
	await await_idle_frame()
	assert_object(panel._sortie_box.find_child("CampaignTab_empire", true, false)).is_not_null()
	panel.open_conquest("ember")
	assert_str(panel.current_tab()).is_equal(panel.TAB_EMPIRE)
	var offer: Dictionary = panel.current_offer()
	assert_str(String(offer.get("kind", ""))).is_equal(ExpeditionGenerator.KIND_CONQUEST)
	assert_str(String(offer.get("island", ""))).is_equal("ember")
	# La tropa se filtra por el medio de la mision que toca (aire en Brasa).
	assert_str(panel.pure_domain()).is_equal(BookScript.mission_domain("ember", 0))

func test_a_conquest_map_names_the_island_and_paints_its_domain() -> void:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	await await_idle_frame()
	var run: Expedition = ExpeditionScript.create_sortie(1, Gen.offer("gulls", 0, 4242, 3), {"gunboat": 2}, 60.0)
	screen.open_map(run)
	await await_idle_frame()
	assert_str(screen._map_title.text).contains(Tr.t(Gen.island_name_key("gulls")))
	assert_bool(screen._map_sky.visible).is_true()
