extends Node
## Generates random resource deposits on the map.
## Deposits are 1x1 obstacles that occupy grid cells.
## Each deposit has limited uses before depletion.

const DEPOSIT_TYPES := {
	"gold_vein": { "display_name": "DEP_GOLD_VEIN", "color": Color(0.9, 0.75, 0.1, 1), "height": 0.6 },
	"iron_deposit": { "display_name": "DEP_IRON", "color": Color(0.6, 0.6, 0.65, 1), "height": 0.5 },
	"oil_well": { "display_name": "DEP_OIL", "color": Color(0.15, 0.15, 0.18, 1), "height": 0.7 },
	"forest": { "display_name": "DEP_FOREST", "color": Color(0.2, 0.5, 0.15, 1), "height": 0.8 },
}

const DEPOSIT_IDS := ["gold_vein", "iron_deposit", "oil_well", "forest"]

var _deposits_container: Node3D
var _deposit_cells: Array = []  # [{ "id": String, "cell_x": int, "cell_y": int, "node": Node3D }]

func _ready() -> void:
	_deposits_container = Node3D.new()
	_deposits_container.name = "Deposits"
	add_child(_deposits_container)
	EventBus.mining_completed.connect(_on_mining_completed)
	GameManager.register_map_generator(self)

func generate_new_map() -> Array:
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	var count := randi_range(GameConfig.deposit_count_min, GameConfig.deposit_count_max)
	var placed: Array = []

	for i in range(count):
		var cell := _random_cell_outside_center(center, placed)
		if cell == Vector2i(-1, -1):
			break
		var deposit_id: String = DEPOSIT_IDS[randi() % DEPOSIT_IDS.size()]
		spawn_deposit(deposit_id, cell)
		placed.append(cell)

	return get_all_deposits()

func spawn_deposit(deposit_id: String, cell: Vector2i, uses_override: int = -1) -> Node3D:
	if not DEPOSIT_TYPES.has(deposit_id):
		return null
	var info: Dictionary = DEPOSIT_TYPES[deposit_id]

	var root := Node3D.new()
	root.name = deposit_id

	var deposit_mesh := _create_deposit_mesh(deposit_id, info)
	root.add_child(deposit_mesh)

	var label := Label3D.new()
	label.text = Tr.t(info["display_name"])
	label.font_size = 48
	label.pixel_size = 0.01
	label.position.y = info["height"] + 0.8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.modulate = Color(1, 1, 1, 1)

	root.add_child(label)
	root.set_meta("deposit_id", deposit_id)
	root.set_meta("cell", cell)

	# Set uses remaining from GameConfig
	var max_uses: int = GameConfig.get_deposit_max_uses(deposit_id)
	var uses: int = uses_override if uses_override > 0 else max_uses
	root.set_meta("uses_remaining", uses)
	root.set_meta("max_uses", max_uses)

	var world_pos := GridManager.cell_to_world(cell)
	root.global_position = world_pos
	_deposits_container.add_child(root)
	GridManager.place_obstacle(cell, root)

	_deposit_cells.append({ "id": deposit_id, "cell_x": cell.x, "cell_y": cell.y, "node": root })
	return root

func _on_mining_completed(deposit_node: Node3D, _deposit_id: String) -> void:
	if not is_instance_valid(deposit_node):
		return
	if not deposit_node.has_meta("uses_remaining"):
		return
	var uses: int = deposit_node.get_meta("uses_remaining") - 1
	if uses <= 0:
		_deplete_deposit(deposit_node)
	else:
		deposit_node.set_meta("uses_remaining", uses)
		# Scale down visually as it depletes
		var max_uses: int = deposit_node.get_meta("max_uses")
		var scale_factor: float = 0.5 + 0.5 * (float(uses) / float(max_uses))
		var deposit_mesh: Node = deposit_node.get_child(0)
		if deposit_mesh:
			deposit_mesh.scale = Vector3(scale_factor, scale_factor, scale_factor)

func _deplete_deposit(node: Node3D) -> void:
	var deposit_id: String = node.get_meta("deposit_id", "")
	var cell: Vector2i = node.get_meta("cell", Vector2i(-1, -1))
	# Remove from tracking
	for i in range(_deposit_cells.size() - 1, -1, -1):
		if _deposit_cells[i]["node"] == node:
			_deposit_cells.remove_at(i)
			break
	# Remove from grid
	if cell != Vector2i(-1, -1):
		GridManager.remove_obstacle(cell)
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
			var dep_entry := { "id": entry["id"], "cell_x": entry["cell_x"], "cell_y": entry["cell_y"] }
			if node.has_meta("uses_remaining"):
				dep_entry["uses_remaining"] = node.get_meta("uses_remaining")
			result.append(dep_entry)
	return result

func clear_all_deposits() -> void:
	for entry in _deposit_cells:
		GridManager.remove_obstacle(Vector2i(entry["cell_x"], entry["cell_y"]))
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
	# Rock cluster base
	_dep_add_sphere(root, Vector3(0, 0.25, 0), 0.45, mat_rock, 6)
	_dep_add_sphere(root, Vector3(0.25, 0.35, 0.15), 0.3, mat_rock, 6)
	_dep_add_sphere(root, Vector3(-0.2, 0.3, -0.15), 0.35, mat_rock, 6)
	# Gold veins (bright streaks on surface)
	_dep_add_box(root, Vector3(0.1, 0.45, 0.3), Vector3(0.2, 0.06, 0.06), mat_gold)
	_dep_add_box(root, Vector3(-0.15, 0.5, -0.1), Vector3(0.15, 0.05, 0.08), mat_gold)
	_dep_add_box(root, Vector3(0.3, 0.3, 0.0), Vector3(0.06, 0.12, 0.15), mat_gold)
	# Gold nuggets scattered
	_dep_add_sphere(root, Vector3(0.4, 0.08, 0.3), 0.08, mat_gold_glow, 5)
	_dep_add_sphere(root, Vector3(-0.35, 0.06, 0.25), 0.06, mat_gold_glow, 5)
	_dep_add_sphere(root, Vector3(0.0, 0.55, 0.15), 0.07, mat_gold_glow, 5)
	return root

func _deposit_iron() -> Node3D:
	var root := Node3D.new()
	var mat_iron := _dep_metal(Color(0.45, 0.42, 0.48), 0.85, 0.35)
	var mat_dark := _dep_metal(Color(0.25, 0.23, 0.27), 0.8, 0.4)
	var mat_rust := _dep_metal(Color(0.55, 0.30, 0.15), 0.5, 0.6)
	# Angular iron chunks (boxes rotated slightly for jagged look)
	var b1 := _dep_add_box(root, Vector3(0, 0.3, 0), Vector3(0.5, 0.6, 0.45), mat_iron)
	b1.rotation.y = 0.3
	var b2 := _dep_add_box(root, Vector3(0.2, 0.45, 0.2), Vector3(0.35, 0.5, 0.3), mat_dark)
	b2.rotation.y = -0.5
	b2.rotation.x = 0.15
	var b3 := _dep_add_box(root, Vector3(-0.15, 0.2, -0.1), Vector3(0.4, 0.35, 0.35), mat_iron)
	b3.rotation.y = 0.8
	# Rust streaks
	_dep_add_box(root, Vector3(0.1, 0.55, 0.25), Vector3(0.25, 0.03, 0.06), mat_rust)
	_dep_add_box(root, Vector3(-0.1, 0.4, -0.18), Vector3(0.18, 0.03, 0.08), mat_rust)
	# Small iron fragments on ground
	_dep_add_sphere(root, Vector3(0.35, 0.06, -0.2), 0.06, mat_dark, 4)
	_dep_add_sphere(root, Vector3(-0.3, 0.05, 0.3), 0.05, mat_dark, 4)
	return root

func _deposit_oil_well() -> Node3D:
	var root := Node3D.new()
	var mat_iron := _dep_metal(Color(0.25, 0.25, 0.28), 0.8, 0.4)
	var mat_black := _dep_metal(Color(0.08, 0.08, 0.10), 0.6, 0.7)
	var mat_brass := _dep_metal(Color(0.72, 0.58, 0.20), 0.9, 0.3)
	var mat_oil_sheen := _dep_emissive(Color(0.15, 0.12, 0.25), 0.3)
	# Oil puddle on ground
	_dep_add_cyl(root, Vector3(0, 0.02, 0), 0.55, 0.04, mat_oil_sheen, 10)
	# Derrick frame (simple A-frame)
	_dep_add_cyl(root, Vector3(-0.15, 0.7, -0.1), 0.04, 1.4, mat_iron, 6)
	_dep_add_cyl(root, Vector3(0.15, 0.7, -0.1), 0.04, 1.4, mat_iron, 6)
	_dep_add_cyl(root, Vector3(0, 0.7, 0.12), 0.04, 1.4, mat_iron, 6)
	# Crossbeams
	_dep_add_box(root, Vector3(0, 0.5, 0), Vector3(0.35, 0.03, 0.28), mat_iron)
	_dep_add_box(root, Vector3(0, 1.0, 0), Vector3(0.25, 0.03, 0.2), mat_iron)
	# Pump head (horsehead pump at top)
	_dep_add_box(root, Vector3(0, 1.4, 0), Vector3(0.12, 0.06, 0.06), mat_brass)
	_dep_add_box(root, Vector3(0.1, 1.35, 0), Vector3(0.04, 0.15, 0.04), mat_iron)
	# Oil barrel
	_dep_add_cyl(root, Vector3(0.35, 0.2, 0.2), 0.12, 0.35, mat_black, 8)
	# Valve
	var torus_mi := MeshInstance3D.new()
	var torus_mesh := TorusMesh.new()
	torus_mesh.inner_radius = 0.03
	torus_mesh.outer_radius = 0.07
	torus_mesh.rings = 6
	torus_mesh.ring_segments = 6
	torus_mi.mesh = torus_mesh
	torus_mi.set_surface_override_material(0, mat_brass)
	torus_mi.position = Vector3(-0.2, 0.3, 0.25)
	root.add_child(torus_mi)
	return root

func _deposit_forest() -> Node3D:
	var root := Node3D.new()
	var mat_trunk := _dep_metal(Color(0.35, 0.22, 0.10), 0.1, 0.85)
	var mat_leaves_dark := _dep_metal(Color(0.15, 0.35, 0.10), 0.1, 0.8)
	var mat_leaves_light := _dep_metal(Color(0.25, 0.45, 0.15), 0.1, 0.75)
	var mat_moss := _dep_metal(Color(0.18, 0.30, 0.12), 0.05, 0.9)
	# Main tree
	_dep_add_cyl(root, Vector3(0, 0.4, 0), 0.08, 0.8, mat_trunk, 6)
	_dep_add_cone(root, Vector3(0, 1.1, 0), 0.4, 0.0, 0.7, mat_leaves_dark, 6)
	_dep_add_cone(root, Vector3(0, 0.9, 0), 0.5, 0.1, 0.5, mat_leaves_light, 6)
	# Secondary smaller tree
	_dep_add_cyl(root, Vector3(0.3, 0.3, 0.25), 0.05, 0.6, mat_trunk, 5)
	_dep_add_cone(root, Vector3(0.3, 0.8, 0.25), 0.3, 0.0, 0.55, mat_leaves_dark, 6)
	# Bush / undergrowth
	_dep_add_sphere(root, Vector3(-0.25, 0.15, 0.2), 0.2, mat_leaves_light, 5)
	_dep_add_sphere(root, Vector3(0.15, 0.12, -0.3), 0.18, mat_leaves_dark, 5)
	# Stump / fallen log
	var log := _dep_add_cyl(root, Vector3(-0.3, 0.08, -0.2), 0.06, 0.35, mat_trunk, 6)
	log.rotation.z = PI / 2.0
	# Moss on ground
	_dep_add_cyl(root, Vector3(0.05, 0.01, -0.05), 0.4, 0.02, mat_moss, 8)
	return root

func _random_cell_outside_center(center: Vector2i, existing: Array) -> Vector2i:
	for attempt in range(50):
		var cx := randi_range(0, GridManager.grid_width - 1)
		var cy := randi_range(0, GridManager.grid_height - 1)
		var cell := Vector2i(cx, cy)
		var dist := absi(cx - center.x) + absi(cy - center.y)
		if dist <= GameConfig.deposit_center_exclusion:
			continue
		if cell in existing:
			continue
		if not GridManager.is_cell_free(cell):
			continue
		return cell
	return Vector2i(-1, -1)
