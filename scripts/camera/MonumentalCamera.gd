extends Camera3D
## RTS camera with perspective projection, orbiting around a ground target.
## Supports pan, zoom, and 360° rotation around the Y axis.
## Uses pivot pattern: _ground_target (XZ) + spherical offset (distance, pitch, yaw).

@export var move_speed: float = 30.0
@export var zoom_speed: float = 2.0
@export var rotate_speed: float = 60.0
@export var min_distance: float = 8.0
@export var max_distance: float = 40.0
@export var pitch_angle: float = -45.0

@export var boundary_min: Vector2 = Vector2(-25, -25)
@export var boundary_max: Vector2 = Vector2(25, 25)

var _ground_target: Vector2 = Vector2.ZERO
var _yaw: float = 0.0
var _distance: float = 20.0
var _target_distance: float = 20.0

func _ready() -> void:
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = 60.0
	near = 0.1
	far = 200.0
	EventBus.camera_pan_requested.connect(_on_pan)
	EventBus.camera_zoom_requested.connect(_on_zoom)
	EventBus.camera_drag_moved.connect(_on_drag)
	EventBus.camera_rotate_requested.connect(_on_rotate)
	_update_transform()

func _process(delta: float) -> void:
	_distance = lerp(_distance, _target_distance, 8.0 * delta)
	_clamp_to_boundaries()
	_update_transform()

func _update_transform() -> void:
	var pitch_rad := deg_to_rad(pitch_angle)
	var yaw_rad := deg_to_rad(_yaw)

	# Spherical to cartesian offset from ground target
	var offset := Vector3(
		_distance * cos(pitch_rad) * sin(yaw_rad),
		-_distance * sin(pitch_rad),
		_distance * cos(pitch_rad) * cos(yaw_rad)
	)

	var target_3d := Vector3(_ground_target.x, 0.0, _ground_target.y)
	global_position = target_3d + offset
	look_at(target_3d, Vector3.UP)

func _on_pan(direction: Vector2) -> void:
	# Pan relative to camera yaw so W always moves "forward" on screen
	var yaw_rad := deg_to_rad(_yaw)
	var forward := Vector2(sin(yaw_rad), cos(yaw_rad))
	var right := Vector2(cos(yaw_rad), -sin(yaw_rad))
	var move := (forward * direction.y + right * direction.x) * move_speed * get_process_delta_time()
	_ground_target += move

func _on_zoom(amount: float) -> void:
	_target_distance = clampf(_target_distance + amount * zoom_speed, min_distance, max_distance)

func _on_drag(delta: Vector2) -> void:
	var yaw_rad := deg_to_rad(_yaw)
	var forward := Vector2(sin(yaw_rad), cos(yaw_rad))
	var right := Vector2(cos(yaw_rad), -sin(yaw_rad))
	_ground_target += forward * delta.y + right * -delta.x

func _on_rotate(amount: float) -> void:
	_yaw += amount * rotate_speed * get_process_delta_time()

func get_state() -> Dictionary:
	return { "target_x": _ground_target.x, "target_y": _ground_target.y, "yaw": _yaw, "distance": _distance }

func set_state(data: Dictionary) -> void:
	_ground_target = Vector2(data.get("target_x", 0.0), data.get("target_y", 0.0))
	_yaw = data.get("yaw", 0.0)
	_distance = data.get("distance", 20.0)
	_target_distance = _distance
	_update_transform()

func _clamp_to_boundaries() -> void:
	_ground_target.x = clampf(_ground_target.x, boundary_min.x, boundary_max.x)
	_ground_target.y = clampf(_ground_target.y, boundary_min.y, boundary_max.y)
