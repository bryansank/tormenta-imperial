extends CanvasLayer
## Displays current resources (gold, steel, oil) at the top of the screen.
## Subscribes to EventBus.resource_changed to update in real-time.

var _labels: Dictionary = {}  # ResourceManager.Type -> Label

func _ready() -> void:
	layer = 10
	_setup_ui()
	EventBus.resource_changed.connect(_on_resource_changed)

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

	# LIMPIAR button (clear save and restart)
	var clear_btn := Button.new()
	clear_btn.text = "LIMPIAR"
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
	var resource_config := [
		[ResourceManager.Type.GOLD, "ORO", Color(1.0, 0.85, 0.2)],
		[ResourceManager.Type.STEEL, "ACERO", Color(0.7, 0.75, 0.8)],
		[ResourceManager.Type.OIL, "PETROLEO", Color(0.3, 0.3, 0.35)],
		[ResourceManager.Type.WOOD, "MADERA", Color(0.55, 0.35, 0.15)],
	]

	for config in resource_config:
		var type: ResourceManager.Type = config[0]
		var name: String = config[1]
		var color: Color = config[2]

		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)

		# Color indicator
		var indicator := ColorRect.new()
		indicator.custom_minimum_size = Vector2(12, 12)
		indicator.color = color
		item.add_child(indicator)

		# Name
		var name_label := Label.new()
		name_label.text = name
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		item.add_child(name_label)

		# Amount
		var amount_label := Label.new()
		amount_label.text = str(ResourceManager.get_amount(type))
		amount_label.add_theme_font_size_override("font_size", 16)
		amount_label.add_theme_color_override("font_color", Color(1, 1, 1))
		item.add_child(amount_label)

		_labels[type] = amount_label
		hbox.add_child(item)

func _on_resource_changed(resource_type: String, new_amount: int, _delta: int) -> void:
	# Find the Type enum from the string name
	for type in _labels:
		if ResourceManager.get_type_name(type) == resource_type:
			_labels[type].text = str(new_amount)
			break
