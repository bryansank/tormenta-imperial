extends Node3D
## Handles building placement and moving via raycasting to the ground plane.
## States: IDLE → PLACING (new building) or MOVING (existing building).
## Left click = place/confirm. Escape = cancel. Mouse hover = preview.

enum State { IDLE, PLACING, MOVING }

## Left-drag camera panning (only while IDLE, so it doesn't fight placement).
## Grabs the terrain: the point under the cursor stays glued to the cursor.
const DRAG_PAN_THRESHOLD := 6.0  # px of movement before a click becomes a pan
var _left_pressed := false
var _left_press_pos := Vector2.ZERO
var _drag_last_pos := Vector2.ZERO
var _left_dragged := false

var _state: State = State.IDLE
var _current_data: BuildingData = null
var _preview_node: Node3D = null
var _preview_mesh: MeshInstance3D = null  # Fallback box (kept for legacy)
var _preview_meshes: Array = []           # All MeshInstance3D in preview for material swap
var _moving_building: Node3D = null
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _grid_overlay: MeshInstance3D = null
var _rotation_steps: int = 0  # 0=0°, 1=90°, 2=180°, 3=270°
var _ghost_valid: StandardMaterial3D
var _ghost_invalid: StandardMaterial3D
var _last_preview_valid := true

# Container for all placed buildings
var _buildings_container: Node3D

func _ready() -> void:
	_buildings_container = Node3D.new()
	_buildings_container.name = "Buildings"
	add_child(_buildings_container)

	# Cached ghost materials for preview
	_ghost_valid = StandardMaterial3D.new()
	_ghost_valid.albedo_color = Color(0.2, 0.85, 0.2, 0.45)
	_ghost_valid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_valid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_valid.no_depth_test = true

	_ghost_invalid = StandardMaterial3D.new()
	_ghost_invalid.albedo_color = Color(0.85, 0.2, 0.2, 0.45)
	_ghost_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_invalid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_invalid.no_depth_test = true

	EventBus.building_selected_for_placement.connect(_on_building_selected)
	EventBus.building_placement_cancelled.connect(_cancel)
	EventBus.request_move_building.connect(_on_move_requested)
	EventBus.request_demolish_building.connect(_on_demolish_requested)
	EventBus.building_clicked.connect(_on_building_clicked)
	EventBus.building_deselected.connect(_on_building_deselected)
	EventBus.building_rotate_requested.connect(_on_rotate_requested)
	GameManager.register_placer(self)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_button(event)
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and _state != State.IDLE:
			# Ignore clicks on UI
			if get_viewport().gui_get_hovered_control() != null:
				return
			_cancel()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _left_pressed:
		_handle_left_drag(event)
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE and _state != State.IDLE:
			_cancel()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R and _state != State.IDLE:
			_rotate_building()
			get_viewport().set_input_as_handled()

## Left mouse button: in IDLE it either drags the camera (if the pointer moves
## past a threshold) or selects a building on release. While placing/moving a
## building it places/confirms immediately on press.
func _handle_left_button(event: InputEventMouseButton) -> void:
	if event.pressed:
		# Ignore presses that start on UI
		if get_viewport().gui_get_hovered_control() != null:
			return
		if _state == State.IDLE:
			_left_pressed = true
			_left_press_pos = event.position
			_drag_last_pos = event.position
			_left_dragged = false
		else:
			_handle_left_click(event.position)
	else:
		# Release: a click without drag selects; a drag was a camera pan
		if _left_pressed and _state == State.IDLE and not _left_dragged:
			_try_select_building(event.position)
		_left_pressed = false
		_left_dragged = false

func _handle_left_drag(event: InputEventMouseMotion) -> void:
	if _state != State.IDLE:
		_left_pressed = false
		return
	if not _left_dragged and event.position.distance_to(_left_press_pos) < DRAG_PAN_THRESHOLD:
		return
	_left_dragged = true
	# Grab-pan: move the camera by the world-space gap between where the cursor
	# was and where it is now, so the terrain follows the cursor 1:1.
	var prev_hit = _raycast_to_ground(_drag_last_pos)
	var cur_hit = _raycast_to_ground(event.position)
	_drag_last_pos = event.position
	if prev_hit == null or cur_hit == null:
		return
	var world_delta := Vector2(prev_hit.x - cur_hit.x, prev_hit.z - cur_hit.z)
	EventBus.camera_drag_world_requested.emit(world_delta)
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _state == State.IDLE:
		return
	_update_preview()

# ── Rotation Helpers ──

## Get the effective grid size accounting for rotation (swap X/Y on 90°/270°).
func _get_rotated_size() -> Vector2i:
	if _current_data == null:
		return Vector2i(1, 1)
	if _rotation_steps % 2 == 1:
		return Vector2i(_current_data.grid_size.y, _current_data.grid_size.x)
	return _current_data.grid_size

## Get the Y rotation in radians for the current rotation step.
func _get_rotation_angle() -> float:
	return _rotation_steps * PI * 0.5

func _rotate_building() -> void:
	_rotation_steps = (_rotation_steps + 1) % 4
	_hover_cell = Vector2i(-1, -1)  # Force preview refresh
	_rebuild_preview()

func _rebuild_preview() -> void:
	if not _preview_node or not _current_data:
		return
	_preview_node.rotation.y = _get_rotation_angle()
	_hover_cell = Vector2i(-1, -1)  # Force position refresh

func _on_rotate_requested() -> void:
	if _state != State.IDLE:
		_rotate_building()

## Load original (unrotated) BuildingData from the .tres file by ID.
func _load_original_data(building_id: String) -> BuildingData:
	var path := "res://data/buildings/%s.tres" % building_id
	if ResourceLoader.exists(path):
		return load(path) as BuildingData
	return null

## Create a copy of BuildingData with swapped grid_size for rotated placement.
func _create_rotated_data(data: BuildingData) -> BuildingData:
	var rotated := data.duplicate()
	rotated.grid_size = Vector2i(data.grid_size.y, data.grid_size.x)
	return rotated

# ── Raycast ──

func _raycast_to_ground(screen_pos: Vector2) -> Variant:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return null
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	# Intersect with Y=0 plane
	if absf(dir.y) < 0.001:
		return null
	var t := -from.y / dir.y
	if t < 0:
		return null
	return from + dir * t

# ── Preview ──

func _update_preview() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var hit = _raycast_to_ground(mouse_pos)
	if hit == null:
		return

	var cell := GridManager.world_to_cell(hit as Vector3)
	if cell == _hover_cell:
		return
	_hover_cell = cell

	if _preview_node and _current_data:
		var rotated_size := _get_rotated_size()
		var world_pos := GridManager.building_center(cell, rotated_size)
		_preview_node.global_position = Vector3(world_pos.x, 0.0, world_pos.z)

		var can_place: bool
		if _state == State.MOVING:
			can_place = GridManager.can_place(cell, rotated_size, _moving_building)
		else:
			can_place = GridManager.can_place(cell, rotated_size)
			# For deposit-requiring buildings, check overlap with required deposit
			var required_dep: String = GameConfig.building_requires_deposit.get(_current_data.id, "")
			if required_dep != "" and _state == State.PLACING:
				var cells := GridManager._get_cells_for(cell, rotated_size)
				var map_gen: Node = get_tree().current_scene.get_node_or_null("MapGenerator")
				var has_deposit := map_gen and map_gen.find_deposit_at_cells(required_dep, cells) != null
				# Valid only if overlapping with the deposit (cells occupied by deposit are OK)
				can_place = has_deposit

		# Update ghost material (green = valid, red = invalid)
		if can_place != _last_preview_valid:
			_last_preview_valid = can_place
			_apply_ghost_material(can_place)

# ── Placement Mode ──

func _on_building_selected(data: Resource) -> void:
	_cancel()
	_current_data = data as BuildingData
	_rotation_steps = 0
	_state = State.PLACING
	_create_preview()

func _handle_left_click(screen_pos: Vector2) -> void:
	if _state == State.IDLE:
		_try_select_building(screen_pos)
		return

	var hit = _raycast_to_ground(screen_pos)
	if hit == null:
		return
	var cell := GridManager.world_to_cell(hit as Vector3)

	if _state == State.PLACING:
		_try_place(cell)
	elif _state == State.MOVING:
		_try_move(cell)

func _try_select_building(screen_pos: Vector2) -> void:
	var hit = _raycast_to_ground(screen_pos)
	if hit == null:
		EventBus.building_deselected.emit()
		return
	var cell := GridManager.world_to_cell(hit as Vector3)
	var node := GridManager.get_building_at(cell)
	if node == null:
		EventBus.building_deselected.emit()
		return
	# Check if it's a building (has info) or a deposit (has metadata)
	var info := GridManager.get_building_info(node)
	if not info.is_empty():
		EventBus.building_clicked.emit(node, info["data"])
	elif node.has_meta("deposit_id"):
		EventBus.deposit_clicked.emit(node, node.get_meta("deposit_id"), cell)
	else:
		EventBus.building_deselected.emit()

func _on_move_requested(building: Node3D) -> void:
	_start_moving(building)

func _on_demolish_requested(building: Node3D) -> void:
	var info := GridManager.get_building_info(building)
	if info.is_empty():
		return
	var data: BuildingData = info["data"]
	if data.is_core:
		return
	var cell: Vector2i = info["origin_cell"]
	# Refund based on GameConfig ratio
	var cost := data.get_cost()
	for type in cost:
		ResourceManager.add(type, int(cost[type] * GameConfig.demolish_refund_ratio))
	# Unregister from production/construction
	ProductionManager.unregister(building)
	ProcessManager.cancel(building)
	# Save cell before removing for road update
	var was_road := data.id == "road"
	# Remove from grid and scene
	GridManager.remove_building(building)
	building.queue_free()
	# Update neighboring roads if we demolished a road
	if was_road:
		for d in ROAD_DIRS:
			var neighbor_cell: Vector2i = cell + d["offset"]
			var neighbor := GridManager.get_building_at(neighbor_cell)
			if neighbor:
				var n_info := GridManager.get_building_info(neighbor)
				if not n_info.is_empty() and n_info["data"].id == "road":
					_update_road_mesh(neighbor, neighbor_cell)
	# Update warehouse count
	if data.id == "warehouse":
		ResourceManager.set_warehouse_count(count_building("warehouse"))
	EventBus.building_demolished.emit(building, cell)

func _try_place(cell: Vector2i) -> void:
	var rotated_size := _get_rotated_size()
	# Check if building requires a deposit underneath
	var required_deposit: String = GameConfig.building_requires_deposit.get(_current_data.id, "")
	var consumed_deposit: Node3D = null
	if required_deposit != "":
		var cells := GridManager._get_cells_for(cell, rotated_size)
		var map_gen: Node = get_tree().current_scene.get_node_or_null("MapGenerator")
		if map_gen:
			consumed_deposit = map_gen.find_deposit_at_cells(required_deposit, cells)
		if consumed_deposit == null:
			_show_feedback(Tr.t("LBL_REQUIRES_DEPOSIT"))
			return
		# Remove deposit from grid so can_place succeeds
		map_gen.remove_deposit(consumed_deposit)
	if not GridManager.can_place(cell, rotated_size):
		return
	# Check building limit
	if not _check_building_limit(_current_data.id):
		_show_feedback(Tr.t("LBL_LIMIT_REACHED") % [count_building(_current_data.id), GameConfig.get_building_limit(_current_data.id)])
		return
	# Check prerequisites
	if not _check_prerequisites(_current_data.id):
		var reqs := GameConfig.get_prerequisites(_current_data.id)
		_show_feedback(Tr.t("LBL_REQUIRES") % " + ".join(reqs))
		return
	# Check workers availability
	if _current_data.workers_required > 0:
		if PopulationManager.get_free_workers() < _current_data.workers_required:
			_show_feedback(Tr.t("LBL_NO_WORKERS"))
			return
	# Check and deduct cost
	var cost := _current_data.get_cost()
	if not cost.is_empty():
		if not ResourceManager.can_afford(cost):
			_show_feedback(Tr.t("LBL_NOT_ENOUGH_RESOURCES"))
			return
		ResourceManager.spend_cost(cost)
	# Create building with rotation applied
	var building := _create_building_mesh(_current_data)
	building.set_meta("level", 1)
	building.set_meta("rotation_steps", _rotation_steps)
	building.rotation.y = _get_rotation_angle()
	# Add to the tree BEFORE setting global_position (global transform needs a parent).
	_buildings_container.add_child(building)
	var world_pos := GridManager.building_center(cell, rotated_size)
	building.global_position = Vector3(world_pos.x, 0.0, world_pos.z)
	# Use a rotated BuildingData proxy for GridManager so it occupies the right cells
	var place_data := _current_data
	if _rotation_steps % 2 == 1:
		place_data = _create_rotated_data(_current_data)
	GridManager.place_building(cell, place_data, building)
	# Update warehouse count
	if _current_data.id == "warehouse":
		ResourceManager.set_warehouse_count(count_building("warehouse"))
	# Update road connections if placing a road
	if _current_data.id == "road":
		_update_road_connections(cell)
	EventBus.building_placed.emit(_current_data, cell)
	# Stay in placement mode for rapid building
	_hover_cell = Vector2i(-1, -1)

func _start_moving(building: Node3D) -> void:
	var info := GridManager.get_building_info(building)
	if info.is_empty():
		return
	var data := info["data"] as BuildingData
	if data.is_core:
		return
	_moving_building = building
	# Always use the original (unrotated) data — reload from .tres
	_current_data = _load_original_data(data.id)
	if not _current_data:
		_current_data = data
	_rotation_steps = building.get_meta("rotation_steps", 0)
	_state = State.MOVING
	# Hide the real building, show preview
	_moving_building.visible = false
	_create_preview()
	_rebuild_preview()

func _try_move(cell: Vector2i) -> void:
	var rotated_size := _get_rotated_size()
	if not GridManager.can_place(cell, rotated_size, _moving_building):
		return
	# Remember old cell for road updates
	var old_info := GridManager.get_building_info(_moving_building)
	var old_cell: Vector2i = old_info.get("origin_cell", cell)
	# Update grid with possibly new rotated size
	GridManager.remove_building(_moving_building)
	var place_data := _current_data
	if _rotation_steps % 2 == 1:
		place_data = _create_rotated_data(_current_data)
	GridManager.place_building(cell, place_data, _moving_building)
	var world_pos := GridManager.building_center(cell, rotated_size)
	_moving_building.global_position = Vector3(world_pos.x, 0.0, world_pos.z)
	_moving_building.rotation.y = _get_rotation_angle()
	_moving_building.set_meta("rotation_steps", _rotation_steps)
	_moving_building.visible = true
	# Update road connections at old and new positions
	if _current_data.id == "road":
		_update_road_connections(cell)
		# Update neighbors at old position (road no longer there)
		for d in ROAD_DIRS:
			var neighbor_cell: Vector2i = old_cell + d["offset"]
			var neighbor := GridManager.get_building_at(neighbor_cell)
			if neighbor:
				var n_info := GridManager.get_building_info(neighbor)
				if not n_info.is_empty() and n_info["data"].id == "road":
					_update_road_mesh(neighbor, neighbor_cell)
	EventBus.building_moved.emit(old_cell, cell)
	_cleanup_preview()
	_moving_building = null
	_current_data = null
	_rotation_steps = 0
	_state = State.IDLE

# ── Preview Mesh ──

func _create_preview() -> void:
	_cleanup_preview()
	_show_grid_overlay()
	_preview_node = Node3D.new()
	_preview_meshes.clear()
	_last_preview_valid = true

	# Use the actual 3D building model for the preview
	var model: Node3D = null
	if _current_data.model_scene:
		model = _current_data.model_scene.instantiate()
	else:
		model = DieselpunkBuildingFactory.create(_current_data.id, GridManager.cell_size, _current_data.grid_size)

	if model:
		_preview_node.add_child(model)
		_collect_mesh_instances(_preview_node)
		_apply_ghost_material(true)
	else:
		# Fallback: transparent box
		_preview_mesh = MeshInstance3D.new()
		var rotated_size := _get_rotated_size()
		var box := BoxMesh.new()
		var sx: float = rotated_size.x * GridManager.cell_size * 0.9
		var sz: float = rotated_size.y * GridManager.cell_size * 0.9
		box.size = Vector3(sx, _current_data.mesh_height, sz)
		_preview_mesh.mesh = box
		_preview_mesh.set_surface_override_material(0, _ghost_valid)
		_preview_mesh.position.y = _current_data.mesh_height * 0.5
		_preview_node.add_child(_preview_mesh)
		_preview_meshes.append(_preview_mesh)

	_preview_node.rotation.y = _get_rotation_angle()
	add_child(_preview_node)

func _collect_mesh_instances(node: Node) -> void:
	if node is MeshInstance3D:
		_preview_meshes.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child)

func _apply_ghost_material(valid: bool) -> void:
	var mat := _ghost_valid if valid else _ghost_invalid
	for mi in _preview_meshes:
		if mi is MeshInstance3D and mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				mi.set_surface_override_material(s, mat)

func _cleanup_preview() -> void:
	if _preview_node:
		_preview_node.queue_free()
		_preview_node = null
		_preview_mesh = null
		_preview_meshes.clear()
	_hide_grid_overlay()
	_hover_cell = Vector2i(-1, -1)

func _cancel() -> void:
	if _state == State.MOVING and _moving_building:
		_moving_building.visible = true
	_cleanup_preview()
	_moving_building = null
	_current_data = null
	_rotation_steps = 0
	_state = State.IDLE

# ── Public API (used by GameManager) ──

func place_building_at(data: BuildingData, cell: Vector2i, rot_steps: int = 0) -> Node3D:
	var place_data := data
	if rot_steps % 2 == 1:
		place_data = _create_rotated_data(data)
	if not GridManager.can_place(cell, place_data.grid_size):
		return null
	var building := _create_building_mesh(data)
	building.set_meta("rotation_steps", rot_steps)
	building.rotation.y = rot_steps * PI * 0.5
	# Add to the tree BEFORE setting global_position (global transform needs a parent).
	_buildings_container.add_child(building)
	var world_pos := GridManager.building_center(cell, place_data.grid_size)
	building.global_position = Vector3(world_pos.x, 0.0, world_pos.z)
	GridManager.place_building(cell, place_data, building)
	# Update road connections after placement (deferred so all buildings load first)
	if data.id == "road":
		_update_road_connections.call_deferred(cell)
	return building

func get_all_placed_buildings() -> Array:
	var result: Array = []
	for building in _buildings_container.get_children():
		var info := GridManager.get_building_info(building)
		if not info.is_empty():
			var origin: Vector2i = info["origin_cell"]
			var data: BuildingData = info["data"]
			var entry := { "id": data.id, "cell_x": origin.x, "cell_y": origin.y }
			var rot: int = building.get_meta("rotation_steps", 0)
			if rot != 0:
				entry["rotation"] = rot
			var level: int = building.get_meta("level", 1)
			if level > 1:
				entry["level"] = level
			if building.has_meta("custom_name"):
				entry["custom_name"] = building.get_meta("custom_name")
			if ProductionManager.is_constructing(building):
				entry["construction_remaining"] = ProductionManager.get_construction_remaining(building)
			result.append(entry)
	return result

func clear_all_buildings() -> void:
	for child in _buildings_container.get_children():
		child.queue_free()
	GridManager.clear_all()

# ── Create actual building mesh ──

# ── Road connectivity ──

## Direction offsets: NORTH=1(Z-), EAST=2(X+), SOUTH=4(Z+), WEST=8(X-)
const ROAD_DIRS: Array = [
	{"bit": 1, "offset": Vector2i(0, -1)},  # North (Z-)
	{"bit": 2, "offset": Vector2i(1, 0)},   # East (X+)
	{"bit": 4, "offset": Vector2i(0, 1)},   # South (Z+)
	{"bit": 8, "offset": Vector2i(-1, 0)},  # West (X-)
]

## Get the neighbor bitmask for a road at the given cell.
func _get_road_neighbors(cell: Vector2i) -> int:
	var mask := 0
	for d in ROAD_DIRS:
		var neighbor_cell: Vector2i = cell + d["offset"]
		var neighbor := GridManager.get_building_at(neighbor_cell)
		if neighbor:
			var info := GridManager.get_building_info(neighbor)
			if not info.is_empty() and info["data"].id == "road":
				mask |= d["bit"]
	return mask

## Rebuild a road's visual mesh based on current neighbors.
func _update_road_mesh(building: Node3D, cell: Vector2i) -> void:
	var neighbors := _get_road_neighbors(cell)
	# Remove old mesh children (keep NameLabel)
	for child in building.get_children():
		if child.name != "NameLabel":
			child.queue_free()
	# Add new procedural road mesh
	var road_mesh := DieselpunkBuildingFactory.create_road(GridManager.cell_size, neighbors)
	building.add_child(road_mesh)

## Update this road and all adjacent roads' meshes.
func _update_road_connections(cell: Vector2i) -> void:
	# Update the road at this cell
	var building := GridManager.get_building_at(cell)
	if building:
		var info := GridManager.get_building_info(building)
		if not info.is_empty() and info["data"].id == "road":
			_update_road_mesh(building, cell)
	# Update all adjacent roads
	for d in ROAD_DIRS:
		var neighbor_cell: Vector2i = cell + d["offset"]
		var neighbor := GridManager.get_building_at(neighbor_cell)
		if neighbor:
			var n_info := GridManager.get_building_info(neighbor)
			if not n_info.is_empty() and n_info["data"].id == "road":
				_update_road_mesh(neighbor, neighbor_cell)

# ── Create actual building mesh ──

func _create_building_mesh(data: BuildingData) -> Node3D:
	var root := Node3D.new()
	root.name = data.id

	if data.model_scene:
		var model_instance := data.model_scene.instantiate()
		root.add_child(model_instance)
	else:
		# Try dieselpunk procedural mesh first
		var dieselpunk := DieselpunkBuildingFactory.create(data.id, GridManager.cell_size, data.grid_size)
		if dieselpunk:
			root.add_child(dieselpunk)
		else:
			# Fallback: colored box placeholder for unknown buildings
			var mesh_inst := MeshInstance3D.new()
			var box := BoxMesh.new()
			var sx: float = data.grid_size.x * GridManager.cell_size * 0.9
			var sz: float = data.grid_size.y * GridManager.cell_size * 0.9
			box.size = Vector3(sx, data.mesh_height, sz)
			mesh_inst.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = data.mesh_color
			mesh_inst.set_surface_override_material(0, mat)
			mesh_inst.position.y = data.mesh_height * 0.5
			root.add_child(mesh_inst)

	# Label above building — large, bold, readable (hidden by default)
	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = data.display_name
	label.font_size = 64
	label.pixel_size = 0.01
	label.position.y = data.mesh_height + 0.5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.modulate = Color(1, 1, 1, 1)
	label.visible = false
	root.add_child(label)

	return root

# ── Grid Overlay ──

func _show_grid_overlay() -> void:
	# Show the main scene GridOverlay (shader-based)
	var scene_grid := get_tree().current_scene.get_node_or_null("GridOverlay")
	if scene_grid:
		scene_grid.visible = true

func _hide_grid_overlay() -> void:
	var scene_grid := get_tree().current_scene.get_node_or_null("GridOverlay")
	if scene_grid:
		scene_grid.visible = false

# ── Limit / Prerequisite Helpers ──

func count_building(building_id: String) -> int:
	var count := 0
	for child in _buildings_container.get_children():
		if child.name == building_id:
			count += 1
	return count

func _check_building_limit(building_id: String) -> bool:
	var limit := GameConfig.get_building_limit(building_id)
	if limit < 0:
		return true
	return count_building(building_id) < limit

func _check_prerequisites(building_id: String) -> bool:
	var reqs := GameConfig.get_prerequisites(building_id)
	for req_id in reqs:
		if count_building(req_id) < 1:
			return false
	return true

var _feedback_canvas: CanvasLayer = null
var _feedback_label: Label = null
var _feedback_tween: Tween = null

func _show_feedback(text: String) -> void:
	# Reuse a single 2D screen label instead of spawning 3D labels
	if not _feedback_canvas:
		_feedback_canvas = CanvasLayer.new()
		_feedback_canvas.layer = 15
		add_child(_feedback_canvas)
		_feedback_label = Label.new()
		_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_feedback_label.set_anchors_preset(Control.PRESET_CENTER)
		_feedback_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_feedback_label.grow_vertical = Control.GROW_DIRECTION_BOTH
		_feedback_label.add_theme_font_size_override("font_size", 16)
		_feedback_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.7))
		_feedback_label.add_theme_constant_override("outline_size", 4)
		_feedback_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		var panel := PanelContainer.new()
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.08, 0.05, 0.9)
		style.border_color = Color(0.7, 0.35, 0.15, 0.8)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		style.set_content_margin_all(12)
		panel.add_theme_stylebox_override("panel", style)
		panel.add_child(_feedback_label)
		_feedback_canvas.add_child(panel)
	_feedback_label.text = text
	_feedback_label.get_parent().visible = true
	_feedback_label.get_parent().modulate = Color(1, 1, 1, 1)
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(1.2)
	_feedback_tween.tween_property(_feedback_label.get_parent(), "modulate:a", 0.0, 0.5)
	_feedback_tween.tween_callback(func(): _feedback_label.get_parent().visible = false)

# ── Show/Hide building labels on selection ──

func _on_building_clicked(building: Node3D, _data: BuildingData) -> void:
	# Hide all labels first
	for child in _buildings_container.get_children():
		var name_label := child.get_node_or_null("NameLabel")
		if name_label:
			name_label.visible = false
	# Show only selected building's label
	var selected_label := building.get_node_or_null("NameLabel")
	if selected_label:
		selected_label.visible = true

func _on_building_deselected() -> void:
	# Hide all labels
	for child in _buildings_container.get_children():
		var name_label := child.get_node_or_null("NameLabel")
		if name_label:
			name_label.visible = false
