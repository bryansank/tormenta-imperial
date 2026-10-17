extends Node
## Sonda de revision visual: las pantallas de la partida que las otras sondas no
## sacan, en una colonia temprana y en una grande, para buscar paneles que tapan,
## textos cortados, rotulos 3D gigantes y cosas ilegibles de noche o en Tormenta.
## La lanza tools/revision_probe.gd. Capturas (ignoradas por git) en
## docs/media/dev/revision/<vista>_<perfil>_<WxH>_<toma>.png:
##
##   temprana_hud, temprana_construir, temprana_construir_detalle,
##   temprana_nucleo, temprana_yacimiento, temprana_quehacer
##   grande_hud, grande_lejos, grande_edificio, grande_nucleo, grande_yacimiento,
##   grande_ejercito, grande_ejercito_ficha, grande_escaramuzas,
##   grande_expedicion_tablero, grande_expedicion_mapa,
##   grande_noche, grande_aviso, grande_tormenta, grande_noche_tormenta
##
## El tutorial guiado se esconde (su tarjeta tiene sonda propia). Argumentos tras
## `--`: --shot-size=WxH, --profile=pc|tablet|phone, --tag=nombre. Aparca
## guardado y ajustes y los devuelve al terminar.

const SaveParking := preload("res://tests/save/save_parking.gd")
const SettingsParking := preload("res://tests/save/settings_parking.gd")
const ArteRunner := preload("res://tools/arte_probe_runner.gd")
const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")
const BACKUP_PATH := "user://save_game.revision_probe.bak"
const OUT_DIR := "res://docs/media/dev/revision"

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
	if FileAccess.file_exists(GameManager.save_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameManager.save_path()))
	_settings_snap = SettingsParking.park()
	GameConfig.dev_mode = false
	GameConfig.ui_view_mode = "3d"
	GameConfig.ui_device_profile = _arg("profile", "auto")
	GameConfig.ui_scale_pct = 0
	GameConfig.ui_text_size = "auto"
	GameConfig.ui_hud_hidden = []
	GameConfig.ui_layout = {}
	GameConfig.ui_helper_visible = false
	GameConfig.ui_touch_controls = "auto"
	DeviceProfile.apply_all()
	await _frames(5)
	var win := DisplayServer.window_get_size()
	_tag = "3d_%s_%dx%d%s" % [DeviceProfile.current(), win.x, win.y,
		("_" + _arg("tag")) if _arg("tag") != "" else ""]

	# ── Colonia temprana: partida nueva ──────────────────────────────────
	GameManager.title_dismissed = true
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await _frames(60)
	_quiet()
	await _seconds(3.0)
	_quiet()
	await _shot("temprana_hud")
	var main := get_tree().current_scene
	var build: Node = main.get_node_or_null("ConstructionMenu")
	build._open()
	await _frames(10)
	await _shot("temprana_construir")
	build._select_building(load("res://data/buildings/foundry.tres"))
	await _frames(10)
	await _shot("temprana_construir_detalle")
	build._close()
	await _frames(5)
	await _click_nucleo("temprana_nucleo")
	await _click_deposit("temprana_yacimiento")
	main.get_node("ObjectivePanel").toggle()
	await _frames(10)
	await _shot("temprana_quehacer")
	UIManager.close_all_windows()
	await _frames(5)

	# ── Colonia grande: la de la sonda de arte ──────────────────────────
	var seeder: Node = ArteRunner.new()
	seeder._write_seeded_save()
	seeder.free()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await _frames(60)
	_quiet()
	await _seconds(6.0)
	_quiet()
	main = get_tree().current_scene
	ArmyManager._units = {"infantry": 6, "artillery": 3, "vehicle": 1}
	EventBus.army_changed.emit()
	ResourceManager.set_amounts({"gold": 2400, "wood": 900, "steel": 300, "oil": 120})
	_camera(Vector2(-6.0, -2.0), -1.0)
	await _seconds(1.5)
	await _shot("grande_hud")
	_camera(Vector2(-4.0, 0.0), 0.5)
	await _seconds(1.5)
	await _shot("grande_lejos")
	_camera(Vector2(-6.0, -2.0), -1.0)
	await _seconds(1.0)
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		if data.id == "sawmill":
			EventBus.building_clicked.emit(info["node"], data)
			break
	await _frames(15)
	await _shot("grande_edificio")
	EventBus.building_deselected.emit()
	await _click_nucleo("grande_nucleo")
	await _click_deposit("grande_yacimiento")

	var army: Node = main.get_node_or_null("ArmyPanel")
	army._toggle_panel()
	await _frames(10)
	await _shot("grande_ejercito")
	army.toggle_unit_card("artillery")
	await _frames(10)
	await _shot("grande_ejercito_ficha")
	UIManager.close_all_windows()
	await _frames(5)
	var skirmish: Node = main.get_node_or_null("SkirmishPanel")
	skirmish.open()
	await _frames(15)
	await _shot("grande_escaramuzas")
	UIManager.close_all_windows()
	await _frames(5)
	if CombatManager.launch_expedition({"infantry": 3, "artillery": 1}, 4242):
		await _seconds(3.0)
		await _shot("grande_expedicion_tablero")
		var battle: Node = main.get_node_or_null("BattleScreen")
		if battle and battle.has_method("open_map"):
			battle.open_map()
			await _frames(15)
			await _shot("grande_expedicion_mapa")
		CombatManager.abandon_expedition()
		await _seconds(1.0)
		if battle:
			battle.visible = false
		var reports: Node = main.get_node_or_null("WarReportScreen")
		if reports:
			reports.visible = false

	# ── Noche y Tormenta ────────────────────────────────────────────────
	var hours := _hours()
	DayClock.set_hour(hours["noche"])
	StormSky.refresh_day()
	await _seconds(2.0)
	await _shot("grande_noche")
	DayClock.set_hour(hours["dia"])
	StormSky.refresh_day()
	EventBus.storm_incoming.emit(60.0)
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.WARNING, 60.0)
	await _seconds(4.0)
	await _shot("grande_aviso")
	EventBus.storm_ash_started.emit()
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.ASH, 30.0)
	EventBus.storm_started.emit(3)
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.STORM, 30.0)
	await _seconds(4.0)
	await _shot("grande_tormenta")
	DayClock.set_hour(hours["noche"])
	StormSky.refresh_day()
	await _seconds(2.0)
	await _shot("grande_noche_tormenta")
	_finish()

func _click_nucleo(shot_name: String) -> void:
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		if data.is_core:
			EventBus.building_clicked.emit(info["node"], data)
			break
	await _frames(15)
	await _shot(shot_name)
	EventBus.building_deselected.emit()
	await _frames(5)

func _click_deposit(shot_name: String) -> void:
	var gen: Node = get_tree().current_scene.get_node_or_null("MapGenerator")
	if gen == null:
		return
	for entry in gen.get("_deposit_cells"):
		if is_instance_valid(entry["node"]) and String(entry["id"]) == "forest":
			EventBus.deposit_clicked.emit(entry["node"], String(entry["id"]),
				Vector2i(int(entry["cell_x"]), int(entry["cell_y"])))
			break
	await _frames(15)
	await _shot(shot_name)
	EventBus.building_deselected.emit()
	UIManager.close_all_windows()
	await _frames(5)

## Fuera prologo, guia rapida, menu principal y la tarjeta del tutorial.
func _quiet() -> void:
	var main := get_tree().current_scene
	var tut: Node = main.get_node_or_null("TutorialPanel")
	if tut and tut.has_method("is_intro_open") and tut.call("is_intro_open"):
		tut.call("_close")
	for guide in get_tree().get_nodes_in_group("quick_guide"):
		if guide.has_method("is_open") and guide.is_open():
			guide.close()
	for panel_name in ["TutorialPanel", "HelperPanel", "TitleMenu"]:
		var p: Node = main.get_node_or_null(panel_name)
		if p and p is CanvasLayer:
			(p as CanvasLayer).visible = false
	get_tree().paused = false

func _hours() -> Dictionary:
	var c: DayCycle = DayClock.get_cycle()
	var L := c.length()
	return {
		"dia": 0.5 * (c.dawn_seconds + c.day_seconds + c.dusk_seconds) / L,
		"noche": 1.0 - 0.5 * c.night_seconds / L,
	}

func _camera(target: Vector2, zoom: float) -> void:
	var cam: Node = get_tree().current_scene.get_node_or_null("MonumentalCamera")
	if cam == null:
		return
	var st: Dictionary = cam.get_state()
	st["target_x"] = target.x
	st["target_y"] = target.y
	if zoom >= 0.0:
		st["distance"] = lerpf(cam.min_distance, cam.max_distance, zoom)
	else:
		st["distance"] = float(cam.get("default_distance"))
	cam.set_state(st)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true).timeout

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [OUT_DIR, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("revision_probe: ", ProjectSettings.globalize_path(path))

func _finish() -> void:
	SettingsParking.restore(_settings_snap)
	SaveParking.restore(BACKUP_PATH)
	get_tree().quit()
