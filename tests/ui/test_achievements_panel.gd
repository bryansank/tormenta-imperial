extends GdUnitTestSuite
## LOGROS Y ESTADISTICAS (AchievementsPanel, docs/29): una fila por logro, los
## secretos tapados hasta ganarlos, lo ganado con su sello, las cifras de la
## partida, una columna en telefono y la entrada LOGROS en la tarjeta de la
## colonia.

const PanelScript := preload("res://scripts/ui/AchievementsPanel.gd")
const RankScene := preload("res://scenes/ui/RankPanel.tscn")
const SettingsParking := preload("res://tests/save/settings_parking.gd")
const SaveParking := preload("res://tests/save/save_parking.gd")

var _settings: Dictionary = {}
var _stats_saved: Dictionary = {}
var _mode_saved: Dictionary = {}
var _phone_saved := false

func before(do_skip := SaveParking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

func before_test() -> void:
	_settings = SettingsParking.park()
	_stats_saved = AchievementManager.get_save_data()
	_mode_saved = GameMode.get_save_data()
	_phone_saved = CartoonTheme.phone
	GameConfig.profile_achievements = {}
	AchievementManager.reset()
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.COLONIST)

func after_test() -> void:
	CartoonTheme.phone = _phone_saved
	GameMode.load_save_data(_mode_saved)
	AchievementManager.load_save_data(_stats_saved)
	SettingsParking.restore(_settings)

func _open_panel() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(PanelScript.new())
	add_child(panel)
	panel.open()
	return panel

func test_one_row_per_achievement() -> void:
	var panel := _open_panel()
	for def in GameConfig.achievement_definitions:
		var id := String(def["id"])
		assert_object(panel.find_child("Ach_" + id, true, false)).override_failure_message(id).is_not_null()
	panel.close()
	assert_bool(panel.is_open()).is_false()

func test_secrets_stay_hidden_until_won() -> void:
	var panel := _open_panel()
	var row: Node = panel.find_child("Ach_deserters", true, false)
	var title: Label = row.find_child("Name", true, false)
	assert_str(title.text).is_equal(Tr.t("LBL_ACH_SECRET_NAME"))
	AchievementManager.count("deserters")
	panel.refresh()
	row = panel.find_child("Ach_deserters", true, false)
	title = row.find_child("Name", true, false)
	assert_str(title.text).is_equal(Tr.t("ACH_DESERTERS_NAME"))
	assert_object(row.find_child("Done", true, false)).is_not_null()
	panel.close()

func test_progress_shows_on_counted_achievements() -> void:
	AchievementManager.count("buildings_built", 10)
	var panel := _open_panel()
	var row: Node = panel.find_child("Ach_builder_25", true, false)
	assert_object(row.find_child("Progress", true, false)).is_not_null()
	# El de una sola vez ya ganado lleva su sello, sin barra.
	var first: Node = panel.find_child("Ach_first_stone", true, false)
	assert_object(first.find_child("Done", true, false)).is_not_null()
	assert_object(first.find_child("Progress", true, false)).is_null()
	panel.close()

func test_stats_tab_shows_the_run() -> void:
	AchievementManager.count("trades", 1234)
	var panel := _open_panel()
	panel.show_tab(PanelScript.Tab.STATS)
	var cell: Node = panel.find_child("Stat_trades", true, false)
	assert_object(cell).is_not_null()
	var value: Label = cell.find_child("Value", true, false)
	assert_str(value.text).is_equal(CartoonTheme.thousands(1234))
	assert_object(panel.find_child("Stat_runs_finished", true, false)).is_not_null()
	panel.close()

func test_phone_puts_achievements_in_one_column() -> void:
	CartoonTheme.phone = true
	var panel := _open_panel()
	var grid: GridContainer = panel.find_child("Group_build", true, false)
	assert_int(grid.columns).is_equal(1)
	panel.close()
	CartoonTheme.phone = false
	var pc := _open_panel()
	grid = pc.find_child("Group_build", true, false)
	assert_int(grid.columns).is_equal(2)
	pc.close()

func test_sandbox_says_why_nothing_is_won() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX, GameMode.Tier.COLONIST)
	var panel := _open_panel()
	var footer: Label = panel.find_child("Footer", true, false)
	assert_str(footer.text).is_equal(Tr.t("LBL_ACH_SANDBOX"))
	assert_bool(footer.visible).is_true()
	panel.close()

func test_played_time_format() -> void:
	assert_str(PanelScript.format_played(59)).is_equal("0 min")
	assert_str(PanelScript.format_played(12 * 60)).is_equal("12 min")
	assert_str(PanelScript.format_played(3 * 3600 + 5 * 60)).is_equal("3 h 05 min")

func test_the_colony_card_has_an_achievements_entry() -> void:
	var rank = auto_free(RankScene.instantiate())
	add_child(rank)
	assert_object(rank.hub_button("achievements")).is_not_null()
	assert_bool(rank.hub_entry_available("achievements")).is_true()
