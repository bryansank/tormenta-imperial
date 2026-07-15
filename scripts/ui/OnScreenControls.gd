extends CanvasLayer
## On-screen controls: D-pad for panning, rotate buttons, zoom buttons.
## Emits signals through EventBus — same as keyboard/touch input.

## Degrees the camera snaps per rotate-button press.
const ROTATE_STEP_DEGREES := 45.0

var _pan_direction: Vector2 = Vector2.ZERO
var _rotate_building_btn: Button = null

func _ready() -> void:
	layer = 10
	_setup_ui()
	EventBus.building_selected_for_placement.connect(func(_d): _rotate_building_btn.visible = true)
	EventBus.building_placement_cancelled.connect(func(): _rotate_building_btn.visible = false)
	EventBus.building_placed.connect(func(_d, _c): pass)  # stay visible during rapid placement
	EventBus.building_deselected.connect(func(): _rotate_building_btn.visible = false)

func _process(_delta: float) -> void:
	if _pan_direction != Vector2.ZERO:
		EventBus.camera_pan_requested.emit(_pan_direction.normalized())

func _setup_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	add_child(margin)

	# Bottom UI container
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

	# Building rotate button (visible only during placement)
	_rotate_building_btn = _styled_button("R ↻")
	_rotate_building_btn.custom_minimum_size = Vector2(108, 50)
	_rotate_building_btn.tooltip_text = Tr.t("LBL_ROTATE_BUILDING")
	_rotate_building_btn.pressed.connect(func(): EventBus.building_rotate_requested.emit())
	_rotate_building_btn.visible = false
	right_vbox.add_child(_rotate_building_btn)

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

	# Each press snaps the camera a fixed step (smoothly eased by the camera),
	# instead of nudging a tiny amount while held.
	var rot_left := _styled_button("\u21BA")
	rot_left.pressed.connect(func(): EventBus.camera_rotate_step_requested.emit(-ROTATE_STEP_DEGREES))

	var rot_right := _styled_button("\u21BB")
	rot_right.pressed.connect(func(): EventBus.camera_rotate_step_requested.emit(ROTATE_STEP_DEGREES))

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
	btn.custom_minimum_size = Vector2(48, 48)

	var bg_color := Color(UITheme.PANEL_BG.r, UITheme.PANEL_BG.g, UITheme.PANEL_BG.b, 0.7)

	var n := StyleBoxFlat.new()
	n.bg_color = bg_color
	n.set_corner_radius_all(6)
	n.set_content_margin_all(6)
	n.border_color = UITheme.ACCENT_DIM
	n.set_border_width_all(2)
	btn.add_theme_stylebox_override("normal", n)

	var h := StyleBoxFlat.new()
	h.bg_color = bg_color.lightened(0.15)
	h.set_corner_radius_all(6)
	h.set_content_margin_all(6)
	h.border_color = UITheme.ACCENT
	h.set_border_width_all(2)
	h.shadow_color = Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.3)
	h.shadow_size = 3
	btn.add_theme_stylebox_override("hover", h)

	var p := StyleBoxFlat.new()
	p.bg_color = bg_color.lightened(0.3)
	p.set_corner_radius_all(6)
	p.set_content_margin_all(6)
	p.border_color = UITheme.ACCENT
	p.set_border_width_all(3)
	btn.add_theme_stylebox_override("pressed", p)

	btn.add_theme_font_size_override("font_size", UITheme.FONT_SECTION)
	btn.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", UITheme.TEXT)
	btn.add_theme_color_override("font_pressed_color", UITheme.TEXT_BRIGHT)
	return btn
