extends CanvasLayer
## Displays current resources at the top of the screen.
## Only shows unlocked resources. Animates new resources appearing.

var _labels: Dictionary = {}
var _items: Dictionary = {}
var _hbox: HBoxContainer
var _feedback_label: Label
var _feedback_tween: Tween

var _resource_ids := ["gold", "steel", "oil", "wood"]
var _resource_types := [
	ResourceManager.Type.GOLD, ResourceManager.Type.STEEL,
	ResourceManager.Type.OIL, ResourceManager.Type.WOOD,
]
var _resource_colors := [UITheme.RES_GOLD, UITheme.RES_STEEL, UITheme.RES_OIL, UITheme.RES_WOOD]

func _ready() -> void:
	layer = 10
	_setup_ui()
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.resources_insufficient.connect(_on_insufficient)
	EventBus.resource_unlocked.connect(_on_resource_unlocked)

func _setup_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.custom_minimum_size.y = 50
	panel.add_theme_stylebox_override("panel", UITheme.make_command_panel_style())
	add_child(panel)

	_hbox = HBoxContainer.new()
	_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_hbox.add_theme_constant_override("separation", 32)
	panel.add_child(_hbox)

	# Clear save button
	var clear_btn := Button.new()
	clear_btn.text = Tr.t("BTN_CLEAR")
	clear_btn.custom_minimum_size = Vector2(80, 30)
	UITheme.style_button(clear_btn, UITheme.DANGER, UITheme.FONT_SMALL)
	clear_btn.pressed.connect(func(): GameManager.clear_save())
	_hbox.add_child(clear_btn)

	for i in range(_resource_ids.size()):
		var type: ResourceManager.Type = _resource_types[i]
		var res_id: String = _resource_ids[i]
		var color: Color = _resource_colors[i]

		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)

		var indicator := ColorRect.new()
		indicator.custom_minimum_size = Vector2(14, 14)
		indicator.color = color
		item.add_child(indicator)

		var name_label := UITheme.make_label(Tr.res_upper(res_id), "small", UITheme.TEXT_DIM)
		item.add_child(name_label)

		var amount_label := UITheme.make_label(str(ResourceManager.get_amount(type)), "section", UITheme.TEXT)
		item.add_child(amount_label)

		_labels[type] = amount_label
		_items[type] = item
		_hbox.add_child(item)
		item.visible = ResourceManager.is_unlocked(type)

func _on_resource_changed(resource_type: String, new_amount: int, _delta: int) -> void:
	for type in _labels:
		if ResourceManager.get_type_name(type) == resource_type:
			_labels[type].text = str(new_amount)
			var cap := ResourceManager.get_storage_cap()
			if new_amount >= cap:
				_labels[type].add_theme_color_override("font_color", UITheme.WARNING)
			else:
				_labels[type].add_theme_color_override("font_color", UITheme.TEXT)
			break

func _on_resource_unlocked(resource_name: String) -> void:
	for i in range(_resource_ids.size()):
		if _resource_ids[i] == resource_name:
			var type: ResourceManager.Type = _resource_types[i]
			var item: HBoxContainer = _items[type]
			item.visible = true
			item.modulate = Color(2.0, 1.8, 0.5, 1.0)
			var tween := create_tween()
			tween.tween_property(item, "modulate", Color(1, 1, 1, 1), 1.5).set_ease(Tween.EASE_OUT)
			break

func _on_insufficient(_resource_type: String, _required: int, _available: int) -> void:
	_show_feedback(Tr.t("LBL_NOT_ENOUGH_RESOURCES"))

func _show_feedback(text: String) -> void:
	if not _feedback_label:
		_feedback_label = UITheme.make_label("", "section", UITheme.DANGER)
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
