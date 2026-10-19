extends Node
## Sonda de los modelos "maqueta" horneados (tools/build_toy_models.gd). La
## lanza tools/toy_probe.gd. Monta sus propios nodos (no toca la rejilla ni
## guarda), los fotografia con la camara del juego (lente 40, 52 grados) y sale.
##
## - toy_probe_all.png: los edificios en su parcela, a la distancia con la que
##   arranca una partida (32);
## - toy_probe_close_<n>.png: de cuatro en cuatro, al zoom mas cercano (13);
## - toy_probe_storm.png: todos con la luz de la Tormenta;
## - con --pieces: toy_probe_pieces.png, las piezas CC0 sueltas ya pasadas a la
##   paleta (para elegir piezas al escribir una receta).

const Placer := preload("res://scripts/buildings/BuildingPlacer.gd")
const Kit := preload("res://tools/toy_kit.gd")
const MeshKit := preload("res://scripts/buildings/LotMesh.gd")

const OUT_DIR := "res://docs/media/dev"
const SETTLE := 30
const PITCH := 52.0
const FOV := 40.0

const IDS := ["nucleo", "house", "sawmill", "gold_mine", "warehouse", "market", "laboratory", "foundry",
	"barracks", "refinery", "tower", "headquarters", "garden", "fountain", "statue", "farm"]

var _world: Node3D = null

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ids: Array = IDS.duplicate()
	var pieces: Array = []
	var near := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			ids = Array(a.substr(6).split(",", false))
		elif a.begins_with("--near="):
			near = float(a.substr(7))
		elif a.begins_with("--pieces="):
			pieces = Array(a.substr(9).split(",", false))
	if near > 0.0:
		await _shoot_rows(ids, near, "toy_probe_near.png", false, 4.8)
	elif not pieces.is_empty():
		await _shoot_pieces(pieces)
	else:
		await _shoot_rows(ids, 32.0, "toy_probe_all.png", false, 5.0)
		await _shoot_rows(ids, 32.0, "toy_probe_storm.png", true, 5.0)
		var i := 0
		var n := 0
		while i < ids.size():
			await _shoot_rows(ids.slice(i, i + 4), 16.0, "toy_probe_close_%d.png" % n, false, 4.8)
			i += 4
			n += 1
	get_tree().quit()

func _settle() -> void:
	for i in SETTLE:
		await get_tree().process_frame

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, name])
	img.save_png(path)
	print("toy_probe: ", path)

## Luz del juego (o la de la Tormenta) y la camara en su angulo.
func _make_world(storm: bool, target: Vector3, dist: float) -> void:
	_world = Node3D.new()
	add_child(_world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	# La luz de Main.tscn (tonemap, SSAO, saturacion), para ver lo que vera el jugador.
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.27, 0.22) if storm else Color(0.45, 0.65, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.45, 0.35) if storm else Color(1, 0.9, 0.76)
	e.ambient_light_energy = 0.2 if storm else 0.6
	e.tonemap_mode = 3
	e.tonemap_exposure = 1.05
	e.tonemap_white = 6.0
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.6
	e.ssao_power = 1.4
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.06
	e.adjustment_saturation = 1.2
	env.environment = e
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(Basis(Vector3(-0.642788, 0.492404, -0.586824), Vector3(0, 0.766044, 0.642788), Vector3(0.766044, 0.413176, -0.492404)), Vector3(0, 20, 0))
	sun.light_color = Color(1, 0.93, 0.8)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.light_energy = 0.2 if storm else 1.35
	_world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 120)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.36, 0.52, 0.24)
	ground.material_override = gmat
	_world.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = FOV
	_world.add_child(cam)
	var p := deg_to_rad(PITCH)
	cam.position = target + Vector3(0, sin(p) * dist, cos(p) * dist)
	cam.rotation_degrees = Vector3(-PITCH, 0, 0)
	cam.make_current()

func _data(id: String) -> BuildingData:
	var path := "res://data/buildings/%s.tres" % id
	var scene := "res://assets/models/toy/%s.tscn" % id
	if ResourceLoader.exists(path):
		var real: BuildingData = load(path)
		if ResourceLoader.exists(scene) and real.model_scene == null or (real.model_scene != null and real.model_scene.resource_path != scene and ResourceLoader.exists(scene)):
			# Aun sin apuntar el .tres: una copia con el modelo horneado.
			real = real.duplicate()
			real.model_scene = load(scene)
			real.model_scale = 1.0
			real.model_stretch = Vector3.ONE
		return real
	# La granja llega en otra rama: datos de prueba con su modelo horneado.
	var d := BuildingData.new()
	d.id = id
	d.display_name = id.capitalize()
	d.grid_size = Vector2i(2, 2)
	d.mesh_height = 1.2
	if ResourceLoader.exists(scene):
		d.model_scene = load(scene)
	return d

func _shoot_rows(ids: Array, dist: float, file: String, storm: bool, step: float) -> void:
	var cols := mini(ids.size(), 8 if dist > 20.0 else 4)
	var rows := int(ceil(float(ids.size()) / float(cols)))
	_make_world(storm, Vector3(0, 0, 0), dist)
	var placer: Node3D = Placer.new()
	for i in ids.size():
		var id: String = ids[i]
		var data := _data(id)
		var pos := Vector3((i % cols - (cols - 1) * 0.5) * step, 0, ((i / cols) - (rows - 1) * 0.5) * (step + 1.0))
		if id == "nucleo":
			pos.z -= 0.4
		var root: Node3D = placer._create_building_mesh(data)
		var badge := root.get_node_or_null("StatusBadge")
		if badge:
			root.remove_child(badge)
			badge.free()
		root.position = pos
		_world.add_child(root)
		var lot := root.get_node_or_null("Lot")
		if lot:
			lot.build(Vector2i(int(pos.x) + 40, int(pos.z) + 40), 4)
		var label := Label3D.new()
		label.text = id
		label.font_size = 48
		label.pixel_size = 0.01
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 10
		label.no_depth_test = true
		label.position = Vector3(0, 0.05, 2.6 if id != "nucleo" else 3.4)
		root.add_child(label)
	placer.free()
	await _settle()
	await _save(file)
	_world.queue_free()
	await get_tree().process_frame

func _shoot_pieces(pieces: Array) -> void:
	var cols := mini(pieces.size(), 6)
	var rows := int(ceil(float(pieces.size()) / float(cols)))
	var step := 4.2
	_make_world(false, Vector3.ZERO, 7.0 + 3.6 * maxf(cols * 0.6, rows))
	var kit := Kit.new()
	for i in pieces.size():
		var name: String = pieces[i]
		var mk := MeshKit.new()
		kit.put(mk, name, Vector3.ZERO, 2.6)
		var mi := MeshInstance3D.new()
		mi.mesh = mk.commit()
		mi.position = Vector3((i % cols - (cols - 1) * 0.5) * step, 0, ((i / cols) - (rows - 1) * 0.5) * step)
		_world.add_child(mi)
		var label := Label3D.new()
		label.text = name
		label.font_size = 40
		label.pixel_size = 0.01
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 8
		label.no_depth_test = true
		label.position = Vector3(0, 0.05, 1.5)
		mi.add_child(label)
	await _settle()
	await _save("toy_probe_pieces.png")
	_world.queue_free()
	await get_tree().process_frame
