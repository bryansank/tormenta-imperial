extends Node3D
## Generates the island: grass ground, sandy shore and the water around it.
##
## Owner decision (P2, 2026-09-14): **the island grows until it fills the grid.**
## The old island was a superellipse *inscribed* in the grid square, so the four
## corners of the grid were water while `GridManager.can_place()` happily let you
## build there. Instead of adding a land mask, the island is now a rounded square
## that contains every one of the 40x40 cells; shore and water start *outside*
## the grid edge. We knowingly trade the organic silhouette for a map where
## "there is grid" and "there is land" mean the same thing.
##
## The border geometry lives in static, pure functions so a test can prove that
## every cell corner is inside the grass polygon without rendering anything.

@export var water_color: Color = Color(0.15, 0.35, 0.58, 1.0)
@export var shore_color: Color = Color(0.72, 0.62, 0.45, 1.0)

## How far the grass extends past the grid edge, in world units. This is what
## guarantees the outermost cells are fully on land even before any wobble.
@export var land_margin: float = 3.0
## Radius of the rounded corners. Bounded by `land_margin` (see
## `max_corner_radius`): too round a corner would cut into the grid's corner cell.
@export var corner_radius: float = 8.0
## Maximum outward wobble of the border. Wobble is never negative, so it can
## only push the border further out — never into the grid.
@export var wobble_amplitude: float = 2.0
## How much wider than the grass the sandy shore is.
@export var shore_width: float = 3.5

## Border resolution. A rounded square spends most segments on straight edges,
## so it needs more than the old organic blob to keep the corners smooth.
const SEGMENTS := 128

# Stored border wobble (generated once, reused for grass + shore)
var _border_offsets: Array = []
var _seed_val: float = 0.0

func _ready() -> void:
	_seed_val = randf() * 100.0
	_border_offsets = make_wobble(SEGMENTS, _seed_val, wobble_amplitude)
	var limit := max_corner_radius(land_margin)
	if corner_radius > limit:
		# A corner rounder than the margin allows would leave the grid's corner
		# cell in the water again — exactly the bug this file exists to close.
		push_warning("IslandGenerator: corner_radius %.1f exceeds %.1f for land_margin %.1f; clamping" % [corner_radius, limit, land_margin])
		corner_radius = limit
	call_deferred("_generate_island")

# ── Pure geometry (static, testable) ──────────────────────────────────

## Deterministic border wobble, one offset per segment, in [0, amplitude].
## The sum of sines spans [-3.3, 3.3]; it is shifted and scaled so the result
## is never negative — the border may only bulge outwards.
static func make_wobble(segments: int, seed_val: float, amplitude: float) -> Array:
	var out: Array = []
	for i in range(segments):
		var angle: float = (float(i) / float(segments)) * TAU
		var w := 0.0
		w += sin(angle * 2.0 + seed_val) * 1.5
		w += sin(angle * 3.0 + seed_val * 0.7) * 1.0
		w += sin(angle * 5.0 + seed_val * 1.3) * 0.5
		w += sin(angle * 7.0 + seed_val * 0.4) * 0.3
		out.append(clampf((w + 3.3) / 6.6, 0.0, 1.0) * amplitude)
	return out

## Largest corner radius that still keeps the grid corner (h, h) inside a
## rounded square of half-side h + margin. The corner circle is centred at
## (h + margin - R, h + margin - R); the grid corner is inside it when
## sqrt(2) * (R - margin) <= R, i.e. R <= margin * sqrt(2) / (sqrt(2) - 1).
static func max_corner_radius(margin: float) -> float:
	return margin * sqrt(2.0) / (sqrt(2.0) - 1.0)

## Distance from the centre to the edge of a rounded rectangle (half extents
## half_w/half_h, corner radius `radius`) along the ray at `angle`.
static func rounded_square_radius(angle: float, half_w: float, half_h: float, radius: float) -> float:
	var d := Vector2(cos(angle), sin(angle))
	var r: float = clampf(radius, 0.0, minf(half_w, half_h))
	# Where the ray leaves the plain rectangle.
	var tx: float = half_w / absf(d.x) if absf(d.x) > 1e-6 else INF
	var tz: float = half_h / absf(d.y) if absf(d.y) > 1e-6 else INF
	var t_box: float = minf(tx, tz)
	var p := d * t_box
	var cx: float = half_w - r
	var cz: float = half_h - r
	# On a straight edge: the rectangle answer is the right one.
	if absf(p.x) <= cx or absf(p.y) <= cz:
		return t_box
	# In a corner: intersect the ray with that corner's circle.
	var c := Vector2(signf(d.x) * cx, signf(d.y) * cz)
	var b: float = d.dot(c)
	var disc: float = b * b - c.length_squared() + r * r
	return b + sqrt(maxf(disc, 0.0))

## Border polygon of the island (XZ plane) for a grid of half extents
## half_w/half_h. `expand` grows the whole shape (used for the shore ring).
static func border_points(half_w: float, half_h: float, margin: float, radius: float, wobble: Array, expand: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n: int = wobble.size()
	var hw: float = half_w + margin + expand
	var hh: float = half_h + margin + expand
	var r: float = radius + expand
	for i in range(n):
		var angle: float = (float(i) / float(n)) * TAU
		var dist: float = rounded_square_radius(angle, hw, hh, r) + float(wobble[i])
		pts.append(Vector2(cos(angle), sin(angle)) * dist)
	return pts

## Grid half extents in world units, straight from GridManager.
static func grid_half_extents() -> Vector2:
	return Vector2(
		GridManager.grid_width * GridManager.cell_size * 0.5,
		GridManager.grid_height * GridManager.cell_size * 0.5)

# ── Mesh generation ───────────────────────────────────────────────────

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
	shore_node.mesh = _build_island_mesh(shore_width, -0.05)
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

	var half := grid_half_extents()
	var pts := border_points(half.x, half.y, land_margin, corner_radius, _border_offsets, expand)
	var segments: int = pts.size()
	var border: Array = []
	for p in pts:
		border.append(Vector3(p.x, y_offset, p.y))

	var center := Vector3(0, y_offset, 0)

	# Fan triangulation from center — the shape is star-shaped around it, so
	# this stays simple and reliable.
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
		var t: float = float(ring) / float(rings)
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
