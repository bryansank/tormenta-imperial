extends Node
## Sonda de la isla irregular (docs/02 "Mapa aleatorio", docs/21 §12). La lanza
## tools/costa_probe.gd. Por cada isla: partida nueva (la isla sale de su
## semilla), foto entera en 3D de dia, de noche y con Tormenta, un plano cerca
## de la costa con la rejilla puesta, y lo mismo en 2D. Imprime
## "costa_probe: ..." con la semilla, el tamano, la tierra y las rutas.
##
## `-- --mar` (aire y mar, 1.1): en vez de la isla entera, el puerto. Planta un
## Muelle de pesca junto a un banco de peces, un Astillero en la costa (girado
## con la misma regla que el fantasma: la darsena al agua) y un Aerodromo tierra
## adentro, y los fotografia de cerca en 3D y en 2D (costa_<n>_mar_*.png): que la
## arena no tape los bancos y que la darsena mire al agua en las dos vistas.
##
## Este autoload sobrevive a los cambios de escena: cada partida nueva recarga
## la escena y la sonda sigue.

const SaveParking := preload("res://tests/save/save_parking.gd")
const ViewMode := preload("res://scripts/view2d/ViewMode.gd")
const BACKUP_PATH := "user://save_game.costa_probe.bak"
const OUT_DIR := "res://docs/media/dev"
const MAIN_3D := "res://scenes/main/Main.tscn"
const Rules := preload("res://scripts/buildings/PlacementRules.gd")

var _sea := false
## Donde se mira en el modo --mar (mundo XZ), el del banco con su muelle.
var _harbour := Vector2.ZERO

var _islands := 5
var _saved_view := "3d"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--islands="):
			_islands = maxi(1, int(arg.substr(10)))
		elif arg == "--mar":
			_sea = true
	_run.call_deferred()

func _hours() -> Dictionary:
	var c: DayCycle = DayClock.get_cycle()
	var L := c.length()
	return {
		"dia": 0.5 * (c.dawn_seconds + c.day_seconds + c.dusk_seconds) / L,
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
	GameConfig.ui_view_mode = "3d"
	GameManager.title_dismissed = true
	get_tree().change_scene_to_file(MAIN_3D)
	await _frames(30)
	for n in range(_islands):
		# Partida nueva de verdad (clear_save borra la activa y recarga): cada
		# vuelta, otra isla.
		GameManager.title_dismissed = true
		GameManager.clear_save()
		await _frames(60)
		await _seconds(3.0)
		_close_overlays()
		print("costa_probe: isla %d semilla=%d rejilla=%dx%d tierra=%d" % [n, GridManager.island_seed,
			GridManager.grid_width, GridManager.grid_height, GridManager.land_cell_count()])
		if _sea:
			_seed_harbour()
			await _frames(30)
			await _sea_shots_3d(n)
		else:
			await _shots_3d(n)
		ViewMode.switch_to("2d", get_tree())
		await _frames(60)
		await _seconds(2.0)
		_close_overlays()
		if _sea:
			await _sea_shots_2d(n)
		else:
			await _shots_2d(n)
		ViewMode.switch_to("3d", get_tree())
		await _frames(30)
	_finish()

func _shots_3d(n: int) -> void:
	var hours := _hours()
	var cam: Node = get_tree().current_scene.get_node_or_null("MonumentalCamera")
	if cam == null:
		push_error("costa_probe: sin MonumentalCamera")
		return
	cam.max_distance = 190.0
	_camera_3d(cam, Vector2.ZERO, 175.0)
	_set_hour(hours["dia"])
	await _seconds(1.5)
	await _shot(n, "3d_dia")
	_set_hour(hours["noche"])
	await _seconds(1.5)
	await _shot(n, "3d_noche")
	_set_hour(hours["dia"])
	# A peso pleno y sin fundido (el fundido es un tween, y con la ventana sin
	# foco el arbol puede estar en pausa).
	StormSky._resolve()
	StormSky._apply_now(1.0)
	await _seconds(1.0)
	await _shot(n, "3d_tormenta")
	# De lejos la niebla de ceniza se lo come todo: tambien a la distancia de juego.
	_camera_3d(cam, _coast_point() + Vector2(14.0, 0.0), 70.0)
	await _seconds(1.0)
	await _shot(n, "3d_tormenta_cerca")
	_camera_3d(cam, Vector2.ZERO, 175.0)
	StormSky._apply_now(0.0)
	await _seconds(0.5)
	# Cerca de la costa, con la rejilla (solo sobre tierra).
	GameConfig.ui_grid_visible = true
	EventBus.grid_overlay_toggled.emit(true)
	_camera_3d(cam, _coast_point(), 40.0)
	await _seconds(1.5)
	await _shot(n, "3d_costa_rejilla")
	GameConfig.ui_grid_visible = false
	EventBus.grid_overlay_toggled.emit(false)

func _shots_2d(n: int) -> void:
	var hours := _hours()
	var cam: Node = get_tree().current_scene.get_node_or_null("Camera2D")
	if cam == null:
		push_error("costa_probe: sin Camera2D")
		return
	cam.max_distance = 190.0
	cam.look_at_world(Vector2.ZERO, 180.0)
	# El tinte de la 2D (dia, noche, Tormenta) va en _process: con la ventana
	# sin foco el juego se pausa, y la foto saldria siempre de dia.
	var tint: Node = get_tree().current_scene.get_node_or_null("StormTint")
	if tint:
		tint.process_mode = Node.PROCESS_MODE_ALWAYS
	_set_hour(hours["dia"])
	await _seconds(1.0)
	await _shot(n, "2d_dia")
	_set_hour(hours["noche"])
	await _seconds(1.0)
	await _shot(n, "2d_noche")
	_set_hour(hours["dia"])
	if tint:
		tint.set("forced_weight", 1.0)
		await _seconds(1.0)
		await _shot(n, "2d_tormenta")
		tint.set("forced_weight", -1.0)
	GameConfig.ui_grid_visible = true
	EventBus.grid_overlay_toggled.emit(true)
	cam.look_at_world(_coast_point(), 30.0)
	await _seconds(1.0)
	await _shot(n, "2d_costa_rejilla")
	GameConfig.ui_grid_visible = false
	EventBus.grid_overlay_toggled.emit(false)

# ── Puerto (--mar) ───────────────────────────────────────────────────

## Muelle junto al primer banco de peces que lo admita, Astillero en la costa mas
## cercana y Aerodromo tierra adentro. Sin coste: place_building_at directo, con
## el mismo veredicto que el clic (se acepta que falte la carretera).
func _seed_harbour() -> void:
	var scene := get_tree().current_scene
	var placer: Node = scene.get_node_or_null("BuildingPlacer")
	var map_gen: Node = scene.get_node_or_null("MapGenerator")
	if placer == null or map_gen == null:
		push_error("costa_probe: sin BuildingPlacer o MapGenerator")
		return
	var shoal: Dictionary = {}
	for entry in map_gen._deposit_cells:
		if String(entry["id"]) == "fish_shoal":
			shoal = entry
			break
	if shoal.is_empty():
		push_warning("costa_probe: esta isla no tiene bancos de peces")
		return
	var c := Vector2i(int(shoal["cell_x"]), int(shoal["cell_y"]))
	var w := GridManager.cell_to_world(c)
	_harbour = Vector2(w.x, w.z)
	var dock := _place_near(placer, map_gen, "fishing_dock", c, 6)
	var yard := _place_near(placer, map_gen, "shipyard", c, 10)
	var aero := _place_near(placer, map_gen, "aerodrome", c, 14)
	print("costa_probe: banco %s muelle=%s astillero=%s aerodromo=%s" % [c, dock, yard, aero])
	GameManager.request_save()

## El primer sitio a `radius` celdas de `around` donde el clic lo aceptaria
## (o solo le faltaria la carretera). Devuelve la celda, o (-1,-1).
func _place_near(placer: Node, map_gen: Node, id: String, around: Vector2i, radius: int) -> Vector2i:
	var data: BuildingData = Rules.load_building_data(id)
	for r in range(0, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var o := around + Vector2i(dx, dy)
				var verdict: Dictionary = Rules.evaluate_placement(id, o, data.grid_size, map_gen)
				if not (bool(verdict["ok"]) or String(verdict["reason"]) == "road"):
					continue
				var steps := maxi(0, Rules.steps_facing_water(id, o, data.grid_size, false))
				var node: Node = placer.place_building_at(data, o, steps)
				if node != null:
					# Terminado (build_time 0), como island_probe.
					ProductionManager.register_building(node, data, 0.0)
					return o
	return Vector2i(-1, -1)

func _sea_shots_3d(n: int) -> void:
	var cam: Node = get_tree().current_scene.get_node_or_null("MonumentalCamera")
	if cam == null:
		return
	_set_hour(_hours()["dia"])
	for d in [55.0, 28.0]:
		for yaw in [0.0, 135.0]:
			var st: Dictionary = cam.get_state()
			st["target_x"] = _harbour.x
			st["target_y"] = _harbour.y
			st["yaw"] = yaw
			st["distance"] = d
			cam.set_state(st)
			await _seconds(1.5)
			await _shot(n, "mar_3d_%d_%d" % [int(d), int(yaw)])

func _sea_shots_2d(n: int) -> void:
	var cam: Node = get_tree().current_scene.get_node_or_null("Camera2D")
	if cam == null:
		return
	_set_hour(_hours()["dia"])
	for d in [40.0, 20.0]:
		cam.look_at_world(_harbour, d)
		await _seconds(1.0)
		await _shot(n, "mar_2d_%d" % int(d))

## Un punto de costa: la celda de tierra mas a la izquierda de la fila del
## Nucleo, en mundo (XZ).
func _coast_point() -> Vector2:
	var y := GridManager.grid_height / 2
	for x in range(GridManager.grid_width):
		if GridManager.is_land_cell(Vector2i(x, y)):
			var w := GridManager.cell_to_world(Vector2i(x + 4, y))
			return Vector2(w.x, w.z)
	return Vector2.ZERO

func _camera_3d(cam: Node, target: Vector2, distance: float) -> void:
	var st: Dictionary = cam.get_state()
	st["target_x"] = target.x
	st["target_y"] = target.y
	st["yaw"] = 0.0
	st["distance"] = distance
	cam.set_state(st)

## Fuera toda la interfaz (prologo, tutorial, HUD): la foto es de la isla.
func _close_overlays() -> void:
	_hide_layers(get_tree().current_scene)

func _hide_layers(node: Node) -> void:
	if node == null:
		return
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	for c in node.get_children():
		_hide_layers(c)

func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame

func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(n: int, shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/costa_%d_%s.png" % [OUT_DIR, n, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("costa_probe: ", ProjectSettings.globalize_path(path))

func _finish() -> void:
	GameConfig.ui_view_mode = _saved_view
	GameConfig.save_user_settings()
	SaveParking.restore(BACKUP_PATH)
	get_tree().quit()
