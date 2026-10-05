extends Node
## Sonda de la vida de la ciudad (docs/04, "Life in the streets"). La lanza
## tools/life_probe.gd. Siembra un pueblo (Nucleo, cuadricula de carreteras,
## 14 casas, talleres con dotacion, mercado y decoraciones), lo abre en Main
## (3D) y:
##   1. captura la calle con la gente de verdad (tope y ritmos del juego);
##   2. captura la Ceniza: calles vacias;
##   3. mide el coste: 60+ figuras en la calle a la vez (estancias cortas y una
##      figura por habitante) contra lo mismo sin figuras, sin vsync;
##   4. cambia a la vista 2D y la captura.
## Imprime "life_probe: ..." con las cifras.

const SAVE_PATH := "user://save_game.json"
const SaveParking := preload("res://tests/save/save_parking.gd")
const BACKUP_PATH := "user://save_game.life_probe.bak"
const OUT_DIR := "res://docs/media/dev"
const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")
const ViewMode := preload("res://scripts/view2d/ViewMode.gd")

var _saved_view := "3d"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _frames(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	SaveParking.park(BACKUP_PATH)
	_saved_view = GameConfig.ui_view_mode
	GameConfig.ui_view_mode = "3d"
	_write_seeded_save()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await _frames(60)
	_close_overlays()
	var walkers := _walkers()
	if walkers == null:
		push_error("life_probe: no hay WorkerWalkers en la escena")
		_finish()
		return
	# 1) La calle con los ritmos del juego.
	await _seconds(14.0)
	print("life_probe: 3d normal actores=%d en_calle=%d cap=%d pob=%d obreros=%d" % [walkers.actor_count(),
		walkers.walker_count(), walkers.figure_cap(), PopulationManager.get_population(), PopulationManager.get_used_workers()])
	await _shot("life_probe_3d")
	_zoom(14.0)
	await _seconds(2.0)
	await _shot("life_probe_3d_close")
	_zoom(30.0)
	# 2) La Ceniza: todos dentro.
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.ASH, 30.0)
	await _seconds(2.0)
	print("life_probe: ceniza en_calle=%d" % walkers.walker_count())
	await _shot("life_probe_3d_ash")
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.CALM, 0.0)
	# 3) Rendimiento con 60+ figuras en la calle.
	await _stress(walkers)
	# 4) La vista 2D.
	_relax()
	ViewMode.switch_to("2d", get_tree())
	await _frames(60)
	_close_overlays()
	var cam: Node = get_tree().current_scene.get_node_or_null("Camera2D")
	if cam:
		cam.look_at_world(Vector2(3, 3), 18.0)
	walkers = _walkers()
	await _seconds(14.0)
	if walkers:
		print("life_probe: 2d actores=%d en_calle=%d" % [walkers.actor_count(), walkers.walker_count()])
	await _shot("life_probe_2d")
	_finish()

func _stress(walkers: Node) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GameConfig.life_people_per_figure = 1
	GameConfig.life_stay_home = Vector2(0.3, 0.8)
	GameConfig.life_stay_work = Vector2(0.3, 0.8)
	GameConfig.life_stay_market = Vector2(0.3, 0.8)
	GameConfig.life_pause_decoration = Vector2(0.3, 0.6)
	GameConfig.life_pause_stroll = Vector2(0.2, 0.4)
	walkers.reconcile()
	await _seconds(6.0)
	var with_fig := await _measure(walkers, 600)
	print("life_probe: estres actores=%d en_calle_media=%.1f frame=%.2fms fps=%.0f walkers_cpu=%.0fus (max %dus) (paso %.0fus, dibujo %.0fus) repaso=%dus" % [
		walkers.actor_count(), with_fig["out"], with_fig["ms"], 1000.0 / with_fig["ms"], with_fig["us"], with_fig["us_max"], walkers.avg_tick_usec, walkers.avg_render_usec, walkers.last_reconcile_usec])
	_bench(walkers)
	await _shot("life_probe_3d_stress")
	# Lo mismo sin figuras: el nodo parado y su capa escondida.
	walkers.set_process(false)
	var layer: Node3D = get_tree().current_scene.get_node("BuildingPlacer/Walkers")
	layer.visible = false
	var without := await _measure(null, 600)
	print("life_probe: sin_figuras frame=%.2fms fps=%.0f -> coste figuras=%.3fms/frame" % [
		without["ms"], 1000.0 / without["ms"], with_fig["ms"] - without["ms"]])
	layer.visible = true
	walkers.set_process(true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

## Coste de CPU aislado del resto del fotograma (con otras cosas corriendo en la
## maquina, el tiempo de fotograma baila): 15 tandas de 60 pasos + dibujo
## seguidos; se queda con la mejor tanda y la mediana.
func _bench(walkers: Node) -> void:
	var figures: Node = get_tree().current_scene.get_node("BuildingPlacer/Walkers/Figures")
	var tick_us: Array = []
	var draw_us: Array = []
	for batch in 15:
		var t_tick := 0
		var t_draw := 0
		for i in 60:
			var t0 := Time.get_ticks_usec()
			walkers.tick(1.0 / 60.0)
			var t1 := Time.get_ticks_usec()
			figures.render(walkers.actors())
			t_tick += t1 - t0
			t_draw += Time.get_ticks_usec() - t1
		tick_us.append(t_tick / 60.0)
		draw_us.append(t_draw / 60.0)
	tick_us.sort()
	draw_us.sort()
	print("life_probe: banco %d figuras (%d en la calle): paso min %.0fus / mediana %.0fus, dibujo min %.0fus / mediana %.0fus" % [
		walkers.actor_count(), walkers.walker_count(), tick_us[0], tick_us[7], draw_us[0], draw_us[7]])

func _measure(walkers: Node, frames: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var out_sum := 0.0
	var us_sum := 0.0
	var us_max := 0
	for i in frames:
		await get_tree().process_frame
		if walkers:
			out_sum += walkers.walker_count()
			us_sum += walkers.last_frame_usec
			us_max = maxi(us_max, walkers.last_frame_usec)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / frames
	return {"ms": ms, "out": out_sum / frames, "us": us_sum / frames, "us_max": us_max}

func _relax() -> void:
	GameConfig.life_people_per_figure = 2
	GameConfig.life_stay_home = Vector2(4.0, 12.0)
	GameConfig.life_stay_work = Vector2(10.0, 20.0)
	GameConfig.life_stay_market = Vector2(4.0, 8.0)
	GameConfig.life_pause_decoration = Vector2(3.0, 6.0)
	GameConfig.life_pause_stroll = Vector2(1.0, 2.5)

func _walkers() -> Node:
	return get_tree().current_scene.get_node_or_null("BuildingPlacer/WorkerWalkers")

func _zoom(distance: float) -> void:
	var cam: Node = get_tree().current_scene.get_node_or_null("MonumentalCamera")
	if cam and cam.has_method("set_state"):
		cam.set_state({"target_x": 3.0, "target_y": 3.0, "yaw": 0.0, "distance": distance})

func _close_overlays() -> void:
	for panel_name in ["TutorialPanel", "HelperPanel", "TitleMenu"]:
		var p: Node = get_tree().current_scene.get_node_or_null(panel_name)
		if p and p is CanvasLayer:
			(p as CanvasLayer).visible = false

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("life_probe: ", ProjectSettings.globalize_path(path))

func _finish() -> void:
	GameConfig.ui_view_mode = _saved_view
	GameConfig.save_user_settings()
	SaveParking.restore(BACKUP_PATH)
	get_tree().quit()

## Cuadricula de carreteras cada 4 celdas (x, y = 11, 15, ..., 31) con el Nucleo
## en la manzana del centro; en cada manzana un edificio 2x2 pegado a su esquina.
func _write_seeded_save() -> void:
	var buildings: Array = [{"id": "nucleo", "cell_x": 20, "cell_y": 20}]
	var roads := {}
	for a in [11, 15, 19, 23, 27, 31]:
		for b in range(11, 32):
			roads[Vector2i(a, b)] = true
			roads[Vector2i(b, a)] = true
	for c in roads:
		buildings.append({"id": "road", "cell_x": c.x, "cell_y": c.y})
	var lots: Array = [
		"house", "house", "garden", "house", "house",
		"house", "warehouse", "market", "house", "house",
		"fountain", "house", "", "laboratory", "house",
		"house", "tower", "statue", "warehouse", "house",
		"house", "house", "house", "garden", "house",
	]
	var i := 0
	for by in 5:
		for bx in 5:
			var id: String = lots[i]
			i += 1
			if id == "":
				continue
			buildings.append({"id": id, "cell_x": 12 + bx * 4, "cell_y": 12 + by * 4})
	var data := {
		"saved_at": Time.get_unix_time_from_system(),
		"format": 2,
		"resources": {"gold": 900, "steel": 300, "oil": 150, "wood": 600},
		"unlocked_resources": {"gold": true, "wood": true, "steel": true, "oil": true},
		"buildings": buildings,
		"deposits": [
			{"id": "forest", "cell_x": 3, "cell_y": 3, "size_x": 3, "size_y": 3},
			{"id": "gold_vein", "cell_x": 34, "cell_y": 4, "size_x": 2, "size_y": 3},
			{"id": "iron_deposit", "cell_x": 3, "cell_y": 34, "size_x": 3, "size_y": 2},
			{"id": "oil_well", "cell_x": 35, "cell_y": 35, "size_x": 2, "size_y": 2},
		],
		"population": {"population": 80, "morale": 75},
		"camera": {"target_x": 3.0, "target_y": 3.0, "yaw": 0.0, "distance": 30.0},
		"tutorial": {"intro_seen": true, "tips_seen": [], "guide_state": "done"},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
