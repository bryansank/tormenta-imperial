extends Node
## Sonda del aspecto de los edificios (docs/03, "Aspecto en el mapa"). La lanza
## tools/look_probe.gd. No guarda partida ni toca la rejilla: monta sus propios
## nodos, los fotografia y sale.
##
## Fila "estilo" (docs/03, "Parcela y atrezo"): los 16 edificios en su parcela,
## con luz normal y con la Tormenta, en 3D (look_probe_style_3d.png,
## look_probe_style_storm_3d.png) y en 2D (look_probe_style_2d.png,
## look_probe_style_storm_2d.png), mas el Aserradero de cerca y en sus estados
## (look_probe_sawmill_3d.png) y los productivos de cerca, cada uno con su
## elemento exagerado (look_probe_style_close_3d.png).

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
	# `-- --only-2d`: solo las capturas 2D (mas rapido al iterar el arte 2D).
	var only_2d := OS.get_cmdline_user_args().has("--only-2d")
	if not only_2d:
		await _shoot_3d()
	await _shoot_2d()
	if not only_2d:
		await _shoot_sites_3d()
	await _shoot_sites_2d()
	if not only_2d:
		await _shoot_style_3d(false)
		await _shoot_style_3d(true)
		await _shoot_sawmill_3d()
		await _shoot_close_3d()
	await _shoot_style_2d(false)
	await _shoot_style_2d(true)
	await _shoot_close_2d()
	await _shoot_icons_2d()
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
	_world.queue_free()
	await get_tree().process_frame

# ── Obras: una fila por fase, varios edificios y dos casas ────────────

## Los edificios de cada fila: estilos distintos y DOS casas (la misma obra en
## dos sitios, que no deben verse iguales).
const SITE_IDS := ["foundry", "sawmill", "refinery", "house", "house", "statue", "tower"]

func _shoot_sites_3d() -> void:
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
	plane.size = Vector2(140, 60)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.3, 0.42, 0.22)
	ground.material_override = gmat
	_world.add_child(ground)
	var placer: Node3D = Placer.new()
	var cols := SITE_IDS.size()
	for phase in 3:
		for i in cols:
			var id := String(SITE_IDS[i])
			var root: Node3D = placer._create_building_mesh(_data(id))
			var badge := root.get_node_or_null("StatusBadge")
			if badge:
				root.remove_child(badge)
				badge.free()
			root.position = Vector3((i - (cols - 1) * 0.5) * 7.0, 0, (phase - 1) * 8.5)
			_world.add_child(root)
			root.get_node("LookVisual").apply({"look": LookRule.Look.CONSTRUCTION, "phase": phase})
			var label := Label3D.new()
			label.text = "F%d %s" % [phase, id]
			label.font_size = 56
			label.pixel_size = 0.012
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.outline_size = 12
			label.position = Vector3(0, -0.2, 3.0)
			label.no_depth_test = true
			root.add_child(label)
	placer.free()
	var cam := Camera3D.new()
	cam.position = Vector3(0, 25, 21)
	cam.rotation_degrees = Vector3(-52, 0, 0)
	cam.fov = 58
	_world.add_child(cam)
	cam.make_current()
	await _settle()
	await _save("look_probe_obras_3d.png")
	# Un instante despues: la grua, el gancho y el banderin se han movido.
	for i in 45:
		await get_tree().process_frame
	await _save("look_probe_obras_3d_b.png")
	_world.queue_free()
	await get_tree().process_frame

func _shoot_sites_2d() -> void:
	_world = Node2D.new()
	add_child(_world)
	var bg := ColorRect.new()
	bg.color = Color(0.3, 0.42, 0.22)
	bg.size = Vector2(4000, 4000)
	bg.position = Vector2(-2000, -2000)
	bg.z_index = -10
	_world.add_child(bg)
	var cam := Camera2D.new()
	cam.zoom = Vector2(1.7, 1.7)
	_world.add_child(cam)
	cam.make_current()
	var cell := View2D.cell_px()
	var step := cell * 2.9
	var cols := SITE_IDS.size()
	var done := [0.1, 0.5, 0.85]
	# Sin reloj de obra: cada fila se queda en su fase mientras se fotografia.
	ProductionManager.process_mode = Node.PROCESS_MODE_DISABLED
	for phase in 3:
		for i in cols:
			var data := _data(String(SITE_IDS[i]))
			var b: Node2D = Building2D.new()
			b.setup(data)
			b.position = Vector2((i - (cols - 1) * 0.5) * step, (phase - 1) * step * 1.15)
			_world.add_child(b)
			var total := GameConfig.get_build_time(maxf(1.0, data.build_time))
			ProductionManager.register_building(b, data, total * (1.0 - float(done[phase])))
			var label := Label.new()
			label.text = "F%d %s" % [phase, data.id]
			label.position = Vector2(-cell, cell * 1.35)
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 4)
			b.add_child(label)
	await _settle()
	await _save("look_probe_obras_2d.png")
	ProductionManager.process_mode = Node.PROCESS_MODE_INHERIT
	for b in _world.get_children():
		ProductionManager.unregister(b)
	_world.queue_free()
	await get_tree().process_frame

# ── Estilo: los 16 en su parcela ──────────────────────────────────────

const STYLE_IDS := ["nucleo", "house", "sawmill", "gold_mine", "warehouse", "market", "laboratory", "foundry",
	"barracks", "refinery", "tower", "headquarters", "garden", "fountain", "statue", "road"]

## Luz de juego; con `storm`, la de StormSky a peso 1 (ceniza, sol al 15 %).
func _style_world(storm: bool) -> Camera3D:
	_world = Node3D.new()
	add_child(_world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.27, 0.22) if storm else Color(0.32, 0.4, 0.46)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.45, 0.35) if storm else Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.18 if storm else 0.6
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 0.15 if storm else 1.0
	_world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 80)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.3, 0.42, 0.22)
	ground.material_override = gmat
	_world.add_child(ground)
	var cam := Camera3D.new()
	_world.add_child(cam)
	cam.make_current()
	return cam

func _style_building(placer: Node3D, id: String, pos: Vector3, road_sides := 0) -> Node3D:
	var data := _data(id)
	var root: Node3D = placer._create_building_mesh(data)
	var badge := root.get_node_or_null("StatusBadge")
	if badge:
		root.remove_child(badge)
		badge.free()
	root.position = pos
	_world.add_child(root)
	var lot := root.get_node_or_null("Lot")
	if lot:
		# Fuera de la rejilla: la semilla sale de la posicion.
		lot.build(Vector2i(int(pos.x), int(pos.z)), road_sides)
	return root

func _style_label(root: Node3D, text: String, z: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.011
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 12
	label.position = Vector3(0, -0.2, z)
	label.no_depth_test = true
	root.add_child(label)

func _shoot_style_3d(storm: bool) -> void:
	var cam := _style_world(storm)
	var placer: Node3D = Placer.new()
	var cols := 8
	var step := 6.2
	for i in STYLE_IDS.size():
		var id: String = STYLE_IDS[i]
		var pos := Vector3((i % cols - (cols - 1) * 0.5) * step, 0, (i / cols) * 7.5 - 3.0)
		var root := _style_building(placer, id, pos)
		_style_label(root, _data(id).get_display_name(), 3.4 if id != "nucleo" else 4.2)
	placer.free()
	cam.position = Vector3(0, 30, 27)
	cam.rotation_degrees = Vector3(-47, 0, 0)
	cam.fov = 45
	await _settle()
	await _save("look_probe_style_storm_3d.png" if storm else "look_probe_style_3d.png")
	_world.queue_free()
	await get_tree().process_frame

## El Aserradero de cerca: dos instancias (atrezo distinto), una con calzada
## delante, y sus estados: obra (3 fases), trabajando y ruina.
func _shoot_sawmill_3d() -> void:
	var cam := _style_world(false)
	var placer: Node3D = Placer.new()
	var L := LookRule.Look
	var cases := [
		["Aserradero A", {"look": L.IDLE, "phase": 0}, 0],
		["Aserradero B (calzada S)", {"look": L.IDLE, "phase": 0}, 4],
		["Trabajando", {"look": L.ACTIVE, "phase": 0}, 0],
		["Obra F0", {"look": L.CONSTRUCTION, "phase": 0}, 0],
		["Obra F1", {"look": L.CONSTRUCTION, "phase": 1}, 0],
		["Obra F2", {"look": L.CONSTRUCTION, "phase": 2}, 0],
		["Ruina", {"look": L.RUIN, "phase": 0}, 0],
		["Mina ruina", {"look": L.RUIN, "phase": 0}, 0],
	]
	for i in cases.size():
		var c: Array = cases[i]
		var id := "gold_mine" if String(c[0]).begins_with("Mina") else "sawmill"
		var pos := Vector3((i % 4 - 1.5) * 6.0, 0, (i / 4) * 7.0 - 3.5)
		var root := _style_building(placer, id, pos, int(c[2]))
		var look := root.get_node_or_null("LookVisual")
		if look:
			look.apply(c[1])
		if (c[1] as Dictionary)["look"] == L.RUIN:
			root.set_meta("health", 0)
			BuildingHealth.refresh_visual(root)
		_style_label(root, String(c[0]), 3.3)
	placer.free()
	cam.position = Vector3(0, 17, 17)
	cam.rotation_degrees = Vector3(-45, 0, 0)
	cam.fov = 45
	await _settle()
	await _save("look_probe_sawmill_3d.png")
	_world.queue_free()
	await get_tree().process_frame

func _shoot_style_2d(storm: bool) -> void:
	_world = Node2D.new()
	add_child(_world)
	var bg := ColorRect.new()
	bg.color = Color(0.3, 0.42, 0.22)
	bg.size = Vector2(4000, 4000)
	bg.position = Vector2(-2000, -2000)
	bg.z_index = -10
	_world.add_child(bg)
	if storm:
		var tint := CanvasModulate.new()
		tint.color = Color(0.46, 0.40, 0.35)
		_world.add_child(tint)
	var cam := Camera2D.new()
	cam.zoom = Vector2(1.6, 1.6)
	_world.add_child(cam)
	cam.make_current()
	var cell := View2D.cell_px()
	var cols := 9
	var step := cell * 3.0
	for i in STYLE_IDS_2D.size():
		var id: String = STYLE_IDS_2D[i]
		var data := _data(id)
		var b: Node2D = Building2D.new()
		b.setup(data)
		b.position = Vector2((i % cols - (cols - 1) * 0.5) * step, (i / cols - 0.5) * step * 1.3)
		_world.add_child(b)
		b.set("_lot_origin", Vector2i(i * 3, 7))
		b.set("_lot_dirty", false)
		if id == "sawmill":
			b.set_meta("staffed", true)
		var label := Label.new()
		label.text = data.get_display_name()
		label.position = Vector2(-cell, cell * (1.2 if id != "nucleo" else 1.6))
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		b.add_child(label)
	await _settle()
	await _save("look_probe_style_storm_2d.png" if storm else "look_probe_style_2d.png")
	_world.queue_free()
	await get_tree().process_frame

## La fila 2D lleva tambien la Granja (rama comida).
const STYLE_IDS_2D := ["nucleo", "house", "sawmill", "gold_mine", "warehouse", "market", "laboratory", "foundry",
	"farm", "barracks", "refinery", "tower", "headquarters", "garden", "fountain", "statue", "road"]

## Los 2D de cerca (zoom 3, el maximo de la camara): para ver el detalle.
func _shoot_close_2d() -> void:
	_world = Node2D.new()
	add_child(_world)
	var bg := ColorRect.new()
	bg.color = Color(0.42, 0.62, 0.26)
	bg.size = Vector2(4000, 4000)
	bg.position = Vector2(-2000, -2000)
	bg.z_index = -10
	_world.add_child(bg)
	var cam := Camera2D.new()
	cam.zoom = Vector2(2.6, 2.6)
	_world.add_child(cam)
	cam.make_current()
	var cell := View2D.cell_px()
	var ids := ["sawmill", "gold_mine", "foundry", "refinery", "warehouse", "market", "laboratory", "farm",
		"barracks", "tower", "headquarters", "house"]
	var cols := 6
	var step := cell * 2.35
	for i in ids.size():
		var data := _data(String(ids[i]))
		var b: Node2D = Building2D.new()
		b.setup(data)
		b.position = Vector2((i % cols - (cols - 1) * 0.5) * step, (i / cols - 0.5) * step * 1.1)
		_world.add_child(b)
		b.set("_lot_origin", Vector2i(i * 3, 9))
		b.set("_lot_dirty", false)
		var badge := b.get_node_or_null("StatusBadge")
		if badge:
			badge.process_mode = Node.PROCESS_MODE_DISABLED
			badge.visible = false
	await _settle()
	await _save("look_probe_close_2d.png")
	_world.queue_free()
	await get_tree().process_frame

## Los iconos del menu de construir (BuildingIcon2D) a tres tamanos.
func _shoot_icons_2d() -> void:
	const Icon2D := preload("res://scripts/view2d/BuildingIcon2D.gd")
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.14, 0.12)
	bg.size = Vector2(1600, 900)
	layer.add_child(bg)
	var x := 10.0
	var y := 10.0
	for px in [36, 56, 96]:
		x = 10.0
		for id in STYLE_IDS_2D:
			var icon: Control = Icon2D.new()
			icon.size = Vector2(px, px)
			icon.position = Vector2(x, y)
			icon.data = _data(String(id))
			layer.add_child(icon)
			x += px + 6.0
		y += px + 14.0
	await _settle()
	await _save("look_probe_icons_2d.png")
	layer.queue_free()
	await get_tree().process_frame

## Los productivos de cerca: parcela, atrezo y elemento exagerado.
func _shoot_close_3d() -> void:
	var cam := _style_world(false)
	var placer: Node3D = Placer.new()
	var ids := ["sawmill", "gold_mine", "foundry", "refinery", "warehouse", "laboratory", "barracks", "tower", "headquarters", "market"]
	for i in ids.size():
		var pos := Vector3((i % 5 - 2.0) * 6.2, 0, (i / 5) * 8.0 - 4.0)
		var root := _style_building(placer, String(ids[i]), pos)
		_style_label(root, _data(String(ids[i])).get_display_name(), 3.2)
	placer.free()
	cam.position = Vector3(0, 19, 18)
	cam.rotation_degrees = Vector3(-45, 0, 0)
	cam.fov = 50
	await _settle()
	await _save("look_probe_style_close_3d.png")
	_world.queue_free()
	await get_tree().process_frame
