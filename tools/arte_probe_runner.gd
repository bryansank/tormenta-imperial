extends Node
## Sonda del arte del mapa (docs/21 §12). La lanza tools/arte_probe.gd.
## Siembra una colonia (Nucleo, cuadricula de carreteras, casas, talleres junto
## a sus depositos, mercado, decoraciones) y la fotografia:
##   1. 3D en calma: vista general y de cerca;
##   2. 3D en Aviso, Ceniza y Tormenta (el cielo de StormSky);
##   3. FPS sin vsync en la vista general (calidad alta y baja);
##   4. 2D en calma y en Tormenta.
## Imprime "arte_probe: ..." con las cifras.

const SAVE_PATH := "user://save_game.json"
const SaveParking := preload("res://tests/save/save_parking.gd")
const BACKUP_PATH := "user://save_game.arte_probe.bak"
const OUT_DIR := "res://docs/media/dev"
const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")
const ViewMode := preload("res://scripts/view2d/ViewMode.gd")

var _tag := "despues"
var _saved_view := "3d"
var _saved_quality := ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.substr(6)
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _frames(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	SaveParking.park(BACKUP_PATH)
	_saved_view = GameConfig.ui_view_mode
	if "ui_graphics_quality" in GameConfig:
		_saved_quality = String(GameConfig.get("ui_graphics_quality"))
	GameConfig.ui_view_mode = "3d"
	_write_seeded_save()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await _frames(60)
	_close_overlays()
	print("arte_probe: renderer=%s" % RenderingServer.get_current_rendering_method())
	await _seconds(8.0)
	_camera(Vector2(-6.0, -2.0), -1.0)
	await _seconds(1.5)
	await _shot("3d_calma")
	_camera(Vector2(-16.0, -6.0), 0.12)
	await _seconds(1.5)
	await _shot("3d_cerca")
	_camera(Vector2(-4.0, 0.0), 0.4)
	await _seconds(1.5)
	await _shot("3d_general")
	_camera(Vector2(-6.0, -2.0), -1.0)
	await _seconds(1.0)
	# 3) Rendimiento en calma.
	await _fps("alta")
	if "ui_graphics_quality" in GameConfig and EventBus.has_signal("graphics_quality_changed"):
		GameConfig.set("ui_graphics_quality", "low")
		EventBus.emit_signal("graphics_quality_changed", "low")
		await _frames(30)
		await _fps("baja")
		await _shot("3d_calma_baja")
		GameConfig.set("ui_graphics_quality", _saved_quality if _saved_quality != "" else "auto")
		EventBus.emit_signal("graphics_quality_changed", GameConfig.get("ui_graphics_quality"))
		await _frames(30)
	# 2) La Tormenta, fase a fase (StormSky funde en 3 s).
	EventBus.storm_incoming.emit(60.0)
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.WARNING, 60.0)
	await _seconds(4.0)
	await _shot("3d_aviso")
	EventBus.storm_ash_started.emit()
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.ASH, 30.0)
	await _seconds(4.0)
	await _shot("3d_ceniza")
	EventBus.storm_started.emit(3)
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.STORM, 30.0)
	await _seconds(4.0)
	await _shot("3d_tormenta")
	EventBus.storm_ended.emit(3)
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.CALM, 0.0)
	await _seconds(6.0)
	# 4) La vista 2D.
	ViewMode.switch_to("2d", get_tree())
	await _frames(60)
	_close_overlays()
	var cam: Node = get_tree().current_scene.get_node_or_null("Camera2D")
	if cam:
		cam.look_at_world(Vector2(-6, -2), 42.0)
	await _seconds(6.0)
	await _shot("2d_calma")
	if cam:
		cam.look_at_world(Vector2(-16, -6), 20.0)
	await _seconds(1.5)
	await _shot("2d_cerca")
	if cam:
		cam.look_at_world(Vector2(-6, -2), 42.0)
	EventBus.storm_started.emit(3)
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.STORM, 30.0)
	await _seconds(4.0)
	await _shot("2d_tormenta")
	EventBus.storm_ended.emit(3)
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.CALM, 0.0)
	_finish()

func _fps(label: String) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _frames(60)
	var frames := 400
	var t0 := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / frames
	print("arte_probe: fps[%s] renderer=%s frame=%.2fms fps=%.0f" % [
		label, RenderingServer.get_current_rendering_method(), ms, 1000.0 / ms])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

## Centra la camara 3D en `target` (mundo XZ). `zoom` en [0, 1] es la fraccion
## entre la distancia minima y la maxima; negativo deja la de por defecto.
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
		st["distance"] = float(cam.get("default_distance")) if "default_distance" in cam else 30.0
	cam.set_state(st)

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
	var path := "%s/arte_%s_%s.png" % [OUT_DIR, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("arte_probe: ", ProjectSettings.globalize_path(path))

func _finish() -> void:
	GameConfig.ui_view_mode = _saved_view
	if _saved_quality != "":
		GameConfig.set("ui_graphics_quality", _saved_quality)
	GameConfig.save_user_settings()
	SaveParking.restore(BACKUP_PATH)
	get_tree().quit()

## Cuadricula de carreteras cada 4 celdas (11, 15, ..., 31) con el Nucleo en la
## manzana del centro; los talleres al oeste, pegados a su deposito y a la
## carretera de x=11.
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
		"house", "house", "garden", "house", "barracks",
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
	buildings.append({"id": "sawmill", "cell_x": 9, "cell_y": 13})
	buildings.append({"id": "gold_mine", "cell_x": 9, "cell_y": 17})
	buildings.append({"id": "foundry", "cell_x": 9, "cell_y": 21})
	buildings.append({"id": "house", "cell_x": 13, "cell_y": 14})
	buildings.append({"id": "house", "cell_x": 16, "cell_y": 13})
	var data := {
		"saved_at": Time.get_unix_time_from_system(),
		"format": 2,
		"resources": {"gold": 500, "steel": 200, "oil": 100, "wood": 400},
		"unlocked_resources": {"gold": true, "wood": true, "steel": true, "oil": true},
		"buildings": buildings,
		"deposits": [
			{"id": "forest", "cell_x": 6, "cell_y": 12, "size_x": 3, "size_y": 3},
			{"id": "gold_vein", "cell_x": 7, "cell_y": 17, "size_x": 2, "size_y": 3},
			{"id": "iron_deposit", "cell_x": 6, "cell_y": 21, "size_x": 3, "size_y": 2},
			{"id": "forest", "cell_x": 4, "cell_y": 28, "size_x": 3, "size_y": 3},
			{"id": "oil_well", "cell_x": 35, "cell_y": 35, "size_x": 2, "size_y": 2},
		],
		"population": {"population": 80, "morale": 75},
		"tutorial": {"intro_seen": true, "tips_seen": [], "guide_state": "done"},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
