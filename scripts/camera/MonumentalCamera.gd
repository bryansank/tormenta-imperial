extends Camera3D
## God-mode RTS camera with orthographic projection at 45 degrees.
## Reacts to EventBus signals emitted by InputService — no direct input handling.

@export var move_speed: float = 15.0
@export var zoom_speed: float = 2.0
@export var min_zoom: float = 5.0
@export var max_zoom: float = 50.0

# Map boundaries (world units)
@export var boundary_min: Vector2 = Vector2(-50, -50)
@export var boundary_max: Vector2 = Vector2(50, 50)

var _target_zoom: float

func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = 20.0
	_target_zoom = size
	EventBus.camera_pan_requested.connect(_on_pan)
	EventBus.camera_zoom_requested.connect(_on_zoom)
	EventBus.camera_drag_moved.connect(_on_drag)

func _process(delta: float) -> void:
	# Smooth zoom interpolation
	size = lerp(size, _target_zoom, 8.0 * delta)
	_clamp_to_boundaries()

func _on_pan(direction: Vector2) -> void:
	# Move along world XZ plane (camera faces at 45 degrees)
	var move := Vector3(direction.x, 0, direction.y) * move_speed * get_process_delta_time()
	global_position += move

func _on_zoom(amount: float) -> void:
	_target_zoom = clampf(_target_zoom + amount * zoom_speed, min_zoom, max_zoom)

func _on_drag(delta: Vector2) -> void:
	global_position += Vector3(-delta.x, 0, -delta.y)

func _clamp_to_boundaries() -> void:
	global_position.x = clampf(global_position.x, boundary_min.x, boundary_max.x)
	global_position.z = clampf(global_position.z, boundary_min.y, boundary_max.y)
