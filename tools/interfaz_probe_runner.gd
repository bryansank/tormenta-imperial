extends Node
## Sonda de interfaz y dispositivos (docs/21): abre una partida sembrada en la
## vista pedida, con el tamano de ventana y las preferencias de interfaz
## pedidas, y hace capturas del HUD, del menu ☰ con un edificio elegido, de
## Ajustes (pestanas Interfaz y Accesibilidad), del editor de disposicion y del
## tablero de combate. Sirve para VER que nada se pisa ni se sale.
##
## Con ventana (headless no pinta). Argumentos tras `--`:
##   --shot-size=WxH   ventana (1280x720, 1280x800, 1024x768, 2560x1080, 400x720)
##   --view=2d         la vista 2D (por defecto 3D)
##   --profile=tablet  perfil forzado (pc, tablet, phone)
##   --scale=150       escala de interfaz en %
##   --text=large      tamano de texto (small, normal, large, xlarge)
##   --palette=red_green / tritan, --hc (alto contraste), --opacity=0.6
##   --edited          mueve un par de paneles (disposicion editada)
##   --tag=nombre      sufijo de los archivos
##   --dev             dev_mode (boton LIMPIAR en la barra de recursos)
##   --only-hud        solo la captura del HUD
##
## Las capturas van a docs/media/dev/interfaz/ (ignorada por git). Correla
## SIEMPRE con una carpeta de datos aparte (override.cfg temporal con
## application/config/use_custom_user_dir=true y un custom_user_dir_name
## propio). Aun asi aparca el guardado (tests/save/save_parking.gd) y los
## ajustes (tests/save/settings_parking.gd) y los devuelve al terminar.

const SaveParking := preload("res://tests/save/save_parking.gd")
const SettingsParking := preload("res://tests/save/settings_parking.gd")
const BACKUP_PATH := "user://save_game.interfaz_probe.bak"
const OUT_DIR := "res://docs/media/dev/interfaz"

var _tag := ""
var _settings_snap: Dictionary
var _args: PackedStringArray

func _ready() -> void:
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
	_settings_snap = SettingsParking.park()
	# --dev deja dev_mode (y con el el boton LIMPIAR de la barra de recursos).
	GameConfig.dev_mode = _arg("dev") == "true"

	# Preferencias de interfaz pedidas, en memoria.
	var profile := _arg("profile", "auto")
	GameConfig.ui_device_profile = profile
	GameConfig.ui_scale_pct = int(_arg("scale", "0"))
	GameConfig.ui_text_size = _arg("text", "auto")
	GameConfig.ui_palette = _arg("palette", "default")
	GameConfig.ui_high_contrast = _arg("hc") == "true"
	GameConfig.ui_panel_opacity = float(_arg("opacity", "1.0"))
	GameConfig.ui_hud_hidden = []
	GameConfig.ui_layout = {}
	GameConfig.ui_helper_visible = true
	if _arg("edited") == "true":
		GameConfig.ui_layout[DeviceProfile.layout_key()] = {
			"NotificationPanel.objective": [0, 520],
			"ConstructionMenu.button": [-360, 0],
		}
	DeviceProfile.apply_all()
	await _frames(5)

	var size := get_tree().root.get_visible_rect().size
	var win := DisplayServer.window_get_size()
	_tag = "%s_%dx%d%s" % [_arg("view", "3d"), win.x, win.y, ("_" + _arg("tag")) if _arg("tag") != "" else ""]
	print("interfaz_probe: window=", win, " canvas=", size, " factor=", get_tree().root.content_scale_factor,
		" profile=", DeviceProfile.current(), " key=", DeviceProfile.layout_key())

	(load("res://tools/view2d_probe_runner.gd").new() as Node)._write_seeded_save()
	var scene := "res://scenes/main/Main2D.tscn" if _arg("view") == "2d" else "res://scenes/main/Main.tscn"
	get_tree().change_scene_to_file(scene)
	await _frames(60)
	var main := get_tree().current_scene
	_seed_state()
	await _frames(20)
	_close_intro(main)
	await _frames(10)
	await _shot("hud")
	if _arg("only-hud") == "true":
		_finish()
		return

	# Menu ☰ abierto y un edificio elegido (columna derecha llena).
	EventBus.sidebar_toggled.emit(true)
	var tower := GridManager.get_building_at(Vector2i(24, 22))
	if tower:
		EventBus.building_clicked.emit(tower, GridManager.get_building_info(tower)["data"])
	await _frames(15)
	await _shot("menu")
	EventBus.building_deselected.emit()
	EventBus.sidebar_toggled.emit(false)
	await _frames(5)

	var settings: Node = main.get_node_or_null("SettingsPanel")
	if settings:
		settings.call("toggle")
		for tab in [1, 3]:
			settings.call("select_tab", tab)
			await _frames(8)
			await _shot("settings_tab%d" % tab)
		settings.set("_needs_rebuild", false)
		settings.call("toggle")
		await _frames(5)

	UILayoutManager.start_layout_edit()
	await _frames(10)
	await _shot("editor")
	UILayoutManager.stop_layout_edit()
	await _frames(5)

	CombatManager.start_skirmish({"infantry": 3, "artillery": 1})
	await _frames(30)
	await _shot("board")
	_finish()

## Fase avanzada, poblacion y la Tormenta en aviso: todo el HUD a la vista.
func _seed_state() -> void:
	ProgressionManager.current_era = 3
	# Los cuatro recursos a la vista: la barra en su ancho maximo.
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": true})
	for res in ["steel", "oil"]:
		EventBus.resource_unlocked.emit(res)
	ProgressionManager.current_phase = GameConfig.Phase.EXPANSION
	PopulationManager._population = 26
	PopulationManager._max_population = 32
	PopulationManager._morale = 72
	ArmyManager._units = {"infantry": 6, "artillery": 3}
	EventBus.phase_advanced.emit(GameConfig.Phase.EXPANSION)
	EventBus.army_changed.emit()
	EventBus.population_changed.emit(26, 32)
	var storm: Node = get_tree().current_scene.get_node_or_null("StormHUD")
	if storm and storm.get("_panel") != null:
		var panel: Control = storm.get("_panel")
		panel.visible = true
		storm.call("_style_for", StormCycle.Phase.WARNING)
	var notif: Node = get_tree().current_scene.get_node_or_null("NotificationPanel")
	if notif and notif.get("_status_panel") != null:
		(notif.get("_status_panel") as Control).visible = true
	EventBus.notification_posted.emit("Aviso de prueba: la sonda de interfaz", "info", UITheme.INFO)

func _close_intro(main: Node) -> void:
	# El parte de "mientras estuviste fuera" (la partida sembrada tiene hora).
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
	print("interfaz_probe: ", ProjectSettings.globalize_path(path), " ", img.get_size())

func _finish() -> void:
	SettingsParking.restore(_settings_snap)
	SaveParking.restore(BACKUP_PATH)
	get_tree().quit()
