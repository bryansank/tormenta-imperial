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
##    donde cabe junto a su yacimiento; el fantasma tactil sale ya en la mas
##    cercana al centro, y si no queda comoda a la vista la camara va a ella.
## 3. Cierra la columna ☰ al empezar a colocar: tapaba la derecha del mapa.
## 4. **Carretera larga** (2026-10-19). Con la carretera en la mano:
##    - raton: mantener el clic y arrastrar dibuja el tramo de donde se pulso a
##      donde esta el cursor; al soltar se tiende. Un clic sin arrastrar pone un
##      solo tramo, como siempre;
##    - dedo: el primer toque fija el inicio (el fantasma); tocar otra casilla
##      dibuja el tramo hasta ella; tocar el final otra vez o ✓ lo tiende. El
##      final pasa a ser el inicio del siguiente (se encadenan calles). Tocar el
##      inicio vuelve a un solo tramo; arrastrar el fantasma mueve el inicio.
##      Arrastrar en otro sitio sigue moviendo el mapa;
##    - R o ↻ cambia el codo de la L.
##    La vista previa son casillas verdes (se pagan) o rojas (no valen o no
##    llega el oro) y un rotulo "N tramos · N oro". Las reglas y el coste son
##    PlacementRules.plan_road_line / lay_road_line, iguales en 3D y 2D.
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

# ── Carretera larga ──
## Inicio del tramo (raton: donde se pulso; dedo: el fantasma). (-1, -1) sin fijar.
var line_start := Vector2i(-1, -1)
## El plan en vista previa (PlacementRules.plan_road_line), {} si no hay tramo.
var line_plan: Dictionary = {}
## El codo de la L va por el otro eje (R o ↻).
var line_flip := false
## Un arrastre de raton esta dibujando un tramo.
var mouse_drawing := false
var _line_label: Label = null

func setup(placer: Node) -> void:
	_placer = placer
	EventBus.sidebar_toggled.connect(func(v: bool): _sidebar_open = v)

func _ready() -> void:
	_build_confirm()
	_build_line_label()
	# El ✓ crece con Ajustes → Controles → Tamano de los controles, como la cruceta.
	EventBus.touch_controls_size_changed.connect(func(_s): _size_confirm())

# ── Empezar y terminar ────────────────────────────────────────────────

## El colocador acaba de entrar en PLACING o MOVING con su fantasma creado.
func begin() -> void:
	_finger = -1
	_grab = false
	line_start = Vector2i(-1, -1)
	line_plan = {}
	line_flip = false
	mouse_drawing = false
	_show_line()
	touch_aim = _touch_mode()
	# El modo tactil puede haber cambiado desde que se construyo (touch_px).
	_size_confirm()
	# Empezar a colocar despeja el mapa: el MENÚ unico (#31) se cierra si estaba
	# abierto, y la columna lateral que quede (si alguna vista la usa) tambien.
	if _sidebar_open:
		EventBus.sidebar_toggled.emit(false)
	var menu: Node = get_tree().get_first_node_in_group("game_menu") if is_inside_tree() else null
	if menu != null and menu.has_method("is_open") and menu.is_open():
		menu.resume()
	refresh_spots()
	# La carretera larga se cuenta la primera vez que se coge la carretera, salvo
	# en plena guia (su paso de practicar ya dice que hacer).
	if is_road() and TutorialManager.guide_state != TutorialManager.GUIDE_ACTIVE:
		TutorialManager.offer_tip("road_drag")
	var centre := _screen_centre_cell()
	var target := nearest_spot(centre) if not spots.is_empty() else centre_origin(centre)
	# Si el hueco elegido no queda comodo a la vista (fuera, o pegado a un borde
	# donde viven los controles), la camara va a el.
	if not spots.is_empty() and not _comfortably_on_screen(target):
		_placer.assist_center_on(target)
	if touch_aim:
		move_to(target, false)
	_update_confirm()

func end() -> void:
	_finger = -1
	_grab = false
	spots = []
	cell = Vector2i(-1, -1)
	line_start = Vector2i(-1, -1)
	line_plan = {}
	mouse_drawing = false
	if _placer:
		_placer.assist_show_cells([])
		_show_line()
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
		# Con la carretera, arrastrar el fantasma mueve el inicio del tramo.
		if is_road():
			line_start = cell
			if line_active():
				var e: Vector2i = line_plan["end"]
				line_plan = {}
				line_to(e)
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
		if not _moved and is_road() and line_active():
			# Tocar el inicio con un tramo dibujado: vuelve a un solo tramo.
			line_clear()
		elif not _moved:
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
	if is_road() and _tap_road(tapped):
		return false
	move_to(snap(tapped), true)
	return false

## Un toque en el mapa con la carretera en la mano. Devuelve false si el toque
## sigue el camino de siempre (lleva el fantasma): el primero, que fija el
## inicio, o el que vuelve al inicio.
func _tap_road(tapped: Vector2i) -> bool:
	if not GridManager.is_valid_cell(line_start):
		line_start = tapped
		return false
	if tapped == line_start:
		line_plan = {}
		_show_line()
		return false
	if line_active() and tapped == line_plan["end"]:
		line_commit()
		return true
	line_to(tapped)
	if not bool(line_plan.get("ok", false)):
		_placer.assist_feedback(Rules.road_line_label(line_plan))
	return true

# ── Fantasma ──────────────────────────────────────────────────────────

## Lleva el fantasma a `origin`. Con `explain`, si no vale se dice por que.
func move_to(origin: Vector2i, explain: bool) -> void:
	cell = origin
	touch_aim = true
	_placer.assist_move_ghost(origin)
	if explain and not is_valid(origin):
		_placer.assist_explain(origin)
	elif explain and _placer.assist_moving_node() == null:
		# El sitio vale pero no llega para pagarlo: se dice ya, al apuntar, y no
		# solo al tocar el ✓ (2026-10-17).
		var data := Rules.load_building_data(_placer.assist_building_id())
		var block: String = Rules.purchase_block_detail(data) if data != null else ""
		if block != "":
			_placer.assist_feedback(block)
	_update_confirm()

func confirm() -> void:
	if is_road() and line_active():
		line_commit()
		return
	if not GridManager.is_valid_cell(cell):
		return
	_placer.assist_confirm(cell)
	# El siguiente tramo sale de este (calles en serie con el dedo).
	if is_road():
		line_start = cell
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

## `origin` cae en el centro de la pantalla: sin el 30 % de cada lado (ahi viven
## la barra de recursos, las ayudas, la cruceta y la columna de botones).
func _comfortably_on_screen(origin: Vector2i) -> bool:
	if not is_inside_tree():
		return true
	var vp := get_viewport().get_visible_rect()
	var rect := vp.grow_individual(-vp.size.x * 0.3, -vp.size.y * 0.3, -vp.size.x * 0.3, -vp.size.y * 0.3)
	var p: Variant = _placer.assist_cell_to_screen(origin, _placer.assist_ghost_size())
	return p != null and rect.has_point(p)

# ── Reglas (puras) ────────────────────────────────────────────────────

## Origenes donde `building_id` con huella `size` pasa el veredicto junto a su
## yacimiento. [] si el edificio no tiene regla de yacimiento.
static func valid_spots(building_id: String, size: Vector2i, map_gen: Node, ignore: Node = null) -> Array:
	if Rules.needs_shore(building_id):
		return shore_spots(building_id, size, map_gen, ignore)
	var rule: Dictionary = GameConfig.get_deposit_rule(building_id)
	if rule.is_empty() or map_gen == null or not map_gen.has_method("get_all_deposits"):
		return []
	var reach := int(rule["reach"])
	var seen := {}
	var out: Array = []
	# Cientos de veredictos seguidos sobre el mismo mapa: la red, el Nucleo y las
	# rutas salen de la cache de PlacementRules, y los sitios sin camino posible
	# se descartan sin un BFS por la rejilla libre cada uno (docs/26 §6.5).
	Rules.prepare_route_queries()
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

## Origenes validos de lo que solo va en la costa (las palmeras): las huellas
## que tocan una celda de tierra pegada al agua y pasan el veredicto. Se
## recorre la franja una vez (al empezar a colocar y tras cada colocada), no por
## frame.
static func shore_spots(building_id: String, size: Vector2i, map_gen: Node, ignore: Node = null) -> Array:
	var seen := {}
	var out: Array = []
	Rules.prepare_route_queries()
	for y in range(GridManager.grid_height):
		for x in range(GridManager.grid_width):
			var c := Vector2i(x, y)
			if not Rules.is_coast_cell(c):
				continue
			for ox in range(c.x - size.x + 1, c.x + 1):
				for oy in range(c.y - size.y + 1, c.y + 1):
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

## La regla del yacimiento de un edificio para su ficha, o "" si construye donde
## sea. Es la misma frase que da el colocador al fallar (la clave `message` de
## `GameConfig.building_deposit_rules`): una sola redaccion en la ficha, en el
## aviso al tocar y en el aviso con raton, para que nunca se contradigan.
static func rule_text(building_id: String) -> String:
	if Rules.needs_shore(building_id):
		return Tr.t("LBL_NEEDS_SHORE")
	var rule: Dictionary = GameConfig.get_deposit_rule(building_id)
	if rule.is_empty():
		return ""
	return Tr.t(String(rule.get("message", "LBL_REQUIRES_DEPOSIT")))

# ── Boton ✓ ───────────────────────────────────────────────────────────

func _build_confirm() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "PlacementConfirm"
	# Debajo de toda la interfaz que se abre (bug de Bryan, 2026-10-14): en la 16
	# se pintaba encima de los menus y paneles, que UIManager apila de la 12 hacia
	# arriba. En la 11 (la base de UIManager) queda por encima del mapa y de la
	# barra del HUD (10), y por debajo de cualquier ventana abierta, de los globos
	# de ayuda, del tutorial (19) y del menu de la partida (30). Con la misma capa
	# que algun panel suelto (11) dibuja antes que el, porque el colocador va antes
	# que la interfaz en la escena.
	_layer.layer = 11
	add_child(_layer)
	_confirm = Button.new()
	_confirm.name = "ConfirmPlacement"
	# El tutorial guiado lo busca para no taparlo con su tarjeta.
	_confirm.add_to_group("placement_confirm")
	UITheme.style_button(_confirm, UITheme.POSITIVE.darkened(0.1), UITheme.FONT_BODY)
	_size_confirm()
	_confirm.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_confirm.pressed.connect(func():
		_confirm_press_ms = Time.get_ticks_msec()
		confirm())
	_confirm.visible = false
	_layer.add_child(_confirm)

## Lado y letra del ✓: los de dedo (UITheme.touch_px) por la escala de los
## controles en pantalla que cabe en el lienzo (la misma que la cruceta).
func _size_confirm() -> void:
	if _confirm == null:
		return
	var lm := get_node_or_null("/root/UILayoutManager")
	var k: float = lm.touch_controls_scale() if lm != null else GameConfig.touch_controls_scale()
	_confirm.custom_minimum_size = Vector2(UITheme.touch_px(56.0), UITheme.touch_px(52.0)) * k
	_confirm.add_theme_font_size_override("font_size", roundi(float(UITheme.FONT_BODY) * k))
	if _confirm.visible:
		_position_confirm()

func confirm_button() -> Button:
	return _confirm

func _update_confirm() -> void:
	if _confirm == null or _placer == null:
		return
	var show: bool = touch_aim and _placer.assist_is_placing() and is_valid(cell)
	if line_active():
		show = touch_aim and _placer.assist_is_placing() and bool(line_plan["ok"]) and int(line_plan["affordable"]) > 0
	_confirm.text = "✓ " + Tr.t("BTN_MOVE_HERE" if _placer.assist_moving_node() != null else "BTN_PLACE_HERE")
	_confirm.visible = show
	if show:
		_position_confirm()

func _process(_delta: float) -> void:
	if _confirm != null and _confirm.visible:
		_position_confirm()
	if _line_label != null and _line_label.visible:
		_position_line_label()

## Encima del fantasma, dentro de la pantalla. Si el fantasma se sale, abajo al
## centro (sigue estando a mano).
func _position_confirm() -> void:
	var vp := get_viewport().get_visible_rect().size
	_confirm.reset_size()
	var sz := _confirm.get_combined_minimum_size()
	var anchor: Variant = _placer.assist_ghost_top_screen(cell)
	# Con un tramo dibujado, el ✓ va sobre su punta final.
	if line_active():
		var p: Variant = _placer.assist_cell_to_screen(line_plan["end"], Vector2i.ONE)
		anchor = null
		if p != null and get_viewport().get_visible_rect().has_point(p):
			anchor = (p as Vector2) - Vector2(0.0, 24.0)
	var pos: Vector2
	if anchor == null:
		pos = Vector2(vp.x * 0.5 - sz.x * 0.5, vp.y - sz.y - 120.0)
	else:
		pos = (anchor as Vector2) - Vector2(sz.x * 0.5, sz.y + 10.0)
	pos.x = clampf(pos.x, 8.0, vp.x - sz.x - 8.0)
	pos.y = clampf(pos.y, 60.0, vp.y - sz.y - 8.0)
	_confirm.position = pos

# ── Carretera larga ───────────────────────────────────────────────────

## Se esta colocando (no moviendo) una carretera.
func is_road() -> bool:
	return _placer != null and _placer.assist_moving_node() == null \
		and _placer.assist_building_id() == Rules.ROAD_ID

func line_active() -> bool:
	return not line_plan.is_empty()

## El raton se pulso en `c` con la carretera: empieza un posible arrastre.
func mouse_line_begin(c: Vector2i) -> void:
	mouse_drawing = true
	line_start = c
	line_plan = {}
	_show_line()

## El cursor esta en `c` con el boton pulsado. Solo se recalcula al cambiar de celda.
func mouse_line_move(c: Vector2i) -> void:
	if mouse_drawing:
		line_to(c)

## Se solto el boton. Devuelve true si habia un tramo (y se tendio); false si
## fue un clic sin arrastre (el colocador pone un solo tramo, como siempre).
func mouse_line_end() -> bool:
	if not mouse_drawing:
		return false
	mouse_drawing = false
	if not line_active():
		line_start = Vector2i(-1, -1)
		return false
	line_commit()
	line_start = Vector2i(-1, -1)
	return true

## Vista previa del tramo de line_start a `end`. No hace nada si `end` no cambio.
func line_to(end: Vector2i) -> void:
	if not GridManager.is_valid_cell(line_start):
		return
	if line_active() and line_plan["end"] == end:
		return
	if end == line_start:
		line_clear()
		return
	line_plan = Rules.plan_road_line(line_start, end, line_flip)
	_show_line()
	_update_confirm()

func line_clear() -> void:
	line_plan = {}
	_show_line()
	if touch_aim and GridManager.is_valid_cell(line_start):
		move_to(line_start, false)
	_update_confirm()

## R o ↻ con la carretera: el codo de la L va por el otro eje.
func line_flip_elbow() -> void:
	line_flip = not line_flip
	if line_active():
		var e: Vector2i = line_plan["end"]
		line_plan = {}
		line_to(e)

## Tiende el tramo en vista previa (con el mapa y el oro de ahora) y lo dice.
func line_commit() -> void:
	if not line_active():
		return
	var end: Vector2i = line_plan["end"]
	var result := Rules.lay_road_line(_placer, line_start, end, line_flip)
	var text := Rules.road_line_result_text(result)
	if text != "":
		_placer.assist_feedback(text)
	line_plan = {}
	if int(result["laid"]) > 0:
		# El final es el inicio del siguiente tramo (con el dedo).
		line_start = end
		_placer.assist_line_laid()
	_show_line()
	if touch_aim:
		move_to(line_start, false)
	_update_confirm()

func _show_line() -> void:
	if _placer == null:
		return
	if line_plan.is_empty():
		_placer.assist_show_line([], [])
		_placer.assist_set_ghost_visible(true)
		if _line_label != null:
			_line_label.visible = false
		return
	var good: Array = []
	var bad: Array = []
	if bool(line_plan["ok"]):
		var new: Array = line_plan["new"]
		var k := int(line_plan["affordable"])
		good = new.slice(0, k)
		bad = new.slice(k)
	else:
		bad = (line_plan["cells"] as Array).filter(func(c): return not Rules.is_road_at(c))
	_placer.assist_show_line(good, bad)
	_placer.assist_set_ghost_visible(false)
	if _line_label != null:
		_line_label.text = Rules.road_line_label(line_plan)
		var ok: bool = bool(line_plan["ok"]) and bad.is_empty()
		_line_label.add_theme_color_override("font_color", UITheme.POSITIVE if ok else UITheme.DANGER)
		_line_label.visible = true
		if is_inside_tree():
			_position_line_label()

func _build_line_label() -> void:
	_line_label = UITheme.make_label("", "body", UITheme.POSITIVE)
	_line_label.name = "RoadLineCost"
	_line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_line_label.add_theme_constant_override("outline_size", 6)
	_line_label.visible = false
	_layer.add_child(_line_label)

func line_label() -> Label:
	return _line_label

## Debajo de la punta final del tramo (el ✓ va encima).
func _position_line_label() -> void:
	var vp := get_viewport().get_visible_rect().size
	_line_label.reset_size()
	var sz := _line_label.get_combined_minimum_size()
	var p: Variant = _placer.assist_cell_to_screen(line_plan["end"], Vector2i.ONE) if line_active() else null
	var pos: Vector2 = Vector2(vp.x * 0.5 - sz.x * 0.5, vp.y - sz.y - 80.0)
	if p != null:
		pos = (p as Vector2) + Vector2(-sz.x * 0.5, 22.0)
	pos.x = clampf(pos.x, 8.0, vp.x - sz.x - 8.0)
	pos.y = clampf(pos.y, 60.0, vp.y - sz.y - 8.0)
	_line_label.position = pos
