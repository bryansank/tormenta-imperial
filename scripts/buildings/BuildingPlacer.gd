extends Node3D
## Handles building placement and moving via raycasting to the ground plane.
## States: IDLE → PLACING (new building) or MOVING (existing building).
## Left click = place/confirm. Escape = cancel. Mouse hover = preview.

enum State { IDLE, PLACING, MOVING }

var _state: State = State.IDLE
var _current_data: BuildingData = null
var _preview_node: Node3D = null
var _preview_mesh: MeshInstance3D = null
var _moving_building: Node3D = null
var _hover_cell: Vector2i = Vector2i(-1, -1)

# Container for all placed buildings
var _buildings_container: Node3D

func _ready() -> void:
	_buildings_container = Node3D.new()
	_buildings_container.name = "Buildings"
	add_child(_buildings_container)

	EventBus.building_selected_for_placement.connect(_on_building_selected)
	EventBus.building_placement_cancelled.connect(_cancel)
	GameManager.register_placer(self)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Ignore clicks on UI
		if get_viewport().gui_get_hovered_control() != null:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and _state != State.IDLE:
			_cancel()
			get_viewport().set_input_as_handled()

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _state != State.IDLE:
			_cancel()
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _state == State.IDLE:
		return
	_update_preview()

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
		var world_pos := GridManager.building_center(cell, _current_data.grid_size)
		_preview_node.global_position = Vector3(world_pos.x, 0.0, world_pos.z)

		var can_place: bool
		if _state == State.MOVING:
			can_place = GridManager.can_place(cell, _current_data.grid_size, _moving_building)
		else:
			can_place = GridManager.can_place(cell, _current_data.grid_size)

		# Green = valid, Red = invalid
		var mat: StandardMaterial3D = _preview_mesh.get_surface_override_material(0)
		if mat:
			mat.albedo_color = Color(0.2, 0.8, 0.2, 0.5) if can_place else Color(0.8, 0.2, 0.2, 0.5)

# ── Placement Mode ──

func _on_building_selected(data: Resource) -> void:
	_cancel()
	_current_data = data as BuildingData
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
		return
	var cell := GridManager.world_to_cell(hit as Vector3)
	var building := GridManager.get_building_at(cell)
	if building:
		_start_moving(building)

func _try_place(cell: Vector2i) -> void:
	if not GridManager.can_place(cell, _current_data.grid_size):
		return
	var building := _create_building_mesh(_current_data)
	var world_pos := GridManager.building_center(cell, _current_data.grid_size)
	building.global_position = Vector3(world_pos.x, 0.0, world_pos.z)
	_buildings_container.add_child(building)
	GridManager.place_building(cell, _current_data, building)
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
	_current_data = data
	_state = State.MOVING
	# Hide the real building, show preview
	_moving_building.visible = false
	_create_preview()

func _try_move(cell: Vector2i) -> void:
	if not GridManager.can_place(cell, _current_data.grid_size, _moving_building):
		return
	GridManager.move_building(_moving_building, cell)
	var world_pos := GridManager.building_center(cell, _current_data.grid_size)
	_moving_building.global_position = Vector3(world_pos.x, 0.0, world_pos.z)
	_moving_building.visible = true
	var old_info := GridManager.get_building_info(_moving_building)
	EventBus.building_moved.emit(old_info.get("origin_cell", cell), cell)
	_cleanup_preview()
	_moving_building = null
	_current_data = null
	_state = State.IDLE

# ── Preview Mesh ──

func _create_preview() -> void:
	_cleanup_preview()
	_preview_node = Node3D.new()
	_preview_mesh = MeshInstance3D.new()

	var box := BoxMesh.new()
	var sx := _current_data.grid_size.x * GridManager.cell_size * 0.9
	var sz := _current_data.grid_size.y * GridManager.cell_size * 0.9
	box.size = Vector3(sx, _current_data.mesh_height, sz)
	_preview_mesh.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.2, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_mesh.set_surface_override_material(0, mat)
	_preview_mesh.position.y = _current_data.mesh_height * 0.5

	_preview_node.add_child(_preview_mesh)
	add_child(_preview_node)

func _cleanup_preview() -> void:
	if _preview_node:
		_preview_node.queue_free()
		_preview_node = null
		_preview_mesh = null
	_hover_cell = Vector2i(-1, -1)

func _cancel() -> void:
	if _state == State.MOVING and _moving_building:
		_moving_building.visible = true
	_cleanup_preview()
	_moving_building = null
	_current_data = null
	_state = State.IDLE

# ── Public API (used by GameManager) ──

func place_building_at(data: BuildingData, cell: Vector2i) -> Node3D:
	if not GridManager.can_place(cell, data.grid_size):
		return null
	var building := _create_building_mesh(data)
	var world_pos := GridManager.building_center(cell, data.grid_size)
	building.global_position = Vector3(world_pos.x, 0.0, world_pos.z)
	_buildings_container.add_child(building)
	GridManager.place_building(cell, data, building)
	return building

func get_all_placed_buildings() -> Array:
	var result: Array = []
	for building in _buildings_container.get_children():
		var info := GridManager.get_building_info(building)
		if not info.is_empty():
			var origin: Vector2i = info["origin_cell"]
			var data: BuildingData = info["data"]
			result.append({ "id": data.id, "cell_x": origin.x, "cell_y": origin.y })
	return result

func clear_all_buildings() -> void:
	for child in _buildings_container.get_children():
		child.queue_free()
	GridManager.clear_all()

# ── Create actual building mesh ──

func _create_building_mesh(data: BuildingData) -> Node3D:
	var root := Node3D.new()
	root.name = data.id

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	var sx := data.grid_size.x * GridManager.cell_size * 0.9
	var sz := data.grid_size.y * GridManager.cell_size * 0.9
	box.size = Vector3(sx, data.mesh_height, sz)
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.mesh_color
	mesh_inst.set_surface_override_material(0, mat)
	mesh_inst.position.y = data.mesh_height * 0.5

	# Label above building
	var label := Label3D.new()
	label.text = data.display_name
	label.font_size = 32
	label.position.y = data.mesh_height + 0.3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED

	root.add_child(mesh_inst)
	root.add_child(label)
	return root
