class_name ProcessActionsPanel
## Manages process/mining buttons and progress display.
## Styled card buttons with clear cost/produce layout.

var _processes_box: VBoxContainer
var _progress_container: VBoxContainer
var _progress_bar: ProgressBar
var _progress_label: Label

func _init(processes_box: VBoxContainer, progress_container: VBoxContainer,
		progress_bar: ProgressBar, progress_label: Label) -> void:
	_processes_box = processes_box
	_progress_container = progress_container
	_progress_bar = progress_bar
	_progress_label = progress_label

func clear() -> void:
	for child in _processes_box.get_children():
		child.queue_free()

func populate_building(node: Node3D, data: BuildingData, is_constructing: bool) -> void:
	clear()
	var processes := ProcessManager.get_processes_for(data.id)
	for proc in processes:
		_add_process_card(proc, node)
	if processes.is_empty() and not data.is_core:
		var no_actions := Label.new()
		no_actions.text = Tr.t("LBL_NO_ACTIONS")
		no_actions.add_theme_font_size_override("font_size", 12)
		no_actions.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		no_actions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_processes_box.add_child(no_actions)
	if is_constructing:
		set_buttons_disabled(true)
	update_progress(node, false, data)

func populate_deposit(node: Node3D, deposit_id: String) -> void:
	clear()
	var mining := ProcessManager.get_mining_info(deposit_id)
	if not mining.is_empty():
		_add_mining_card(mining, node, deposit_id)
	update_progress(node, true, null)

func update_progress(node: Node3D, is_deposit: bool, data: BuildingData) -> void:
	if not node:
		_progress_container.visible = false
		return
	var active := ProcessManager.get_active(node)
	if active.is_empty():
		_progress_container.visible = false
		if not is_deposit and data and not ProductionManager.is_constructing(node):
			set_buttons_disabled(false)
		return
	_progress_container.visible = true
	_progress_bar.value = ProcessManager.get_progress(node)
	var remaining: float = active["remaining"]
	_progress_label.text = Tr.t("FMT_PROGRESS") % [active["name"], ceili(remaining)]
	set_buttons_disabled(true)

func set_buttons_disabled(disabled: bool) -> void:
	for child in _processes_box.get_children():
		if child is Button:
			child.disabled = disabled

# ── Styled Process Card ──

func _add_process_card(proc: Dictionary, node: Node3D) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 0)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Build label with clear sections
	var lines: Array = []
	lines.append(Tr.t(proc["name"]))

	# Cost line (red)
	if proc.has("cost") and not proc["cost"].is_empty():
		var cost_parts: Array = []
		for res_id in proc["cost"]:
			cost_parts.append("-%d %s" % [proc["cost"][res_id], Tr.res_name(res_id)])
		lines.append(Tr.t("FMT_COST") % " | ".join(cost_parts))

	# Produce line (green)
	var produce_parts: Array = []
	for res_id in proc["produces"]:
		produce_parts.append("+%d %s" % [proc["produces"][res_id], Tr.res_name(res_id)])
	lines.append(Tr.t("FMT_PRODUCES") % " | ".join(produce_parts))

	# Duration
	lines.append(Tr.t("FMT_DURATION") % int(proc["duration"]))

	btn.text = "\n".join(lines)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	_style_card_button(btn, Color(0.14, 0.16, 0.2, 0.9))
	btn.pressed.connect(func(): _start_process(node, proc))
	_processes_box.add_child(btn)

func _add_mining_card(mining: Dictionary, node: Node3D, deposit_id: String) -> void:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lines: Array = []
	lines.append(Tr.t(mining["name"]))

	var parts: Array = []
	for res_id in mining["produces"]:
		parts.append("+%d %s" % [mining["produces"][res_id], Tr.res_name(res_id)])
	lines.append(Tr.t("FMT_PRODUCES") % " | ".join(parts))
	lines.append(Tr.t("FMT_DURATION") % int(mining["duration"]))

	btn.text = "\n".join(lines)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	_style_card_button(btn, Color(0.12, 0.18, 0.14, 0.9))
	btn.pressed.connect(func(): _start_mining(node, deposit_id))
	_processes_box.add_child(btn)

func _style_card_button(btn: Button, bg_color: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_color
	normal.border_color = Color(0.4, 0.35, 0.15, 0.5)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = bg_color.lightened(0.12)
	hover.border_color = Color(0.7, 0.55, 0.15, 0.7)
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(8)
	hover.set_content_margin_all(10)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = bg_color.lightened(0.25)
	pressed.border_color = Color(0.7, 0.55, 0.15, 0.9)
	pressed.set_border_width_all(1)
	pressed.set_corner_radius_all(8)
	pressed.set_content_margin_all(10)
	btn.add_theme_stylebox_override("pressed", pressed)

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.12, 0.12, 0.12, 0.6)
	disabled.border_color = Color(0.3, 0.3, 0.3, 0.3)
	disabled.set_border_width_all(1)
	disabled.set_corner_radius_all(8)
	disabled.set_content_margin_all(10)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8))
	btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.45))

func _start_process(node: Node3D, proc: Dictionary) -> void:
	if node and not ProcessManager.is_busy(node):
		ProcessManager.start_process(node, proc)

func _start_mining(node: Node3D, deposit_id: String) -> void:
	if node and not ProcessManager.is_busy(node):
		ProcessManager.start_mining(node, deposit_id)
