extends Node
## Ayudas de colocacion comunes a la vista 3D y a la 2D (docs/21 §Tactil):
##
## 1. **Colocar con el dedo.** Con el raton el fantasma sigue al cursor y el clic
##    planta. Con el dedo no hay cursor que seguir (el raton emulado se queda
##    donde fue el ultimo toque), asi que:
##    - **tocar el mapa** lleva el fantasma a esa casilla, centrado bajo el dedo,
##      verde o rojo. Si es rojo, se dice por que en el acto;
##    - **arrastrar el fantasma** (apoyar el dedo encima) lo mueve con el dedo; en
##      cualquier otro sitio arrastrar sigue moviendo el mapa;
##    - **tocar el fantasma** o el boton **✓ CONSTRUIR AQUI** que flota sobre el
##      lo planta. Tocar donde ya esta es confirmar.
##    Se eligio asi, y no "planta al levantar el dedo", porque un toque en un
##    tactil no se ve antes de comprometerse: primero se ve verde, luego se paga.
##    Y el arrastre de un dedo sigue siendo del mapa, que es lo que el jugador
##    hace el 90 % del tiempo (bug 8).
## 2. **La regla del yacimiento se ve antes.** Al empezar a colocar un extractor
##    (aserradero, mina, fundicion, refineria) se resaltan en verde las casillas
##    donde cabe junto a su yacimiento, y si ninguna esta en pantalla la camara va
##    a la mas cercana. En tactil el fantasma ya sale ahi.
## 3. Cierra la columna ☰ al empezar a colocar: tapaba la derecha del mapa.
##
## El colocador (BuildingPlacer o BuildingPlacer2D) crea este nodo como hijo y
## responde a los metodos `assist_*` (ver cada llamada). Las reglas no viven
## aqui: el veredicto es PlacementRules.evaluate_placement, el mismo del clic.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")
## Casillas validas: verde palido, que se lea sobre la hierba (verde oscuro).
const SPOT_COLOR := Color(0.78, 1.0, 0.55)

## Dedo que se esta siguiendo, -1 si ninguno.
var _finger := -1
var _press_pos := Vector2.ZERO
## El dedo se apoyo sobre el fantasma: arrastrarlo lo mueve (y no panea).
var _grab := false
var _grab_offset := Vector2i.ZERO
var _moved := false
## El fantasma lo esta apuntando el dedo, no el raton. Lo apaga un movimiento de
## raton de verdad (no emulado).
var touch_aim := false
## Casilla (origen) del fantasma cuando lo apunta el dedo.
var cell := Vector2i(-1, -1)
## Origenes validos para el edificio en curso (solo extractores; [] si no hay regla).
var spots: Array = []
var _sidebar_open := false
## ✓ se pulso hace menos de esto: el toque que sigue es el mismo dedo.
const CONFIRM_SWALLOW_MS := 250
var _confirm_press_ms := -100000
var _swallow_finger := -1

var _placer: Node = null
var _layer: CanvasLayer = null
var _confirm: Button = null

func setup(placer: Node) -> void:
	_placer = placer
	EventBus.sidebar_toggled.connect(func(v: bool): _sidebar_open = v)

func _ready() -> void:
	_build_confirm()

# ── Empezar y terminar ────────────────────────────────────────────────

## El colocador acaba de entrar en PLACING o MOVING con su fantasma creado.
func begin() -> void:
	_finger = -1
	_grab = false
	touch_aim = _touch_mode()
	if _sidebar_open:
		EventBus.sidebar_toggled.emit(false)
	refresh_spots()
	var centre := _screen_centre_cell()
	var target := nearest_spot(centre) if not spots.is_empty() else centre_origin(centre)
	if not spots.is_empty() and not _spot_on_screen():
		_placer.assist_center_on(target)
	if touch_aim:
		move_to(target, false)
	_update_confirm()

func end() -> void:
	_finger = -1
	_grab = false
	spots = []
	cell = Vector2i(-1, -1)
	if _placer:
		_placer.assist_show_cells([])
	_update_confirm()

## Recalcula las casillas validas (tras colocar, girar o demoler) y las pinta.
func refresh_spots() -> void:
	spots = valid_spots(_placer.assist_building_id(), _placer.assist_ghost_size(),
		_placer.assist_map_generator(), _placer.assist_moving_node())
	_placer.assist_show_cells(spot_cells(spots, _placer.assist_ghost_size()))

func _touch_mode() -> bool:
	return GameConfig.touch_controls_enabled() or GameConfig.real_touch_seen()

# ── Entrada ───────────────────────────────────────────────────────────

## El colocador pasa aqui cada evento de _input mientras coloca. Solo mira si
## el raton de verdad ha vuelto (entonces manda el cursor otra vez).
func notice_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if touch_aim:
			touch_aim = false
			_update_confirm()

## Toques y arrastres que llegan al mapa (_unhandled_input: la interfaz ya se
## quedo los suyos). Devuelve true si el evento era del colocador: el colocador
## lo marca como manejado y InputService no lo ve.
func handle_touch(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		# El dedo que acaba de pulsar ✓: el raton emulado llega antes que el toque,
		# el boton planta y se esconde, y el toque en si cae al mapa. Sin esto ese
		# mismo dedo movia el fantasma a la casilla de debajo del boton.
		if Time.get_ticks_msec() - _confirm_press_ms < CONFIRM_SWALLOW_MS or _swallow_finger == st.index:
			if st.pressed:
				_swallow_finger = st.index
			else:
				_swallow_finger = -1
			_confirm_press_ms = -100000
			return true
		if st.pressed:
			return _on_press(st)
		return _on_release(st)
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index != _finger or not _grab:
			return false
		if not _moved and sd.position.distance_to(_press_pos) < InputService.touch_slop_px():
			return true
		_moved = true
		move_to(_placer.assist_screen_to_cell(sd.position) - _grab_offset, false)
		return true
	return false

func _on_press(st: InputEventScreenTouch) -> bool:
	touch_aim = true
	if _finger != -1:
		# Segundo dedo: pellizco o giro. Se suelta el fantasma donde este.
		_finger = -1
		_grab = false
		return false
	_finger = st.index
	_press_pos = st.position
	_moved = false
	var c: Vector2i = _placer.assist_screen_to_cell(st.position)
	_grab = _in_ghost(c)
	if _grab:
		_grab_offset = c - cell
		# Por si InputService lo vio antes que nosotros: ese dedo no panea.
		InputService.forget_touch(st.index)
		return true
	return false

func _on_release(st: InputEventScreenTouch) -> bool:
	if st.index != _finger and st.index >= 0:
		return false
	_finger = -1
	# Un gesto que corta el sistema (llamada, app en segundo plano) no es un
	# toque: ni planta ni mueve. InputService lo purga por su lado.
	if st.canceled or st.index < 0:
		_grab = false
		return false
	if _grab:
		_grab = false
		if not _moved:
			# Un toque sobre el fantasma: confirmar.
			confirm()
		elif not is_valid(cell):
			_placer.assist_explain(cell)
		_update_confirm()
		return true
	# Un arrastre del mapa no es un toque.
	if InputService.touch_pan_consumed_click() or st.position.distance_to(_press_pos) >= InputService.touch_slop_px():
		return false
	# La casilla es la de apoyar el dedo, no la de levantarlo: el temblor al
	# soltar no cambia a donde se apunto.
	# Se devuelve false a proposito: InputService tiene que ver este soltar para
	# olvidar el dedo, o el toque siguiente contaria como segundo dedo.
	var tapped: Vector2i = _placer.assist_screen_to_cell(_press_pos)
	if not GridManager.is_valid_cell(tapped):
		EventBus.notification_posted.emit(Tr.t("LBL_OUTSIDE_MAP"), "info", UITheme.INFO)
		_placer.assist_feedback(Tr.t("LBL_OUTSIDE_MAP"))
		return false
	move_to(snap(tapped), true)
	return false

# ── Fantasma ──────────────────────────────────────────────────────────

## Lleva el fantasma a `origin`. Con `explain`, si no vale se dice por que.
func move_to(origin: Vector2i, explain: bool) -> void:
	cell = origin
	touch_aim = true
	_placer.assist_move_ghost(origin)
	if explain and not is_valid(origin):
		_placer.assist_explain(origin)
	_update_confirm()

func confirm() -> void:
	if not GridManager.is_valid_cell(cell):
		return
	_placer.assist_confirm(cell)
	if _placer.assist_is_placing():
		refresh_spots()
	_update_confirm()

func is_valid(origin: Vector2i) -> bool:
	if not GridManager.is_valid_cell(origin):
		return false
	return bool(Rules.evaluate_placement(_placer.assist_building_id(), origin,
		_placer.assist_ghost_size(), _placer.assist_map_generator(), _placer.assist_moving_node())["ok"])

func _in_ghost(c: Vector2i) -> bool:
	if not touch_aim or not GridManager.is_valid_cell(cell):
		return false
	var size: Vector2i = _placer.assist_ghost_size()
	return c.x >= cell.x and c.y >= cell.y and c.x < cell.x + size.x and c.y < cell.y + size.y

## Origen que deja la casilla `c` en el centro de la huella.
func centre_origin(c: Vector2i) -> Vector2i:
	var size: Vector2i = _placer.assist_ghost_size()
	return c - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)

## Donde acaba un toque en `c`: centrado bajo el dedo si ahi vale; si no, el
## hueco valido mas cercano cuya huella cubra el dedo (tocar la franja verde
## siempre da un fantasma verde); si tampoco, centrado (y saldra rojo).
func snap(c: Vector2i) -> Vector2i:
	var centred := centre_origin(c)
	if spots.is_empty() or is_valid(centred):
		return centred
	var size: Vector2i = _placer.assist_ghost_size()
	var best := centred
	var best_d := INF
	for o in spots:
		var origin: Vector2i = o
		if c.x < origin.x or c.y < origin.y or c.x >= origin.x + size.x or c.y >= origin.y + size.y:
			continue
		var d := Vector2(origin - centred).length_squared()
		if d < best_d:
			best_d = d
			best = origin
	return best

func nearest_spot(c: Vector2i) -> Vector2i:
	var best: Vector2i = spots[0]
	var best_d := INF
	for o in spots:
		var d := Vector2((o as Vector2i) - c).length_squared()
		if d < best_d:
			best_d = d
			best = o
	return best

func _screen_centre_cell() -> Vector2i:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	var c: Vector2i = _placer.assist_screen_to_cell(vp * 0.5)
	if not GridManager.is_valid_cell(c):
		c = Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	return c

func _spot_on_screen() -> bool:
	if not is_inside_tree():
		return true
	var rect := get_viewport().get_visible_rect().grow(-40.0)
	var size: Vector2i = _placer.assist_ghost_size()
	for o in spots:
		var p: Variant = _placer.assist_cell_to_screen(o, size)
		if p != null and rect.has_point(p):
			return true
	return false

# ── Reglas (puras) ────────────────────────────────────────────────────

## Origenes donde `building_id` con huella `size` pasa el veredicto junto a su
## yacimiento. [] si el edificio no tiene regla de yacimiento.
static func valid_spots(building_id: String, size: Vector2i, map_gen: Node, ignore: Node = null) -> Array:
	var rule: Dictionary = GameConfig.get_deposit_rule(building_id)
	if rule.is_empty() or map_gen == null or not map_gen.has_method("get_all_deposits"):
		return []
	var reach := int(rule["reach"])
	var seen := {}
	var out: Array = []
	for dep in map_gen.get_all_deposits():
		if String(dep["id"]) != String(rule["deposit"]):
			continue
		var dx := int(dep["cell_x"])
		var dy := int(dep["cell_y"])
		var dw := int(dep.get("size_x", 2))
		var dh := int(dep.get("size_y", 2))
		for ox in range(dx - size.x - reach + 1, dx + dw + reach):
			for oy in range(dy - size.y - reach + 1, dy + dh + reach):
				var origin := Vector2i(ox, oy)
				if seen.has(origin) or not GridManager.is_valid_cell(origin):
					continue
				seen[origin] = true
				if Rules.evaluate_placement(building_id, origin, size, map_gen, ignore)["ok"]:
					out.append(origin)
	return out

## Casillas cubiertas por alguna huella valida: lo que se pinta de verde.
static func spot_cells(origins: Array, size: Vector2i) -> Array:
	var seen := {}
	for o in origins:
		for c in GridManager.cells_for(o, size):
			seen[c] = true
	return seen.keys()

## Linea "Necesita ..." de un edificio para su ficha, o "" si construye donde sea.
static func rule_text(building_id: String) -> String:
	var rule: Dictionary = GameConfig.get_deposit_rule(building_id)
	if rule.is_empty():
		return ""
	return Tr.t("LBL_RULE_" + String(rule["deposit"]).to_upper())

# ── Boton ✓ ───────────────────────────────────────────────────────────

func _build_confirm() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "PlacementConfirm"
	_layer.layer = 11
	add_child(_layer)
	_confirm = Button.new()
	_confirm.name = "ConfirmPlacement"
	_confirm.custom_minimum_size = Vector2(UITheme.touch_px(56.0), UITheme.touch_px(52.0))
	UITheme.style_button(_confirm, UITheme.POSITIVE.darkened(0.1), UITheme.FONT_BODY)
	_confirm.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_confirm.pressed.connect(func():
		_confirm_press_ms = Time.get_ticks_msec()
		confirm())
	_confirm.visible = false
	_layer.add_child(_confirm)

func confirm_button() -> Button:
	return _confirm

func _update_confirm() -> void:
	if _confirm == null or _placer == null:
		return
	var show: bool = touch_aim and _placer.assist_is_placing() and is_valid(cell)
	_confirm.text = "✓ " + Tr.t("BTN_MOVE_HERE" if _placer.assist_moving_node() != null else "BTN_PLACE_HERE")
	_confirm.visible = show
	if show:
		_position_confirm()

func _process(_delta: float) -> void:
	if _confirm != null and _confirm.visible:
		_position_confirm()

## Encima del fantasma, dentro de la pantalla. Si el fantasma se sale, abajo al
## centro (sigue estando a mano).
func _position_confirm() -> void:
	var vp := get_viewport().get_visible_rect().size
	_confirm.reset_size()
	var sz := _confirm.get_combined_minimum_size()
	var anchor: Variant = _placer.assist_ghost_top_screen(cell)
	var pos: Vector2
	if anchor == null:
		pos = Vector2(vp.x * 0.5 - sz.x * 0.5, vp.y - sz.y - 120.0)
	else:
		pos = (anchor as Vector2) - Vector2(sz.x * 0.5, sz.y + 10.0)
	pos.x = clampf(pos.x, 8.0, vp.x - sz.x - 8.0)
	pos.y = clampf(pos.y, 60.0, vp.y - sz.y - 8.0)
	_confirm.position = pos
