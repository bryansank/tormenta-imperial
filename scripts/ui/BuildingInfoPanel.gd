extends CanvasLayer
## Panel that appears when selecting a building or deposit.
## Scrollable, styled, with upgrade, demolish confirm, level display.

var _panel: PanelContainer
var _scroll: ScrollContainer
var _vbox: VBoxContainer
var _title_label: Label
var _level_label: Label
var _desc_label: Label
var _production_container: PanelContainer
var _production_label: Label
var _construction_container: VBoxContainer
var _construction_label: Label
var _construction_bar: ProgressBar
var _deposit_uses_label: Label
var _name_container: HBoxContainer
var _name_edit: LineEdit
var _upgrade_container: VBoxContainer
var _upgrade_btn: Button
var _upgrade_cost_label: Label
var _actions_box: HBoxContainer
var _move_btn: Button
var _demolish_btn: Button
var _close_btn: Button
var _confirm_container: VBoxContainer
var _confirm_label: Label

var _process_panel: ProcessActionsPanel
var _selected_node: Node3D = null
var _selected_data: BuildingData = null
var _selected_deposit_id: String = ""
var _is_deposit: bool = false
var _demolish_pending: bool = false

func _ready() -> void:
	layer = 10
	_build_ui()
	_panel.visible = false

	EventBus.building_clicked.connect(_on_building_clicked)
	EventBus.building_deselected.connect(_on_deselected)
	EventBus.deposit_clicked.connect(_on_deposit_clicked)
	EventBus.process_completed.connect(_on_process_event)
	EventBus.mining_completed.connect(_on_mining_event)
	EventBus.construction_completed.connect(_on_construction_completed)
	EventBus.building_upgrade_completed.connect(_on_upgrade_completed)
	EventBus.building_selected_for_placement.connect(func(_d): _hide_panel())
	EventBus.building_demolished.connect(func(_n, _c): _hide_panel())
	EventBus.deposit_depleted.connect(func(n, _id): if n == _selected_node: _hide_panel())

func _process(_delta: float) -> void:
	if not _selected_node or not _panel.visible:
		return
	if not is_instance_valid(_selected_node):
		_hide_panel()
		return
	_process_panel.update_progress(_selected_node, _is_deposit, _selected_data)
	_update_construction()

# ── UI Construction ──

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	UILayoutManager.apply_layout("BuildingInfoPanel", _panel)
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(_scroll)

	var vbox_margin := MarginContainer.new()
	vbox_margin.add_theme_constant_override("margin_left", UITheme.MARGIN)
	vbox_margin.add_theme_constant_override("margin_right", UITheme.MARGIN)
	vbox_margin.add_theme_constant_override("margin_top", UITheme.MARGIN)
	vbox_margin.add_theme_constant_override("margin_bottom", UITheme.MARGIN)
	vbox_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(vbox_margin)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_margin.add_child(_vbox)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	_title_label = UITheme.make_label("", "title", UITheme.ACCENT)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_title_label)
	_close_btn = UITheme.make_close_button(_hide_panel)
	header.add_child(_close_btn)
	_vbox.add_child(header)

	# Level label
	_level_label = UITheme.make_label("", "body", UITheme.INFO)
	_vbox.add_child(_level_label)

	# Description
	_desc_label = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_vbox.add_child(_desc_label)

	# Production info card
	_production_container = PanelContainer.new()
	var prod_style := StyleBoxFlat.new()
	prod_style.bg_color = UITheme.POSITIVE.darkened(0.7)
	prod_style.set_corner_radius_all(UITheme.CORNER)
	prod_style.set_content_margin_all(8)
	prod_style.border_color = UITheme.POSITIVE.darkened(0.3)
	prod_style.border_width_left = 3
	_production_container.add_theme_stylebox_override("panel", prod_style)
	_production_label = UITheme.make_label("", "body", UITheme.POSITIVE)
	_production_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_production_container.add_child(_production_label)
	_vbox.add_child(_production_container)

	# Deposit uses
	_deposit_uses_label = UITheme.make_label("", "body", UITheme.WARNING)
	_deposit_uses_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(_deposit_uses_label)

	# Construction state
	_construction_container = VBoxContainer.new()
	_construction_container.add_theme_constant_override("separation", 4)
	_construction_label = UITheme.make_label("", "body", UITheme.WARNING)
	_construction_bar = UITheme.make_progress_bar(UITheme.WARNING)
	_construction_container.add_child(_construction_label)
	_construction_container.add_child(_construction_bar)
	_vbox.add_child(_construction_container)

	# Name editor (nucleus)
	_name_container = HBoxContainer.new()
	_name_container.add_theme_constant_override("separation", 4)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = Tr.t("LBL_BUILDING_NAME_PLACEHOLDER")
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 20
	_name_edit.text_submitted.connect(func(_t): _on_rename())
	var name_btn := Button.new()
	name_btn.text = Tr.t("BTN_RENAME")
	UITheme.style_button(name_btn, UITheme.INFO)
	name_btn.pressed.connect(_on_rename)
	_name_container.add_child(_name_edit)
	_name_container.add_child(name_btn)
	_vbox.add_child(_name_container)

	# Upgrade section
	_upgrade_container = VBoxContainer.new()
	_upgrade_container.add_theme_constant_override("separation", 4)
	_upgrade_cost_label = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	_upgrade_cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_upgrade_container.add_child(_upgrade_cost_label)
	_upgrade_btn = Button.new()
	_upgrade_btn.text = Tr.t("BTN_UPGRADE")
	UITheme.style_button(_upgrade_btn, UITheme.INFO)
	_upgrade_btn.pressed.connect(_on_upgrade)
	_upgrade_container.add_child(_upgrade_btn)
	_vbox.add_child(_upgrade_container)

	_vbox.add_child(UITheme.make_separator())

	# Processes header
	_vbox.add_child(UITheme.section_header(Tr.t("LBL_ACTIONS"), UITheme.ACCENT))

	# Process actions (delegated)
	var processes_box := VBoxContainer.new()
	processes_box.add_theme_constant_override("separation", 6)
	_vbox.add_child(processes_box)

	# Progress bar
	var progress_container := VBoxContainer.new()
	progress_container.add_theme_constant_override("separation", 3)
	var progress_label := UITheme.make_label("", "small", UITheme.WARNING)
	var progress_bar := UITheme.make_progress_bar(UITheme.ACCENT, 14)
	progress_container.add_child(progress_label)
	progress_container.add_child(progress_bar)
	_vbox.add_child(progress_container)
	_process_panel = ProcessActionsPanel.new(processes_box, progress_container, progress_bar, progress_label)

	_vbox.add_child(UITheme.make_separator())

	# Action buttons
	_actions_box = HBoxContainer.new()
	_actions_box.add_theme_constant_override("separation", 8)
	_actions_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_move_btn = Button.new()
	_move_btn.text = Tr.t("BTN_MOVE")
	UITheme.style_button(_move_btn, UITheme.INFO)
	_move_btn.pressed.connect(_on_move)
	_demolish_btn = Button.new()
	_demolish_btn.text = Tr.t("BTN_DEMOLISH")
	UITheme.style_button(_demolish_btn, UITheme.DANGER)
	_demolish_btn.pressed.connect(_on_demolish)
	_actions_box.add_child(_move_btn)
	_actions_box.add_child(_demolish_btn)
	_vbox.add_child(_actions_box)

	# Demolish confirmation
	_confirm_container = VBoxContainer.new()
	_confirm_container.add_theme_constant_override("separation", 4)
	_confirm_container.visible = false
	_confirm_label = UITheme.make_label("", "body", UITheme.DANGER)
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_container.add_child(_confirm_label)
	var confirm_row := HBoxContainer.new()
	confirm_row.add_theme_constant_override("separation", 8)
	confirm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var yes_btn := Button.new()
	yes_btn.text = Tr.t("BTN_CONFIRM")
	UITheme.style_button(yes_btn, UITheme.DANGER)
	yes_btn.pressed.connect(_confirm_demolish)
	var no_btn := Button.new()
	no_btn.text = Tr.t("BTN_CANCEL")
	UITheme.style_button(no_btn, UITheme.BTN)
	no_btn.pressed.connect(_cancel_demolish)
	confirm_row.add_child(yes_btn)
	confirm_row.add_child(no_btn)
	_confirm_container.add_child(confirm_row)
	_vbox.add_child(_confirm_container)

	add_child(_panel)

# ── Event Handlers ──

func _on_building_clicked(building_node: Node3D, building_data: Resource) -> void:
	_selected_node = building_node
	_selected_data = building_data as BuildingData
	_selected_deposit_id = ""
	_is_deposit = false
	_demolish_pending = false
	_show_building_panel()

func _on_deposit_clicked(deposit_node: Node3D, deposit_id: String, _cell: Vector2i) -> void:
	_selected_node = deposit_node
	_selected_data = null
	_selected_deposit_id = deposit_id
	_is_deposit = true
	_demolish_pending = false
	_show_deposit_panel()

func _on_deselected() -> void:
	_hide_panel()

func _on_process_event(node: Node3D, _pid: String) -> void:
	if node == _selected_node:
		_process_panel.update_progress(_selected_node, _is_deposit, _selected_data)

func _on_mining_event(node: Node3D, _pid: String) -> void:
	if node == _selected_node:
		_process_panel.update_progress(_selected_node, _is_deposit, _selected_data)
		if _is_deposit and is_instance_valid(_selected_node):
			_update_deposit_uses()

func _on_construction_completed(node: Node3D) -> void:
	if node == _selected_node:
		_show_building_panel()

func _on_upgrade_completed(node: Node3D, _new_level: int) -> void:
	if node == _selected_node:
		_show_building_panel()

# ── Panel Display ──

func _show_building_panel() -> void:
	_confirm_container.visible = false
	var custom_name: String = _selected_node.get_meta("custom_name", "")
	_title_label.text = custom_name if not custom_name.is_empty() else _selected_data.display_name
	_desc_label.text = _selected_data.description
	_desc_label.visible = not _selected_data.description.is_empty()

	# Level display + workers/morale info
	var level: int = _selected_node.get_meta("level", 1)
	var level_text := Tr.t("LBL_LEVEL") % [level]
	if _selected_data.workers_required > 0:
		level_text += "  |  " + Tr.t("LBL_WORKERS_NEEDED") % _selected_data.workers_required
	if _selected_data.population_capacity > 0:
		level_text += "  |  " + Tr.t("LBL_POP_CAPACITY") % _selected_data.population_capacity
	if _selected_data.morale_bonus > 0:
		level_text += "  |  " + Tr.t("LBL_MORALE_BONUS") % _selected_data.morale_bonus
	_level_label.text = level_text
	_level_label.visible = true

	# Production info (with level multiplier)
	var mult := GameConfig.get_production_multiplier(level)
	var prod_parts: Array = []
	if _selected_data.produces_gold > 0:
		prod_parts.append("+%d %s" % [int(_selected_data.produces_gold * mult), Tr.res_name("gold")])
	if _selected_data.produces_steel > 0:
		prod_parts.append("+%d %s" % [int(_selected_data.produces_steel * mult), Tr.res_name("steel")])
	if _selected_data.produces_oil > 0:
		prod_parts.append("+%d %s" % [int(_selected_data.produces_oil * mult), Tr.res_name("oil")])
	if _selected_data.produces_wood > 0:
		prod_parts.append("+%d %s" % [int(_selected_data.produces_wood * mult), Tr.res_name("wood")])
	if not prod_parts.is_empty():
		var interval := GameConfig.get_production_interval(_selected_data.production_interval)
		_production_label.text = Tr.t("FMT_PRODUCES_EVERY") % [" | ".join(prod_parts), int(interval)]
		_production_container.visible = true
	else:
		_production_container.visible = false

	_deposit_uses_label.visible = false

	var is_building := ProductionManager.is_constructing(_selected_node)
	_construction_container.visible = is_building
	if is_building:
		_update_construction()

	_name_container.visible = _selected_data.is_core and not is_building
	if _selected_data.is_core:
		_name_edit.text = custom_name

	# Upgrade section
	var next_level := level + 1
	if next_level <= GameConfig.max_building_level and not is_building:
		var cost := GameConfig.get_upgrade_cost(_selected_data, next_level)
		var cost_parts: Array = []
		for type in cost:
			cost_parts.append("%d %s" % [cost[type], Tr.res_name(ResourceManager.get_type_name(type))])
		_upgrade_btn.text = Tr.t("LBL_UPGRADE_TO") % [next_level]
		_upgrade_cost_label.text = Tr.t("FMT_COST") % " | ".join(cost_parts)
		_upgrade_btn.disabled = not ResourceManager.can_afford(cost)
		_upgrade_container.visible = true
	else:
		if level >= GameConfig.max_building_level:
			_upgrade_cost_label.text = Tr.t("LBL_MAX_LEVEL")
			_upgrade_btn.visible = false
			_upgrade_container.visible = true
		else:
			_upgrade_container.visible = false

	_move_btn.visible = not _selected_data.is_core and not is_building
	_demolish_btn.visible = not _selected_data.is_core

	_process_panel.populate_building(_selected_node, _selected_data, is_building)
	_scroll.scroll_vertical = 0
	_panel.visible = true
	UIManager.open_window(self)

func _show_deposit_panel() -> void:
	_confirm_container.visible = false
	var display_name := _selected_deposit_id
	for child in _selected_node.get_children():
		if child is Label3D:
			display_name = child.text
			break
	_title_label.text = display_name
	_desc_label.text = Tr.t("LBL_NATURAL_RESOURCE")
	_desc_label.visible = true
	_level_label.visible = false
	_production_container.visible = false
	_construction_container.visible = false
	_name_container.visible = false
	_upgrade_container.visible = false
	_move_btn.visible = false
	_demolish_btn.visible = false
	_update_deposit_uses()
	_process_panel.populate_deposit(_selected_node, _selected_deposit_id)
	_scroll.scroll_vertical = 0
	_panel.visible = true
	UIManager.open_window(self)

func _update_deposit_uses() -> void:
	if _selected_node and _selected_node.has_meta("uses_remaining"):
		var uses: int = _selected_node.get_meta("uses_remaining")
		_deposit_uses_label.text = Tr.t("LBL_DEPOSIT_USES") % [uses]
		_deposit_uses_label.visible = true
	else:
		_deposit_uses_label.visible = false

func _hide_panel() -> void:
	if _panel.visible:
		UIManager.close_window(self)
	_panel.visible = false
	_selected_node = null
	_selected_data = null
	_selected_deposit_id = ""
	_demolish_pending = false

func _toggle_panel() -> void:
	_hide_panel()

# ── Actions ──

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

func _on_upgrade() -> void:
	if not _selected_node or not _selected_data:
		return
	var level: int = _selected_node.get_meta("level", 1)
	var next_level := level + 1
	if next_level > GameConfig.max_building_level:
		return
	ProductionManager.start_upgrade(_selected_node, _selected_data, next_level)
	_show_building_panel()

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
	# Show confirmation
	_demolish_pending = true
	var refund_pct := int(GameConfig.demolish_refund_ratio * 100)
	_confirm_label.text = Tr.t("FMT_DEMOLISH_CONFIRM") % [_selected_data.display_name, refund_pct]
	_confirm_container.visible = true
	_actions_box.visible = false

func _confirm_demolish() -> void:
	if _demolish_pending and _selected_node:
		EventBus.request_demolish_building.emit(_selected_node)
	_demolish_pending = false
	_confirm_container.visible = false
	_actions_box.visible = true

func _cancel_demolish() -> void:
	_demolish_pending = false
	_confirm_container.visible = false
	_actions_box.visible = true

# ── Construction ──

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
	_construction_label.text = Tr.t("FMT_CONSTRUCTION") % [int(progress * 100), ceili(remaining)]
