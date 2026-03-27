extends CanvasLayer
## On-screen controls: D-pad for panning, rotate buttons, zoom buttons.
## Emits signals through EventBus — same as keyboard/touch input.

var _pan_direction: Vector2 = Vector2.ZERO
var _rotate_direction: float = 0.0

func _ready() -> void:
	layer = 10
	_setup_ui()

func _process(_delta: float) -> void:
	if _pan_direction != Vector2.ZERO:
		EventBus.camera_pan_requested.emit(_pan_direction.normalized())
	if _rotate_direction != 0.0:
		EventBus.camera_rotate_requested.emit(_rotate_direction)

func _setup_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_END
	hbox.size_flags_vertical = Control.SIZE_SHRINK_END
	margin.add_child(hbox)

	# D-Pad (left side)
	var dpad := _create_dpad()
	hbox.add_child(dpad)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	# Right side: rotate + zoom stacked
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 12)
	hbox.add_child(right_vbox)

	var rotate_box := _create_rotate_buttons()
	right_vbox.add_child(rotate_box)

	var zoom_box := _create_zoom_buttons()
	right_vbox.add_child(zoom_box)

func _create_dpad() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3

	# 8 directions: NW, N, NE, W, center, E, SW, S, SE
	var labels := ["\u2196", "\u2191", "\u2197",
				   "\u2190", "",       "\u2192",
				   "\u2199", "\u2193", "\u2198"]
	var dirs := [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1),
				 Vector2(-1, 0),  Vector2.ZERO,   Vector2(1, 0),
				 Vector2(-1, 1),  Vector2(0, 1),  Vector2(1, 1)]

	for i in range(9):
		if labels[i] == "":
			var empty := Control.new()
			empty.custom_minimum_size = Vector2(50, 50)
			grid.add_child(empty)
		else:
			var btn := _create_pad_button(labels[i], dirs[i])
			grid.add_child(btn)

	return grid

func _create_pad_button(label: String, direction: Vector2) -> Button:
	var btn := _styled_button(label)
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.button_down.connect(func(): _pan_direction += direction)
	btn.button_up.connect(func(): _pan_direction -= direction)
	return btn

func _create_rotate_buttons() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var rot_left := _styled_button("\u21BA")
	rot_left.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	rot_left.button_down.connect(func(): _rotate_direction -= 1.0)
	rot_left.button_up.connect(func(): _rotate_direction += 1.0)

	var rot_right := _styled_button("\u21BB")
	rot_right.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	rot_right.button_down.connect(func(): _rotate_direction += 1.0)
	rot_right.button_up.connect(func(): _rotate_direction -= 1.0)

	hbox.add_child(rot_left)
	hbox.add_child(rot_right)
	return hbox

func _create_zoom_buttons() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var zoom_in := _styled_button("+")
	zoom_in.pressed.connect(func(): EventBus.camera_zoom_requested.emit(-1.0))

	var zoom_out := _styled_button("-")
	zoom_out.pressed.connect(func(): EventBus.camera_zoom_requested.emit(1.0))

	hbox.add_child(zoom_in)
	hbox.add_child(zoom_out)
	return hbox

func _styled_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(50, 50)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.15, 0.15, 0.6)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.3, 0.3, 0.3, 0.8)
	pressed.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("pressed", pressed)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.2, 0.2, 0.2, 0.7)
	hover.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("hover", hover)

	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	btn.add_theme_font_size_override("font_size", 20)
	return btn
