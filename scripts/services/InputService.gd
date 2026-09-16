extends Node
## Unified input service: abstracts keyboard, mouse, and touch into EventBus signals.
## Supports: WASD/Arrows (pan), scroll wheel (zoom), middle-mouse drag (pan),
## right-mouse drag (rotate), single-finger grab-pan, two-finger pinch (zoom).
##
## El dedo y el raton mueven el mapa con la misma cuenta: `screen_drag_to_world_delta`
## proyecta los dos puntos del arrastre sobre el suelo y devuelve el hueco en
## unidades de mundo, asi que el trozo de terreno que hay bajo el dedo (o bajo el
## cursor) se queda pegado a el sin importar el zoom ni el giro de la camara.
## BuildingPlacer llama a esa misma funcion para el arrastre con el boton
## izquierdo: hay un solo camino, no dos parecidos.

@export var mouse_drag_sensitivity: float = 0.05
@export var mouse_rotate_sensitivity: float = 0.3

var _is_mouse_dragging: bool = false
var _is_mouse_rotating: bool = false

## Dedos vivos cuyo apoyo llego hasta aqui (es decir, que empezaron sobre el mapa
## y no sobre un panel): indice -> ultima posicion conocida.
var _touch_points: Dictionary = {}
## Dedo que manda el paneo, -1 si ninguno. Solo panea un dedo a la vez.
var _pan_finger: int = -1
var _pan_start_pos: Vector2 = Vector2.ZERO
var _pan_last_pos: Vector2 = Vector2.ZERO
## El dedo ya paso el umbral: desde aqui arrastra el mapa y deja de ser un clic.
var _touch_panning: bool = false
## El gesto tactil en curso (o el ultimo) llego a arrastrar. Sobrevive a levantar
## el dedo porque el clic emulado que Godot fabrica al soltar llega despues.
var _touch_pan_consumed_click: bool = false
var _last_pinch_distance: float = 0.0

func _ready() -> void:
	# Ensure mouse cursor is always visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(_delta: float) -> void:
	_handle_keyboard()

## F11 alterna pantalla completa desde cualquier parte del juego. Va en _input
## (no en _unhandled_input) para que siga funcionando con un panel abierto.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F11:
			GameConfig.toggle_fullscreen()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	# Skip mouse/touch input when hovering over UI elements
	if _is_mouse_over_ui():
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			return
		# Un dedo que se apoya encima de un panel es de la interfaz, no del mapa:
		# ni se registra ni, por tanto, sus arrastres mueven la camara.
		if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			return

	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)

func _is_mouse_over_ui() -> bool:
	var viewport := get_viewport()
	if not viewport:
		return false
	return viewport.gui_get_hovered_control() != null

# ── Keyboard ──

func _handle_keyboard() -> void:
	# Don't process camera keys when a text field has focus
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return

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

	# Q/E rotation
	if Input.is_key_pressed(KEY_Q):
		EventBus.camera_rotate_requested.emit(-1.0)
	if Input.is_key_pressed(KEY_E):
		EventBus.camera_rotate_requested.emit(1.0)

# ── Mouse ──

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			EventBus.camera_zoom_requested.emit(-1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			EventBus.camera_zoom_requested.emit(1.0)
		MOUSE_BUTTON_MIDDLE:
			_is_mouse_dragging = event.pressed
		MOUSE_BUTTON_RIGHT:
			_is_mouse_rotating = event.pressed

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_mouse_dragging:
		EventBus.camera_drag_moved.emit(event.relative * mouse_drag_sensitivity)
	elif _is_mouse_rotating:
		EventBus.camera_rotate_requested.emit(event.relative.x * mouse_rotate_sensitivity)

# ── Touch ──

## Hay al menos un dedo apoyado sobre el mapa.
func is_touch_gesture_active() -> bool:
	return not _touch_points.is_empty()

## El dedo ya esta arrastrando el mapa (paso el umbral).
func is_touch_panning() -> bool:
	return _touch_panning

## El gesto tactil actual acabo siendo un arrastre, asi que el clic emulado que
## Godot fabrica al levantar el dedo no debe seleccionar ni colocar nada. Se
## limpia cuando empieza el gesto siguiente.
func touch_pan_consumed_click() -> bool:
	return _touch_pan_consumed_click

func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_points[event.index] = event.position
		if _touch_points.size() == 1:
			_touch_pan_consumed_click = false
			_begin_pan_finger(event.index, event.position)
		else:
			# Aparece el segundo dedo: el arrastre de uno se corta en seco y toma
			# el mando el pellizco. Si no, el zoom arranca dando un tiron al mapa.
			_cancel_touch_pan()
			_arm_pinch()
		return

	_touch_points.erase(event.index)
	if event.index == _pan_finger:
		_cancel_touch_pan()
	if _touch_points.size() >= 2:
		_arm_pinch()
	elif _touch_points.size() == 1:
		# Se levanta uno de los dos dedos del pellizco: el que queda vuelve a
		# empezar desde donde esta y tiene que pasar otra vez el umbral, para que
		# el mapa no pegue el salto de todo lo que se movio pellizcando.
		var remaining: int = _touch_points.keys()[0]
		_begin_pan_finger(remaining, _touch_points[remaining])
		_last_pinch_distance = 0.0
	else:
		_last_pinch_distance = 0.0

func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	# Un dedo cuyo apoyo nunca paso por aqui empezo sobre la interfaz: el Control
	# se quedo el toque, y el mapa no se entera de este arrastre.
	if not _touch_points.has(event.index):
		return
	_touch_points[event.index] = event.position

	if _touch_points.size() >= 2:
		_handle_pinch()
		return
	if event.index != _pan_finger:
		return
	if not _touch_panning:
		if event.position.distance_to(_pan_start_pos) < GameConfig.touch_drag_threshold_px:
			return
		_touch_panning = true
		_touch_pan_consumed_click = true
	# Como el raton: el primer paneo arrastra desde donde se apoyo el dedo, asi
	# que los pixeles del umbral no se pierden y el terreno no da un respingo.
	var from_pos := _pan_last_pos
	_pan_last_pos = event.position
	_emit_grab_pan(from_pos, event.position)

func _begin_pan_finger(index: int, pos: Vector2) -> void:
	_pan_finger = index
	_pan_start_pos = pos
	_pan_last_pos = pos
	_touch_panning = false

func _cancel_touch_pan() -> void:
	_pan_finger = -1
	_touch_panning = false

func _arm_pinch() -> void:
	var points := _touch_points.values()
	if points.size() < 2:
		return
	_last_pinch_distance = (points[0] as Vector2).distance_to(points[1] as Vector2)

func _handle_pinch() -> void:
	var points := _touch_points.values()
	if points.size() < 2:
		return
	var current_dist := (points[0] as Vector2).distance_to(points[1] as Vector2)
	if _last_pinch_distance <= 0.0:
		_last_pinch_distance = current_dist
		return
	var diff := current_dist - _last_pinch_distance
	if absf(diff) > GameConfig.pinch_zoom_dead_zone_px:
		EventBus.camera_zoom_requested.emit(-diff * GameConfig.pinch_zoom_sensitivity)
		_last_pinch_distance = current_dist

func _emit_grab_pan(from_pos: Vector2, to_pos: Vector2) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var world_delta = screen_drag_to_world_delta(viewport.get_camera_3d(), from_pos, to_pos)
	if world_delta == null:
		return
	EventBus.camera_drag_world_requested.emit(world_delta)

# ── Grab-pan compartido (raton y dedo) ──

## Cuanto hay que mover el objetivo de la camara (en unidades de mundo XZ) para
## que el punto del suelo que estaba bajo `from_pos` acabe bajo `to_pos`.
## Proyecta ambos puntos de pantalla sobre el plano Y=0, de modo que el mismo
## recorrido en pixeles mueve mas mundo cuanto mas lejos esta la camara: es lo
## que hace que agarrar el terreno se sienta igual con el dedo que con el raton.
## Devuelve null si no hay camara o si el rayo no corta el suelo (mirando al cielo).
static func screen_drag_to_world_delta(camera: Camera3D, from_pos: Vector2, to_pos: Vector2) -> Variant:
	var from_hit = raycast_to_ground(camera, from_pos)
	var to_hit = raycast_to_ground(camera, to_pos)
	if from_hit == null or to_hit == null:
		return null
	var a := from_hit as Vector3
	var b := to_hit as Vector3
	return Vector2(a.x - b.x, a.z - b.z)

## Punto del plano del suelo (Y=0) bajo una posicion de pantalla, o null.
static func raycast_to_ground(camera: Camera3D, screen_pos: Vector2) -> Variant:
	if camera == null or not camera.is_inside_tree():
		return null
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.001:
		return null
	var t := -from.y / dir.y
	if t < 0:
		return null
	return from + dir * t
