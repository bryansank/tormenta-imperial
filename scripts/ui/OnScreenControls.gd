extends CanvasLayer
## On-screen controls: D-pad for panning, rotate buttons, zoom buttons.
## Emits signals through EventBus — same as keyboard/touch input.
##
## Only shown when GameConfig.touch_controls_enabled() (A5): on a mobile OS, or
## on a PC once a real finger touches the screen, or when forced from Settings.
## On a desktop there is WASD, the wheel, R, ESC and right-click, and these
## buttons were eating all four corners of the screen.
##
## While a building is being placed or moved, the right column also shows
## rotate-building and CANCEL: without it a finger had no way out of placement
## (cancel was right-click or ESC only).
##
## Tactil (docs/21 §Tactil):
## - Solo los Button paran el dedo. Cada contenedor (fila, columna, cruceta, el
##   hueco del centro) va en MOUSE_FILTER_IGNORE: un Container vale PASS por
##   defecto y el GUI entrega el toque a cualquier control no-IGNORE bajo el dedo,
##   asi que la fila inferior se comia el tercio de abajo del mapa (bug 8).
## - Mantener pulsado repite: la cruceta panea cada frame, zoom y giro disparan al
##   tocar y siguen solos tras GameConfig.hold_repeat_delay_sec (bug 5).
## - Semitransparentes: cada boton va a GameConfig.ui_touch_controls_opacity y se
##   ve entero mientras se pulsa (bug 7).

## Degrees the camera snaps per rotate-button press.
const ROTATE_STEP_DEGREES := 45.0

## Seconds between repeats of R held: a building turning 12 times a second is
## useless, one quarter turn every half second can be aimed.
const BUILDING_ROTATE_REPEAT_SEC := 0.45
## Zoom held: units of camera_zoom_requested per second (MonumentalCamera
## multiplies by its zoom_speed).
const HOLD_ZOOM_PER_SEC := 5.0

var _pan_direction: Vector2 = Vector2.ZERO
var _rotate_building_btn: Button = null
var _cancel_placement_btn: Button = null
## Every button of the layer, for the opacity.
var _buttons: Array[Button] = []
## Held buttons: Button -> {"t": seconds held, "next": next repeat time,
## "interval": seconds (0 = every frame), "repeat": Callable(delta)}.
var _holds: Dictionary = {}
var _opacity: float = 0.45

func _ready() -> void:
	layer = 10
	_setup_ui()
	EventBus.building_selected_for_placement.connect(func(_d): _set_placing(true))
	EventBus.request_move_building.connect(func(_b): _set_placing(true))
	EventBus.building_placement_cancelled.connect(func(): _set_placing(false))
	EventBus.building_placed.connect(func(_d, _c): pass)  # stay visible during rapid placement
	EventBus.building_moved.connect(func(_from, _to): _set_placing(false))
	EventBus.building_deselected.connect(func(): _set_placing(false))
	_apply_visibility(GameConfig.touch_controls_enabled())
	EventBus.touch_controls_changed.connect(_apply_visibility)
	set_opacity(GameConfig.ui_touch_controls_opacity)
	EventBus.touch_controls_opacity_changed.connect(set_opacity)

## Hides the whole layer. A held D-pad button is released too, so the camera
## does not keep drifting after the controls vanish under the finger.
func _apply_visibility(enabled: bool) -> void:
	visible = enabled
	if not enabled:
		_pan_direction = Vector2.ZERO
		_holds.clear()

## The placement pair (rotate building + cancel) comes and goes together.
func _set_placing(placing: bool) -> void:
	_rotate_building_btn.visible = placing
	_cancel_placement_btn.visible = placing

func is_placing_shown() -> bool:
	return _cancel_placement_btn.visible

## Same signal every other cancel path uses: BuildingPlacer listens to it.
func _on_cancel_placement() -> void:
	EventBus.building_placement_cancelled.emit()

func _process(delta: float) -> void:
	if not visible:
		return
	if _pan_direction != Vector2.ZERO:
		EventBus.camera_pan_requested.emit(_pan_direction.normalized())
	_tick_holds(delta)

# ── Mantener pulsado ──────────────────────────────────────────────────

## `btn` fires `on_press` the moment it is touched and, held past
## GameConfig.hold_repeat_delay_sec, `on_repeat(delta)` every `interval` seconds
## (0 = every frame, with the frame's delta, for continuous zoom and turn).
func _add_hold(btn: Button, on_press: Callable, on_repeat: Callable, interval: float) -> void:
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.button_down.connect(func():
		on_press.call()
		_holds[btn] = {"t": 0.0, "next": GameConfig.hold_repeat_delay_sec,
			"interval": interval, "repeat": on_repeat})
	btn.button_up.connect(func(): _holds.erase(btn))

func _tick_holds(delta: float) -> void:
	for btn in _holds.keys():
		if not is_instance_valid(btn) or not (btn as Button).is_visible_in_tree():
			_holds.erase(btn)
			continue
		var h: Dictionary = _holds[btn]
		h["t"] = float(h["t"]) + delta
		if float(h["t"]) < GameConfig.hold_repeat_delay_sec:
			continue
		var interval: float = h["interval"]
		if interval <= 0.0:
			(h["repeat"] as Callable).call(delta)
			continue
		while float(h["t"]) >= float(h["next"]):
			(h["repeat"] as Callable).call(interval)
			h["next"] = float(h["next"]) + interval

func is_holding(btn: Button) -> bool:
	return _holds.has(btn)

# ── Opacidad ──────────────────────────────────────────────────────────

## Background, border and glyph of every button at `value`; a pressed button
## shows at full strength until it is released.
func set_opacity(value: float) -> void:
	_opacity = clampf(value, GameConfig.TOUCH_OPACITY_MIN, GameConfig.TOUCH_OPACITY_MAX)
	for btn in _buttons:
		if is_instance_valid(btn):
			btn.modulate.a = 1.0 if (btn.button_pressed or _holds.has(btn)) else _opacity

func get_opacity() -> float:
	return _opacity

func get_buttons() -> Array[Button]:
	return _buttons

func _register(btn: Button) -> void:
	_buttons.append(btn)
	btn.modulate.a = _opacity
	# Al tocar, entero en el acto (es la confirmacion de que el dedo acerto); al
	# soltar vuelve a la opacidad elegida en release_fade_sec.
	btn.button_down.connect(func(): _flash(btn, 1.0, 0.0))
	btn.button_up.connect(func(): _flash(btn, _opacity, release_fade_sec))

## Seconds a released button takes to fade back (0 = at once; tests use it).
var release_fade_sec := 0.2

func _flash(btn: Button, alpha: float, seconds: float) -> void:
	if btn.has_meta("fade_tween"):
		var old: Tween = btn.get_meta("fade_tween")
		if old and old.is_valid():
			old.kill()
	if seconds <= 0.0 or not btn.is_inside_tree():
		btn.modulate.a = alpha
		return
	var tw := btn.create_tween()
	tw.tween_property(btn, "modulate:a", alpha, seconds)
	btn.set_meta("fade_tween", tw)

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
	hbox.name = "BottomRow"
	hbox.alignment = BoxContainer.ALIGNMENT_END
	hbox.size_flags_vertical = Control.SIZE_SHRINK_END
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(hbox)

	# D-Pad (left side)
	var dpad := _create_dpad()
	# Pegado abajo: sin esto la rejilla se estira a la altura de la columna
	# derecha (que crece al colocar) y las flechas se separan hacia arriba.
	dpad.size_flags_vertical = Control.SIZE_SHRINK_END
	hbox.add_child(dpad)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	# Right side: rotate + zoom stacked
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 12)
	right_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Pegada abajo: al colocar crece hacia arriba solo lo que ocupan sus botones.
	right_vbox.size_flags_vertical = Control.SIZE_SHRINK_END
	hbox.add_child(right_vbox)

	var rotate_box := _create_rotate_buttons()
	right_vbox.add_child(rotate_box)
	# La vista 2D (docs/18-vista-2d.md) no gira la camara: sin Camera3D, fuera.
	rotate_box.visible = get_viewport().get_camera_3d() != null

	# Building rotate button (visible only during placement)
	_rotate_building_btn = _styled_button("R ↻")
	_rotate_building_btn.custom_minimum_size = Vector2(108, 50)
	_rotate_building_btn.tooltip_text = Tr.ti("LBL_ROTATE_BUILDING")
	_add_hold(_rotate_building_btn, func(): EventBus.building_rotate_requested.emit(),
		func(_d: float): EventBus.building_rotate_requested.emit(), BUILDING_ROTATE_REPEAT_SEC)
	_rotate_building_btn.visible = false
	right_vbox.add_child(_rotate_building_btn)

	# Cancel placement / move (visible only during placement): the finger's ESC.
	_cancel_placement_btn = Button.new()
	_cancel_placement_btn.name = "CancelPlacement"
	_cancel_placement_btn.text = "✕ " + Tr.t("BTN_CANCEL").to_upper()
	_cancel_placement_btn.custom_minimum_size = Vector2(108, 50)
	_cancel_placement_btn.tooltip_text = Tr.ti("LBL_CANCEL_PLACEMENT_TIP")
	UITheme.style_button(_cancel_placement_btn, UITheme.DANGER, UITheme.FONT_BODY)
	_cancel_placement_btn.pressed.connect(_on_cancel_placement)
	_register(_cancel_placement_btn)
	_cancel_placement_btn.visible = false
	right_vbox.add_child(_cancel_placement_btn)

	var zoom_box := _create_zoom_buttons()
	right_vbox.add_child(zoom_box)

func _create_dpad() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
			# El centro de la cruceta no es un boton: el dedo pasa al mapa.
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# A touch snaps the camera a fixed step (smoothly eased by the camera); held,
	# it keeps turning at GameConfig.hold_rotate_degrees_per_sec.
	var rot_left := _styled_button("\u21BA")
	rot_left.name = "RotateLeft"
	_add_hold(rot_left, func(): EventBus.camera_rotate_step_requested.emit(-ROTATE_STEP_DEGREES),
		func(d: float): EventBus.camera_rotate_step_requested.emit(-GameConfig.hold_rotate_degrees_per_sec * d), 0.0)

	var rot_right := _styled_button("\u21BB")
	rot_right.name = "RotateRight"
	_add_hold(rot_right, func(): EventBus.camera_rotate_step_requested.emit(ROTATE_STEP_DEGREES),
		func(d: float): EventBus.camera_rotate_step_requested.emit(GameConfig.hold_rotate_degrees_per_sec * d), 0.0)

	hbox.add_child(rot_left)
	hbox.add_child(rot_right)
	return hbox

func _create_zoom_buttons() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# One step on touch, then a smooth zoom while held.
	var zoom_in := _styled_button("+")
	zoom_in.name = "ZoomIn"
	_add_hold(zoom_in, func(): EventBus.camera_zoom_requested.emit(-1.0),
		func(d: float): EventBus.camera_zoom_requested.emit(-HOLD_ZOOM_PER_SEC * d), 0.0)

	var zoom_out := _styled_button("-")
	zoom_out.name = "ZoomOut"
	_add_hold(zoom_out, func(): EventBus.camera_zoom_requested.emit(1.0),
		func(d: float): EventBus.camera_zoom_requested.emit(HOLD_ZOOM_PER_SEC * d), 0.0)

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
	UITheme.set_label_color(btn, UITheme.TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", UITheme.TEXT)
	btn.add_theme_color_override("font_pressed_color", UITheme.TEXT_BRIGHT)
	_register(btn)
	return btn
