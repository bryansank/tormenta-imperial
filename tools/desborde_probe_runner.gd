extends "res://tools/revision_probe_runner.gd"
## Sonda de desbordes (fix/desbordes-derecha): abre cada ventana, panel y
## tarjeta del juego (lo de la sonda ui2 y lo que ella no saca: Astillero y
## Aerodromo con cola, mapa de mision, draft, informe, Orden de la Regencia,
## AYUDA pagina a pagina, consejos, guia de edificios, Nueva partida, prologo,
## guia rapida, derrota del asedio...) y en cada una escribe en consola cada
## Control visible cuyo rectangulo se sale del lienzo o del padre que lo
## recorta (tests/ui/overflow_scan.gd). Lanzador: tools/desborde_probe.gd.
##
## Argumentos tras `--`: --shot-size=WxH, --profile=pc|tablet|phone,
## --canvas=WxH (fuerza ese lienzo logico: los de telefono 640x360, 800x360,
## 400x720 no salen en un monitor de PC), --theme=dark|light (sin el, el de
## serie: oscuro desde la piel dieselpunk), --view=2d, --tag=x,
## --shots (guarda captura de cada pantalla; sin el, solo de las que se salen),
## --only=pantalla1,pantalla2 (solo esas tomas, por prefijo).
##
## Resumen al final: "desborde_probe: RESUMEN n desbordes en m pantallas".

const Scan := preload("res://tests/ui/overflow_scan.gd")
const OUT := "res://docs/media/dev/desbordes"
const HelpCatalogRef := preload("res://scripts/ui/HelpCatalog.gd")
const FinalAuditScript := preload("res://scripts/combat/FinalAudit.gd")

var _hits_total := 0
var _screens_hit: Array = []
var _canvas := Vector2.ZERO

func _run() -> void:
	_args = OS.get_cmdline_user_args()
	var shot := _arg("shot-size")
	if shot != "":
		var wh := shot.split("x")
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
		await _frames(10)
	if _arg("canvas") != "":
		var cv := _arg("canvas").split("x")
		_canvas = Vector2(float(cv[0]), float(cv[1]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	SaveParking.park(BACKUP_PATH)
	_settings_snap = SettingsParking.park()
	GameConfig.dev_mode = false
	GameConfig.ui_view_mode = "2d" if _arg("view") == "2d" else "3d"
	GameConfig.ui_device_profile = _arg("profile", "auto")
	GameConfig.ui_scale_pct = _scale_for_canvas()
	GameConfig.ui_text_size = "auto"
	GameConfig.ui_hud_hidden = []
	GameConfig.ui_layout = {}
	GameConfig.ui_helper_visible = false
	GameConfig.ui_touch_controls = "auto"
	var theme_arg := _arg("theme")
	GameConfig.ui_theme = theme_arg if theme_arg in CartoonTheme.WINDOW_THEMES else CartoonTheme.WINDOW_THEME_DEFAULT
	DeviceProfile.apply_all()
	await _frames(5)
	var win := DisplayServer.window_get_size()
	var logical := get_tree().root.get_visible_rect().size
	_tag = "%s_%s_%dx%d%s%s" % [_arg("view", "3d"), DeviceProfile.current(), win.x, win.y,
		"_claro" if GameConfig.ui_theme == "light" else "",
		("_" + _arg("tag")) if _arg("tag") != "" else ""]
	print("desborde_probe: ventana=%s lienzo=%s telefono=%s perfil=%s" % [win, logical,
		CartoonTheme.phone, DeviceProfile.current()])
	var scene := "res://scenes/main/Main2D.tscn" if _arg("view") == "2d" else "res://scenes/main/Main.tscn"

	# ── Colonia temprana ────────────────────────────────────────────────
	GameManager.title_dismissed = true
	get_tree().change_scene_to_file(scene)
	await _frames(60)
	_quiet()
	await _seconds(3.0)
	_quiet()
	var main := get_tree().current_scene
	await _shot("t_hud")
	var build: Node = main.get_node_or_null("ConstructionMenu")
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
	await _tutorial_shots(main)
	await _click_deposit("t_yacimiento")
	# Menu principal, Nueva partida, prologo y guia rapida.
	var title: Node = main.get_node_or_null("TitleMenu")
	if title:
		(title as CanvasLayer).visible = true
		title.open_menu()
		await _frames(15)
		await _shot("menu_principal")
		title.close_menu()
		await _frames(5)
	var dialog: CanvasLayer = GameManager.request_new_game()
	await _frames(15)
	await _shot("nueva_partida")
	if is_instance_valid(dialog):
		if dialog.has_method("cancel"):
			dialog.cancel()
		elif dialog.has_method("close"):
			dialog.close()
	await _frames(5)
	var tut: Node = main.get_node_or_null("TutorialPanel")
	if tut:
		(tut as CanvasLayer).visible = true
		# "De que va" (tutorial corto): antes del prologo en una partida nueva.
		var about: CanvasLayer = tut.about()
		if about:
			about.open()
			await _frames(15)
			await _shot("de_que_va")
			about.close(true)
			await _frames(5)
		var pro: CanvasLayer = tut.prologue()
		if pro and pro.has_method("open"):
			pro.open("full")
			await _frames(10)
			for i in range(pro.page_count()):
				pro.go_to_page(i)
				await _frames(10)
				await _shot("prologo_%d" % i)
			pro.close()
			await _frames(5)
		tut.open_quick_guide()
		await _frames(12)
		await _shot("guia_rapida")
		tut.quick_guide().close()
		await _frames(5)
		(tut as CanvasLayer).visible = false

	# ── Colonia grande ──────────────────────────────────────────────────
	var seeder: Node = ArteRunner.new()
	seeder._write_seeded_save()
	_add_military_lots(String(seeder.SAVE_PATH))
	_add_ficha_lots(String(seeder.SAVE_PATH))
	seeder.free()
	GameManager.clear_save_and_reload_from(SaveSlotsRef.read(GameManager.active_slot()), scene)
	await _frames(60)
	_quiet()
	await _seconds(5.0)
	_quiet()
	main = get_tree().current_scene
	ProgressionManager.current_era = 3
	ArmyManager._units = {"infantry": 6, "artillery": 3, "vehicle": 1}
	EventBus.army_changed.emit()
	ResourceManager.set_amounts({"gold": 2400, "wood": 900, "steel": 300, "oil": 120,
		"planks": 40, "beams": 12, "ingots": 10, "fuel": 10})
	_camera(Vector2(-6.0, -2.0), -1.0)
	await _seconds(1.5)
	await _shot("g_hud")

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
		for hub in ["progress", "contracts", "log"]:
			rank.open_hub_entry(hub)
			await _frames(12)
			await _shot("g_colonia_" + hub)
			UIManager.close_all_windows()
			await _frames(5)

	build = main.get_node_or_null("ConstructionMenu")
	ResourceManager.set_amounts({"gold": 120, "wood": 60, "steel": 10, "oil": 0})
	build._open()
	await _frames(12)
	await _shot("g_construir_pobre")
	for b in ["warehouse", "headquarters", "shipyard", "statue"]:
		build._select_building(load("res://data/buildings/%s.tres" % b))
		await _frames(10)
		await _shot("g_construir_" + b)
	build._close()
	await _frames(5)
	ResourceManager.set_amounts({"gold": 2400, "wood": 900, "steel": 300, "oil": 120,
		"planks": 40, "beams": 12, "ingots": 10, "fuel": 10})

	# Fichas de cada edificio del mapa (una por tipo), con su cola donde la hay.
	var seen := {}
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		if seen.has(data.id) or data.id == "road":
			continue
		seen[data.id] = true
		var node: Node = info["node"]
		match data.id:
			"barracks":
				ArmyManager.train("infantry")
			"shipyard":
				ArmyManager.train("torpedo_boat")
			"aerodrome":
				ArmyManager.train("fighter")
		if data.id in ["sawmill", "nucleo", "gold_mine", "foundry"]:
			var procs: Array = ProcessManager.get_processes_for(data.id)
			if not procs.is_empty():
				ProcessManager.enqueue_process(node, procs[0], 1)
				ProcessManager.enqueue_process(node, procs[0], 5)
		EventBus.building_clicked.emit(node, data)
		await _frames(15)
		await _shot("g_ficha_" + data.id)
		var panel: Node = main.get_node_or_null("BuildingInfoPanel")
		if panel and panel.get("_scroll") is ScrollContainer:
			(panel.get("_scroll") as ScrollContainer).scroll_vertical = 100000
			await _frames(5)
			await _shot("g_ficha_%s_abajo" % data.id)
		EventBus.building_deselected.emit()
		await _frames(5)
		ProcessManager.cancel(node)
	# Ficha danada.
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).id == "sawmill":
			BuildingHealth.damage_building(info["node"], int(BuildingHealth.get_max_health(info["node"]) * 0.5))
			EventBus.building_clicked.emit(info["node"], info["data"])
			await _frames(15)
			await _shot("g_ficha_danado")
			EventBus.building_deselected.emit()
			await _frames(5)
			break

	if rank and rank.has_method("open_editor"):
		rank.open_editor()
		await _frames(15)
		await _shot("g_pais_bandera")
		var ed: Node = rank.editor()
		if ed:
			for tab in ["colors", "emblems"]:
				ed.select_tab(tab)
				await _frames(10)
				await _shot("g_pais_bandera_" + tab)
			ed.cancel()
		await _frames(5)

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
				"smuggler": {"id": 5, "source": "smuggler", "template": "sm_oil",
					"ask": {"oil": 400, "gold": 250, "wood": 300}, "reward": {"steel": 200, "gold": 150},
					"seconds_total": 300.0, "seconds_left": 280.0},
			},
			"cooldowns": {"regency": 0.0, "neighbors": 0.0, "smuggler": 0.0},
			"reputation": {"regency": 0, "neighbors": 0, "smuggler": 0},
			"next_id": 6})
		contracts.open()
		await _frames(15)
		await _shot("g_encargos")
		UIManager.close_all_windows()
		await _frames(5)

	# EJERCITO por pestanas, ficha de unidad y regimiento.
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
		army.select_tab("land")
		await _frames(5)
		army.toggle_unit_card("artillery")
		await _frames(10)
		await _shot("g_ejercito_ficha")
		army.toggle_unit_card("artillery")
		await _frames(5)
		for card in army.find_children("*", "", true, false):
			if card.has_method("toggle_editor") and card.has_method("is_editor_open"):
				card.toggle_editor()
				await _frames(10)
				await _shot("g_regimiento")
				card.toggle_editor()
				break
		UIManager.close_all_windows()
		await _frames(5)

	# MISIONES: cada pestana con campana a medias.
	var skirmish: Node = main.get_node_or_null("SkirmishPanel")
	TutorialManager.first_sortie_done = true
	CombatManager._campaigns.progress = {"land": 3, "sea": 1, "air": 0}
	EventBus.campaign_changed.emit()
	if skirmish:
		skirmish.open()
		await _frames(10)
		for tab in ["land", "sea", "air", skirmish.TAB_RAIDS]:
			skirmish.select_tab(tab)
			await _frames(10)
			await _shot("g_misiones_%s" % tab)
		UIManager.close_all_windows()
		await _frames(5)

	# Mapa de mision, tablero, draft e informe.
	var battle: Node = main.get_node_or_null("BattleScreen")
	if battle and CombatManager.launch_expedition({"infantry": 3, "artillery": 1}, 4242):
		await _seconds(3.0)
		await _shot("g_tablero")
		battle.open_map()
		await _frames(15)
		await _shot("g_mapa_mision")
		var run = CombatManager._expedition
		if run != null:
			var opts: Array = ExpeditionGenerator.draft_options(ExpeditionGenerator.make_rng(7), run.party)
			if not opts.is_empty():
				battle._pending_draft = opts
				battle._open_draft()
				await _frames(12)
				await _shot("g_draft")
				battle._close_draft()
				await _frames(5)
		CombatManager.abandon_expedition()
		await _seconds(1.0)
		battle._show_expedition_report(0, {"gold": 320, "steel": 60, "oil": 25, "wood": 140},
			{"infantry": 2, "artillery": 1})
		await _frames(12)
		await _shot("g_informe")
		battle.visible = false
		var reports0: Node = main.get_node_or_null("WarReportScreen")
		if reports0:
			while reports0.is_showing():
				reports0.close_current()
				await _frames(3)
			reports0.visible = false
	if skirmish:
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
		reports.visible = false
		EventBus.defense_auto_resolved.emit(false, 6, {"casualties": {"infantry": 2, "artillery": 1, "vehicle": 1},
			"enemy_casualties": {"infantry": 3, "artillery": 1, "vehicle": 2}, "tower_crews": 2,
			"tower_crews_lost": 1, "morale_delta": -4})
		reports.try_show_next()
		await _frames(15)
		await _shot("g_parte_defensa")
		reports.close_current()
		await _frames(5)
		EventBus.tithe_resolved.emit(true, {"gold": 300, "wood": 120, "steel": 80, "oil": 40})
		await _frames(3)
		reports.try_show_next()
		await _frames(15)
		await _shot("g_parte_impuesto")
		while reports.is_showing():
			reports.close_current()
			await _frames(3)

	# La Orden de la Regencia (tarjeta del barometro).
	if StormManager.order_visible():
		EventBus.storm_order_changed.emit(true)
		await _frames(15)
		await _shot("g_orden_regencia")
	else:
		print("desborde_probe: sin Orden de la Regencia visible (tormenta no armada)")

	# Ajustes: las pestanas y Mas opciones.
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

	# AYUDA: el indice y cada pagina; la guia de edificios; los consejos.
	for help in get_tree().get_nodes_in_group("help_index"):
		help.open()
		await _frames(12)
		await _shot("g_ayuda")
		for id in help.listed_ids():
			help.show_page(String(id))
			await _frames(6)
			await _look("g_ayuda_" + String(id), false)
		help.close()
		await _frames(5)
		break
	var helper: Node = main.get_node_or_null("HelperPanel")
	if helper:
		(helper as CanvasLayer).visible = true
		helper.open_building_guide()
		await _frames(12)
		await _shot("g_guia_edificios")
		UIManager.close_all_windows()
		await _frames(5)
		for id in HelpCatalogRef.ENTRIES.keys():
			helper.show_help(String(id))
			await _frames(6)
			await _look("g_consejo_" + String(id), false)
			if helper.has_method("skip_gap"):
				helper.skip_gap()
		(helper as CanvasLayer).visible = false

	var saves: CanvasLayer = GameManager.open_saves_list()
	await _frames(15)
	await _shot("g_partidas")
	if is_instance_valid(saves):
		saves.close()
	await _frames(5)
	EventBus.final_audit_lost.emit(2)
	await _frames(15)
	await _shot("g_derrota_asedio")
	var defeat: Node = main.get_node_or_null("AuditDefeatScreen")
	if defeat and defeat.has_method("close"):
		defeat.close()
	await _frames(5)
	EventBus.victory_achieved.emit({"time_played": 5400.0, "buildings_built": 64,
		"trades_completed": 12, "milestones": 9, "storms_survived": 7,
		"tithes_repelled": 3, "audit_summons": 1, "mode": "campaign"})
	await _frames(20)
	await _shot("g_victoria")
	await _v12_shots(main)
	print("desborde_probe: RESUMEN %d desbordes en %d pantallas %s" % [_hits_total,
		_screens_hit.size(), _screens_hit])
	_finish()

## Las pantallas de la 1.2 (como tools/v12_probe_runner.gd): amenaza de costa,
## ATAQUES RAPIDOS con amenazas, el barco del contrabandista y el final con
## eleccion (victoria, EL LIBRO, QUEMAR, FIRMAR, el archipielago, IMPERIO).
func _v12_shots(main: Node) -> void:
	var victory: Node = main.get_node_or_null("VictoryScreen")
	if victory and victory.has_method("dismiss"):
		victory.dismiss()
	await _frames(5)
	var spots: Dictionary = ThreatManager.free_spots()
	var land: Array = spots.get("land", [])
	if land.size() > 2:
		var a: Vector2i = land[0]
		var b: Vector2i = land[land.size() / 2]
		var threats := [
			{"id": 1, "type": "vanguard", "x": a.x, "y": a.y, "water": false, "seed": 5, "era": 3,
				"born": 0.0, "ends": 99999.0, "state": "idle", "explore_ends": 0.0, "seen": false},
			{"id": 2, "type": "wreck", "x": b.x, "y": b.y, "water": false, "seed": 6, "era": 3,
				"born": 0.0, "ends": 99999.0, "state": "idle", "explore_ends": 0.0, "seen": false},
		]
		ThreatManager.load_save_data({"threats": threats, "next_spawn_at": 99999.0, "next_id": 3})
		await _frames(10)
		EventBus.threat_clicked.emit(1)
		await _frames(15)
		await _shot("v12_amenaza_tarjeta")
		var card := main.find_child("ThreatCard", true, false)
		if card and card.has_method("close"):
			card.close()
		await _frames(5)
	var skirmish: Node = main.get_node_or_null("SkirmishPanel")
	if skirmish and land.size() > 2:
		skirmish.open_threat(1)
		await _frames(15)
		await _shot("v12_misiones_amenazas")
		skirmish._close()
		await _frames(5)
	var offers := [
		{"kind": "parts", "give": {"parts": 3}, "price": 180, "sold": false},
		{"kind": "material", "give": {"beams": 6}, "price": 312, "sold": false},
		{"kind": "buy", "ask": {"wood": 60}, "pay": 230, "sold": false},
	]
	EconomyManager.load_save_data({"ship": {"wait_left": 300.0, "docked_left": 80.0, "offers": offers, "visits": 1}})
	var smuggler = load("res://scripts/ui/SmugglerPanel.gd").open_in(get_tree())
	await _frames(15)
	await _shot("v12_barco")
	if smuggler:
		smuggler.close()
	await _frames(5)
	if victory == null:
		return
	EmpireManager.reset()
	var audit = FinalAuditScript.create(5, {"infantry": 3}, 3, 70.0)
	audit.state = FinalAudit.State.WON
	ProgressionManager.final_audit = audit
	victory._on_victory_achieved({"time_played": 11100.0, "buildings_built": 64, "trades_completed": 12,
		"milestones": 9, "storms_survived": 11, "tithes_repelled": 9, "audit_summons": 1, "mode": "campaign"})
	await _frames(20)
	await _shot("v12_final_victoria")
	victory.show_choice()
	await _frames(20)
	await _shot("v12_final_el_libro")
	victory.choose("burn")
	await _frames(20)
	await _shot("v12_final_quemar")
	victory.dismiss()
	await _frames(5)
	EmpireManager.reset()
	victory.show_choice()
	await _frames(10)
	victory.choose("sign")
	await _frames(20)
	await _shot("v12_final_firmar")
	victory.open_archipelago()
	await _frames(25)
	await _shot("v12_archipielago")
	var arch := main.get_node_or_null("ArchipelagoPanel")
	if arch and arch.has_method("close"):
		arch.close()
	await _frames(5)
	if skirmish:
		skirmish.open_conquest("gulls")
		await _frames(15)
		await _shot("v12_misiones_imperio")
		skirmish._close()
		await _frames(5)

## Tutorial: tarjeta de un paso need_* (sin oro ni madera) y el recordatorio.
func _tutorial_shots(main: Node) -> void:
	var tut: CanvasLayer = main.get_node_or_null("TutorialPanel")
	if tut == null:
		return
	var saved_res := {"gold": ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"wood": ResourceManager.get_amount(ResourceManager.Type.WOOD)}
	tut.visible = true
	TutorialManager.intro_seen = true
	TutorialManager.start_guide(false)
	await _frames(5)
	await _shot("t_tutorial_meta")
	for s in ["goal", "core"]:
		if TutorialManager.current_step() == s:
			TutorialManager.confirm_step(s)
			await _frames(5)
	await _seconds(1.0)
	await _shot("t_tutorial_" + TutorialManager.current_step())
	ResourceManager.set_amounts({"gold": 10, "wood": 5})
	await _seconds(1.5)
	await _shot("t_tutorial_" + TutorialManager.current_step())
	await _seconds(4.5)
	await _shot("t_tutorial_recordatorio")
	TutorialManager.finish_guide()
	await _frames(5)
	tut.visible = false
	ResourceManager.set_amounts(saved_res)

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

## Escala de interfaz que da el lienzo de --canvas en el perfil telefono (que
## sigue a los dp de la pantalla de quien corre la sonda).
func _scale_for_canvas() -> int:
	if _canvas == Vector2.ZERO:
		return 0
	var win := Vector2(DisplayServer.window_get_size())
	var density := float(DisplayServer.screen_get_dpi()) / 160.0
	if density <= 0.0:
		density = 1.0
	var k := (win.x / density / _canvas.x) if win.y > win.x else (win.y / density / _canvas.y)
	return maxi(1, roundi(k * 100.0))

## Mira desbordes en lo que hay en pantalla; captura si hay o con --shots.
func _shot(shot_name: String) -> void:
	await _look(shot_name, true)

func _look(shot_name: String, picture: bool) -> void:
	var only := _arg("only")
	if only != "":
		var keep := false
		for p in only.split(","):
			if shot_name.begins_with(p):
				keep = true
		if not keep:
			return
	await RenderingServer.frame_post_draw
	var hits: Array = Scan.scan(get_tree().root)
	print("desborde_probe: [%s] %d controles, %d desbordes" % [shot_name, Scan.last_checked, hits.size()])
	for line in Scan.report(hits):
		print("desborde_probe: [%s] %s" % [shot_name, line])
	if not hits.is_empty():
		_hits_total += hits.size()
		_screens_hit.append(shot_name)
	if (picture and _arg("shots") != "") or not hits.is_empty():
		var img := get_tree().root.get_texture().get_image()
		var path := "%s/%s_%s.png" % [OUT, _tag, shot_name]
		img.save_png(ProjectSettings.globalize_path(path))
		print("desborde_probe: ", ProjectSettings.globalize_path(path))
