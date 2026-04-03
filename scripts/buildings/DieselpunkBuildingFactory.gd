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

static func _add_cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: StandardMaterial3D, segments: int = 12) -> MeshInstance3D:
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

static func _add_cone(parent: Node3D, pos: Vector3, bottom_r: float, top_r: float, height: float, mat: StandardMaterial3D, segments: int = 12) -> MeshInstance3D:
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

static func _add_torus(parent: Node3D, pos: Vector3, inner_r: float, outer_r: float, mat: StandardMaterial3D, rings: int = 12, segments: int = 12) -> MeshInstance3D:
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

static func _add_sphere(parent: Node3D, pos: Vector3, radius: float, mat: StandardMaterial3D, segments: int = 12) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = segments / 2
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
		_add_sphere(parent, pos, radius, mat, 6)

# Horizontal pipe between two points
static func _add_pipe(parent: Node3D, from: Vector3, to: Vector3, radius: float, mat: StandardMaterial3D) -> void:
	var mid: Vector3 = (from + to) * 0.5
	var diff: Vector3 = to - from
	var length: float = diff.length()
	var mi: MeshInstance3D = _add_cylinder(parent, mid, radius, length, mat, 8)
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
		"road": return _build_road(sx, sz)
	return null


# ════════════════════════════════════════════════════════════════
# NUCLEO — Presidential palace, cyberpunk neoclassical
# Columned facade, central dome, neon accents, antenna spire
# ════════════════════════════════════════════════════════════════
static func _build_nucleo(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()

	# Materials
	var mat_marble := _metal(Color(0.85, 0.82, 0.78), 0.15, 0.55)
	var mat_dark := _metal(Color(0.18, 0.18, 0.22), 0.85, 0.35)
	var mat_gold := _metal(Color(0.82, 0.68, 0.2), 0.95, 0.25)
	var mat_neon_cyan := _emissive(Color(0.1, 0.9, 0.95), 2.5)
	var mat_neon_amber := _emissive(Color(1.0, 0.7, 0.1), 1.8)
	var mat_window := _emissive(Color(0.2, 0.6, 0.9), 0.6)
	var mat_roof := _metal(Color(0.25, 0.28, 0.32), 0.7, 0.4)

	# ── Foundation platform (stepped) ──
	_add_box(root, Vector3(0, 0.1, 0), Vector3(sx * 0.98, 0.2, sz * 0.98), mat_dark)
	_add_box(root, Vector3(0, 0.25, 0), Vector3(sx * 0.93, 0.12, sz * 0.93), mat_marble)

	# ── Main body — wide, 2-story presidential block ──
	_add_box(root, Vector3(0, 1.1, 0), Vector3(sx * 0.82, 1.5, sz * 0.7), mat_marble)

	# ── Front portico (extended entrance with columns) ──
	_add_box(root, Vector3(0, 0.9, sz * 0.38), Vector3(sx * 0.5, 1.1, sz * 0.12), mat_marble)

	# ── Columns (6 across the front) ──
	var col_count := 6
	var col_spacing := sx * 0.7 / float(col_count - 1)
	var col_start_x := -sx * 0.35
	for i in range(col_count):
		var cx := col_start_x + i * col_spacing
		_add_cylinder(root, Vector3(cx, 1.0, sz * 0.44), 0.07, 1.5, mat_marble, 8)
		# Gold capital on top of each column
		_add_box(root, Vector3(cx, 1.78, sz * 0.44), Vector3(0.16, 0.06, 0.16), mat_gold)

	# ── Portico entablature (beam above columns) ──
	_add_box(root, Vector3(0, 1.85, sz * 0.44), Vector3(sx * 0.55, 0.1, 0.18), mat_marble)
	# Triangular pediment
	_add_prism(root, Vector3(0, 2.1, sz * 0.44), Vector3(sx * 0.5, 0.4, 0.16), mat_marble)

	# ── Central dome ──
	_add_cylinder(root, Vector3(0, 2.0, 0), sx * 0.18, 0.2, mat_roof, 16)
	_add_sphere(root, Vector3(0, 2.45, 0), sx * 0.18, mat_roof, 16)
	# Dome top spire
	_add_cylinder(root, Vector3(0, 2.85, 0), 0.03, 0.5, mat_gold, 6)
	_add_sphere(root, Vector3(0, 3.15, 0), 0.06, mat_neon_amber, 6)

	# ── Side wings ──
	_add_box(root, Vector3(sx * 0.35, 0.85, 0), Vector3(sx * 0.22, 1.1, sz * 0.55), mat_marble)
	_add_box(root, Vector3(-sx * 0.35, 0.85, 0), Vector3(sx * 0.22, 1.1, sz * 0.55), mat_marble)

	# ── Windows (glowing cyan, cyberpunk style) ──
	# Front windows
	for i in range(4):
		var wx := -sx * 0.28 + i * sx * 0.19
		_add_box(root, Vector3(wx, 1.2, sz * 0.351), Vector3(0.18, 0.35, 0.02), mat_window)
		# Neon trim under each window
		_add_box(root, Vector3(wx, 0.98, sz * 0.352), Vector3(0.2, 0.03, 0.02), mat_neon_cyan)

	# Side windows
	for side in [-1.0, 1.0]:
		for j in range(2):
			var wz := -sz * 0.15 + j * sz * 0.25
			_add_box(root, Vector3(side * sx * 0.411, 1.2, wz), Vector3(0.02, 0.3, 0.15), mat_window)

	# ── Neon accent lines (cyberpunk) ──
	# Horizontal neon strips along building edges
	_add_box(root, Vector3(0, 1.88, sz * 0.351), Vector3(sx * 0.84, 0.025, 0.02), mat_neon_cyan)
	_add_box(root, Vector3(0, 0.35, sz * 0.351), Vector3(sx * 0.84, 0.025, 0.02), mat_neon_cyan)
	# Back neon
	_add_box(root, Vector3(0, 1.88, -sz * 0.351), Vector3(sx * 0.84, 0.025, 0.02), mat_neon_cyan)
	# Side neon strips
	_add_box(root, Vector3(sx * 0.461, 1.88, 0), Vector3(0.02, 0.025, sz * 0.56), mat_neon_cyan)
	_add_box(root, Vector3(-sx * 0.461, 1.88, 0), Vector3(0.02, 0.025, sz * 0.56), mat_neon_cyan)

	# ── Roof details ──
	_add_box(root, Vector3(0, 1.92, 0), Vector3(sx * 0.85, 0.06, sz * 0.73), mat_roof)

	# ── Antenna towers on wings ──
	for side in [-1.0, 1.0]:
		_add_cylinder(root, Vector3(side * sx * 0.35, 2.0, -sz * 0.2), 0.04, 0.8, mat_dark, 6)
		_add_sphere(root, Vector3(side * sx * 0.35, 2.45, -sz * 0.2), 0.05, mat_neon_amber, 6)

	# ── Gold eagle/emblem on pediment ──
	_add_sphere(root, Vector3(0, 2.15, sz * 0.46), 0.1, mat_gold, 8)

	# ── Rivets along foundation ──
	_add_rivets(root, Vector3(-sx * 0.45, 0.32, sz * 0.47), Vector3(sx * 0.45, 0.32, sz * 0.47), 10)

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
	_add_cylinder(root, Vector3(tower_x, 3.5, tower_z), 0.06, 2.5, mat_dark, 6)
	_add_cylinder(root, Vector3(tower_x, 4.6, tower_z), 0.03, 0.8, mat_brass, 6)
	# Antenna crossbars
	_add_box(root, Vector3(tower_x, 4.2, tower_z), Vector3(0.5, 0.03, 0.03), mat_brass)
	_add_box(root, Vector3(tower_x, 4.5, tower_z), Vector3(0.35, 0.03, 0.03), mat_brass)
	# Blinking light at top
	_add_sphere(root, Vector3(tower_x, 5.05, tower_z), 0.06, _emissive(Color(1, 0.2, 0.1), 2.0), 6)

	# Side armor plates (angled reinforcement)
	_add_box(root, Vector3(sx * 0.44, 0.8, 0), Vector3(0.08, 1.2, sz * 0.6), mat_dark)
	_add_box(root, Vector3(-sx * 0.44, 0.8, 0), Vector3(0.08, 1.2, sz * 0.6), mat_dark)

	# Rivets along top edge
	_add_rivets(root, Vector3(-sx * 0.4, 2.42, sz * 0.4), Vector3(sx * 0.4, 2.42, sz * 0.4), 8)
	_add_rivets(root, Vector3(-sx * 0.4, 2.42, -sz * 0.4), Vector3(sx * 0.4, 2.42, -sz * 0.4), 8)

	# Exhaust pipes on back
	_add_cylinder(root, Vector3(-sx * 0.25, 2.8, -sz * 0.4), 0.08, 0.5, mat_copper())
	_add_cylinder(root, Vector3(-sx * 0.1, 2.8, -sz * 0.4), 0.08, 0.5, mat_copper())

	# Door (dark recessed area on front)
	_add_box(root, Vector3(0, 0.7, sz * 0.43), Vector3(sx * 0.25, 1.2, 0.06), mat_dark)
	# Door handle/lock
	_add_sphere(root, Vector3(sx * 0.08, 0.7, sz * 0.46), 0.04, mat_brass, 6)

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
	_add_cylinder(root, Vector3(sx * 0.25, 2.3, -sz * 0.15), 0.1, 0.7, mat_iron, 8)
	_add_cone(root, Vector3(sx * 0.25, 2.7, -sz * 0.15), 0.14, 0.06, 0.15, mat_iron, 8)

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
	_add_cylinder(root, Vector3(wt_x, 1.5, wt_z), 0.06, 3.0, mat_iron, 6)
	_add_box(root, Vector3(wt_x, 2.9, wt_z), Vector3(0.5, 0.05, 0.5), mat_iron)
	# Spotlight on watchtower
	_add_cone(root, Vector3(wt_x, 3.1, wt_z + 0.15), 0.12, 0.04, 0.2, _emissive(COL_SEARCHLIGHT, 1.0), 8)

	# Iron reinforcement strips on walls
	_add_box(root, Vector3(0, 0.5, sz * 0.41), Vector3(sx * 0.85, 0.06, 0.02), mat_iron)
	_add_box(root, Vector3(0, 1.3, sz * 0.41), Vector3(sx * 0.85, 0.06, 0.02), mat_iron)

	# Rivets
	_add_rivets(root, Vector3(-sx * 0.35, 1.82, sz * 0.42), Vector3(sx * 0.35, 1.82, sz * 0.42), 7)

	# Door
	_add_box(root, Vector3(sx * 0.15, 0.7, sz * 0.42), Vector3(sx * 0.2, 1.2, 0.04), mat_iron)

	# Flag pole
	_add_cylinder(root, Vector3(sx * 0.38, 2.0, sz * 0.38), 0.03, 2.0, mat_iron, 4)
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
	_add_cylinder(root, Vector3(-sx * 0.12, hf_h * 0.5, sz * 0.1), 0.06, hf_h, mat_iron, 6)
	_add_cylinder(root, Vector3(sx * 0.12, hf_h * 0.5, sz * 0.1), 0.06, hf_h, mat_iron, 6)
	_add_cylinder(root, Vector3(-sx * 0.12, hf_h * 0.5, -sz * 0.05), 0.06, hf_h, mat_iron, 6)
	_add_cylinder(root, Vector3(sx * 0.12, hf_h * 0.5, -sz * 0.05), 0.06, hf_h, mat_iron, 6)
	# Crossbeams
	_add_box(root, Vector3(0, hf_h * 0.35, sz * 0.025), Vector3(sx * 0.28, 0.04, sz * 0.18), mat_iron)
	_add_box(root, Vector3(0, hf_h * 0.7, sz * 0.025), Vector3(sx * 0.28, 0.04, sz * 0.18), mat_iron)
	# Pulley wheel at top
	_add_torus(root, Vector3(0, hf_h + 0.1, sz * 0.025), 0.08, 0.18, mat_rust, 10, 8)
	# Top platform
	_add_box(root, Vector3(0, hf_h - 0.1, sz * 0.025), Vector3(sx * 0.3, 0.06, sz * 0.2), mat_iron)

	# Engine house (small building beside headframe)
	_add_box(root, Vector3(-sx * 0.3, 0.6, -sz * 0.2), Vector3(sx * 0.3, 1.2, sz * 0.35), mat_rust)
	_add_prism(root, Vector3(-sx * 0.3, 1.3, -sz * 0.2), Vector3(sx * 0.32, 0.4, sz * 0.37), mat_iron)
	# Smokestack on engine house
	_add_cylinder(root, Vector3(-sx * 0.35, 1.8, -sz * 0.25), 0.08, 0.8, mat_iron, 8)
	_add_sphere(root, Vector3(-sx * 0.35, 2.25, -sz * 0.25), 0.06, _emissive(COL_STEAM, 0.5), 6)

	# Ore cart on rails
	_add_box(root, Vector3(sx * 0.25, 0.2, sz * 0.3), Vector3(0.3, 0.2, 0.2), mat_rust)
	# Cart wheels
	_add_cylinder(root, Vector3(sx * 0.2, 0.08, sz * 0.3), 0.06, 0.05, mat_iron, 8)
	_add_cylinder(root, Vector3(sx * 0.3, 0.08, sz * 0.3), 0.06, 0.05, mat_iron, 8)
	# Gold ore pile in cart
	_add_sphere(root, Vector3(sx * 0.25, 0.35, sz * 0.3), 0.1, mat_gold, 6)

	# Rail tracks
	_add_box(root, Vector3(sx * 0.1, 0.02, sz * 0.25), Vector3(sx * 0.6, 0.03, 0.03), mat_iron)
	_add_box(root, Vector3(sx * 0.1, 0.02, sz * 0.35), Vector3(sx * 0.6, 0.03, 0.03), mat_iron)

	# Ore pile on ground
	_add_sphere(root, Vector3(sx * 0.3, 0.15, -sz * 0.3), 0.2, mat_gold, 6)
	_add_sphere(root, Vector3(sx * 0.22, 0.1, -sz * 0.25), 0.15, mat_gold, 6)

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
	_add_cylinder(root, Vector3(-sx * 0.1, 0.15, sz * 0.35), 0.2, 0.3, mat_fire, 8)

	# Large smokestack
	_add_cylinder(root, Vector3(-sx * 0.1, 2.8, 0), 0.2, 1.2, mat_iron, 8)
	_add_cone(root, Vector3(-sx * 0.1, 3.5, 0), 0.25, 0.15, 0.25, mat_iron, 8)
	# Smoke glow
	_add_sphere(root, Vector3(-sx * 0.1, 3.7, 0), 0.12, _emissive(COL_STEAM, 0.8), 6)

	# Second smaller stack
	_add_cylinder(root, Vector3(sx * 0.15, 2.5, -sz * 0.1), 0.12, 0.8, mat_rust, 8)

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
	_add_rivets(root, Vector3(-sx * 0.1 - 0.5, 0.3, -0.2), Vector3(-sx * 0.1 + 0.5, 0.3, -0.2), 6)

	# Molten metal channel on ground (glowing line)
	_add_box(root, Vector3(sx * 0.08, 0.04, sz * 0.15), Vector3(0.4, 0.04, 0.06), mat_fire)

	# Gear on side
	_add_torus(root, Vector3(-sx * 0.1, 1.5, -sz * 0.38), 0.1, 0.2, mat_brass, 8, 8)

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
	_add_torus(root, Vector3(-sx * 0.2, 1.0, -sz * 0.15), 0.32, 0.40, mat_rust, 8, 8)
	_add_torus(root, Vector3(-sx * 0.2, 2.0, -sz * 0.15), 0.32, 0.40, mat_rust, 8, 8)
	_add_torus(root, Vector3(-sx * 0.2, 3.0, -sz * 0.15), 0.32, 0.40, mat_rust, 8, 8)
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
	_add_cylinder(root, Vector3(sx * 0.3, 0.8, -sz * 0.1), 0.04, 1.0, mat_copper, 6)
	_add_cylinder(root, Vector3(-sx * 0.35, 0.6, sz * 0.1), 0.04, 0.8, mat_copper, 6)

	# Valve wheels
	_add_torus(root, Vector3(sx * 0.3, 1.3, -sz * 0.1), 0.04, 0.1, mat_brass, 6, 8)
	_add_torus(root, Vector3(-sx * 0.2, 1.5, sz * 0.06), 0.04, 0.1, mat_brass, 6, 8)

	# Pressure gauge (small disc on pipe)
	_add_cylinder(root, Vector3(sx * 0.1, 2.5, sz * 0.0), 0.08, 0.02, mat_brass, 8)

	# Steam vent
	_add_cylinder(root, Vector3(-sx * 0.2, 3.8, -sz * 0.15), 0.06, 0.3, mat_iron, 6)
	_add_sphere(root, Vector3(-sx * 0.2, 4.0, -sz * 0.15), 0.08, _emissive(COL_STEAM, 0.6), 6)

	# Foundation platform
	_add_box(root, Vector3(0, 0.05, 0), Vector3(sx * 0.95, 0.1, sz * 0.95), _metal(COL_CONCRETE, 0.2, 0.8))

	# Rivets on tank
	_add_rivets(root, Vector3(sx * 0.0, 0.7, sz * 0.58), Vector3(sx * 0.3, 0.7, sz * 0.58), 5)

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
	_add_cylinder(root, Vector3(0, 0.8, 0), 0.04, sz * 0.5, mat_brass, 6)

	# Conveyor table (flat platform for logs)
	_add_box(root, Vector3(-sx * 0.15, 0.55, 0), Vector3(sx * 0.35, 0.06, sz * 0.4), mat_iron)
	_add_box(root, Vector3(sx * 0.15, 0.55, 0), Vector3(sx * 0.35, 0.06, sz * 0.4), mat_iron)

	# Log on the conveyor (horizontal cylinder)
	var log: MeshInstance3D = _add_cylinder(root, Vector3(-sx * 0.2, 0.65, 0), 0.1, sx * 0.3, mat_light_wood, 8)
	log.rotation.z = PI / 2.0

	# Log pile (stacked logs on one side)
	for i in range(3):
		var l: MeshInstance3D = _add_cylinder(root, Vector3(sx * 0.35, 0.12 + i * 0.18, -sz * 0.15 + i * 0.02), 0.08, sz * 0.4, mat_light_wood, 6)
		l.rotation.x = PI / 2.0
	# Second row
	for i in range(2):
		var l: MeshInstance3D = _add_cylinder(root, Vector3(sx * 0.35, 0.48 + i * 0.18, -sz * 0.1), 0.08, sz * 0.3, mat_light_wood, 6)
		l.rotation.x = PI / 2.0

	# Belt/gear mechanism
	_add_torus(root, Vector3(-sx * 0.35, 0.8, -sz * 0.3), 0.06, 0.14, mat_brass, 6, 8)
	# Drive belt (thin box connecting)
	_add_box(root, Vector3(-sx * 0.18, 0.8, -sz * 0.3), Vector3(sx * 0.35, 0.02, 0.04), mat_iron)

	# Wood chips / sawdust pile
	_add_sphere(root, Vector3(sx * 0.1, 0.08, sz * 0.3), 0.15, _metal(Color(0.6, 0.45, 0.25), 0.0, 0.95), 6)

	# Smokestack (small steam engine)
	_add_cylinder(root, Vector3(-sx * 0.38, 1.9, -sz * 0.25), 0.07, 0.5, mat_iron, 8)

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
	_add_cylinder(root, Vector3(0, 0.2, 0), 0.7, 0.4, mat_concrete, 8)

	# Main tower shaft — tapered cylinder (wider at bottom)
	_add_cone(root, Vector3(0, 1.8, 0), 0.55, 0.4, 3.0, mat_iron, 8)

	# Armored rings
	_add_torus(root, Vector3(0, 0.6, 0), 0.48, 0.58, mat_gun, 8, 8)
	_add_torus(root, Vector3(0, 1.6, 0), 0.42, 0.52, mat_gun, 8, 8)
	_add_torus(root, Vector3(0, 2.6, 0), 0.36, 0.46, mat_gun, 8, 8)

	# Observation platform at top
	_add_cylinder(root, Vector3(0, 3.3, 0), 0.6, 0.15, mat_iron, 8)

	# Railing posts
	for i in range(8):
		var angle: float = i * PI * 2.0 / 8.0
		var rx: float = cos(angle) * 0.55
		var rz: float = sin(angle) * 0.55
		_add_cylinder(root, Vector3(rx, 3.55, rz), 0.025, 0.4, mat_iron, 4)

	# Railing ring (top)
	_add_torus(root, Vector3(0, 3.7, 0), 0.5, 0.56, mat_iron, 8, 8)

	# Searchlight housing
	_add_cone(root, Vector3(0, 3.6, 0.35), 0.18, 0.06, 0.25, mat_gun, 8)
	_add_sphere(root, Vector3(0, 3.6, 0.48), 0.08, _emissive(COL_SEARCHLIGHT, 3.0), 6)

	# Gun barrel / cannon
	var cannon: MeshInstance3D = _add_cylinder(root, Vector3(0.3, 3.45, 0), 0.05, 0.6, mat_iron, 6)
	cannon.rotation.x = PI / 10.0
	cannon.rotation.y = PI / 4.0

	# Rivets along base
	_add_rivets(root, Vector3(-0.5, 0.4, 0.2), Vector3(0.5, 0.4, 0.2), 6)

	# Antenna on top
	_add_cylinder(root, Vector3(0, 4.1, 0), 0.02, 0.6, mat_brass, 4)
	_add_sphere(root, Vector3(0, 4.45, 0), 0.04, _emissive(Color(1, 0.2, 0.1), 2.0), 4)

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
	_add_rivets(root, Vector3(-sx * 0.38, 1.28, sz * 0.4), Vector3(sx * 0.38, 1.28, sz * 0.4), 6)
	_add_rivets(root, Vector3(-sx * 0.38, 1.28, -sz * 0.4), Vector3(sx * 0.38, 1.28, -sz * 0.4), 6)

	# Crates stacked outside
	_add_box(root, Vector3(sx * 0.35, 0.15, -sz * 0.25), Vector3(0.25, 0.3, 0.25), mat_wood)
	_add_box(root, Vector3(sx * 0.35, 0.4, -sz * 0.25), Vector3(0.2, 0.2, 0.2), mat_wood)
	_add_box(root, Vector3(sx * 0.2, 0.12, -sz * 0.35), Vector3(0.2, 0.22, 0.2), mat_wood)

	# Ventilation pipe on roof
	_add_cylinder(root, Vector3(sx * 0.2, 1.85, 0), 0.06, 0.3, mat_iron, 6)
	_add_cone(root, Vector3(sx * 0.2, 2.05, 0), 0.09, 0.03, 0.12, mat_iron, 6)

	# Lock/padlock on door
	_add_box(root, Vector3(0.15, 0.35, sz * 0.46), Vector3(0.08, 0.1, 0.04), mat_brass)

	return root


# ════════════════════════════════════════════════════════════════
# HOUSE — Small residential dwelling with chimney and windows
# ════════════════════════════════════════════════════════════════
static func _build_house(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_wall := _metal(Color(0.55, 0.42, 0.28), 0.2, 0.8)
	var mat_roof := _metal(Color(0.45, 0.22, 0.12), 0.3, 0.7)
	var mat_window := _emissive(Color(0.9, 0.75, 0.3), 0.8)
	var mat_chimney := _metal(COL_DARK_IRON, 0.6, 0.5)

	# Main body
	_add_box(root, Vector3(0, 0.6, 0), Vector3(sx * 0.85, 1.2, sz * 0.8), mat_wall)
	# Roof (angled box)
	var roof := _add_box(root, Vector3(0, 1.35, 0), Vector3(sx * 0.95, 0.4, sz * 0.9), mat_roof)
	roof.rotation.x = 0.0
	# Chimney
	_add_cylinder(root, Vector3(sx * 0.25, 1.7, sz * 0.1), 0.08, 0.5, mat_chimney, 6)
	# Windows (glowing)
	_add_box(root, Vector3(sx * 0.25, 0.65, sz * 0.41), Vector3(0.2, 0.2, 0.02), mat_window)
	_add_box(root, Vector3(-sx * 0.2, 0.65, sz * 0.41), Vector3(0.2, 0.2, 0.02), mat_window)
	# Door
	_add_box(root, Vector3(0, 0.35, sz * 0.41), Vector3(0.2, 0.5, 0.02), mat_roof)

	return root


# ════════════════════════════════════════════════════════════════
# GARDEN — Green patch with small bushes/flowers
# ════════════════════════════════════════════════════════════════
static func _build_garden(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_grass := _metal(Color(0.25, 0.5, 0.15), 0.1, 0.9)
	var mat_bush_dark := _metal(Color(0.15, 0.4, 0.12), 0.1, 0.85)
	var mat_bush_light := _metal(Color(0.3, 0.55, 0.2), 0.1, 0.8)
	var mat_flower := _emissive(Color(0.9, 0.3, 0.4), 0.5)

	# Ground
	_add_cylinder(root, Vector3(0, 0.02, 0), sx * 0.45, 0.04, mat_grass, 10)
	# Bushes
	_add_sphere(root, Vector3(-0.2, 0.18, 0.15), 0.2, mat_bush_dark, 6)
	_add_sphere(root, Vector3(0.2, 0.15, -0.1), 0.18, mat_bush_light, 6)
	_add_sphere(root, Vector3(0, 0.12, -0.25), 0.15, mat_bush_dark, 5)
	# Flowers
	_add_sphere(root, Vector3(0.3, 0.1, 0.2), 0.06, mat_flower, 4)
	_add_sphere(root, Vector3(-0.15, 0.1, 0.3), 0.05, mat_flower, 4)

	return root


# ════════════════════════════════════════════════════════════════
# FOUNTAIN — Circular base with water jet
# ════════════════════════════════════════════════════════════════
static func _build_fountain(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_stone := _metal(Color(0.5, 0.48, 0.45), 0.4, 0.6)
	var mat_water := _emissive(Color(0.3, 0.5, 0.8), 0.4)
	var mat_brass := _metal(COL_BRASS, 0.9, 0.3)

	# Base pool
	_add_cylinder(root, Vector3(0, 0.15, 0), 0.55, 0.3, mat_stone, 12)
	# Water
	_add_cylinder(root, Vector3(0, 0.2, 0), 0.45, 0.1, mat_water, 12)
	# Central pillar
	_add_cylinder(root, Vector3(0, 0.6, 0), 0.08, 0.8, mat_stone, 8)
	# Top bowl
	_add_cylinder(root, Vector3(0, 1.05, 0), 0.2, 0.1, mat_stone, 8)
	# Water spray (emissive sphere)
	_add_sphere(root, Vector3(0, 1.2, 0), 0.08, mat_water, 6)
	# Brass accents
	_add_cylinder(root, Vector3(0, 0.95, 0), 0.1, 0.04, mat_brass, 8)

	return root


# ════════════════════════════════════════════════════════════════
# STATUE — Imperial monument on pedestal
# ════════════════════════════════════════════════════════════════
static func _build_statue(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_stone := _metal(Color(0.55, 0.52, 0.48), 0.3, 0.65)
	var mat_bronze := _metal(Color(0.6, 0.45, 0.2), 0.85, 0.35)
	var mat_gold := _emissive(Color(0.9, 0.75, 0.15), 0.5)

	# Pedestal base
	_add_box(root, Vector3(0, 0.2, 0), Vector3(0.6, 0.4, 0.6), mat_stone)
	# Pedestal mid
	_add_box(root, Vector3(0, 0.5, 0), Vector3(0.45, 0.2, 0.45), mat_stone)
	# Figure body
	_add_cylinder(root, Vector3(0, 1.1, 0), 0.15, 1.0, mat_bronze, 8)
	# Head
	_add_sphere(root, Vector3(0, 1.7, 0), 0.12, mat_bronze, 6)
	# Arms (simplified)
	_add_box(root, Vector3(0.2, 1.2, 0), Vector3(0.3, 0.06, 0.06), mat_bronze)
	# Eagle/star on top
	_add_sphere(root, Vector3(0, 1.9, 0), 0.06, mat_gold, 4)
	# Plaque
	_add_box(root, Vector3(0, 0.35, 0.31), Vector3(0.3, 0.12, 0.02), mat_gold)

	return root


# ════════════════════════════════════════════════════════════════
# ROAD — Flat paved surface
# ════════════════════════════════════════════════════════════════
static func _build_road(sx: float, sz: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var mat_pave := _metal(Color(0.35, 0.33, 0.3), 0.2, 0.85)
	var mat_edge := _metal(Color(0.28, 0.26, 0.24), 0.3, 0.8)

	# Main road surface
	_add_box(root, Vector3(0, 0.025, 0), Vector3(sx * 0.95, 0.05, sz * 0.95), mat_pave)
	# Edge stones
	_add_box(root, Vector3(sx * 0.45, 0.04, 0), Vector3(0.06, 0.08, sz * 0.9), mat_edge)
	_add_box(root, Vector3(-sx * 0.45, 0.04, 0), Vector3(0.06, 0.08, sz * 0.9), mat_edge)

	return root
