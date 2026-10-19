extends Node
## Arrastrar para desplazar, en cualquier lista, empiece donde empiece el dedo.
##
## Un ScrollContainer de Godot solo se desplaza arrastrando sobre su hueco: una
## tarjeta, un boton o un deslizador encima se quedan el gesto. Este nodo va de
## hijo de cada ScrollContainer (UIManager lo engancha solo, a todos) y mira la
## entrada ANTES que la interfaz. Decide que es el gesto antes de dejar que lo
## vea nadie (como las listas de un movil):
##
##   - pulsar dentro de una lista que se puede desplazar NO llega todavia al
##     control de debajo: se apunta y se espera;
##   - soltar sin haberse movido mas que el umbral (touch_slop_px, en dp: el
##     mismo que separa toque de arrastre en el mapa) es un TOQUE: se le manda
##     al control la pulsacion y el soltar, en su sitio, y pulsa como siempre;
##   - moverse mas que el umbral es un DESPLAZAMIENTO: la lista sigue al dedo y
##     el control de debajo no se entera de nada (ni pulsa, ni se hunde, ni un
##     deslizador cambia, ni un selector elige); "mantener pulsado"
##     (TouchTooltip) se cancela;
##   - excepcion: si el gesto empieza SOBRE la bolita o el carril de un
##     deslizador y el primer movimiento va a lo largo de el (horizontal en un
##     HSlider), es del deslizador: se le manda la pulsacion y el movimiento y
##     desde ahi todo le llega a el. Vertical sobre un HSlider desplaza la lista;
##   - la rueda del raton desplaza la lista y nunca llega a un regulador o a un
##     desplegable de dentro;
##   - la barra de desplazamiento propia de la lista va como siempre.
##
## Con listas anidadas, el desplazamiento se lo queda la lista mas interior que
## pueda moverse en la direccion del gesto (una tira horizontal dentro de una
## lista vertical no bloquea arrastrar en vertical). Una lista que cabe entera
## decide igual (un arrastre no pulsa, ni mueve un deslizador en vertical: que
## la pantalla sea grande no cambia el gesto), solo que no se mueve.
##
## Los botones de Godot 4.7 atienden tambien el TOQUE (InputEventScreenTouch),
## no solo el raton emulado: retener el raton no basta. Al empezar a arrastrar
## se le cancela el toque al control que lo tiene (touch_cancel_events): si no,
## al levantar el dedo se disparaba, porque la lista se mueve con el dedo y el
## dedo sigue encima del mismo boton ("se pulsa el boton al desplazar").
##
## El gesto es uno solo para todas las listas (estado estatico): el primer
## DragScroll que ve la pulsacion lo lleva y los demas lo respetan. El control
## bajo el dedo se busca por posicion (TouchTooltip.control_at): con el dedo no
## hay movimiento antes de tocar y el "hover" del motor es el del toque anterior.

const WHEEL_STEP := 64.0
## Umbral si no hay InputService (pruebas sueltas): pixeles del lienzo.
const FALLBACK_THRESHOLD := 10.0
## Holgura alrededor de la bolita/carril de un deslizador, en pixeles.
const SLIDER_BAND_PAD := 6.0
## Donde se manda el soltar que cancela un toque: fuera de cualquier control.
const FAR_AWAY := Vector2(-100000, -100000)

const TouchTooltipScript := preload("res://scripts/ui/TouchTooltip.gd")

enum Mode { NONE, PENDING, DRAGGING, SLIDER }

## El gesto en curso, compartido por todas las listas.
static var _mode: int = Mode.NONE
static var _press: InputEventMouseButton = null
static var _press_pos := Vector2.INF
## Las listas bajo el dedo que pueden desplazarse, de la mas interior afuera
## (nodos DragScroll).
static var _chain: Array = []
## El deslizador sobre cuya bolita/carril empezo el gesto (o null).
static var _slider: Slider = null
## La lista que se desplaza y su desplazamiento al empezar.
static var _owner_ds: Node = null
static var _start_scroll := Vector2i.ZERO
## Mientras se reenvian eventos a la interfaz, ningun DragScroll los mira.
static var _replaying := false
## El dedo (indice de InputEventScreenTouch) del gesto, si es un dedo: en Godot
## 4.7 los botones tambien atienden el toque, no solo el raton emulado.
static var _touch_index := -1
## Un dedo cuyo soltar de verdad ya no debe llegar a la interfaz (su pulsacion
## se le cancelo al empezar a arrastrar).
static var _eat_touch_release := -1
## Dedos apoyados ahora mismo: indice -> posicion (lienzo). El toque puede
## llegar antes o despues del raton emulado segun la plataforma.
static var _down_touches: Dictionary = {}
## Distancia maxima entre un dedo apoyado y la pulsacion emulada que es suya.
const TOUCH_MATCH_PX := 24.0

var _scroll: ScrollContainer
## Contenido apagado durante el arrastre: control -> su mouse_behavior_recursive.
var _muted: Dictionary = {}

func _ready() -> void:
	name = "DragScroll"
	_scroll = get_parent() as ScrollContainer

## Esta lista se esta arrastrando ahora mismo.
func is_dragging() -> bool:
	return _mode == Mode.DRAGGING and _owner_ds == self

## Hay un gesto de lista en curso (pendiente, arrastrando o de un deslizador).
static func gesture_mode() -> int:
	return _mode

## Olvida el gesto en curso sin mandar nada a nadie (TouchTooltip al ensenar
## su burbuja: el toque ya no es un toque).
static func cancel_gesture() -> void:
	if _owner_ds != null and is_instance_valid(_owner_ds):
		_owner_ds._unmute()
	_mode = Mode.NONE
	_press = null
	_press_pos = Vector2.INF
	_chain = []
	_slider = null
	_owner_ds = null
	_touch_index = -1

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

## La lista esta a la vista y `pos` cae dentro (se pueda mover o no).
func _usable_at(pos: Vector2) -> bool:
	return _scroll != null and _scroll.is_visible_in_tree() \
		and _scroll.get_global_rect().has_point(pos)

## El umbral de "se ha movido", en pixeles del lienzo (dp escalados por dpi).
func _threshold() -> float:
	var input := get_node_or_null("/root/InputService")
	if input != null and input.has_method("touch_slop_px"):
		return float(input.touch_slop_px())
	return FALLBACK_THRESHOLD

## Las listas (sus DragScroll) bajo `pos`, de la mas interior afuera, segun el control que de verdad recibiria el toque. Vacia si
## el punto no es de ninguna lista, o cae en una barra de desplazamiento.
func _chain_at(pos: Vector2) -> Array:
	var hit := _control_at(pos)
	if hit == null or not (hit == _scroll or _scroll.is_ancestor_of(hit)):
		return []
	var out: Array = []
	var n: Node = hit
	while n != null:
		if n is ScrollBar:
			return []
		if n is ScrollContainer:
			var ds: Node = n.get_node_or_null("DragScroll")
			if ds != null and ds.has_method("_usable_at") and ds._usable_at(pos):
				out.append(ds)
		n = n.get_parent()
	return out

## El deslizador bajo `pos` si el punto cae sobre su bolita o su carril (no en
## el margen de alrededor), o null.
func _slider_at(pos: Vector2) -> Slider:
	var n: Node = _control_at(pos)
	while n != null and n != _scroll:
		if n is Slider:
			var sl := n as Slider
			return sl if on_slider_track(sl, pos) else null
		n = n.get_parent()
	return null

## `pos` (lienzo) cae sobre la bolita o el carril de `sl`: a lo largo, en todo
## el control; a lo ancho, en la franja de la bolita (o del carril, si es mas
## gruesa) con una pequena holgura.
static func on_slider_track(sl: Slider, pos: Vector2) -> bool:
	var rect := sl.get_global_rect()
	if not rect.has_point(pos):
		return false
	var grab: Texture2D = sl.get_theme_icon("grabber")
	var rail: StyleBox = sl.get_theme_stylebox("slider")
	var horizontal := sl is HSlider
	var thick := 0.0
	if grab != null:
		thick = grab.get_size().y if horizontal else grab.get_size().x
	if rail != null:
		var rm := rail.get_minimum_size()
		thick = maxf(thick, rm.y if horizontal else rm.x)
	if thick <= 0.0:
		return true
	var half := thick * 0.5 + SLIDER_BAND_PAD
	if horizontal:
		return absf(pos.y - rect.get_center().y) <= half
	return absf(pos.x - rect.get_center().x) <= half

func _input(event: InputEvent) -> void:
	if _scroll == null or _replaying:
		return
	if event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag and _mode == Mode.DRAGGING:
		# El arrastre ya lo lleva este nodo con el raton emulado: que la lista no
		# lo desplace otra vez por su cuenta con el evento tactil.
		get_viewport().set_input_as_handled()

func _on_button(e: InputEventMouseButton) -> void:
	if e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		_on_wheel(e)
		return
	if e.button_index != MOUSE_BUTTON_LEFT:
		return
	if e.pressed:
		_on_press(e)
	else:
		_on_release(e)

## El toque de verdad (en Godot 4.7 llega despues del raton emulado; se mira
## tambien al reves): se apunta su dedo para poder cancelarselo al boton si el
## gesto acaba siendo un arrastre.
func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_down_touches[e.index] = e.position
		if e.index == _eat_touch_release:
			_eat_touch_release = -1
		if _mode == Mode.PENDING and _touch_index < 0 \
				and e.position.distance_to(_press_pos) <= TOUCH_MATCH_PX:
			_touch_index = e.index
		return
	if e.index < 0 or e.canceled:
		_down_touches.clear()
	else:
		_down_touches.erase(e.index)
	if e.index == _eat_touch_release:
		_eat_touch_release = -1
		get_viewport().set_input_as_handled()

func _on_wheel(e: InputEventMouseButton) -> void:
	if not _usable_at(e.position) or _under_popup(e.position):
		return
	for ds in _chain_at(e.position):
		if ds._room().y > 0.5:
			var dir := -1.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			ds._scroll.scroll_vertical += int(dir * WHEEL_STEP * maxf(e.factor, 1.0))
			get_viewport().set_input_as_handled()
			return

func _on_press(e: InputEventMouseButton) -> void:
	# Una pulsacion nueva acaba con cualquier gesto anterior cuyo soltar no
	# llego (ventana que pierde el foco, lista cerrada a medias).
	if _mode != Mode.NONE:
		cancel_gesture()
	if not _usable_at(e.position) or _under_popup(e.position):
		return
	var chain := _chain_at(e.position)
	if chain.is_empty():
		return
	_mode = Mode.PENDING
	_press = e.duplicate() as InputEventMouseButton
	_press_pos = e.position
	_chain = chain
	_slider = _slider_at(e.position)
	_owner_ds = null
	# El toque de este dedo pudo llegar antes que el raton emulado.
	for idx in _down_touches:
		if (_down_touches[idx] as Vector2).distance_to(e.position) <= TOUCH_MATCH_PX:
			_touch_index = idx
			break
	# Nadie mas ve la pulsacion hasta saber si es toque, arrastre o deslizador.
	get_viewport().set_input_as_handled()

func _on_release(e: InputEventMouseButton) -> void:
	match _mode:
		Mode.PENDING:
			# Un soltar fuera de la pantalla no es un toque (el soltar-lejos de
			# TouchTooltip, o el raton que se suelta fuera de la ventana).
			var tap := get_viewport().get_visible_rect().has_point(e.position)
			var press := _press
			cancel_gesture()
			if tap and press != null:
				var release := e.duplicate() as InputEventMouseButton
				release.position = press.position
				release.global_position = press.global_position
				_replay([_hover_at(press), press, release])
				get_viewport().set_input_as_handled()
		Mode.DRAGGING:
			cancel_gesture()
			get_viewport().set_input_as_handled()
		Mode.SLIDER:
			# El deslizador tiene la pulsacion: su soltar es suyo.
			cancel_gesture()

func _on_motion(e: InputEventMouseMotion) -> void:
	if _mode == Mode.NONE or _mode == Mode.SLIDER:
		return
	if (e.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		# El soltar no llego: no queda gesto.
		cancel_gesture()
		return
	if absf(e.position.x) > 50000.0 or absf(e.position.y) > 50000.0:
		# El "irse lejos" de quien cancela su pulsacion: no es el dedo.
		return
	var delta: Vector2 = e.position - _press_pos
	if _mode == Mode.PENDING:
		if delta.length() < _threshold():
			get_viewport().set_input_as_handled()
			return
		_decide(e, delta)
		if _mode != Mode.DRAGGING:
			return
	_scroll_owner(delta)
	get_viewport().set_input_as_handled()

## El dedo ya se ha movido: o es del deslizador, o es desplazar la lista.
func _decide(e: InputEventMouseMotion, delta: Vector2) -> void:
	var horizontal := absf(delta.x) > absf(delta.y)
	_cancel_hold()
	if _slider != null and is_instance_valid(_slider) and _slider.is_visible_in_tree() \
			and _slider.editable and horizontal == (_slider is HSlider):
		var press := _press
		var motion := e.duplicate() as InputEventMouseMotion
		_chain = []
		_mode = Mode.SLIDER
		_replay([press, motion])
		get_viewport().set_input_as_handled()
		return
	# La lista mas interior que pueda moverse en la direccion del gesto; si
	# ninguna puede, la mas interior (el gesto es arrastre igual: no pulsa).
	var pick: Node = null
	for ds in _chain:
		if not is_instance_valid(ds):
			continue
		var r: Vector2 = ds._room()
		if (horizontal and r.x > 0.5) or (not horizontal and r.y > 0.5):
			pick = ds
			break
	if pick == null:
		for ds in _chain:
			if is_instance_valid(ds):
				pick = ds
				break
	if pick == null:
		cancel_gesture()
		return
	_cancel_touch_press()
	_mode = Mode.DRAGGING
	_owner_ds = pick
	_start_scroll = Vector2i(pick._scroll.scroll_horizontal, pick._scroll.scroll_vertical)
	pick._mute()

func _scroll_owner(delta: Vector2) -> void:
	if _owner_ds == null or not is_instance_valid(_owner_ds):
		cancel_gesture()
		return
	var sc: ScrollContainer = _owner_ds._scroll
	var room: Vector2 = _owner_ds._room()
	if room.y > 0.5:
		sc.scroll_vertical = _start_scroll.y - int(delta.y)
	if room.x > 0.5:
		sc.scroll_horizontal = _start_scroll.x - int(delta.x)

## El boton bajo el dedo recibio el TOQUE (en Godot 4.7 BaseButton atiende
## InputEventScreenTouch, no solo el raton emulado, que aqui se retuvo): al
## levantar el dedo se dispararia, porque la lista se mueve con el dedo y este
## sigue encima del mismo boton. Se le cancela: el dedo "sale" lejos (un
## soltar a secas no basta: el boton se dispara donde sea que se suelte si el
## dedo no salio antes) y se suelta alli. El soltar de verdad de ese dedo ya no
## llega a la interfaz.
func _cancel_touch_press() -> void:
	if _touch_index < 0:
		return
	_replay(touch_cancel_events(_touch_index))
	_eat_touch_release = _touch_index

## Los eventos que le quitan un toque al control que lo tiene sin dispararlo:
## el dedo `index` se va lejos de todo control y se suelta alli, cancelado.
static func touch_cancel_events(index: int) -> Array:
	var d := InputEventScreenDrag.new()
	d.index = index
	d.position = FAR_AWAY
	var t := InputEventScreenTouch.new()
	t.index = index
	t.pressed = false
	t.canceled = true
	t.position = FAR_AWAY
	return [d, t]

## "Mantener pulsado para leer" no sigue si el dedo ya esta desplazando.
func _cancel_hold() -> void:
	var input := get_node_or_null("/root/InputService")
	if input == null or not input.has_method("touch_tooltip"):
		return
	var tt: Node = input.touch_tooltip()
	if tt != null and tt.has_method("cancel_hold"):
		tt.cancel_hold()

## Un movimiento sin boton al sitio de la pulsacion: que la interfaz sepa donde
## esta el puntero antes de recibirla (el hover de un toque es el del anterior).
func _hover_at(press: InputEventMouseButton) -> InputEventMouseMotion:
	var m := InputEventMouseMotion.new()
	m.device = press.device
	m.position = press.position
	m.global_position = press.global_position
	m.button_mask = 0
	return m

## Manda `events` (en pixeles del lienzo) a la interfaz sin que ningun
## DragScroll los mire otra vez.
func _replay(events: Array) -> void:
	var vp := get_viewport()
	_replaying = true
	for ev in events:
		if ev != null:
			vp.push_input(ev, true)
	_replaying = false

## Un desplegable (ventana incrustada) abierto encima del punto se queda el
## gesto entero.
func _under_popup(pos: Vector2) -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	for w in vp.get_embedded_subwindows():
		if w is Window and (w as Window).visible:
			var r := Rect2(Vector2((w as Window).position), Vector2((w as Window).size))
			if r.has_point(pos):
				return true
	return false

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
## dentro se activa ni se resalta al pasar el dedo por encima.
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
	if _owner_ds == self:
		cancel_gesture()

func _notification(what: int) -> void:
	# Si la ventana pierde el foco a mitad de gesto, el soltar no llega.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _mode != Mode.NONE:
		cancel_gesture()
