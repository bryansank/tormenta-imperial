extends Node
## Sonda de los yacimientos (docs/02, "Yacimientos en el mapa"). La lanza
## tools/deposito_probe.gd. Siembra una partida con dos filas de yacimientos:
## arriba los cuatro enteros, cada uno con su extractor de maqueta al lado
## (Aserradero, Mina de oro, Fundicion; una Casa junto al pozo, que la Refineria
## se lo comeria); abajo otros cuatro de otros tamanos y medio gastados.
## Fotografia:
##   1. 3D de dia: las dos mitades de la fila de arriba, la de abajo y general;
##   2. 3D en la Tormenta y de noche (DayClock);
##   3. 2D de dia y en la Tormenta.
## Imprime "deposito_probe: ..." con el coste (mallas, triangulos, superficies
## y el tiempo de montar los yacimientos).

var SAVE_PATH: String:
	get:
		return GameManager.save_path()
const SaveParking := preload("res://tests/save/save_parking.gd")
const BACKUP_PATH := "user://save_game.deposito_probe.bak"
const OUT_DIR := "res://docs/media/dev"
const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")
const ViewMode := preload("res://scripts/view2d/ViewMode.gd")

## Centros de las tomas (mundo XZ) y zoom (fraccion entre min y max).
const SHOT_A := Vector2(-15.0, -17.0)
const SHOT_B := Vector2(3.0, -17.0)
const SHOT_ROW2 := Vector2(-4.0, -5.0)
const SHOT_ALL := Vector2(-6.0, -11.0)
const ZOOM_NEAR := 0.1

var _tag := "despues"
var _saved_view := "3d"

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
	GameConfig.ui_view_mode = "3d"
	_write_seeded_save()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await _frames(60)
	_close_overlays()
	await _seconds(6.0)
	_report_cost()
	_set_hour("dia")
	_camera(SHOT_A, ZOOM_NEAR)
	await _seconds(1.5)
	await _shot("3d_dia_bosque_oro")
	_camera(SHOT_B, ZOOM_NEAR)
	await _seconds(1.5)
	await _shot("3d_dia_hierro_petroleo")
	_camera(SHOT_ROW2, ZOOM_NEAR + 0.05)
	await _seconds(1.5)
	await _shot("3d_dia_gastados")
	_camera(SHOT_ALL, 0.3)
	await _seconds(1.5)
	await _shot("3d_dia_general")
	# La Tormenta (StormSky funde en 3 s).
	EventBus.storm_incoming.emit(60.0)
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.WARNING, 60.0)
	EventBus.storm_ash_started.emit()
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.ASH, 30.0)
	EventBus.storm_started.emit(3)
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.STORM, 30.0)
	_camera(SHOT_A, ZOOM_NEAR)
	await _seconds(4.0)
	await _shot("3d_tormenta_bosque_oro")
	_camera(SHOT_B, ZOOM_NEAR)
	await _seconds(1.5)
	await _shot("3d_tormenta_hierro_petroleo")
	EventBus.storm_ended.emit(3)
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.CALM, 0.0)
	await _seconds(4.0)
	# De noche.
	_set_hour("noche")
	_camera(SHOT_A, ZOOM_NEAR)
	await _seconds(2.0)
	await _shot("3d_noche_bosque_oro")
	_camera(SHOT_B, ZOOM_NEAR)
	await _seconds(1.5)
	await _shot("3d_noche_hierro_petroleo")
	_set_hour("dia")
	_camera(SHOT_ALL, 0.3)
	await _fps("3d")
	# La vista 2D.
	ViewMode.switch_to("2d", get_tree())
	await _frames(60)
	_close_overlays()
	await _seconds(4.0)
	var cam: Node = get_tree().current_scene.get_node_or_null("Camera2D")
	if cam:
		cam.look_at_world(Vector2(-6, -12), 26.0)
	await _seconds(1.5)
	await _shot("2d_dia")
	if cam:
		cam.look_at_world(Vector2(-14, -16), 12.0)
	await _seconds(1.5)
	await _shot("2d_cerca")
	if cam:
		cam.look_at_world(Vector2(-6, -12), 26.0)
	EventBus.storm_started.emit(3)
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.STORM, 30.0)
	await _seconds(4.0)
	await _shot("2d_tormenta")
	EventBus.storm_ended.emit(3)
	EventBus.storm_phase_changed.emit(StormCycleScript.Phase.CALM, 0.0)
	await _fps("2d")
	_finish()

## Mallas, triangulos y superficies (llamadas de dibujo) de los yacimientos.
func _report_cost() -> void:
	var gen: Node = get_tree().current_scene.get_node_or_null("MapGenerator")
	if gen == null:
		return
	var deps: Node = gen.get_node_or_null("Deposits")
	if deps == null:
		return
	for dep in deps.get_children():
		var meshes := 0
		var surfaces := 0
		var tris := 0
		var stack: Array = [dep]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if n is MeshInstance3D and (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh != null:
				var m: Mesh = (n as MeshInstance3D).mesh
				meshes += 1
				surfaces += m.get_surface_count()
				tris += _tris(m)
			elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
				var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
				meshes += 1
				if mm.mesh:
					surfaces += mm.mesh.get_surface_count()
					tris += _tris(mm.mesh) * mm.visible_instance_count if mm.visible_instance_count >= 0 else _tris(mm.mesh) * mm.instance_count
		var size: Vector2i = dep.get_meta("deposit_size", Vector2i.ZERO)
		print("deposito_probe: coste %-13s %dx%d usos %d/%d  mallas=%d superficies=%d tri=%d" % [
			dep.get_meta("deposit_id", "?"), size.x, size.y, int(dep.get_meta("uses_remaining", 0)),
			int(dep.get_meta("max_uses", 0)), meshes, surfaces, tris])
	# Tiempo de montar la malla de un yacimiento de cada tipo (sin cache): lo
	# que cuesta la primera vez que aparece una combinacion tipo/tamano/variante/etapa.
	var DepositMesh = load("res://scripts/map/DepositMesh.gd")
	for id in ["forest", "gold_vein", "iron_deposit", "oil_well"]:
		for size in [Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)]:
			var reps := 10
			var t0 := Time.get_ticks_usec()
			var mesh: Mesh = null
			for i in reps:
				mesh = DepositMesh.build(id, size, i, 4, 2.0)
			print("deposito_probe: montar %-13s %dx%d = %.2f ms, %d tri, %d superficies" % [id, size.x, size.y,
				float(Time.get_ticks_usec() - t0) / 1000.0 / reps, _tris(mesh), mesh.get_surface_count()])

static func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			t += (idx as PackedInt32Array).size() / 3
		else:
			t += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t

func _fps(label: String) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _frames(60)
	var frames := 300
	var t0 := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / frames
	print("deposito_probe: fps[%s] frame=%.2fms dibujos=%d" % [label, ms,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

func _set_hour(moment: String) -> void:
	var c = DayClock.get_cycle()
	var L: float = c.length()
	var h: float = 0.5 * (c.dawn_seconds + c.day_seconds + c.dusk_seconds) / L
	if moment == "noche":
		h = 1.0 - 0.5 * c.night_seconds / L
	DayClock.set_hour(h)
	StormSky.refresh_day()

func _camera(target: Vector2, zoom: float) -> void:
	var cam: Node = get_tree().current_scene.get_node_or_null("MonumentalCamera")
	if cam == null:
		return
	var st: Dictionary = cam.get_state()
	st["target_x"] = target.x
	st["target_y"] = target.y
	st["distance"] = lerpf(cam.min_distance, cam.max_distance, zoom)
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
	var path := "%s/dep_%s_%s.png" % [OUT_DIR, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("deposito_probe: ", ProjectSettings.globalize_path(path))

func _finish() -> void:
	GameConfig.ui_view_mode = _saved_view
	GameConfig.save_user_settings()
	SaveParking.restore(BACKUP_PATH)
	get_tree().quit()

## Fila de arriba (y = 9..13): yacimiento entero y su edificio debajo, pegado a
## la carretera de y = 14. Fila de abajo (y = 16..18): otros tamanos, gastados.
func _write_seeded_save() -> void:
	var buildings: Array = [{"id": "nucleo", "cell_x": 20, "cell_y": 20}]
	var roads := {}
	for x in range(7, 29):
		roads[Vector2i(x, 14)] = true
	for y in range(15, 19):
		roads[Vector2i(21, y)] = true
	for c in roads:
		buildings.append({"id": "road", "cell_x": c.x, "cell_y": c.y})
	buildings.append({"id": "sawmill", "cell_x": 8, "cell_y": 12})
	buildings.append({"id": "gold_mine", "cell_x": 13, "cell_y": 12})
	buildings.append({"id": "foundry", "cell_x": 18, "cell_y": 12})
	buildings.append({"id": "house", "cell_x": 23, "cell_y": 12})
	var data := {
		"saved_at": Time.get_unix_time_from_system(),
		"format": 2,
		"resources": {"gold": 500, "steel": 200, "oil": 100, "wood": 400},
		"unlocked_resources": {"gold": true, "wood": true, "steel": true, "oil": true},
		"buildings": buildings,
		"deposits": [
			{"id": "forest", "cell_x": 8, "cell_y": 9, "size_x": 3, "size_y": 3},
			{"id": "gold_vein", "cell_x": 13, "cell_y": 9, "size_x": 3, "size_y": 3},
			{"id": "iron_deposit", "cell_x": 18, "cell_y": 10, "size_x": 3, "size_y": 2},
			{"id": "oil_well", "cell_x": 23, "cell_y": 10, "size_x": 2, "size_y": 2},
			{"id": "forest", "cell_x": 7, "cell_y": 16, "size_x": 4, "size_y": 3, "uses_remaining": 3},
			{"id": "gold_vein", "cell_x": 12, "cell_y": 16, "size_x": 2, "size_y": 2, "uses_remaining": 2},
			{"id": "iron_deposit", "cell_x": 15, "cell_y": 16, "size_x": 2, "size_y": 3, "uses_remaining": 3},
			{"id": "oil_well", "cell_x": 24, "cell_y": 16, "size_x": 3, "size_y": 3, "uses_remaining": 4},
		],
		"population": {"population": 20, "morale": 75},
		"tutorial": {"intro_seen": true, "tips_seen": [], "guide_state": "done"},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
