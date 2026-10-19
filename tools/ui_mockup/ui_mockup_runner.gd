extends Node
## Sonda de maquetas (fase 1 del rediseno, docs/28-guia-ui.md): arranca una
## partida en la vista 3D, planta unos edificios para que el mapa tenga vida,
## esconde la interfaz de siempre y monta encima las cinco pantallas clave con
## el estilo "maqueta" (CartoonTheme), en cada lienzo y combinacion pedidos.
##
## Lienzos: PC 1280x720 y telefono 640x360 / 800x360 (ventana al doble con
## content_scale_factor 2: la captura sale nitida, el lienzo es el de un
## telefono pequeno en horizontal).
##
## Salida: docs/media/dev/ui_mockups/<fuente>/<fondo>_<lienzo>_<pantalla>.png
## Argumentos tras `--`: --only=<etiqueta de lienzo> (pc, phone640, phone800).

const Mock := preload("res://tools/ui_mockup/mock_screens.gd")
const OUT_DIR := "res://docs/media/dev/ui_mockups"

const LAYOUT := [
	["sawmill", Vector2i(25, 15)],
	["gold_mine", Vector2i(15, 15)],
	["house", Vector2i(17, 18)],
	["house", Vector2i(19, 18)],
	["warehouse", Vector2i(27, 21)],
	["farm", Vector2i(13, 22)],
	["barracks", Vector2i(25, 24)],
	["garden", Vector2i(21, 22)],
]

## Lienzos: etiqueta, tamano de ventana, factor de escala.
const CANVASES := {
	"pc": [Vector2i(1280, 720), 1.0],
	"phone640": [Vector2i(1280, 720), 2.0],
	"phone800": [Vector2i(1600, 720), 2.0],
}

## Que se captura: la eleccion de Bryan entera en los tres lienzos, y las
## variantes que se descartaron solo en PC, para la hoja de comparacion.
const PLAN := [
	["baloo_nunitosans", "mixed", "pc", ["hud", "construir", "ficha", "misiones", "ajustes"]],
	["baloo_nunitosans", "mixed", "phone640", ["hud", "construir", "ficha", "misiones", "ajustes"]],
	["baloo_nunitosans", "mixed", "phone800", ["hud", "construir", "ficha", "misiones", "ajustes"]],
	["lilita_nunito", "mixed", "pc", ["hud", "construir", "ficha"]],
	["fredoka_inter", "mixed", "pc", ["hud", "construir", "ficha"]],
	["baloo_nunitosans", "light", "pc", ["hud", "ficha"]],
	["baloo_nunitosans", "dark", "pc", ["hud", "ficha"]],
]

var _thumbs := {}
var _layer: CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _arg(key: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return ""

func _run() -> void:
	var udir := OS.get_user_data_dir()
	if udir.contains("Tormenta Imperial") or udir.ends_with("TormentaImperial"):
		push_error("ui_mockup_probe: necesita un override.cfg con su propia carpeta de datos (%s)" % udir)
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if FileAccess.file_exists("user://save_game.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_game.json"))
	GameConfig.ui_device_profile = "pc"
	GameConfig.ui_scale_pct = 100
	GameConfig.ui_helper_visible = false
	DeviceProfile.apply_all()
	GameManager.title_dismissed = true
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await _frames(60)
	var main := get_tree().current_scene
	_close_intro(main)
	await _frames(10)
	var placer: Node = main.get_node_or_null("BuildingPlacer")
	if placer != null:
		for e in LAYOUT:
			_plant(placer, String(e[0]), e[1] as Vector2i)
		PopulationManager._recalculate_all()
	await _frames(30)
	_hide_ui(main)
	# Algo mas de mapa a la vista que el encuadre de arranque.
	EventBus.camera_zoom_requested.emit(5.0)
	await _frames(40)
	await _render_thumbnails()
	# Los lienzos de telefono se fuerzan a mano: DeviceProfile no baja de 540
	# de alto logico (docs/28 §4 explica por que la fase 2 debe cambiarlo).
	if get_tree().root.size_changed.is_connected(DeviceProfile._on_window_resized):
		get_tree().root.size_changed.disconnect(DeviceProfile._on_window_resized)

	_layer = CanvasLayer.new()
	_layer.layer = 60
	get_tree().root.add_child(_layer)
	var only := _arg("only")
	var canvas_now := ""
	for step in PLAN:
		var canvas: String = step[2]
		if only != "" and canvas != only:
			continue
		if canvas != canvas_now:
			await _set_canvas(canvas)
			canvas_now = canvas
		UITheme.use_style("cartoon", step[1], step[0])
		CartoonTheme.phone = get_viewport().get_visible_rect().size.y < 450.0
		CartoonTheme.show_caption_never = CartoonTheme.phone
		for screen in step[3]:
			await _shot(step[0], step[1], canvas, screen)
	UITheme.use_style("classic")
	print("ui_mockup_probe: listo en ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()

func _set_canvas(label: String) -> void:
	var c: Array = CANVASES[label]
	DisplayServer.window_set_size(c[0])
	await _frames(12)
	get_tree().root.content_scale_factor = float(c[1])
	await _frames(6)
	# DeviceProfile reescala al cambiar la ventana: se fuerza de nuevo.
	get_tree().root.content_scale_factor = float(c[1])
	await _frames(4)
	print("ui_mockup_probe: lienzo ", label, " ventana=", DisplayServer.window_get_size(),
		" lienzo=", get_viewport().get_visible_rect().size)

func _shot(combo: String, surface: String, canvas: String, screen: String) -> void:
	for ch in _layer.get_children():
		ch.queue_free()
	await _frames(2)
	var vp := get_viewport().get_visible_rect().size
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(holder)
	var ui := Mock.build(screen, {"vp": vp, "thumbs": _thumbs, "host": holder})
	await _frames(5)
	if screen == "construir":
		Mock.place_tooltip(ui)
		await _frames(3)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := "%s/%s" % [OUT_DIR, combo]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := "%s/%s_%s_%s.png" % [dir, surface, canvas, screen]
	img.save_png(ProjectSettings.globalize_path(path))
	print("ui_mockup_probe: ", path, " ", img.get_size())

func _hide_ui(main: Node) -> void:
	for ch in main.get_children():
		if ch is CanvasLayer:
			(ch as CanvasLayer).visible = false

func _close_intro(main: Node) -> void:
	var title: Node = main.get_node_or_null("TitleMenu")
	if title != null and title.has_method("close_menu"):
		title.close_menu()
	var tut: Node = main.get_node_or_null("TutorialPanel")
	if tut and tut.has_method("is_intro_open") and tut.call("is_intro_open"):
		tut.call("_close")
	for guide in get_tree().get_nodes_in_group("quick_guide"):
		if guide.has_method("is_open") and guide.is_open():
			guide.close()

func _plant(placer: Node, id: String, wanted: Vector2i) -> void:
	var data: BuildingData = load("res://data/buildings/%s.tres" % id)
	if data == null:
		return
	var cell := _find_spot(wanted, data.grid_size)
	if cell.x < 0:
		return
	var node: Node3D = placer.place_building_at(data, cell)
	if node != null:
		ProductionManager.register_building(node, data, 0.0)

func _find_spot(wanted: Vector2i, size: Vector2i) -> Vector2i:
	for radius in range(0, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var c := wanted + Vector2i(dx, dy)
				if GridManager.is_valid_cell(c) and GridManager.can_place(c, size):
					return c
	return Vector2i(-1, -1)

## Miniaturas 3D de los edificios, como las de ConstructionMenu.
func _render_thumbnails() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 192)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.world_3d = World3D.new()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.look_at_from_position(Vector3(3.5, 4.0, 3.5), Vector3(0, 0.3, 0))
	viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	light.light_energy = 1.25
	viewport.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, -150, 0)
	fill.light_energy = 0.5
	viewport.add_child(fill)
	add_child(viewport)
	for e in Mock.BUILD_LIST:
		var data: BuildingData = load("res://data/buildings/%s.tres" % e[0])
		if data == null:
			continue
		var model: Node3D = data.instantiate_model() if data.model_scene else \
			DieselpunkBuildingFactory.create(data.id, GridManager.cell_size, data.grid_size)
		if model == null:
			continue
		viewport.add_child(model)
		camera.size = maxf(data.grid_size.x, data.grid_size.y) * GridManager.cell_size * 1.35
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_thumbs[String(e[0])] = ImageTexture.create_from_image(viewport.get_texture().get_image())
		model.queue_free()
		await _frames(1)
	viewport.queue_free()

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
