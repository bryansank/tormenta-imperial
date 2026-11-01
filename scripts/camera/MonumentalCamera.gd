extends Camera3D
## RTS camera with perspective projection, orbiting around a ground target.
## Supports pan, zoom, and 360° rotation around the Y axis.
## Uses pivot pattern: _ground_target (XZ) + spherical offset (distance, pitch, yaw).
##
## Maqueta (arte, 2026-10-05, docs/21 §12): lente cerrada (fov 40) desde mas
## lejos y algo mas picada (52 grados). Con la lente cerrada la perspectiva se
## aplana y la isla se lee como un diorama visto desde arriba, no como una
## foto gran angular. Las distancias crecen en proporcion para encuadrar lo
## mismo que antes (fov 60 a 20 unidades ~ fov 40 a 32).
##
## Inicio de maqueta (V3, rediseno 2026-10-14): una partida nueva arranca mas
## cerca (default_distance) y, al acercarse, la camara se tumba un poco
## (pitch_near_angle): de cerca se ven los costados de los edificios, la
## maqueta, y no un plano. La inclinacion sale de la distancia, asi que no hay
## nada nuevo que guardar: de pitch_flat_distance para afuera la vista es la de
## siempre (pitch_angle), y una partida cargada vuelve a su distancia guardada.

@export var move_speed: float = 30.0
@export var zoom_speed: float = 3.0
@export var rotate_speed: float = 60.0
@export var rotate_step_degrees: float = 45.0  # degrees per rotate-button press
@export var rotate_lerp_speed: float = 10.0    # how fast yaw eases to its target
@export var min_distance: float = 12.0
@export var max_distance: float = 95.0
## Inclinacion de lejos (la de siempre): desde pitch_flat_distance hacia fuera.
@export var pitch_angle: float = -52.0
## Inclinacion en min_distance: mas tumbada, para ver la maqueta de lado.
@export var pitch_near_angle: float = -38.0
## A partir de esta distancia la inclinacion ya es pitch_angle.
@export var pitch_flat_distance: float = 32.0
@export var lens_fov: float = 40.0
## Distancia con la que arranca una partida nueva (y la de una partida sin
## camara guardada). Mas cerca que antes (32): se ve el Nucleo y su calle.
@export var default_distance: float = 24.0

@export var boundary_min: Vector2 = Vector2(-40, -40)
@export var boundary_max: Vector2 = Vector2(40, 40)

var _ground_target: Vector2 = Vector2.ZERO
var _yaw: float = 0.0
var _target_yaw: float = 0.0
var _distance: float = 24.0
var _target_distance: float = 24.0

func _ready() -> void:
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = lens_fov
	near = 0.3
	far = 400.0
	_distance = default_distance
	_target_distance = default_distance
	EventBus.camera_pan_requested.connect(_on_pan)
	EventBus.camera_zoom_requested.connect(_on_zoom)
	EventBus.camera_drag_moved.connect(_on_drag)
	EventBus.camera_drag_world_requested.connect(_on_drag_world)
	EventBus.camera_rotate_requested.connect(_on_rotate)
	EventBus.camera_rotate_step_requested.connect(_on_rotate_step)
	EventBus.grid_resized.connect(_on_grid_resized)
	fit_to_grid()
	_update_transform()

## Los limites del paneo: el rectangulo de la tierra (con la isla cuadrada, la
## rejilla entera) mas GameConfig.camera_bounds_margin_cells. Desde la beta 0.9
## no se limita solo el centro de la vista sino lo que se ve
## (_clamp_to_boundaries): con la camara inclinada y alejada, el centro en la
## orilla dejaba media pantalla de mar abierto (QA tablet real, 2026-10-26).
func fit_to_grid() -> void:
	var land: Rect2 = GridManager.land_world_rect()
	var margin: float = GameConfig.camera_bounds_margin_cells * GridManager.cell_size
	land = land.grow(margin)
	boundary_min = land.position
	boundary_max = land.end

func _on_grid_resized(_w: int, _h: int) -> void:
	fit_to_grid()
	_clamp_to_boundaries()

func _process(delta: float) -> void:
	_distance = lerp(_distance, _target_distance, 8.0 * delta)
	_yaw = lerp(_yaw, _target_yaw, minf(1.0, rotate_lerp_speed * delta))
	_clamp_to_boundaries()
	_update_transform()

## La inclinacion para una distancia: pitch_near_angle en min_distance, que se
## endereza hasta pitch_angle en pitch_flat_distance y se queda ahi.
func pitch_for(distance: float) -> float:
	var span := maxf(0.001, pitch_flat_distance - min_distance)
	var t := clampf((pitch_flat_distance - distance) / span, 0.0, 1.0)
	return lerpf(pitch_angle, pitch_near_angle, t)

func _update_transform() -> void:
	var pitch_rad := deg_to_rad(pitch_for(_distance))
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

## World-space grab-pan: the delta is already in world XZ units (computed by the
## caller via ground raycasts), so the terrain point under the cursor stays glued
## to the cursor regardless of zoom or yaw.
func _on_drag_world(delta: Vector2) -> void:
	_ground_target += delta

func _on_rotate(amount: float) -> void:
	_target_yaw += amount * rotate_speed * get_process_delta_time()

func _on_rotate_step(degrees: float) -> void:
	_target_yaw += degrees

func get_state() -> Dictionary:
	return { "target_x": _ground_target.x, "target_y": _ground_target.y, "yaw": _yaw, "distance": _distance }

func set_state(data: Dictionary) -> void:
	_ground_target = Vector2(data.get("target_x", 0.0), data.get("target_y", 0.0))
	_yaw = data.get("yaw", 0.0)
	_target_yaw = _yaw
	_distance = clampf(float(data.get("distance", default_distance)), min_distance, max_distance)
	_target_distance = _distance
	_update_transform()

## Mantiene lo que se ve dentro de [boundary_min, boundary_max]: el borde de
## la vista (de lado, la fila del centro de la pantalla; de frente, la de
## arriba y la de abajo) llega como mucho al limite. Si la vista es mas grande
## que el limite en un eje (muy alejada), se centra en ese eje. Vale para
## teclado, arrastre, dedo y controles en pantalla: todos mueven
## _ground_target y aqui se recorta cada fotograma.
func _clamp_to_boundaries() -> void:
	var fp := view_footprint(_distance, pitch_for(_distance), _yaw, _aspect(), fov)
	_ground_target.x = clamp_axis(_ground_target.x, boundary_min.x, boundary_max.x, fp.position.x, fp.end.x)
	_ground_target.y = clamp_axis(_ground_target.y, boundary_min.y, boundary_max.y, fp.position.y, fp.end.y)

## Recorta `v` (el centro) para que [v + lo_off, v + hi_off] quede dentro de
## [lo, hi]; si no cabe, lo centra.
static func clamp_axis(v: float, lo: float, hi: float, lo_off: float, hi_off: float) -> float:
	var a := lo - lo_off
	var b := hi - hi_off
	if a > b:
		return (a + b) * 0.5
	return clampf(v, a, b)

## Lo que se ve en el suelo, relativo al objetivo, como caja en XZ (x, z):
## de frente, hasta donde llegan la fila de arriba y la de abajo de la
## pantalla; de lado, el ancho a la altura del centro (los rincones de arriba
## pueden asomar algo mas: la perspectiva abre la vista al fondo). Con el giro,
## la caja que contiene ese rectangulo girado.
static func view_footprint(distance: float, pitch_deg: float, yaw_deg: float, aspect: float, fov_deg: float = 40.0) -> Rect2:
	var pitch := deg_to_rad(absf(pitch_deg))
	var half := deg_to_rad(fov_deg) * 0.5
	var height := distance * sin(pitch)
	var back := distance * cos(pitch)
	# Fila de arriba: el rayo baja (pitch - half); se acota por si roza el horizonte.
	var top_angle := maxf(deg_to_rad(5.0), pitch - half)
	var bottom_angle := minf(deg_to_rad(89.0), pitch + half)
	var far := height / tan(top_angle) - back
	var near := back - height / tan(bottom_angle)
	var side := distance * tan(half) * maxf(0.1, aspect)
	var yaw := deg_to_rad(yaw_deg)
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var lat := Vector2(cos(yaw), -sin(yaw))
	var box := Rect2(fwd * far + lat * side, Vector2.ZERO)
	for p in [fwd * far - lat * side, -fwd * near + lat * side, -fwd * near - lat * side]:
		box = box.expand(p)
	return box

func _aspect() -> float:
	if not is_inside_tree():
		return 16.0 / 9.0
	var vp := get_viewport().get_visible_rect().size
	return vp.x / vp.y if vp.y > 0.0 else 16.0 / 9.0
