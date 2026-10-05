extends Node
## Sonda de textos de los paneles (rama feat/menos-texto). Arranca una partida
## NUEVA, la siembra (era 3, cuatro recursos, un aserradero junto al bosque, un
## cuartel y tropa) y fotografia cada panel y overlay del juego, uno a uno:
##
##   hud            HUD con la Tormenta en aviso y tres avisos en pantalla
##   construir      CONSTRUIR con la Fundicion elegida (se puede pagar)
##   construir_hq   CONSTRUIR con el Cuartel General elegido (no se puede)
##   nucleo         panel del Nucleo (procesos y nombre)
##   aserradero     panel del aserradero (produccion, mejora, trabajadores)
##   veta           panel de un bosque (yacimiento)
##   objetivos      ¿QUE HACER?
##   ejercito       EJERCITO (entrenar, con una unidad en cola)
##   escaramuza     ESCARAMUZAS (elegir tropa)
##   menu           ☰ MENU
##   mercado        Mercado
##   tecnologia     Arbol tecnologico
##   parte_defensa  parte de defensa a ciegas
##   parte_diezmo   parte del Diezmo cobrado
##   ayuda          globo de ayuda de CONSTRUIR
##   mapa           mapa de expedicion
##   tablero        tablero de combate
##
## Argumentos tras `--`: --shot-size=WxH, --profile=pc|tablet|phone,
## --prefix=antes|despues, --locale=es|en. Capturas en docs/media/dev/.

const SaveParking := preload("res://tests/save/save_parking.gd")
const SettingsParking := preload("res://tests/save/settings_parking.gd")
const BACKUP_PATH := "user://save_game.texto_probe.bak"
const OUT_DIR := "res://docs/media/dev"

var _tag := ""
var _settings_snap: Dictionary
var _args: PackedStringArray
var _main: Node
var _sawmill: Node = null

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
	var shot := _arg("shot-size", "1280x800")
	var wh := shot.split("x")
	DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	await _frames(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	SaveParking.park(BACKUP_PATH)
	if FileAccess.file_exists("user://save_game.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_game.json"))
	_settings_snap = SettingsParking.park()
	GameConfig.dev_mode = false
	GameConfig.ui_device_profile = _arg("profile", "pc")
	GameConfig.ui_scale_pct = 0
	GameConfig.ui_text_size = "auto"
	GameConfig.ui_hud_hidden = []
	GameConfig.ui_layout = {}
	GameConfig.ui_helper_visible = false
	GameConfig.ui_touch_controls = "auto"
	Tr.set_locale(_arg("locale", "es"))
	DeviceProfile.apply_all()
	await _frames(5)
	var win := DisplayServer.window_get_size()
	_tag = "%s_%s_%s" % [_arg("prefix", "antes"), DeviceProfile.current(), _arg("locale", "es")]
	print("texto_probe: window=", win, " profile=", DeviceProfile.current())

	GameManager.title_dismissed = true
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await _frames(60)
	_main = get_tree().current_scene
	_quiet_onboarding()
	await _frames(10)
	_seed()
	await _frames(30)
	_quiet_onboarding()
	await _frames(10)

	# ── HUD con la Tormenta y avisos ──
	var storm: Node = _main.get_node_or_null("StormHUD")
	if storm != null and storm.get("_panel") != null:
		(storm.get("_panel") as Control).visible = true
		storm.call("_style_for", StormCycle.Phase.WARNING)
	EventBus.notification_posted.emit(Tr.t("NOTIF_NO_WOOD"), "warning", UITheme.WARNING)
	EventBus.notification_posted.emit(Tr.t("NOTIF_UPKEEP_UNPAID") % 12, "danger", UITheme.DANGER)
	EventBus.notification_posted.emit(Tr.t("NOTIF_STORAGE_TRIMMED") % [40, 3500], "warning", UITheme.WARNING)
	await _frames(10)
	await _shot("hud")

	# ── CONSTRUIR ──
	var build: Node = _main.get_node_or_null("ConstructionMenu")
	if build != null:
		build.call("_open")
		build.call("_select_building", _data("foundry"))
		await _frames(15)
		await _shot("construir")
		build.call("_select_building", _data("headquarters"))
		await _frames(10)
		await _shot("construir_hq")
		build.call("_close")
		await _frames(5)

	# ── Paneles de edificio y yacimiento ──
	var nucleo: Node = _first_building("nucleo")
	if nucleo != null:
		EventBus.building_clicked.emit(nucleo, GridManager.get_building_info(nucleo)["data"])
		await _frames(10)
		await _shot("nucleo")
	if _sawmill != null:
		EventBus.building_clicked.emit(_sawmill, GridManager.get_building_info(_sawmill)["data"])
		await _frames(10)
		await _shot("aserradero")
	var forest: Node = _first_deposit("forest")
	if forest != null:
		EventBus.deposit_clicked.emit(forest, "forest", Vector2i.ZERO)
		await _frames(10)
		await _shot("veta")
	EventBus.building_deselected.emit()
	await _frames(5)

	# ── Paneles de colonia ──
	await _panel_shot("ObjectivePanel", "toggle", "objetivos")
	ArmyManager.train("infantry")
	await _panel_shot("ArmyPanel", "_toggle_panel", "ejercito")
	await _panel_shot("SkirmishPanel", "_toggle_panel", "escaramuza")
	await _panel_shot("MarketPanel", "_toggle_panel", "mercado")
	await _panel_shot("TechTreePanel", "_toggle_panel", "tecnologia")

	var menu: Node = _main.get_node_or_null("PauseMenu")
	if menu != null:
		menu.menu_button().pressed.emit()
		await _frames(10)
		await _shot("menu")
		menu.resume()
		await _frames(5)

	# ── Partes de guerra ──
	var report: Node = _main.get_node_or_null("WarReportScreen")
	if report != null:
		EventBus.defense_auto_resolved.emit(false, 6, {
			"casualties": {"infantry": 2}, "enemy_casualties": {"infantry": 3},
			"tower_crews": 1, "tower_crews_lost": 1, "morale_delta": -5})
		report.try_show_next()
		await _frames(10)
		await _shot("parte_defensa")
		report.close_current()
		EventBus.tithe_resolved.emit(false, {"gold": 120, "wood": 80, "buildings": 1, "workers": 2})
		await _frames(5)
		report.try_show_next()
		await _frames(10)
		await _shot("parte_diezmo")
		report.close_current()
		await _frames(5)

	# ── Un globo de ayuda ──
	var helper: Node = _main.get_node_or_null("HelperPanel")
	if helper != null:
		helper.show_help("callout_build")
		await _frames(15)
		await _shot("ayuda")
		helper.show_help("callout_menus")
		await _frames(15)
		await _shot("ayuda_menu")

	# ── Mapa de expedicion y tablero ──
	ArmyManager._units = {"infantry": 4, "artillery": 2}
	EventBus.army_changed.emit()
	if CombatManager.launch_expedition({"infantry": 2, "artillery": 1}, 7, false):
		await _frames(20)
		var battle: Node = _main.get_node_or_null("BattleScreen")
		if battle != null and battle.has_method("open_map"):
			battle.open_map()
			await _frames(15)
		await _shot("mapa")
		CombatManager.abandon_expedition()
		await _frames(20)
		var bs: Node = _main.get_node_or_null("BattleScreen")
		if bs != null and bs.has_method("_close_all"):
			bs.call("_close_all")
		await _frames(10)
	if CombatManager.start_skirmish({"infantry": 2, "artillery": 1}, 3):
		await _frames(30)
		await _shot("tablero")
	_finish()

func _panel_shot(node_name: String, method: String, file_name: String) -> void:
	var panel: Node = _main.get_node_or_null(node_name)
	if panel == null or not panel.has_method(method):
		return
	panel.call(method)
	await _frames(12)
	await _shot(file_name)
	panel.call(method)
	await _frames(5)

## Sin prologo, guia rapida ni tutorial: tapan los paneles.
func _quiet_onboarding() -> void:
	TutorialManager.intro_seen = true
	TutorialManager.mark_help_seen("quick_guide")
	if TutorialManager.is_guide_active():
		TutorialManager.skip_guide()
	for group in ["prologue_screen", "quick_guide"]:
		for n in get_tree().get_nodes_in_group(group):
			if n.has_method("is_open") and n.is_open():
				n.close()
	var offline: Variant = GameManager.get("_offline_canvas")
	if offline != null and is_instance_valid(offline):
		(offline as Node).queue_free()
		GameManager.set("_offline_canvas", null)
	if get_tree().paused:
		get_tree().paused = false

func _seed() -> void:
	ProgressionManager.current_era = 3
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": true})
	for res in ["steel", "oil"]:
		EventBus.resource_unlocked.emit(res)
	ProgressionManager.current_phase = GameConfig.Phase.EXPANSION
	EventBus.phase_advanced.emit(GameConfig.Phase.EXPANSION)
	ResourceManager.set_amounts({"gold": 900, "wood": 400, "steel": 250, "oil": 60})
	var placer: Node = _main.get_node_or_null("BuildingPlacer")
	var map_gen: Node = _main.get_node_or_null("MapGenerator")
	if placer != null and map_gen != null:
		_sawmill = _plant_near(placer, map_gen, "sawmill", "forest")
		_plant_anywhere(placer, "barracks")
		_plant_anywhere(placer, "warehouse")
	PopulationManager._population = 26
	PopulationManager._max_population = 32
	PopulationManager._morale = 72
	ArmyManager._units = {"infantry": 3, "artillery": 1}
	EventBus.army_changed.emit()
	EventBus.population_changed.emit(26, 32)

func _plant_near(placer: Node, map_gen: Node, id: String, deposit: String) -> Node:
	var data := _data(id)
	var spots: Array = map_gen.buildable_spots_near(deposit, data.grid_size, 1, 1)
	if spots.is_empty():
		return null
	var node: Node = placer.place_building_at(data, spots[0]["origin"])
	if node != null:
		ProductionManager.register_building(node, data, 0.0)
	return node

func _plant_anywhere(placer: Node, id: String) -> Node:
	var data := _data(id)
	for r in range(3, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := Vector2i(20 + dx, 20 + dy)
				if GridManager.is_valid_cell(c) and GridManager.can_place(c, data.grid_size):
					var node: Node = placer.place_building_at(data, c)
					if node != null:
						ProductionManager.register_building(node, data, 0.0)
					return node
	return null

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id)

func _first_building(id: String) -> Node:
	for info in GridManager.get_all_buildings():
		var d: BuildingData = info.get("data")
		if d != null and d.id == id:
			return info["node"]
	return null

func _first_deposit(id: String) -> Node:
	var map_gen: Node = _main.get_node_or_null("MapGenerator")
	if map_gen == null:
		return null
	for entry in map_gen.get("_deposit_cells"):
		if entry["id"] == id and is_instance_valid(entry["node"]):
			return entry["node"]
	return null

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [OUT_DIR, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("texto_probe: ", ProjectSettings.globalize_path(path))

func _finish() -> void:
	SettingsParking.restore(_settings_snap)
	SaveParking.restore(BACKUP_PATH)
	get_tree().quit()
