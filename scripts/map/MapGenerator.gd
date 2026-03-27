extends Node
## Generates random resource deposits on the map.
## Deposits are 1x1 obstacles that occupy grid cells.

const DEPOSIT_TYPES := {
	"gold_vein": { "display_name": "Veta de Oro", "color": Color(0.9, 0.75, 0.1, 1), "height": 0.6 },
	"iron_deposit": { "display_name": "Hierro", "color": Color(0.6, 0.6, 0.65, 1), "height": 0.5 },
	"oil_well": { "display_name": "Petróleo", "color": Color(0.15, 0.15, 0.18, 1), "height": 0.7 },
	"forest": { "display_name": "Bosque", "color": Color(0.2, 0.5, 0.15, 1), "height": 0.8 },
}

const DEPOSIT_IDS := ["gold_vein", "iron_deposit", "oil_well", "forest"]
const MIN_DEPOSITS := 15
const MAX_DEPOSITS := 25
const CENTER_EXCLUSION := 4  # cells from center to keep clear

var _deposits_container: Node3D
var _deposit_cells: Array = []  # [{ "id": String, "cell_x": int, "cell_y": int, "node": Node3D }]

func _ready() -> void:
	_deposits_container = Node3D.new()
	_deposits_container.name = "Deposits"
	add_child(_deposits_container)
	GameManager.register_map_generator(self)

func generate_new_map() -> Array:
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	var count := randi_range(MIN_DEPOSITS, MAX_DEPOSITS)
	var placed: Array = []

	for i in range(count):
		var cell := _random_cell_outside_center(center, placed)
		if cell == Vector2i(-1, -1):
			break
		var deposit_id: String = DEPOSIT_IDS[randi() % DEPOSIT_IDS.size()]
		spawn_deposit(deposit_id, cell)
		placed.append(cell)

	return get_all_deposits()

func spawn_deposit(deposit_id: String, cell: Vector2i) -> Node3D:
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
	label.text = info["display_name"]
	label.font_size = 24
	label.position.y = info["height"] + 0.2
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED

	root.add_child(mesh_inst)
	root.add_child(label)
	root.set_meta("deposit_id", deposit_id)
	root.set_meta("cell", cell)

	var world_pos := GridManager.cell_to_world(cell)
	root.global_position = world_pos
	_deposits_container.add_child(root)
	GridManager.place_obstacle(cell, root)

	_deposit_cells.append({ "id": deposit_id, "cell_x": cell.x, "cell_y": cell.y, "node": root })
	return root

func get_all_deposits() -> Array:
	var result: Array = []
	for entry in _deposit_cells:
		result.append({ "id": entry["id"], "cell_x": entry["cell_x"], "cell_y": entry["cell_y"] })
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
		if dist <= CENTER_EXCLUSION:
			continue
		if cell in existing:
			continue
		if not GridManager.is_cell_free(cell):
			continue
		return cell
	return Vector2i(-1, -1)
