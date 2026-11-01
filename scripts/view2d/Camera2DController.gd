extends Camera2D
## Camara de la vista 2D: mapa visto desde arriba, sin giro.
##
## Escucha las mismas senales de EventBus que MonumentalCamera (teclado, rueda,
## pellizco, arrastre con el dedo o el raton) y guarda el mismo estado:
## {target_x, target_y, yaw, distance} en unidades de mundo. Una partida guardada
## en 3D abre en 2D mirando al mismo sitio y al reves. El giro no existe en 2D:
## el que traiga la partida se conserva tal cual para devolverselo a la 3D.

const View2D := preload("res://scripts/view2d/View2D.gd")

## Los mismos limites que MonumentalCamera, en su unidad (distancia de camara).
@export var move_speed: float = 30.0
@export var zoom_speed: float = 3.0
@export var min_distance: float = 12.0
@export var max_distance: float = 95.0
@export var boundary_min: Vector2 = Vector2(-40, -40)
@export var boundary_max: Vector2 = Vector2(40, 40)

## Objetivo en unidades de mundo (X, Z), como la 3D.
var _target := Vector2.ZERO
var _distance := 32.0
var _target_distance := 32.0
var _yaw := 0.0

func _ready() -> void:
	make_current()
	EventBus.camera_pan_requested.connect(_on_pan)
	EventBus.camera_zoom_requested.connect(_on_zoom)
	EventBus.camera_drag_moved.connect(_on_drag)
	EventBus.camera_drag_world_requested.connect(_on_drag_world)
	GameManager.register_camera(self)
	EventBus.grid_resized.connect(_on_grid_resized)
	fit_to_grid()
	_apply()

## Los limites del paneo: la tierra (con la isla cuadrada, la rejilla entera)
## mas GameConfig.camera_bounds_margin_cells, como la 3D. Desde la beta 0.9 se
## limita lo que se ve, no solo el centro (_clamp).
func fit_to_grid() -> void:
	var land: Rect2 = GridManager.land_world_rect()
	land = land.grow(GameConfig.camera_bounds_margin_cells * GridManager.cell_size)
	boundary_min = land.position
	boundary_max = land.end

func _on_grid_resized(_w: int, _h: int) -> void:
	fit_to_grid()
	_clamp()

func _process(delta: float) -> void:
	_distance = lerpf(_distance, _target_distance, minf(1.0, 8.0 * delta))
	_clamp()
	_apply()

func _apply() -> void:
	position = _target * View2D.PX_PER_UNIT
	var z := View2D.distance_to_zoom(_distance) * screen_boost() / ui_scale()
	zoom = Vector2(z, z)

## La escala de interfaz (content_scale_factor, DeviceProfile) agranda el lienzo
## entero, mapa 2D incluido. La camara la descuenta: la escala es de la
## interfaz, no un zoom del mapa. La 3D no la necesita (canvas_items no escala
## el 3D).
func ui_scale() -> float:
	if not is_inside_tree():
		return 1.0
	return maxf(0.01, get_tree().root.content_scale_factor)

## En una pantalla estrecha (movil) el lienzo logico de 1280 se encoge a unos
## 400 px fisicos y las celdas quedarian diminutas. Se acerca la camara en
## proporcion (amortiguada) para que una celda siga siendo tocable con el dedo.
## En escritorio vale 1.
func screen_boost() -> float:
	if not is_inside_tree():
		return 1.0
	var phys := float(DisplayServer.window_get_size().x) if DisplayServer.get_name() != "headless" else 0.0
	# El lienzo sin la escala de interfaz: esa ya la descuenta ui_scale().
	var logical := get_viewport().get_visible_rect().size.x / ui_scale()
	if phys <= 0.0 or logical <= phys:
		return 1.0
	return pow(logical / phys, 0.75)

## El borde de la pantalla llega como mucho al limite; si la vista es mas
## grande que el limite en un eje, se centra en ese eje. El zoom es el que va a
## tener la camara con _distance (no el de ahora): asi no tiembla al alejarse.
func _clamp() -> void:
	var half := view_half_extent()
	_target.x = clamp_axis(_target.x, boundary_min.x, boundary_max.x, half.x)
	_target.y = clamp_axis(_target.y, boundary_min.y, boundary_max.y, half.y)

## Media vista en unidades de mundo (x, z).
func view_half_extent() -> Vector2:
	if not is_inside_tree():
		return Vector2.ZERO
	var z := View2D.distance_to_zoom(_distance) * screen_boost() / ui_scale()
	if z <= 0.0:
		return Vector2.ZERO
	return get_viewport().get_visible_rect().size * 0.5 / z / View2D.PX_PER_UNIT

static func clamp_axis(v: float, lo: float, hi: float, half: float) -> float:
	var a := lo + half
	var b := hi - half
	if a > b:
		return (a + b) * 0.5
	return clampf(v, a, b)

# ── Senales ───────────────────────────────────────────────────────────

func _on_pan(direction: Vector2) -> void:
	# W sube por la pantalla (hacia -Z), como la 3D con giro cero. Mas lejos, mas rapido.
	_target += direction * move_speed * get_process_delta_time() * (_distance / 20.0) / screen_boost()

func _on_zoom(amount: float) -> void:
	_target_distance = clampf(_target_distance + amount * zoom_speed, min_distance, max_distance)

## Arrastre con el boton central: InputService manda relative * sensibilidad.
## En 2D se agarra el mapa: el punto bajo el cursor se queda bajo el cursor.
func _on_drag(delta: Vector2) -> void:
	var sens: float = InputService.mouse_drag_sensitivity if InputService.mouse_drag_sensitivity > 0.0 else 0.05
	var relative_px := delta / sens
	_target -= relative_px / zoom.x / View2D.PX_PER_UNIT

## Arrastre con el dedo o el boton izquierdo: el delta ya viene en unidades de
## mundo (View2D.screen_drag_to_world_delta), el mismo contrato que la 3D.
func _on_drag_world(delta: Vector2) -> void:
	_target += delta
	_clamp()
	_apply()

# ── Estado (mismo formato que MonumentalCamera) ───────────────────────

func get_state() -> Dictionary:
	return { "target_x": _target.x, "target_y": _target.y, "yaw": _yaw, "distance": _distance }

func set_state(data: Dictionary) -> void:
	_target = Vector2(float(data.get("target_x", 0.0)), float(data.get("target_y", 0.0)))
	_yaw = float(data.get("yaw", 0.0))
	_distance = clampf(float(data.get("distance", 32.0)), min_distance, max_distance)
	_target_distance = _distance
	_clamp()
	_apply()

## Centra la camara en un punto del mundo (herramientas y tests).
func look_at_world(target: Vector2, distance: float = -1.0) -> void:
	_target = target
	if distance > 0.0:
		_distance = clampf(distance, min_distance, max_distance)
		_target_distance = _distance
	_clamp()
	_apply()
