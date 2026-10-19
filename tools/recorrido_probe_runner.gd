extends Node
## Sonda del recorrido de una partida nueva, de principio a fin, como lo ve un
## jugador: menu principal, Nueva partida (modo), pais y bandera, prologo, guia
## rapida, los 13 pasos del tutorial guiado JUGADOS (abre CONSTRUIR, elige la
## tarjeta, coloca en un sitio valido, gira, mueve, derriba...) y, al acabar, la
## leccion de reparar con un edificio danado. Saca una captura antes de cada
## accion, con el numero de orden y el paso del tutorial en el nombre.
##
## Argumentos tras `--`: --shot-size=WxH, --view=2d, --profile=pc|tablet|phone,
## --tag=nombre. Capturas en docs/media/dev/recorrido/ (ignorada por git).
## Aparca guardado y ajustes y los devuelve al terminar.

const SaveParking := preload("res://tests/save/save_parking.gd")
const SettingsParking := preload("res://tests/save/settings_parking.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const BACKUP_PATH := "user://save_game.recorrido_probe.bak"
const OUT_DIR := "res://docs/media/dev/recorrido"

var _tag := ""
var _settings_snap: Dictionary
var _args: PackedStringArray
var _n := 0
var _road_node: Node = null
## Ya se enseno el paso "consigue lo que falta" (una vez por recorrido).
var _need_shown := false
var _need_planks_shown := false

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
	_settings_snap = SettingsParking.park()
	GameConfig.dev_mode = true
	GameConfig.ui_view_mode = "2d" if _arg("view") == "2d" else "3d"
	GameConfig.ui_device_profile = _arg("profile", "auto")
	GameConfig.ui_scale_pct = 0
	GameConfig.ui_text_size = "auto"
	GameConfig.ui_hud_hidden = []
	GameConfig.ui_layout = {}
	GameConfig.ui_helper_visible = true
	GameConfig.ui_touch_controls = "auto"
	if _arg("quality") != "":
		GameConfig.ui_graphics_quality = _arg("quality")
		EventBus.graphics_quality_changed.emit(GameConfig.ui_graphics_quality)
	DeviceProfile.apply_all()
	await _frames(5)
	var win := DisplayServer.window_get_size()
	_tag = "%s_%s_%dx%d%s" % [_arg("view", "3d"), DeviceProfile.current(), win.x, win.y,
		("_" + _arg("tag")) if _arg("tag") != "" else ""]
	print("recorrido_probe: window=", win, " canvas=", get_tree().root.get_visible_rect().size)

	# ── Menu principal ──
	GameManager.title_dismissed = false
	var scene := "res://scenes/main/Main2D.tscn" if _arg("view") == "2d" else "res://scenes/main/Main.tscn"
	get_tree().change_scene_to_file(scene)
	await _frames(60)
	await _shot("menu_principal")

	# ── Nueva partida: modo, pais y bandera ──
	var dialog: CanvasLayer = GameManager.request_new_game()
	await _frames(20)
	await _shot("nueva_modo")
	if dialog != null and dialog.has_method("_on_start"):
		dialog.call("_on_start")
		await _frames(20)
		await _shot("nueva_pais")
		var ident: Node = dialog.get("_identity")
		if ident != null:
			for tab in ["emblems", "colors"]:
				if ident.has_method("select_tab"):
					ident.call("select_tab", tab)
					await _frames(10)
					await _shot("nueva_pais_" + tab)
			ident.call("confirm")
	await _frames(90)

	# La tormenta de prueba no sale sola a mitad del recorrido (el reloj corre en
	# dev a x5): se lanza a mano al final, en _extras().
	StormManager.set("_trial_done", true)

	# ── Prologo y guia rapida ──
	var main := get_tree().current_scene
	var tut: Node = main.get_node("TutorialPanel")
	var pro: Node = tut.call("prologue")
	print("recorrido_probe: prologo abierto=", pro.call("is_open"))
	if pro.call("is_open"):
		await _frames(60)
		pro.call("_finish_typing")
		await _frames(5)
		await _shot("prologo_1")
		for i in range(1, int(pro.call("page_count"))):
			pro.call("go_to_page", i)
			await _frames(20)
			pro.call("_finish_typing")
			await _frames(5)
			await _shot("prologo_%d" % (i + 1))
		pro.call("close")
		await _frames(30)
	var qg: Node = get_tree().get_first_node_in_group("quick_guide")
	if qg != null and qg.call("is_open"):
		await _shot("guia_rapida")
		qg.call("close")
		await _frames(20)

	# ── Solo el recordatorio plegado del tutorial (--recordatorio, feat/ui3-tutorial) ──
	if _arg("recordatorio") == "true":
		await _reminder_tour(main)
		_finish()
		return

	# ── Solo ¿QUE HACER? paso a paso (--objetivo, 2026-10-19) ──
	if _arg("objetivo") == "true":
		await _objective_tour(main)
		_finish()
		return

	# ── Tutorial guiado, jugado ──
	await _play_guide(main)

	# ── Leccion de reparar ──
	await _seconds(1.0)
	var victim: Node = _first("sawmill")
	if victim != null:
		BuildingHealth.damage_building(victim, int(BuildingHealth.get_max_health(victim) * 0.5))
		await _seconds(1.5)
		print("recorrido_probe: leccion=", TutorialManager.get("_extra_step"))
		await _shot("reparar_leccion")
		EventBus.building_clicked.emit(victim, _data_of(victim))
		await _frames(20)
		await _shot("reparar_ficha")
		# Se repara, como pide la leccion: si no, su tarjeta tapa lo que sigue.
		_top_up()
		print("recorrido_probe: reparado=", BuildingHealth.repair(victim))
		await _seconds(1.0)
		EventBus.building_deselected.emit()
		await _frames(5)
		print("recorrido_probe: leccion tras reparar=", TutorialManager.get("_extra_step"))
	# ── La 1.0: topes, mejoras, AYUDA, tormenta de prueba con su Impuesto ──
	await _extras(main)
	_finish()

## Lo nuevo de la 1.0 (ronda de pruebas 2026-10-17): la tarjeta "Al maximo" con
## MEJORAR UNO, la ficha "Nivel N de 3", las paginas nuevas de AYUDA, y la
## tormenta de prueba con su Impuesto de juguete (peleado con un soldado en casa,
## con el combate guiado, y pagado sin tropas).
func _extras(main: Node) -> void:
	var cm: Node = main.get_node("ConstructionMenu")
	_top_up()
	# Tope lleno: la Granja a 1 (la del tutorial) con un rango de mentira.
	var saved_bonus: Dictionary = GameConfig.rank_limit_bonus.duplicate()
	GameConfig.rank_limit_bonus["farm"] = 1 - GameConfig.base_building_limit("farm", 1)
	cm.call("_open")
	await _frames(15)
	cm.call("_select_building", Rules.load_building_data("farm"))
	await _frames(15)
	await _shot("tope_al_maximo")
	var up: Button = cm.find_child("DetailUpgradeOne", true, false) as Button
	print("recorrido_probe: MEJORAR UNO visible=", up != null and up.visible)
	if up != null and up.visible:
		up.pressed.emit()
		await _frames(30)
		await _shot("tope_mejorar_uno_ficha")
	else:
		cm.call("_close")
	EventBus.building_deselected.emit()
	await _frames(5)
	GameConfig.rank_limit_bonus = saved_bonus
	# Ficha "Nivel 2 de 3".
	var saw := _first("sawmill")
	if saw != null:
		saw.set_meta("level", 2)
		EventBus.building_clicked.emit(saw, _data_of(saw))
		await _frames(20)
		await _shot("ficha_nivel_2_de_3")
		EventBus.building_deselected.emit()
		await _frames(5)
	var bar := _first("barracks")
	if bar != null:
		EventBus.building_clicked.emit(bar, _data_of(bar))
		await _frames(20)
		await _shot("ficha_cuartel_sin_mejoras")
		EventBus.building_deselected.emit()
		await _frames(5)
	# AYUDA: las paginas nuevas.
	var idx: Node = get_tree().get_first_node_in_group("help_index")
	if idx != null:
		idx.call("open")
		await _frames(20)
		await _shot("ayuda_indice")
		for id in ["guide_limits", "guide_upgrades", "guide_eras", "guide_workshop", "guide_towers"]:
			idx.call("show_page", id)
			await _frames(15)
			await _shot("ayuda_" + id)
		idx.call("close")
		await _frames(10)
	# Tormenta de prueba con un soldado en casa: Impuesto de juguete peleado.
	ArmyManager.load_save_data({"units": {"infantry": 1}, "training": [], "upkeep_accum": 0.0})
	var trial_ok: bool = StormManager.start_trial()
	if not trial_ok and StormManager.get("_trial") == null:
		# Ya paso sola durante el tutorial (el reloj de partida corre): otra vez.
		StormManager.set("_trial_done", false)
		trial_ok = StormManager.start_trial()
	# O esta pasando ahora mismo (empezo sola mientras se miraba lo demas).
	trial_ok = trial_ok or StormManager.get("_trial") != null
	print("recorrido_probe: tormenta de prueba=", trial_ok)
	if trial_ok:
		var guard := 0
		var last_phase := -1
		while StormManager.get("_trial") != null and guard < 400:
			guard += 1
			StormManager._publish_trial(StormManager.get("_trial").advance(2.0))
			var ph: int = int(StormManager.get("_trial").phase) if StormManager.get("_trial") != null else -1
			if ph != last_phase:
				last_phase = ph
				await _frames(20)
				await _shot("prueba_fase_%d" % ph)
			if StormManager.is_trial_tithe_pending():
				break
		await _frames(30)
		print("recorrido_probe: impuesto pendiente=", StormManager.is_trial_tithe_pending(),
			" tablero=", CombatManager.is_board_open())
		await _shot("prueba_impuesto_tablero")
		await _seconds(1.5)
		await _shot("prueba_combate_guiado")
		if CombatManager.is_board_open():
			# La sonda no juega el tablero: lo resuelve la IA (con el listón de
			# "resolver solo" bajado solo para esto) y cierra el parte como el boton.
			var ratio: float = GameConfig.combat_auto_resolve_ratio
			GameConfig.combat_auto_resolve_ratio = 0.0
			print("recorrido_probe: resolver solo=", CombatManager.auto_resolve_current())
			GameConfig.combat_auto_resolve_ratio = ratio
			await _seconds(4.0)
			await _shot("prueba_impuesto_final_tablero")
			var bs: Node = main.get_node_or_null("BattleScreen")
			if bs != null and bs.has_method("_close_board"):
				bs.call("_close_board")
			else:
				CombatManager.end_encounter()
			await _frames(30)
		await _shot("prueba_impuesto_parte")
		var wr: Node = main.get_node_or_null("WarReportScreen")
		if wr != null and wr.has_method("close_current"):
			wr.call("close_current")
			await _frames(15)
	# Sin tropas: se llevan un poco de la bolsa.
	ArmyManager.load_save_data({"units": {}, "training": [], "upkeep_accum": 0.0})
	StormManager.begin_trial_tithe()
	await _frames(30)
	await _shot("prueba_impuesto_pagado_parte")
	var wr2: Node = main.get_node_or_null("WarReportScreen")
	if wr2 != null and wr2.has_method("close_current"):
		wr2.call("close_current")
		await _frames(10)

## ¿QUE HACER? paso a paso (feat/objetivo-paso-a-paso): la linea del HUD y el
## panel con el objetivo y sus pasos, sin recoger nada a mano. Dos momentos: el
## oro que espera en la Mina (el paso es recogerlo) y los tablones del Cuartel
## (6 de 10). Tambien la tarjeta del tutorial "consigue lo que falta".
func _objective_tour(main: Node) -> void:
	var cm: Node = main.get_node("ConstructionMenu")
	var placer: Node = main.get_node("BuildingPlacer")
	var obj: Node = main.get_node("ObjectivePanel")
	# Sin globos de ayuda encima: las capturas son del objetivo.
	GameConfig.ui_helper_visible = false
	EventBus.helper_visibility_changed.emit(false)
	# La tarjeta del tutorial con oro sin recoger: el paso es recogerlo.
	await _frames(20)
	_top_up()
	for id in ["sawmill", "gold_mine"]:
		cm.call("_open")
		cm.call("_select_building", Rules.load_building_data(id))
		cm.call("_on_build_pressed")
		var spot := _free_spot(id, null)
		placer.call("assist_center_on", spot)
		placer.call("assist_move_ghost", spot)
		await _frames(10)
		placer.call("assist_confirm", spot)
		await _frames(10)
		_complete_all()
		_top_up()
	EventBus.building_placement_cancelled.emit()
	var mine := _first("gold_mine")
	ResourceManager.set_amounts({"gold": 10, "wood": 220, "food": 40, "planks": 0})
	ProductionManager._add_to_stock(mine, {"gold": 45})
	# El tutorial ya enseno a recoger: lo siguiente es el Cuartel, sin oro.
	for fact in ["goal_seen", "core_seen", "collected"]:
		TutorialManager.note_guide_fact(fact)
	await _seconds(1.5)
	print("recorrido_probe: tutorial paso=", TutorialManager.current_step(), " texto=", TutorialManager.step_text(TutorialManager.current_step()))
	await _shot("objetivo_tutorial_recoger")
	# Sin tutorial: la linea del HUD y el panel.
	TutorialManager.skip_guide()
	await _frames(10)
	obj.call("refresh_line")
	await _frames(5)
	print("recorrido_probe: linea=", obj.call("line_text"))
	await _shot("objetivo_linea_recoger")
	obj.call("toggle")
	await _frames(15)
	print("recorrido_probe: panel=", obj.call("get_now_text"))
	await _shot("objetivo_panel_recoger")
	obj.call("toggle")
	await _frames(5)
	# Tablones: 6 de 10, con el oro ya recogido.
	ProductionManager.collect(mine)
	ResourceManager.set_amounts({"gold": 400, "wood": 220, "food": 40, "planks": 6})
	await _frames(10)
	obj.call("refresh_line")
	await _frames(5)
	print("recorrido_probe: linea=", obj.call("line_text"))
	await _shot("objetivo_linea_tablones")
	obj.call("toggle")
	await _frames(15)
	print("recorrido_probe: panel=", obj.call("get_now_text"))
	await _shot("objetivo_panel_tablones")
	obj.call("toggle")
	await _frames(5)

## El recordatorio plegado (feat/ui3-tutorial): un paso de espera sale como
## tarjeta, se pliega a los 4 s, se resalta a los 90 s sin avance, se reabre al
## tocarlo y, al tenerlo todo, la tarjeta del paso de accion sale UNA vez con su
## flecha ("¡Ya puedes!"). Sin recoger a mano: la espera es de verdad.
func _reminder_tour(main: Node) -> void:
	var cm: Node = main.get_node("ConstructionMenu")
	var placer: Node = main.get_node("BuildingPlacer")
	var tut: Node = main.get_node("TutorialPanel")
	GameConfig.ui_helper_visible = false
	EventBus.helper_visibility_changed.emit(false)
	await _frames(20)
	for fact in ["goal_seen", "core_seen"]:
		TutorialManager.note_guide_fact(fact)
	# 1. Sin oro ni madera: need_sawmill.
	ResourceManager.set_amounts({"gold": 0, "wood": 0})
	await _seconds(1.5)
	_log_reminder(tut, "need 1s")
	await _shot("rec_need_tarjeta")
	await _seconds(4.0)
	_log_reminder(tut, "need 5s")
	await _shot("rec_need_chip")
	tut.set("_chip_idle", 999.0)
	await _frames(5)
	_log_reminder(tut, "need 90s")
	await _shot("rec_need_chip_resaltado")
	(tut.call("reminder") as Button).pressed.emit()
	await _frames(10)
	_log_reminder(tut, "need reabierta")
	await _shot("rec_need_reabierta")
	await _seconds(FOLD_WAIT)
	_log_reminder(tut, "need replegada")
	# 2. Ya lo tiene: la tarjeta de CONSTRUIR, una vez, con su flecha.
	ResourceManager.set_amounts({"gold": 320, "wood": 220})
	await _seconds(1.5)
	_log_reminder(tut, "ya puedes")
	await _shot("rec_ya_puedes_tarjeta")
	var later: Button = tut.find_child("GuideLater", true, false)
	if later != null and later.visible:
		later.pressed.emit()
		await _frames(10)
		_log_reminder(tut, "ya puedes plegada")
		await _shot("rec_ya_puedes_chip")
	# 3. Se vuelve a quedar sin nada: el paso de espera ya visto sale plegado.
	ResourceManager.set_amounts({"gold": 0, "wood": 0})
	await _seconds(1.5)
	_log_reminder(tut, "otra vez sin nada")
	await _shot("rec_need_otra_vez")
	ResourceManager.set_amounts({"gold": 320, "wood": 220})
	await _seconds(1.5)
	_log_reminder(tut, "otra vez ya puedes")
	await _shot("rec_ya_puedes_otra_vez")
	# 4. El Aserradero: su obra es un paso de espera; recoger espera la madera.
	cm.call("_open")
	await _frames(10)
	cm.call("_select_building", Rules.load_building_data("sawmill"))
	await _frames(5)
	cm.call("_on_build_pressed")
	var spot := _free_spot("sawmill", null)
	placer.call("assist_center_on", spot)
	placer.call("assist_move_ghost", spot)
	await _frames(10)
	placer.call("assist_confirm", spot)
	await _frames(5)
	# Una obra larga (en dev dura un suspiro): que se vea el recordatorio de obra.
	var site := _first("sawmill")
	if site != null and ProductionManager._constructing.has(site):
		ProductionManager._constructing[site]["duration"] = 60.0
		ProductionManager._constructing[site]["remaining"] = 40.0
	await _seconds(1.0)
	_log_reminder(tut, "obra 1s")
	await _shot("rec_obra_tarjeta")
	await _seconds(FOLD_WAIT)
	_log_reminder(tut, "obra plegada")
	await _shot("rec_obra_chip")
	_complete_all()
	var saw := _first("sawmill")
	# Recien acabada, sin madera aun: recoger espera. En dev corta en 2 s: se
	# para un momento (trabajadores fuera) para ver la espera.
	PopulationManager.set_workers_off(saw, true)
	await _seconds(1.0)
	_log_reminder(tut, "recoger 1s")
	await _shot("rec_recoger_tarjeta")
	await _seconds(FOLD_WAIT)
	_log_reminder(tut, "recoger plegada")
	await _shot("rec_recoger_chip")
	PopulationManager.set_workers_off(saw, false)
	# Espera de verdad a que el Aserradero corte madera (dev x5), sin tocar nada.
	for i in 60:
		if int(ProductionManager.get_stock(saw).get("wood", 0)) > 0:
			break
		await _seconds(0.5)
	await _seconds(1.0)
	_log_reminder(tut, "recoger ya puedes")
	await _shot("rec_recoger_ya_puedes")
	ProductionManager.collect(saw)
	await _seconds(1.5)
	# 5. El Cuartel sin tablones.
	ResourceManager.set_amounts({"planks": 0, "gold": 320, "wood": 220})
	await _seconds(1.5)
	_log_reminder(tut, "cuartel 1s")
	await _shot("rec_cuartel_tarjeta")
	await _seconds(FOLD_WAIT)
	_log_reminder(tut, "cuartel plegada")
	await _shot("rec_cuartel_chip")
	# Con CONSTRUIR abierto encima, el chip no estorba (ni se ve sobre la lista).
	cm.call("_open")
	await _frames(15)
	await _shot("rec_cuartel_chip_construir")
	cm.call("_close")
	await _frames(10)

const FOLD_WAIT := 5.0

func _log_reminder(tut: Node, what: String) -> void:
	var chip: Control = tut.call("reminder")
	print("recorrido_probe: [rec] ", what, " paso=", TutorialManager.current_step(), " plegada=", tut.call("is_folded"),
		" chip=", chip.visible, " '", tut.call("reminder_text"), "' rect=", chip.get_global_rect(),
		" tarjeta=", (tut.find_child("CoachCard", true, false) as Control).visible,
		" flecha=", (tut.find_child("Arrow", true, false) as Control).visible)

## Juega el tutorial hasta "done" (o 70 vueltas), una captura antes de cada accion.
func _play_guide(main: Node) -> void:
	var cm: Node = main.get_node("ConstructionMenu")
	var placer: Node = main.get_node("BuildingPlacer")
	var info: Node = main.get_node("BuildingInfoPanel")
	var last := ""
	var same := 0
	for i in 70:
		await _frames(15)
		var step: String = TutorialManager.current_step()
		print("recorrido_probe: vuelta ", i, " paso=", step)
		if step == last:
			same += 1
			if same > 3:
				print("recorrido_probe: ATASCADO en ", step)
				await _shot("atascado_" + step)
				return
		else:
			same = 0
		last = step
		_top_up()
		await _shot("tut_" + step)
		match step:
			"", "done":
				TutorialManager.finish_guide()
				return
			"goal", "core":
				TutorialManager.confirm_step(step)
			"wait_sawmill", "wait_barracks":
				await _seconds(1.0)
				_complete_all()
			"collect":
				var saw := _first("sawmill")
				ProductionManager._add_to_stock(saw, {"wood": 6})
				await _frames(20)
				await _shot("tut_collect_lleno")
				ProductionManager.collect(saw)
			"rotate_now":
				EventBus.building_rotate_requested.emit()
				await _frames(15)
				await _shot("tut_rotate_girado")
			"move":
				var house := _first("house")
				EventBus.building_clicked.emit(house, _data_of(house))
				await _frames(20)
				await _shot("tut_move_ficha")
				info.call("_on_move")
			"move_place":
				var house := _first("house")
				var spot := _free_spot("house", house)
				placer.call("assist_center_on", spot)
				placer.call("assist_move_ghost", spot)
				await _frames(20)
				await _shot("tut_move_place_fantasma")
				placer.call("assist_confirm", spot)
			"road_place":
				var cell := _road_cell()
				placer.call("assist_move_ghost", cell)
				await _frames(15)
				await _shot("tut_road_place_fantasma")
				placer.call("assist_confirm", cell)
				await _frames(5)
				EventBus.building_placement_cancelled.emit()
				_road_node = GridManager.get_building_at(cell)
			"demolish":
				var road := _road_node
				if road == null or not is_instance_valid(road):
					road = _practice_road()
				if road != null:
					EventBus.building_clicked.emit(road, _data_of(road))
					await _frames(20)
					await _shot("tut_demolish_ficha")
					info.call("_on_demolish")
					await _frames(10)
					await _shot("tut_demolish_confirmar")
					info.call("_confirm_demolish")
			_:
				# Una vez, sin oro ni madera ante la Mina: el paso "consigue lo que
				# falta" (docs/23 §2.7) tiene que salir y volver solo al rellenar.
				# Y el de los tablones del Cuartel (need_barracks): sin tablones.
				if step == "open_barracks" and not _need_planks_shown:
					_need_planks_shown = true
					ResourceManager.set_amounts({"planks": 0})
					await _seconds(1.5)
					print("recorrido_probe: sin tablones paso=", TutorialManager.current_step())
					await _shot("tut_need_barracks_tablones")
					_top_up()
					await _seconds(1.5)
					continue
				if step == "open_gold_mine" and not _need_shown:
					_need_shown = true
					ResourceManager.set_amounts({"gold": 0, "wood": 0, "food": 40})
					await _seconds(1.5)
					print("recorrido_probe: sin recursos paso=", TutorialManager.current_step())
					await _shot("tut_need_sin_recursos")
					_top_up()
					await _seconds(1.5)
					print("recorrido_probe: rellenado paso=", TutorialManager.current_step())
					continue
				if step.begins_with("need_"):
					# Sin trabajadores (el Laboratorio tras el Cuartel temprano: 1 libre
					# de 2) el paso dice "Haz otra Casa": se hace, como el jugador.
					var need_data: BuildingData = Rules.load_building_data(TutorialManager.step_building(step))
					if TutorialManager.workers_short(need_data) > 0:
						await _shot("tut_" + step + "_trabajadores")
						cm.call("_open")
						cm.call("_select_building", Rules.load_building_data("house"))
						cm.call("_on_build_pressed")
						var hspot := _free_spot("house", null)
						placer.call("assist_move_ghost", hspot)
						await _frames(10)
						placer.call("assist_confirm", hspot)
						await _seconds(0.5)
						_complete_all()
						# Y la gente que llega a la Casa nueva (en partida, un ciclo).
						PopulationManager._population += 4
						PopulationManager._recalculate_all()
						await _seconds(1.2)
						continue
					# _top_up() ya lo relleno: en un segundo vuelve al paso de construir.
					await _seconds(1.2)
				elif step.begins_with("open_") or step in ["rotate", "road_open"]:
					cm.call("_open")
				elif step.begins_with("pick_") or step in ["rotate_pick", "road_pick"]:
					var id: String = TutorialManager.step_building(step)
					cm.call("_select_building", Rules.load_building_data(id))
					await _frames(10)
					await _shot("tut_" + step + "_ficha")
					cm.call("_on_build_pressed")
				elif step.begins_with("place_"):
					var id: String = TutorialManager.step_building(step)
					var spot := _free_spot(id, null)
					placer.call("assist_center_on", spot)
					placer.call("assist_move_ghost", spot)
					await _frames(20)
					await _shot("tut_" + step + "_fantasma")
					placer.call("assist_confirm", spot)
					await _frames(10)
					if id != "sawmill":
						await _seconds(0.5)
						_complete_all()
				else:
					print("recorrido_probe: paso sin accion ", step)
	print("recorrido_probe: fin de vueltas")

## Recursos y obreros de sobra para que el tutorial no se pare por coste.
func _top_up() -> void:
	# Los tablones del Cuartel (cuartel temprano, 2026-10-17) tambien.
	ResourceManager.set_amounts({"gold": 320, "wood": 220, "food": 40, "planks": 20})
	if PopulationManager.get_free_workers() < 4:
		PopulationManager._population += 4
		PopulationManager._max_population = maxi(PopulationManager._max_population, PopulationManager._population)
		PopulationManager._recalculate_all()

func _complete_all() -> void:
	for info in GridManager.get_all_buildings():
		var node: Node = info["node"]
		if ProductionManager.is_constructing(node):
			ProductionManager._complete_construction(node)

func _first(id: String) -> Node:
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).id == id:
			return info["node"]
	return null

func _data_of(node: Node) -> BuildingData:
	return GridManager.get_building_info(node).get("data") as BuildingData

func _map() -> Node:
	return get_tree().current_scene.get_node_or_null("MapGenerator")

## Un sitio valido para `id`: junto a su yacimiento si lo pide, si no lo mas
## cerca del Nucleo sin pisar la orla de los yacimientos.
func _free_spot(id: String, ignore: Node) -> Vector2i:
	var data: BuildingData = Rules.load_building_data(id)
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	var map := _map()
	var rule: Dictionary = GameConfig.get_deposit_rule(id)
	if not rule.is_empty():
		var spots: Array = map.buildable_spots_near(String(rule["deposit"]), data.grid_size, int(rule["reach"]), 0)
		spots.sort_custom(func(a, b): return _dist(a["origin"], center) < _dist(b["origin"], center))
		for s in spots:
			if (s["size"] as Vector2i) == data.grid_size and Rules.road_route(s["origin"], s["size"]) != null:
				return s["origin"]
	var reserved := {}
	for dep in map.get_all_deposits():
		for x in range(int(dep["cell_x"]) - 1, int(dep["cell_x"]) + int(dep["size_x"]) + 1):
			for y in range(int(dep["cell_y"]) - 1, int(dep["cell_y"]) + int(dep["size_y"]) + 1):
				reserved[Vector2i(x, y)] = true
	var best := center
	var best_d := 1 << 30
	for x in range(GridManager.grid_width - data.grid_size.x + 1):
		for y in range(GridManager.grid_height - data.grid_size.y + 1):
			var origin := Vector2i(x, y)
			var d := _dist(origin, center)
			if d >= best_d or d < 4:
				continue
			if not bool(Rules.evaluate_placement(id, origin, data.grid_size, map, ignore)["ok"]):
				continue
			var clash := false
			for c in GridManager.cells_for(origin, data.grid_size):
				if reserved.has(c):
					clash = true
					break
			if clash:
				continue
			best = origin
			best_d = d
	return best

## Una celda libre pegada a la red, para el tramo de practica.
func _road_cell() -> Vector2i:
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	var best := center
	var best_d := 1 << 30
	for x in GridManager.grid_width:
		for y in GridManager.grid_height:
			var c := Vector2i(x, y)
			var d := _dist(c, center)
			if d >= best_d:
				continue
			var v: Dictionary = Rules.evaluate_placement("road", c, Vector2i(1, 1), _map())
			if bool(v["ok"]) and (v.get("route", []) as Array).is_empty():
				best = c
				best_d = d
	return best

func _practice_road() -> Node:
	var cell: Vector2i = TutorialManager.practice_road_cell
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).id == "road" and info.get("origin_cell", Vector2i(-9, -9)) == cell:
			return info["node"]
	return null

func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true).timeout

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	_n += 1
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%02d_%s.png" % [OUT_DIR, _tag, _n, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("recorrido_probe: ", ProjectSettings.globalize_path(path))

func _finish() -> void:
	SettingsParking.restore(_settings_snap)
	SaveParking.restore(BACKUP_PATH)
	get_tree().paused = false
	get_tree().quit()
