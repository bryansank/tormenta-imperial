extends Node
## Sonda del menu unico, Ajustes y HUD (bugs 1, 3, 9 y 11 del diagnostico de
## jugabilidad). Arranca una partida NUEVA (era 1) en la vista pedida, con el
## perfil de dispositivo y el tamano de ventana pedidos, y captura:
##
##   title            el menu principal
##   title_settings   Ajustes abierto desde el menu principal (por encima de todo)
##   hud_era1         el HUD de una partida recien empezada
##   menu             el menu de la partida (☰ MENU) con un panel de edificio
##                    abierto antes (el boton lo cierra y abre igual)
##   settings_tab0..4 cada pestana de Ajustes, abierto desde el menu
##   hud_era3         el HUD con los cuatro recursos, poblacion y la Tormenta
##
## Argumentos tras `--`: --shot-size=WxH, --view=2d, --profile=pc|tablet|phone,
## --tag=nombre. Capturas en docs/media/dev/menu/ (ignorada por git).
## Aparca guardado y ajustes y los devuelve al terminar.

const SaveParking := preload("res://tests/save/save_parking.gd")
const SettingsParking := preload("res://tests/save/settings_parking.gd")
const BACKUP_PATH := "user://save_game.menu_probe.bak"
const OUT_DIR := "res://docs/media/dev/menu"

var _tag := ""
var _settings_snap: Dictionary
var _args: PackedStringArray

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _arg(key: String, fallback: String = "") -> String:
	for a in _args:
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
		if a == "--" + key:
			return "true"
	return fallback

func _run() -> void:
	_args = OS.get_cmdline_user_args()
	var shot := _arg("shot-size")
	if shot != "":
		var wh := shot.split("x")
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
		await _frames(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	SaveParking.park(BACKUP_PATH)
	if FileAccess.file_exists("user://save_game.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_game.json"))
	_settings_snap = SettingsParking.park()
	GameConfig.dev_mode = false
	GameConfig.ui_device_profile = _arg("profile", "auto")
	GameConfig.ui_scale_pct = 0
	GameConfig.ui_text_size = "auto"
	GameConfig.ui_hud_hidden = []
	GameConfig.ui_layout = {}
	GameConfig.ui_helper_visible = true
	GameConfig.ui_touch_controls = "auto"
	DeviceProfile.apply_all()
	await _frames(5)
	var win := DisplayServer.window_get_size()
	_tag = "%s_%s_%dx%d%s" % [_arg("view", "3d"), DeviceProfile.current(), win.x, win.y,
		("_" + _arg("tag")) if _arg("tag") != "" else ""]
	print("menu_probe: window=", win, " canvas=", get_tree().root.get_visible_rect().size,
		" profile=", DeviceProfile.current())

	GameManager.title_dismissed = false
	var scene := "res://scenes/main/Main2D.tscn" if _arg("view") == "2d" else "res://scenes/main/Main.tscn"
	get_tree().change_scene_to_file(scene)
	await _frames(60)
	var main := get_tree().current_scene
	var title: Node = main.get_node_or_null("TitleMenu")
	var settings: Node = main.get_node_or_null("SettingsPanel")
	var menu: Node = main.get_node_or_null("PauseMenu")
	if title != null and not title.is_open():
		title.open_menu()
	await _frames(10)
	await _shot("title")
	title._on_settings()
	await _frames(10)
	await _shot("title_settings")
	settings.toggle()
	await _frames(5)
	title.close_menu()
	await _frames(30)
	_close_intro(main)
	await _frames(20)
	await _shot("hud_era1")

	# Un panel de edificio abierto, como tras cualquier toque en el mapa: el
	# boton del menu lo cierra y abre igual (bug 3).
	var nucleo: Node = null
	for info in GridManager.get_all_buildings():
		nucleo = info["node"]
		break
	if nucleo != null:
		EventBus.building_clicked.emit(nucleo, GridManager.get_building_info(nucleo)["data"])
		await _frames(10)
	menu.menu_button().pressed.emit()
	await _frames(10)
	await _shot("menu")
	menu.entry("Game_Settings").pressed.emit()
	await _frames(5)
	for tab in 5:
		settings.select_tab(tab)
		await _frames(8)
		await _shot("settings_tab%d" % tab)
	settings.set("_needs_rebuild", false)
	settings.toggle()
	await _frames(5)
	menu.resume()
	await _frames(5)

	_seed_era3()
	await _frames(30)
	await _shot("hud_era3")

	# El boton del menu sobre el tablero de combate: no puede tapar nada.
	ArmyManager._units = {"infantry": 3, "artillery": 1}
	EventBus.army_changed.emit()
	CombatManager.start_skirmish({"infantry": 3, "artillery": 1})
	await _frames(30)
	await _shot("board")
	_finish()

func _seed_era3() -> void:
	ProgressionManager.current_era = 3
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": true})
	for res in ["steel", "oil"]:
		EventBus.resource_unlocked.emit(res)
	ProgressionManager.current_phase = GameConfig.Phase.EXPANSION
	PopulationManager._population = 26
	PopulationManager._max_population = 32
	PopulationManager._morale = 72
	EventBus.phase_advanced.emit(GameConfig.Phase.EXPANSION)
	EventBus.population_changed.emit(26, 32)
	EventBus.morale_changed.emit(72)
	EventBus.workers_changed.emit(14, 26)
	var notif: Node = get_tree().current_scene.get_node_or_null("NotificationPanel")
	if notif and notif.get("_status_panel") != null:
		(notif.get("_status_panel") as Control).visible = true
	# Un hito y una era a la vez: salen en cola, sin pisarse.
	EventBus.milestone_completed.emit("era_3")
	EventBus.era_advanced.emit(3)

func _close_intro(main: Node) -> void:
	var offline: Variant = GameManager.get("_offline_canvas")
	if offline != null and is_instance_valid(offline):
		(offline as Node).queue_free()
		GameManager.set("_offline_canvas", null)
	var tut: Node = main.get_node_or_null("TutorialPanel")
	if tut and tut.has_method("is_intro_open") and tut.call("is_intro_open"):
		tut.call("_close")

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [OUT_DIR, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("menu_probe: ", ProjectSettings.globalize_path(path), " ", img.get_size())

func _finish() -> void:
	SettingsParking.restore(_settings_snap)
	SaveParking.restore(BACKUP_PATH)
	get_tree().quit()
