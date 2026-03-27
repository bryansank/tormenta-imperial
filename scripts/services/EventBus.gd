extends Node
## Global signal bus for decoupled communication between systems.
## All game-wide events flow through here. Systems emit signals, others subscribe.

# ── Camera ──
signal camera_pan_requested(direction: Vector2)
signal camera_zoom_requested(amount: float)
signal camera_drag_moved(delta: Vector2)
signal camera_rotate_requested(amount: float)

# ── Resources ──
signal resource_changed(resource_type: String, new_amount: int, delta: int)
signal resources_insufficient(resource_type: String, required: int, available: int)

# ── Buildings ──
signal building_selected_for_placement(building_data: Resource)
signal building_placement_cancelled()
signal building_placed(building_data: Resource, cell: Vector2i)
signal building_moved(from_cell: Vector2i, to_cell: Vector2i)
signal building_removed(cell: Vector2i)

# ── Selection ──
signal building_clicked(building_node: Node3D, building_data: Resource)
signal building_deselected()
signal deposit_clicked(deposit_node: Node3D, deposit_id: String, cell: Vector2i)
signal request_move_building(building_node: Node3D)
signal building_renamed(building_node: Node3D, new_name: String)

# ── Processes & Mining ──
signal process_started(building_node: Node3D, process_id: String)
signal process_completed(building_node: Node3D, process_id: String)
signal mining_started(deposit_node: Node3D, deposit_id: String)
signal mining_completed(deposit_node: Node3D, deposit_id: String)

# ── Construction ──
signal construction_started(building_node: Node3D)
signal construction_completed(building_node: Node3D)

# ── Production ──
signal production_tick(building_node: Node3D)

# ── Demolish ──
signal request_demolish_building(building_node: Node3D)
signal building_demolished(building_node: Node3D, cell: Vector2i)

# ── Ground Interaction ──
signal ground_clicked(world_pos: Vector3, cell: Vector2i)
signal ground_hover(world_pos: Vector3, cell: Vector2i)

# ── Persistence ──
signal game_new_started()
signal game_load_completed()
