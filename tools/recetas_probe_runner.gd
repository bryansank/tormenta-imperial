extends "res://tools/ficha_probe_runner.gd"
## Sonda de las recetas (feat/recetas-tarjetas): siembra la colonia de la sonda
## de arte y saca la ficha con FABRICAR de cada taller en sus estados (libre,
## con cola, con recetas cerradas y sin recursos) y las pestanas del Nucleo.
## Capturas (ignoradas por git) en
## docs/media/dev/recetas/<vista>_<perfil>_<WxH>_<toma>.png.

const RECETAS_OUT := "res://docs/media/dev/recetas"

func _run() -> void:
	_args = OS.get_cmdline_user_args()
	var shot := _arg("shot-size")
	if shot != "":
		var wh := shot.split("x")
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
		await _frames(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RECETAS_OUT))
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
	_tag = "%s_%s_%dx%d" % [_arg("view", "3d"), DeviceProfile.current(), win.x, win.y]
	var scene := "res://scenes/main/Main2D.tscn" if _arg("view") == "2d" else "res://scenes/main/Main.tscn"
	GameManager.title_dismissed = true
	get_tree().change_scene_to_file(scene)
	await _frames(40)
	_quiet()

	var seeder: Node = ArteRunner.new()
	seeder._write_seeded_save()
	_add_military_lots(String(seeder.SAVE_PATH))
	seeder.free()
	GameManager.clear_save_and_reload_from(SaveSlotsRef.read(GameManager.active_slot()), scene)
	await _frames(60)
	_quiet()
	await _seconds(4.0)
	_quiet()
	ProgressionManager.current_era = 3
	for res_name in ["gold", "wood", "steel", "planks", "ingots", "beams"]:
		ResourceManager.unlock(ResourceManager.name_to_type(res_name))
	_camera(Vector2(-6.0, -2.0), -1.0)
	await _seconds(1.0)

	# Aserradero: libre, y con 7 tandas en cola (×1 + ×1 + ×5 desde la tarjeta).
	ResourceManager.set_amounts({"gold": 900, "wood": 600, "steel": 200, "planks": 10, "ingots": 4, "beams": 2})
	var saw := _first("sawmill")
	if saw:
		await _recipes(saw, "aserradero")
		_press_card(saw, "make_planks", [1, 1, 5])
		await _recipes(saw, "aserradero_cola", "make_planks")
		ProcessManager.cancel(saw)
	# Mina: sin acero las de acero salen cerradas; con poco oro, lo que falta.
	_lock("steel")
	ResourceManager.set_amounts({"gold": 25, "wood": 600, "planks": 10})
	var mine := _first("gold_mine")
	if mine:
		await _recipes(mine, "mina")
	ResourceManager.unlock(ResourceManager.Type.STEEL)
	# Fundicion: todo abierto, una en marcha.
	ResourceManager.set_amounts({"gold": 900, "wood": 600, "steel": 300, "planks": 10, "beams": 2})
	var foundry := _first("foundry")
	if foundry:
		await _recipes(foundry, "fundicion")
		_press_card(foundry, "make_beams", [5])
		await _recipes(foundry, "fundicion_cola", "make_beams")
		ProcessManager.cancel(foundry)
	# Nucleo: sus pestanas (lo suyo, un taller y la Refineria cerrada).
	_lock("oil")
	_lock("fuel")
	var core := _first("nucleo")
	if core:
		for tab in ["own", "sawmill", "refinery", "hand"]:
			ProcessActionsPanel._core_tab_memory = tab
			await _recipes(core, "nucleo_" + tab)
	ProcessActionsPanel._core_tab_memory = ""
	_finish()

func _lock(res_name: String) -> void:
	ResourceManager._unlocked[ResourceManager.name_to_type(res_name)] = false

## Abre la ficha y pulsa en la tarjeta `pid` el verbo con cada cantidad de `picks`.
func _press_card(node: Node, pid: String, picks: Array) -> void:
	var info: Node = get_tree().current_scene.get_node("BuildingInfoPanel")
	EventBus.building_clicked.emit(node, GridManager.get_building_info(node)["data"])
	var card: Node = info._scroll.find_child("ProcessCard_" + pid, true, false)
	if card == null:
		print("recetas_probe: sin tarjeta ", pid)
		return
	for n in picks:
		card.select(int(n))
		card.verb_button().pressed.emit()
	card.select(1)
	EventBus.building_deselected.emit()

## La ficha abierta en FABRICAR (y, si se pide, con la tarjeta `pid` a la vista).
func _recipes(node: Node, shot_name: String, pid: String = "") -> void:
	var info: Node = get_tree().current_scene.get_node("BuildingInfoPanel")
	EventBus.building_clicked.emit(node, GridManager.get_building_info(node)["data"])
	await _frames(15)
	var section: Control = info._scroll.find_child("RecipeSection", true, false)
	var target: Control = section
	if pid != "":
		var card: Control = info._scroll.find_child("ProcessCard_" + pid, true, false)
		if card != null:
			target = card
	if target != null:
		# La seccion (o la tarjeta) arriba del todo de la ficha.
		var y: float = target.get_global_rect().position.y - (info._vbox as Control).get_global_rect().position.y
		info._scroll.scroll_vertical = int(maxf(0.0, y - 4.0))
	await _frames(6)
	_report_widths(shot_name)
	await _rshot(shot_name)
	EventBus.building_deselected.emit()
	await _frames(5)

func _rshot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [RECETAS_OUT, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("recetas_probe: ", ProjectSettings.globalize_path(path))
