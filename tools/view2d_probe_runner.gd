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
## Las capturas van a docs/media/dev/ (ignorada por git). Correla SIEMPRE con
## una carpeta de datos aparte (un override.cfg temporal, no versionado, con
## application/config/use_custom_user_dir=true y custom_user_dir_name propio):
## asi no toca ni el guardado ni los ajustes del jugador. Aun asi, el guardado
## que haya se aparca (tests/save/save_parking.gd) y se devuelve al terminar.
##
## La partida sembrada esta escrita en el formato de save_game.json de siempre,
## el mismo que escribe la vista 3D: que abra bien aqui ES la prueba de que un
## guardado 3D carga en 2D.

const View2D := preload("res://scripts/view2d/View2D.gd")
const SAVE_PATH := "user://save_game.json"
const SaveParking := preload("res://tests/save/save_parking.gd")
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
	SaveParking.park(BACKUP_PATH)
	GameConfig.dev_mode = false
	_saved_view = GameConfig.ui_view_mode
	if OS.get_cmdline_user_args().has("--play"):
		await _play()
		_finish()
		return
	if OS.get_cmdline_user_args().has("--perf"):
		await _perf()
		_finish()
		return
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
	# Las capturas de arte van sin interfaz encima (avisos, ventana de "mientras
	# estuviste fuera"): solo el mapa.
	_ui(false)
	await _frames(30)
	await _shot("2d_overview")

	# Alejado: toda la base
	cam.look_at_world(Vector2(3, 3), 60.0)
	await _frames(5)
	await _shot("2d_far")
	cam.look_at_world(Vector2(-12, 3), 18.0)
	await _frames(20)
	await _shot("2d_close")
	cam.look_at_world(Vector2(3, 3), 32.0)
	await _frames(5)
	_ui(true)

	# Seleccion de un edificio (el panel de info se abre como en 3D)
	var tower := GridManager.get_building_at(Vector2i(12, 24))
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
	await _ghost_at(placer, Vector2i(18, 26))
	await _shot("2d_ghost_valid")
	EventBus.building_selected_for_placement.emit(mine)
	await _ghost_at(placer, Vector2i(21, 21))
	await _shot("2d_ghost_invalid")
	EventBus.building_placement_cancelled.emit()
	await _frames(5)

	# Tormenta: el mapa se apaga y cae ceniza
	var tint: Node = get_tree().current_scene.get_node_or_null("StormTint")
	if tint:
		tint.set("forced_weight", 0.9)
	_ui(false)
	await _frames(90)
	await _shot("2d_storm")
	if tint:
		tint.set("forced_weight", 0.35)
	await _frames(10)
	await _shot("2d_storm_warning")
	_ui(true)
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

## --play: partida NUEVA en 2D jugada con eventos de raton de verdad (los que
## llegan a _unhandled_input): arrastrar el mapa, colocar un aserradero junto a
## un bosque, seleccionarlo. Imprime lo que comprueba.
func _play() -> void:
	GameConfig.dev_mode = true
	get_tree().change_scene_to_file("res://scenes/main/Main2D.tscn")
	await _frames(45)
	var scene := get_tree().current_scene
	_close_overlays()
	var cam: Node = scene.get_node("Camera2D")
	var map_gen: Node = scene.get_node("MapGenerator")
	var nucleo := GridManager.get_building_at(Vector2i(21, 21))
	print("view2d_probe: play nucleo=", nucleo != null, " deposits=", map_gen.get_all_deposits().size())
	# 1) Arrastrar el mapa con el boton izquierdo
	var before: Dictionary = cam.get_state()
	_mouse(Vector2(640, 360), true)
	for i in range(1, 11):
		_motion(Vector2(640 - i * 20, 360))
		await _frames(1)
	_mouse(Vector2(440, 360), false)
	await _frames(3)
	var after: Dictionary = cam.get_state()
	print("view2d_probe: drag moved target_x ", before["target_x"], " -> ", after["target_x"])
	# 2) Colocar un aserradero junto a un bosque, con un clic
	ResourceManager.add(ResourceManager.Type.WOOD, 200)
	ResourceManager.add(ResourceManager.Type.GOLD, 200)
	var spots: Array = map_gen.buildable_spots_near("forest", Vector2i(2, 1), 1, 1)
	if spots.is_empty():
		print("view2d_probe: play no forest spot")
		return
	var spot: Dictionary = spots[0]
	var cell: Vector2i = spot["origin"]
	var sawmill: BuildingData = load("res://data/buildings/sawmill.tres")
	# La huella girada si el hueco es vertical
	EventBus.building_selected_for_placement.emit(sawmill)
	if (spot["size"] as Vector2i) != sawmill.grid_size:
		EventBus.building_rotate_requested.emit()
	cam.look_at_world(Vector2(View2D.px_to_world(View2D.footprint_center_px(cell, spot["size"])).x, View2D.px_to_world(View2D.footprint_center_px(cell, spot["size"])).z))
	await _frames(3)
	var screen := View2D.px_to_screen(get_tree().root.get_canvas_transform(), View2D.footprint_center_px(cell, Vector2i.ONE))
	get_tree().root.warp_mouse(screen)
	await _frames(3)
	await _shot("2d_play_ghost")
	_mouse(screen, true)
	_mouse(screen, false)
	await _frames(3)
	var placed := GridManager.get_building_at(cell)
	var info := GridManager.get_building_info(placed) if placed else {}
	print("view2d_probe: play placed sawmill=", (not info.is_empty()) and info["data"].id == "sawmill", " at ", cell)
	EventBus.building_placement_cancelled.emit()
	await _frames(30)
	# 3) Seleccionarlo con un clic
	_mouse(screen, true)
	_mouse(screen, false)
	await _frames(5)
	var panel: Node = scene.get_node("BuildingInfoPanel")
	var panel_open := false
	for c in panel.get_children():
		if c is Control and (c as Control).visible:
			panel_open = true
	print("view2d_probe: play selected=", placed != null and bool(placed.call("is_selected")), " info_panel_visible=", panel_open)
	await _frames(120)
	await _shot("2d_play_built")

## --perf: un mapa grande (unas 350 calzadas y 150 edificios) visto entero, sin
## vsync. Mide la media de 240 fotogramas: tiempo de fotograma, de _process,
## de CPU y GPU del render del mapa, y primitivas. Si ArtCache2D existe, mide
## con la cache y sin ella (todo a mano). Imprime "view2d_perf: ...".
func _perf() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_write_perf_save()
	get_tree().change_scene_to_file("res://scenes/main/Main2D.tscn")
	await _frames(60)
	var cam: Node = get_tree().current_scene.get_node_or_null("Camera2D")
	_close_overlays()
	_ui(false)
	cam.look_at_world(Vector2(0, 0), 70.0)
	await _frames(120)
	print("view2d_perf: buildings=", GridManager.get_all_buildings().size())
	var cache_path := "res://scripts/view2d/ArtCache2D.gd"
	if ResourceLoader.exists(cache_path):
		var cache: GDScript = load(cache_path)
		await _measure("cache")
		print("view2d_perf: cache entries=", cache.call("count"), " bytes=", cache.call("bytes"))
		await _shot("2d_perf")
		cache.set("enabled", false)
		_clear_cache(cache)
		_redraw_all()
		await _frames(30)
		await _measure("a_mano")
		cache.set("enabled", true)
		_redraw_all()
		await _frames(30)
	else:
		await _measure("antes")
		await _shot("2d_perf_before")
	# Microbanco: cuanto cuesta cada consulta por edificio.
	var sample: Node = null
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).id == "foundry":
			sample = info["node"]
			break
	if sample:
		var t := Time.get_ticks_usec()
		for i in 1000:
			sample.call("_current_signature")
		print("view2d_perf: _current_signature us=", float(Time.get_ticks_usec() - t) / 1000.0)
		var badge: Node = sample.get_node_or_null("StatusBadge")
		t = Time.get_ticks_usec()
		for i in 1000:
			badge.call("refresh")
		print("view2d_perf: badge.refresh us=", float(Time.get_ticks_usec() - t) / 1000.0)
		t = Time.get_ticks_usec()
		for i in 1000:
			badge.call("_process", 0.0)
		print("view2d_perf: badge._process us=", float(Time.get_ticks_usec() - t) / 1000.0)
		t = Time.get_ticks_usec()
		for i in 1000:
			sample.call("_process", 0.016)
		print("view2d_perf: building._process us=", float(Time.get_ticks_usec() - t) / 1000.0)
	# Coste de un fotograma de _process de todos los edificios y sus hijos, por script.
	var per_script := {}
	for info in GridManager.get_all_buildings():
		var node: Node = info["node"]
		for nd in [node] + node.get_children():
			if not nd.is_processing() or not nd.has_method("_process"):
				continue
			var key: String = (nd.get_script() as Script).resource_path.get_file() if nd.get_script() else nd.get_class()
			var t0 := Time.get_ticks_usec()
			nd.call("_process", 0.016)
			per_script[key] = int(per_script.get(key, 0)) + (Time.get_ticks_usec() - t0)
	print("view2d_perf: process por script (us/fotograma) ", per_script)
	# Desglose: que pesa en _process.
	var nodes: Array = []
	for info in GridManager.get_all_buildings():
		nodes.append(info["node"])
	var was := {}
	for n in nodes:
		was[n] = (n as Node).is_processing()
		(n as Node).set_process(false)
	await _measure("sin_process_Building2D")
	for n in nodes:
		(n as Node).set_process(bool(was[n]))
	var badges: Array = []
	for n in nodes:
		var bd: Node = (n as Node).get_node_or_null("StatusBadge")
		if bd and bd.is_processing():
			badges.append(bd)
			bd.set_process(false)
	await _measure("sin_badges (%d)" % badges.size())
	for bd in badges:
		bd.set_process(true)
	for n in nodes:
		(n as Node).process_mode = Node.PROCESS_MODE_DISABLED
	await _measure("sin_process_edificios")
	for n in nodes:
		(n as Node).process_mode = Node.PROCESS_MODE_INHERIT
	var walkers := get_tree().current_scene.find_children("WorkerWalkers", "", true, false)
	for w in walkers:
		w.process_mode = Node.PROCESS_MODE_DISABLED
	await _measure("sin_caminantes")
	for w in walkers:
		w.process_mode = Node.PROCESS_MODE_INHERIT
	var island := get_tree().current_scene.get_node_or_null("Island")
	if island:
		island.visible = false
		await _measure("sin_isla")
		island.visible = true
	for n in nodes:
		(n as CanvasItem).visible = false
	await _measure("sin_edificios")
	for n in nodes:
		(n as CanvasItem).visible = true

func _redraw_all() -> void:
	for info in GridManager.get_all_buildings():
		(info["node"] as CanvasItem).queue_redraw()

func _clear_cache(cache: GDScript) -> void:
	var tex: Dictionary = cache.get("_tex")
	tex.clear()

func _measure(label: String) -> void:
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _frames(30)
	var n := 240
	var frame := 0.0
	var proc := 0.0
	var cpu := 0.0
	var gpu := 0.0
	var prims := 0
	var t0 := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	frame = float(Time.get_ticks_usec() - t0) / 1000.0 / n
	print("view2d_perf: %s frame_ms=%.2f process_ms=%.2f render_cpu_ms=%.2f render_gpu_ms=%.2f prims=%d" % [
		label, frame, proc / n * 1000.0, cpu / n, gpu / n, prims / n])

func _write_perf_save() -> void:
	var taken := {}
	var buildings: Array = []
	var put := func(id: String, x: int, y: int, w: int) -> void:
		for dx in w:
			for dy in w:
				if taken.has(Vector2i(x + dx, y + dy)):
					return
		for dx in w:
			for dy in w:
				taken[Vector2i(x + dx, y + dy)] = true
		buildings.append({"id": id, "cell_x": x, "cell_y": y})
	put.call("nucleo", 20, 20, 3)
	var ids := ["house", "sawmill", "gold_mine", "warehouse", "market", "laboratory", "foundry", "farm",
		"barracks", "refinery", "tower", "headquarters", "garden", "fountain", "statue", "house"]
	var k := 0
	for band in range(2, 37, 4):
		for x in range(2, 38):
			put.call("road", x, band, 1)
		for x in range(2, 37, 2):
			put.call(String(ids[k % ids.size()]), x, band + 1, 2)
			k += 1
	var data := {
		"format": 2,
		"saved_at": Time.get_unix_time_from_system(),
		"resources": {"gold": 900, "steel": 300, "oil": 150, "wood": 600},
		"unlocked_resources": {"gold": true, "wood": true, "steel": true, "oil": true},
		"buildings": buildings,
		"deposits": [],
		"population": {"population": 120, "morale": 80},
		"camera": {"target_x": 0.0, "target_y": 0.0, "yaw": 0.0, "distance": 70.0},
		"tutorial": {"intro_seen": true, "tips_seen": []},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "	"))
	f.close()

func _mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func _motion(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func _ghost_at(placer: Node, cell: Vector2i) -> void:
	var xform := get_tree().root.get_canvas_transform()
	var screen := View2D.px_to_screen(xform, View2D.footprint_center_px(cell, Vector2i.ONE))
	get_tree().root.warp_mouse(screen)
	await _frames(3)
	placer.update_ghost(cell)
	await _frames(3)

## Muestra u oculta toda la interfaz (los CanvasLayer de la escena).
var _ui_was := {}
func _ui(on: bool) -> void:
	if not on:
		_ui_was.clear()
		for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
			if c.name != "AshLayer":
				_ui_was[c] = (c as CanvasLayer).visible
				(c as CanvasLayer).visible = false
		return
	for c in _ui_was:
		if is_instance_valid(c):
			(c as CanvasLayer).visible = bool(_ui_was[c])
	_close_overlays()

func _close_overlays() -> void:
	for panel_name in ["TutorialPanel", "HelperPanel"]:
		var p: Node = get_tree().current_scene.get_node_or_null(panel_name)
		if p and p is CanvasLayer:
			(p as CanvasLayer).visible = false
	# La guia rapida y el prologo son capas propias (hijas del TutorialPanel).
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if c.is_in_group("quick_guide") or c.name == "PrologueScreen" or c.name == "QuickGuide":
			(c as CanvasLayer).visible = false

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
	SaveParking.restore(BACKUP_PATH)
	get_tree().quit()

func _write_seeded_save() -> void:
	var b := func(id: String, x: int, y: int, extra: Dictionary = {}) -> Dictionary:
		var e := {"id": id, "cell_x": x, "cell_y": y}
		e.merge(extra)
		return e
	# Rejilla de 40x40 (sin clave "grid"). El Nucleo en 20,20 con su acera, dos
	# calles (filas 18 y 24) que la tocan y una fila de edificios a cada lado:
	# todos conectados, cada extractor junto a su yacimiento.
	var buildings: Array = [b.call("nucleo", 20, 20)]
	for x in range(19, 24):
		buildings.append(b.call("road", x, 19))
		buildings.append(b.call("road", x, 23))
	for y in range(20, 23):
		buildings.append(b.call("road", 19, y))
		buildings.append(b.call("road", 23, y))
	for x in range(8, 34):
		if x < 19 or x > 23:
			buildings.append(b.call("road", x, 19))
			buildings.append(b.call("road", x, 23))
	buildings.append_array([
		# Norte (filas 17-18)
		b.call("sawmill", 8, 17),
		b.call("house", 10, 17), b.call("house", 12, 17, {"custom_name": "Casa Key"}),
		b.call("market", 14, 17), b.call("laboratory", 16, 17),
		b.call("warehouse", 24, 17), b.call("gold_mine", 26, 17),
		b.call("farm", 28, 17), b.call("house", 30, 17, {"level": 2}), b.call("garden", 32, 17),
		# Sur (filas 24-25)
		b.call("foundry", 8, 24), b.call("barracks", 10, 24, {"health": 0}),
		b.call("tower", 12, 24, {"health": 60}), b.call("refinery", 14, 24, {"level": 2}),
		b.call("headquarters", 16, 24),
		b.call("fountain", 24, 24), b.call("statue", 26, 24),
		b.call("foundry", 28, 24, {"rotation": 1, "construction_remaining": 500.0}),
		b.call("tower", 30, 24, {"rotation": 1}), b.call("warehouse", 32, 24, {"rotation": 2}),
	])
	var data := {
		"format": 2,
		"saved_at": Time.get_unix_time_from_system(),
		"resources": {"gold": 900, "steel": 300, "oil": 150, "wood": 600},
		"unlocked_resources": {"gold": true, "wood": true, "steel": true, "oil": true},
		"buildings": buildings,
		"deposits": [
			{"id": "forest", "cell_x": 5, "cell_y": 16, "size_x": 3, "size_y": 3},
			{"id": "gold_vein", "cell_x": 26, "cell_y": 14, "size_x": 2, "size_y": 3},
			{"id": "iron_deposit", "cell_x": 5, "cell_y": 24, "size_x": 3, "size_y": 2},
			{"id": "oil_well", "cell_x": 14, "cell_y": 27, "size_x": 2, "size_y": 2},
			{"id": "forest", "cell_x": 20, "cell_y": 27, "size_x": 3, "size_y": 2},
		],
		"population": {"population": 40, "morale": 80},
		"camera": {"target_x": 3.0, "target_y": 3.0, "yaw": 0.0, "distance": 32.0},
		"tutorial": {"intro_seen": true, "tips_seen": []},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "	"))
	f.close()
