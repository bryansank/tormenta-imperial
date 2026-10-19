extends "res://tools/revision_probe_runner.gd"
## Sonda de las fichas (feat/ui3-ficha): siembra la colonia grande de la sonda
## de arte con Cuartel, Astillero, Aerodromo y Granja, y saca la ficha de cada
## edificio y de un yacimiento. Capturas (ignoradas por git) en
## docs/media/dev/ficha/<vista>_<perfil>_<WxH>_<tag>_<toma>.png.

const FICHA_OUT := "res://docs/media/dev/ficha"

func _run() -> void:
	_args = OS.get_cmdline_user_args()
	var shot := _arg("shot-size")
	if shot != "":
		var wh := shot.split("x")
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
		await _frames(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FICHA_OUT))
	SaveParking.park(BACKUP_PATH)
	_settings_snap = SettingsParking.park()
	GameConfig.dev_mode = false
	GameConfig.ui_view_mode = "2d" if _arg("view") == "2d" else "3d"
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
	_tag = "%s_%s_%dx%d%s" % [_arg("view", "3d"), DeviceProfile.current(), win.x, win.y,
		("_" + _arg("tag")) if _arg("tag") != "" else ""]
	var scene := "res://scenes/main/Main2D.tscn" if _arg("view") == "2d" else "res://scenes/main/Main.tscn"
	GameManager.title_dismissed = true
	get_tree().change_scene_to_file(scene)
	await _frames(40)
	_quiet()

	var seeder: Node = ArteRunner.new()
	seeder._write_seeded_save()
	_add_military_lots(String(seeder.SAVE_PATH))
	_add_ficha_lots(String(seeder.SAVE_PATH))
	seeder.free()
	GameManager.clear_save_and_reload_from(SaveSlotsRef.read(GameManager.active_slot()), scene)
	await _frames(60)
	_quiet()
	await _seconds(4.0)
	_quiet()
	ProgressionManager.current_era = 3
	ArmyManager._units = {"infantry": 4, "artillery": 2}
	EventBus.army_changed.emit()
	ResourceManager.set_amounts({"gold": 1500, "wood": 600, "steel": 300, "oil": 120, "planks": 40, "beams": 12})
	_camera(Vector2(-6.0, -2.0), -1.0)
	await _seconds(1.0)

	var saw := _first("sawmill")
	if saw:
		await _ficha(saw, "aserradero")
		ProductionManager.keep_in_building(saw, {"wood": 24})
		# El primero que la ficha ensena (sin recursos ni materiales cerrados).
		var procs: Array = ProcessManager.get_processes_for("sawmill").filter(
			func(p): return not ProcessActionsPanel._process_has_locked_resource(p))
		if not procs.is_empty():
			ProcessManager.enqueue_process(saw, procs[0], 1)
			ProcessManager.enqueue_process(saw, procs[0], 1)
			ProcessManager.enqueue_process(saw, procs[0], 5)
		await _ficha(saw, "aserradero_cola")
		var scroll: ScrollContainer = get_tree().current_scene.get_node("BuildingInfoPanel")._scroll
		EventBus.building_clicked.emit(saw, GridManager.get_building_info(saw)["data"])
		await _frames(15)
		if not procs.is_empty():
			var card: Control = scroll.find_child("ProcessCard_" + String(procs[0]["id"]), true, false)
			if card:
				scroll.ensure_control_visible(card)
				await _frames(5)
				await _shot("aserradero_cola_tarjeta")
		scroll.scroll_vertical = 100000
		await _frames(5)
		await _shot("aserradero_cola_abajo")
		EventBus.building_deselected.emit()
		await _frames(5)
		ProcessManager.cancel(saw)
	for pair in [["nucleo", "nucleo"], ["farm", "granja"], ["market", "mercado"],
			["laboratory", "laboratorio"], ["barracks", "cuartel"], ["shipyard", "astillero"],
			["aerodrome", "aerodromo"], ["house", "casa"], ["road", "carretera"]]:
		var node := _first(String(pair[0]))
		if node == null:
			print("ficha_probe: no hay ", pair[0])
			continue
		if pair[0] == "barracks":
			ArmyManager.train("infantry")
		await _ficha(node, String(pair[1]))
		if pair[0] == "barracks":
			var panel: Node = get_tree().current_scene.get_node("BuildingInfoPanel")
			EventBus.building_clicked.emit(node, GridManager.get_building_info(node)["data"])
			await _frames(15)
			panel._scroll.scroll_vertical = 100000
			await _frames(5)
			await _shot("cuartel_abajo")
			EventBus.building_deselected.emit()
			await _frames(5)
	await _click_deposit("yacimiento")
	var army: Node = get_tree().current_scene.get_node_or_null("ArmyPanel")
	if army:
		army.open()
		await _frames(15)
		await _shot("ejercito_resumen")
		UIManager.close_all_windows()
		await _frames(5)
	_finish()

func _add_ficha_lots(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	for entry in data["buildings"]:
		var cell := Vector2i(int(entry["cell_x"]), int(entry["cell_y"]))
		if cell == Vector2i(12, 12):
			entry["id"] = "shipyard"
		elif cell == Vector2i(24, 12):
			entry["id"] = "aerodrome"
		elif cell == Vector2i(12, 16):
			entry["id"] = "farm"
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func _first(building_id: String) -> Node:
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).id == building_id:
			return info["node"]
	return null

func _ficha(node: Node, shot_name: String) -> void:
	EventBus.building_clicked.emit(node, GridManager.get_building_info(node)["data"])
	await _frames(15)
	_report_widths(shot_name)
	await _shot(shot_name)
	EventBus.building_deselected.emit()
	await _frames(5)

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [FICHA_OUT, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("ficha_probe: ", ProjectSettings.globalize_path(path))

## Lo que mide la ficha y lo mas ancho de dentro: nada debe pasar del panel.
func _report_widths(shot_name: String) -> void:
	var info: Node = get_tree().current_scene.get_node_or_null("BuildingInfoPanel")
	if info == null:
		return
	var root: Control = info._panel
	var panel: Control = info._win["panel"]
	print("ficha_probe: ", shot_name, " root=", root.size.x, " panel=", panel.size.x,
		" panel_min=", panel.get_combined_minimum_size().x, " scroll=", info._scroll.size.x)
	for c in info._vbox.get_children() + (info._win["body"] as Node).get_children():
		if c is Control and (c as Control).visible:
			var w: float = (c as Control).get_combined_minimum_size().x
			if w > 300.0:
				print("ficha_probe:   ancho ", c.name, " ", c.get_class(), " min=", w)
