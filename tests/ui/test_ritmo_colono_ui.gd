extends GdUnitTestSuite
## La interfaz de feat/ritmo-colono: la tarjeta de cierre de capitulo, el
## capitulo en ¿QUE HACER?, el boton ¡PELEAR! de la Visita y el parte automatico.

const ChapterScreenScript := preload("res://scripts/ui/ChapterScreen.gd")
const Chapters := preload("res://scripts/services/Chapters.gd")

var _storm_saved: Dictionary = {}
var _progression_saved: Dictionary = {}
var _campaigns_saved: Dictionary = {}
var _army_saved: Dictionary = {}
## El rango: estas pruebas ganan peleas y piezas (XP); sin devolverlo, otra suite
## veria subir de rango y sus consejos.
var _rank_saved: Dictionary = {}

func before_test() -> void:
	_storm_saved = StormManager.get_save_data()
	_progression_saved = ProgressionManager.get_save_data()
	_campaigns_saved = CombatManager.get_campaigns_save_data()
	_army_saved = ArmyManager.get_save_data()
	_rank_saved = RankManager.get_save_data()
	StormManager.reset()
	CombatManager.reset()
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.tier)

func after_test() -> void:
	CombatManager.reset()
	ProgressionManager.load_save_data(_progression_saved)
	CombatManager.load_campaigns_save_data(_campaigns_saved)
	StormManager.load_save_data(_storm_saved)
	ArmyManager.load_save_data(_army_saved)
	RankManager.load_save_data(_rank_saved)

func test_the_chapter_card_shows_once_the_chapter_closes() -> void:
	var screen: CanvasLayer = auto_free(ChapterScreenScript.new())
	add_child(screen)
	await await_idle_frame()
	assert_bool(screen.is_showing()).is_false()
	EventBus.chapter_completed.emit(1)
	assert_bool(screen.try_show_next()).is_true()
	assert_bool(screen.is_showing()).is_true()
	assert_int(screen.current_chapter()).is_equal(1)
	assert_str(screen.title_text()).is_equal(Chapters.title(1))
	screen.close_current()
	assert_bool(screen.is_showing()).is_false()

func test_the_last_chapter_is_closed_by_the_victory_screen() -> void:
	var screen: CanvasLayer = auto_free(ChapterScreenScript.new())
	add_child(screen)
	await await_idle_frame()
	EventBus.chapter_completed.emit(Chapters.COUNT)
	assert_int(screen.pending_count()).is_equal(0)
	assert_bool(screen.try_show_next()).is_false()

## Integracion v1.3: la victoria (y su EL LIBRO) no deja una tarjeta de
## capitulo pendiente ni a la vista detras.
func test_the_victory_clears_a_pending_or_shown_chapter_card() -> void:
	var screen: CanvasLayer = auto_free(ChapterScreenScript.new())
	add_child(screen)
	await await_idle_frame()
	EventBus.chapter_completed.emit(1)
	EventBus.chapter_completed.emit(2)
	assert_bool(screen.try_show_next()).is_true()
	screen._on_victory({})
	assert_bool(screen.is_showing()).is_false()
	assert_int(screen.pending_count()).is_equal(0)

func test_the_chapter_card_waits_for_an_open_board() -> void:
	ArmyManager.load_save_data({"units": {"infantry": 2}, "training": [], "upkeep_accum": 0.0})
	var screen: CanvasLayer = auto_free(ChapterScreenScript.new())
	add_child(screen)
	await await_idle_frame()
	CombatManager.start_skirmish({"infantry": 1})
	EventBus.chapter_completed.emit(2)
	if CombatManager.is_board_open():
		assert_bool(screen.try_show_next()).is_false()
	CombatManager.reset()
	assert_bool(screen.try_show_next()).is_true()

func test_what_to_do_shows_the_chapter_and_its_goals() -> void:
	ProgressionManager.reset()
	CombatManager.load_campaigns_save_data({"seed": 1})
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/ObjectivePanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	panel.refresh()
	var text: String = panel.chapter_text()
	assert_str(text).contains(Chapters.heading(1).to_upper())
	assert_str(text).contains(Tr.t("CHAPTER_GOAL_FOUNDRY"))

func test_the_fight_button_appears_while_the_routine_tax_is_offered() -> void:
	ArmyManager.load_save_data({"units": {"infantry": 4}, "training": [], "upkeep_accum": 0.0})
	var hud: CanvasLayer = auto_free(load("res://scenes/ui/StormHUD.tscn").instantiate())
	add_child(hud)
	await await_idle_frame()
	var btn: Button = hud.fight_button()
	assert_object(btn).is_not_null()
	assert_bool(btn.visible).is_false()
	var cycle: StormCycle = StormManager.get_cycle()
	cycle.storms_survived = 1
	cycle.phase = StormCycle.Phase.TITHE
	StormManager._begin_tithe(1)
	assert_bool(btn.visible).is_true()
	btn.pressed.emit()
	assert_bool(btn.visible).is_false()
	assert_bool(CombatManager.is_board_open()).is_true()

func test_the_routine_report_is_one_card_with_the_tax_and_the_next_visit() -> void:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/WarReportScreen.tscn").instantiate())
	add_child(screen)
	await await_idle_frame()
	StormManager.get_cycle().storms_survived = 2
	EventBus.defense_auto_resolved.emit(true, 6, {"reason": "auto_tithe", "casualties": {"infantry": 1}})
	EventBus.tithe_resolved.emit(true, {})
	await await_idle_frame()
	assert_bool(screen.try_show_next() or screen.is_showing()).is_true()
	assert_int(screen.pending_count()).is_equal(0)
	assert_str(screen.body_text()).contains(Tr.t("LBL_REPORT_NEXT_VISIT") % 2)
	assert_str(screen.stamp_text()).is_not_empty()
