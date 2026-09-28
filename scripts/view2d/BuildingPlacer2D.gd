extends Node2D
## BuildingPlacer de la vista 2D: colocar, girar, mover, demoler y seleccionar
## edificios y yacimientos sobre el mapa plano.
##
## Mismo contrato que BuildingPlacer (3D) hacia fuera: escucha las mismas
## senales, emite las mismas, se registra en GameManager y expone la misma API
## (place_building_at, get_all_placed_buildings, clear_all_buildings,
## count_building). Las reglas —veredicto de colocacion, topes, requisitos,
## bolsa, demoler, formato de guardado— no estan aqui: son PlacementRules, las
## mismas que usa la 3D. Aqui solo vive lo que es de la vista: pantalla -> celda,
## el fantasma, el arrastre del mapa y el dibujo.
##
## En la escena se llama "BuildingPlacer": ArmyManager y las reglas de yacimiento
## lo buscan por ese nombre.

enum State { IDLE, PLACING, MOVING }

const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")
const Building2D := preload("res://scripts/view2d/Building2D.gd")
## Dedo, casillas validas y boton ✓: lo mismo que en 3D (docs/21 §Tactil).
const Assist := preload("res://scripts/buildings/PlacementAssist.gd")

var _state: State = State.IDLE
var _current_data: BuildingData = null
var _rotation_steps := 0
var _moving_building: Node2D = null
var _ghost: Node2D = null
var _hover_cell := Vector2i(-99999, -99999)
var _selected: Node = null

var _left_pressed := false
var _left_press_pos := Vector2.ZERO
var _drag_last_pos := Vector2.ZERO
var _left_dragged := false
var _left_from_touch := false

var _buildings_container: Node2D
var _assist: Node = null
var _spot_highlight: Node2D = null
var _spot_cells: Array = []

func _ready() -> void:
	_buildings_container = Node2D.new()
	_buildings_container.name = "Buildings"
	_buildings_container.z_index = 2
	add_child(_buildings_container)
	EventBus.building_selected_for_placement.connect(_on_building_selected)
	EventBus.building_placement_cancelled.connect(_cancel)
	EventBus.request_move_building.connect(_on_move_requested)
	EventBus.request_demolish_building.connect(_on_demolish_requested)
	EventBus.building_clicked.connect(_on_building_clicked)
	EventBus.deposit_clicked.connect(_on_deposit_clicked)
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

# ── Pantalla -> celda ─────────────────────────────────────────────────

## Celda bajo un punto de pantalla. Fuera de la rejilla devuelve una celda
## invalida (el agua no es la celda del borde).
func screen_to_cell(screen_pos: Vector2) -> Vector2i:
	return View2D.screen_to_cell(get_viewport().get_canvas_transform(), screen_pos)

func get_state() -> int:
	return _state

func get_ghost() -> Node2D:
	return _ghost

# ── Entrada ───────────────────────────────────────────────────────────

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
			if get_viewport().gui_get_hovered_control() != null:
				return
			# La misma senal que ESC en 3D y el CANCELAR en pantalla: _cancel la
			# escucha, y tambien los controles tactiles y la ayuda.
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

## Igual que en 3D: con el raton se coloca al pulsar; con el dedo, al levantarlo
## (hasta entonces no se sabe si era un toque o un arrastre del mapa). En reposo,
## un clic sin arrastre selecciona y un arrastre mueve el mapa.
func _handle_left_button(event: InputEventMouseButton) -> void:
	if event.pressed:
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
			handle_click(event.position)
		return
	var was_click := _left_pressed and not _left_dragged
	if _left_from_touch and InputService.touch_pan_consumed_click():
		was_click = false
	# Colocando, el dedo lo lleva PlacementAssist: el clic emulado no planta.
	if _left_from_touch and _state != State.IDLE:
		was_click = false
	_left_pressed = false
	_left_dragged = false
	_left_from_touch = false
	if was_click:
		handle_click(event.position)

func _handle_left_drag(event: InputEventMouseMotion) -> void:
	# El dedo lo panea InputService con la misma cuenta; aqui iria el doble.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if _state != State.IDLE:
		_left_pressed = false
		return
	if not _left_dragged and event.position.distance_to(_left_press_pos) < GameConfig.mouse_drag_threshold_px:
		return
	_left_dragged = true
	var prev := _drag_last_pos
	_drag_last_pos = event.position
	EventBus.camera_drag_world_requested.emit(
		View2D.screen_drag_to_world_delta(get_viewport().get_canvas_transform(), prev, event.position))
	get_viewport().set_input_as_handled()

## Un clic (o toque) ya decidido en `screen_pos`: selecciona en reposo, coloca o
## mueve si hay fantasma. Publico para las herramientas y los tests.
func handle_click(screen_pos: Vector2) -> void:
	var cell := screen_to_cell(screen_pos)
	match _state:
		State.IDLE:
			_try_select(cell)
		State.PLACING:
			if GridManager.is_valid_cell(cell):
				try_place(cell)
		State.MOVING:
			if GridManager.is_valid_cell(cell):
				try_move(cell)

func _process(_delta: float) -> void:
	if _state == State.IDLE or _ghost == null:
		return
	# Con el dedo el fantasma esta donde lo dejo el ultimo toque.
	var cell: Vector2i = _assist.cell if _assist.touch_aim else screen_to_cell(get_viewport().get_mouse_position())
	if cell != _hover_cell:
		_hover_cell = cell
		update_ghost(cell)

# ── Fantasma ──────────────────────────────────────────────────────────

## Pone el fantasma sobre `cell` y lo tine segun el veredicto (el mismo que el clic).
func update_ghost(cell: Vector2i) -> void:
	if _ghost == null or _current_data == null:
		return
	var size := Rules.rotated_size(_current_data, _rotation_steps)
	_ghost.position = View2D.footprint_center_px(cell, size)
	var ignore: Node = _moving_building if _state == State.MOVING else null
	var ok: bool = GridManager.is_valid_cell(cell) and bool(Rules.evaluate_placement(_current_data.id, cell, size, _map_generator(), ignore)["ok"])
	_ghost.set("ghost_valid", ok)
	_ghost.set_meta("rotation_steps", _rotation_steps)
	_ghost.queue_redraw()

func _create_ghost() -> void:
	_cleanup_ghost()
	_ghost = Building2D.new()
	_ghost.setup(_current_data, true)
	_ghost.modulate = Color(1, 1, 1, 0.72)
	_ghost.set_meta("rotation_steps", _rotation_steps)
	add_child(_ghost)
	_show_grid_overlay(true)
	_hover_cell = Vector2i(-99999, -99999)
	_assist.begin()

func _cleanup_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_show_grid_overlay(false)
	if _assist:
		_assist.end()

func _rotate_building() -> void:
	_rotation_steps = (_rotation_steps + 1) % 4
	_hover_cell = Vector2i(-99999, -99999)
	if _ghost:
		_ghost.set_meta("rotation_steps", _rotation_steps)
		_ghost.queue_redraw()
	_assist.refresh_spots()
	if _assist.touch_aim:
		_assist.move_to(_assist.cell, false)

func _on_rotate_requested() -> void:
	if _state != State.IDLE:
		_rotate_building()

func _show_grid_overlay(forced: bool) -> void:
	var scene := get_tree().current_scene if is_inside_tree() else null
	var grid := scene.get_node_or_null("GridOverlay") if scene else null
	if grid:
		grid.visible = forced or GameConfig.ui_grid_visible

# ── Colocar ───────────────────────────────────────────────────────────

func _on_building_selected(data: Resource) -> void:
	_cancel()
	_current_data = data as BuildingData
	_rotation_steps = 0
	_state = State.PLACING
	_create_ghost()

## Intenta plantar el edificio en curso en `cell`. Devuelve el nodo o null.
func try_place(cell: Vector2i) -> Node:
	if _current_data == null:
		return null
	var size := Rules.rotated_size(_current_data, _rotation_steps)
	var map_gen := _map_generator()
	var verdict := Rules.evaluate_placement(_current_data.id, cell, size, map_gen)
	if not verdict["ok"]:
		if verdict["reason"] == "deposit":
			_reject_for_deposit(_current_data.id)
		elif verdict["reason"] == "occupied":
			_show_feedback(Tr.t("LBL_CELL_OCCUPIED"))
		return null
	var blocked := Rules.purchase_block_message(_current_data)
	if blocked != "":
		_show_feedback(blocked)
		return null
	var cost := _current_data.get_cost()
	if not cost.is_empty():
		ResourceManager.spend_cost(cost)
	# Solo ahora, pasadas todas las comprobaciones, se come el pozo la Refineria.
	Rules.consume_deposit_if_required(_current_data.id, verdict, map_gen)
	var building := _spawn(_current_data, cell, _rotation_steps)
	building.set_meta("level", 1)
	if _current_data.id == "warehouse":
		ResourceManager.set_warehouse_count(count_building("warehouse"))
	_redraw_roads_around(cell)
	EventBus.building_placed.emit(_current_data, cell)
	# Se sigue en modo colocacion para construir en serie, como en 3D.
	_hover_cell = Vector2i(-99999, -99999)
	return building

func _spawn(data: BuildingData, cell: Vector2i, rot_steps: int) -> Node2D:
	var building: Node2D = Building2D.new()
	building.setup(data)
	building.set_meta("rotation_steps", rot_steps)
	_buildings_container.add_child(building)
	var size := Rules.rotated_size(data, rot_steps)
	building.position = View2D.footprint_center_px(cell, size)
	GridManager.place_building(cell, Rules.placement_data(data, rot_steps), building)
	return building

# ── Mover ─────────────────────────────────────────────────────────────

func _on_move_requested(building: Node) -> void:
	var info := GridManager.get_building_info(building)
	if info.is_empty():
		return
	var data := info["data"] as BuildingData
	if data.is_core:
		return
	_cancel()
	_moving_building = building as Node2D
	_current_data = Rules.load_building_data(data.id)
	if _current_data == null:
		_current_data = data
	_rotation_steps = building.get_meta("rotation_steps", 0)
	_state = State.MOVING
	_moving_building.visible = false
	_create_ghost()

func try_move(cell: Vector2i) -> bool:
	if _moving_building == null or _current_data == null:
		return false
	var size := Rules.rotated_size(_current_data, _rotation_steps)
	var map_gen := _map_generator()
	var verdict := Rules.evaluate_placement(_current_data.id, cell, size, map_gen, _moving_building)
	if not verdict["ok"]:
		if verdict["reason"] == "deposit":
			_reject_for_deposit(_current_data.id)
		elif verdict["reason"] == "occupied":
			_show_feedback(Tr.t("LBL_CELL_OCCUPIED"))
		return false
	Rules.consume_deposit_if_required(_current_data.id, verdict, map_gen)
	var old_info := GridManager.get_building_info(_moving_building)
	var old_cell: Vector2i = old_info.get("origin_cell", cell)
	GridManager.remove_building(_moving_building)
	GridManager.place_building(cell, Rules.placement_data(_current_data, _rotation_steps), _moving_building)
	_moving_building.position = View2D.footprint_center_px(cell, size)
	_moving_building.set_meta("rotation_steps", _rotation_steps)
	_moving_building.visible = true
	_moving_building.queue_redraw()
	if _current_data.id == "road":
		_redraw_roads_around(old_cell)
		_redraw_roads_around(cell)
	EventBus.building_moved.emit(old_cell, cell)
	_cleanup_ghost()
	_moving_building = null
	_current_data = null
	_rotation_steps = 0
	_state = State.IDLE
	return true

# ── Demoler ───────────────────────────────────────────────────────────

func _on_demolish_requested(building: Node) -> void:
	var result := Rules.demolish(building)
	if result.is_empty():
		return
	var data: BuildingData = result["data"]
	var cell: Vector2i = result["cell"]
	if building == _selected:
		_selected = null
	building.queue_free()
	if data.id == "road":
		_redraw_roads_around(cell)
	if data.id == "warehouse":
		ResourceManager.set_warehouse_count(count_building("warehouse"))
	EventBus.building_demolished.emit(building, cell)

func _redraw_roads_around(cell: Vector2i) -> void:
	# Building2D relee su mascara de calzada cada frame; basta con pedir repintado.
	for n in Rules.neighbor_roads(cell):
		(n["node"] as CanvasItem).queue_redraw()

## Sin colocar ni mover nada. El menu de pausa lo pregunta antes de abrirse con
## ESC: mientras hay un edificio en la mano, ESC es "cancelar", no "pausa".
func is_idle() -> bool:
	return _state == State.IDLE

func _cancel() -> void:
	if _state == State.MOVING and _moving_building:
		_moving_building.visible = true
	_cleanup_ghost()
	_moving_building = null
	_current_data = null
	_rotation_steps = 0
	_state = State.IDLE

# ── Seleccion ─────────────────────────────────────────────────────────

func _try_select(cell: Vector2i) -> void:
	var node := GridManager.get_building_at(cell) if GridManager.is_valid_cell(cell) else null
	if node == null:
		EventBus.building_deselected.emit()
		return
	var info := GridManager.get_building_info(node)
	if not info.is_empty():
		EventBus.building_clicked.emit(node, info["data"])
	elif node.has_meta("deposit_id"):
		EventBus.deposit_clicked.emit(node, node.get_meta("deposit_id"), cell)
	else:
		EventBus.building_deselected.emit()

func _set_selected(node: Node) -> void:
	if is_instance_valid(_selected) and _selected.has_method("set_selected"):
		_selected.set_selected(false)
	_selected = node
	if is_instance_valid(_selected) and _selected.has_method("set_selected"):
		_selected.set_selected(true)

func _on_building_clicked(building: Node, _data: BuildingData) -> void:
	_set_selected(building)

func _on_deposit_clicked(deposit: Node, _id: String, _cell: Vector2i) -> void:
	_set_selected(deposit)

func _on_building_deselected() -> void:
	_set_selected(null)

# ── Reglas compartidas ────────────────────────────────────────────────

func _map_generator() -> Node:
	var scene := get_tree().current_scene if is_inside_tree() else null
	var found: Node = scene.get_node_or_null("MapGenerator") if scene else null
	if found == null and get_parent():
		found = get_parent().get_node_or_null("MapGenerator")
	return found

func _reject_for_deposit(building_id: String) -> void:
	var msg: String = Rules.deposit_reject_message(building_id)
	_show_feedback(msg)
	EventBus.notification_posted.emit(msg, "warning", Color(0.9, 0.6, 0.3))

func count_building(building_id: String) -> int:
	return Rules.count_building(building_id)

# ── API publica (GameManager) ─────────────────────────────────────────

func place_building_at(data: BuildingData, cell: Vector2i, rot_steps: int = 0) -> Node:
	if not GridManager.can_place(cell, Rules.rotated_size(data, rot_steps)):
		return null
	var building := _spawn(data, cell, rot_steps)
	if data.id == "road":
		_redraw_roads_around.call_deferred(cell)
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

# ── Aviso en pantalla ─────────────────────────────────────────────────

var _feedback_canvas: CanvasLayer = null
var _feedback_panel: PanelContainer = null
var _feedback_label: Label = null
var _feedback_tween: Tween = null

func _show_feedback(text: String) -> void:
	if _feedback_canvas == null:
		_feedback_canvas = CanvasLayer.new()
		_feedback_canvas.layer = 15
		add_child(_feedback_canvas)
		_feedback_panel = PanelContainer.new()
		_feedback_panel.set_anchors_preset(Control.PRESET_CENTER)
		_feedback_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_feedback_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		_feedback_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.08, 0.05, 0.9)
		style.border_color = UITheme.DANGER
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		style.set_content_margin_all(12)
		_feedback_panel.add_theme_stylebox_override("panel", style)
		_feedback_label = UITheme.make_label("", "body", Color(1.0, 0.85, 0.7))
		_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_feedback_label.custom_minimum_size.x = 240
		_feedback_panel.add_child(_feedback_label)
		_feedback_canvas.add_child(_feedback_panel)
	_feedback_label.text = text
	_feedback_panel.visible = true
	_feedback_panel.modulate = Color.WHITE
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(1.2)
	_feedback_tween.tween_property(_feedback_panel, "modulate:a", 0.0, 0.5)
	_feedback_tween.tween_callback(func(): _feedback_panel.visible = false)

# ── PlacementAssist (dedo, casillas validas, ✓) ───────────────────────

func assist_screen_to_cell(screen_pos: Vector2) -> Vector2i:
	return screen_to_cell(screen_pos)

func assist_cell_to_screen(origin: Vector2i, size: Vector2i) -> Variant:
	return View2D.px_to_screen(get_viewport().get_canvas_transform(), View2D.footprint_center_px(origin, size))

func assist_ghost_top_screen(origin: Vector2i) -> Variant:
	if _current_data == null or not GridManager.is_valid_cell(origin):
		return null
	var r := View2D.footprint_rect_px(origin, Rules.rotated_size(_current_data, _rotation_steps))
	var p := View2D.px_to_screen(get_viewport().get_canvas_transform(), Vector2(r.get_center().x, r.position.y))
	return p if get_viewport().get_visible_rect().has_point(p) else null

func assist_move_ghost(origin: Vector2i) -> void:
	_hover_cell = origin
	update_ghost(origin)

func assist_confirm(origin: Vector2i) -> void:
	if _state == State.PLACING:
		try_place(origin)
	elif _state == State.MOVING:
		try_move(origin)
	if _ghost:
		update_ghost(origin)

## Por que no se puede en `origin`: el mismo aviso que el clic rechazado.
func assist_explain(origin: Vector2i) -> void:
	if _current_data == null:
		return
	if not GridManager.is_valid_cell(origin):
		_show_feedback(Tr.t("LBL_OUTSIDE_MAP"))
		return
	var ignore: Node = _moving_building if _state == State.MOVING else null
	var verdict := Rules.evaluate_placement(_current_data.id, origin, Rules.rotated_size(_current_data, _rotation_steps), _map_generator(), ignore)
	if verdict["reason"] == "deposit":
		_reject_for_deposit(_current_data.id)
	elif verdict["reason"] == "occupied":
		_show_feedback(Tr.t("LBL_CELL_OCCUPIED"))

func assist_feedback(text: String) -> void:
	_show_feedback(text)

func assist_building_id() -> String:
	return _current_data.id if _current_data else ""

func assist_ghost_size() -> Vector2i:
	return Rules.rotated_size(_current_data, _rotation_steps) if _current_data else Vector2i.ONE

func assist_map_generator() -> Node:
	return _map_generator()

func assist_moving_node() -> Node:
	return _moving_building if _state == State.MOVING else null

func assist_is_placing() -> bool:
	return _state != State.IDLE

func assist_center_on(origin: Vector2i) -> void:
	var vp := get_viewport().get_visible_rect().size
	var centre_px := View2D.screen_to_px(get_viewport().get_canvas_transform(), vp * 0.5)
	var target_px := View2D.footprint_center_px(origin, assist_ghost_size())
	EventBus.camera_drag_world_requested.emit((target_px - centre_px) / View2D.PX_PER_UNIT)

func assist_show_cells(cells: Array) -> void:
	_spot_cells = cells
	if _spot_highlight == null:
		if cells.is_empty():
			return
		_spot_highlight = Node2D.new()
		_spot_highlight.name = "ValidSpots"
		# Encima del suelo y de la rejilla, debajo de los edificios (z 2).
		_spot_highlight.z_index = 1
		_spot_highlight.draw.connect(_draw_spots)
		add_child(_spot_highlight)
	_spot_highlight.visible = not cells.is_empty()
	_spot_highlight.queue_redraw()

func _draw_spots() -> void:
	var fill := Color(Assist.SPOT_COLOR, 0.45)
	var edge := Color(Assist.SPOT_COLOR, 0.95)
	for c in _spot_cells:
		var r := View2D.footprint_rect_px(c, Vector2i.ONE).grow(-2.0)
		_spot_highlight.draw_rect(r, fill, true)
		_spot_highlight.draw_rect(r, edge, false, 1.5)

func get_spot_highlight() -> Node2D:
	return _spot_highlight

func get_spot_cells() -> Array:
	return _spot_cells

func get_assist() -> Node:
	return _assist
