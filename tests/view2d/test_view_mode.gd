extends GdUnitTestSuite
## La preferencia de vista (3D / 2D): se guarda en user://settings.cfg, sobrevive
## a recargar los ajustes, un valor raro no rompe nada, y `--view=2d` en la linea
## de comandos se entiende. Aparta settings.cfg y lo devuelve al terminar.

const ViewMode := preload("res://scripts/view2d/ViewMode.gd")
const ViewRouter := preload("res://scripts/view2d/ViewRouter.gd")

const SETTINGS := "user://settings.cfg"
const BACKUP := "user://settings.view_mode_test.bak"

var _saved_mode := "3d"

func before_test() -> void:
	_saved_mode = GameConfig.ui_view_mode
	# Una copia aparcada que sigue ahi es de una ejecucion que murio a medias:
	# son los ajustes de verdad y vuelven a su sitio antes de aparcar otra vez.
	if FileAccess.file_exists(BACKUP):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(BACKUP), ProjectSettings.globalize_path(SETTINGS))
	if FileAccess.file_exists(SETTINGS):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SETTINGS), ProjectSettings.globalize_path(BACKUP))

func after_test() -> void:
	if FileAccess.file_exists(BACKUP):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(BACKUP), ProjectSettings.globalize_path(SETTINGS))
		DirAccess.remove_absolute(BACKUP)
	elif FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(SETTINGS)
	GameConfig.load_user_settings()
	GameConfig.ui_view_mode = _saved_mode
	ViewMode._session_override = ""
	ViewMode._cmdline_read = true

func test_the_default_view_is_3d() -> void:
	# Hacer la 2D la de serie es cambiar este valor por defecto en GameConfig.
	var fresh: Node = load("res://scripts/services/GameConfig.gd").new()
	assert_str(fresh.ui_view_mode).is_equal("3d")
	fresh.free()

func test_the_view_mode_survives_a_settings_reload() -> void:
	GameConfig.ui_view_mode = "2d"
	GameConfig.save_user_settings()
	GameConfig.ui_view_mode = "3d"
	GameConfig.load_user_settings()
	assert_str(GameConfig.ui_view_mode).is_equal("2d")
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	assert_str(String(cf.get_value("ui", "view_mode", ""))).is_equal("2d")

func test_a_garbage_value_in_the_file_is_ignored() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("ui", "view_mode", "isometric")
	cf.save(SETTINGS)
	GameConfig.ui_view_mode = "3d"
	GameConfig.load_user_settings()
	assert_str(GameConfig.ui_view_mode).is_equal("3d")

func test_saving_other_settings_keeps_the_view_mode() -> void:
	GameConfig.ui_view_mode = "2d"
	GameConfig.save_user_settings()
	GameConfig.ui_grid_visible = not GameConfig.ui_grid_visible
	GameConfig.save_user_settings()
	GameConfig.ui_grid_visible = not GameConfig.ui_grid_visible
	GameConfig.save_user_settings()
	GameConfig.ui_view_mode = "3d"
	GameConfig.load_user_settings()
	assert_str(GameConfig.ui_view_mode).is_equal("2d")

func test_the_command_line_flag_is_understood() -> void:
	assert_str(ViewMode.parse_cmdline(PackedStringArray(["--view=2d"]))).is_equal("2d")
	assert_str(ViewMode.parse_cmdline(PackedStringArray(["--foo", "--view=3D"]))).is_equal("3d")
	assert_str(ViewMode.parse_cmdline(PackedStringArray(["--view=vr"]))).is_equal("")
	assert_str(ViewMode.parse_cmdline(PackedStringArray([]))).is_equal("")

func test_the_scene_for_each_mode() -> void:
	assert_str(ViewMode.scene_for("2d")).is_equal("res://scenes/main/Main2D.tscn")
	assert_str(ViewMode.scene_for("3d")).is_equal("res://scenes/main/Main.tscn")
	assert_str(ViewMode.scene_for("nonsense")).is_equal("res://scenes/main/Main.tscn")
	assert_bool(ResourceLoader.exists(ViewMode.SCENE_2D)).is_true()

func test_choosing_a_view_persists_it_and_beats_the_command_line() -> void:
	ViewMode._cmdline_read = true
	ViewMode._session_override = "2d"
	assert_str(ViewMode.requested()).is_equal("2d")
	ViewMode.set_preference("3d")
	assert_str(ViewMode.requested()).is_equal("3d")
	GameConfig.ui_view_mode = "2d"
	GameConfig.load_user_settings()
	assert_str(GameConfig.ui_view_mode).is_equal("3d")

func test_both_main_scenes_carry_the_router() -> void:
	for pair in [["res://scenes/main/Main.tscn", "3d"], ["res://scenes/main/Main2D.tscn", "2d"]]:
		var state: SceneState = (load(String(pair[0])) as PackedScene).get_state()
		var found_script := false
		var found_mode := String(pair[1]) == "3d"  # 3d es el valor por defecto del export
		for i in range(state.get_node_property_count(0)):
			var prop := state.get_node_property_name(0, i)
			if prop == "script":
				found_script = state.get_node_property_value(0, i) == ViewRouter
			if prop == "view_mode":
				found_mode = state.get_node_property_value(0, i) == String(pair[1])
		assert_bool(found_script).override_failure_message("%s sin ViewRouter" % pair[0]).is_true()
		assert_bool(found_mode).is_true()

func test_the_2d_scene_has_the_same_ui_as_the_3d_scene() -> void:
	var names_3d := _child_names("res://scenes/main/Main.tscn")
	var names_2d := _child_names("res://scenes/main/Main2D.tscn")
	for n in ["ResourceHUD", "ConstructionMenu", "BuildingInfoPanel", "MarketPanel", "ProgressPanel",
			"VictoryScreen", "NotificationPanel", "TechTreePanel", "ObjectivePanel", "ArmyPanel",
			"SettingsPanel", "HelperPanel", "SkirmishPanel", "BattleScreen", "StormHUD", "TutorialPanel",
			"OnScreenControls", "BuildingPlacer", "MapGenerator", "GridOverlay",
			# menus-informes: PauseMenu y TitleMenu buscan a sus hermanos por nombre.
			"AuditWaveBanner", "WarReportScreen", "AuditDefeatScreen", "PauseMenu", "TitleMenu"]:
		assert_bool(n in names_3d).override_failure_message("%s falta en Main" % n).is_true()
		assert_bool(n in names_2d).override_failure_message("%s falta en Main2D" % n).is_true()

func _child_names(path: String) -> Array:
	var state: SceneState = (load(path) as PackedScene).get_state()
	var out: Array = []
	for i in range(1, state.get_node_count()):
		if String(state.get_node_path(i)).count("/") == 1:
			out.append(String(state.get_node_name(i)))
	return out
