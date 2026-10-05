extends Node
## Sonda del aspecto de los edificios (docs/03, "Aspecto en el mapa"). La lanza
## tools/look_probe.gd. No guarda partida ni toca la rejilla: monta sus propios
## nodos, los fotografia y sale.

const LookRule := preload("res://scripts/buildings/BuildingLook.gd")
const LookVisual := preload("res://scripts/buildings/BuildingLookVisual.gd")
const Placer := preload("res://scripts/buildings/BuildingPlacer.gd")
const Building2D := preload("res://scripts/view2d/Building2D.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")

const OUT_DIR := "res://docs/media/dev"
const SETTLE_FRAMES := 40

var _world: Node = null

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await _shoot_3d()
	await _shoot_2d()
	get_tree().quit()

func _settle() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, name])
	img.save_png(path)
	print("look_probe: ", path)

# ── 3D ────────────────────────────────────────────────────────────────

## [etiqueta, id del .tres, veredicto]. Las fases van por huella: la 1x1 y la
## 3x3 salen de datos de prueba con ese tamano.
func _cases_3d() -> Array:
	var L := LookRule.Look
	return [
		["Obra F0 1x1", "@1", {"look": L.CONSTRUCTION, "phase": 0}],
		["Obra F0 2x2", "foundry", {"look": L.CONSTRUCTION, "phase": 0}],
		["Obra F1 2x2", "foundry", {"look": L.CONSTRUCTION, "phase": 1}],
		["Obra F2 2x2", "foundry", {"look": L.CONSTRUCTION, "phase": 2}],
		["Obra F2 3x3", "@3", {"look": L.CONSTRUCTION, "phase": 2}],
		["Mejora", "foundry", {"look": L.UPGRADE, "phase": 2}],
		["Ruina", "barracks", {"look": L.RUIN, "phase": 0}],
		["Ruina", "foundry", {"look": L.RUIN, "phase": 0}],
		["Quieta", "foundry", {"look": L.IDLE, "phase": 0}],
		["Humo", "foundry", {"look": L.ACTIVE, "phase": 0}],
		["Serrin", "sawmill", {"look": L.ACTIVE, "phase": 0}],
		["Luz", "warehouse", {"look": L.ACTIVE, "phase": 0}],
	]

func _data(id: String) -> BuildingData:
	if id.begins_with("@"):
		var n := int(id.substr(1))
		var d := BuildingData.new()
		d.id = "probe_%dx%d" % [n, n]
		d.grid_size = Vector2i(n, n)
		d.mesh_height = 2.0
		return d
	return load("res://data/buildings/%s.tres" % id)

func _shoot_3d() -> void:
	_world = Node3D.new()
	add_child(_world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.4, 0.46)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.6
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	_world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 40)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.3, 0.42, 0.22)
	ground.material_override = gmat
	_world.add_child(ground)
	var placer: Node3D = Placer.new()
	var cases := _cases_3d()
	var cols := 6
	for i in cases.size():
		var c: Array = cases[i]
		var data := _data(String(c[1]))
		var root: Node3D
		if String(c[1]).begins_with("@"):
			root = Node3D.new()
			var look: Node3D = LookVisual.new()
			root.add_child(look)
			look.setup(root, data, 2.0)
		else:
			root = placer._create_building_mesh(data)
		# Sin el Zzz encima: la captura es del edificio, no del badge.
		var badge := root.get_node_or_null("StatusBadge")
		if badge:
			root.remove_child(badge)
			badge.free()
		root.position = Vector3((i % cols - (cols - 1) * 0.5) * 7.5, 0, (i / cols) * 9.0 - 4.5)
		_world.add_child(root)
		var look_node := root.get_node_or_null("LookVisual")
		if look_node:
			look_node.apply(c[2])
		if (c[2] as Dictionary)["look"] == LookRule.Look.RUIN:
			root.set_meta("health", 0)
			BuildingHealth.refresh_visual(root)
		var label := Label3D.new()
		label.text = String(c[0])
		label.font_size = 64
		label.pixel_size = 0.012
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 12
		label.position = Vector3(0, -0.2, 3.2)
		label.no_depth_test = true
		root.add_child(label)
	placer.free()
	var cam := Camera3D.new()
	cam.position = Vector3(0, 26, 24)
	cam.rotation_degrees = Vector3(-45, 0, 0)
	cam.fov = 50
	_world.add_child(cam)
	cam.make_current()
	await _settle()
	await _save("look_probe_3d.png")
	_world.queue_free()
	await get_tree().process_frame

# ── 2D ────────────────────────────────────────────────────────────────

func _shoot_2d() -> void:
	_world = Node2D.new()
	add_child(_world)
	var bg := ColorRect.new()
	bg.color = Color(0.3, 0.42, 0.22)
	bg.size = Vector2(4000, 4000)
	bg.position = Vector2(-2000, -2000)
	bg.z_index = -10
	_world.add_child(bg)
	var cam := Camera2D.new()
	cam.zoom = Vector2(1.6, 1.6)
	_world.add_child(cam)
	cam.make_current()
	var cell := View2D.cell_px()
	# [etiqueta, id, como ponerlo]
	var cases := [
		["Obra F0", "foundry", "build:0.1"], ["Obra F1", "foundry", "build:0.5"],
		["Obra F2", "foundry", "build:0.85"], ["Obra F2 3x3", "@3", "build:0.85"],
		["Mejora", "foundry", "upgrade:0.5"], ["Ruina", "barracks", "ruin"],
		["Ruina", "refinery", "ruin"], ["Quieta", "foundry", ""],
		["Humo", "foundry", "staffed"], ["Serrin", "sawmill", "staffed"],
		["Luz", "warehouse", "staffed"], ["Humo", "refinery", "staffed"],
	]
	var cols := 6
	var step := cell * 3.4
	for i in cases.size():
		var c: Array = cases[i]
		var data := _data(String(c[1]))
		if String(c[1]).begins_with("@"):
			data.build_time = 20.0
		var b: Node2D = Building2D.new()
		b.setup(data)
		b.position = Vector2((i % cols - (cols - 1) * 0.5) * step, (i / cols - 0.5) * step * 1.25)
		_world.add_child(b)
		var how := String(c[2])
		if how.begins_with("build:") or how.begins_with("upgrade:"):
			var done := float(how.get_slice(":", 1))
			var upgrade := how.begins_with("upgrade:")
			var total := GameConfig.get_upgrade_duration(2) if upgrade else GameConfig.get_build_time(maxf(1.0, data.build_time))
			ProductionManager.register_building(b, data, total * (1.0 - done), 2 if upgrade else 0)
		elif how == "ruin":
			b.set_meta("health", 0)
		elif how == "staffed":
			b.set_meta("staffed", true)
		var label := Label.new()
		label.text = String(c[0])
		label.position = Vector2(-cell, cell * 1.2)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		b.add_child(label)
	await _settle()
	await _save("look_probe_2d.png")
	for b in _world.get_children():
		ProductionManager.unregister(b)
