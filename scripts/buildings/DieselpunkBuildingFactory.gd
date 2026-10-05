class_name DieselpunkBuildingFactory
## Generates procedural dieselpunk 3D meshes for each building type.
## Each building has a distinct silhouette with industrial details:
## smokestacks, pipes, riveted panels, gears, glowing elements.

# ── Material palette ──

# CC0 metal-plate maps (Poly Haven) shared by every metal surface. We keep each
# material's albedo_color (preserving the dieselpunk palette) and only add the
# normal + roughness maps, so flat primitives gain plate relief and varied
# reflections instead of looking like solid-color boxes.
const TEX_METAL_ROUGH := "res://assets/textures/metal_plate_rough_1k.jpg"
const TEX_METAL_NORMAL := "res://assets/textures/metal_plate_nor_gl_1k.jpg"

static var _tex_rough: Texture2D
static var _tex_normal: Texture2D
static var _tex_ready := false

## Loads a texture robustly: the imported resource if present (export-safe),
## otherwise the raw image bytes so it works before Godot reimports.
static func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
	return null

static func _ensure_textures() -> void:
	if _tex_ready:
		return
	_tex_ready = true
	_tex_rough = _load_tex(TEX_METAL_ROUGH)
	_tex_normal = _load_tex(TEX_METAL_NORMAL)

static func _metal(color: Color, metallic: float = 0.7, roughness: float = 0.45) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	_ensure_textures()
	if _tex_rough:
		mat.roughness_texture = _tex_rough
		mat.uv1_scale = Vector3(1.6, 1.6, 1.6)
	if _tex_normal:
		mat.normal_enabled = true
		mat.normal_texture = _tex_normal
		mat.normal_scale = 0.8
	return mat

static func _emissive(color: Color, energy: float = 1.5) -> StandardMaterial3D:
	# Plain material (no plate maps) so glowing glass/fire/steam stays clean.
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.0
	mat.roughness = 0.9
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat

# Common dieselpunk colors
static var COL_DARK_IRON: Color = Color(0.22, 0.20, 0.22)
static var COL_GUNMETAL: Color = Color(0.30, 0.30, 0.33)
static var COL_BRASS: Color = Color(0.72, 0.58, 0.20)
static var COL_COPPER: Color = Color(0.65, 0.38, 0.22)
static var COL_RUST: Color = Color(0.50, 0.28, 0.15)
static var COL_DARK_WOOD: Color = Color(0.30, 0.20, 0.10)
static var COL_CONCRETE: Color = Color(0.38, 0.36, 0.34)
static var COL_FIRE: Color = Color(1.0, 0.45, 0.05)
static var COL_STEAM: Color = Color(0.85, 0.88, 0.90)
static var COL_OIL_BLACK: Color = Color(0.10, 0.10, 0.12)
static var COL_OLIVE: Color = Color(0.30, 0.33, 0.18)
static var COL_GOLD_ORE: Color = Color(0.80, 0.65, 0.15)
static var COL_SEARCHLIGHT: Color = Color(1.0, 0.95, 0.7)

# ── Helpers ──

static func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _add_cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: StandardMaterial3D, segments: int = 24) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _add_cone(parent: Node3D, pos: Vector3, bottom_r: float, top_r: float, height: float, mat: StandardMaterial3D, segments: int = 24) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = segments
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _add_prism(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: PrismMesh = PrismMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _add_torus(parent: Node3D, pos: Vector3, inner_r: float, outer_r: float, mat: StandardMaterial3D, rings: int = 24, segments: int = 16) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: TorusMesh = TorusMesh.new()
	mesh.inner_radius = inner_r
	mesh.outer_radius = outer_r
	mesh.rings = rings
	mesh.ring_segments = segments
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _add_sphere(parent: Node3D, pos: Vector3, radius: float, mat: StandardMaterial3D, segments: int = 16) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = maxi(segments / 2, 8)
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi

# Rivet strip: a row of small spheres along an edge
static func _add_rivets(parent: Node3D, start: Vector3, end: Vector3, count: int = 8, radius: float = 0.04) -> void:
	var mat: StandardMaterial3D = _metal(COL_BRASS, 0.9, 0.3)
	for i in range(count):
		var t: float = float(i) / float(count - 1) if count > 1 else 0.5
		var pos: Vector3 = start.lerp(end, t)
		_add_sphere(parent, pos, radius, mat)

# Horizontal pipe between two points
static func _add_pipe(parent: Node3D, from: Vector3, to: Vector3, radius: float, mat: StandardMaterial3D) -> void:
	var mid: Vector3 = (from + to) * 0.5
	var diff: Vector3 = to - from
	var length: float = diff.length()
	var mi: MeshInstance3D = _add_cylinder(parent, mid, radius, length, mat)
	# Orient pipe along the direction
	if absf(diff.y) < 0.001:
		if absf(diff.x) > absf(diff.z):
			mi.rotation.z = PI / 2.0
		else:
			mi.rotation.x = PI / 2.0
	# Vertical pipes need no rotation (default cylinder is vertical)

# ── BUILDING GENERATORS ──

static func create(building_id: String, cell_size: float, grid_size: Vector2i) -> Node3D:
	var sx: float = grid_size.x * cell_size * 0.9
	var sz: float = grid_size.y * cell_size * 0.9
	match building_id:
		"nucleo": return _build_nucleo(sx, sz)
		"headquarters": return _build_headquarters(sx, sz)
		"barracks": return _build_barracks(sx, sz)
		"gold_mine": return _build_gold_mine(sx, sz)
		"foundry": return _build_foundry(sx, sz)
		"refinery": return _build_refinery(sx, sz)
		"sawmill": return _build_sawmill(sx, sz)
		"tower": return _build_tower(sx, sz)
		"warehouse": return _build_warehouse(sx, sz)
		"market": return _build_market(sx, sz)
		"laboratory": return _build_laboratory(sx, sz)
		"house": return _build_house(sx, sz)
		"garden": return _build_garden(sx, sz)
		"fountain": return _build_fountain(sx, sz)
		"statue": return _build_statue(sx, sz)
		"road": return _build_road(sx, sz, 0)
	return null

## Create a road mesh with neighbor connectivity.
## neighbors is a bitmask: NORTH=1, EAST=2, SOUTH=4, WEST=8
static func create_road(cell_size: float, neighbors: int = 0) -> Node3D:
	# La celda entera (2026-09-28): dos tramos vecinos se tocan y la red se lee
	# como una sola carretera, no como losas sueltas con cesped entre medias.
	return _build_road(cell_size, cell_size, neighbors)


# ════════════════════════════════════════════════════════════════
# NUCLEO — Monumental dieselpunk imperial citadel
# Tiered fortress with central dome, four corner towers,
# grand columned entrance, industrial pipes, gears, searchlights
# ════════════════════════════════════════════════════════════════

## Final scale of the Nucleo mesh (A12). The owner wants "the town hall" to
## dominate the view: it is the one building that never falls and the heart of
## the lore, so it has to read as such from the default camera. Only the MESH is
## scaled — the 3x3 footprint, the grid cells and the click hit-test are
## untouched. XZ stays close to 1 so the base does not spill onto neighbouring
## cells; the drama comes from height.
## XZ en 1.0 desde el 2026-09-28: alrededor va la acera y la base no la pisa.
const NUCLEO_SCALE := Vector3(1.0, 2.4, 1.0)

static func _build_nucleo(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()

	# ── Materials ──
	var mat_stone := _metal(Color(0.55, 0.50, 0.42), 0.2, 0.7)
	var mat_marble := _metal(Color(0.82, 0.78, 0.72), 0.15, 0.55)
	var mat_iron := _metal(COL_DARK_IRON, 0.85, 0.35)
	var mat_gunmetal := _metal(COL_GUNMETAL, 0.8, 0.4)
	var mat_gold := _metal(Color(0.85, 0.70, 0.15), 0.95, 0.2)
	var mat_brass := _metal(COL_BRASS, 0.9, 0.3)
	var mat_copper := _metal(COL_COPPER, 0.85, 0.35)
	var mat_roof := _metal(Color(0.20, 0.22, 0.25), 0.7, 0.4)
	var mat_neon_cyan := _emissive(Color(0.1, 0.85, 0.9), 2.0)
	var mat_neon_amber := _emissive(Color(1.0, 0.7, 0.1), 2.5)
	var mat_neon_red := _emissive(Color(1.0, 0.15, 0.05), 1.5)
	var mat_window := _emissive(Color(0.25, 0.55, 0.85), 0.8)
	var mat_window_warm := _emissive(Color(0.9, 0.7, 0.3), 0.5)
	var mat_fire := _emissive(COL_FIRE, 2.0)
	var mat_searchlight := _emissive(COL_SEARCHLIGHT, 3.0)

	# ══════════════════════════════════════════════
	# TIER 1 — Massive stepped foundation
	# ══════════════════════════════════════════════
	_add_box(root, Vector3(0, 0.06, 0), Vector3(sx * 1.0, 0.12, sz * 1.0), mat_iron)
	_add_box(root, Vector3(0, 0.18, 0), Vector3(sx * 0.96, 0.12, sz * 0.96), mat_stone)
	_add_box(root, Vector3(0, 0.30, 0), Vector3(sx * 0.92, 0.12, sz * 0.92), mat_iron)
	# Rivets along foundation edges
	_add_rivets(root, Vector3(-sx * 0.48, 0.13, sz * 0.50), Vector3(sx * 0.48, 0.13, sz * 0.50), 14)
	_add_rivets(root, Vector3(-sx * 0.48, 0.13, -sz * 0.50), Vector3(sx * 0.48, 0.13, -sz * 0.50), 14)
	_add_rivets(root, Vector3(-sx * 0.50, 0.13, -sz * 0.48), Vector3(-sx * 0.50, 0.13, sz * 0.48), 14)
	_add_rivets(root, Vector3(sx * 0.50, 0.13, -sz * 0.48), Vector3(sx * 0.50, 0.13, sz * 0.48), 14)

	# ══════════════════════════════════════════════
	# TIER 2 — Main building body (2 stories)
	# ══════════════════════════════════════════════
	_add_box(root, Vector3(0, 1.15, 0), Vector3(sx * 0.78, 1.5, sz * 0.68), mat_marble)
	# Iron band between floors
	_add_box(root, Vector3(0, 1.15, sz * 0.341), Vector3(sx * 0.80, 0.06, 0.02), mat_iron)
	_add_box(root, Vector3(0, 1.15, -sz * 0.341), Vector3(sx * 0.80, 0.06, 0.02), mat_iron)
	_add_box(root, Vector3(sx * 0.391, 1.15, 0), Vector3(0.02, 0.06, sz * 0.70), mat_iron)
	_add_box(root, Vector3(-sx * 0.391, 1.15, 0), Vector3(0.02, 0.06, sz * 0.70), mat_iron)

	# ── Reinforced corners (iron plates) ──
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_add_box(root, Vector3(cx * sx * 0.38, 1.15, cz * sz * 0.33), Vector3(0.12, 1.52, 0.12), mat_gunmetal)

	# ══════════════════════════════════════════════
	# TIER 3 — Grand front portico with 8 columns
	# ══════════════════════════════════════════════
	_add_box(root, Vector3(0, 0.95, sz * 0.40), Vector3(sx * 0.6, 1.2, sz * 0.14), mat_marble)
	# Columns (8 across front)
	var col_count := 8
	var col_spacing: float = sx * 0.54 / float(col_count - 1)
	var col_start_x: float = -sx * 0.27
	for i in range(col_count):
		var cx: float = col_start_x + i * col_spacing
		# Column shaft (fluted look with low segments)
		_add_cylinder(root, Vector3(cx, 1.05, sz * 0.47), 0.06, 1.5, mat_marble)
		# Column base
		_add_box(root, Vector3(cx, 0.28, sz * 0.47), Vector3(0.15, 0.06, 0.15), mat_stone)
		# Gold Corinthian capital
		_add_cone(root, Vector3(cx, 1.82, sz * 0.47), 0.04, 0.09, 0.08, mat_gold)
	# Entablature
	_add_box(root, Vector3(0, 1.90, sz * 0.47), Vector3(sx * 0.62, 0.08, 0.20), mat_marble)
	# Pediment (triangular)
	_add_prism(root, Vector3(0, 2.18, sz * 0.47), Vector3(sx * 0.56, 0.45, 0.18), mat_marble)
	# Gold imperial eagle on pediment
	_add_sphere(root, Vector3(0, 2.20, sz * 0.49), 0.12, mat_gold, 10)
	# Eagle wings (flattened boxes)
	_add_box(root, Vector3(-0.15, 2.22, sz * 0.50), Vector3(0.18, 0.06, 0.03), mat_gold)
	_add_box(root, Vector3(0.15, 2.22, sz * 0.50), Vector3(0.18, 0.06, 0.03), mat_gold)

	# Stairs leading up to portico
	for step in range(4):
		var sy: float = 0.06
		var y: float = 0.08 + step * sy
		var depth: float = sz * 0.08 + step * 0.04
		_add_box(root, Vector3(0, y, sz * 0.50 + depth * 0.5), Vector3(sx * 0.52 - step * 0.02, sy, depth), mat_stone)

	# ══════════════════════════════════════════════
	# CENTRAL DOME — Crowned with spire
	# ══════════════════════════════════════════════
	# Drum base
	_add_cylinder(root, Vector3(0, 2.05, 0), sx * 0.20, 0.2, mat_gunmetal, 16)
	# Dome windows in drum
	for a in range(8):
		var angle: float = a * PI / 4.0
		var dwx: float = sin(angle) * sx * 0.205
		var dwz: float = cos(angle) * sx * 0.205
		_add_box(root, Vector3(dwx, 2.05, dwz), Vector3(0.08, 0.12, 0.02), mat_window)
	# Main dome sphere
	_add_sphere(root, Vector3(0, 2.55, 0), sx * 0.20, mat_roof, 16)
	# Gold ring at dome base
	_add_torus(root, Vector3(0, 2.15, 0), sx * 0.18, sx * 0.21, mat_gold, 16)
	# Lantern on top
	_add_cylinder(root, Vector3(0, 2.90, 0), 0.07, 0.3, mat_gunmetal)
	# Spire
	_add_cone(root, Vector3(0, 3.25, 0), 0.06, 0.01, 0.5, mat_gold)
	# Beacon light at tip
	_add_sphere(root, Vector3(0, 3.55, 0), 0.06, mat_neon_amber)

	# ══════════════════════════════════════════════
	# FOUR CORNER TOWERS — Industrial watchtowers
	# ══════════════════════════════════════════════
	for tx in [-1.0, 1.0]:
		for tz in [-1.0, 1.0]:
			var bx: float = tx * sx * 0.42
			var bz: float = tz * sz * 0.38
			# Tower body (octagonal feel via low-seg cylinder)
			_add_cylinder(root, Vector3(bx, 1.4, bz), 0.22, 2.4, mat_gunmetal)
			# Iron bands
			_add_torus(root, Vector3(bx, 0.5, bz), 0.20, 0.24, mat_iron, 8)
			_add_torus(root, Vector3(bx, 1.8, bz), 0.20, 0.24, mat_iron, 8)
			# Tower windows (2 levels)
			for wlev in [1.0, 1.8]:
				var wdir: Vector3 = Vector3(tx, 0, tz).normalized()
				_add_box(root, Vector3(bx + wdir.x * 0.22, wlev, bz + wdir.z * 0.22), Vector3(0.08, 0.14, 0.08), mat_window_warm)
			# Crenellated tower top
			_add_cylinder(root, Vector3(bx, 2.65, bz), 0.25, 0.1, mat_iron)
			# Conical tower roof
			_add_cone(root, Vector3(bx, 2.95, bz), 0.24, 0.02, 0.5, mat_roof)
			# Searchlight on two front towers
			if tz > 0:
				_add_sphere(root, Vector3(bx, 3.25, bz), 0.05, mat_searchlight)

	# ══════════════════════════════════════════════
	# WINDOWS — Rows of glowing windows on main body
	# ══════════════════════════════════════════════
	# Front face - upper floor (5 windows)
	for i in range(5):
		var wx: float = -sx * 0.28 + i * sx * 0.14
		_add_box(root, Vector3(wx, 1.55, sz * 0.342), Vector3(0.14, 0.25, 0.02), mat_window)
		_add_box(root, Vector3(wx, 1.55, sz * 0.345), Vector3(0.16, 0.02, 0.02), mat_brass)  # lintel
		_add_box(root, Vector3(wx, 1.40, sz * 0.345), Vector3(0.16, 0.02, 0.02), mat_brass)  # sill
	# Front face - lower floor (5 windows)
	for i in range(5):
		var wx: float = -sx * 0.28 + i * sx * 0.14
		_add_box(root, Vector3(wx, 0.75, sz * 0.342), Vector3(0.12, 0.2, 0.02), mat_window_warm)

	# Side windows (3 per side, 2 floors)
	for side in [-1.0, 1.0]:
		for j in range(3):
			var wz: float = -sz * 0.18 + j * sz * 0.18
			_add_box(root, Vector3(side * sx * 0.392, 1.55, wz), Vector3(0.02, 0.25, 0.12), mat_window)
			_add_box(root, Vector3(side * sx * 0.392, 0.75, wz), Vector3(0.02, 0.2, 0.10), mat_window_warm)

	# Back windows
	for i in range(4):
		var wx: float = -sx * 0.24 + i * sx * 0.16
		_add_box(root, Vector3(wx, 1.55, -sz * 0.342), Vector3(0.14, 0.25, 0.02), mat_window)

	# ══════════════════════════════════════════════
	# INDUSTRIAL DETAILS — Pipes, gears, smokestacks
	# ══════════════════════════════════════════════
	# Back smokestacks (2)
	for side in [-1.0, 1.0]:
		var pipe_x: float = side * sx * 0.25
		_add_cylinder(root, Vector3(pipe_x, 2.4, -sz * 0.35), 0.08, 1.0, mat_iron)
		_add_torus(root, Vector3(pipe_x, 2.95, -sz * 0.35), 0.06, 0.10, mat_copper, 8)
		# Smoke cap
		_add_cone(root, Vector3(pipe_x, 3.05, -sz * 0.35), 0.10, 0.12, 0.12, mat_iron)
		# Fire glow inside
		_add_sphere(root, Vector3(pipe_x, 2.90, -sz * 0.35), 0.05, mat_fire)

	# Steam pipes along sides
	for side in [-1.0, 1.0]:
		_add_pipe(root, Vector3(side * sx * 0.40, 0.55, -sz * 0.28), Vector3(side * sx * 0.40, 0.55, sz * 0.28), 0.03, mat_copper)
		_add_pipe(root, Vector3(side * sx * 0.40, 0.45, -sz * 0.28), Vector3(side * sx * 0.40, 0.45, sz * 0.28), 0.025, mat_brass)
		# Pipe joints
		for jz in [-0.15, 0.0, 0.15]:
			_add_torus(root, Vector3(side * sx * 0.40, 0.55, sz * jz), 0.025, 0.045, mat_brass)

	# Gears on back wall (decorative)
	_add_torus(root, Vector3(0, 1.4, -sz * 0.345), 0.12, 0.18, mat_brass, 12)
	_add_torus(root, Vector3(0.22, 1.2, -sz * 0.345), 0.08, 0.12, mat_copper, 10)
	# Gear center pins
	_add_cylinder(root, Vector3(0, 1.4, -sz * 0.34), 0.04, 0.04, mat_iron)
	_add_cylinder(root, Vector3(0.22, 1.2, -sz * 0.34), 0.03, 0.04, mat_iron)

	# ══════════════════════════════════════════════
	# NEON ACCENT LINES — Cyberpunk glow strips
	# ══════════════════════════════════════════════
	# Horizontal cyan strips at roofline
	_add_box(root, Vector3(0, 1.92, sz * 0.343), Vector3(sx * 0.80, 0.025, 0.015), mat_neon_cyan)
	_add_box(root, Vector3(0, 1.92, -sz * 0.343), Vector3(sx * 0.80, 0.025, 0.015), mat_neon_cyan)
	_add_box(root, Vector3(sx * 0.393, 1.92, 0), Vector3(0.015, 0.025, sz * 0.70), mat_neon_cyan)
	_add_box(root, Vector3(-sx * 0.393, 1.92, 0), Vector3(0.015, 0.025, sz * 0.70), mat_neon_cyan)
	# Foundation glow line
	_add_box(root, Vector3(0, 0.37, sz * 0.465), Vector3(sx * 0.90, 0.02, 0.015), mat_neon_cyan)
	_add_box(root, Vector3(0, 0.37, -sz * 0.465), Vector3(sx * 0.90, 0.02, 0.015), mat_neon_cyan)
	# Vertical accent on portico columns (every other)
	for i in [0, 2, 5, 7]:
		var cx: float = col_start_x + i * col_spacing
		_add_box(root, Vector3(cx, 1.05, sz * 0.475), Vector3(0.015, 1.5, 0.015), mat_neon_cyan)
	# Red warning lights on smokestacks
	for side in [-1.0, 1.0]:
		_add_sphere(root, Vector3(side * sx * 0.25, 3.15, -sz * 0.35), 0.035, mat_neon_red)

	# ══════════════════════════════════════════════
	# ROOF — Armored plates with gold trim
	# ══════════════════════════════════════════════
	_add_box(root, Vector3(0, 1.95, 0), Vector3(sx * 0.82, 0.06, sz * 0.72), mat_roof)
	# Gold cornice trim
	_add_box(root, Vector3(0, 1.98, sz * 0.345), Vector3(sx * 0.82, 0.03, 0.04), mat_gold)
	_add_box(root, Vector3(0, 1.98, -sz * 0.345), Vector3(sx * 0.82, 0.03, 0.04), mat_gold)
	_add_box(root, Vector3(sx * 0.395, 1.98, 0), Vector3(0.04, 0.03, sz * 0.70), mat_gold)
	_add_box(root, Vector3(-sx * 0.395, 1.98, 0), Vector3(0.04, 0.03, sz * 0.70), mat_gold)

	# ══════════════════════════════════════════════
	# ENTRANCE DETAILS — Door, banners, lamps
	# ══════════════════════════════════════════════
	# Grand doorway
	_add_box(root, Vector3(0, 0.7, sz * 0.345), Vector3(0.3, 0.8, 0.04), mat_iron)
	_add_box(root, Vector3(0, 1.12, sz * 0.345), Vector3(0.34, 0.04, 0.05), mat_gold)  # lintel
	# Door glow
	_add_box(root, Vector3(0, 0.7, sz * 0.35), Vector3(0.26, 0.7, 0.01), mat_window_warm)

	# Lanterns flanking entrance
	for side in [-1.0, 1.0]:
		_add_cylinder(root, Vector3(side * 0.25, 0.8, sz * 0.50), 0.02, 0.4, mat_iron)
		_add_sphere(root, Vector3(side * 0.25, 1.05, sz * 0.50), 0.04, mat_neon_amber)

	# Scale the entire citadel up to be imposing (see NUCLEO_SCALE)
	root.scale = NUCLEO_SCALE
	return root


# ════════════════════════════════════════════════════════════════
# HEADQUARTERS — Command bunker with radio tower, armored walls
# ════════════════════════════════════════════════════════════════
static func _build_headquarters(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_walls: StandardMaterial3D = _metal(COL_GUNMETAL, 0.8, 0.4)
	var mat_dark: StandardMaterial3D = _metal(COL_DARK_IRON, 0.85, 0.35)
	var mat_brass: StandardMaterial3D = _metal(COL_BRASS, 0.9, 0.3)
	var mat_concrete: StandardMaterial3D = _metal(COL_CONCRETE, 0.2, 0.8)

	# Main armored body — thick, squat bunker
	_add_box(root, Vector3(0, 1.2, 0), Vector3(sx * 0.85, 2.4, sz * 0.85), mat_walls)

	# Reinforced base plinth
	_add_box(root, Vector3(0, 0.15, 0), Vector3(sx * 0.95, 0.3, sz * 0.95), mat_concrete)

	# Armored roof slab (slightly smaller, darker)
	_add_box(root, Vector3(0, 2.45, 0), Vector3(sx * 0.78, 0.12, sz * 0.78), mat_dark)

	# Observation deck on top
	_add_box(root, Vector3(0, 2.7, 0), Vector3(sx * 0.4, 0.4, sz * 0.4), mat_dark)
	# Observation windows (brass strips)
	_add_box(root, Vector3(0, 2.85, sz * 0.21), Vector3(sx * 0.35, 0.1, 0.02), mat_brass)
	_add_box(root, Vector3(0, 2.85, -sz * 0.21), Vector3(sx * 0.35, 0.1, 0.02), mat_brass)
	_add_box(root, Vector3(sx * 0.21, 2.85, 0), Vector3(0.02, 0.1, sz * 0.35), mat_brass)

	# Radio/antenna tower (tall mast on one corner)
	var tower_x: float = sx * 0.32
	var tower_z: float = -sz * 0.32
	_add_cylinder(root, Vector3(tower_x, 3.5, tower_z), 0.06, 2.5, mat_dark)
	_add_cylinder(root, Vector3(tower_x, 4.6, tower_z), 0.03, 0.8, mat_brass)
	# Antenna crossbars
	_add_box(root, Vector3(tower_x, 4.2, tower_z), Vector3(0.5, 0.03, 0.03), mat_brass)
	_add_box(root, Vector3(tower_x, 4.5, tower_z), Vector3(0.35, 0.03, 0.03), mat_brass)
	# Blinking light at top
	_add_sphere(root, Vector3(tower_x, 5.05, tower_z), 0.06, _emissive(Color(1, 0.2, 0.1), 2.0))

	# Side armor plates (angled reinforcement)
	_add_box(root, Vector3(sx * 0.44, 0.8, 0), Vector3(0.08, 1.2, sz * 0.6), mat_dark)
	_add_box(root, Vector3(-sx * 0.44, 0.8, 0), Vector3(0.08, 1.2, sz * 0.6), mat_dark)

	# Rivets along top edge
	_add_rivets(root, Vector3(-sx * 0.4, 2.42, sz * 0.4), Vector3(sx * 0.4, 2.42, sz * 0.4))
	_add_rivets(root, Vector3(-sx * 0.4, 2.42, -sz * 0.4), Vector3(sx * 0.4, 2.42, -sz * 0.4))

	# Exhaust pipes on back
	_add_cylinder(root, Vector3(-sx * 0.25, 2.8, -sz * 0.4), 0.08, 0.5, mat_copper())
	_add_cylinder(root, Vector3(-sx * 0.1, 2.8, -sz * 0.4), 0.08, 0.5, mat_copper())

	# Door (dark recessed area on front)
	_add_box(root, Vector3(0, 0.7, sz * 0.43), Vector3(sx * 0.25, 1.2, 0.06), mat_dark)
	# Door handle/lock
	_add_sphere(root, Vector3(sx * 0.08, 0.7, sz * 0.46), 0.04, mat_brass)

	return root

static func mat_copper() -> StandardMaterial3D:
	return _metal(COL_COPPER, 0.85, 0.35)


# ════════════════════════════════════════════════════════════════
# BARRACKS — Military bunker, low and wide with sandbags
# ════════════════════════════════════════════════════════════════
static func _build_barracks(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_walls: StandardMaterial3D = _metal(COL_OLIVE, 0.3, 0.7)
	var mat_iron: StandardMaterial3D = _metal(COL_DARK_IRON, 0.8, 0.4)
	var mat_brass: StandardMaterial3D = _metal(COL_BRASS, 0.9, 0.3)
	var mat_sand: StandardMaterial3D = _metal(Color(0.55, 0.48, 0.32), 0.1, 0.9)

	# Main bunker body — low, wide
	_add_box(root, Vector3(0, 0.9, 0), Vector3(sx * 0.9, 1.8, sz * 0.8), mat_walls)

	# Corrugated roof (slightly arched look with layered boxes)
	_add_box(root, Vector3(0, 1.85, 0), Vector3(sx * 0.92, 0.08, sz * 0.85), mat_iron)
	_add_box(root, Vector3(0, 1.93, 0), Vector3(sx * 0.8, 0.06, sz * 0.75), mat_iron)

	# Chimney / ventilation stack
	_add_cylinder(root, Vector3(sx * 0.25, 2.3, -sz * 0.15), 0.1, 0.7, mat_iron)
	_add_cone(root, Vector3(sx * 0.25, 2.7, -sz * 0.15), 0.14, 0.06, 0.15, mat_iron)

	# Sandbag walls (front)
	for i in range(4):
		var x_off: float =-sx * 0.3 + i * sx * 0.2
		_add_box(root, Vector3(x_off, 0.2, sz * 0.48), Vector3(sx * 0.18, 0.35, 0.25), mat_sand)
	# Second row of sandbags
	for i in range(3):
		var x_off: float =-sx * 0.2 + i * sx * 0.2
		_add_box(root, Vector3(x_off, 0.5, sz * 0.48), Vector3(sx * 0.18, 0.25, 0.2), mat_sand)

	# Corner watchtower post
	var wt_x: float = -sx * 0.38
	var wt_z: float = -sz * 0.38
	_add_cylinder(root, Vector3(wt_x, 1.5, wt_z), 0.06, 3.0, mat_iron)
	_add_box(root, Vector3(wt_x, 2.9, wt_z), Vector3(0.5, 0.05, 0.5), mat_iron)
	# Spotlight on watchtower
	_add_cone(root, Vector3(wt_x, 3.1, wt_z + 0.15), 0.12, 0.04, 0.2, _emissive(COL_SEARCHLIGHT, 1.0))

	# Iron reinforcement strips on walls
	_add_box(root, Vector3(0, 0.5, sz * 0.41), Vector3(sx * 0.85, 0.06, 0.02), mat_iron)
	_add_box(root, Vector3(0, 1.3, sz * 0.41), Vector3(sx * 0.85, 0.06, 0.02), mat_iron)

	# Rivets
	_add_rivets(root, Vector3(-sx * 0.35, 1.82, sz * 0.42), Vector3(sx * 0.35, 1.82, sz * 0.42))

	# Door
	_add_box(root, Vector3(sx * 0.15, 0.7, sz * 0.42), Vector3(sx * 0.2, 1.2, 0.04), mat_iron)

	# Flag pole
	_add_cylinder(root, Vector3(sx * 0.38, 2.0, sz * 0.38), 0.03, 2.0, mat_iron)
	_add_box(root, Vector3(sx * 0.38 + 0.15, 2.85, sz * 0.38), Vector3(0.25, 0.15, 0.02), _metal(Color(0.7, 0.15, 0.1), 0.1, 0.8))

	return root


# ════════════════════════════════════════════════════════════════
# GOLD MINE — Headframe tower, ore cart, conveyor
# ════════════════════════════════════════════════════════════════
static func _build_gold_mine(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_wood: StandardMaterial3D = _metal(COL_DARK_WOOD, 0.1, 0.85)
	var mat_iron: StandardMaterial3D = _metal(COL_DARK_IRON, 0.8, 0.4)
	var mat_gold: StandardMaterial3D = _metal(COL_GOLD_ORE, 0.9, 0.3)
	var mat_rust: StandardMaterial3D = _metal(COL_RUST, 0.6, 0.6)

	# Mine shaft entrance — dark recessed opening
	_add_box(root, Vector3(0, 0.4, sz * 0.2), Vector3(sx * 0.35, 0.8, sz * 0.15), mat_iron)
	_add_box(root, Vector3(0, 0.35, sz * 0.28), Vector3(sx * 0.25, 0.5, 0.08), _metal(Color(0.05, 0.05, 0.05), 0.0, 1.0))

	# Headframe tower (A-frame) — tall triangular structure
	var hf_h: float = 3.2
	# Four support beams as angled cylinders
	_add_cylinder(root, Vector3(-sx * 0.12, hf_h * 0.5, sz * 0.1), 0.06, hf_h, mat_iron)
	_add_cylinder(root, Vector3(sx * 0.12, hf_h * 0.5, sz * 0.1), 0.06, hf_h, mat_iron)
	_add_cylinder(root, Vector3(-sx * 0.12, hf_h * 0.5, -sz * 0.05), 0.06, hf_h, mat_iron)
	_add_cylinder(root, Vector3(sx * 0.12, hf_h * 0.5, -sz * 0.05), 0.06, hf_h, mat_iron)
	# Crossbeams
	_add_box(root, Vector3(0, hf_h * 0.35, sz * 0.025), Vector3(sx * 0.28, 0.04, sz * 0.18), mat_iron)
	_add_box(root, Vector3(0, hf_h * 0.7, sz * 0.025), Vector3(sx * 0.28, 0.04, sz * 0.18), mat_iron)
	# Pulley wheel at top
	_add_torus(root, Vector3(0, hf_h + 0.1, sz * 0.025), 0.08, 0.18, mat_rust, 10)
	# Top platform
	_add_box(root, Vector3(0, hf_h - 0.1, sz * 0.025), Vector3(sx * 0.3, 0.06, sz * 0.2), mat_iron)

	# Engine house (small building beside headframe)
	_add_box(root, Vector3(-sx * 0.3, 0.6, -sz * 0.2), Vector3(sx * 0.3, 1.2, sz * 0.35), mat_rust)
	_add_prism(root, Vector3(-sx * 0.3, 1.3, -sz * 0.2), Vector3(sx * 0.32, 0.4, sz * 0.37), mat_iron)
	# Smokestack on engine house
	_add_cylinder(root, Vector3(-sx * 0.35, 1.8, -sz * 0.25), 0.08, 0.8, mat_iron)
	_add_sphere(root, Vector3(-sx * 0.35, 2.25, -sz * 0.25), 0.06, _emissive(COL_STEAM, 0.5))

	# Ore cart on rails
	_add_box(root, Vector3(sx * 0.25, 0.2, sz * 0.3), Vector3(0.3, 0.2, 0.2), mat_rust)
	# Cart wheels
	_add_cylinder(root, Vector3(sx * 0.2, 0.08, sz * 0.3), 0.06, 0.05, mat_iron)
	_add_cylinder(root, Vector3(sx * 0.3, 0.08, sz * 0.3), 0.06, 0.05, mat_iron)
	# Gold ore pile in cart
	_add_sphere(root, Vector3(sx * 0.25, 0.35, sz * 0.3), 0.1, mat_gold)

	# Rail tracks
	_add_box(root, Vector3(sx * 0.1, 0.02, sz * 0.25), Vector3(sx * 0.6, 0.03, 0.03), mat_iron)
	_add_box(root, Vector3(sx * 0.1, 0.02, sz * 0.35), Vector3(sx * 0.6, 0.03, 0.03), mat_iron)

	# Ore pile on ground
	_add_sphere(root, Vector3(sx * 0.3, 0.15, -sz * 0.3), 0.2, mat_gold)
	_add_sphere(root, Vector3(sx * 0.22, 0.1, -sz * 0.25), 0.15, mat_gold)

	return root


# ════════════════════════════════════════════════════════════════
# FOUNDRY — Blast furnace with glowing interior, smokestacks
# ════════════════════════════════════════════════════════════════
static func _build_foundry(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_iron: StandardMaterial3D = _metal(COL_DARK_IRON, 0.85, 0.35)
	var mat_rust: StandardMaterial3D = _metal(COL_RUST, 0.6, 0.55)
	var mat_fire: StandardMaterial3D = _emissive(COL_FIRE, 2.5)
	var mat_brass: StandardMaterial3D = _metal(COL_BRASS, 0.9, 0.3)
	var mat_copper: StandardMaterial3D = mat_copper()

	# Main furnace body — large cylinder
	_add_cylinder(root, Vector3(-sx * 0.1, 1.1, 0), 0.55, 2.2, mat_iron, 10)
	# Furnace belly ring (wider middle)
	_add_torus(root, Vector3(-sx * 0.1, 0.8, 0), 0.5, 0.62, mat_rust, 10, 10)
	# Furnace opening — glowing
	_add_cylinder(root, Vector3(-sx * 0.1, 0.15, sz * 0.35), 0.2, 0.3, mat_fire)

	# Large smokestack
	_add_cylinder(root, Vector3(-sx * 0.1, 2.8, 0), 0.2, 1.2, mat_iron)
	_add_cone(root, Vector3(-sx * 0.1, 3.5, 0), 0.25, 0.15, 0.25, mat_iron)
	# Smoke glow
	_add_sphere(root, Vector3(-sx * 0.1, 3.7, 0), 0.12, _emissive(COL_STEAM, 0.8))

	# Second smaller stack
	_add_cylinder(root, Vector3(sx * 0.15, 2.5, -sz * 0.1), 0.12, 0.8, mat_rust)

	# Anvil platform / work area
	_add_box(root, Vector3(sx * 0.25, 0.5, 0), Vector3(sx * 0.4, 1.0, sz * 0.7), mat_rust)
	# Anvil
	_add_box(root, Vector3(sx * 0.3, 1.1, sz * 0.05), Vector3(0.25, 0.15, 0.12), mat_iron)

	# Pipe from furnace to work area
	_add_pipe(root, Vector3(0.1, 1.5, 0), Vector3(sx * 0.25, 1.5, 0), 0.06, mat_copper)

	# Bellows (accordion shape using stacked boxes)
	_add_box(root, Vector3(-sx * 0.35, 0.6, sz * 0.2), Vector3(0.2, 0.5, 0.2), mat_rust)
	_add_box(root, Vector3(-sx * 0.35, 0.6, sz * 0.2), Vector3(0.25, 0.08, 0.25), mat_iron)
	_add_box(root, Vector3(-sx * 0.35, 0.75, sz * 0.2), Vector3(0.25, 0.08, 0.25), mat_iron)

	# Rivets on furnace base
	_add_rivets(root, Vector3(-sx * 0.1 - 0.5, 0.3, -0.2), Vector3(-sx * 0.1 + 0.5, 0.3, -0.2))

	# Molten metal channel on ground (glowing line)
	_add_box(root, Vector3(sx * 0.08, 0.04, sz * 0.15), Vector3(0.4, 0.04, 0.06), mat_fire)

	# Gear on side
	_add_torus(root, Vector3(-sx * 0.1, 1.5, -sz * 0.38), 0.1, 0.2, mat_brass, 8)

	return root


# ════════════════════════════════════════════════════════════════
# REFINERY — Distillation towers, pipe maze, storage tanks
# ════════════════════════════════════════════════════════════════
static func _build_refinery(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_iron: StandardMaterial3D = _metal(COL_DARK_IRON, 0.85, 0.35)
	var mat_oil: StandardMaterial3D = _metal(COL_OIL_BLACK, 0.7, 0.5)
	var mat_copper: StandardMaterial3D = mat_copper()
	var mat_brass: StandardMaterial3D = _metal(COL_BRASS, 0.9, 0.3)
	var mat_rust: StandardMaterial3D = _metal(COL_RUST, 0.6, 0.55)

	# Main distillation column (tall cylinder)
	_add_cylinder(root, Vector3(-sx * 0.2, 1.8, -sz * 0.15), 0.35, 3.6, mat_iron, 10)
	# Rings on column
	_add_torus(root, Vector3(-sx * 0.2, 1.0, -sz * 0.15), 0.32, 0.40, mat_rust, 8)
	_add_torus(root, Vector3(-sx * 0.2, 2.0, -sz * 0.15), 0.32, 0.40, mat_rust, 8)
	_add_torus(root, Vector3(-sx * 0.2, 3.0, -sz * 0.15), 0.32, 0.40, mat_rust, 8)
	# Column cap
	_add_sphere(root, Vector3(-sx * 0.2, 3.65, -sz * 0.15), 0.35, mat_iron, 10)

	# Secondary smaller column
	_add_cylinder(root, Vector3(sx * 0.1, 1.3, -sz * 0.2), 0.22, 2.6, mat_rust, 10)
	_add_sphere(root, Vector3(sx * 0.1, 2.65, -sz * 0.2), 0.22, mat_rust, 10)

	# Oil storage tank (horizontal cylinder)
	var tank: MeshInstance3D = _add_cylinder(root, Vector3(sx * 0.15, 0.5, sz * 0.2), 0.4, sx * 0.5, mat_oil, 10)
	tank.rotation.z = PI / 2.0
	# Tank supports
	_add_box(root, Vector3(sx * 0.0, 0.15, sz * 0.2), Vector3(0.08, 0.3, 0.5), mat_iron)
	_add_box(root, Vector3(sx * 0.3, 0.15, sz * 0.2), Vector3(0.08, 0.3, 0.5), mat_iron)

	# Pipe network connecting everything
	_add_pipe(root, Vector3(-sx * 0.2, 2.5, -sz * 0.15), Vector3(sx * 0.1, 2.5, -sz * 0.2), 0.04, mat_copper)
	_add_pipe(root, Vector3(sx * 0.1, 1.5, -sz * 0.2), Vector3(sx * 0.1, 1.5, sz * 0.2), 0.04, mat_copper)
	# Vertical pipes
	_add_cylinder(root, Vector3(sx * 0.3, 0.8, -sz * 0.1), 0.04, 1.0, mat_copper)
	_add_cylinder(root, Vector3(-sx * 0.35, 0.6, sz * 0.1), 0.04, 0.8, mat_copper)

	# Valve wheels
	_add_torus(root, Vector3(sx * 0.3, 1.3, -sz * 0.1), 0.04, 0.1, mat_brass, 6)
	_add_torus(root, Vector3(-sx * 0.2, 1.5, sz * 0.06), 0.04, 0.1, mat_brass, 6)

	# Pressure gauge (small disc on pipe)
	_add_cylinder(root, Vector3(sx * 0.1, 2.5, sz * 0.0), 0.08, 0.02, mat_brass)

	# Steam vent
	_add_cylinder(root, Vector3(-sx * 0.2, 3.8, -sz * 0.15), 0.06, 0.3, mat_iron)
	_add_sphere(root, Vector3(-sx * 0.2, 4.0, -sz * 0.15), 0.08, _emissive(COL_STEAM, 0.6))

	# Foundation platform
	_add_box(root, Vector3(0, 0.05, 0), Vector3(sx * 0.95, 0.1, sz * 0.95), _metal(COL_CONCRETE, 0.2, 0.8))

	# Rivets on tank
	_add_rivets(root, Vector3(sx * 0.0, 0.7, sz * 0.58), Vector3(sx * 0.3, 0.7, sz * 0.58))

	return root


# ════════════════════════════════════════════════════════════════
# SAWMILL — Cobertizo ABIERTO (2026-10-04, guia de estilo): tejado de una
# sola agua sobre postes que solo cubre la mitad de atras, cerchas al aire
# delante y ninguna pared en el frente. Desde la camara de 45 grados se ve
# lo que hace: la sierra circular GRANDE (el elemento exagerado, un 30 %
# mas de lo realista), el tronco en la mesa, el tablon recien cortado, la
# pila de tablones, la de troncos y la maquina de vapor que mueve la correa.
# El serrin de "trabajando" sale de la sierra (Marker3D "FxAnchor").
# ════════════════════════════════════════════════════════════════

static var _cached_mats: Dictionary = {}

## Material con mapas de chapa, compartido por nombre (los edificios
## procedurales nuevos no crean uno por pieza).
static func _shared_metal(key: String, color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	if not _cached_mats.has(key):
		_cached_mats[key] = _metal(color, metallic, roughness)
	return _cached_mats[key]

static func _shared_emissive(key: String, color: Color, energy: float) -> StandardMaterial3D:
	if not _cached_mats.has(key):
		_cached_mats[key] = _emissive(color, energy)
	return _cached_mats[key]

## _group(): el de la obra, mas abajo (crea un Node3D con nombre colgado de otro).

static func _build_sawmill(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "SawmillOpen"
	var wood := _shared_metal("saw_wood", Color(0.50, 0.34, 0.18), 0.05, 0.85)
	var dark_wood := _shared_metal("saw_dark_wood", COL_DARK_WOOD, 0.05, 0.9)
	var light_wood := _shared_metal("saw_light_wood", Color(0.74, 0.57, 0.34), 0.05, 0.8)
	var bark := _shared_metal("saw_bark", Color(0.36, 0.24, 0.13), 0.05, 0.95)
	var iron := _shared_metal("saw_iron", COL_DARK_IRON, 0.8, 0.4)
	var roof_mat := _shared_metal("saw_roof", Color(0.42, 0.30, 0.22), 0.6, 0.55)
	# Acero claro y poco metalico: muy metalico refleja el cielo y se ve negro.
	var steel := _shared_metal("saw_steel", Color(0.86, 0.88, 0.9), 0.35, 0.3)
	var red := _shared_metal("saw_red", Color(0.80, 0.16, 0.10), 0.3, 0.5)
	var brass := _shared_metal("saw_brass", COL_BRASS, 0.9, 0.3)
	var fire := _shared_emissive("saw_fire", COL_FIRE, 2.2)
	var hw := minf(sx, 3.2) * 0.5
	var hd := minf(sz, 3.2) * 0.5
	var floor_y := 0.14

	# ── Suelo de tablas ──
	var floor_g := _group(root, "Floor")
	_add_box(floor_g, Vector3(0, floor_y * 0.5, 0), Vector3(hw * 2.0, floor_y, hd * 2.0), wood)
	for i in 7:
		var z := lerpf(-hd + 0.2, hd - 0.2, float(i) / 6.0)
		_add_box(floor_g, Vector3(0, floor_y + 0.005, z), Vector3(hw * 2.0, 0.01, 0.025), dark_wood)

	# ── Cobertizo: postes, media cubierta atras, cerchas al aire delante ──
	var shed := _group(root, "Shed")
	var back_z := -hd + 0.1
	var mid_z := -0.15
	var front_z := hd - 0.15
	var roof_low := 1.85
	var roof_high := 2.35
	var posts := _group(shed, "Posts")
	for x in [-hw + 0.08, 0.0, hw - 0.08]:
		_add_box(posts, Vector3(x, (floor_y + roof_low) * 0.5, back_z), Vector3(0.14, roof_low - floor_y, 0.14), dark_wood)
		_add_box(posts, Vector3(x, (floor_y + roof_high) * 0.5, mid_z), Vector3(0.14, roof_high - floor_y, 0.14), dark_wood)
	for x in [-hw + 0.08, hw - 0.08]:
		_add_box(posts, Vector3(x, (floor_y + roof_high) * 0.5, front_z), Vector3(0.14, roof_high - floor_y, 0.14), dark_wood)
	# Media cubierta de chapa, de una sola agua, solo sobre la mitad de atras.
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	var roof_box := BoxMesh.new()
	var run := mid_z - back_z + 0.3
	var rise := roof_high - roof_low
	roof_box.size = Vector3(hw * 2.0 + 0.2, 0.07, sqrt(run * run + rise * rise))
	roof.mesh = roof_box
	roof.set_surface_override_material(0, roof_mat)
	roof.position = Vector3(0, (roof_low + roof_high) * 0.5 + 0.06, (back_z + mid_z) * 0.5 + 0.05)
	roof.rotation.x = -atan2(rise, run)
	shed.add_child(roof)
	# Ondas de la chapa
	for i in 6:
		var x := lerpf(-hw, hw, (float(i) + 0.5) / 6.0)
		var rib := _add_box(shed, Vector3(x, roof.position.y + 0.05, roof.position.z), Vector3(0.05, 0.04, roof_box.size.z), roof_mat)
		rib.rotation.x = roof.rotation.x
	# Cerchas al aire sobre la sierra: vigas, sin cubierta, dejan ver dentro.
	var rafters := _group(shed, "Rafters")
	_add_box(rafters, Vector3(0, roof_high, front_z), Vector3(hw * 2.0, 0.12, 0.12), dark_wood)
	_add_box(rafters, Vector3(0, roof_high, mid_z), Vector3(hw * 2.0, 0.12, 0.12), dark_wood)
	for x in [-hw + 0.08, -hw * 0.33, hw * 0.33, hw - 0.08]:
		_add_box(rafters, Vector3(x, roof_high + 0.02, (mid_z + front_z) * 0.5), Vector3(0.09, 0.09, front_z - mid_z), wood)
	# Pared de atras y media pared en el lado izquierdo (solo detras): el
	# frente, abierto.
	var back_wall := _add_box(shed, Vector3(0, (floor_y + roof_low) * 0.5, back_z - 0.02), Vector3(hw * 2.0, roof_low - floor_y, 0.08), wood)
	back_wall.name = "BackWall"
	var side_wall := _add_box(shed, Vector3(-hw + 0.02, (floor_y + roof_low) * 0.5, (back_z + mid_z) * 0.5), Vector3(0.08, roof_low - floor_y, mid_z - back_z), wood)
	side_wall.name = "SideWall"
	for i in 5:
		var y := floor_y + 0.3 + 0.3 * i
		_add_box(shed, Vector3(0, y, back_z + 0.03), Vector3(hw * 2.0, 0.02, 0.02), dark_wood)

	# ── La sierra: mesa larga, tronco, tablon cortado y la hoja grande ──
	var saw := _group(root, "Saw")
	var table_z := 0.42
	var table_y := 0.78
	var table := _add_box(saw, Vector3(0, table_y, table_z), Vector3(hw * 1.7, 0.1, 0.62), iron)
	table.name = "SawTable"
	for x in [-hw * 0.75, hw * 0.75]:
		for dz in [-0.24, 0.24]:
			_add_box(saw, Vector3(x, (floor_y + table_y) * 0.5, table_z + dz), Vector3(0.08, table_y - floor_y, 0.08), iron)
	# Franja roja de aviso a los dos lados de la hoja
	_add_box(saw, Vector3(0, table_y + 0.055, table_z + 0.27), Vector3(0.9, 0.012, 0.05), red)
	_add_box(saw, Vector3(0, table_y + 0.055, table_z - 0.27), Vector3(0.9, 0.012, 0.05), red)
	# Tronco entrando por la izquierda
	var log_r := 0.22
	var log_node := _add_cylinder(saw, Vector3(-hw * 0.42, table_y + 0.05 + log_r, table_z), log_r, hw * 0.75, bark, 10)
	log_node.rotation.z = PI / 2.0
	log_node.name = "Log"
	var end_cap := _add_cylinder(saw, Vector3(-hw * 0.42 - hw * 0.375 - 0.005, table_y + 0.05 + log_r, table_z), log_r * 0.85, 0.02, light_wood, 10)
	end_cap.rotation.z = PI / 2.0
	# Tablon recien cortado saliendo por la derecha
	var plank := _add_box(saw, Vector3(hw * 0.45, table_y + 0.09, table_z), Vector3(hw * 0.7, 0.07, 0.36), light_wood)
	plank.name = "CutPlank"
	# La hoja: un disco vertical de frente a la camara, con dientes y buje rojo.
	var blade_r := 0.88
	var blade_c := Vector3(0.0, table_y + 0.16, table_z)
	var blade := _group(saw, "SawBlade")
	blade.position = blade_c
	var disc := _add_cylinder(blade, Vector3.ZERO, blade_r, 0.035, steel, 28)
	disc.rotation.x = PI / 2.0
	var inner := _add_cylinder(blade, Vector3(0, 0, 0.02), blade_r * 0.62, 0.01, _shared_metal("saw_steel_dark", Color(0.62, 0.64, 0.68), 0.35, 0.35), 24)
	inner.rotation.x = PI / 2.0
	for i in 22:
		var a := TAU * float(i) / 22.0
		var tooth := _add_box(blade, Vector3(cos(a), sin(a), 0) * (blade_r + 0.05), Vector3(0.13, 0.09, 0.045), steel)
		tooth.rotation.z = a + 0.5
	var hub := _add_cylinder(blade, Vector3.ZERO, 0.24, 0.12, red, 12)
	hub.rotation.x = PI / 2.0
	var cap := _add_cylinder(blade, Vector3(0, 0, 0.07), 0.06, 0.02, brass, 8)
	cap.rotation.x = PI / 2.0
	# Eje, polea y correa hasta la maquina de vapor del fondo
	var axle := _add_cylinder(saw, blade_c + Vector3(0, 0, -0.45), 0.05, 0.9, iron, 8)
	axle.rotation.x = PI / 2.0
	var pulley := _add_cylinder(saw, blade_c + Vector3(0, 0, -0.75), 0.22, 0.1, brass, 12)
	pulley.rotation.x = PI / 2.0
	var engine := _group(root, "SteamEngine")
	var eng_c := Vector3(hw * 0.5, floor_y, back_z + 0.55)
	var boiler := _add_cylinder(engine, eng_c + Vector3(0, 0.42, 0), 0.32, 0.9, iron, 12)
	boiler.rotation.z = PI / 2.0
	_add_box(engine, eng_c + Vector3(-0.55, 0.3, 0), Vector3(0.3, 0.6, 0.5), iron)
	_add_box(engine, eng_c + Vector3(-0.55, 0.25, 0.26), Vector3(0.16, 0.14, 0.02), fire)
	var belt_from := blade_c + Vector3(0, 0, -0.75)
	var belt_to := eng_c + Vector3(-0.3, 0.42, 0)
	var belt := _add_box(engine, (belt_from + belt_to) * 0.5, Vector3(0.05, 0.04, belt_from.distance_to(belt_to)), dark_wood)
	belt.name = "Belt"
	belt.transform = Transform3D(Basis.looking_at(belt_to - belt_from, Vector3.UP), (belt_from + belt_to) * 0.5)
	var chimney := _add_cylinder(engine, eng_c + Vector3(0.25, 1.55, 0), 0.09, 2.2, iron, 8)
	chimney.name = "Chimney"
	_add_cylinder(engine, eng_c + Vector3(0.25, 2.66, 0), 0.13, 0.06, red, 8)

	# ── Pilas: tablones bajo techo (izquierda) y troncos delante ──
	var planks := _group(root, "PlankStack")
	for layer in 5:
		for j in 4:
			var col := light_wood if (layer + j) % 2 == 0 else wood
			_add_box(planks, Vector3(-hw * 0.5 + (j - 1.5) * 0.24, floor_y + 0.05 + 0.1 * layer, back_z + 0.6), Vector3(0.22, 0.09, 0.95), col)
	var logs := _group(root, "LogPile")
	var lp := Vector3(-hw * 0.45, floor_y, front_z - 0.05)
	for k in 3:
		var l := _add_cylinder(logs, lp + Vector3(0, 0.15, -0.22 + 0.15 * k), 0.15, 1.1, bark, 8)
		l.rotation.z = PI / 2.0
	for k in 2:
		var l := _add_cylinder(logs, lp + Vector3(0, 0.41, -0.15 + 0.15 * k), 0.15, 1.1, bark, 8)
		l.rotation.z = PI / 2.0
	# Serrin bajo la hoja
	_add_cone(saw, Vector3(0.1, floor_y + 0.1, table_z + 0.55), 0.35, 0.05, 0.2, light_wood, 8)

	var anchor := Marker3D.new()
	anchor.name = "FxAnchor"
	anchor.position = blade_c + Vector3(0, blade_r * 0.7, 0.1)
	root.add_child(anchor)
	return root


# ════════════════════════════════════════════════════════════════
# TOWER — Tall octagonal watchtower, searchlight, armored
# ════════════════════════════════════════════════════════════════
static func _build_tower(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_iron: StandardMaterial3D = _metal(COL_DARK_IRON, 0.85, 0.35)
	var mat_gun: StandardMaterial3D = _metal(COL_GUNMETAL, 0.8, 0.4)
	var mat_brass: StandardMaterial3D = _metal(COL_BRASS, 0.9, 0.3)
	var mat_concrete: StandardMaterial3D = _metal(COL_CONCRETE, 0.2, 0.8)

	# Concrete base
	_add_cylinder(root, Vector3(0, 0.2, 0), 0.7, 0.4, mat_concrete)

	# Main tower shaft — tapered cylinder (wider at bottom)
	_add_cone(root, Vector3(0, 1.8, 0), 0.55, 0.4, 3.0, mat_iron)

	# Armored rings
	_add_torus(root, Vector3(0, 0.6, 0), 0.48, 0.58, mat_gun, 8)
	_add_torus(root, Vector3(0, 1.6, 0), 0.42, 0.52, mat_gun, 8)
	_add_torus(root, Vector3(0, 2.6, 0), 0.36, 0.46, mat_gun, 8)

	# Observation platform at top
	_add_cylinder(root, Vector3(0, 3.3, 0), 0.6, 0.15, mat_iron)

	# Railing posts
	for i in range(8):
		var angle: float = i * PI * 2.0 / 8.0
		var rx: float = cos(angle) * 0.55
		var rz: float = sin(angle) * 0.55
		_add_cylinder(root, Vector3(rx, 3.55, rz), 0.025, 0.4, mat_iron)

	# Railing ring (top)
	_add_torus(root, Vector3(0, 3.7, 0), 0.5, 0.56, mat_iron, 8)

	# Searchlight housing
	_add_cone(root, Vector3(0, 3.6, 0.35), 0.18, 0.06, 0.25, mat_gun)
	_add_sphere(root, Vector3(0, 3.6, 0.48), 0.08, _emissive(COL_SEARCHLIGHT, 3.0))

	# Gun barrel / cannon
	var cannon: MeshInstance3D = _add_cylinder(root, Vector3(0.3, 3.45, 0), 0.05, 0.6, mat_iron)
	cannon.rotation.x = PI / 10.0
	cannon.rotation.y = PI / 4.0

	# Rivets along base
	_add_rivets(root, Vector3(-0.5, 0.4, 0.2), Vector3(0.5, 0.4, 0.2))

	# Antenna on top
	_add_cylinder(root, Vector3(0, 4.1, 0), 0.02, 0.6, mat_brass)
	_add_sphere(root, Vector3(0, 4.45, 0), 0.04, _emissive(Color(1, 0.2, 0.1), 2.0))

	return root


# ════════════════════════════════════════════════════════════════
# WAREHOUSE — Riveted metal shed, sliding door, crates
# ════════════════════════════════════════════════════════════════
## Mercado: plataforma de madera con tres puestos de toldo a rayas y cajas.
static func _build_market(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_wood := _metal(COL_DARK_WOOD, 0.1, 0.85)
	var mat_iron := _metal(COL_DARK_IRON, 0.8, 0.4)
	var mat_brass := _metal(COL_BRASS, 0.9, 0.3)
	var awnings := [_metal(Color(0.72, 0.18, 0.12), 0.1, 0.7), _metal(Color(0.85, 0.7, 0.25), 0.1, 0.7), _metal(Color(0.2, 0.42, 0.6), 0.1, 0.7)]
	_add_box(root, Vector3(0, 0.08, 0), Vector3(sx * 0.95, 0.16, sz * 0.95), mat_wood)
	for i in 3:
		var x: float = (-0.3 + 0.3 * i) * sx
		var z: float = -0.18 * sz if i != 1 else 0.18 * sz
		_add_box(root, Vector3(x, 0.45, z), Vector3(sx * 0.22, 0.55, sz * 0.26), mat_wood)
		for cx in [-1, 1]:
			for cz in [-1, 1]:
				_add_box(root, Vector3(x + cx * sx * 0.1, 0.75, z + cz * sz * 0.12), Vector3(0.05, 1.1, 0.05), mat_iron)
		_add_prism(root, Vector3(x, 1.4, z), Vector3(sx * 0.34, 0.42, sz * 0.4), awnings[i])
		# Mercancia en el mostrador: la funcion se ve desde fuera.
		var goods := [Color(0.85, 0.2, 0.12), Color(0.95, 0.78, 0.2), Color(0.35, 0.62, 0.22)]
		for g in 3:
			_add_sphere(root, Vector3(x + (g - 1) * sx * 0.06, 0.8, z + sz * 0.09), 0.09, _shared_metal("market_goods_%d" % g, goods[g], 0.0, 0.7), 8)
	# Balanza de laton en el centro
	_add_box(root, Vector3(0, 0.6, sz * 0.38), Vector3(0.06, 0.9, 0.06), mat_brass)
	_add_box(root, Vector3(0, 1.05, sz * 0.38), Vector3(sx * 0.3, 0.04, 0.04), mat_brass)
	for k in 4:
		_add_box(root, Vector3(sx * (-0.4 + 0.25 * k), 0.3, sz * 0.4), Vector3(0.35, 0.3, 0.35), mat_wood)
	return root

## Laboratorio: bloque de hormigon con cupula de cristal, antena y tuberias.
static func _build_laboratory(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_stone := _metal(Color(0.55, 0.55, 0.52), 0.2, 0.7)
	var mat_iron := _metal(COL_DARK_IRON, 0.8, 0.4)
	var mat_copper := _metal(COL_COPPER, 0.85, 0.35)
	var mat_glass := _emissive(Color(0.35, 0.8, 0.95), 0.9)
	_add_box(root, Vector3(0, 0.8, 0), Vector3(sx * 0.8, 1.6, sz * 0.75), mat_stone)
	_add_box(root, Vector3(0, 1.62, 0), Vector3(sx * 0.84, 0.08, sz * 0.79), mat_iron)
	# Cupula de cristal con luz azulada (la funcion se ve desde fuera); la antena
	# grande, la exagerada, va en el patio (BuildingLot, "antenna").
	_add_cylinder(root, Vector3(0, 1.75, 0), sx * 0.27, 0.18, mat_iron, 20)
	_add_sphere(root, Vector3(0, 1.84, 0), sx * 0.25, mat_glass, 20)
	_add_torus(root, Vector3(0, 1.86, 0), sx * 0.24, sx * 0.28, _metal(COL_BRASS, 0.9, 0.3), 20, 8)
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var rib := _add_box(root, Vector3(cos(a) * sx * 0.12, 2.0, sin(a) * sx * 0.12), Vector3(0.05, sx * 0.4, 0.05), mat_iron)
		rib.rotation = Vector3(sin(a) * 0.9, 0, -cos(a) * 0.9)
	for i in 3:
		_add_box(root, Vector3(-sx * 0.42, 0.4 + 0.4 * i, sz * (-0.2 + 0.2 * i)), Vector3(0.08, 0.08, sz * 0.5), mat_copper)
	_add_box(root, Vector3(0, 0.5, sz * 0.38), Vector3(sx * 0.25, 1.0, 0.04), mat_iron)
	return root

static func _build_warehouse(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_iron: StandardMaterial3D = _metal(COL_DARK_IRON, 0.8, 0.4)
	var mat_rust: StandardMaterial3D = _metal(COL_RUST, 0.6, 0.55)
	var mat_brass: StandardMaterial3D = _metal(COL_BRASS, 0.9, 0.3)
	var mat_wood: StandardMaterial3D = _metal(COL_DARK_WOOD, 0.1, 0.85)

	# Main warehouse body
	_add_box(root, Vector3(0, 0.65, 0), Vector3(sx * 0.85, 1.3, sz * 0.8), mat_iron)

	# Arched roof (approximated with a half-cylinder using prism)
	_add_prism(root, Vector3(0, 1.5, 0), Vector3(sx * 0.88, 0.45, sz * 0.83), mat_rust)

	# Reinforcement strips (horizontal iron bands)
	_add_box(root, Vector3(0, 0.3, sz * 0.41), Vector3(sx * 0.86, 0.05, 0.02), mat_rust)
	_add_box(root, Vector3(0, 0.8, sz * 0.41), Vector3(sx * 0.86, 0.05, 0.02), mat_rust)
	_add_box(root, Vector3(0, 0.3, -sz * 0.41), Vector3(sx * 0.86, 0.05, 0.02), mat_rust)
	_add_box(root, Vector3(0, 0.8, -sz * 0.41), Vector3(sx * 0.86, 0.05, 0.02), mat_rust)

	# Sliding door (front, slightly offset)
	_add_box(root, Vector3(-0.05, 0.5, sz * 0.42), Vector3(sx * 0.4, 0.9, 0.04), _metal(Color(0.35, 0.32, 0.30), 0.7, 0.5))
	# Door rail
	_add_box(root, Vector3(0, 1.0, sz * 0.43), Vector3(sx * 0.7, 0.04, 0.02), mat_brass)
	# Door handle
	_add_box(root, Vector3(0.12, 0.5, sz * 0.45), Vector3(0.04, 0.15, 0.04), mat_brass)

	# Rivets along edges
	_add_rivets(root, Vector3(-sx * 0.38, 1.28, sz * 0.4), Vector3(sx * 0.38, 1.28, sz * 0.4))
	_add_rivets(root, Vector3(-sx * 0.38, 1.28, -sz * 0.4), Vector3(sx * 0.38, 1.28, -sz * 0.4))

	# Crates stacked outside
	_add_box(root, Vector3(sx * 0.35, 0.15, -sz * 0.25), Vector3(0.25, 0.3, 0.25), mat_wood)
	_add_box(root, Vector3(sx * 0.35, 0.4, -sz * 0.25), Vector3(0.2, 0.2, 0.2), mat_wood)
	_add_box(root, Vector3(sx * 0.2, 0.12, -sz * 0.35), Vector3(0.2, 0.22, 0.2), mat_wood)

	# Ventilation pipe on roof
	_add_cylinder(root, Vector3(sx * 0.2, 1.85, 0), 0.06, 0.3, mat_iron)
	_add_cone(root, Vector3(sx * 0.2, 2.05, 0), 0.09, 0.03, 0.12, mat_iron)

	# Lock/padlock on door
	_add_box(root, Vector3(0.15, 0.35, sz * 0.46), Vector3(0.08, 0.1, 0.04), mat_brass)

	return root


# ════════════════════════════════════════════════════════════════
# HOUSE — Dieselpunk worker cottage with timber frame, metal roof
# ════════════════════════════════════════════════════════════════
static func _build_house(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_wall := _metal(Color(0.55, 0.42, 0.28), 0.2, 0.8)
	var mat_wall_dark := _metal(Color(0.42, 0.32, 0.20), 0.15, 0.85)
	var mat_roof := _metal(Color(0.30, 0.28, 0.32), 0.7, 0.45)
	var mat_window := _emissive(Color(0.9, 0.72, 0.25), 0.9)
	var mat_chimney := _metal(COL_DARK_IRON, 0.6, 0.5)
	var mat_wood := _metal(COL_DARK_WOOD, 0.1, 0.85)
	var mat_brass := _metal(COL_BRASS, 0.9, 0.3)
	var mat_door := _metal(Color(0.35, 0.20, 0.10), 0.3, 0.75)

	# Foundation
	_add_box(root, Vector3(0, 0.06, 0), Vector3(sx * 0.92, 0.12, sz * 0.88), _metal(COL_CONCRETE, 0.2, 0.8))
	# Main body
	_add_box(root, Vector3(0, 0.7, 0), Vector3(sx * 0.82, 1.15, sz * 0.78), mat_wall)
	# Second floor (slightly recessed)
	_add_box(root, Vector3(0, 1.0, 0), Vector3(sx * 0.78, 0.5, sz * 0.74), mat_wall_dark)
	# Timber frame beams
	_add_box(root, Vector3(-sx * 0.40, 0.7, 0), Vector3(0.05, 1.15, sz * 0.80), mat_wood)
	_add_box(root, Vector3(sx * 0.40, 0.7, 0), Vector3(0.05, 1.15, sz * 0.80), mat_wood)
	_add_box(root, Vector3(0, 0.7, -sz * 0.38), Vector3(sx * 0.82, 1.15, 0.05), mat_wood)
	_add_box(root, Vector3(0, 1.28, 0), Vector3(sx * 0.84, 0.04, sz * 0.80), mat_wood)
	# Pitched metal roof
	_add_prism(root, Vector3(0, 1.55, 0), Vector3(sx * 0.92, 0.45, sz * 0.88), mat_roof)
	# Roof ridge cap (brass)
	_add_box(root, Vector3(0, 1.78, 0), Vector3(0.04, 0.03, sz * 0.70), mat_brass)
	# Chimney with smoke
	_add_box(root, Vector3(sx * 0.25, 1.85, -sz * 0.15), Vector3(0.16, 0.5, 0.14), mat_chimney)
	_add_box(root, Vector3(sx * 0.25, 2.12, -sz * 0.15), Vector3(0.18, 0.04, 0.16), mat_chimney)
	_add_sphere(root, Vector3(sx * 0.25, 2.2, -sz * 0.15), 0.06, _emissive(COL_STEAM, 0.3))
	# Front windows (warm glow, with shutters)
	for wx in [-0.18, 0.18]:
		_add_box(root, Vector3(wx, 0.72, sz * 0.40), Vector3(0.16, 0.22, 0.02), mat_window)
		_add_box(root, Vector3(wx - 0.10, 0.72, sz * 0.41), Vector3(0.04, 0.24, 0.01), mat_wood)
		_add_box(root, Vector3(wx + 0.10, 0.72, sz * 0.41), Vector3(0.04, 0.24, 0.01), mat_wood)
		_add_box(root, Vector3(wx, 0.85, sz * 0.41), Vector3(0.18, 0.02, 0.01), mat_wood)
	# Upper window (attic)
	_add_box(root, Vector3(0, 1.35, sz * 0.39), Vector3(0.12, 0.14, 0.02), mat_window)
	# Side windows
	for side in [-1.0, 1.0]:
		_add_box(root, Vector3(side * sx * 0.42, 0.72, 0), Vector3(0.02, 0.2, 0.14), mat_window)
	# Front door with frame
	_add_box(root, Vector3(0, 0.38, sz * 0.40), Vector3(0.22, 0.6, 0.03), mat_door)
	_add_box(root, Vector3(0, 0.70, sz * 0.41), Vector3(0.26, 0.03, 0.02), mat_wood)
	_add_sphere(root, Vector3(0.08, 0.38, sz * 0.42), 0.025, mat_brass)
	# Pipe on side
	_add_cylinder(root, Vector3(-sx * 0.42, 0.6, sz * 0.2), 0.025, 0.8, mat_chimney)
	# Flower box under front window
	_add_box(root, Vector3(-0.18, 0.58, sz * 0.43), Vector3(0.18, 0.05, 0.06), mat_wood)
	_add_sphere(root, Vector3(-0.22, 0.63, sz * 0.43), 0.03, _emissive(Color(0.9, 0.3, 0.3), 0.4))
	_add_sphere(root, Vector3(-0.15, 0.64, sz * 0.43), 0.03, _emissive(Color(0.9, 0.8, 0.2), 0.4))

	return root


# ════════════════════════════════════════════════════════════════
# GARDEN — Industrial victory garden with raised beds, lamp post
# ════════════════════════════════════════════════════════════════
static func _build_garden(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_grass := _metal(Color(0.25, 0.5, 0.15), 0.1, 0.9)
	var mat_dirt := _metal(Color(0.35, 0.25, 0.15), 0.1, 0.9)
	var mat_bush_dark := _metal(Color(0.15, 0.4, 0.12), 0.1, 0.85)
	var mat_bush_light := _metal(Color(0.3, 0.55, 0.2), 0.1, 0.8)
	var mat_flower_red := _emissive(Color(0.9, 0.2, 0.25), 0.6)
	var mat_flower_yel := _emissive(Color(0.95, 0.85, 0.15), 0.5)
	var mat_flower_blue := _emissive(Color(0.3, 0.4, 0.9), 0.5)
	var mat_wood := _metal(COL_DARK_WOOD, 0.1, 0.85)
	var mat_iron := _metal(COL_DARK_IRON, 0.7, 0.5)
	var mat_stone := _metal(Color(0.45, 0.42, 0.40), 0.3, 0.7)

	# Cobblestone border ring
	_add_cylinder(root, Vector3(0, 0.02, 0), sx * 0.48, 0.04, mat_stone, 12)
	# Grass center
	_add_cylinder(root, Vector3(0, 0.03, 0), sx * 0.42, 0.04, mat_grass, 10)
	# Raised wooden planter beds (2 L-shaped)
	_add_box(root, Vector3(-0.2, 0.08, 0.15), Vector3(0.35, 0.1, 0.25), mat_wood)
	_add_box(root, Vector3(-0.2, 0.04, 0.15), Vector3(0.37, 0.02, 0.27), mat_wood)
	_add_box(root, Vector3(-0.2, 0.1, 0.15), Vector3(0.33, 0.02, 0.23), mat_dirt)
	_add_box(root, Vector3(0.2, 0.08, -0.18), Vector3(0.3, 0.1, 0.22), mat_wood)
	_add_box(root, Vector3(0.2, 0.1, -0.18), Vector3(0.28, 0.02, 0.20), mat_dirt)
	# Ornamental bushes (trimmed spheres)
	_add_sphere(root, Vector3(-0.35, 0.2, -0.3), 0.18, mat_bush_dark)
	_add_sphere(root, Vector3(0.35, 0.18, 0.32), 0.16, mat_bush_light)
	_add_sphere(root, Vector3(-0.1, 0.22, -0.35), 0.2, mat_bush_light)
	# Flowers in planters (clusters)
	_add_sphere(root, Vector3(-0.28, 0.16, 0.2), 0.04, mat_flower_red)
	_add_sphere(root, Vector3(-0.22, 0.17, 0.1), 0.04, mat_flower_yel)
	_add_sphere(root, Vector3(-0.12, 0.16, 0.22), 0.035, mat_flower_blue)
	_add_sphere(root, Vector3(-0.18, 0.15, 0.18), 0.04, mat_flower_red)
	_add_sphere(root, Vector3(0.25, 0.16, -0.15), 0.04, mat_flower_yel)
	_add_sphere(root, Vector3(0.15, 0.15, -0.22), 0.035, mat_flower_red)
	_add_sphere(root, Vector3(0.22, 0.17, -0.12), 0.04, mat_flower_blue)
	# Tiny iron lamp post
	_add_cylinder(root, Vector3(0.35, 0.35, -0.05), 0.02, 0.7, mat_iron)
	_add_box(root, Vector3(0.35, 0.72, -0.05), Vector3(0.08, 0.06, 0.08), mat_iron)
	_add_sphere(root, Vector3(0.35, 0.72, -0.05), 0.035, _emissive(Color(1.0, 0.85, 0.4), 1.2))
	# Small fence segments
	for i in range(5):
		var angle: float = i * TAU / 5.0 + 0.3
		var fx: float = cos(angle) * sx * 0.44
		var fz: float = sin(angle) * sx * 0.44
		_add_box(root, Vector3(fx, 0.1, fz), Vector3(0.03, 0.18, 0.03), mat_wood)

	return root


# ════════════════════════════════════════════════════════════════
# FOUNTAIN — Tiered industrial fountain with steam and copper pipes
# ════════════════════════════════════════════════════════════════
static func _build_fountain(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_stone := _metal(Color(0.50, 0.48, 0.44), 0.35, 0.65)
	var mat_stone_dark := _metal(Color(0.38, 0.36, 0.33), 0.3, 0.7)
	var mat_water := _emissive(Color(0.25, 0.50, 0.80), 0.5)
	var mat_brass := _metal(COL_BRASS, 0.9, 0.3)
	var mat_copper := _metal(COL_COPPER, 0.85, 0.35)
	var mat_iron := _metal(COL_DARK_IRON, 0.7, 0.45)

	# Octagonal base pool (thick rim)
	_add_cylinder(root, Vector3(0, 0.1, 0), 0.60, 0.2, mat_stone)
	_add_cylinder(root, Vector3(0, 0.12, 0), 0.52, 0.18, mat_stone_dark)
	# Water surface
	_add_cylinder(root, Vector3(0, 0.15, 0), 0.48, 0.06, mat_water, 10)
	# Decorative rim rivets
	for i in range(8):
		var angle: float = i * TAU / 8.0
		var rx: float = cos(angle) * 0.56
		var rz: float = sin(angle) * 0.56
		_add_sphere(root, Vector3(rx, 0.2, rz), 0.03, mat_brass)
	# Central pillar (fluted with copper bands)
	_add_cylinder(root, Vector3(0, 0.6, 0), 0.09, 0.8, mat_stone)
	_add_torus(root, Vector3(0, 0.35, 0), 0.07, 0.11, mat_copper)
	_add_torus(root, Vector3(0, 0.75, 0), 0.07, 0.11, mat_copper)
	# Upper bowl (second tier)
	_add_cone(root, Vector3(0, 1.0, 0), 0.06, 0.25, 0.15, mat_stone)
	_add_cylinder(root, Vector3(0, 1.1, 0), 0.22, 0.06, mat_stone_dark)
	# Upper water
	_add_cylinder(root, Vector3(0, 1.12, 0), 0.18, 0.03, mat_water)
	# Water spouts (4 copper pipes pouring into lower pool)
	for i in range(4):
		var angle: float = i * TAU / 4.0 + PI / 4.0
		var px: float = cos(angle) * 0.20
		var pz: float = sin(angle) * 0.20
		_add_cylinder(root, Vector3(px, 1.0, pz), 0.02, 0.12, mat_copper)
		# Water stream (emissive drop)
		_add_sphere(root, Vector3(px, 0.88, pz), 0.025, mat_water)
	# Central jet/spray
	_add_cone(root, Vector3(0, 1.35, 0), 0.04, 0.01, 0.3, mat_water)
	_add_sphere(root, Vector3(0, 1.52, 0), 0.05, _emissive(Color(0.4, 0.6, 0.9), 1.0))
	# Iron decorative base ring
	_add_torus(root, Vector3(0, 0.03, 0), 0.55, 0.62, mat_iron)

	return root


# ════════════════════════════════════════════════════════════════
# STATUE — Imperial soldier monument with gear base, eternal flame
# ════════════════════════════════════════════════════════════════
static func _build_statue(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_stone := _metal(Color(0.50, 0.48, 0.45), 0.25, 0.7)
	var mat_stone_dark := _metal(Color(0.35, 0.33, 0.32), 0.3, 0.75)
	var mat_bronze := _metal(Color(0.55, 0.42, 0.18), 0.85, 0.3)
	var mat_bronze_dark := _metal(Color(0.40, 0.32, 0.15), 0.8, 0.4)
	var mat_gold := _emissive(Color(0.9, 0.75, 0.15), 0.6)
	var mat_iron := _metal(COL_DARK_IRON, 0.7, 0.45)
	var mat_flame := _emissive(COL_FIRE, 2.5)

	# Tiered pedestal — 3 steps
	_add_box(root, Vector3(0, 0.06, 0), Vector3(0.7, 0.12, 0.7), mat_stone_dark)
	_add_box(root, Vector3(0, 0.18, 0), Vector3(0.58, 0.12, 0.58), mat_stone)
	_add_box(root, Vector3(0, 0.30, 0), Vector3(0.46, 0.12, 0.46), mat_stone_dark)
	# Pillar body
	_add_box(root, Vector3(0, 0.65, 0), Vector3(0.34, 0.6, 0.34), mat_stone)
	# Iron corner reinforcements
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_add_box(root, Vector3(cx * 0.17, 0.65, cz * 0.17), Vector3(0.04, 0.62, 0.04), mat_iron)
	# Decorative gear on front
	_add_torus(root, Vector3(0, 0.55, 0.18), 0.06, 0.1, _metal(COL_BRASS, 0.9, 0.3))
	# Gold plaque
	_add_box(root, Vector3(0, 0.72, 0.175), Vector3(0.22, 0.1, 0.02), mat_gold)
	# Figure — soldier at attention
	# Torso
	_add_box(root, Vector3(0, 1.25, 0), Vector3(0.18, 0.4, 0.12), mat_bronze)
	# Shoulders
	_add_box(root, Vector3(0, 1.48, 0), Vector3(0.26, 0.06, 0.14), mat_bronze_dark)
	# Head (with helmet)
	_add_sphere(root, Vector3(0, 1.62, 0), 0.09, mat_bronze)
	_add_cylinder(root, Vector3(0, 1.72, 0), 0.10, 0.06, mat_bronze_dark)
	# Legs
	_add_box(root, Vector3(-0.05, 1.0, 0), Vector3(0.07, 0.3, 0.08), mat_bronze)
	_add_box(root, Vector3(0.05, 1.0, 0), Vector3(0.07, 0.3, 0.08), mat_bronze)
	# Right arm raised (holding something)
	_add_box(root, Vector3(0.15, 1.42, 0), Vector3(0.06, 0.25, 0.06), mat_bronze)
	_add_box(root, Vector3(0.15, 1.58, 0), Vector3(0.06, 0.08, 0.06), mat_bronze_dark)
	# Left arm at side
	_add_box(root, Vector3(-0.15, 1.32, 0), Vector3(0.06, 0.2, 0.06), mat_bronze)
	# Sword/torch held high
	_add_cylinder(root, Vector3(0.15, 1.78, 0), 0.015, 0.3, mat_iron)
	# Eternal flame at top
	_add_sphere(root, Vector3(0.15, 1.96, 0), 0.05, mat_flame)
	# Boots
	_add_box(root, Vector3(-0.05, 0.84, 0.02), Vector3(0.08, 0.04, 0.12), mat_bronze_dark)
	_add_box(root, Vector3(0.05, 0.84, 0.02), Vector3(0.08, 0.04, 0.12), mat_bronze_dark)

	return root


# ════════════════════════════════════════════════════════════════
# ROAD — Flat paved surface
# ════════════════════════════════════════════════════════════════
## Dynamic road that connects to adjacent roads.
## neighbors bitmask: NORTH=1 (Z-), EAST=2 (X+), SOUTH=4 (Z+), WEST=8 (X-)
static func _build_road(sx: float, sz: float, neighbors: int = 0) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_pave := _metal(Color(0.34, 0.32, 0.29), 0.2, 0.85)
	var mat_curb := _metal(Color(0.62, 0.58, 0.52), 0.1, 0.8)
	var mat_line := _metal(Color(0.85, 0.72, 0.3), 0.1, 0.7)

	var has_n := (neighbors & 1) != 0
	var has_e := (neighbors & 2) != 0
	var has_s := (neighbors & 4) != 0
	var has_w := (neighbors & 8) != 0

	# Pavimento de la celda entera: con el vecino, un solo firme.
	_add_box(root, Vector3(0, 0.025, 0), Vector3(sx, 0.05, sz), mat_pave)

	# Acera (bordillo claro y algo alto) en cada lado que no sigue la calle.
	var curb_w: float = sx * 0.16
	var curb_h := 0.1
	if not has_n:
		_add_box(root, Vector3(0, curb_h * 0.5, -sz * 0.5 + curb_w * 0.5), Vector3(sx, curb_h, curb_w), mat_curb)
	if not has_s:
		_add_box(root, Vector3(0, curb_h * 0.5, sz * 0.5 - curb_w * 0.5), Vector3(sx, curb_h, curb_w), mat_curb)
	if not has_e:
		_add_box(root, Vector3(sx * 0.5 - curb_w * 0.5, curb_h * 0.5, 0), Vector3(curb_w, curb_h, sz), mat_curb)
	if not has_w:
		_add_box(root, Vector3(-sx * 0.5 + curb_w * 0.5, curb_h * 0.5, 0), Vector3(curb_w, curb_h, sz), mat_curb)

	# Linea central en los tramos rectos; de borde a borde, para que se una.
	if has_n and has_s and not has_e and not has_w:
		_add_box(root, Vector3(0, 0.052, 0), Vector3(0.05, 0.01, sz), mat_line)
	elif has_e and has_w and not has_n and not has_s:
		_add_box(root, Vector3(0, 0.052, 0), Vector3(sx, 0.01, 0.05), mat_line)

	return root


# ════════════════════════════════════════════════════════════════
# OBRA Y RUINA (docs/03, "Aspecto en el mapa" y "Obra por edificio")
# Tres fases de obra, las mismas para todos: valla con materiales ->
# solar con cimientos -> estructura a medio levantar. La huella decide
# el tamano y cuantas piezas; el ESTILO del edificio (BuildingLook.
# site_style) que materiales, que valla, que lona y que silueta; y la
# SEMILLA de la instancia (BuildingLook.site_layout) donde va cada cosa.
# Piezas low-poly (cilindros de 6 lados) y materiales cacheados.
# ════════════════════════════════════════════════════════════════

const _LookRule := preload("res://scripts/buildings/BuildingLook.gd")
const _SiteFx := preload("res://scripts/buildings/SiteFx.gd")
const _Fx := preload("res://scripts/buildings/BuildingFx.gd")

static var _site_mats: Dictionary = {}
static var _site_meshes: Dictionary = {}

## Material de obra cacheado por nombre (sin mapas de chapa: son piezas
## pequenas y lejanas, y asi se agrupan mejor en Mobile).
static func _site_mat(key: String) -> StandardMaterial3D:
	if _site_mats.has(key):
		return _site_mats[key]
	var colors := {
		"dirt": Color(0.36, 0.27, 0.18), "wood": Color(0.55, 0.40, 0.22),
		"dark_wood": COL_DARK_WOOD, "steel": COL_GUNMETAL, "brick": Color(0.55, 0.25, 0.17),
		"concrete": Color(0.58, 0.56, 0.52), "concrete_dark": COL_CONCRETE,
		"rebar": COL_RUST, "hazard": Color(0.95, 0.72, 0.1), "char": Color(0.07, 0.06, 0.055),
		"scorch": Color(0.1, 0.085, 0.07), "rubble": Color(0.3, 0.28, 0.26),
		"stone": Color(0.64, 0.61, 0.55), "stone_dark": Color(0.47, 0.45, 0.41),
		"sack": Color(0.78, 0.68, 0.48), "sandbag": Color(0.62, 0.57, 0.40),
		"sawdust": Color(0.86, 0.74, 0.52), "gravel": Color(0.50, 0.48, 0.45),
		"soil": Color(0.24, 0.17, 0.11), "sheet": Color(0.44, 0.46, 0.48),
		"crate": Color(0.47, 0.32, 0.16), "log": Color(0.42, 0.28, 0.15),
		"drum": Color(0.22, 0.30, 0.25), "copper": COL_COPPER, "leaf": Color(0.26, 0.5, 0.18),
	}
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colors.get(key, COL_CONCRETE)
	mat.roughness = 0.9
	mat.metallic = 0.5 if key in ["steel", "rebar", "hazard", "sheet", "copper", "drum"] else 0.0
	_site_mats[key] = mat
	return mat

## Material de obra de un color suelto (lonas, la grua de cada estilo).
static func _site_color_mat(color: Color) -> StandardMaterial3D:
	var key := "#" + color.to_html()
	if _site_mats.has(key):
		return _site_mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	_site_mats[key] = mat
	return mat

static func _foot_dims(footprint: Vector2i, cell_size: float) -> Vector2:
	return Vector2(footprint.x * cell_size * 0.9, footprint.y * cell_size * 0.9)

## Fase de obra `phase` (0, 1, 2) para una parcela de `footprint` celdas, con el
## estilo de `building_id` ("" = el de por defecto) y la disposicion de la
## semilla `seed_val` (BuildingLook.seed_of). Misma entrada, misma obra.
## Raiz "ConstructionPhase<N>" con un grupo por fase: "Fence" y "Piles" (0),
## "Foundation" (1), "Frame" y "Scaffold" (2). Null si la fase no existe.
static func create_construction_phase(footprint: Vector2i, phase: int, cell_size: float, building_id: String = "", seed_val: int = 0) -> Node3D:
	if phase < 0 or phase > 2:
		return null
	var d := _foot_dims(footprint, cell_size)
	var n := clampi(maxi(footprint.x, footprint.y), 1, 3)
	var style := _LookRule.site_style(building_id)
	var layout := _LookRule.site_layout(seed_val, style, n)
	var root := Node3D.new()
	root.name = "ConstructionPhase%d" % phase
	root.set_meta("site_seed", seed_val)
	root.set_meta("site_frame", String(style["frame"]))
	match phase:
		0: _phase_fence(root, d.x, d.y, n, style, layout)
		1: _phase_foundation(root, d.x, d.y, n, style, layout)
		2: _phase_frame(root, d.x, d.y, n, style, layout)
	return root

static func _group(root: Node3D, group_name: String) -> Node3D:
	var g := Node3D.new()
	g.name = group_name
	root.add_child(g)
	return g

## De fracciones de la huella (marco sin girar) a la parcela 3D.
static func _at(frac: Vector2, sx: float, sz: float, y: float = 0.0) -> Vector3:
	return Vector3(frac.x * sx, y, frac.y * sz)

## Fase 0: tierra removida, valla con su puerta (en el lado que diga la
## semilla) y las pilas del estilo, una lona sobre alguna y algo de desorden.
static func _phase_fence(root: Node3D, sx: float, sz: float, n: int, style: Dictionary, layout: Dictionary) -> void:
	_add_box(root, Vector3(0, 0.02, 0), Vector3(sx, 0.04, sz), _site_mat("dirt"))
	var fence := _group(root, "Fence")
	var kind := String(style["fence"])
	var post_mat := _site_mat({"dark_planks": "dark_wood", "sheet": "steel"}.get(kind, "wood"))
	var rail_mat: StandardMaterial3D
	match kind:
		"dark_planks": rail_mat = _site_mat("dark_wood")
		"sheet": rail_mat = _site_mat("sheet")
		"canvas": rail_mat = _site_color_mat(style["tarp"])
		_: rail_mat = _site_mat("wood")
	var post_h := 0.75
	var gate := int(layout["gate_side"])
	var step := float(layout["post_step"])
	for side in 4:
		var nrm := _LookRule.side_normal(side)
		var along := Vector2(-nrm.y, nrm.x)
		var length := sx if nrm.x == 0.0 else sz
		var half := (sz if nrm.x == 0.0 else sx) * 0.5
		var mid := nrm * half
		var yaw := 0.0 if nrm.x == 0.0 else PI * 0.5
		var posts := maxi(2, int(length / step) + 1)
		for i in posts:
			var t := lerpf(-length * 0.5, length * 0.5, float(i) / float(posts - 1))
			if side == gate and absf(t) < length * 0.18:
				continue
			var p := mid + along * t
			_add_cylinder(fence, Vector3(p.x, post_h * 0.5, p.y), 0.05, post_h, post_mat, 6)
		var segs := [[0.0, length]]
		if side == gate:
			var seg := length * 0.32
			segs = [[-(length * 0.5 - seg * 0.5), seg], [length * 0.5 - seg * 0.5, seg]]
		for s in segs:
			var c: Vector2 = mid + along * float(s[0])
			if kind == "sheet" or kind == "canvas":
				var panel := _add_box(fence, Vector3(c.x, 0.37, c.y), Vector3(float(s[1]), 0.58, 0.04), rail_mat)
				panel.rotation.y = yaw
			else:
				for h in [0.3, 0.62]:
					var rail := _add_box(fence, Vector3(c.x, h, c.y), Vector3(float(s[1]), 0.08, 0.05), rail_mat)
					rail.rotation.y = yaw
	# Cinta de peligro sobre la puerta y el banderin en uno de sus postes.
	var gn := _LookRule.side_normal(gate)
	var glen := sx if gn.x == 0.0 else sz
	var ghalf := (sz if gn.x == 0.0 else sx) * 0.5
	var tape := _add_box(fence, Vector3(gn.x * ghalf, post_h, gn.y * ghalf), Vector3(glen * 0.36, 0.06, 0.06), _site_mat("hazard"))
	tape.rotation.y = 0.0 if gn.x == 0.0 else PI * 0.5
	var flag_at := gn * ghalf + Vector2(-gn.y, gn.x) * glen * 0.2 * float(layout["flag_post"])
	_add_flag(fence, Vector3(flag_at.x, 0, flag_at.y), 1.15, style["flag"])
	# Las pilas del estilo, donde diga la semilla.
	var piles := _group(root, "Piles")
	var list: Array = layout["piles"]
	for k in list.size():
		var p: Dictionary = list[k]
		var holder := _group(piles, "Pile_" + String(p["kind"]))
		holder.position = _at(p["pos"], sx, sz)
		holder.rotation.y = float(p["yaw"])
		holder.scale = Vector3.ONE * float(p["scale"])
		_pile(holder, String(p["kind"]), n)
		if k == int(layout["tarp_pile"]):
			var tarp := _add_box(holder, Vector3(0.12, 0.36, 0.0), Vector3(0.75, 0.04, 0.6), _site_color_mat(style["tarp"]))
			tarp.rotation.z = 0.25
	_clutter(piles, sx, sz, layout)
	_add_site_fx(root, _SiteFx.fx_for(style, 0), _at(layout["fx_spot"], sx, sz, 0.35), 1.1 + 0.2 * n)

## Una pila de material, centrada en el origen de `h` (ya girada y escalada).
static func _pile(h: Node3D, kind: String, n: int) -> void:
	match kind:
		"planks":
			var wood := _site_mat("wood")
			for layer in 3:
				for j in 3:
					var b := _add_box(h, Vector3.ZERO, Vector3(0.9 + 0.15 * n, 0.09, 0.14), wood)
					var off := (j - 1) * 0.18
					if layer % 2 == 1:
						b.rotation.y = PI * 0.5
						b.position = Vector3(off, 0.05 + layer * 0.1, 0.0)
					else:
						b.position = Vector3(0.0, 0.05 + layer * 0.1, off)
		"beams":
			var steel := _site_mat("steel")
			for j in 3:
				var y := 0.07 + (0.13 if j == 2 else 0.0)
				var z := (-0.1 + 0.2 * (j % 2)) if j < 2 else 0.0
				_add_box(h, Vector3(0, y, z), Vector3(1.0 + 0.2 * n, 0.12, 0.12), steel)
		"bricks":
			_add_box(h, Vector3(0, 0.04, 0), Vector3(0.66, 0.08, 0.5), _site_mat("wood"))
			_add_box(h, Vector3(0, 0.3, 0), Vector3(0.6, 0.44, 0.45), _site_mat("brick"))
		"logs":
			var log_mat := _site_mat("log")
			var rows := [[-0.21, 0.0, 0.21], [-0.105, 0.105], [0.0]]
			for r in rows.size():
				for z in rows[r]:
					var c := _add_cylinder(h, Vector3(0, 0.11 + r * 0.18, float(z)), 0.1, 1.0 + 0.15 * n, log_mat, 6)
					c.rotation.z = PI * 0.5
		"sawdust":
			_add_cone(h, Vector3(0, 0.14, 0), 0.42, 0.06, 0.28, _site_mat("sawdust"), 8)
		"gravel":
			_add_cone(h, Vector3(0, 0.17, 0), 0.45, 0.05, 0.34, _site_mat("gravel"), 8)
		"soil":
			_add_cone(h, Vector3(0, 0.13, 0), 0.42, 0.08, 0.26, _site_mat("soil"), 8)
		"rivets":
			_add_box(h, Vector3(0.2, 0.13, 0), Vector3(0.3, 0.26, 0.3), _site_mat("crate"))
			for j in 3:
				_add_cylinder(h, Vector3(-0.2 + 0.05 * j, 0.11, -0.18 + 0.18 * j), 0.09, 0.22, _site_mat("rebar"), 6)
		"pipes":
			var pipe_mat := _site_mat("copper")
			var rows := [[-0.16, 0.0, 0.16], [-0.08, 0.08]]
			for r in rows.size():
				for z in rows[r]:
					var c := _add_cylinder(h, Vector3(0, 0.07 + r * 0.13, float(z)), 0.07, 1.1 + 0.15 * n, pipe_mat, 6)
					c.rotation.z = PI * 0.5
		"drums":
			var drum := _site_mat("drum")
			for o in [Vector2(-0.15, -0.14), Vector2(0.14, -0.12), Vector2(0.0, 0.14)]:
				_add_cylinder(h, Vector3(o.x, 0.18, o.y), 0.13, 0.36, drum, 8)
			var lying := _add_cylinder(h, Vector3(0.32, 0.13, 0.2), 0.13, 0.36, drum, 8)
			lying.rotation.x = PI * 0.5
		"sacks", "sandbags":
			var sack := _site_mat("sack" if kind == "sacks" else "sandbag")
			var per := 3 if kind == "sacks" else 4
			for layer in 2:
				for j in per - layer:
					var s := _add_sphere(h, Vector3((j - (per - layer - 1) * 0.5) * 0.24, 0.08 + layer * 0.13, 0.0), 0.14, sack, 8)
					s.scale = Vector3(1.0, 0.55, 0.75)
		"stone":
			var stone := _site_mat("stone")
			var dark := _site_mat("stone_dark")
			var blocks := [[Vector3(-0.2, 0.13, -0.1), Vector3(0.38, 0.26, 0.3)], [Vector3(0.2, 0.11, 0.08), Vector3(0.34, 0.22, 0.34)],
				[Vector3(-0.05, 0.36, 0.0), Vector3(0.3, 0.22, 0.26)]]
			for b in blocks.size():
				var m := _add_box(h, blocks[b][0], blocks[b][1], stone if b % 2 == 0 else dark)
				m.rotation.y = 0.2 * b
		"crates":
			var crate := _site_mat("crate")
			_add_box(h, Vector3(-0.17, 0.15, 0), Vector3(0.3, 0.3, 0.3), crate)
			_add_box(h, Vector3(0.17, 0.15, 0.03), Vector3(0.3, 0.3, 0.3), crate)
			var top := _add_box(h, Vector3(0.0, 0.43, 0.0), Vector3(0.27, 0.26, 0.27), crate)
			top.rotation.y = 0.4
		_:
			_add_box(h, Vector3(0, 0.15, 0), Vector3(0.5, 0.3, 0.4), _site_mat("concrete_dark"))

## El pequeno desorden de la semilla: un bidon, una caja, un cono sueltos.
static func _clutter(parent: Node3D, sx: float, sz: float, layout: Dictionary) -> void:
	for c in layout["clutter"]:
		var p := _at(c["pos"], sx, sz)
		match String(c["kind"]):
			"barrel": _add_cylinder(parent, p + Vector3(0, 0.12, 0), 0.09, 0.24, _site_mat("drum"), 6)
			"crate": _add_box(parent, p + Vector3(0, 0.11, 0), Vector3(0.22, 0.22, 0.22), _site_mat("crate"))
			_: _add_cone(parent, p + Vector3(0, 0.15, 0), 0.09, 0.02, 0.3, _site_mat("hazard"), 6)

## Fase 1: solar despejado con la losa (de piedra en los edificios de piedra),
## zapatas, esperas de ferralla (o estacas de madera), conos en dos esquinas de
## la semilla y lo que sobro de la primera pila en otra.
static func _phase_foundation(root: Node3D, sx: float, sz: float, n: int, style: Dictionary, layout: Dictionary) -> void:
	_foundation_slab(root, sx, sz, style)
	var g := _group(root, "Foundation")
	var slab_h := 0.22
	var dark := _site_mat("stone_dark" if style["frame_mat"] == "stone" else "concrete_dark")
	var wood := String(style["frame_mat"]) == "wood"
	for p in _frame_points(sx * 0.8, sz * 0.8, n, String(style["frame"])):
		_add_box(g, Vector3(p.x, slab_h + 0.02, p.y), Vector3(0.36, 0.05, 0.36), dark)
		if wood:
			_add_box(g, Vector3(p.x, slab_h + 0.25, p.y), Vector3(0.09, 0.5, 0.09), _site_mat("dark_wood"))
		else:
			for o in [Vector2(-0.08, -0.08), Vector2(0.08, 0.08)]:
				_add_cylinder(g, Vector3(p.x + o.x, slab_h + 0.3, p.y + o.y), 0.025, 0.6, _site_mat("rebar"), 6)
	_foundation_hint(g, sx, sz, slab_h, style, layout)
	var hazard := _site_mat("hazard")
	for s in layout["cone_corners"]:
		_add_cone(g, Vector3(s.x * sx * 0.47, 0.18, s.y * sz * 0.47), 0.1, 0.02, 0.36, hazard, 6)
	var left: Vector2 = layout["leftover_corner"]
	var piles: Array = layout["piles"]
	if not piles.is_empty():
		var holder := _group(g, "Leftover")
		holder.position = Vector3(left.x * sx * 0.36, slab_h, left.y * sz * 0.36)
		holder.rotation.y = float(piles[0]["yaw"])
		holder.scale = Vector3.ONE * 0.7
		_pile(holder, String(piles[0]["kind"]), n)
	var cc: Vector2 = layout["cone_corners"][1]
	_add_flag(g, Vector3(cc.x * sx * 0.4, slab_h, cc.y * sz * 0.4), 0.95, style["flag"])
	_add_site_fx(root, _SiteFx.fx_for(style, 1), _at(layout["fx_spot"], sx, sz, slab_h + 0.4), 1.0 + 0.2 * n)

## Lo que ya asoma en los cimientos de cada silueta: la base redonda de la
## chimenea, los anillos de los depositos o la cupula, la zapata de la torre,
## el primer escalon del pedestal, los bancales, las durmientes de madera...
static func _foundation_hint(g: Node3D, sx: float, sz: float, y: float, style: Dictionary, layout: Dictionary) -> void:
	var cc: Vector2 = layout["crane_corner"]
	var dark := _site_mat("concrete_dark")
	match String(style["frame"]):
		"chimney":
			_add_cylinder(g, Vector3(-cc.x * sx * 0.26, y + 0.08, -cc.y * sz * 0.26), 0.36, 0.16, _site_mat("brick"), 8)
		"tanks":
			for side in [-1.0, 1.0]:
				_add_cylinder(g, Vector3(side * sx * 0.22, y + 0.05, 0), minf(sx, sz) * 0.2, 0.1, dark, 12)
		"dome", "basin":
			var r := minf(sx, sz) * 0.38
			_add_torus(g, Vector3(0, y + 0.05, 0), r - 0.1, r + 0.08, _site_mat("stone" if style["frame_mat"] == "stone" else "concrete_dark"), 20, 4)
		"tower":
			_add_box(g, Vector3(0, y + 0.08, 0), Vector3(sx * 0.6, 0.16, sz * 0.6), dark)
		"plinth":
			_add_box(g, Vector3(0, y + 0.12, 0), Vector3(sx * 0.8, 0.24, sz * 0.8), _site_mat("stone"))
		"low":
			for zs in [-1.0, 1.0]:
				_add_box(g, Vector3(0, y + 0.06, zs * sz * 0.18), Vector3(sx * 0.6, 0.12, sz * 0.18), _site_mat("soil"))
		"headframe":
			for zs in [-1.0, 1.0]:
				for xs in [-1.0, 1.0]:
					_add_box(g, Vector3(xs * sx * 0.35, y + 0.08, zs * sz * 0.18), Vector3(0.4, 0.16, 0.4), dark)
		"gable", "hall":
			var sill := _site_mat("dark_wood" if style["frame_mat"] == "wood" else "steel")
			_add_box(g, Vector3(0, y + 0.06, -sz * 0.4), Vector3(sx * 0.82, 0.1, 0.12), sill)
			_add_box(g, Vector3(0, y + 0.06, sz * 0.4), Vector3(sx * 0.82, 0.1, 0.12), sill)
			_add_box(g, Vector3(-sx * 0.4, y + 0.06, 0), Vector3(0.12, 0.1, sz * 0.82), sill)
			_add_box(g, Vector3(sx * 0.4, y + 0.06, 0), Vector3(0.12, 0.1, sz * 0.82), sill)
		"mast":
			_add_cylinder(g, Vector3(0, y + 0.1, 0), 0.25, 0.2, dark, 8)

## Fase 2: losa, la estructura con la silueta del edificio (grupo "Frame"),
## andamio en el lado de la semilla y, desde 2x2, grua en la esquina de la
## semilla, girando. Banderin en lo alto y chispas o polvo.
static func _phase_frame(root: Node3D, sx: float, sz: float, n: int, style: Dictionary, layout: Dictionary) -> void:
	_foundation_slab(root, sx, sz, style)
	var h := 1.3 + 0.45 * n
	var frame := _group(root, "Frame")
	var top := _frame_shape(frame, sx, sz, n, h, style, layout)
	_add_scaffold_side(_group(root, "Scaffold"), sx, sz, h, int(layout["scaffold_side"]))
	var cc: Vector2 = layout["crane_corner"]
	if n >= 2:
		var yaw := atan2(-cc.y, cc.x) + (float(layout["crane_yaw"]) / TAU - 0.5) * 1.2
		_add_crane(root, Vector3(cc.x * sx * 0.42, 0, cc.y * sz * 0.42), maxf(h, top) + 1.2, sx * 0.7, yaw, style["crane"])
	if String(style["frame"]) != "mast":
		var fc := -cc
		_add_flag(frame, Vector3(fc.x * sx * 0.4, 0.22, fc.y * sz * 0.4), h + 0.7, style["flag"])
	var fx := _SiteFx.fx_for(style, 2)
	_add_site_fx(root, fx, _at(layout["fx_spot"], sx, sz, (0.22 + h * 0.6) if fx == "sparks" else 0.5), 1.0 + 0.25 * n)

static func _foundation_slab(root: Node3D, sx: float, sz: float, style: Dictionary = {}) -> void:
	_add_box(root, Vector3(0, 0.02, 0), Vector3(sx, 0.04, sz), _site_mat("dirt"))
	var slab := "stone" if style.get("frame_mat", "") == "stone" else "concrete"
	_add_box(root, Vector3(0, 0.11, 0), Vector3(sx * 0.86, 0.22, sz * 0.86), _site_mat(slab))

## Puntos de pilar: esquinas para la clase 1, rejilla 3x3 para la 2 y 4x4 para la 3.
static func _grid_points(w: float, d: float, n: int) -> Array:
	var per := n + 1
	var pts: Array = []
	for i in per:
		for j in per:
			pts.append(Vector2(lerpf(-w * 0.5, w * 0.5, float(i) / float(per - 1)), lerpf(-d * 0.5, d * 0.5, float(j) / float(per - 1))))
	return pts

## Los apoyos de cada silueta: en rejilla, o en anillo para las redondas
## (cupula, depositos, pilon).
static func _frame_points(w: float, d: float, n: int, shape: String) -> Array:
	if shape in ["dome", "basin", "tanks"]:
		var pts: Array = []
		var count := 4 + 2 * n
		for k in count:
			var a := TAU * k / count
			pts.append(Vector2(cos(a) * w * 0.48, sin(a) * d * 0.48))
		return pts
	return _grid_points(w, d, n)

## Una barra entre dos puntos (pilar inclinado, cabio, riostra).
static func _strut(parent: Node3D, a: Vector3, b: Vector3, thick: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mid := (a + b) * 0.5
	var length := a.distance_to(b)
	var mi := _add_box(parent, mid, Vector3(thick, length, thick), mat)
	var dir := (b - a).normalized()
	if absf(dir.dot(Vector3.UP)) < 0.999:
		var axis := Vector3.UP.cross(dir).normalized()
		mi.basis = Basis(axis, Vector3.UP.angle_to(dir))
	return mi

## La silueta de la fase 2, que insinua el edificio terminado. Devuelve la
## altura de su punto mas alto (para que la grua quede por encima).
static func _frame_shape(f: Node3D, sx: float, sz: float, n: int, h: float, style: Dictionary, layout: Dictionary) -> float:
	var shape := String(style["frame"])
	var mat := _site_mat({"wood": "wood", "stone": "stone"}.get(String(style["frame_mat"]), "steel"))
	var steel := _site_mat("steel")
	var base := 0.22
	var top := base + h
	var cc: Vector2 = layout["crane_corner"]
	match shape:
		"chimney":
			_pillars(f, sx, sz, n, h * 0.8, mat, true)
			var c := Vector3(-cc.x * sx * 0.26, 0, -cc.y * sz * 0.26)
			var ch := h * 1.9
			_add_cylinder(f, c + Vector3(0, base + ch * 0.5, 0), 0.3, ch, _site_mat("brick"), 8)
			for y in [0.45, 0.8]:
				_add_torus(f, c + Vector3(0, base + ch * y, 0), 0.28, 0.36, steel, 8, 4)
			top = base + ch
		"gable", "hall":
			var hall := shape == "hall"
			_pillars(f, sx, sz, n, h, mat, false)
			var roof := sz * (0.2 if hall else 0.36)
			var count := n + 2
			for i in count:
				var x := lerpf(-sx * 0.4, sx * 0.4, float(i) / float(count - 1))
				var apex := Vector3(x, base + h + roof, 0)
				_strut(f, Vector3(x, base + h, sz * 0.42), apex, 0.08, mat)
				_strut(f, Vector3(x, base + h, -sz * 0.42), apex, 0.08, mat)
				if hall:
					_add_box(f, Vector3(x, base + h, 0), Vector3(0.07, 0.07, sz * 0.84), mat)
			_add_box(f, Vector3(0, base + h + roof, 0), Vector3(sx * 0.84, 0.09, 0.09), mat)
			top = base + h + roof
		"tower":
			var th := h * 1.75
			var w := 0.3
			var feet := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
			for k in 4:
				var a: Vector2 = feet[k]
				var b: Vector2 = feet[(k + 1) % 4]
				_strut(f, Vector3(a.x * sx * w, base, a.y * sz * w), Vector3(a.x * sx * w * 0.6, base + th, a.y * sz * w * 0.6), 0.14, mat)
				# Riostra en aspa por cara: la celosia de una torre.
				_strut(f, Vector3(a.x * sx * w, base, a.y * sz * w), Vector3(b.x * sx * w * 0.8, base + th * 0.5, b.y * sz * w * 0.8), 0.06, mat)
			for lv in [0.5, 1.0]:
				var s := lerpf(1.0, 0.6, lv)
				_add_box(f, Vector3(0, base + th * lv, 0), Vector3(sx * w * 2.0 * s + 0.15, 0.08, sz * w * 2.0 * s + 0.15), mat)
			top = base + th
		"tanks":
			var r := minf(sx, sz) * 0.2
			for side in [-1.0, 1.0]:
				var c := Vector3(side * sx * 0.22, 0, 0)
				for y in [0.3, 0.65, 0.95]:
					_add_torus(f, c + Vector3(0, base + h * y, 0), r - 0.04, r + 0.03, mat, 12, 4)
				for k in 6:
					var a := TAU * k / 6.0
					_add_box(f, c + Vector3(cos(a) * r, base + h * 0.5, sin(a) * r), Vector3(0.06, h, 0.06), mat)
			# Uno ya medio chapado y una tuberia que los une.
			_add_cylinder(f, Vector3(sx * 0.22, base + h * 0.2, 0), r, h * 0.4, _site_mat("sheet"), 10)
			var pipe := _add_cylinder(f, Vector3(0, base + h * 0.35, sz * 0.12), 0.06, sx * 0.44, _site_mat("copper"), 6)
			pipe.rotation.z = PI * 0.5
		"dome":
			var R := minf(sx, sz) * 0.4
			var ring_h := h * 0.55
			for p in _frame_points(sx * 0.8, sz * 0.8, n, shape):
				_add_box(f, Vector3(p.x, base + ring_h * 0.5, p.y), Vector3(0.14, ring_h, 0.14), mat)
			_add_torus(f, Vector3(0, base + ring_h, 0), R - 0.05, R + 0.05, mat, 16, 4)
			# Nervios de la cupula: cuartos de arco, tres tramos cada uno.
			for k in 6:
				var rib := _group(f, "Rib%d" % k)
				rib.rotation.y = TAU * k / 6.0
				var prev := Vector3(R, base + ring_h, 0)
				for s in range(1, 4):
					var phi := PI * 0.5 * s / 3.0
					var next := Vector3(R * cos(phi), base + ring_h + R * 0.9 * sin(phi), 0)
					_strut(rib, prev, next, 0.07, mat)
					prev = next
			top = base + ring_h + R * 0.9
		"plinth":
			var stone := _site_mat("stone")
			for i in 3:
				var s := 0.8 - 0.18 * i
				_add_box(f, Vector3(0, base + 0.12 + 0.24 * i, 0), Vector3(sx * s, 0.24, sz * s), stone if i % 2 == 0 else _site_mat("stone_dark"))
			# La figura, aun tapada con la lona, y los pies de un andamio de madera.
			var fig_h := h * 0.9
			_add_box(f, Vector3(0, base + 0.72 + fig_h * 0.5, 0), Vector3(0.45, fig_h, 0.4), _site_color_mat(style["tarp"]))
			_add_sphere(f, Vector3(0, base + 0.72 + fig_h + 0.12, 0), 0.2, _site_color_mat(style["tarp"]), 8)
			for s in _LookRule.CORNERS:
				_add_cylinder(f, Vector3(s.x * sx * 0.3, base + h * 0.6, s.y * sz * 0.3), 0.035, h * 1.2, _site_mat("dark_wood"), 6)
			top = base + 0.72 + fig_h + 0.3
		"basin":
			var stone := _site_mat("stone")
			var count := 10 + 2 * n
			for k in count:
				if k % 5 == 4:
					continue   # huecos: el pilon aun no esta cerrado
				var a := TAU * k / count
				var blk := _add_box(f, Vector3(cos(a) * sx * 0.38, base + 0.18, sin(a) * sz * 0.38), Vector3(0.36, 0.36, 0.22), stone)
				blk.rotation.y = -a + PI * 0.5
			_add_cylinder(f, Vector3(0, base + 0.5, 0), 0.08, 1.0, _site_mat("copper"), 6)
			# Cabria de tres patas sobre el centro, para subir la pila.
			var apex := Vector3(0, base + h * 1.1, 0)
			for k in 3:
				var a := TAU * k / 3.0 + 0.3
				_strut(f, Vector3(cos(a) * sx * 0.32, base, sin(a) * sz * 0.32), apex, 0.07, _site_mat("dark_wood"))
			top = apex.y
		"headframe":
			_pillars(f, sx, sz, 1, h * 0.45, mat, true)
			var apex_h := h * 1.7
			for zs in [-1.0, 1.0]:
				for xs in [-1.0, 1.0]:
					_strut(f, Vector3(xs * sx * 0.35, base, zs * sz * 0.18), Vector3(0, base + apex_h, zs * sz * 0.1), 0.1, mat)
			var wheel := _add_torus(f, Vector3(0, base + apex_h + 0.25, 0), 0.26, 0.34, steel, 12, 4)
			wheel.rotation.x = PI * 0.5
			top = base + apex_h + 0.6
		"low":
			# Pergola de madera y bancales: lo que sera el jardin.
			for s in _LookRule.CORNERS:
				_add_box(f, Vector3(s.x * sx * 0.32, base + h * 0.4, s.y * sz * 0.32), Vector3(0.1, h * 0.8, 0.1), mat)
			for i in 4:
				var x := lerpf(-sx * 0.32, sx * 0.32, float(i) / 3.0)
				_add_box(f, Vector3(x, base + h * 0.8, 0), Vector3(0.06, 0.06, sz * 0.7), mat)
			for zs in [-1.0, 1.0]:
				_add_box(f, Vector3(0, base + h * 0.8, zs * sz * 0.32), Vector3(sx * 0.7, 0.08, 0.08), mat)
				_add_box(f, Vector3(0, base + 0.08, zs * sz * 0.18), Vector3(sx * 0.6, 0.12, sz * 0.18), _site_mat("soil"))
			top = base + h * 0.8
		"mast":
			_pillars(f, sx, sz, n, h, mat, true)
			var mh := h * 2.2
			_add_cylinder(f, Vector3(0, base + mh * 0.5, 0), 0.07, mh, steel, 6)
			_add_flag(f, Vector3(0, base + mh - 0.7, 0), 0.7, style["flag"])
			top = base + mh
		_:
			_pillars(f, sx, sz, n, h, mat, true)
	return top

## Pilares en rejilla, medio forjado detras y (si `ring`) vigas de coronacion.
static func _pillars(f: Node3D, sx: float, sz: float, n: int, h: float, mat: StandardMaterial3D, ring: bool) -> void:
	var base := 0.22
	for p in _grid_points(sx * 0.8, sz * 0.8, n):
		_add_box(f, Vector3(p.x, base + h * 0.5, p.y), Vector3(0.18, h, 0.18), mat)
	_add_box(f, Vector3(0, base + h * 0.5, -sz * 0.2), Vector3(sx * 0.82, 0.12, sz * 0.42), _site_mat("concrete"))
	if not ring:
		return
	var top := base + h
	_add_box(f, Vector3(0, top, -sz * 0.4), Vector3(sx * 0.82, 0.12, 0.12), mat)
	_add_box(f, Vector3(0, top, sz * 0.4), Vector3(sx * 0.82, 0.12, 0.12), mat)
	_add_box(f, Vector3(-sx * 0.4, top, 0), Vector3(0.12, 0.12, sz * 0.82), mat)
	_add_box(f, Vector3(sx * 0.4, top, 0), Vector3(0.12, 0.12, sz * 0.82), mat)

## Andamio en el lado `side` (0 delante +Z, 1 +X, 2 detras, 3 -X): pies
## derechos y plataformas de tabla.
static func _add_scaffold_side(root: Node3D, sx: float, sz: float, h: float, side: int = 0) -> void:
	var wood := _site_mat("wood")
	var pole := _site_mat("dark_wood")
	var nrm := _LookRule.side_normal(side)
	var length := sx if nrm.x == 0.0 else sz
	var off := (sz if nrm.x == 0.0 else sx) * 0.5
	var along := Vector2(-nrm.y, nrm.x)
	for i in 3:
		var p := nrm * off + along * lerpf(-length * 0.42, length * 0.42, float(i) / 2.0)
		_add_cylinder(root, Vector3(p.x, h * 0.5 + 0.1, p.y), 0.035, h + 0.2, pole, 6)
	var level := 0.7
	while level < h:
		var plank := _add_box(root, Vector3(nrm.x * off, level, nrm.y * off), Vector3(length * 0.86, 0.05, 0.28), wood)
		plank.rotation.y = 0.0 if nrm.x == 0.0 else PI * 0.5
		level += 0.75

## Malla de varias cajas fundidas en una, con el origen en el eje de la grua
## (las gira el shader). Cacheada por medidas.
static func _merged_boxes(key: String, parts: Array) -> ArrayMesh:
	if _site_meshes.has(key):
		return _site_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		var box := BoxMesh.new()
		box.size = p[1]
		st.append_from(box, 0, Transform3D(Basis.IDENTITY, p[0]))
	var mesh := st.commit()
	_site_meshes[key] = mesh
	return mesh

static func _shader_mesh(parent: Node3D, node_name: String, mesh: Mesh, mat: Material, pos: Vector3, yaw: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)
	return mi

## Grua: mastil fijo y, en lo alto, pluma + contrapeso + cable con gancho
## (tres mallas con el origen en el eje) que gira el shader de SiteFx, cada
## grua a su ritmo; el gancho sube y baja. `yaw`: hacia donde apunta en reposo.
static func _add_crane(root: Node3D, base: Vector3, height: float, jib: float, yaw: float = 0.0, color: Color = Color(0.95, 0.72, 0.1)) -> void:
	_add_box(root, base + Vector3(0, height * 0.5, 0), Vector3(0.16, height, 0.16), _site_color_mat(color))
	_add_box(root, base + Vector3(0, height - 0.25, 0), Vector3(0.3, 0.3, 0.3), _site_mat("concrete_dark"))
	var pivot := base + Vector3(0, height, 0)
	var k := "%.2f" % jib
	var arm := _merged_boxes("jib:" + k, [[Vector3(-jib * 0.4, 0, 0), Vector3(jib, 0.1, 0.1)],
		[Vector3(-jib * 0.75, -0.06, 0), Vector3(0.16, 0.08, 0.14)]])
	_shader_mesh(root, "CraneJib", arm, _SiteFx.crane_material_3d(color), pivot, yaw)
	var weight := _merged_boxes("weight:" + k, [[Vector3(jib * 0.18, -0.12, 0), Vector3(0.3, 0.24, 0.24)]])
	_shader_mesh(root, "CraneWeight", weight, _SiteFx.crane_material_3d(COL_CONCRETE), pivot, yaw)
	var hook := _merged_boxes("hook:" + k, [[Vector3(-jib * 0.75, -0.5, 0), Vector3(0.025, 1.0, 0.025)],
		[Vector3(-jib * 0.75, -1.02, 0), Vector3(0.14, 0.12, 0.14)]])
	_shader_mesh(root, "CraneHook", hook, _SiteFx.crane_material_3d(COL_DARK_IRON, 0.55), pivot, yaw)

## Banderin en su palo: el palo es fijo y la tela la ondea el shader de SiteFx.
static func _add_flag(parent: Node3D, foot: Vector3, pole_h: float, color: Color) -> void:
	_add_cylinder(parent, foot + Vector3(0, pole_h * 0.5, 0), 0.025, pole_h, _site_mat("dark_wood"), 6)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.24)
	quad.subdivide_width = 4
	quad.center_offset = Vector3(0.21, 0, 0)
	var mi := _shader_mesh(parent, "SiteFlag", quad, _SiteFx.flag_material_3d(color), foot + Vector3(0.02, pole_h - 0.14, 0), 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Chispas o polvo de obra (hoja animada de BuildingFx). "" = nada.
static func _add_site_fx(root: Node3D, kind: String, pos: Vector3, size: float) -> void:
	if kind == "":
		return
	var q := _Fx.quad_3d(kind, size, "site" if kind == "dust" else "")
	q.name = "SiteFx_" + kind
	q.position = pos + Vector3(0, size * 0.3, 0)
	root.add_child(q)

## Andamio alrededor de un edificio que se esta MEJORANDO: el edificio sigue a
## la vista y el andamio dice que hay obra. Raiz "UpgradeScaffold".
static func create_scaffold(footprint: Vector2i, cell_size: float, height: float) -> Node3D:
	var d := _foot_dims(footprint, cell_size)
	var root := Node3D.new()
	root.name = "UpgradeScaffold"
	var h := maxf(1.0, height)
	var pole := _site_mat("dark_wood")
	var wood := _site_mat("wood")
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(0, 1), Vector2(0, -1)]:
		_add_cylinder(root, Vector3(s.x * d.x * 0.52, h * 0.5, s.y * d.y * 0.52), 0.035, h, pole, 6)
	var level := 0.8
	while level < h:
		_add_box(root, Vector3(0, level, d.y * 0.52), Vector3(d.x * 1.04, 0.05, 0.22), wood)
		_add_box(root, Vector3(0, level, -d.y * 0.52), Vector3(d.x * 1.04, 0.05, 0.22), wood)
		level += 0.9
	_add_box(root, Vector3(0, h * 0.5, d.y * 0.53), Vector3(d.x, 0.07, 0.03), _site_mat("hazard"))
	return root

## Escombros de una ruina, alrededor del modelo hundido y tiznado: suelo
## quemado, montones de cascote, un muro roto y vigas carbonizadas al aire.
## Determinista por `seed_val`: la misma ruina se ve igual tras cargar.
## Raiz "RuinOverlay".
static func create_ruin_overlay(footprint: Vector2i, cell_size: float, seed_val: int = 0) -> Node3D:
	var d := _foot_dims(footprint, cell_size)
	var n := clampi(maxi(footprint.x, footprint.y), 1, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var root := Node3D.new()
	root.name = "RuinOverlay"
	_add_box(root, Vector3(0, 0.015, 0), Vector3(d.x * 1.05, 0.03, d.y * 1.05), _site_mat("scorch"))
	var rubble := _site_mat("rubble")
	var dark := _site_mat("concrete_dark")
	for k in 3 + n * 2:
		var p := Vector3(rng.randf_range(-0.45, 0.45) * d.x, 0.0, rng.randf_range(-0.45, 0.45) * d.y)
		var s := Vector3(rng.randf_range(0.25, 0.6), rng.randf_range(0.12, 0.35), rng.randf_range(0.25, 0.6)) * (0.8 + 0.2 * n)
		var b := _add_box(root, p + Vector3(0, s.y * 0.4, 0), s, rubble if k % 2 == 0 else dark)
		b.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
	# Muro roto: tres trozos de altura decreciente en el lado de atras.
	var wall_h := [1.1, 0.7, 0.35]
	for i in 3:
		var w := d.x * 0.26
		var hh: float = float(wall_h[i]) * (0.8 + 0.25 * n)
		_add_box(root, Vector3(-d.x * 0.33 + i * w, hh * 0.5, -d.y * 0.45), Vector3(w * 0.92, hh, 0.16), dark)
	# Vigas carbonizadas clavadas en angulo: la silueta que se lee de lejos.
	var char_mat := _site_mat("char")
	for k in 2 + n:
		var beam := _add_box(root, Vector3(rng.randf_range(-0.3, 0.3) * d.x, 0.6, rng.randf_range(-0.3, 0.3) * d.y), Vector3(0.12, 1.4 + 0.3 * n, 0.12), char_mat)
		beam.rotation = Vector3(rng.randf_range(0.4, 0.9) * (1.0 if k % 2 == 0 else -1.0), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
	return root
