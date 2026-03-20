extends Node
## Unified input service: abstracts keyboard, mouse, and touch into EventBus signals.
## Supports: WASD/Arrows (pan), scroll wheel (zoom), middle-mouse drag (pan),
## single-finger drag (pan), two-finger pinch (zoom).

@export var mouse_drag_sensitivity: float = 0.05
@export var touch_drag_sensitivity: float = 0.02
@export var pinch_zoom_sensitivity: float = 0.05

var _is_mouse_dragging: bool = false
var _touch_points: Dictionary = {}  # index -> position
var _last_pinch_distance: float = 0.0

func _process(_delta: float) -> void:
	_handle_keyboard()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)

# ── Keyboard ──

func _handle_keyboard() -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if dir != Vector2.ZERO:
		EventBus.camera_pan_requested.emit(dir.normalized())

# ── Mouse ──

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			EventBus.camera_zoom_requested.emit(-1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			EventBus.camera_zoom_requested.emit(1.0)
		MOUSE_BUTTON_MIDDLE:
			_is_mouse_dragging = event.pressed

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_mouse_dragging:
		EventBus.camera_drag_moved.emit(event.relative * mouse_drag_sensitivity)

# ── Touch ──

func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_points[event.index] = event.position
	else:
		_touch_points.erase(event.index)

	# Reset pinch baseline when two fingers land
	if _touch_points.size() == 2:
		var points := _touch_points.values()
		_last_pinch_distance = (points[0] as Vector2).distance_to(points[1] as Vector2)

func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	_touch_points[event.index] = event.position

	if _touch_points.size() == 1:
		# Single finger → pan
		EventBus.camera_drag_moved.emit(event.relative * touch_drag_sensitivity)
	elif _touch_points.size() == 2:
		# Two fingers → pinch zoom
		var points := _touch_points.values()
		var current_dist := (points[0] as Vector2).distance_to(points[1] as Vector2)
		var diff := current_dist - _last_pinch_distance
		if absf(diff) > 1.0:
			EventBus.camera_zoom_requested.emit(-diff * pinch_zoom_sensitivity)
			_last_pinch_distance = current_dist
