extends Node3D
## Generates the island: grass ground, sandy shore and the water around it.
##
## Maqueta (arte, 2026-10-05, docs/21 §12): el cesped es una placa con canto de
## tierra ("Cliff"), la playa baja hacia el mar ("Shore"), el agua la corta y
## alli va la espuma ("Foam"). Todo con shaders propios de scripts/map, sin
## texturas: grass_ground, island_cliff, island_sand, island_foam y
## water_border.
##
## Owner decision (P2, 2026-09-14): **the island grows until it fills the grid.**
## The old island was a superellipse *inscribed* in the grid square, so the four
## corners of the grid were water while `GridManager.can_place()` happily let you
## build there. Instead of adding a land mask, the island is now a rounded square
## that contains every cell of the grid; shore and water start *outside*
## the grid edge. We knowingly trade the organic silhouette for a map where
## "there is grid" and "there is land" mean the same thing.
##
## Mapa aleatorio (2026-09-28): la rejilla cambia de tamano por partida (40 a 48
## por lado) y la forma sale de GridManager.island_seed (shape_for_seed): margen,
## esquinas, ondulacion y su detalle varian, siempre dentro de la garantia. Al
## oir EventBus.grid_resized la isla se rehace.
##
## The border geometry lives in static, pure functions so a test can prove that
## every cell corner is inside the grass polygon without rendering anything.

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
@export var shore_width: float = 4.5

## Border resolution. A rounded square spends most segments on straight edges,
## so it needs more than the old organic blob to keep the corners smooth.
const SEGMENTS := 128

# Stored border wobble (generated once, reused for grass + shore)
var _border_offsets: Array = []
var _seed_val: float = 0.0

## Detalle de la ondulacion (peso de los armonicos altos): 1 = el de siempre.
var _wobble_detail: float = 1.0
var _regen_queued := false
# Nodos de isla que ha creado este generador (para rehacerlos al cambiar la rejilla)
var _made: Array = []

func _ready() -> void:
	_apply_shape()
	EventBus.grid_resized.connect(_on_grid_resized)
	_queue_regen()

## La forma de esta partida: de GridManager.island_seed si la hay (partida
## nueva o cargada), si no los valores exportados con una ondulacion al azar.
func _apply_shape() -> void:
	if GridManager.island_seed >= 0:
		var shape := shape_for_seed(GridManager.island_seed)
		_seed_val = shape["seed_val"]
		land_margin = shape["margin"]
		corner_radius = shape["radius"]
		wobble_amplitude = shape["amplitude"]
		_wobble_detail = shape["detail"]
	elif _seed_val == 0.0:
		_seed_val = randf() * 100.0
	var limit := max_corner_radius(land_margin)
	if corner_radius > limit:
		# A corner rounder than the margin allows would leave the grid's corner
		# cell in the water again — exactly the bug this file exists to close.
		push_warning("IslandGenerator: corner_radius %.1f exceeds %.1f for land_margin %.1f; clamping" % [corner_radius, limit, land_margin])
		corner_radius = limit
	_border_offsets = make_wobble(SEGMENTS, _seed_val, wobble_amplitude, _wobble_detail)

func _on_grid_resized(_w: int, _h: int) -> void:
	_apply_shape()
	_queue_regen()

func _queue_regen() -> void:
	if _regen_queued:
		return
	_regen_queued = true
	call_deferred("_generate_island")

# ── Pure geometry (static, testable) ──────────────────────────────────

## La forma de la isla de una partida, sacada de su semilla (la guarda
## GridManager). Todo lo que sale de aqui mantiene la promesa de cubrir la
## rejilla: margen >= 3, esquina <= max_corner_radius(margen) y ondulacion >= 0.
## La usan la isla 3D y la 2D, asi que las dos vistas dibujan la misma isla.
static func shape_for_seed(island_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = island_seed
	var margin: float = rng.randf_range(3.0, 6.0)
	return {
		"seed_val": rng.randf() * 100.0,
		"margin": margin,
		"radius": rng.randf_range(0.35, 1.0) * max_corner_radius(margin),
		"amplitude": rng.randf_range(1.0, 4.5),
		"detail": rng.randf_range(0.5, 2.0),
	}

## Deterministic border wobble, one offset per segment, in [0, amplitude].
## The sum of sines is shifted and scaled by its own bound so the result is
## never negative — the border may only bulge outwards. `detail` weights the
## high harmonics: below 1 a smoother coast, above 1 a more jagged one.
static func make_wobble(segments: int, seed_val: float, amplitude: float, detail: float = 1.0) -> Array:
	var out: Array = []
	var bound: float = 1.5 + 1.0 + (0.5 + 0.3) * detail
	for i in range(segments):
		var angle: float = (float(i) / float(segments)) * TAU
		var w := 0.0
		w += sin(angle * 2.0 + seed_val) * 1.5
		w += sin(angle * 3.0 + seed_val * 0.7) * 1.0
		w += sin(angle * 5.0 + seed_val * 1.3) * 0.5 * detail
		w += sin(angle * 7.0 + seed_val * 0.4) * 0.3 * detail
		out.append(clampf((w + bound) / (2.0 * bound), 0.0, 1.0) * amplitude)
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

## Alturas de la maqueta (docs/21 §12). El cesped esta en y=0 (la rejilla, los
## rayos del raton y los edificios cuentan con ello); su canto baja hasta
## CLIFF_BOTTOM; la playa empieza mas abajo y desciende hacia el mar, y el agua
## la corta: donde se cruzan va la espuma.
const GRASS_Y := 0.0
const CLIFF_BOTTOM := -0.6
const BEACH_TOP_Y := -0.28
const BEACH_BOTTOM_Y := -0.9
const WATER_Y := -0.5
const FOAM_INNER := 0.35
const FOAM_OUTER := 1.9

## Nodos que genera esta isla (para quitarlos al rehacerla).
const NODE_NAMES := ["Ground", "Cliff", "Shore", "Foam", "Water"]

## Fraccion del ancho de playa en la que el agua corta la arena.
static func waterline_t() -> float:
	return (BEACH_TOP_Y - WATER_Y) / (BEACH_TOP_Y - BEACH_BOTTOM_Y)

func _generate_island() -> void:
	_regen_queued = false
	# La escena ya se fue (ViewRouter la cambio por la vista 2D antes de este
	# call_deferred): no hay isla que generar.
	if not is_inside_tree():
		return
	# Remove old static meshes from Main if they exist (and the ones this
	# generator made before the grid changed size). Out of the tree right away,
	# so the new nodes keep their names.
	var main := get_tree().current_scene
	if main == null:
		return
	for old in _made:
		if is_instance_valid(old):
			if old.get_parent() != null:
				old.get_parent().remove_child(old)
			old.queue_free()
	_made.clear()
	for node_name in NODE_NAMES:
		var old := main.get_node_or_null(node_name)
		if old:
			main.remove_child(old)
			old.queue_free()

	var half := grid_half_extents()
	var water_at: float = shore_width * waterline_t()

	# El mar: un plano enorme por debajo de todo, el primero (queda detras).
	var water_node := MeshInstance3D.new()
	water_node.name = "Water"
	var water_plane := PlaneMesh.new()
	water_plane.size = Vector2(400, 400)
	water_node.mesh = water_plane
	water_node.set_surface_override_material(0, _shader_material("water_border", {
		"island_half": Vector2(half.x + land_margin + water_at, half.y + land_margin + water_at),
		"island_radius": corner_radius + water_at,
	}))
	water_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_node.position.y = WATER_Y
	main.add_child(water_node)

	# La playa: un anillo que baja del pie del canto hasta debajo del agua.
	var shore_node := MeshInstance3D.new()
	shore_node.name = "Shore"
	shore_node.mesh = _build_ring_mesh(0.0, BEACH_TOP_Y, shore_width, BEACH_BOTTOM_Y)
	shore_node.set_surface_override_material(0, _shader_material("island_sand", {"water_y": WATER_Y}))
	main.add_child(shore_node)

	# El canto de la maqueta: del borde del cesped hacia abajo.
	var cliff_node := MeshInstance3D.new()
	cliff_node.name = "Cliff"
	cliff_node.mesh = _build_skirt_mesh(GRASS_Y, CLIFF_BOTTOM)
	cliff_node.set_surface_override_material(0, _shader_material("island_cliff", {"top_y": GRASS_Y}))
	main.add_child(cliff_node)

	# La espuma, justo encima del agua y siguiendo la costa exacta.
	var foam_node := MeshInstance3D.new()
	foam_node.name = "Foam"
	foam_node.mesh = _build_ring_mesh(water_at - FOAM_INNER, WATER_Y + 0.02, water_at + FOAM_OUTER, WATER_Y + 0.02)
	foam_node.set_surface_override_material(0, _shader_material("island_foam", {}))
	foam_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(foam_node)

	# Grass island (main ground)
	var grass_node := MeshInstance3D.new()
	grass_node.name = "Ground"
	grass_node.mesh = _build_island_mesh(0.0, GRASS_Y)
	grass_node.set_surface_override_material(0, _create_grass_material())
	main.add_child(grass_node)
	_made = [water_node, shore_node, cliff_node, foam_node, grass_node]

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

## Anillo entre el borde de la isla crecido `expand_in` (a altura y_in) y el
## crecido `expand_out` (a y_out). UV.x: distancia recorrida a lo largo de la
## costa; UV.y: 0 dentro, 1 fuera. Para la playa y la espuma.
func _build_ring_mesh(expand_in: float, y_in: float, expand_out: float, y_out: float) -> ArrayMesh:
	var half := grid_half_extents()
	var inner := border_points(half.x, half.y, land_margin, corner_radius, _border_offsets, expand_in)
	var outer := border_points(half.x, half.y, land_margin, corner_radius, _border_offsets, expand_out)
	var n: int = inner.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	for i in range(n):
		var j := (i + 1) % n
		var step: float = inner[i].distance_to(inner[j])
		var verts := [
			[Vector3(inner[i].x, y_in, inner[i].y), Vector2(along, 0.0)],
			[Vector3(outer[i].x, y_out, outer[i].y), Vector2(along, 1.0)],
			[Vector3(outer[j].x, y_out, outer[j].y), Vector2(along + step, 1.0)],
			[Vector3(inner[i].x, y_in, inner[i].y), Vector2(along, 0.0)],
			[Vector3(outer[j].x, y_out, outer[j].y), Vector2(along + step, 1.0)],
			[Vector3(inner[j].x, y_in, inner[j].y), Vector2(along + step, 0.0)],
		]
		for v in verts:
			st.set_uv(v[1])
			st.add_vertex(v[0])
		along += step
	st.generate_normals()
	return st.commit()

## El canto: una pared del borde del cesped (y_top) hasta y_bottom, mirando
## hacia fuera.
func _build_skirt_mesh(y_top: float, y_bottom: float) -> ArrayMesh:
	var half := grid_half_extents()
	var pts := border_points(half.x, half.y, land_margin, corner_radius, _border_offsets, 0.0)
	var n: int = pts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	for i in range(n):
		var j := (i + 1) % n
		var step: float = pts[i].distance_to(pts[j])
		var ni := Vector3(pts[i].x, 0.0, pts[i].y).normalized()
		var nj := Vector3(pts[j].x, 0.0, pts[j].y).normalized()
		var top_i := Vector3(pts[i].x, y_top, pts[i].y)
		var bot_i := Vector3(pts[i].x, y_bottom, pts[i].y)
		var top_j := Vector3(pts[j].x, y_top, pts[j].y)
		var bot_j := Vector3(pts[j].x, y_bottom, pts[j].y)
		var verts := [
			[top_i, ni, Vector2(along, 0.0)], [bot_i, ni, Vector2(along, 1.0)], [bot_j, nj, Vector2(along + step, 1.0)],
			[top_i, ni, Vector2(along, 0.0)], [bot_j, nj, Vector2(along + step, 1.0)], [top_j, nj, Vector2(along + step, 0.0)],
		]
		for v in verts:
			st.set_normal(v[1])
			st.set_uv(v[2])
			st.add_vertex(v[0])
		along += step
	return st.commit()

## Un ShaderMaterial con el shader `shader_name` de scripts/map y sus parametros.
## Todos llevan `storm_weight` (storm_grade.gdshaderinc): nacen con el peso de
## Tormenta que tenga StormSky ahora, asi que rehacer la isla a media tormenta
## (grid_resized, recarga) no la devuelve limpia. Luego StormSky los funde.
## Lo mismo con `night_weight`: una isla rehecha de noche nace de noche.
func _shader_material(shader_name: String, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/map/%s.gdshader" % shader_name) as Shader
	for key in params:
		m.set_shader_parameter(key, params[key])
	m.set_shader_parameter("storm_weight", StormSky.get_island_weight())
	m.set_shader_parameter("night_weight", StormSky.get_island_night_weight())
	# Version sencilla en calidad baja o minima (WorldLook, hermano en Main).
	var look := get_parent().get_node_or_null("WorldEnvironment") if get_parent() != null else null
	if look != null and look.has_method("island_simple"):
		m.set_shader_parameter("simple", look.island_simple())
	return m

func _create_grass_material() -> ShaderMaterial:
	return _shader_material("grass_ground", {})
