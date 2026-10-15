extends Node
## Arrastrar para desplazar, en cualquier lista, empiece donde empiece el dedo.
##
## Un ScrollContainer de Godot solo se desplaza arrastrando sobre su hueco: una
## tarjeta o un boton encima se quedan el gesto y la lista no se mueve (la de
## CONSTRUIR, entera de tarjetas, no se podia arrastrar). Este nodo va de hijo
## de cada ScrollContainer (UIManager lo engancha solo, a todos) y mira la
## entrada ANTES que la interfaz:
##
##   - pulsar dentro de la lista solo toma nota; los botones siguen recibiendo
##     su pulsacion;
##   - moverse mas de DRAG_THRESHOLD px la convierte en arrastre: la lista se
##     desplaza con el dedo y el gesto ya no es un toque;
##   - al empezar a arrastrar, el control de debajo recibe un "soltar" lejos de
##     el (fuera de todo control): no se dispara y no se queda hundido; el
##     soltar de verdad, al acabar, ya no le llega;
##   - la rueda del raton desplaza la lista y nunca llega a un regulador o a un
##     desplegable de dentro.
##
## Solo actua la lista mas interior bajo el puntero que de verdad pueda
## desplazarse: una lista que cabe entera deja pasar todo.
##
## Mientras dura el arrastre, el contenido de la lista no recibe raton
## (mouse_behavior_recursive): los botones por los que pasa el dedo no se
## pulsan, no se activan ni se quedan resaltados. Al soltar se devuelve.
## El control bajo el dedo se busca por posicion (TouchTooltip.control_at)
## cuando el "hover" del motor no esta ahi: con el dedo no hay movimiento antes
## de tocar y el hover es el del toque anterior, asi que la lista no tomaba el
## gesto y el boton de debajo se quedaba con todo.

const DRAG_THRESHOLD := 10.0
const WHEEL_STEP := 64.0
## Donde se manda el "soltar" de un arrastre: fuera de cualquier control.
const FAR_AWAY := Vector2(-100000, -100000)

const TouchTooltipScript := preload("res://scripts/ui/TouchTooltip.gd")

var _scroll: ScrollContainer
## Contenido apagado durante el arrastre: control -> su mouse_behavior_recursive.
var _muted: Dictionary = {}
var _press_pos := Vector2.INF
var _start_scroll := Vector2i.ZERO
var _dragging := false
## Mientras se manda el soltar-fuera de _cancel_press, este nodo no lo mira.
var _cancelling := false

func _ready() -> void:
	name = "DragScroll"
	_scroll = get_parent() as ScrollContainer

func is_dragging() -> bool:
	return _dragging

## Cuanto se puede desplazar en vertical / horizontal (0 si cabe entera).
func _room() -> Vector2:
	var v := _scroll.get_v_scroll_bar()
	var h := _scroll.get_h_scroll_bar()
	var ry := 0.0
	var rx := 0.0
	if _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and v != null:
		ry = maxf(0.0, v.max_value - v.page)
	if _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and h != null:
		rx = maxf(0.0, h.max_value - h.page)
	return Vector2(rx, ry)

func can_scroll() -> bool:
	var r := _room()
	return r.x > 0.5 or r.y > 0.5

## Esta lista es la que manda bajo el puntero: esta a la vista, el control
## sobre el que esta el puntero es suyo, y ninguna lista mas interior que pueda
## desplazarse lo reclama antes.
func _owns_pointer(pos: Vector2 = Vector2.INF) -> bool:
	if _scroll == null or not _scroll.is_visible_in_tree():
		return false
	# Fuera de la lista no hay nada que decidir (y asi la busqueda de abajo
	# solo la hacen las listas que estan bajo el dedo).
	if pos != Vector2.INF and not _scroll.get_global_rect().has_point(pos):
		return false
	var hovered := get_viewport().gui_get_hovered_control()
	# Con el dedo el hover es el del toque anterior (no hay movimiento antes de
	# tocar): si no cae donde se toca, se busca el control de verdad.
	if pos != Vector2.INF and (hovered == null or not hovered.get_global_rect().has_point(pos)):
		var hit := _control_at(pos)
		if hit != null:
			hovered = hit
	if hovered == null:
		# Sin control bajo el puntero conocido (el motor aun no lo calculo, o sin
		# ventana): basta con que el punto caiga dentro de la lista.
		return pos != Vector2.INF and _scroll.get_global_rect().has_point(pos)
	if not (hovered == _scroll or _scroll.is_ancestor_of(hovered)):
		return false
	var n: Node = hovered
	while n != null and n != _scroll:
		if n is ScrollContainer:
			var inner := n.get_node_or_null("DragScroll")
			if inner != null and inner.can_scroll():
				return false
		n = n.get_parent()
	return true

func _input(event: InputEvent) -> void:
	if _scroll == null:
		return
	if event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenDrag and _dragging:
		# El arrastre ya lo lleva este nodo con el raton emulado: que el scroll
		# no lo desplace otra vez por su cuenta con el evento tactil.
		get_viewport().set_input_as_handled()

func _on_button(e: InputEventMouseButton) -> void:
	if e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if _room().y > 0.5 and _owns_pointer(e.position):
			var dir := -1.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			_scroll.scroll_vertical += int(dir * WHEEL_STEP * maxf(e.factor, 1.0))
			get_viewport().set_input_as_handled()
		return
	if e.button_index != MOUSE_BUTTON_LEFT:
		return
	if e.pressed:
		# Un arrastre anterior cuyo soltar no llego (ventana que pierde el foco).
		_unmute()
		_dragging = false
		_press_pos = Vector2.INF
		if can_scroll() and _owns_pointer(e.position):
			_press_pos = e.position
			_start_scroll = Vector2i(_scroll.scroll_horizontal, _scroll.scroll_vertical)
		return
	# Soltar
	if _cancelling:
		return
	if _dragging:
		# El boton de debajo ya recibio su soltar-fuera al empezar el arrastre
		# (_cancel_press): este soltar de verdad no le llega.
		get_viewport().set_input_as_handled()
	_unmute()
	_dragging = false
	_press_pos = Vector2.INF

func _on_motion(e: InputEventMouseMotion) -> void:
	if _cancelling:
		return
	if _press_pos == Vector2.INF or (e.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		return
	var delta: Vector2 = e.position - _press_pos
	if not _dragging and delta.length() < DRAG_THRESHOLD:
		return
	if not _dragging:
		_dragging = true
		_cancel_press()
		_mute()
	var room := _room()
	if room.y > 0.5:
		_scroll.scroll_vertical = _start_scroll.y - int(delta.y)
	if room.x > 0.5:
		_scroll.scroll_horizontal = _start_scroll.x - int(delta.x)
	get_viewport().set_input_as_handled()

## Engancha un DragScroll a `scroll` si aun no lo tiene.
## Sin tipo: llega diferido, y el scroll pudo liberarse entre medias.
static func attach(scroll) -> void:
	if not is_instance_valid(scroll) or not (scroll is ScrollContainer) or scroll.has_node("DragScroll") \
			or scroll.has_meta("no_drag_scroll"):
		return
	var ds: Node = (load("res://scripts/ui/DragScroll.gd") as GDScript).new()
	ds.name = "DragScroll"
	scroll.add_child(ds, false, Node.INTERNAL_MODE_BACK)

## El control bajo `pos`, buscado una vez por fotograma y punto aunque haya
## varias listas anidadas preguntando (recorre las capas de la interfaz).
static var _hit_frame := -1
static var _hit_pos := Vector2.INF
static var _hit: Control = null
func _control_at(pos: Vector2) -> Control:
	var frame := Engine.get_process_frames()
	if frame != _hit_frame or pos != _hit_pos or (_hit != null and not is_instance_valid(_hit)):
		_hit_frame = frame
		_hit_pos = pos
		_hit = TouchTooltipScript.control_at(get_tree(), pos)
	return _hit

## Apaga el raton en el contenido de la lista mientras se arrastra: nada de
## dentro se pulsa, se activa ni se resalta al pasar el dedo por encima.
func _mute() -> void:
	for c in _scroll.get_children():
		if c is Control and "mouse_behavior_recursive" in c and not _muted.has(c):
			_muted[c] = c.get("mouse_behavior_recursive")
			c.set("mouse_behavior_recursive", Control.MOUSE_BEHAVIOR_DISABLED)

func _unmute() -> void:
	for c in _muted:
		if is_instance_valid(c):
			c.set("mouse_behavior_recursive", _muted[c])
	_muted.clear()

func _exit_tree() -> void:
	_unmute()

func _notification(what: int) -> void:
	# Si la ventana pierde el foco a mitad de arrastre, el soltar no llega.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _dragging:
		_unmute()
		_dragging = false
		_press_pos = Vector2.INF

## Le dice a la interfaz que el boton se solto FUERA de todo control: el boton
## que recibio la pulsacion la da por cancelada y no se queda hundido.
func _cancel_press() -> void:
	# Primero el puntero se va lejos (el boton mira si sigue encima con los
	# movimientos, y esos se los queda el arrastre); luego se suelta alli.
	var m := InputEventMouseMotion.new()
	m.position = FAR_AWAY
	m.global_position = FAR_AWAY
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_LEFT
	r.pressed = false
	r.position = FAR_AWAY
	r.global_position = FAR_AWAY
	_cancelling = true
	get_viewport().push_input(m)
	get_viewport().push_input(r)
	_cancelling = false
