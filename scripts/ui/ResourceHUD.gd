extends CanvasLayer
## Displays current resources (gold, steel, oil) at the top of the screen.
## Subscribes to EventBus.resource_changed to update in real-time.

var _labels: Dictionary = {}  # ResourceManager.Type -> Label

var _feedback_label: Label
var _feedback_tween: Tween

func _ready() -> void:
	layer = 10
	_setup_ui()
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.resources_insufficient.connect(_on_insufficient)

func _setup_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.custom_minimum_size.y = 40

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.7)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 40)
	panel.add_child(hbox)

	# Clear save button
	var clear_btn := Button.new()
	clear_btn.text = Tr.t("BTN_CLEAR")
	clear_btn.custom_minimum_size = Vector2(80, 28)
	var clear_style := StyleBoxFlat.new()
	clear_style.bg_color = Color(0.5, 0.15, 0.15, 0.8)
	clear_style.set_corner_radius_all(6)
	clear_btn.add_theme_stylebox_override("normal", clear_style)
	var clear_hover := StyleBoxFlat.new()
	clear_hover.bg_color = Color(0.6, 0.2, 0.2, 0.9)
	clear_hover.set_corner_radius_all(6)
	clear_btn.add_theme_stylebox_override("hover", clear_hover)
	clear_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	clear_btn.add_theme_font_size_override("font_size", 12)
	clear_btn.pressed.connect(func(): GameManager.clear_save())
	hbox.add_child(clear_btn)

	# Create label for each resource type
	var resource_ids := ["gold", "steel", "oil", "wood"]
	var resource_types := [
		ResourceManager.Type.GOLD,
		ResourceManager.Type.STEEL,
		ResourceManager.Type.OIL,
		ResourceManager.Type.WOOD,
	]
	var resource_colors := [
		Color(1.0, 0.85, 0.2),
		Color(0.7, 0.75, 0.8),
		Color(0.3, 0.3, 0.35),
		Color(0.55, 0.35, 0.15),
	]

	for i in range(resource_ids.size()):
		var type: ResourceManager.Type = resource_types[i]
		var res_id: String = resource_ids[i]
		var color: Color = resource_colors[i]

		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)

		var indicator := ColorRect.new()
		indicator.custom_minimum_size = Vector2(12, 12)
		indicator.color = color
		item.add_child(indicator)

		var name_label := Label.new()
		name_label.text = Tr.res_upper(res_id)
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		item.add_child(name_label)

		var amount_label := Label.new()
		amount_label.text = str(ResourceManager.get_amount(type))
		amount_label.add_theme_font_size_override("font_size", 16)
		amount_label.add_theme_color_override("font_color", Color(1, 1, 1))
		item.add_child(amount_label)

		_labels[type] = amount_label
		hbox.add_child(item)

func _on_resource_changed(resource_type: String, new_amount: int, _delta: int) -> void:
	for type in _labels:
		if ResourceManager.get_type_name(type) == resource_type:
			_labels[type].text = str(new_amount)
			# Flash red if at cap
			var cap := ResourceManager.get_storage_cap()
			if new_amount >= cap:
				_labels[type].add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
			else:
				_labels[type].add_theme_color_override("font_color", Color(1, 1, 1))
			break

func _on_insufficient(_resource_type: String, _required: int, _available: int) -> void:
	_show_feedback(Tr.t("LBL_NOT_ENOUGH_RESOURCES"))

func _show_feedback(text: String) -> void:
	if not _feedback_label:
		_feedback_label = Label.new()
		_feedback_label.add_theme_font_size_override("font_size", 18)
		_feedback_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_feedback_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_feedback_label.position.y = 50
		_feedback_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		add_child(_feedback_label)
	_feedback_label.text = text
	_feedback_label.modulate.a = 1.0
	_feedback_label.visible = true
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(1.5)
	_feedback_tween.tween_property(_feedback_label, "modulate:a", 0.0, 0.8)
	_feedback_tween.tween_callback(func(): _feedback_label.visible = false)
