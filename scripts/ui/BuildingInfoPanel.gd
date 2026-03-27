extends CanvasLayer
## Panel that appears when selecting a building or deposit.
## Shows name, production info, rename (nucleus), processes, construction state,
## progress bars, move/demolish/close buttons.

var _panel: PanelContainer
var _vbox: VBoxContainer
var _title_label: Label
var _desc_label: Label
var _production_label: Label
var _construction_container: VBoxContainer
var _construction_label: Label
var _construction_bar: ProgressBar
var _name_container: HBoxContainer
var _name_edit: LineEdit
var _processes_box: VBoxContainer
var _progress_container: VBoxContainer
var _progress_bar: ProgressBar
var _progress_label: Label
var _actions_box: HBoxContainer
var _move_btn: Button
var _demolish_btn: Button
var _close_btn: Button

var _selected_node: Node3D = null
var _selected_data: BuildingData = null
var _selected_deposit_id: String = ""
var _is_deposit: bool = false

func _ready() -> void:
	layer = 10
	_build_ui()
	_panel.visible = false

	EventBus.building_clicked.connect(_on_building_clicked)
	EventBus.building_deselected.connect(_on_deselected)
	EventBus.deposit_clicked.connect(_on_deposit_clicked)
	EventBus.process_completed.connect(_on_process_event)
	EventBus.mining_completed.connect(_on_process_event)
	EventBus.construction_completed.connect(_on_construction_completed)
	EventBus.building_selected_for_placement.connect(func(_d): _hide_panel())
	EventBus.building_demolished.connect(func(_n, _c): _hide_panel())

func _process(_delta: float) -> void:
	if not _selected_node or not _panel.visible:
		return
	if not is_instance_valid(_selected_node):
		_hide_panel()
		return
	_update_progress()
	_update_construction()

# ── UI Construction ──

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(280, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.94)
	style.border_color = Color(0.65, 0.5, 0.15, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)

	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.offset_left = -295
	_panel.offset_right = -10
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(_vbox)

	# Title
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.25))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(_title_label)

	# Description
	_desc_label = Label.new()
	_desc_label.add_theme_font_size_override("font_size", 12)
	_desc_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_vbox.add_child(_desc_label)

	# Production info
	_production_label = Label.new()
	_production_label.add_theme_font_size_override("font_size", 13)
	_production_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.4))
	_production_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_vbox.add_child(_production_label)

	# Construction state
	_construction_container = VBoxContainer.new()
	_construction_container.add_theme_constant_override("separation", 2)
	_construction_label = Label.new()
	_construction_label.add_theme_font_size_override("font_size", 13)
	_construction_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_construction_bar = ProgressBar.new()
	_construction_bar.custom_minimum_size = Vector2(0, 16)
	_construction_bar.max_value = 1.0
	_construction_bar.show_percentage = false
	var constr_bg := StyleBoxFlat.new()
	constr_bg.bg_color = Color(0.15, 0.15, 0.15)
	constr_bg.set_corner_radius_all(3)
	_construction_bar.add_theme_stylebox_override("background", constr_bg)
	var constr_fill := StyleBoxFlat.new()
	constr_fill.bg_color = Color(0.9, 0.7, 0.1)
	constr_fill.set_corner_radius_all(3)
	_construction_bar.add_theme_stylebox_override("fill", constr_fill)
	_construction_container.add_child(_construction_label)
	_construction_container.add_child(_construction_bar)
	_vbox.add_child(_construction_container)

	# Name editor (nucleus)
	_name_container = HBoxContainer.new()
	_name_container.add_theme_constant_override("separation", 4)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Nombre del edificio..."
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 20
	_name_edit.text_submitted.connect(func(_t): _on_rename())
	var name_btn := Button.new()
	name_btn.text = "Renombrar"
	name_btn.pressed.connect(_on_rename)
	_name_container.add_child(_name_edit)
	_name_container.add_child(name_btn)
	_vbox.add_child(_name_container)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.4, 0.35, 0.15, 0.6))
	_vbox.add_child(sep)

	# Processes header
	var proc_header := Label.new()
	proc_header.text = "Acciones"
	proc_header.add_theme_font_size_override("font_size", 14)
	proc_header.add_theme_color_override("font_color", Color(0.75, 0.7, 0.5))
	_vbox.add_child(proc_header)

	_processes_box = VBoxContainer.new()
	_processes_box.add_theme_constant_override("separation", 4)
	_vbox.add_child(_processes_box)

	# Process progress
	_progress_container = VBoxContainer.new()
	_progress_container.add_theme_constant_override("separation", 2)
	_progress_label = Label.new()
	_progress_label.add_theme_font_size_override("font_size", 12)
	_progress_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.5))
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 18)
	_progress_bar.max_value = 1.0
	_progress_bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.15, 0.15, 0.15)
	bar_bg.set_corner_radius_all(3)
	_progress_bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.8, 0.6, 0.1)
	bar_fill.set_corner_radius_all(3)
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)
	_progress_container.add_child(_progress_label)
	_progress_container.add_child(_progress_bar)
	_vbox.add_child(_progress_container)

	# Action buttons
	_actions_box = HBoxContainer.new()
	_actions_box.add_theme_constant_override("separation", 6)
	_actions_box.alignment = BoxContainer.ALIGNMENT_CENTER

	_move_btn = Button.new()
	_move_btn.text = "Mover"
	_move_btn.pressed.connect(_on_move)

	_demolish_btn = Button.new()
	_demolish_btn.text = "Demoler"
	_demolish_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	_demolish_btn.pressed.connect(_on_demolish)

	_close_btn = Button.new()
	_close_btn.text = "Cerrar"
	_close_btn.pressed.connect(_hide_panel)

	_actions_box.add_child(_move_btn)
	_actions_box.add_child(_demolish_btn)
	_actions_box.add_child(_close_btn)
	_vbox.add_child(_actions_box)

	add_child(_panel)

# ── Event Handlers ──

func _on_building_clicked(building_node: Node3D, building_data: Resource) -> void:
	_selected_node = building_node
	_selected_data = building_data as BuildingData
	_selected_deposit_id = ""
	_is_deposit = false
	_show_building_panel()

func _on_deposit_clicked(deposit_node: Node3D, deposit_id: String, _cell: Vector2i) -> void:
	_selected_node = deposit_node
	_selected_data = null
	_selected_deposit_id = deposit_id
	_is_deposit = true
	_show_deposit_panel()

func _on_deselected() -> void:
	_hide_panel()

func _on_process_event(node: Node3D, _pid: String) -> void:
	if node == _selected_node:
		_update_progress()

func _on_construction_completed(node: Node3D) -> void:
	if node == _selected_node:
		_show_building_panel()

# ── Panel Display ──

func _show_building_panel() -> void:
	var custom_name: String = _selected_node.get_meta("custom_name", "")
	_title_label.text = custom_name if not custom_name.is_empty() else _selected_data.display_name
	_desc_label.text = _selected_data.description
	_desc_label.visible = not _selected_data.description.is_empty()

	# Production info
	var prod_parts: Array = []
	if _selected_data.produces_gold > 0:
		prod_parts.append("+%d oro" % _selected_data.produces_gold)
	if _selected_data.produces_steel > 0:
		prod_parts.append("+%d acero" % _selected_data.produces_steel)
	if _selected_data.produces_oil > 0:
		prod_parts.append("+%d petroleo" % _selected_data.produces_oil)
	if _selected_data.produces_wood > 0:
		prod_parts.append("+%d madera" % _selected_data.produces_wood)
	if not prod_parts.is_empty():
		_production_label.text = "Produce: %s cada %ds" % [" | ".join(prod_parts), int(_selected_data.production_interval)]
		_production_label.visible = true
	else:
		_production_label.visible = false

	# Construction state
	var is_building := ProductionManager.is_constructing(_selected_node)
	_construction_container.visible = is_building
	if is_building:
		_update_construction()

	# Name editor: visible for core buildings (not during construction)
	_name_container.visible = _selected_data.is_core and not is_building

	if _selected_data.is_core:
		_name_edit.text = custom_name

	# Move/demolish: only for non-core
	_move_btn.visible = not _selected_data.is_core and not is_building
	_demolish_btn.visible = not _selected_data.is_core

	# Populate process buttons (disabled during construction)
	_clear_processes()
	var processes := ProcessManager.get_processes_for(_selected_data.id)
	for proc in processes:
		_add_process_button(proc)

	if processes.is_empty() and not _selected_data.is_core:
		var no_actions := Label.new()
		no_actions.text = "Sin acciones disponibles"
		no_actions.add_theme_font_size_override("font_size", 12)
		no_actions.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_processes_box.add_child(no_actions)

	# Disable process buttons if constructing
	if is_building:
		_set_buttons_disabled(true)

	_update_progress()
	_panel.visible = true

func _show_deposit_panel() -> void:
	var display_name := _selected_deposit_id
	for child in _selected_node.get_children():
		if child is Label3D:
			display_name = child.text
			break
	_title_label.text = display_name
	_desc_label.text = "Recurso natural disponible para extraccion."
	_desc_label.visible = true
	_production_label.visible = false
	_construction_container.visible = false
	_name_container.visible = false
	_move_btn.visible = false
	_demolish_btn.visible = false

	_clear_processes()
	var mining := ProcessManager.get_mining_info(_selected_deposit_id)
	if not mining.is_empty():
		_add_mining_button(mining)

	_update_progress()
	_panel.visible = true

func _hide_panel() -> void:
	_panel.visible = false
	_selected_node = null
	_selected_data = null
	_selected_deposit_id = ""

# ── Process Buttons ──

func _clear_processes() -> void:
	for child in _processes_box.get_children():
		child.queue_free()

func _add_process_button(proc: Dictionary) -> void:
	var btn := Button.new()
	var cost_parts: Array = []
	if proc.has("cost"):
		for res_name in proc["cost"]:
			cost_parts.append("%d %s" % [proc["cost"][res_name], _translate_res(res_name)])
	var produce_parts: Array = []
	for res_name in proc["produces"]:
		produce_parts.append("+%d %s" % [proc["produces"][res_name], _translate_res(res_name)])

	var label := proc["name"]
	if not cost_parts.is_empty():
		label += "\nCosto: %s" % " | ".join(cost_parts)
	label += "\nProduce: %s" % " | ".join(produce_parts)
	label += " (%ds)" % int(proc["duration"])

	btn.text = label
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(_start_process.bind(proc))
	_processes_box.add_child(btn)

func _add_mining_button(mining: Dictionary) -> void:
	var btn := Button.new()
	var parts: Array = []
	for res_name in mining["produces"]:
		parts.append("+%d %s" % [mining["produces"][res_name], _translate_res(res_name)])
	btn.text = "%s\nProduce: %s (%ds)" % [mining["name"], " | ".join(parts), int(mining["duration"])]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(_start_mining)
	_processes_box.add_child(btn)

# ── Actions ──

func _start_process(proc: Dictionary) -> void:
	if _selected_node and not ProcessManager.is_busy(_selected_node):
		ProcessManager.start_process(_selected_node, proc)
		_update_progress()

func _start_mining() -> void:
	if _selected_node and not ProcessManager.is_busy(_selected_node):
		ProcessManager.start_mining(_selected_node, _selected_deposit_id)
		_update_progress()

func _on_rename() -> void:
	if not _selected_node or not _selected_data or not _selected_data.is_core:
		return
	var new_name := _name_edit.text.strip_edges()
	if new_name.is_empty():
		return
	_selected_node.set_meta("custom_name", new_name)
	_title_label.text = new_name
	var label_node := _selected_node.get_node_or_null("NameLabel")
	if label_node and label_node is Label3D:
		label_node.text = new_name
	EventBus.building_renamed.emit(_selected_node, new_name)

func _on_move() -> void:
	if not _selected_node or _is_deposit:
		return
	if _selected_data and _selected_data.is_core:
		return
	EventBus.request_move_building.emit(_selected_node)
	_hide_panel()

func _on_demolish() -> void:
	if not _selected_node or _is_deposit:
		return
	if _selected_data and _selected_data.is_core:
		return
	EventBus.request_demolish_building.emit(_selected_node)

# ── Progress Updates ──

func _update_progress() -> void:
	if not _selected_node:
		_progress_container.visible = false
		return
	var active := ProcessManager.get_active(_selected_node)
	if active.is_empty():
		_progress_container.visible = false
		if not _is_deposit and _selected_data and not ProductionManager.is_constructing(_selected_node):
			_set_buttons_disabled(false)
		return
	_progress_container.visible = true
	_progress_bar.value = ProcessManager.get_progress(_selected_node)
	var remaining: float = active["remaining"]
	_progress_label.text = "%s — %ds restantes" % [active["name"], ceili(remaining)]
	_set_buttons_disabled(true)

func _update_construction() -> void:
	if not _selected_node or _is_deposit:
		_construction_container.visible = false
		return
	if not ProductionManager.is_constructing(_selected_node):
		_construction_container.visible = false
		return
	_construction_container.visible = true
	var progress := ProductionManager.get_construction_progress(_selected_node)
	_construction_bar.value = progress
	var remaining := ProductionManager.get_construction_remaining(_selected_node)
	_construction_label.text = "En construccion: %d%% — %ds restantes" % [int(progress * 100), ceili(remaining)]

func _set_buttons_disabled(disabled: bool) -> void:
	for child in _processes_box.get_children():
		if child is Button:
			child.disabled = disabled

# ── Helpers ──

func _translate_res(res_name: String) -> String:
	match res_name:
		"gold": return "oro"
		"steel": return "acero"
		"oil": return "petroleo"
		"wood": return "madera"
	return res_name
