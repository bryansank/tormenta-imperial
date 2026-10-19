extends "res://tools/revision_probe_runner.gd"
## Sonda del rediseno de la interfaz (fase 2): recorre con ventana las pantallas
## nuevas en una colonia temprana y en la grande de la sonda de arte. Reutiliza
## la siembra y los ayudantes de revision_probe_runner.gd. Capturas (ignoradas
## por git) en docs/media/dev/ui2/<vista>_<perfil>_<WxH>_<toma>.png. Argumentos
## tras `--`: --shot-size=WxH, --profile=pc|tablet|phone, --view=2d, --tag=x.

const UI2_OUT := "res://docs/media/dev/ui2"

func _run() -> void:
	_args = OS.get_cmdline_user_args()
	var shot := _arg("shot-size")
	if shot != "":
		var wh := shot.split("x")
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
		await _frames(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UI2_OUT))
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
	# --theme=dark: el tema oscuro de las ventanas (Ajustes > Pantalla > Tema).
	GameConfig.ui_theme = "dark" if _arg("theme") == "dark" else "light"
	DeviceProfile.apply_all()
	await _frames(5)
	var win := DisplayServer.window_get_size()
	_tag = "%s_%s_%dx%d%s%s" % [_arg("view", "3d"), DeviceProfile.current(), win.x, win.y,
		"_oscuro" if _arg("theme") == "dark" else "",
		("_" + _arg("tag")) if _arg("tag") != "" else ""]
	var scene := "res://scenes/main/Main2D.tscn" if _arg("view") == "2d" else "res://scenes/main/Main.tscn"

	# ── Colonia temprana ────────────────────────────────────────────────
	GameManager.title_dismissed = true
	get_tree().change_scene_to_file(scene)
	await _frames(60)
	_quiet()
	await _seconds(3.0)
	_quiet()
	var main := get_tree().current_scene
	await _shot("t_hud_barra_bloqueada")
	var bar: Node = main.get_node_or_null("BottomBar")
	if bar and bar.has_method("button"):
		var b: Button = bar.button("army")
		if b:
			print("ui2_probe: army bloqueado=", not bar.is_open_for("army"), " porque=", bar.reason_for("army"))
	var skb: CanvasLayer = main.get_node_or_null("SkirmishButton")
	print("ui2_probe: SkirmishButton visible=", skb.visible if skb else null)
	var only_bar := _arg("only") == "bar"
	var build: Node = main.get_node_or_null("ConstructionMenu")
	if only_bar:
		await _bar_shots(main, scene)
		return
	build._open()
	await _frames(12)
	await _shot("t_construir")
	build._select_building(load("res://data/buildings/barracks.tres"))
	await _frames(10)
	await _shot("t_construir_cuartel_bloqueado")
	build._close()
	await _frames(5)
	main.get_node("ObjectivePanel").toggle()
	await _frames(10)
	await _shot("t_quehacer")
	UIManager.close_all_windows()
	await _frames(5)
	# Tutorial: un paso de espera (sin oro ni madera) abierto y luego plegado.
	var tut: CanvasLayer = main.get_node_or_null("TutorialPanel")
	if tut:
		var saved_res := {"gold": ResourceManager.get_amount(ResourceManager.Type.GOLD),
			"wood": ResourceManager.get_amount(ResourceManager.Type.WOOD)}
		ResourceManager.set_amounts({"gold": 10, "wood": 5})
		tut.visible = true
		TutorialManager.intro_seen = true
		TutorialManager.start_guide(false)
		await _seconds(1.5)
		print("ui2_probe: paso del tutorial=", TutorialManager.current_step())
		await _shot("t_tutorial_paso")
		await _seconds(4.5)
		await _shot("t_tutorial_recordatorio")
		TutorialManager.finish_guide()
		await _frames(5)
		tut.visible = false
		ResourceManager.set_amounts(saved_res)
	# Menu principal con partida que continuar.
	var title: Node = main.get_node_or_null("TitleMenu")
	if title:
		(title as CanvasLayer).visible = true
		title.open_menu()
		await _frames(15)
		await _shot("menu_principal_con_partida")
		title.close_menu()
		await _frames(5)

	# ── Colonia grande ──────────────────────────────────────────────────
	var seeder: Node = ArteRunner.new()
	seeder._write_seeded_save()
	_add_military_lots(String(seeder.SAVE_PATH))
	seeder.free()
	GameManager.clear_save_and_reload_from(SaveSlotsRef.read(GameManager.active_slot()), scene)
	await _frames(60)
	_quiet()
	await _seconds(5.0)
	_quiet()
	main = get_tree().current_scene
	ArmyManager._units = {"infantry": 6, "artillery": 3, "vehicle": 1}
	EventBus.army_changed.emit()
	ResourceManager.set_amounts({"gold": 2400, "wood": 900, "steel": 300, "oil": 120})
	_camera(Vector2(-6.0, -2.0), -1.0)
	await _seconds(1.5)
	skb = main.get_node_or_null("SkirmishButton")
	print("ui2_probe: SkirmishButton visible (grande)=", skb.visible if skb else null)
	await _shot("g_hud_barra")

	# ☰ y la tarjeta de la colonia.
	var pause: Node = main.get_node_or_null("PauseMenu")
	if pause:
		pause.open_menu()
		await _frames(12)
		await _shot("g_menu")
		pause.resume()
		await _frames(5)
	var rank: Node = main.get_node_or_null("RankPanel")
	if rank:
		rank.open()
		await _frames(12)
		await _shot("g_colonia")
		UIManager.close_all_windows()
		await _frames(5)

	# CONSTRUIR con todo: filas, rojos, candados, Al maximo.
	build = main.get_node_or_null("ConstructionMenu")
	ResourceManager.set_amounts({"gold": 120, "wood": 60, "steel": 10, "oil": 0})
	build._open()
	await _frames(12)
	await _shot("g_construir_pobre")
	build._select_building(load("res://data/buildings/warehouse.tres"))
	await _frames(10)
	await _shot("g_construir_almacen")
	build._close()
	await _frames(5)
	ResourceManager.set_amounts({"gold": 2400, "wood": 900, "steel": 300, "oil": 120})

	# Fichas: aserradero nivel 2, dañado, Nucleo, Granja.
	var saw: Node = null
	var farm: Node = null
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		if data.id == "sawmill" and saw == null:
			saw = info["node"]
		elif data.id == "farm" and farm == null:
			farm = info["node"]
	if saw:
		saw.set_meta("level", 2)
		EventBus.building_clicked.emit(saw, GridManager.get_building_data(saw) if GridManager.has_method("get_building_data") else load("res://data/buildings/sawmill.tres"))
		await _frames(15)
		await _shot("g_ficha_aserradero")
		EventBus.building_deselected.emit()
		await _frames(5)
		BuildingHealth.damage_building(saw, int(BuildingHealth.get_max_health(saw) * 0.5))
		EventBus.building_clicked.emit(saw, load("res://data/buildings/sawmill.tres"))
		await _frames(15)
		await _shot("g_ficha_danado")
		EventBus.building_deselected.emit()
		await _frames(5)
	if farm:
		EventBus.building_clicked.emit(farm, load("res://data/buildings/farm.tres"))
		await _frames(15)
		await _shot("g_ficha_granja")
		EventBus.building_deselected.emit()
		await _frames(5)
	await _click_nucleo("g_ficha_nucleo")
	# El Nucleo con una cola de tandas: x1 + x1 + x5 = 7.
	var core: Node = null
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).is_core:
			core = info["node"]
	if core:
		var procs: Array = ProcessManager.get_processes_for("nucleo")
		if not procs.is_empty():
			ProcessManager.enqueue_process(core, procs[0], 1)
			ProcessManager.enqueue_process(core, procs[0], 1)
			ProcessManager.enqueue_process(core, procs[0], 5)
		await _click_nucleo("g_ficha_nucleo_cola")
		ProcessManager.cancel(core)
	# El Cuartel: su ficha trae ENTRENAR.
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).id == "barracks":
			ArmyManager.train("infantry")
			EventBus.building_clicked.emit(info["node"], info["data"])
			await _frames(15)
			await _shot("g_ficha_cuartel")
			EventBus.building_deselected.emit()
			await _frames(5)
			break
	# PAIS Y BANDERA: fondos y colores.
	if rank and rank.has_method("open_editor"):
		rank.open_editor()
		await _frames(15)
		await _shot("g_pais_bandera")
		var ed: Node = rank.editor()
		if ed:
			ed.select_tab("colors")
			await _frames(10)
			await _shot("g_pais_bandera_colores")
			ed.select_tab("emblems")
			await _frames(10)
			await _shot("g_pais_bandera_emblemas")
			ed.cancel()
		await _frames(5)

	# Mercado, Investigar, Encargos.
	for pair in [["MarketPanel", "g_mercado"], ["TechTreePanel", "g_investigar"]]:
		var p: Node = main.get_node_or_null(pair[0])
		if p:
			p.open()
			await _frames(15)
			await _shot(pair[1])
			UIManager.close_all_windows()
			await _frames(5)
	var contracts: Node = main.get_node_or_null("ContractPanel")
	if contracts:
		ContractManager.load_save_data({"v": 1,
			"slots": {
				"neighbors": {"id": 3, "source": "neighbors", "template": "nb_wood",
					"ask": {"wood": 60}, "reward": {"morale": 8},
					"seconds_total": 240.0, "seconds_left": 120.0},
				"regency": {"id": 4, "source": "regency", "template": "rg_steel",
					"ask": {"steel": 900, "gold": 100}, "reward": {"gold": 300},
					"seconds_total": 300.0, "seconds_left": 50.0},
			},
			"cooldowns": {"regency": 0.0, "neighbors": 0.0, "smuggler": 90.0},
			"reputation": {"regency": 0, "neighbors": 0, "smuggler": 0},
			"next_id": 5})
		contracts.open()
		await _frames(15)
		await _shot("g_encargos")
		UIManager.close_all_windows()
		await _frames(5)

	# EJERCITO por pestañas.
	ProgressionManager.current_era = 3
	ArmyManager._units = {"infantry": 4, "artillery": 3, "vehicle": 2, "torpedo_boat": 2,
		"gunboat": 3, "dreadnought": 1, "fighter": 4, "airship": 1}
	EventBus.army_changed.emit()
	var army: Node = main.get_node_or_null("ArmyPanel")
	if army:
		army.open()
		await _frames(10)
		for tab in ["land", "sea", "air"]:
			army.select_tab(tab)
			await _frames(10)
			await _shot("g_ejercito_%s" % tab)
		UIManager.close_all_windows()
		await _frames(5)

	# MISIONES: campaña a medias y Ataque Final.
	var skirmish: Node = main.get_node_or_null("SkirmishPanel")
	TutorialManager.first_sortie_done = true
	CombatManager._campaigns.progress = {"land": 3, "sea": 1, "air": 0}
	EventBus.campaign_changed.emit()
	if skirmish:
		skirmish.open()
		await _frames(10)
		skirmish.select_tab("land")
		await _frames(10)
		await _shot("g_misiones_tierra")
		UIManager.close_all_windows()
		await _frames(5)
		ProgressionManager.summon_final_audit()
		await _frames(5)
		skirmish.open()
		await _frames(15)
		await _shot("g_misiones_ataque_final")
		UIManager.close_all_windows()
		await _frames(5)

	# Partes de guerra.
	var reports: Node = main.get_node_or_null("WarReportScreen")
	if reports:
		reports.visible = true
		EventBus.defense_auto_resolved.emit(false, 6, {"casualties": {"infantry": 2},
			"enemy_casualties": {"infantry": 3, "artillery": 1}, "tower_crews": 1,
			"tower_crews_lost": 0, "morale_delta": -4})
		await _frames(15)
		await _shot("g_parte_defensa")
		reports.close_current()
		await _frames(5)
		EventBus.tithe_resolved.emit(true, {"gold": 300, "wood": 120})
		await _frames(15)
		await _shot("g_parte_impuesto")
		while reports.is_showing():
			reports.close_current()
			await _frames(3)

	# Ajustes: las pestañas y Mas opciones.
	var settings: Node = main.get_node_or_null("SettingsPanel")
	if settings:
		settings.toggle()
		await _frames(10)
		for i in range(4):
			settings.select_tab(i)
			await _frames(10)
			await _shot("g_ajustes_%d" % i)
		settings.select_tab(1)
		settings.set_advanced_open(true)
		await _frames(10)
		await _shot("g_ajustes_mas_opciones")
		if settings.is_open():
			settings.toggle()
		await _frames(5)

	# Ayuda.
	for help in get_tree().get_nodes_in_group("help_index"):
		help.open()
		await _frames(12)
		await _shot("g_ayuda")
		var ids: Array = help.listed_ids()
		if not ids.is_empty():
			help.show_page(String(ids[0]))
			await _frames(10)
			await _shot("g_ayuda_pagina")
		help.close()
		await _frames(5)
		break

	# Partidas y Victoria.
	var saves: CanvasLayer = GameManager.open_saves_list()
	await _frames(15)
	await _shot("g_partidas")
	if is_instance_valid(saves):
		saves.close()
	await _frames(5)
	EventBus.victory_achieved.emit({"time_played": 5400.0, "buildings_built": 64,
		"trades_completed": 12, "milestones": 9, "storms_survived": 7,
		"tithes_repelled": 3, "audit_summons": 1, "mode": "campaign"})
	await _frames(20)
	await _shot("g_victoria")
	_finish()

## Solo la barra de abajo: temprana (bloqueada) y con la colonia grande.
func _bar_shots(main: Node, scene: String) -> void:
	var seeder: Node = ArteRunner.new()
	seeder._write_seeded_save()
	_add_military_lots(String(seeder.SAVE_PATH))
	seeder.free()
	GameManager.clear_save_and_reload_from(SaveSlotsRef.read(GameManager.active_slot()), scene)
	await _frames(60)
	_quiet()
	await _seconds(4.0)
	_quiet()
	_camera(Vector2(-6.0, -2.0), -1.0)
	await _seconds(1.0)
	await _shot("g_hud_barra")
	_finish()

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [UI2_OUT, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("ui2_probe: ", ProjectSettings.globalize_path(path))
