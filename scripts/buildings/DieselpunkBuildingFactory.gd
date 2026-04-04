class_name DieselpunkBuildingFactory
## Generates procedural dieselpunk 3D meshes for each building type.
## Each building has a distinct silhouette with industrial details:
## smokestacks, pipes, riveted panels, gears, glowing elements.

# ── Material palette ──

static func _metal(color: Color, metallic: float = 0.7, roughness: float = 0.45) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat

static func _emissive(color: Color, energy: float = 1.5) -> StandardMaterial3D:
	var mat: StandardMaterial3D = _metal(color, 0.0, 0.9)
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
static func _add_rivets(parent: Node3D, start: Vector3, end: Vector3, count: int, radius: float = 0.04) -> void:
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
		"house": return _build_house(sx, sz)
		"garden": return _build_garden(sx, sz)
		"fountain": return _build_fountain(sx, sz)
		"statue": return _build_statue(sx, sz)
		"road": return _build_road(sx, sz, 0)
	return null

## Create a road mesh with neighbor connectivity.
## neighbors is a bitmask: NORTH=1, EAST=2, SOUTH=4, WEST=8
static func create_road(cell_size: float, neighbors: int = 0) -> Node3D:
	var sx: float = cell_size * 0.9
	var sz: float = cell_size * 0.9
	return _build_road(sx, sz, neighbors)


# ════════════════════════════════════════════════════════════════
# NUCLEO — Monumental dieselpunk imperial citadel
# Tiered fortress with central dome, four corner towers,
# grand columned entrance, industrial pipes, gears, searchlights
# ════════════════════════════════════════════════════════════════
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

	# Scale the entire citadel up to be imposing (1.6x taller)
	root.scale = Vector3(1.0, 1.6, 1.0)
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
# SAWMILL — Timber frame, saw blade, log pile, conveyor
# ════════════════════════════════════════════════════════════════
static func _build_sawmill(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_wood: StandardMaterial3D = _metal(COL_DARK_WOOD, 0.1, 0.85)
	var mat_iron: StandardMaterial3D = _metal(COL_DARK_IRON, 0.8, 0.4)
	var mat_brass: StandardMaterial3D = _metal(COL_BRASS, 0.9, 0.3)
	var mat_light_wood: StandardMaterial3D = _metal(Color(0.55, 0.40, 0.22), 0.1, 0.8)

	# Main timber frame structure — open shed
	# Four corner posts
	_add_box(root, Vector3(-sx * 0.4, 0.7, -sz * 0.35), Vector3(0.12, 1.4, 0.12), mat_wood)
	_add_box(root, Vector3(sx * 0.4, 0.7, -sz * 0.35), Vector3(0.12, 1.4, 0.12), mat_wood)
	_add_box(root, Vector3(-sx * 0.4, 0.7, sz * 0.35), Vector3(0.12, 1.4, 0.12), mat_wood)
	_add_box(root, Vector3(sx * 0.4, 0.7, sz * 0.35), Vector3(0.12, 1.4, 0.12), mat_wood)
	# Corrugated metal roof
	_add_box(root, Vector3(0, 1.5, 0), Vector3(sx * 0.95, 0.06, sz * 0.85), mat_iron)
	_add_prism(root, Vector3(0, 1.7, 0), Vector3(sx * 0.95, 0.35, sz * 0.85), mat_iron)

	# Saw blade (large torus in the center, vertical)
	var blade: MeshInstance3D = _add_torus(root, Vector3(0, 0.8, 0), 0.15, 0.35, mat_iron, 8, 16)
	blade.rotation.z = PI / 2.0
	# Blade axle
	_add_cylinder(root, Vector3(0, 0.8, 0), 0.04, sz * 0.5, mat_brass)

	# Conveyor table (flat platform for logs)
	_add_box(root, Vector3(-sx * 0.15, 0.55, 0), Vector3(sx * 0.35, 0.06, sz * 0.4), mat_iron)
	_add_box(root, Vector3(sx * 0.15, 0.55, 0), Vector3(sx * 0.35, 0.06, sz * 0.4), mat_iron)

	# Log on the conveyor (horizontal cylinder)
	var log: MeshInstance3D = _add_cylinder(root, Vector3(-sx * 0.2, 0.65, 0), 0.1, sx * 0.3, mat_light_wood)
	log.rotation.z = PI / 2.0

	# Log pile (stacked logs on one side)
	for i in range(3):
		var l: MeshInstance3D = _add_cylinder(root, Vector3(sx * 0.35, 0.12 + i * 0.18, -sz * 0.15 + i * 0.02), 0.08, sz * 0.4, mat_light_wood)
		l.rotation.x = PI / 2.0
	# Second row
	for i in range(2):
		var l: MeshInstance3D = _add_cylinder(root, Vector3(sx * 0.35, 0.48 + i * 0.18, -sz * 0.1), 0.08, sz * 0.3, mat_light_wood)
		l.rotation.x = PI / 2.0

	# Belt/gear mechanism
	_add_torus(root, Vector3(-sx * 0.35, 0.8, -sz * 0.3), 0.06, 0.14, mat_brass, 6)
	# Drive belt (thin box connecting)
	_add_box(root, Vector3(-sx * 0.18, 0.8, -sz * 0.3), Vector3(sx * 0.35, 0.02, 0.04), mat_iron)

	# Wood chips / sawdust pile
	_add_sphere(root, Vector3(sx * 0.1, 0.08, sz * 0.3), 0.15, _metal(Color(0.6, 0.45, 0.25), 0.0, 0.95))

	# Smokestack (small steam engine)
	_add_cylinder(root, Vector3(-sx * 0.38, 1.9, -sz * 0.25), 0.07, 0.5, mat_iron)

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
	var mat_pave := _metal(Color(0.35, 0.33, 0.3), 0.2, 0.85)
	var mat_edge := _metal(Color(0.28, 0.26, 0.24), 0.3, 0.8)
	var mat_line := _metal(Color(0.45, 0.42, 0.38), 0.15, 0.9)

	var has_n := (neighbors & 1) != 0
	var has_e := (neighbors & 2) != 0
	var has_s := (neighbors & 4) != 0
	var has_w := (neighbors & 8) != 0

	# Center pad (always present)
	_add_box(root, Vector3(0, 0.025, 0), Vector3(sx * 0.5, 0.05, sz * 0.5), mat_pave)

	# Connection strips toward each neighbor
	if has_n:
		_add_box(root, Vector3(0, 0.025, -sz * 0.25), Vector3(sx * 0.5, 0.05, sz * 0.5), mat_pave)
	if has_s:
		_add_box(root, Vector3(0, 0.025, sz * 0.25), Vector3(sx * 0.5, 0.05, sz * 0.5), mat_pave)
	if has_e:
		_add_box(root, Vector3(sx * 0.25, 0.025, 0), Vector3(sx * 0.5, 0.05, sz * 0.5), mat_pave)
	if has_w:
		_add_box(root, Vector3(-sx * 0.25, 0.025, 0), Vector3(sx * 0.5, 0.05, sz * 0.5), mat_pave)

	# Edge stones on sides that DON'T connect
	var half: float = sx * 0.48
	var edge_h := 0.08
	var edge_w := 0.06
	if not has_n:
		_add_box(root, Vector3(0, 0.04, -half), Vector3(sx * 0.5 if neighbors == 0 else sx * 0.5, edge_h, edge_w), mat_edge)
	if not has_s:
		_add_box(root, Vector3(0, 0.04, half), Vector3(sx * 0.5 if neighbors == 0 else sx * 0.5, edge_h, edge_w), mat_edge)
	if not has_e:
		_add_box(root, Vector3(half, 0.04, 0), Vector3(edge_w, edge_h, sz * 0.5 if neighbors == 0 else sz * 0.5), mat_edge)
	if not has_w:
		_add_box(root, Vector3(-half, 0.04, 0), Vector3(edge_w, edge_h, sz * 0.5 if neighbors == 0 else sz * 0.5), mat_edge)

	# Center line markings for straight roads
	if has_n and has_s and not has_e and not has_w:
		_add_box(root, Vector3(0, 0.052, 0), Vector3(0.04, 0.01, sz * 0.8), mat_line)
	elif has_e and has_w and not has_n and not has_s:
		_add_box(root, Vector3(0, 0.052, 0), Vector3(sx * 0.8, 0.01, 0.04), mat_line)

	return root
