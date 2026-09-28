extends Node3D
## Handles building placement and moving via raycasting to the ground plane.
## States: IDLE → PLACING (new building) or MOVING (existing building).
## Left click = place/confirm. Escape = cancel. Mouse hover = preview.
## Con el dedo: tocar lleva el fantasma, tocar el fantasma o ✓ lo planta, y las
## casillas validas de un extractor se ven en verde (PlacementAssist, docs/21).

enum State { IDLE, PLACING, MOVING }

## Preloaded so placement does not depend on the editor's global class cache
## (a fresh clone runs the game headless before any editor scan).
const StatusBadge := preload("res://scripts/buildings/BuildingStatusBadge.gd")
## Las cuentas de pantalla -> suelo son estaticas y viven en InputService, que es
## quien las usa para el dedo. Se cargan por script (no por el autoload) para
## llamarlas como lo que son: funciones sueltas, sin instancia de por medio.
const PointerMath := preload("res://scripts/services/InputService.gd")
## Las reglas (veredicto, topes, demoler, guardar) son las mismas en la vista 2D:
## viven en PlacementRules y aqui solo se llaman.
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const WorkerWalkers := preload("res://scripts/map/WorkerWalkers.gd")
const Assist := preload("res://scripts/buildings/PlacementAssist.gd")

## Left-drag camera panning (only while IDLE, so it doesn't fight placement).
## Grabs the terrain: the point under the cursor stays glued to the cursor.
## El umbral vive en GameConfig.mouse_drag_threshold_px.
var _left_pressed := false
var _left_press_pos := Vector2.ZERO
var _drag_last_pos := Vector2.ZERO
var _left_dragged := false
## Este clic viene de un dedo (Godot fabrica un raton emulado a partir del tacto).
## Con el dedo, colocar y seleccionar esperan a levantarlo: hasta entonces no se
## sabe si el gesto era un toque o el principio de un arrastre del mapa.
var _left_from_touch := false

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
## Dedo, casillas validas y boton ✓ (compartido con la vista 2D).
var _assist: Node = null
## Casillas donde cabe el extractor en curso, en verde sobre el suelo.
var _spot_highlight: MultiMeshInstance3D = null

func _ready() -> void:
	_buildings_container = Node3D.new()
	_buildings_container.name = "Buildings"
	add_child(_buildings_container)
	# Los trabajadores que andan del Nucleo a su edificio: fuera del contenedor
	# de edificios, que es lo que se guarda.
	var walkers_layer := Node3D.new()
	walkers_layer.name = "Walkers"
	add_child(walkers_layer)
	var walkers: Node = WorkerWalkers.new()
	walkers.setup(walkers_layer, false)
	add_child(walkers)

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
	_assist = Assist.new()
	_assist.name = "PlacementAssist"
	_assist.setup(self)
	add_child(_assist)

func _input(event: InputEvent) -> void:
	if _state != State.IDLE:
		_assist.notice_input(event)

func _unhandled_input(event: InputEvent) -> void:
	if _state != State.IDLE and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		if _assist.handle_touch(event):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_button(event)
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and _state != State.IDLE:
			# Ignore clicks on UI
			if get_viewport().gui_get_hovered_control() != null:
				return
			# Por la senal, no _cancel() directo: asi el boton tactil de
			# cancelar y los de colocacion se enteran y se ocultan tambien.
			EventBus.building_placement_cancelled.emit()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _left_pressed:
		_handle_left_drag(event)
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE and _state != State.IDLE:
			EventBus.building_placement_cancelled.emit()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R and _state != State.IDLE:
			_rotate_building()
			get_viewport().set_input_as_handled()

## Left mouse button: in IDLE it either drags the camera (if the pointer moves
## past a threshold) or selects a building on release. With the mouse, placing or
## confirming happens on press; con el dedo espera a levantarlo, porque el mismo
## gesto puede acabar siendo un arrastre del mapa.
func _handle_left_button(event: InputEventMouseButton) -> void:
	if event.pressed:
		# Ignore presses that start on UI
		if get_viewport().gui_get_hovered_control() != null:
			return
		_left_pressed = true
		_left_press_pos = event.position
		_drag_last_pos = event.position
		_left_dragged = false
		_left_from_touch = event.device == InputEvent.DEVICE_ID_EMULATION
		if _left_from_touch:
			return
		if _state != State.IDLE:
			_left_pressed = false
			_handle_left_click(event.position)
		return

	# Release: a click without drag places or selects; a drag was a camera pan.
	var was_click := _left_pressed and not _left_dragged
	if _left_from_touch and InputService.touch_pan_consumed_click():
		was_click = false
	# Colocando, el dedo lo lleva PlacementAssist con los toques de verdad: el
	# clic emulado que Godot fabrica al levantarlo no planta nada.
	if _left_from_touch and _state != State.IDLE:
		was_click = false
	_left_pressed = false
	_left_dragged = false
	_left_from_touch = false
	if not was_click:
		return
	if _state == State.IDLE:
		_try_select_building(event.position)
	else:
		_handle_left_click(event.position)

func _handle_left_drag(event: InputEventMouseMotion) -> void:
	# El arrastre con el dedo lo panea InputService con esta misma cuenta; si lo
	# repitiesemos aqui con el raton emulado, el mapa correria el doble.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if _state != State.IDLE:
		_left_pressed = false
		return
	if not _left_dragged and event.position.distance_to(_left_press_pos) < GameConfig.mouse_drag_threshold_px:
		return
	_left_dragged = true
	# Grab-pan: move the camera by the world-space gap between where the cursor
	# was and where it is now, so the terrain follows the cursor 1:1. Es la misma
	# funcion que usa el dedo, de ahi que ambos se sientan igual.
	var prev_pos := _drag_last_pos
	_drag_last_pos = event.position
	var world_delta = PointerMath.screen_drag_to_world_delta(
		get_viewport().get_camera_3d(), prev_pos, event.position)
	if world_delta == null:
		return
	EventBus.camera_drag_world_requested.emit(world_delta)
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _state == State.IDLE:
		return
	_update_preview()

# ── Rotation Helpers ──

## Get the effective grid size accounting for rotation (swap X/Y on 90°/270°).
func _get_rotated_size() -> Vector2i:
	return Rules.rotated_size(_current_data, _rotation_steps)

## Get the Y rotation in radians for the current rotation step.
func _get_rotation_angle() -> float:
	return _rotation_steps * PI * 0.5

func _rotate_building() -> void:
	_rotation_steps = (_rotation_steps + 1) % 4
	_hover_cell = Vector2i(-1, -1)  # Force preview refresh
	_rebuild_preview()
	# La huella girada cabe en otros sitios: se repintan las casillas validas.
	_assist.refresh_spots()
	if _assist.touch_aim:
		_assist.move_to(_assist.cell, false)

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
	return Rules.load_building_data(building_id)

## Create a copy of BuildingData with swapped grid_size for rotated placement.
func _create_rotated_data(data: BuildingData) -> BuildingData:
	return Rules.rotated_data(data)

# ── Raycast ──

func _raycast_to_ground(screen_pos: Vector2) -> Variant:
	# La proyeccion sobre el plano Y=0 vive en InputService: la comparten el
	# fantasma de colocacion, el clic y el arrastre del mapa (raton y dedo).
	return PointerMath.raycast_to_ground(get_viewport().get_camera_3d(), screen_pos)

# ── Preview ──

func _update_preview() -> void:
	# Con el dedo el fantasma esta donde lo dejo el ultimo toque, no donde quedo
	# el raton emulado.
	if _assist.touch_aim:
		if GridManager.is_valid_cell(_assist.cell):
			_set_preview_cell(_assist.cell)
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var hit = _raycast_to_ground(mouse_pos)
	if hit == null:
		return
	_set_preview_cell(GridManager.world_to_cell(hit as Vector3))

func _set_preview_cell(cell: Vector2i) -> void:
	if cell == _hover_cell:
		return
	_hover_cell = cell

	if _preview_node and _current_data:
		var rotated_size := _get_rotated_size()
		var world_pos := GridManager.building_center(cell, rotated_size)
		_preview_node.global_position = Vector3(world_pos.x, 0.0, world_pos.z)

		# Same verdict for placing and moving: the ghost goes red wherever the
		# click would be refused, deposit rule included.
		var ignore: Node = _moving_building if _state == State.MOVING else null
		var can_place: bool = evaluate_placement(_current_data.id, cell, rotated_size, _map_generator(), ignore)["ok"]

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
	_assist.begin()

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

func _on_move_requested(building: Node) -> void:
	_start_moving(building)

func _on_demolish_requested(building: Node) -> void:
	# Reembolso, produccion, procesos y rejilla: PlacementRules.demolish.
	var result := Rules.demolish(building)
	if result.is_empty():
		return
	if result.has("blocked"):
		_show_feedback(String(result["blocked"]))
		return
	var data: BuildingData = result["data"]
	var cell: Vector2i = result["cell"]
	building.queue_free()
	# Update neighboring roads if we demolished a road
	if data.id == "road":
		for n in Rules.neighbor_roads(cell):
			_update_road_mesh(n["node"], n["cell"])
	# Update warehouse count
	if data.id == "warehouse":
		ResourceManager.set_warehouse_count(count_building("warehouse"))
	EventBus.building_demolished.emit(building, cell)

func _try_place(cell: Vector2i) -> void:
	var rotated_size := _get_rotated_size()
	var map_gen := _map_generator()
	var verdict := evaluate_placement(_current_data.id, cell, rotated_size, map_gen)
	if not verdict["ok"]:
		if verdict["reason"] == "deposit":
			_reject_for_deposit(_current_data.id)
		elif verdict["reason"] == "occupied":
			# Antes, silencio: el clic no hacia nada y no se sabia por que.
			_show_feedback(Tr.t("LBL_CELL_OCCUPIED"))
		elif verdict["reason"] == "road":
			_show_feedback(Tr.t("LBL_NEEDS_ROAD"))
		return
	# Tope, requisitos, obreros y coste, en ese orden (PlacementRules).
	var blocked := Rules.purchase_block_detail(_current_data)
	if blocked != "":
		_show_feedback(blocked)
		return
	# La carretera automatica se paga con el edificio: si no llega para los dos,
	# no se pone ni un tramo (luego no quedarian calles a ninguna parte).
	var route: Array = verdict.get("route", [])
	if not route.is_empty() and not ResourceManager.can_afford(Rules.cost_with_route(_current_data, route)):
		_show_feedback(Tr.t("LBL_ROUTE_TOO_EXPENSIVE") % route.size())
		return
	if not route.is_empty():
		var laid := Rules.pave_route(self, route)
		_show_feedback(Tr.t("LBL_ROUTE_LAID") % [laid, laid])
	var cost := _current_data.get_cost()
	if not cost.is_empty():
		ResourceManager.spend_cost(cost)
	# Only now, with every check passed, does a consuming building eat its
	# deposit. Before, the oil well was removed BEFORE the limit / cost checks,
	# so a refused placement could still swallow the well.
	_consume_deposit_if_required(verdict, map_gen)
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
	# Decoraciones y caminos se ponen en serie; el resto, de uno en uno: se sale
	# del modo colocar por la misma senal que cualquier otra salida.
	if Rules.keeps_placing(_current_data):
		_hover_cell = Vector2i(-1, -1)
	else:
		EventBus.building_placement_cancelled.emit()

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
	_assist.begin()

func _try_move(cell: Vector2i) -> void:
	var rotated_size := _get_rotated_size()
	# Moving obeys the same deposit rule as placing; otherwise a sawmill could be
	# planted by a forest and then dragged anywhere.
	if _current_data.id == "road" and Rules.road_removal_strands(_moving_building) != null:
		_show_feedback(Tr.t("LBL_ROAD_NEEDED_BY"))
		return
	var map_gen := _map_generator()
	var verdict := evaluate_placement(_current_data.id, cell, rotated_size, map_gen, _moving_building)
	if not verdict["ok"]:
		if verdict["reason"] == "deposit":
			_reject_for_deposit(_current_data.id)
		elif verdict["reason"] == "occupied":
			_show_feedback(Tr.t("LBL_CELL_OCCUPIED"))
		elif verdict["reason"] == "road":
			_show_feedback(Tr.t("LBL_NEEDS_ROAD"))
		return
	# Llevado a donde no llega la red: su carretera se tiende (y se paga) igual
	# que al colocarlo.
	var move_route: Array = verdict.get("route", [])
	if not move_route.is_empty():
		if not ResourceManager.can_afford(Rules.route_cost(move_route)):
			_show_feedback(Tr.t("LBL_ROUTE_TOO_EXPENSIVE") % move_route.size())
			return
		Rules.pave_route(self, move_route)
	_consume_deposit_if_required(verdict, map_gen)
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
		for n in Rules.neighbor_roads(old_cell):
			_update_road_mesh(n["node"], n["cell"])
	EventBus.building_moved.emit(old_cell, cell)
	_cleanup_preview()
	_moving_building = null
	_current_data = null
	_rotation_steps = 0
	_state = State.IDLE

# ── Deposit rules ──

## The scene's MapGenerator, or null (tests, or a scene without one).
func _map_generator() -> Node:
	var scene := get_tree().current_scene if is_inside_tree() else null
	var found: Node = scene.get_node_or_null("MapGenerator") if scene else null
	# Como en la 2D: un hermano llamado MapGenerator (tests, herramientas).
	if found == null and get_parent():
		found = get_parent().get_node_or_null("MapGenerator")
	return found

## Full placement verdict for `building_id` with footprint `size` at `cell`:
## the GameConfig deposit rule (reach / overlap) AND free cells. Static so the
## same function serves the ghost preview, the click, the move and the tests.
## `ignore_building` is the building being moved (its own cells count as free).
## Returns {"ok": bool, "reason": "" | "deposit" | "occupied", "deposit": Node}.
static func evaluate_placement(building_id: String, cell: Vector2i, size: Vector2i, map_gen: Node, ignore_building: Node = null) -> Dictionary:
	return Rules.evaluate_placement(building_id, cell, size, map_gen, ignore_building)

## Removes the deposit a consuming building (the Refinery) is placed on.
func _consume_deposit_if_required(verdict: Dictionary, map_gen: Node) -> void:
	Rules.consume_deposit_if_required(_current_data.id, verdict, map_gen)

## Tells the player why the click was refused, on screen and in the log.
func _reject_for_deposit(building_id: String) -> void:
	var msg: String = Rules.deposit_reject_message(building_id)
	_show_feedback(msg)
	EventBus.notification_posted.emit(msg, "warning", Color(0.9, 0.6, 0.3))

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
		model = _current_data.instantiate_model()
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
	if _assist:
		_assist.end()

## Sin colocar ni mover nada. El menu de pausa lo pregunta antes de abrirse con
## ESC: mientras hay un edificio en la mano, ESC es "cancelar", no "pausa".
func is_idle() -> bool:
	return _state == State.IDLE

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
		var entry := Rules.serialize_building(building)
		if not entry.is_empty():
			result.append(entry)
	return result

func clear_all_buildings() -> void:
	for child in _buildings_container.get_children():
		child.queue_free()
	GridManager.clear_all()

# ── Create actual building mesh ──

# ── Road connectivity ──

## Get the neighbor bitmask for a road at the given cell (PlacementRules.ROAD_DIRS).
func _get_road_neighbors(cell: Vector2i) -> int:
	return Rules.road_neighbor_mask(cell)

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
	for n in Rules.neighbor_roads(cell):
		_update_road_mesh(n["node"], n["cell"])

# ── Create actual building mesh ──

func _create_building_mesh(data: BuildingData) -> Node3D:
	var root := Node3D.new()
	root.name = data.id

	if data.model_scene:
		var model_instance := data.instantiate_model()
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
	label.text = data.get_display_name()
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

	# Status badge (A11): Zzz / worker above every building that can work.
	# Measured from the real mesh so it clears the Nucleo's scaled dome too.
	var badge: Label3D = StatusBadge.new()
	var top: float = maxf(data.mesh_height, StatusBadge.measure_top(root))
	root.add_child(badge)
	badge.setup(root, data, top)

	return root

# ── Grid Overlay ──

func _show_grid_overlay() -> void:
	# Show the main scene GridOverlay (shader-based)
	var scene_grid: Node = get_tree().current_scene.get_node_or_null("GridOverlay") if get_tree().current_scene else null
	if scene_grid:
		scene_grid.visible = true

func _hide_grid_overlay() -> void:
	# Restore the user preference instead of always hiding — the Settings
	# toggle can keep the grid permanently visible.
	var scene_grid: Node = get_tree().current_scene.get_node_or_null("GridOverlay") if get_tree().current_scene else null
	if scene_grid:
		scene_grid.visible = GameConfig.ui_grid_visible

# ── Limit / Prerequisite Helpers ──

## Cuantos hay en pie de este tipo. Se le pregunta a GridManager, que guarda el
## BuildingData de cada edificio, y no al nombre del nodo: el nodo se bautiza con
## el id, pero Godot renombra a los hermanos repetidos ("house", "house2"...), asi
## que comparar nombres devolvia 1 siempre. Con eso ningun tope limitaba nada —
## cabian dos Cuarteles Generales con el tope en uno—, los Cuarteles de mas no
## daban plaza de entrenamiento, y el almacen compartido se quedaba en un solo
## Almacen hasta que el jugador guardaba y recargaba, que es cuando el tope subia
## de golpe porque la carga si los contaba bien.
func count_building(building_id: String) -> int:
	return Rules.count_building(building_id)

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
		# Un aviso no es un boton: el dedo que cae encima sigue siendo del mapa.
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

func _on_building_clicked(building: Node, _data: BuildingData) -> void:
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

# ── PlacementAssist (dedo, casillas validas, ✓) ───────────────────────

## Casilla bajo un punto de pantalla SIN recortar a la rejilla: un toque en el
## agua no es un toque en la casilla del borde. (-1, -1) si no corta el suelo.
func assist_screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var hit = _raycast_to_ground(screen_pos)
	if hit == null:
		return Vector2i(-1, -1)
	var local: Vector3 = (hit as Vector3) - GridManager.get_origin()
	return Vector2i(floori(local.x / GridManager.cell_size), floori(local.z / GridManager.cell_size))

func assist_cell_to_screen(origin: Vector2i, size: Vector2i) -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var w := GridManager.building_center(origin, size)
	if cam.is_position_behind(w):
		return null
	return cam.unproject_position(w)

func assist_ghost_top_screen(origin: Vector2i) -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _current_data == null or not GridManager.is_valid_cell(origin):
		return null
	var w := GridManager.building_center(origin, _get_rotated_size()) + Vector3(0.0, _current_data.mesh_height, 0.0)
	if cam.is_position_behind(w):
		return null
	var p := cam.unproject_position(w)
	return p if get_viewport().get_visible_rect().has_point(p) else null

func assist_move_ghost(origin: Vector2i) -> void:
	if GridManager.is_valid_cell(origin):
		_set_preview_cell(origin)

func assist_confirm(origin: Vector2i) -> void:
	if _state == State.PLACING:
		_try_place(origin)
	elif _state == State.MOVING:
		_try_move(origin)
	_hover_cell = Vector2i(-1, -1)

## Por que no se puede en `origin`: el mismo aviso que el clic rechazado.
func assist_explain(origin: Vector2i) -> void:
	if _current_data == null:
		return
	if not GridManager.is_valid_cell(origin):
		_show_feedback(Tr.t("LBL_OUTSIDE_MAP"))
		return
	var ignore: Node = _moving_building if _state == State.MOVING else null
	var verdict := evaluate_placement(_current_data.id, origin, _get_rotated_size(), _map_generator(), ignore)
	if verdict["reason"] == "deposit":
		_reject_for_deposit(_current_data.id)
	elif verdict["reason"] == "occupied":
		_show_feedback(Tr.t("LBL_CELL_OCCUPIED"))
	elif verdict["reason"] == "road":
		_show_feedback(Tr.t("LBL_NEEDS_ROAD"))

func assist_feedback(text: String) -> void:
	_show_feedback(text)

func assist_building_id() -> String:
	return _current_data.id if _current_data else ""

func assist_ghost_size() -> Vector2i:
	return _get_rotated_size() if _current_data else Vector2i.ONE

func assist_map_generator() -> Node:
	return _map_generator()

func assist_moving_node() -> Node:
	return _moving_building if _state == State.MOVING else null

func assist_is_placing() -> bool:
	return _state != State.IDLE

## Lleva la camara para que el origen `origin` quede en el centro de la pantalla.
func assist_center_on(origin: Vector2i) -> void:
	var vp := get_viewport().get_visible_rect().size
	var centre = _raycast_to_ground(vp * 0.5)
	if centre == null:
		return
	var w := GridManager.building_center(origin, assist_ghost_size())
	var c := centre as Vector3
	EventBus.camera_drag_world_requested.emit(Vector2(w.x - c.x, w.z - c.z))

func assist_show_cells(cells: Array) -> void:
	if cells.is_empty():
		if _spot_highlight:
			_spot_highlight.visible = false
		return
	if _spot_highlight == null:
		_spot_highlight = MultiMeshInstance3D.new()
		_spot_highlight.name = "ValidSpots"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE * GridManager.cell_size * 0.86
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(Assist.SPOT_COLOR, 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		plane.material = mat
		mm.mesh = plane
		_spot_highlight.multimesh = mm
		add_child(_spot_highlight)
	var multimesh := _spot_highlight.multimesh
	multimesh.instance_count = cells.size()
	for i in cells.size():
		var w := GridManager.cell_to_world(cells[i])
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(w.x, 0.06, w.z)))
	_spot_highlight.visible = true

func get_spot_highlight() -> MultiMeshInstance3D:
	return _spot_highlight

func get_assist() -> Node:
	return _assist
