extends Node3D
## Generates an organic island shape with grass, sandy shore, and water.

@export var water_color: Color = Color(0.15, 0.35, 0.58, 1.0)
@export var shore_color: Color = Color(0.72, 0.62, 0.45, 1.0)

# Stored border shape (generated once, reused for grass + shore)
var _border_offsets: Array = []  # float offsets per segment
var _seed_val: float = 0.0

func _ready() -> void:
	_seed_val = randf() * 100.0
	# Pre-compute border wobble offsets (deterministic per segment)
	var segments := 64
	_border_offsets.clear()
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		var wobble := 0.0
		wobble += sin(angle * 2.0 + _seed_val) * 1.5
		wobble += sin(angle * 3.0 + _seed_val * 0.7) * 1.0
		wobble += sin(angle * 5.0 + _seed_val * 1.3) * 0.5
		wobble += sin(angle * 7.0 + _seed_val * 0.4) * 0.3
		_border_offsets.append(wobble)

	call_deferred("_generate_island")

func _generate_island() -> void:
	# Remove old static meshes from Main if they exist
	var main := get_tree().current_scene
	for node_name in ["Ground", "Shore", "Water"]:
		var old := main.get_node_or_null(node_name)
		if old:
			old.queue_free()
			await get_tree().process_frame

	# Water plane (huge, below everything) — add first so it's behind
	var water_node := MeshInstance3D.new()
	water_node.name = "Water"
	var water_plane := PlaneMesh.new()
	water_plane.size = Vector2(300, 300)
	water_node.mesh = water_plane
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = water_color
	water_mat.roughness = 0.3
	water_mat.metallic = 0.1
	water_node.set_surface_override_material(0, water_mat)
	water_node.position.y = -0.35
	main.add_child(water_node)

	# Shore (slightly larger than grass, sandy color)
	var shore_node := MeshInstance3D.new()
	shore_node.name = "Shore"
	shore_node.mesh = _build_island_mesh(3.5, -0.05)
	var shore_mat := StandardMaterial3D.new()
	shore_mat.albedo_color = shore_color
	shore_mat.roughness = 0.95
	shore_node.set_surface_override_material(0, shore_mat)
	main.add_child(shore_node)

	# Grass island (main ground)
	var grass_node := MeshInstance3D.new()
	grass_node.name = "Ground"
	grass_node.mesh = _build_island_mesh(0.0, 0.0)
	var grass_mat := _create_grass_material()
	grass_node.set_surface_override_material(0, grass_mat)
	main.add_child(grass_node)

func _build_island_mesh(expand: float, y_offset: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segments := _border_offsets.size()
	var half_w: float = GridManager.grid_width * GridManager.cell_size * 0.5
	var half_h: float = GridManager.grid_height * GridManager.cell_size * 0.5

	# Generate border points using stored offsets
	# Use superellipse (squircle) shape so the island covers the full rectangular grid
	var border: Array = []
	var n := 4.0  # Superellipse exponent: higher = more rectangular
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		var ca := cos(angle)
		var sa := sin(angle)
		# Superellipse radius: r = 1 / (|cos|^n + |sin|^n)^(1/n)
		var abs_ca := absf(ca)
		var abs_sa := absf(sa)
		var r_factor := 1.0 / pow(pow(abs_ca, n) + pow(abs_sa, n), 1.0 / n)
		var r_x := (half_w + 2.0 + expand + float(_border_offsets[i])) * r_factor
		var r_z := (half_h + 2.0 + expand + float(_border_offsets[i])) * r_factor
		border.append(Vector3(r_x * ca, y_offset, r_z * sa))

	var center := Vector3(0, y_offset, 0)

	# Fan triangulation from center — simple, reliable
	for i in range(segments):
		var j := (i + 1) % segments
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(center)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(border[i].x / 100.0 + 0.5, border[i].z / 100.0 + 0.5))
		st.add_vertex(border[i])

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(border[j].x / 100.0 + 0.5, border[j].z / 100.0 + 0.5))
		st.add_vertex(border[j])

	# Add subdivided ring for better grass shader detail
	var rings := 5
	for ring in range(1, rings):
		var t := float(ring) / float(rings)
		for i in range(segments):
			var j := (i + 1) % segments
			var inner_i: Vector3 = center.lerp(border[i], t)
			var inner_j: Vector3 = center.lerp(border[j], t)
			var outer_i: Vector3 = center.lerp(border[i], t + 1.0 / float(rings))
			var outer_j: Vector3 = center.lerp(border[j], t + 1.0 / float(rings))

			# Quad as 2 triangles
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(inner_i.x / 100.0 + 0.5, inner_i.z / 100.0 + 0.5))
			st.add_vertex(inner_i)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(outer_i.x / 100.0 + 0.5, outer_i.z / 100.0 + 0.5))
			st.add_vertex(outer_i)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(outer_j.x / 100.0 + 0.5, outer_j.z / 100.0 + 0.5))
			st.add_vertex(outer_j)

			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(inner_i.x / 100.0 + 0.5, inner_i.z / 100.0 + 0.5))
			st.add_vertex(inner_i)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(outer_j.x / 100.0 + 0.5, outer_j.z / 100.0 + 0.5))
			st.add_vertex(outer_j)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(inner_j.x / 100.0 + 0.5, inner_j.z / 100.0 + 0.5))
			st.add_vertex(inner_j)

	return st.commit()

func _create_grass_material() -> ShaderMaterial:
	var shader := load("res://scripts/map/grass_ground.gdshader") as Shader
	if not shader:
		# Fallback to simple green if shader not found
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.30, 0.50, 0.20, 1)
		# Can't return StandardMaterial3D as ShaderMaterial, use shader
		push_warning("Grass shader not found, using default")
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("grass_color_1", Color(0.30, 0.52, 0.18, 1))
	m.set_shader_parameter("grass_color_2", Color(0.38, 0.58, 0.22, 1))
	m.set_shader_parameter("grass_color_3", Color(0.25, 0.45, 0.15, 1))
	m.set_shader_parameter("noise_scale", 12.0)
	m.set_shader_parameter("detail_scale", 80.0)
	m.set_shader_parameter("roughness_val", 0.85)
	return m
