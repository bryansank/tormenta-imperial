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

	var mesh_inst := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = GridManager.cell_size * 0.35
	cylinder.bottom_radius = GridManager.cell_size * 0.4
	cylinder.height = info["height"]
	mesh_inst.mesh = cylinder

	var mat := StandardMaterial3D.new()
	mat.albedo_color = info["color"]
	mesh_inst.set_surface_override_material(0, mat)
	mesh_inst.position.y = info["height"] * 0.5

	var label := Label3D.new()
	label.text = Tr.t(info["display_name"])
	label.font_size = 24
	label.position.y = info["height"] + 0.2
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED

	root.add_child(mesh_inst)
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
		var mesh_inst: Node = deposit_node.get_child(0)
		if mesh_inst is MeshInstance3D:
			mesh_inst.scale = Vector3(scale_factor, scale_factor, scale_factor)

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
