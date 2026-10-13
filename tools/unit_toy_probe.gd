extends SceneTree
## Foto de las unidades de juguete horneadas (tools/build_toy_models.gd -- --units):
## las seis (tipo x bando) y el atrezo del jefe y de la dotacion, en fila.
##
##     godot --path . -s tools/unit_toy_probe.gd
##
## Sale docs/media/dev/unit_toys.png (git-ignorado). Con override.cfg propio.

const OUT := "res://docs/media/dev/unit_toys.png"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.22, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 0.9, 0.76)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 12)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.55, 0.3)
	ground.material_override = gm
	root.add_child(ground)
	var names := ["infantry_player", "infantry_regency", "artillery_player", "artillery_regency",
		"vehicle_player", "vehicle_regency", "boss_mark", "crew_nest"]
	var team := StandardMaterial3D.new()
	team.vertex_color_use_as_albedo = true
	team.vertex_color_is_srgb = true
	team.roughness = 0.82
	team.albedo_color = Color(0.30, 0.45, 0.62)  # "steel" de GameConfig.colony_colors
	for i in names.size():
		var scene: PackedScene = load("res://assets/models/toy/units/%s.tscn" % names[i])
		var n: MeshInstance3D = scene.instantiate()
		n.position = Vector3(-10.5 + i * 3.0, 0, 0)
		var idx: int = n.mesh.surface_find_by_name("team")
		if idx >= 0:
			n.set_surface_override_material(idx, team)
		root.add_child(n)
	var cam := Camera3D.new()
	cam.fov = 30
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 9, 17), Vector3(0, 0.4, 0))
	cam.current = true
	for k in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/media/dev"))
	get_root().get_texture().get_image().save_png(OUT)
	print("unit_toy_probe: ", OUT)
	quit()
