extends CanvasLayer
## "Mantener pulsado para leer": el tooltip de cualquier Control, con el dedo.
##
## Godot no ensena tooltips al tocar, y mucho texto vive ya en tooltips (rama
## feat/menos-texto). Con el estilo de entrada tactil (DeviceProfile.input_style)
## este nodo mira cada dedo ANTES que la interfaz:
##
##   - apoyar un dedo sobre un Control con tooltip arma el gesto; nada mas: el
##     boton recibe su pulsacion como siempre;
##   - si el dedo sigue quieto GameConfig.touch_tooltip_hold_sec (0,5 s), sale
##     una burbuja con el texto del tooltip encima del dedo, dentro de la
##     pantalla, y el boton recibe un "soltar" lejos de el (como DragScroll):
##     no se dispara y no se queda hundido. El soltar de verdad ya no le llega;
##   - un toque corto no ve nada de esto: pulsa;
##   - moverse mas que el umbral de toque (InputService.touch_slop_px), un
##     segundo dedo o un soltar-lejos de DragScroll cancelan el gesto;
##   - levantar el dedo cierra la burbuja; otro dedo, tambien.
##
## Los botones que actuan al tocar (ACTION_MODE_BUTTON_PRESS: la cruceta, el
## zoom y el giro de OnScreenControls, que repiten al mantener) no arman el
## gesto: ya hicieron su trabajo y mantenerlos es repetir, no leer.
##
## Con raton (PC) no hace nada: ahi siguen los tooltips de Godot. Vive como hijo
## de InputService (autoload), asi que sobrevive a las recargas de escena, y
## corre tambien en pausa (el menu ☰ pausa el arbol).

const LAYER := 50
## Ancho maximo de la burbuja, en pixeles del lienzo.
const MAX_WIDTH := 360.0
## Margen con los bordes de la pantalla.
const EDGE := 8.0
## Hueco entre la yema del dedo y la burbuja: que el dedo no la tape.
const FINGER_GAP := 56.0
## Donde se manda el "soltar" que cancela la pulsacion: fuera de todo control.
const FAR_AWAY := Vector2(-100000, -100000)

var _bubble: PanelContainer
var _label: Label

## Dedos apoyados: indice -> posicion.
var _touches: Dictionary = {}
## Hay un gesto armado (un dedo quieto sobre un control con tooltip).
var _pending := false
var _held := 0.0
var _start := Vector2.ZERO
var _target: Control = null
## La burbuja esta a la vista (el dedo sigue puesto).
var _shown := false
## El soltar de verdad del raton emulado no debe llegar al boton.
var _eat_release := false
## Mientras se manda el soltar-lejos, este nodo no lo mira.
var _cancelling := false

func _ready() -> void:
	name = "TouchTooltip"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bubble = PanelContainer.new()
	_bubble.name = "TouchTooltipBubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.visible = false
	add_child(_bubble)
	_label = Label.new()
	_label.name = "TouchTooltipText"
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(_label)

# ── Estado (para pruebas y para quien quiera saberlo) ─────────────────

## El gesto esta activo: estilo de entrada tactil.
func active() -> bool:
	var dp := get_node_or_null("/root/DeviceProfile")
	return dp != null and dp.has_method("input_style") and dp.input_style() == "touch"

func is_shown() -> bool:
	return _shown

func is_pending() -> bool:
	return _pending

func bubble() -> PanelContainer:
	return _bubble

func bubble_text() -> String:
	return _label.text if _shown else ""

# ── Entrada ───────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _cancelling:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag((event as InputEventScreenDrag).position)
	elif event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_on_drag(mm.position)

func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = e.position
		if _touches.size() == 1 and not _shown:
			_arm(e.position)
		else:
			# Dos dedos nunca son "leer": pellizco, giro, o tocar fuera.
			_pending = false
			_hide()
		return
	# Un soltar sin dedo (index -1) o cancelado los levanta todos.
	if e.index < 0 or e.canceled:
		_touches.clear()
	else:
		_touches.erase(e.index)
	_pending = false
	if _touches.is_empty():
		# El soltar emulado llega antes que este: si no llego (gesto cortado por
		# el sistema), que no se coma el siguiente.
		_eat_release = false
		_hide()

func _on_drag(pos: Vector2) -> void:
	if _pending and pos.distance_to(_start) > _slop():
		_pending = false

func _on_mouse_button(e: InputEventMouseButton) -> void:
	if e.button_index != MOUSE_BUTTON_LEFT or e.pressed:
		return
	if _eat_release:
		# El soltar del raton emulado al levantar el dedo: el boton ya recibio
		# el suyo, lejos, al salir la burbuja.
		_eat_release = false
		get_viewport().set_input_as_handled()
		_hide()
		return
	# Un soltar que no es el del dedo (el soltar-lejos de DragScroll al empezar
	# a arrastrar una lista): el gesto ya no es un toque quieto.
	_pending = false

func _arm(pos: Vector2) -> void:
	_pending = false
	_held = 0.0
	_start = pos
	_target = null
	if not active():
		return
	var hit := control_at(get_tree(), pos, self)
	if hit == null or acts_on_press(hit):
		return
	var owner_ctrl := tooltip_owner(hit, pos)
	if owner_ctrl == null:
		return
	_target = owner_ctrl
	_pending = true

## El umbral de "se ha movido", el mismo que separa toque de arrastre en el mapa.
func _slop() -> float:
	var input := get_node_or_null("/root/InputService")
	if input != null and input.has_method("touch_slop_px"):
		return float(input.touch_slop_px())
	return 10.0

# ── Tiempo ────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	tick(delta)

## Avanza el reloj del gesto. Publico para las pruebas.
func tick(delta: float) -> void:
	if not _pending:
		return
	_held += delta
	if _held >= GameConfig.touch_tooltip_hold_sec:
		_fire()

func _fire() -> void:
	_pending = false
	if _target == null or not is_instance_valid(_target) or not _target.is_visible_in_tree():
		return
	var text := _tooltip_of(_target, _start)
	if text == "":
		return
	_cancel_press()
	show_bubble(text, _start)

## Le dice a la interfaz que el boton se solto FUERA de todo control (como
## DragScroll._cancel_press): no se dispara y no se queda hundido.
func _cancel_press() -> void:
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
	get_viewport().push_input(m, true)
	get_viewport().push_input(r, true)
	_cancelling = false
	_eat_release = true

# ── Burbuja ───────────────────────────────────────────────────────────

## Ensena `text` encima de `finger` (pixeles del lienzo), dentro de la pantalla.
func show_bubble(text: String, finger: Vector2) -> void:
	if UITheme.is_cartoon():
		# Estilo maqueta: el bocadillo de las ventanas (sigue al tema claro u
		# oscuro) con su texto; antes salia tinta sobre la ficha oscura del HUD.
		var st := CartoonTheme.bubble_style()
		st.set_content_margin_all(10)
		_bubble.add_theme_stylebox_override("panel", st)
		CartoonTheme.style_label(_label, "body", CartoonTheme.text("window"))
	else:
		_bubble.add_theme_stylebox_override("panel", UITheme.make_hud_card_style(UITheme.ACCENT, 2))
		UITheme.apply_text_style(_label, "body", UITheme.TEXT_BRIGHT)
	_label.text = text
	var vp := get_viewport().get_visible_rect().size
	var max_w := minf(MAX_WIDTH, vp.x - EDGE * 2.0)
	var font: Font = _label.get_theme_font("font")
	var fs: int = _label.get_theme_font_size("font_size")
	var natural := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font != null else max_w
	_label.custom_minimum_size = Vector2(minf(ceilf(natural) + 2.0, max_w - 20.0), 0)
	_bubble.reset_size()
	_bubble.visible = true
	_shown = true
	_place(finger)
	# El alto de un texto con ajuste de linea se sabe al ordenar el contenedor.
	_place.call_deferred(finger)

func _place(finger: Vector2) -> void:
	if not _shown:
		return
	_bubble.reset_size()
	var size := _bubble.get_combined_minimum_size()
	_bubble.size = size
	_bubble.position = bubble_position(size, finger, get_viewport().get_visible_rect().size)

## Donde va una burbuja de `size` para un dedo en `finger`, en un lienzo de
## `vp`: centrada sobre el dedo y encima; si no cabe encima, debajo; nunca
## fuera de la pantalla. Pura, para las pruebas.
static func bubble_position(size: Vector2, finger: Vector2, vp: Vector2) -> Vector2:
	var x := clampf(finger.x - size.x / 2.0, EDGE, maxf(EDGE, vp.x - size.x - EDGE))
	var y := finger.y - FINGER_GAP - size.y
	if y < EDGE:
		y = finger.y + FINGER_GAP
	y = clampf(y, EDGE, maxf(EDGE, vp.y - size.y - EDGE))
	return Vector2(x, y)

func _hide() -> void:
	_shown = false
	if _bubble != null:
		_bubble.visible = false

# ── Buscar el control bajo el dedo ────────────────────────────────────

## El Control que recibiria un toque en `pos` (pixeles del lienzo): el de mas
## arriba (capa mas alta, ultimo hijo), visible, que no sea IGNORE y que no
## este recortado por un ScrollContainer. Lo mismo que hace la interfaz, sin
## depender de que el raton emulado haya pasado ya por ahi. `skip`: una capa
## que no cuenta (la propia burbuja).
static func control_at(tree: SceneTree, pos: Vector2, skip: Node = null) -> Control:
	if tree == null:
		return null
	var layers: Array = []
	var order := 0
	for n in tree.root.find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		if cl == skip or not cl.visible:
			continue
		layers.append({"node": cl, "layer": cl.layer, "order": order})
		order += 1
	# El lienzo de la raiz (Controls fuera de toda CanvasLayer) es la capa 0.
	layers.append({"node": tree.root, "layer": 0, "order": -1})
	layers.sort_custom(func(a, b):
		if a["layer"] != b["layer"]:
			return a["layer"] > b["layer"]
		return a["order"] > b["order"])
	for entry in layers:
		var holder: Node = entry["node"]
		var local := pos
		if holder is CanvasLayer:
			local = (holder as CanvasLayer).transform.affine_inverse() * pos
		var hit := _hit_children(holder, local)
		if hit != null:
			return hit
	return null

static func _hit_children(node: Node, pos: Vector2) -> Control:
	var children := node.get_children()
	for i in range(children.size() - 1, -1, -1):
		var child: Node = children[i]
		# Otra capa se mira por su cuenta; un Window es otro lienzo.
		if child is CanvasLayer or child is Window:
			continue
		var hit: Control = null
		if child is Control:
			hit = _hit_control(child as Control, pos)
		elif not (child is Node2D or child is Node3D):
			hit = _hit_children(child, pos)
		if hit != null:
			return hit
	return null

static func _hit_control(c: Control, pos: Vector2) -> Control:
	if not c.visible:
		return null
	var inside := c.get_global_rect().has_point(pos)
	if c.clip_contents and not inside:
		return null
	var hit := _hit_children(c, pos)
	if hit != null:
		return hit
	if inside and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return c
	return null

## El control cuyo tooltip se lee: el tocado o, si no tiene, el primer padre
## que lo tenga (como el tooltip del raton). null si nadie lo tiene.
static func tooltip_owner(hit: Control, pos: Vector2) -> Control:
	var c := hit
	while c != null:
		if _tooltip_of(c, pos) != "":
			return c
		c = c.get_parent_control()
	return null

static func _tooltip_of(c: Control, pos: Vector2) -> String:
	var local := c.get_global_transform().affine_inverse() * pos
	return String(c.get_tooltip(local)).strip_edges()

## Un boton que hace lo suyo al tocar (y repite al mantener): no se lee.
static func acts_on_press(c: Control) -> bool:
	return c is BaseButton and (c as BaseButton).action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS
