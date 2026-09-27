extends Node
## Sonda de la vista 2D: siembra una partida con de todo (edificios de todos los
## tamanos, una obra, una ruina, uno danado, uno de nivel 2, calzadas, los cuatro
## yacimientos), la abre en Main2D y hace capturas: vista general, seleccion,
## fantasma valido e invalido y tormenta. Sirve para VER la vista 2D sin jugar.
##
## Con ventana (no headless: headless no pinta nada):
##
##     godot --path . -s tools/view2d_probe.gd -- --view=2d
##     godot --path . -s tools/view2d_probe.gd -- --view=2d --shot-size=400x720
##
## Las capturas van a docs/media/dev/ (ignorada por git). El guardado del
## jugador se aparta al empezar y se devuelve al terminar: la partida sembrada
## se escribe en su sitio solo mientras dura la sonda.
##
## La partida sembrada esta escrita en el formato de save_game.json de siempre,
## el mismo que escribe la vista 3D: que abra bien aqui ES la prueba de que un
## guardado 3D carga en 2D.

const View2D := preload("res://scripts/view2d/View2D.gd")
const SAVE_PATH := "user://save_game.json"
const BACKUP_PATH := "user://save_game.view2d_probe.bak"
const OUT_DIR := "res://docs/media/dev"

var _tag := ""
var _saved_view := "3d"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# --resolution no cambia la ventana con este proyecto; se hace a mano.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-size="):
			var wh := a.substr(12).split("x")
			if wh.size() == 2:
				DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
				await _frames(10)
	var size := get_tree().root.get_visible_rect().size
	print("view2d_probe: window=", DisplayServer.window_get_size(), " visible=", size, " tex=", get_tree().root.get_texture().get_size())
	_tag = "%dx%d" % [int(size.x), int(size.y)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.rename_absolute(SAVE_PATH, BACKUP_PATH)
	GameConfig.dev_mode = false
	_saved_view = GameConfig.ui_view_mode
	_write_seeded_save()
	get_tree().change_scene_to_file("res://scenes/main/Main2D.tscn")
	await _frames(45)
	var placer: Node = get_tree().current_scene.get_node_or_null("BuildingPlacer")
	var cam: Node = get_tree().current_scene.get_node_or_null("Camera2D")
	if placer == null or cam == null:
		push_error("view2d_probe: Main2D sin BuildingPlacer/Camera2D (get_tree().current_scene=%s)" % get_tree().current_scene)
		_finish()
		return
	# Sin paneles encima de la primera captura
	_close_overlays()
	await _frames(5)
	await _shot("2d_overview")

	# Alejado: toda la base
	cam.look_at_world(Vector2(3, 5), 40.0)
	await _frames(5)
	await _shot("2d_far")
	cam.look_at_world(Vector2(3, 5), 22.0)
	await _frames(5)

	# Seleccion de un edificio (el panel de info se abre como en 3D)
	var tower := GridManager.get_building_at(Vector2i(24, 22))
	if tower:
		EventBus.building_clicked.emit(tower, GridManager.get_building_info(tower)["data"])
	await _frames(10)
	await _shot("2d_selected")
	EventBus.building_deselected.emit()
	await _frames(5)

	# Fantasma valido y fantasma invalido (encima del Nucleo)
	var house: BuildingData = load("res://data/buildings/house.tres")
	var mine: BuildingData = load("res://data/buildings/gold_mine.tres")
	EventBus.building_selected_for_placement.emit(house)
	await _ghost_at(placer, Vector2i(18, 18))
	await _shot("2d_ghost_valid")
	EventBus.building_selected_for_placement.emit(mine)
	await _ghost_at(placer, Vector2i(20, 20))
	await _shot("2d_ghost_invalid")
	EventBus.building_placement_cancelled.emit()
	await _frames(5)

	# Tormenta: el mapa se apaga y cae ceniza
	var tint: Node = get_tree().current_scene.get_node_or_null("StormTint")
	if tint:
		tint.set("forced_weight", 0.9)
	await _frames(90)
	await _shot("2d_storm")
	if tint:
		tint.set("forced_weight", 0.0)
	await _frames(5)

	# Menu de construccion con las miniaturas 2D
	var menu: Node = get_tree().current_scene.get_node_or_null("ConstructionMenu")
	if menu:
		menu.call("_open")
		menu.call("_select_building", load("res://data/buildings/refinery.tres"))
		await _frames(10)
		await _shot("2d_menu")
		menu.call("_close")
		await _frames(5)

	# Ajustes con el selector de vista
	var settings: Node = get_tree().current_scene.get_node_or_null("SettingsPanel")
	if settings:
		settings.call("toggle")
		await _frames(10)
		await _shot("2d_settings")
		settings.call("toggle")
		await _frames(5)

	# Cambio de vista en caliente: la misma partida, ahora en 3D
	if not OS.get_cmdline_user_args().has("--no-switch"):
		const ViewMode := preload("res://scripts/view2d/ViewMode.gd")
		var before := GridManager.get_all_buildings().size()
		ViewMode.switch_to("3d", get_tree())
		await _frames(60)
		print("view2d_probe: switched to ", get_tree().current_scene.scene_file_path, " buildings ", before, " -> ", GridManager.get_all_buildings().size(), " cap ", ResourceManager.get_storage_cap(), " warehouses ", ResourceManager.get_warehouse_count())
		_close_overlays()
		await _frames(5)
		await _shot("3d_after_switch")
		# ...y de vuelta, para dejar la preferencia como estaba en esta carpeta de datos
		ViewMode.switch_to("2d", get_tree())
		await _frames(60)
		print("view2d_probe: back to ", get_tree().current_scene.scene_file_path, " buildings ", GridManager.get_all_buildings().size())
		await _shot("2d_after_roundtrip")
	_finish()

func _ghost_at(placer: Node, cell: Vector2i) -> void:
	var xform := get_tree().root.get_canvas_transform()
	var screen := View2D.px_to_screen(xform, View2D.footprint_center_px(cell, Vector2i.ONE))
	get_tree().root.warp_mouse(screen)
	await _frames(3)
	placer.update_ghost(cell)
	await _frames(3)

func _close_overlays() -> void:
	for panel_name in ["TutorialPanel", "HelperPanel"]:
		var p: Node = get_tree().current_scene.get_node_or_null(panel_name)
		if p and p is CanvasLayer:
			(p as CanvasLayer).visible = false

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [OUT_DIR, shot_name, _tag]
	img.save_png(ProjectSettings.globalize_path(path))
	print("view2d_probe: ", ProjectSettings.globalize_path(path))

func _finish() -> void:
	# La preferencia de vista vuelve a como estaba (el cambio en caliente la toca).
	GameConfig.ui_view_mode = _saved_view
	GameConfig.save_user_settings()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.rename_absolute(BACKUP_PATH, SAVE_PATH)
	get_tree().quit()

func _write_seeded_save() -> void:
	var b := func(id: String, x: int, y: int, extra: Dictionary = {}) -> Dictionary:
		var e := {"id": id, "cell_x": x, "cell_y": y}
		e.merge(extra)
		return e
	var buildings: Array = [
		b.call("nucleo", 20, 20),
		b.call("house", 17, 20), b.call("house", 17, 21), b.call("house", 18, 23, {"custom_name": "Casa Key"}),
		b.call("road", 19, 24), b.call("road", 20, 24), b.call("road", 21, 24), b.call("road", 22, 24),
		b.call("road", 23, 24), b.call("road", 23, 23), b.call("road", 23, 22),
		b.call("sawmill", 15, 17),
		b.call("gold_mine", 25, 17),
		b.call("warehouse", 24, 20),
		b.call("foundry", 26, 20, {"rotation": 1, "construction_remaining": 500.0}),
		b.call("barracks", 16, 25, {"health": 0}),
		b.call("tower", 24, 22, {"health": 60}),
		b.call("refinery", 27, 23, {"level": 2}),
		b.call("headquarters", 22, 26),
		b.call("garden", 19, 26), b.call("fountain", 20, 26), b.call("statue", 21, 27),
	]
	var data := {
		"saved_at": Time.get_unix_time_from_system(),
		"resources": {"gold": 900, "steel": 300, "oil": 150, "wood": 600},
		"unlocked_resources": {"gold": true, "wood": true, "steel": true, "oil": true},
		"buildings": buildings,
		"deposits": [
			{"id": "forest", "cell_x": 12, "cell_y": 16, "size_x": 3, "size_y": 3},
			{"id": "gold_vein", "cell_x": 25, "cell_y": 14, "size_x": 2, "size_y": 3},
			{"id": "iron_deposit", "cell_x": 29, "cell_y": 18, "size_x": 3, "size_y": 2},
			{"id": "oil_well", "cell_x": 12, "cell_y": 21, "size_x": 2, "size_y": 2},
			{"id": "forest", "cell_x": 8, "cell_y": 26, "size_x": 3, "size_y": 2},
		],
		"camera": {"target_x": 3.0, "target_y": 5.0, "yaw": 0.0, "distance": 22.0},
		"tutorial": {"intro_seen": true, "tips_seen": []},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
