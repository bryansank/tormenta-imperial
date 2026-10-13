extends Node
## Sonda del dia y la noche (docs/21 §12). La lanza tools/dianoche_probe.gd.
## Siembra la colonia de la sonda de arte y pone el reloj (DayClock) a mano en
## cada momento del dia; imprime "dianoche_probe: ..." con rutas y cifras.

const SaveParking := preload("res://tests/save/save_parking.gd")
const ArteRunner := preload("res://tools/arte_probe_runner.gd")
const BACKUP_PATH := "user://save_game.dianoche_probe.bak"
const OUT_DIR := "res://docs/media/dev"
const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")
const ViewMode := preload("res://scripts/view2d/ViewMode.gd")

var _tag := "dianoche"
var _saved_view := "3d"
var _saved_quality := ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.substr(6)
	_run.call_deferred()

## Las horas de cada toma: el punto mas calido del alba y del ocaso, el
## mediodia y la medianoche.
func _hours() -> Dictionary:
	var c: DayCycle = DayClock.get_cycle()
	var L := c.length()
	return {
		"amanecer": 0.5 * c.dawn_seconds / L,
		"dia": 0.5 * (c.dawn_seconds + c.day_seconds + c.dusk_seconds) / L,
		"atardecer": (c.dawn_seconds + c.day_seconds + 0.5 * c.dusk_seconds) / L,
		"noche": 1.0 - 0.5 * c.night_seconds / L,
	}

func _set_hour(h: float) -> void:
	DayClock.set_hour(h)
	StormSky.refresh_day()

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _frames(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	SaveParking.park(BACKUP_PATH)
	_saved_view = GameConfig.ui_view_mode
	_saved_quality = GameConfig.ui_graphics_quality
	GameConfig.ui_view_mode = "3d"
	var seeder: Node = ArteRunner.new()
	seeder._write_seeded_save()
	seeder.free()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await _frames(60)
	_close_overlays()
	await _seconds(8.0)
	_camera(Vector2(-6.0, -2.0), -1.0)
	var hours := _hours()
	for moment in ["amanecer", "dia", "atardecer", "noche"]:
		_set_hour(hours[moment])
		await _seconds(1.5)
		await _shot("3d_" + moment)
	# Rendimiento: de dia y de noche, calidad alta.
	_set_hour(hours["dia"])
	await _fps("dia_alta")
	_set_hour(hours["noche"])
	await _fps("noche_alta")
	# La costa de noche (espuma y agua con night_weight).
	_camera(ArteRunner.COAST, ArteRunner.COAST_ZOOM)
	await _seconds(1.5)
	await _shot("3d_costa_noche")
	_camera(Vector2(-16.0, -6.0), 0.12)
	await _seconds(1.5)
	await _shot("3d_cerca_noche")
	_camera(Vector2(-6.0, -2.0), -1.0)
	# Calidad minima de noche: sin sombras, el mismo coste que de dia.
	GameConfig.ui_graphics_quality = "minimal"
	EventBus.graphics_quality_changed.emit("minimal")
	await _frames(30)
	await _fps("noche_minima")
	await _shot("3d_noche_minima")
	_set_hour(hours["dia"])
	await _fps("dia_minima")
	GameConfig.ui_graphics_quality = _saved_quality
	EventBus.graphics_quality_changed.emit(_saved_quality)
	await _frames(30)
	# La Tormenta de noche: la ceniza manda.
	_set_hour(hours["noche"])
	EventBus.storm_started.emit(3)
	await _seconds(4.0)
	await _shot("3d_noche_tormenta")
	EventBus.storm_ended.emit(3)
	await _seconds(6.0)
	await _shot("3d_noche_tras_tormenta")
	# La vista 2D.
	ViewMode.switch_to("2d", get_tree())
	await _frames(60)
	_close_overlays()
	var cam: Node = get_tree().current_scene.get_node_or_null("Camera2D")
	if cam:
		cam.look_at_world(Vector2(-6, -2), 42.0)
	await _seconds(4.0)
	for moment in ["amanecer", "dia", "atardecer", "noche"]:
		_set_hour(hours[moment])
		await _seconds(1.0)
		await _shot("2d_" + moment)
	var tint: Node = get_tree().current_scene.get_node_or_null("StormTint")
	if tint:
		tint.set("forced_weight", 1.0)
		await _seconds(1.0)
		await _shot("2d_noche_tormenta")
		tint.set("forced_weight", -1.0)
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
	print("dianoche_probe: fps[%s] renderer=%s frame=%.2fms fps=%.0f" % [
		label, RenderingServer.get_current_rendering_method(), ms, 1000.0 / ms])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

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
	GameManager._close_offline_report()
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
	var path := "%s/dianoche_%s_%s.png" % [OUT_DIR, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("dianoche_probe: ", ProjectSettings.globalize_path(path))

func _finish() -> void:
	GameConfig.ui_view_mode = _saved_view
	GameConfig.ui_graphics_quality = _saved_quality
	GameConfig.save_user_settings()
	SaveParking.restore(BACKUP_PATH)
	get_tree().quit()
