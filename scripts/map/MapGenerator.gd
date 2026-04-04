extends Node
## Generates random resource deposits on the map.
## Deposits occupy multiple grid cells with random sizes.
## Each deposit has limited uses before depletion.

const DEPOSIT_TYPES := {
	"gold_vein": { "display_name": "DEP_GOLD_VEIN", "color": Color(0.9, 0.75, 0.1, 1), "height": 0.6 },
	"iron_deposit": { "display_name": "DEP_IRON", "color": Color(0.6, 0.6, 0.65, 1), "height": 0.5 },
	"oil_well": { "display_name": "DEP_OIL", "color": Color(0.15, 0.15, 0.18, 1), "height": 0.15 },
	"forest": { "display_name": "DEP_FOREST", "color": Color(0.2, 0.5, 0.15, 1), "height": 0.8 },
}

const DEPOSIT_IDS := ["gold_vein", "iron_deposit", "oil_well", "forest"]

var _deposits_container: Node3D
var _deposit_cells: Array = []  # [{ "id": String, "cell_x": int, "cell_y": int, "size_x": int, "size_y": int, "node": Node3D }]

func _ready() -> void:
	_deposits_container = Node3D.new()
	_deposits_container.name = "Deposits"
	add_child(_deposits_container)
	EventBus.mining_completed.connect(_on_mining_completed)
	GameManager.register_map_generator(self)

func _roll_deposit_size(deposit_id: String) -> Vector2i:
	var sizes: Dictionary = GameConfig.deposit_sizes.get(deposit_id, {"min_w": 2, "max_w": 3, "min_h": 2, "max_h": 3})
	var w := randi_range(sizes["min_w"], sizes["max_w"])
	var h := randi_range(sizes["min_h"], sizes["max_h"])
	return Vector2i(w, h)

func generate_new_map() -> Array:
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	var count := randi_range(GameConfig.deposit_count_min, GameConfig.deposit_count_max)

	for i in range(count):
		var deposit_id: String = DEPOSIT_IDS[randi() % DEPOSIT_IDS.size()]
		var dep_size := _roll_deposit_size(deposit_id)
		var cell := _random_cell_for_deposit(center, dep_size)
		if cell == Vector2i(-1, -1):
			continue
		spawn_deposit(deposit_id, cell, -1, dep_size)

	return get_all_deposits()

func spawn_deposit(deposit_id: String, cell: Vector2i, uses_override: int = -1, dep_size: Vector2i = Vector2i(2, 2)) -> Node3D:
	if not DEPOSIT_TYPES.has(deposit_id):
		return null
	var info: Dictionary = DEPOSIT_TYPES[deposit_id]

	var root := Node3D.new()
	root.name = deposit_id

	# Scale mesh to fill the multi-cell area
	var scale_x: float = float(dep_size.x)
	var scale_z: float = float(dep_size.y)
	var deposit_mesh := _create_deposit_mesh(deposit_id, info)
	deposit_mesh.scale = Vector3(scale_x, maxf(scale_x, scale_z) * 0.8, scale_z)
	root.add_child(deposit_mesh)

	# Hidden label — used by BuildingInfoPanel to get display name on click
	var label := Label3D.new()
	label.text = Tr.t(info["display_name"])
	label.font_size = 48
	label.pixel_size = 0.01
	label.position.y = info["height"] * maxf(scale_x, scale_z) + 1.2
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.modulate = Color(1, 1, 1, 1)
	label.visible = false

	root.add_child(label)
	root.set_meta("deposit_id", deposit_id)
	root.set_meta("cell", cell)
	root.set_meta("deposit_size", dep_size)

	# Set uses remaining from GameConfig
	var max_uses: int = GameConfig.get_deposit_max_uses(deposit_id)
	var uses: int = uses_override if uses_override > 0 else max_uses
	root.set_meta("uses_remaining", uses)
	root.set_meta("max_uses", max_uses)

	# Add to tree FIRST, then set global_position (requires being in tree)
	_deposits_container.add_child(root)
	var world_pos := GridManager.building_center(cell, dep_size)
	root.global_position = world_pos
	GridManager.place_obstacle(cell, root, dep_size)

	_deposit_cells.append({ "id": deposit_id, "cell_x": cell.x, "cell_y": cell.y, "size_x": dep_size.x, "size_y": dep_size.y, "node": root })
	return root

func _on_mining_completed(deposit_node: Node3D, _deposit_id: String) -> void:
	if not is_instance_valid(deposit_node):
		return
	if not deposit_node.has_meta("uses_remaining"):
		return
	var uses: int = deposit_node.get_meta("uses_remaining") - 1
	deposit_node.set_meta("uses_remaining", uses)
	if uses <= 0:
		_deplete_deposit(deposit_node)

func _deplete_deposit(node: Node3D) -> void:
	var deposit_id: String = node.get_meta("deposit_id", "")
	var cell: Vector2i = node.get_meta("cell", Vector2i(-1, -1))
	var dep_size: Vector2i = node.get_meta("deposit_size", Vector2i(2, 2))
	# Remove from tracking
	for i in range(_deposit_cells.size() - 1, -1, -1):
		if _deposit_cells[i]["node"] == node:
			_deposit_cells.remove_at(i)
			break
	# Remove from grid (multi-cell)
	if cell != Vector2i(-1, -1):
		GridManager.remove_obstacle(cell, dep_size)
	# Floating text
	var pos := node.global_position
	var label := Label3D.new()
	label.text = Tr.t("LBL_DEPOSIT_DEPLETED")
	label.font_size = 22
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 3
	label.modulate = Color(0.8, 0.3, 0.2)
	label.global_position = pos + Vector3(0, 2.0, 0)
	get_tree().current_scene.add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "global_position:y", pos.y + 5.0, 2.0).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 2.0).set_delay(0.5)
	tween.tween_callback(label.queue_free)
	# Signal and remove node
	EventBus.deposit_depleted.emit(node, deposit_id)
	EventBus.notification_posted.emit(Tr.t("NOTIF_DEPOSIT_GONE") % Tr.t(DEPOSIT_TYPES[deposit_id]["display_name"]), "warning", Color(0.8, 0.5, 0.2))
	node.queue_free()
	# Auto-save
	GameManager.save_game()

func get_all_deposits() -> Array:
	var result: Array = []
	for entry in _deposit_cells:
		if is_instance_valid(entry["node"]):
			var node: Node3D = entry["node"]
			var dep_entry := {
				"id": entry["id"],
				"cell_x": entry["cell_x"],
				"cell_y": entry["cell_y"],
				"size_x": entry.get("size_x", 2),
				"size_y": entry.get("size_y", 2),
			}
			if node.has_meta("uses_remaining"):
				dep_entry["uses_remaining"] = node.get_meta("uses_remaining")
			result.append(dep_entry)
	return result

func clear_all_deposits() -> void:
	for entry in _deposit_cells:
		var dep_size := Vector2i(entry.get("size_x", 2), entry.get("size_y", 2))
		GridManager.remove_obstacle(Vector2i(entry["cell_x"], entry["cell_y"]), dep_size)
		if is_instance_valid(entry["node"]):
			entry["node"].queue_free()
	_deposit_cells.clear()

# ── Deposit mesh generation ──

func _dep_metal(color: Color, metallic: float = 0.7, roughness: float = 0.45) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat

func _dep_emissive(color: Color, energy: float = 1.5) -> StandardMaterial3D:
	var mat := _dep_metal(color, 0.0, 0.9)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat

func _dep_add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _dep_add_cyl(parent: Node3D, pos: Vector3, radius: float, height: float, mat: StandardMaterial3D, seg: int = 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = seg
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _dep_add_sphere(parent: Node3D, pos: Vector3, radius: float, mat: StandardMaterial3D, seg: int = 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = seg
	mesh.rings = seg / 2
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _dep_add_cone(parent: Node3D, pos: Vector3, bot_r: float, top_r: float, height: float, mat: StandardMaterial3D, seg: int = 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bot_r
	mesh.height = height
	mesh.radial_segments = seg
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _create_deposit_mesh(deposit_id: String, info: Dictionary) -> Node3D:
	match deposit_id:
		"gold_vein": return _deposit_gold_vein()
		"iron_deposit": return _deposit_iron()
		"oil_well": return _deposit_oil_well()
		"forest": return _deposit_forest()
	# Fallback
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = GridManager.cell_size * 0.35
	cyl.bottom_radius = GridManager.cell_size * 0.4
	cyl.height = info["height"]
	mi.mesh = cyl
	mi.set_surface_override_material(0, _dep_metal(info["color"]))
	mi.position.y = info["height"] * 0.5
	node.add_child(mi)
	return node

func _deposit_gold_vein() -> Node3D:
	var root := Node3D.new()
	var mat_rock := _dep_metal(Color(0.40, 0.35, 0.30), 0.3, 0.8)
	var mat_gold := _dep_metal(Color(0.85, 0.70, 0.15), 0.95, 0.2)
	var mat_gold_glow := _dep_emissive(Color(0.9, 0.75, 0.1), 0.6)
	# Large rock cluster
	_dep_add_sphere(root, Vector3(0, 0.4, 0), 0.7, mat_rock, 7)
	_dep_add_sphere(root, Vector3(0.5, 0.5, 0.3), 0.5, mat_rock, 6)
	_dep_add_sphere(root, Vector3(-0.4, 0.45, -0.35), 0.55, mat_rock, 6)
	_dep_add_sphere(root, Vector3(-0.6, 0.3, 0.4), 0.4, mat_rock, 6)
	_dep_add_sphere(root, Vector3(0.3, 0.3, -0.5), 0.45, mat_rock, 6)
	# Gold veins (bright streaks on surface)
	_dep_add_box(root, Vector3(0.2, 0.7, 0.5), Vector3(0.35, 0.08, 0.08), mat_gold)
	_dep_add_box(root, Vector3(-0.3, 0.75, -0.2), Vector3(0.25, 0.07, 0.12), mat_gold)
	_dep_add_box(root, Vector3(0.5, 0.5, 0.0), Vector3(0.08, 0.18, 0.25), mat_gold)
	_dep_add_box(root, Vector3(-0.1, 0.6, 0.4), Vector3(0.3, 0.06, 0.06), mat_gold)
	# Gold nuggets scattered around base
	_dep_add_sphere(root, Vector3(0.7, 0.1, 0.5), 0.12, mat_gold_glow, 5)
	_dep_add_sphere(root, Vector3(-0.6, 0.08, 0.5), 0.09, mat_gold_glow, 5)
	_dep_add_sphere(root, Vector3(0.0, 0.85, 0.2), 0.1, mat_gold_glow, 5)
	_dep_add_sphere(root, Vector3(-0.5, 0.1, -0.4), 0.08, mat_gold_glow, 5)
	_dep_add_sphere(root, Vector3(0.4, 0.08, -0.6), 0.1, mat_gold_glow, 5)
	return root

func _deposit_iron() -> Node3D:
	var root := Node3D.new()
	var mat_iron := _dep_metal(Color(0.45, 0.42, 0.48), 0.85, 0.35)
	var mat_dark := _dep_metal(Color(0.25, 0.23, 0.27), 0.8, 0.4)
	var mat_rust := _dep_metal(Color(0.55, 0.30, 0.15), 0.5, 0.6)
	var mat_sheen := _dep_emissive(Color(0.55, 0.55, 0.65), 0.3)
	# Large angular iron ore chunks (scattered boulders)
	var b1 := _dep_add_box(root, Vector3(0, 0.5, 0), Vector3(0.8, 1.0, 0.7), mat_iron)
	b1.rotation.y = 0.3
	var b2 := _dep_add_box(root, Vector3(0.4, 0.65, 0.4), Vector3(0.55, 0.9, 0.5), mat_dark)
	b2.rotation.y = -0.5
	b2.rotation.x = 0.15
	var b3 := _dep_add_box(root, Vector3(-0.3, 0.4, -0.25), Vector3(0.65, 0.7, 0.55), mat_iron)
	b3.rotation.y = 0.8
	var b4 := _dep_add_box(root, Vector3(-0.5, 0.3, 0.4), Vector3(0.45, 0.5, 0.45), mat_dark)
	b4.rotation.y = -0.2
	b4.rotation.z = 0.1
	# Tall ore pillar
	var b5 := _dep_add_box(root, Vector3(0.15, 0.7, -0.35), Vector3(0.35, 1.2, 0.3), mat_iron)
	b5.rotation.y = 0.5
	# Metallic veins (shiny streaks)
	_dep_add_box(root, Vector3(0.2, 0.85, 0.4), Vector3(0.4, 0.05, 0.08), mat_sheen)
	_dep_add_box(root, Vector3(-0.15, 0.7, -0.3), Vector3(0.3, 0.05, 0.1), mat_sheen)
	_dep_add_box(root, Vector3(0.5, 0.5, -0.1), Vector3(0.08, 0.05, 0.3), mat_sheen)
	# Rust weathering
	_dep_add_box(root, Vector3(-0.4, 0.6, 0.25), Vector3(0.5, 0.03, 0.06), mat_rust)
	_dep_add_box(root, Vector3(0.3, 0.35, 0.15), Vector3(0.35, 0.03, 0.08), mat_rust)
	# Scattered ore fragments
	_dep_add_sphere(root, Vector3(0.6, 0.1, -0.4), 0.1, mat_dark, 4)
	_dep_add_sphere(root, Vector3(-0.55, 0.08, 0.55), 0.08, mat_dark, 4)
	_dep_add_sphere(root, Vector3(0.7, 0.07, 0.3), 0.07, mat_iron, 4)
	_dep_add_sphere(root, Vector3(-0.65, 0.06, -0.35), 0.06, mat_dark, 4)
	_dep_add_sphere(root, Vector3(0.1, 0.05, 0.65), 0.07, mat_iron, 4)
	return root

func _deposit_oil_well() -> Node3D:
	var root := Node3D.new()
	var mat_oil_dark := _dep_metal(Color(0.06, 0.05, 0.08), 0.4, 0.15)
	var mat_oil_sheen := _dep_emissive(Color(0.12, 0.08, 0.20), 0.4)
	var mat_oil_edge := _dep_metal(Color(0.10, 0.08, 0.12), 0.3, 0.25)
	var mat_iron := _dep_metal(Color(0.25, 0.23, 0.27), 0.8, 0.4)
	var mat_rust := _dep_metal(Color(0.50, 0.28, 0.15), 0.6, 0.55)
	var mat_warning := _dep_emissive(Color(1.0, 0.3, 0.05), 1.5)
	# Oil puddle base
	_dep_add_cyl(root, Vector3(0, 0.02, 0), 0.85, 0.04, mat_oil_sheen, 12)
	_dep_add_cyl(root, Vector3(0.35, 0.02, 0.25), 0.55, 0.04, mat_oil_dark, 10)
	_dep_add_cyl(root, Vector3(-0.3, 0.02, -0.2), 0.6, 0.04, mat_oil_dark, 10)
	_dep_add_cyl(root, Vector3(-0.45, 0.02, 0.35), 0.4, 0.03, mat_oil_sheen, 8)
	_dep_add_cyl(root, Vector3(0.5, 0.02, -0.35), 0.45, 0.03, mat_oil_edge, 9)
	# Natural oil seep (geyser pipe)
	_dep_add_cyl(root, Vector3(0, 0.3, 0), 0.08, 0.6, mat_iron, 6)
	_dep_add_cyl(root, Vector3(0, 0.65, 0), 0.12, 0.1, mat_rust, 6)
	# Oil bubbling up from pipe
	_dep_add_sphere(root, Vector3(0, 0.72, 0), 0.08, mat_oil_sheen, 6)
	_dep_add_sphere(root, Vector3(0.04, 0.78, 0.02), 0.04, mat_oil_dark, 4)
	# Warning stakes around the seep
	for i in range(4):
		var angle := i * TAU / 4.0 + PI / 4.0
		var sx := cos(angle) * 0.6
		var sz := sin(angle) * 0.6
		_dep_add_cyl(root, Vector3(sx, 0.2, sz), 0.02, 0.4, mat_rust, 4)
		_dep_add_sphere(root, Vector3(sx, 0.42, sz), 0.035, mat_warning, 4)
	# Small satellite puddles
	_dep_add_cyl(root, Vector3(0.7, 0.015, 0.5), 0.25, 0.03, mat_oil_dark, 8)
	_dep_add_cyl(root, Vector3(-0.65, 0.015, -0.5), 0.3, 0.03, mat_oil_sheen, 8)
	# Bubbles
	_dep_add_sphere(root, Vector3(0.15, 0.05, 0.15), 0.06, mat_oil_sheen, 5)
	_dep_add_sphere(root, Vector3(-0.25, 0.05, -0.1), 0.05, mat_oil_sheen, 5)
	return root

func _deposit_forest() -> Node3D:
	var root := Node3D.new()
	var mat_trunk := _dep_metal(Color(0.35, 0.22, 0.10), 0.1, 0.85)
	var mat_trunk_birch := _dep_metal(Color(0.65, 0.58, 0.48), 0.1, 0.8)
	var mat_leaves_dark := _dep_metal(Color(0.15, 0.35, 0.10), 0.1, 0.8)
	var mat_leaves_light := _dep_metal(Color(0.28, 0.50, 0.18), 0.1, 0.75)
	var mat_leaves_autumn := _dep_metal(Color(0.45, 0.35, 0.10), 0.1, 0.8)
	var mat_moss := _dep_metal(Color(0.18, 0.30, 0.12), 0.05, 0.9)
	var mat_mushroom := _dep_emissive(Color(0.8, 0.6, 0.2), 0.3)
	# Main tall pine (layered canopy)
	_dep_add_cyl(root, Vector3(0, 0.8, 0), 0.12, 1.6, mat_trunk, 6)
	_dep_add_cone(root, Vector3(0, 2.0, 0), 0.65, 0.0, 0.9, mat_leaves_dark, 7)
	_dep_add_cone(root, Vector3(0, 1.7, 0), 0.72, 0.2, 0.6, mat_leaves_light, 7)
	_dep_add_cone(root, Vector3(0, 1.4, 0), 0.55, 0.3, 0.4, mat_leaves_dark, 7)
	# Second tall tree (birch)
	_dep_add_cyl(root, Vector3(0.55, 0.65, 0.5), 0.07, 1.3, mat_trunk_birch, 6)
	_dep_add_sphere(root, Vector3(0.55, 1.55, 0.5), 0.4, mat_leaves_light, 6)
	_dep_add_sphere(root, Vector3(0.55, 1.35, 0.55), 0.35, mat_leaves_dark, 5)
	# Third pine
	_dep_add_cyl(root, Vector3(-0.55, 0.5, -0.45), 0.08, 1.0, mat_trunk, 5)
	_dep_add_cone(root, Vector3(-0.55, 1.25, -0.45), 0.45, 0.0, 0.7, mat_leaves_dark, 6)
	_dep_add_cone(root, Vector3(-0.55, 1.05, -0.45), 0.50, 0.12, 0.4, mat_leaves_light, 6)
	# Fourth small autumn tree
	_dep_add_cyl(root, Vector3(-0.35, 0.5, 0.55), 0.06, 1.0, mat_trunk, 5)
	_dep_add_sphere(root, Vector3(-0.35, 1.2, 0.55), 0.35, mat_leaves_autumn, 5)
	# Fifth young sapling
	_dep_add_cyl(root, Vector3(0.4, 0.3, -0.5), 0.04, 0.6, mat_trunk, 4)
	_dep_add_cone(root, Vector3(0.4, 0.75, -0.5), 0.2, 0.0, 0.35, mat_leaves_light, 5)
	# Dense undergrowth
	_dep_add_sphere(root, Vector3(-0.4, 0.2, 0.15), 0.25, mat_leaves_light, 5)
	_dep_add_sphere(root, Vector3(0.3, 0.2, -0.3), 0.22, mat_leaves_dark, 5)
	_dep_add_sphere(root, Vector3(0.65, 0.15, 0.1), 0.2, mat_leaves_light, 5)
	_dep_add_sphere(root, Vector3(-0.6, 0.18, -0.2), 0.22, mat_leaves_dark, 5)
	_dep_add_sphere(root, Vector3(0.1, 0.15, 0.65), 0.18, mat_leaves_light, 4)
	_dep_add_sphere(root, Vector3(-0.2, 0.14, -0.6), 0.16, mat_leaves_dark, 4)
	# Fallen logs
	var log1 := _dep_add_cyl(root, Vector3(-0.6, 0.1, 0.4), 0.07, 0.5, mat_trunk, 6)
	log1.rotation.z = PI / 2.0
	var log2 := _dep_add_cyl(root, Vector3(0.5, 0.1, 0.7), 0.06, 0.45, mat_trunk, 6)
	log2.rotation.z = PI / 2.0
	log2.rotation.y = 0.8
	# Tree stump
	_dep_add_cyl(root, Vector3(0.6, 0.1, -0.55), 0.1, 0.2, mat_trunk, 6)
	# Moss patches
	_dep_add_cyl(root, Vector3(0.1, 0.01, -0.1), 0.6, 0.02, mat_moss, 8)
	_dep_add_cyl(root, Vector3(-0.3, 0.01, 0.3), 0.45, 0.02, mat_moss, 8)
	_dep_add_cyl(root, Vector3(0.4, 0.01, 0.35), 0.3, 0.02, mat_moss, 7)
	# Mushrooms
	_dep_add_cyl(root, Vector3(-0.5, 0.06, 0.0), 0.015, 0.06, mat_trunk, 4)
	_dep_add_sphere(root, Vector3(-0.5, 0.1, 0.0), 0.04, mat_mushroom, 4)
	_dep_add_cyl(root, Vector3(-0.45, 0.05, 0.05), 0.01, 0.04, mat_trunk, 4)
	_dep_add_sphere(root, Vector3(-0.45, 0.08, 0.05), 0.03, mat_mushroom, 4)
	return root

## Find a deposit of the given type that overlaps any of the provided cells.
## Returns the deposit node or null.
func find_deposit_at_cells(deposit_id: String, cells: Array) -> Node3D:
	for entry in _deposit_cells:
		if entry["id"] != deposit_id or not is_instance_valid(entry["node"]):
			continue
		var dep_origin := Vector2i(entry["cell_x"], entry["cell_y"])
		var dep_size := Vector2i(entry.get("size_x", 2), entry.get("size_y", 2))
		for dx in range(dep_size.x):
			for dy in range(dep_size.y):
				var dep_cell := Vector2i(dep_origin.x + dx, dep_origin.y + dy)
				if dep_cell in cells:
					return entry["node"]
	return null

## Remove a deposit programmatically (used when a building consumes it).
func remove_deposit(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var deposit_id: String = node.get_meta("deposit_id", "")
	var cell: Vector2i = node.get_meta("cell", Vector2i(-1, -1))
	var dep_size: Vector2i = node.get_meta("deposit_size", Vector2i(2, 2))
	for i in range(_deposit_cells.size() - 1, -1, -1):
		if _deposit_cells[i]["node"] == node:
			_deposit_cells.remove_at(i)
			break
	if cell != Vector2i(-1, -1):
		GridManager.remove_obstacle(cell, dep_size)
	node.queue_free()

func _random_cell_for_deposit(center: Vector2i, dep_size: Vector2i) -> Vector2i:
	for attempt in range(80):
		var cx := randi_range(0, GridManager.grid_width - dep_size.x)
		var cy := randi_range(0, GridManager.grid_height - dep_size.y)
		var cell := Vector2i(cx, cy)
		# Check center exclusion from deposit center
		var mid_x: float = cx + dep_size.x * 0.5
		var mid_y: float = cy + dep_size.y * 0.5
		var dist := absf(mid_x - center.x) + absf(mid_y - center.y)
		if dist <= GameConfig.deposit_center_exclusion:
			continue
		# Check all cells are free
		if not GridManager.can_place(cell, dep_size):
			continue
		return cell
	return Vector2i(-1, -1)
