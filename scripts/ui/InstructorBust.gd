extends Control
## Los instructores (feat/instructores, docs/23 §9): un busto caricaturesco
## de medio cuerpo que acompana a las tarjetas que le hablan al jugador.
##
##   * **Capitana Ada Remache** (`COLONY`), Capitana de Ingenieros: la colonia.
##     Tutorial guiado de construccion y consejos de economia y edificios.
##     Gorra de plato ladeada con gafas de aviador y la rueda dentada de la
##     colonia, flequillo y trenza pelirrojos, guerrera de acero azul cerrada
##     con charreteras de laton, cinturon, la mano en la cadera; guina el ojo.
##   * **Sargento Mayor Casimiro Bombarda** (`COMBAT`): el combate. Combate
##     guiado, consejos de Tormenta, Impuesto, ejercito y misiones, y los partes
##     de guerra. Veterano corpulento: casco remachado con estrella, cejas de
##     cepillo, nariz de patata, bigote de manillar, una cerilla apagada en la
##     comisura, capote oliva con galones de ambar y medallas.
##
## Caricatura a color (rediseno de 2026-10-26, rama feat/instructores-caricatura):
## trazo grueso de tinta, colores planos con una sola sombra, ojos grandes.
## Diseno propio, nada de otros juegos; publico de 10 a 15 anos: uniforme
## cerrado y proporciones de caricatura normales.
##
## Todo sale de _draw, sin imagenes (como PrologueEngraving y RegenciaSeal):
## escala sin pixelarse y no pesa en el APK. Seis expresiones (EXPRESSIONS) con
## su gesto de brazo. Coste: el cuerpo se pinta al cambiar de quien, expresion,
## tamano u orientacion, y Godot guarda las ordenes de dibujo; no hay _process.
## Mientras habla (speak) un Timer de ~0,1 s abre y cierra la boca, que es un
## hijo aparte (`Mouth`): solo se repinta la boca. Al callarse, el Timer se para.
##
## El marco sigue a UITheme (laton para Remache, peligro para Bombarda; borde
## mas grueso en alto contraste; fondo de rayos con los tokens). La figura es
## una ilustracion con su propia tinta, en el laton, el acero y el ambar de la
## paleta base: no cambia con la paleta de daltonismo (no lleva informacion de
## color). Las caras en circulo (CartoonTheme.CaptainFace, InstructorFace)
## usan el mismo dibujo: `_draw_ada` / `_draw_bombarda` (o `draw_figure`).
##
## Las funciones de colocacion (dock) son estaticas y puras: las pruebas las
## llaman sin escena.

const COLONY := "colony"
const COMBAT := "combat"
const WHO := [COLONY, COMBAT]

const EXPRESSIONS := ["happy", "point", "worried", "angry", "salute", "surprised"]

## Tamano de serie (PC/tableta) y el de pantalla pequena.
const BASE_SIZE := Vector2(112, 140)
const SMALL_SIZE := Vector2(88, 110)
## Escalas que prueba dock_rect antes de rendirse y ocultarlo.
const DOCK_SCALES := [1.0, 0.8, 0.62]
## Hueco entre la tarjeta y el busto.
const DOCK_GAP := 6.0
const EDGE := 16.0

## Habla: letras por segundo del texto que se escribe, y topes.
const CHARS_PER_SEC := 60.0
const TALK_MIN := 0.5
const TALK_MAX := 2.4
const FLAP_SECONDS := 0.11

## Tinta y colores de la ilustracion (no es interfaz: ver la cabecera). El
## laton, el acero azul y el ambar son los de la paleta de la interfaz
## (UITheme._BASE), fijos: asi el retrato casa con el marco sin depender de la
## paleta de daltonismo.
const INK := Color("1d1712")
const WHITE := Color("fbf6ec")
const BRASS := Color("c99a45")
const AMBER := Color("e5ae3e")
const STEEL := Color("2e4a5e")
const SLATE := Color("1c2026")
## Lo que se oscurece la sombra (una sola, abajo a la derecha).
const SHADE := 0.24
const SKIN_ADA := Color("f7cfab")
const SKIN_BOMB := Color("e2a87f")
const CHEEK := Color(0.93, 0.42, 0.38, 0.42)
const HAIR_ADA := Color("d9581f")
const EYES_ADA := Color("3e9a6c")
const EYES_BOMB := Color("4f7aa6")
## La guerrera de la Capitana: el acero azul aclarado (su sombra es el acero).
const COAT_ADA := Color("3d6787")
## El capote del Sargento: oliva de campana.
const COAT_BOMB := Color("66703f")
const MOUSTACHE := Color("8d6b4c")
const HELMET := Color("6b777f")
const LEATHER := Color("70452a")
const WOOD := Color("b07a42")
const COLLAR_TAB := Color("b8382b")
const LENS := Color("a9dbe6")
const WRENCH := Color("b4bcc2")
const MOUTH_IN := Color("5b161a")
const TONGUE := Color("e2706c")
const SWEAT := Color("8fd0f2")
const ANGER := Color("e0412f")
const MATCH_TIP := Color("c8352a")
## Donde va la boca de cada uno (v dentro de la figura).
const MOUTH_V_COLONY := 0.522
const MOUTH_V_COMBAT := 0.562


var who := COLONY
var expression := "point"
## 1: mira y senala a la derecha (la tarjeta a su derecha); -1: a la izquierda.
var facing := 1

var _mouth: Control
var _timer: Timer
var _type_tween: Tween
var _label_ref: WeakRef = null
var _talk_left := 0.0
var mouth_open := false

func _init() -> void:
	name = "InstructorBust"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = BASE_SIZE
	size = BASE_SIZE
	resized.connect(_redraw_all)
	_mouth = _Mouth.new()
	_mouth.name = "Mouth"
	_mouth.set("bust", self)
	_mouth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mouth.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_mouth)
	_timer = Timer.new()
	_timer.name = "TalkTimer"
	_timer.wait_time = FLAP_SECONDS
	_timer.one_shot = false
	_timer.timeout.connect(_on_flap)
	add_child(_timer)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			finish_speaking())

# ── Estado ───────────────────────────────────────────────────────────

func set_who(id: String) -> void:
	if not id in WHO:
		id = COLONY
	if id == who:
		return
	who = id
	_redraw_all()

func set_expression(e: String) -> void:
	if not e in EXPRESSIONS:
		e = "point"
	if e == expression:
		return
	expression = e
	_redraw_all()

func set_facing(dir: int) -> void:
	dir = 1 if dir >= 0 else -1
	if dir == facing:
		return
	facing = dir
	_redraw_all()

## Quien, que cara y hacia donde, de una vez.
func show_as(id: String, e: String, dir: int = 1) -> void:
	set_who(id)
	set_expression(e)
	set_facing(dir)

func _redraw_all() -> void:
	queue_redraw()
	if _mouth != null:
		_mouth.queue_redraw()

# ── Hablar ───────────────────────────────────────────────────────────

## Escribe `label` poco a poco (visible_ratio, sin cambiar su tamano) y mueve la
## boca mientras tanto. Sin etiqueta, solo la boca, el tiempo de `chars` letras.
## Con el busto oculto (Ajustes, o no cabe) el texto sale entero y no habla.
func speak(label: Label = null, chars: int = -1) -> void:
	finish_speaking()
	if label != null:
		label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
		if chars < 0:
			chars = label.get_total_character_count()
	# `visible` y no is_visible_in_tree(): la tarjeta del tutorial se ve un
	# fotograma despues de cambiar de paso. Si luego se oculta, visibility_changed
	# lo calla y el texto sale entero.
	if not visible or not GameConfig.ui_instructors_visible or not is_inside_tree():
		if label != null:
			label.visible_ratio = 1.0
		return
	var dur := talk_seconds(maxi(chars, 1))
	if label != null:
		_label_ref = weakref(label)
		label.visible_ratio = 0.0
		_type_tween = create_tween()
		_type_tween.tween_property(label, "visible_ratio", 1.0, dur)
	_talk_left = dur
	mouth_open = true
	_mouth.queue_redraw()
	_timer.start()

## Lo que dura hablar `chars` letras (puro, para las pruebas).
static func talk_seconds(chars: int) -> float:
	return clampf(float(chars) / CHARS_PER_SEC, TALK_MIN, TALK_MAX)

## Calla ya: el texto entero, la boca cerrada, el Timer parado.
func finish_speaking() -> void:
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	_type_tween = null
	if _label_ref != null:
		var l: Variant = _label_ref.get_ref()
		if l != null and is_instance_valid(l):
			(l as Label).visible_ratio = 1.0
	_label_ref = null
	_talk_left = 0.0
	if _timer != null:
		_timer.stop()
	if mouth_open:
		mouth_open = false
		if _mouth != null:
			_mouth.queue_redraw()

func is_speaking() -> bool:
	return _timer != null and not _timer.is_stopped()

func _on_flap() -> void:
	_talk_left -= FLAP_SECONDS
	if _talk_left <= 0.0:
		_timer.stop()
		mouth_open = false
	else:
		mouth_open = not mouth_open
	_mouth.queue_redraw()

# ── Textos ───────────────────────────────────────────────────────────

static func name_key(id: String) -> String:
	return "INSTR_COMBAT_NAME" if id == COMBAT else "INSTR_COLONY_NAME"

static func rank_key(id: String) -> String:
	return "INSTR_COMBAT_RANK" if id == COMBAT else "INSTR_COLONY_RANK"

static func short_key(id: String) -> String:
	return "INSTR_COMBAT_SHORT" if id == COMBAT else "INSTR_COLONY_SHORT"

## Quien habla de un consejo segun su categoria de HelpCatalog: Tormenta y
## ejercito, el Sargento; lo basico y la economia, la Capitana.
static func who_for_category(cat: String) -> String:
	return COMBAT if cat in ["storm", "army"] else COLONY

static func expression_for_category(cat: String) -> String:
	match cat:
		"storm":
			return "worried"
		"army":
			return "angry"
		"economy":
			return "happy"
	return "point"

## La cara de la Capitana en cada paso del tutorial guiado.
static func expression_for_step(step: String) -> String:
	if step.begins_with("need_") or step == "repair":
		return "worried"
	if step.begins_with("wait_") or step in ["collect", "done"]:
		return "happy"
	match step:
		"goal":
			return "salute"
		"demolish":
			return "angry"
		"rotate_now":
			return "surprised"
	return "point"

## La cara del Sargento en cada paso del combate guiado.
static func expression_for_combat_step(step: String) -> String:
	match step:
		"c_select":
			return "salute"
		"c_attack", "c_defend":
			return "angry"
		"c_enemy_turn":
			return "worried"
		"c_type_circle":
			return "surprised"
	return "point"

# ── Colocacion ───────────────────────────────────────────────────────

## El tamano de serie para esta pantalla (mas pequeno en un telefono).
static func base_size_for(vp: Vector2) -> Vector2:
	return SMALL_SIZE if vp.x < 900.0 or vp.y < 560.0 else BASE_SIZE

## Donde va el busto pegado a `card`: a su izquierda (mirando a la derecha) o a
## su derecha (mirando a la izquierda), alineado abajo; si no cabe, sentado
## encima de la tarjeta, en su esquina. Prueba cada escala de DOCK_SCALES; nunca
## sale de la pantalla, nunca baja de `min_y` y nunca pisa nada de `avoid` (lo
## que el tutorial senala, los avisos). {"rect": Rect2, "facing": int}, o {} si
## no cabe en ningun sitio (entonces se oculta).
static func dock_rect(vp: Vector2, card: Rect2, base: Vector2, avoid: Array = [], min_y: float = EDGE) -> Dictionary:
	var screen := Rect2(Vector2(EDGE, EDGE), vp - Vector2(EDGE, EDGE) * 2.0)
	for s in DOCK_SCALES:
		var sz: Vector2 = base * float(s)
		var bottom := card.end.y - sz.y
		var tries: Array = [
			[Vector2(card.position.x - DOCK_GAP - sz.x, bottom), 1],
			[Vector2(card.end.x + DOCK_GAP, bottom), -1],
		]
		for t in tries:
			var r := Rect2(t[0], sz)
			if _fits(r, screen, min_y, avoid):
				return {"rect": r, "facing": int(t[1])}
	# Encima de la tarjeta, asomando por su esquina (telefono estrecho).
	for s in DOCK_SCALES:
		var sz: Vector2 = base * float(s)
		var top := card.position.y - sz.y + 4.0
		for t in [[Vector2(card.position.x + 8.0, top), 1], [Vector2(card.end.x - 8.0 - sz.x, top), -1]]:
			var r := Rect2(t[0], sz)
			if _fits(r, screen, min_y, avoid):
				return {"rect": r, "facing": int(t[1])}
	return {}

## Cuanto se corre a la derecha una tarjeta centrada en horizontal (ancho `tw`,
## empieza en `card_top`) para no pisar `block` (la Tormenta con la orden de la
## Regencia, cuando baja a la columna izquierda en tablet 4:3 y movil). 0 si no
## estorba; nunca saca la tarjeta de la pantalla (si no cabe, lo que quepa).
## La usan la tarjeta de consejo y la del tutorial (ronda visual de la 1.1).
static func centered_card_shift(vp: Vector2, tw: float, block: Rect2, card_top: float) -> float:
	if block.size.x < 1.0 or block.end.y <= card_top:
		return 0.0
	var left := vp.x * 0.5 - tw * 0.5
	if block.end.x <= left or block.position.x > vp.x * 0.5:
		return 0.0
	var room := (vp.x - EDGE) - (vp.x * 0.5 + tw * 0.5)
	if room <= 0.0:
		return 0.0
	return minf(block.end.x + EDGE - left, room)

static func _fits(r: Rect2, screen: Rect2, min_y: float, avoid: Array) -> bool:
	if not screen.encloses(r) or r.position.y < min_y:
		return false
	for a in avoid:
		var ar: Rect2 = a
		if ar.size.x > 1.0 and ar.size.y > 1.0 and r.intersects(ar):
			return false
	return true

## Coloca el busto segun dock_rect, o lo oculta. Devuelve si se ve.
func dock_to(vp: Vector2, card: Rect2, avoid: Array = [], min_y: float = EDGE) -> bool:
	if not GameConfig.ui_instructors_visible:
		visible = false
		return false
	var d := dock_rect(vp, card, base_size_for(vp), avoid, min_y)
	if d.is_empty():
		visible = false
		return false
	var r: Rect2 = d["rect"]
	position = r.position
	if not size.is_equal_approx(r.size):
		custom_minimum_size = Vector2.ZERO
		size = r.size
	set_facing(int(d["facing"]))
	visible = true
	return true

# ══════════════════════════════════════════════════════════════════════
# ── Dibujo ──
# ══════════════════════════════════════════════════════════════════════
#
# Caricatura a color (rediseño de feat/instructores-caricatura): trazo grueso de
# tinta, colores planos con UNA sombra (abajo a la derecha: la luz viene de
# arriba a la izquierda) y ojos grandes. Coordenadas (u, v) en [0, 1] dentro de
# la figura; los radios, en fracciones del alto `h`.

func _draw() -> void:
	draw_bust(self, Rect2(Vector2.ZERO, size), who, expression, facing)

## El busto entero en `area`: marco, fondo de rayos, figura y placa con el
## nombre. Estatica para las pruebas y las capturas. La boca no: va en su nodo.
static func draw_bust(ci: CanvasItem, area: Rect2, id: String, e: String, dir: int) -> void:
	if area.size.x < 24.0 or area.size.y < 30.0:
		return
	var h := area.size.y
	var border: Color = UITheme.DANGER.lightened(0.15) if id == COMBAT else UITheme.ACCENT
	var bw := 3.0 if UITheme.high_contrast else 2.0
	var radius := maxf(4.0, h * 0.06)
	var fig := area.grow(-bw)
	# Fondo: la pizarra con un sol de rayos detras de la cabeza; laton para la
	# Capitana (su guerrera azul resalta), acero para el Sargento (su oliva).
	var inner := _round_rect(area, radius)
	ci.draw_colored_polygon(inner, UITheme.SURFACE)
	var ray: Color = UITheme.INFO if id == COMBAT else UITheme.ACCENT.darkened(0.45)
	_sunburst(ci, inner, _p(fig, 0.5, 0.34), h, ray)
	# La figura, espejada si mira a la izquierda.
	_mirror(ci, area, dir)
	draw_figure(ci, fig, id, e, false, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# La placa con el nombre corto, con un remache a cada lado.
	var ph := h * 0.17
	var plate := Rect2(area.position.x, area.end.y - ph - bw, area.size.x, ph + bw)
	for part in Geometry2D.intersect_polygons(_rect_poly(plate), inner):
		_fill(ci, part, UITheme.HUD_BG)
	ci.draw_line(Vector2(area.position.x + bw, plate.position.y), Vector2(area.end.x - bw, plate.position.y), border, bw)
	var rv := maxf(1.5, h * 0.016)
	for x in [area.position.x + bw + rv * 2.2, area.end.x - bw - rv * 2.2]:
		var rc := Vector2(x, plate.position.y + ph * 0.5)
		ci.draw_circle(rc, rv, border)
		ci.draw_circle(rc + Vector2(-rv * 0.3, -rv * 0.3), rv * 0.35, Color(1, 1, 1, 0.35))
	var font: Font = UITheme.bold_font()
	if font != null:
		var fs := int(clampf(h * 0.085, 9.0, 16.0))
		var text := Tr.t(short_key(id))
		var room := area.size.x - bw * 2.0 - rv * 8.0
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base_y: float = plate.position.y + ph * 0.5 + fs * 0.36
		ci.draw_string(font, Vector2(area.position.x + maxf(bw + rv * 4.0, (area.size.x - tw) * 0.5), base_y),
			text, HORIZONTAL_ALIGNMENT_LEFT, room, fs, UITheme.TEXT_BRIGHT)
	# El marco, encima de todo: recoge lo que asome de la figura.
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.border_color = border
	frame.set_border_width_all(int(bw))
	frame.set_corner_radius_all(int(radius))
	frame.anti_aliasing = true
	ci.draw_style_box(frame, area)

static func _mirror(ci: CanvasItem, area: Rect2, dir: int) -> void:
	if dir < 0:
		ci.draw_set_transform(Vector2(area.position.x * 2.0 + area.size.x, 0.0), 0.0, Vector2(-1, 1))
	else:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func _sunburst(ci: CanvasItem, clip: PackedVector2Array, c: Vector2, h: float, col: Color) -> void:
	_fill(ci, clip, col.darkened(0.28))
	var n := 18
	var far := h * 2.0
	for i in n:
		if i % 2 == 1:
			continue
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var wedge := PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * far, c + Vector2(cos(a1), sin(a1)) * far])
		for part in Geometry2D.intersect_polygons(wedge, clip):
			_fill(ci, part, col)
	ci.draw_circle(c, h * 0.26, Color(col.lightened(0.25), 0.35))

## La figura sola (sin marco) en `b`. `with_mouth`: la boca cerrada (para las
## caras recortadas, que no llevan el nodo Mouth). `arms`: los brazos y lo que
## llevan en la mano (las caras recortadas no: no caben en el circulo).
static func draw_figure(ci: CanvasItem, b: Rect2, id: String, e: String, with_mouth: bool = true, arms: bool = true) -> void:
	if b.size.x < 8.0 or b.size.y < 10.0:
		return
	if not e in EXPRESSIONS:
		e = "point"
	if id == COMBAT:
		_figure_bombarda(ci, b, e, arms)
	else:
		_figure_ada(ci, b, e, arms)
	if with_mouth:
		_mouth_shape(ci, b, id, e, false)

## Las caras en circulo (CartoonTheme.CaptainFace, la maqueta, InstructorFace
## de la 1.2) llaman a estas dos: el mismo retrato, con su boca y sin brazos.
static func _draw_ada(ci: CanvasItem, b: Rect2, e: String) -> void:
	draw_figure(ci, b, COLONY, e, true, false)

static func _draw_bombarda(ci: CanvasItem, b: Rect2, e: String) -> void:
	draw_figure(ci, b, COMBAT, e, true, false)

## El rectangulo de la figura para una cara en circulo de `size`: la boca de
## `id` cae a 2/3 del alto del circulo, asi la cabeza queda centrada (la
## caricatura de 2026-10-26 tiene la cabeza mas abajo que el busto viejo y el
## recorte de antes solo ensenaba la gorra). Integracion v1.3.
static func face_rect(size: Vector2, id: String) -> Rect2:
	var sz := minf(size.x, size.y)
	var h := sz * 2.15
	var w := h * 0.8
	var mouth_v: float = MOUTH_V_COMBAT if id == COMBAT else MOUTH_V_COLONY
	var top := sz * 0.68 - mouth_v * h
	return Rect2(Vector2(size.x * 0.5 - w * 0.5, top), Vector2(w, h))

# ── Utilidades ───────────────────────────────────────────────────────

## Punto (u, v) en [0, 1] dentro de `box`.
static func _p(box: Rect2, u: float, v: float) -> Vector2:
	return box.position + Vector2(u * box.size.x, v * box.size.y)

static func _ow(h: float) -> float:
	return maxf(1.2, h * 0.02)

static func _ell(c: Vector2, rx: float, ry: float, n: int = 24, from := 0.0, to := TAU) -> PackedVector2Array:
	var out := PackedVector2Array()
	var full := is_equal_approx(to - from, TAU)
	var count := n if full else n + 1
	for i in count:
		var a := from + (to - from) * float(i) / float(n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out

static func _poly(box: Rect2, uv: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, uv.size(), 2):
		out.append(_p(box, float(uv[i]), float(uv[i + 1])))
	return out

static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])

static func _round_rect(r: Rect2, rad: float, seg: int = 4) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var out := PackedVector2Array()
	var corners := [
		[Vector2(r.end.x - rad, r.position.y + rad), -PI * 0.5],
		[Vector2(r.end.x - rad, r.end.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5],
		[Vector2(r.position.x + rad, r.position.y + rad), PI],
	]
	for c in corners:
		for i in seg + 1:
			var a: float = float(c[1]) + PI * 0.5 * float(i) / float(seg)
			out.append((c[0] as Vector2) + Vector2(cos(a), sin(a)) * rad)
	return out

static func _rot(pts: PackedVector2Array, piv: Vector2, ang: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(piv + (p - piv).rotated(ang))
	return out

## Relleno sin contorno; no pinta un poligono que no se pueda triangular.
static func _fill(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() >= 3 and not Geometry2D.triangulate_polygon(pts).is_empty():
		ci.draw_colored_polygon(pts, col)

static func _outline(ci: CanvasItem, pts: PackedVector2Array, ow: float) -> void:
	if pts.size() < 2:
		return
	var line := pts.duplicate()
	line.append(pts[0])
	ci.draw_polyline(line, INK, ow, true)

## Relleno plano, su sombra (si `shade` > 0: el ancho de la franja) y el
## contorno de tinta.
static func _shape(ci: CanvasItem, pts: PackedVector2Array, fill: Color, ow: float, shade: float = 0.0) -> void:
	if pts.size() < 3:
		return
	_fill(ci, pts, fill)
	if shade > 0.0:
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + Vector2(-shade, -shade))
		for part in Geometry2D.clip_polygons(pts, moved):
			_fill(ci, part, fill.darkened(SHADE))
	if ow > 0.0:
		_outline(ci, pts, ow)

## Rellena la parte de `pts` que cae dentro de `clip`.
static func _fill_in(ci: CanvasItem, pts: PackedVector2Array, clip: PackedVector2Array, col: Color) -> void:
	for part in Geometry2D.intersect_polygons(pts, clip):
		_fill(ci, part, col)

## Un trazo grueso (manga, dedo, asta) con contorno: la tinta debajo.
static func _limb(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, ow: float) -> void:
	ci.draw_polyline(pts, INK, w + ow * 2.0, true)
	for p in [pts[0], pts[pts.size() - 1]]:
		ci.draw_circle(p, w * 0.5 + ow, INK)
	ci.draw_polyline(pts, col, w, true)
	for p in pts:
		ci.draw_circle(p, w * 0.5, col)

static func _button(ci: CanvasItem, c: Vector2, r: float, ow: float) -> void:
	ci.draw_circle(c, r + ow * 0.6, INK)
	ci.draw_circle(c, r, BRASS)
	ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.35, Color(1, 1, 1, 0.5))

## Rueda dentada de laton: la insignia de la colonia.
static func _cog(ci: CanvasItem, c: Vector2, r: float, ow: float) -> void:
	var pts := PackedVector2Array()
	var teeth := 8
	for i in teeth * 4:
		var a := TAU * (float(i) + 0.5) / float(teeth * 4)
		pts.append(c + Vector2(cos(a), sin(a)) * (r if (i % 4) < 2 else r * 0.72))
	_shape(ci, pts, BRASS, ow)
	ci.draw_circle(c, r * 0.36, STEEL)
	ci.draw_arc(c, r * 0.36, 0.0, TAU, 12, INK, ow * 0.7, true)

static func _star(ci: CanvasItem, c: Vector2, r: float, col: Color, ow: float) -> void:
	var sp := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		sp.append(c + Vector2(cos(a), sin(a)) * rr)
	_shape(ci, sp, col, ow)

# ── Ojos, cejas y gestos de la cara ──────────────────────────────────

## Como mira cada expresion: hacia donde (en fracciones del ojo), cuanto baja
## el parpado (0..1) y su inclinacion (+ baja el lado de dentro: enfado; - el
## de fuera: pena).
static func _eye_pose(e: String) -> Dictionary:
	match e:
		"happy":
			return {"look": Vector2(0.6, 0.0), "lid": 0.1, "tilt": 0.0, "big": 1.0}
		"worried":
			return {"look": Vector2(-0.6, -0.7), "lid": 0.08, "tilt": -0.3, "big": 1.05}
		"angry":
			return {"look": Vector2(0.6, 0.35), "lid": 0.42, "tilt": 0.4, "big": 1.0}
		"salute":
			return {"look": Vector2(0.4, 0.0), "lid": 0.34, "tilt": 0.0, "big": 1.0}
		"surprised":
			return {"look": Vector2(0.0, 0.0), "lid": 0.0, "tilt": 0.0, "big": 1.2}
	return {"look": Vector2(1.0, -0.15), "lid": 0.1, "tilt": 0.0, "big": 1.0}

## Un ojo grande de caricatura. `side` -1 el de la izquierda (antes del
## espejo), +1 el que da a la tarjeta.
static func _eye(ci: CanvasItem, c: Vector2, rx: float, ry: float, iris: Color, pose: Dictionary, side: float,
		skin: Color, ow: float, lid_min: float = 0.0) -> void:
	var big: float = pose["big"]
	rx *= big
	ry *= big
	var eye := _ell(c, rx, ry, 22)
	_fill(ci, eye, WHITE)
	var k := 0.42 if big > 1.1 else 0.64
	var ir := minf(rx, ry) * k
	var look: Vector2 = pose["look"]
	var ic := c + Vector2(look.x * rx * 0.4, look.y * ry * 0.38)
	_fill_in(ci, _ell(ic, ir, ir * 1.06, 16), eye, iris)
	_fill_in(ci, _ell(ic, ir * 0.52, ir * 0.55, 12), eye, INK)
	ci.draw_circle(ic + Vector2(-ir * 0.36, -ir * 0.4), ir * 0.3, WHITE)
	var lid: float = maxf(float(pose["lid"]), lid_min) if big <= 1.1 else float(pose["lid"])
	var tilt: float = pose["tilt"]
	if lid > 0.01 or absf(tilt) > 0.01:
		var inner_x := c.x - side * rx * 1.4
		var outer_x := c.x + side * rx * 1.4
		var y_mid := c.y - ry + 2.0 * ry * lid
		var top := c.y - ry * 1.4
		var lid_poly := PackedVector2Array([Vector2(inner_x, top), Vector2(outer_x, top),
			Vector2(outer_x, y_mid - tilt * ry), Vector2(inner_x, y_mid + tilt * ry)])
		for part in Geometry2D.intersect_polygons(lid_poly, eye):
			_fill(ci, part, skin.darkened(0.1))
			_outline(ci, part, ow * 0.7)
	_outline(ci, eye, ow * 0.8)

## Ojo cerrado de risa (o guino): un arco hacia arriba.
static func _eye_closed(ci: CanvasItem, c: Vector2, rx: float, ry: float, ow: float) -> void:
	ci.draw_arc(c + Vector2(0, ry * 0.35), rx * 0.95, PI * 1.12, PI * 1.88, 12, INK, ow * 1.6, true)

static func _brow(ci: CanvasItem, c: Vector2, rx: float, ry: float, side: float, e: String, col: Color, thick: float, ow: float) -> void:
	var inner := Vector2(c.x - side * rx * 0.9, c.y - ry * 1.42)
	var outer := Vector2(c.x + side * rx * 1.1, c.y - ry * 1.3)
	var arch := ry * 0.25
	match e:
		"angry":
			inner.y += ry * 0.5
			outer.y -= ry * 0.22
			arch = 0.0
		"worried":
			inner.y -= ry * 0.45
			outer.y += ry * 0.2
			arch = ry * 0.08
		"surprised":
			inner.y -= ry * 0.6
			outer.y -= ry * 0.5
			arch = ry * 0.35
		"happy":
			inner.y -= ry * 0.18
			outer.y -= ry * 0.08
	var mid := (inner + outer) * 0.5 + Vector2(0, -arch)
	_limb(ci, PackedVector2Array([inner, mid, outer]), col, thick, ow * 0.5)

## Lo que acompana a la cara: gotas de sudor, la vena del enfado, las rayas de
## la sorpresa.
static func _marks(ci: CanvasItem, b: Rect2, e: String, h: float, ow: float) -> void:
	match e:
		"worried":
			_drop(ci, _p(b, 0.23, 0.31), h * 0.03, ow * 0.8)
			_drop(ci, _p(b, 0.19, 0.39), h * 0.021, ow * 0.7)
		"angry":
			var c := _p(b, 0.16, 0.13)
			var s := h * 0.045
			for k in 4:
				var a := PI * 0.25 + PI * 0.5 * float(k)
				var d := Vector2(cos(a), sin(a))
				ci.draw_arc(c + d * s * 0.95, s * 0.6, a + PI * 0.72, a + PI * 1.28, 6, INK, ow * 2.6, true)
				ci.draw_arc(c + d * s * 0.95, s * 0.6, a + PI * 0.72, a + PI * 1.28, 6, ANGER, ow * 1.3, true)
		"surprised":
			var c := _p(b, 0.5, 0.31)
			for s in [-1.0, 1.0]:
				for k in 3:
					var a: float = -PI * 0.5 + s * (PI * 0.2 + PI * 0.11 * float(k))
					var d := Vector2(cos(a), sin(a))
					ci.draw_line(c + d * h * 0.31, c + d * h * 0.38, INK, ow * 1.4, true)

static func _drop(ci: CanvasItem, c: Vector2, s: float, ow: float) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -s * 1.5)])
	pts.append_array(_ell(c, s * 0.75, s * 0.75, 12, -PI * 0.2, PI * 1.2))
	_shape(ci, pts, SWEAT, ow)
	ci.draw_circle(c + Vector2(-s * 0.25, -s * 0.1), s * 0.2, WHITE)

# ── Brazos y manos ───────────────────────────────────────────────────

## Una manga (de `uv`, del hombro a la muneca) con su puno y la mano. Devuelve
## el centro de la mano.
static func _arm(ci: CanvasItem, b: Rect2, uv: Array, cloth: Color, skin: Color, cuff: Color, hand: String,
		hand_dir: Vector2, sw: float, r: float, ow: float, chevrons: bool = false) -> Vector2:
	var pts := _poly(b, uv)
	_limb(ci, pts, cloth, sw, ow)
	var wrist := pts[pts.size() - 1]
	var d := (wrist - pts[pts.size() - 2]).normalized()
	if chevrons:
		_chevrons(ci, pts[0], pts[1], sw, ow)
	ci.draw_line(wrist - d * sw * 0.55, wrist - d * sw * 0.15, cuff, sw * 0.98)
	var c := wrist + d * r * 0.55
	_hand(ci, c, hand, hand_dir if hand_dir != Vector2.ZERO else d, r, skin, ow)
	return c

static func _chevrons(ci: CanvasItem, a: Vector2, z: Vector2, sw: float, ow: float) -> void:
	var d := (z - a).normalized()
	var n := Vector2(-d.y, d.x)
	for k in [0.42, 0.66]:
		var c := a.lerp(z, k)
		var v := PackedVector2Array([c + n * sw * 0.42 + d * sw * 0.32, c, c - n * sw * 0.42 + d * sw * 0.32])
		ci.draw_polyline(v, INK, ow * 3.0, true)
		ci.draw_polyline(v, AMBER, ow * 1.4, true)

static func _hand(ci: CanvasItem, c: Vector2, kind: String, dir: Vector2, r: float, skin: Color, ow: float) -> void:
	var d := dir.normalized()
	match kind:
		"point":
			_limb(ci, PackedVector2Array([c + d * r * 0.4, c + d * r * 2.0]), skin, r * 0.62, ow * 0.8)
			_shape(ci, _ell(c, r, r * 0.9, 16), skin, ow)
			ci.draw_arc(c + Vector2(-r * 0.1, r * 0.1), r * 0.5, PI * 0.1, PI * 0.9, 6, INK, ow * 0.6, true)
		"thumb":
			_limb(ci, PackedVector2Array([c + Vector2(-r * 0.25, -r * 0.4), c + Vector2(-r * 0.3, -r * 1.75)]), skin, r * 0.62, ow * 0.8)
			_shape(ci, _ell(c, r * 1.05, r * 0.9, 16), skin, ow)
			for i in 2:
				var y := -r * 0.15 + r * 0.42 * float(i)
				ci.draw_line(c + Vector2(r * 0.05, y), c + Vector2(r * 0.85, y), INK, ow * 0.6, true)
		"flat":
			# La palma de canto, de la muneca a la punta de los dedos.
			var n := Vector2(-d.y, d.x)
			var palm := PackedVector2Array([c - n * r * 0.72 - d * r * 0.3, c - n * r * 0.62 + d * r * 1.7,
				c + d * r * 2.15, c + n * r * 0.62 + d * r * 1.7, c + n * r * 0.72 - d * r * 0.3])
			_shape(ci, palm, skin, ow)
			ci.draw_line(c + d * r * 0.9, c + d * r * 1.8, INK, ow * 0.6, true)
		"open":
			# La palma abierta hacia el jugador: cuatro dedos arriba y el pulgar.
			for i in 4:
				var a := -PI * 0.5 + (float(i) - 1.3) * 0.34
				_limb(ci, PackedVector2Array([c, c + Vector2(cos(a), sin(a)) * r * 1.75]), skin, r * 0.5, ow * 0.7)
			_limb(ci, PackedVector2Array([c, c + Vector2(-r * 1.45, -r * 0.15)]), skin, r * 0.52, ow * 0.7)
			_shape(ci, _ell(c, r * 1.0, r * 0.95, 16), skin, ow)
		_:
			# Puno (tambien el que agarra el asta).
			_shape(ci, _ell(c, r * 1.05, r * 0.92, 16), skin, ow)
			for i in 2:
				var y := -r * 0.2 + r * 0.42 * float(i)
				ci.draw_line(c + Vector2(-r * 0.55, y), c + Vector2(r * 0.55, y), INK, ow * 0.55, true)

## Una charretera de laton con flecos de ambar.
static func _epaulette(ci: CanvasItem, c: Vector2, h: float, ang: float, ow: float) -> void:
	var rx := h * 0.064
	var ry := h * 0.027
	var ax := Vector2(cos(ang), sin(ang))
	var nx := Vector2(-ax.y, ax.x)
	for k in 5:
		var t := -0.8 + 0.4 * float(k)
		var base := c + ax * rx * t + nx * ry * 0.7
		var tip := base + Vector2(0, h * 0.024)
		ci.draw_line(base, tip, INK, ow * 2.1, true)
		ci.draw_line(base, tip, AMBER, ow * 0.9, true)
	_shape(ci, _rot(_ell(c, rx, ry, 16), c, ang), BRASS, ow)
	ci.draw_circle(c, ry * 0.45, AMBER.lightened(0.2))

# ── La Capitana Ada Remache ──────────────────────────────────────────
#
# Oficial de ingenieros con carisma de mando: gorra de plato ladeada con las
# gafas de aviador sobre la copa y la rueda dentada de la colonia, flequillo y
# trenza pelirrojos, guerrera de acero azul cerrada hasta el cuello con
# charreteras de laton, cinturon de cuero, la otra mano en la cadera, guino y
# media sonrisa.

static func _figure_ada(ci: CanvasItem, b: Rect2, e: String, arms: bool) -> void:
	var h := b.size.y
	var ow := _ow(h)
	var sh := h * 0.028
	var skin := SKIN_ADA
	var coat := COAT_ADA
	var sw := h * 0.088
	var hr := h * 0.038
	# Cuello, torso y cuello alto de la guerrera.
	_shape(ci, _poly(b, [0.43, 0.50, 0.57, 0.50, 0.58, 0.65, 0.42, 0.65]), skin, ow)
	ci.draw_colored_polygon(_ell(_p(b, 0.5, 0.575), h * 0.052, h * 0.03, 14), skin.darkened(0.22))
	_shape(ci, _poly(b, [0.04, 1.0, 0.045, 0.77, 0.13, 0.678, 0.36, 0.635, 0.64, 0.635, 0.87, 0.678, 0.955, 0.77, 0.96, 1.0]), coat, ow, sh)
	_shape(ci, _poly(b, [0.39, 0.595, 0.61, 0.595, 0.63, 0.665, 0.5, 0.685, 0.37, 0.665]), coat.darkened(0.12), ow)
	ci.draw_line(_p(b, 0.395, 0.603), _p(b, 0.605, 0.603), BRASS, ow * 1.3, true)
	# Cierre cruzado con dos filas de botones y la insignia en el pecho.
	ci.draw_line(_p(b, 0.5, 0.685), _p(b, 0.5, 0.78), INK, ow * 0.9, true)
	for v in [0.715, 0.752]:
		for u in [0.445, 0.555]:
			_button(ci, _p(b, u, v), h * 0.013, ow)
	_cog(ci, _p(b, 0.72, 0.725), h * 0.034, ow * 0.7)
	# El cinturon con su hebilla.
	_shape(ci, _poly(b, [0.046, 0.778, 0.954, 0.778, 0.957, 0.826, 0.043, 0.826]), LEATHER, ow, sh * 0.4)
	var bk := Rect2(_p(b, 0.5, 0.802) - Vector2(h * 0.04, h * 0.029), Vector2(h * 0.08, h * 0.058))
	_shape(ci, _rect_poly(bk), BRASS, ow * 0.8)
	_fill(ci, _rect_poly(bk.grow(-h * 0.014)), LEATHER.darkened(0.2))
	# La trenza, por delante del hombro, con su pasador de laton y la punta.
	for i in 6:
		var t := float(i) / 5.0
		var c := _p(b, 0.335 - 0.07 * t, 0.50 + 0.235 * t)
		_shape(ci, _ell(c, h * (0.043 - 0.008 * t), h * 0.036, 14), HAIR_ADA if i % 2 == 0 else HAIR_ADA.darkened(0.14), ow * 0.8)
	_shape(ci, _poly(b, [0.243, 0.765, 0.287, 0.765, 0.297, 0.805, 0.265, 0.79, 0.233, 0.805]), HAIR_ADA, ow * 0.8)
	_shape(ci, _rect_poly(Rect2(_p(b, 0.265, 0.758) - Vector2(h * 0.026, h * 0.012), Vector2(h * 0.052, h * 0.024))), BRASS, ow * 0.7)
	if arms:
		# La mano en la cadera.
		_arm(ci, b, [0.15, 0.685, 0.075, 0.76, 0.18, 0.805], coat, skin, BRASS, "fist", Vector2.ZERO, sw, hr, ow)
		if e == "worried":
			# Se rasca la nuca: la mano queda detras de la cabeza.
			_arm(ci, b, [0.86, 0.69, 0.94, 0.53, 0.80, 0.37], coat, skin, BRASS, "fist", Vector2.ZERO, sw, hr, ow)
	# El pelo de detras y las orejas.
	_shape(ci, _ell(_p(b, 0.5, 0.345), h * 0.205, h * 0.165, 28), HAIR_ADA, ow, sh)
	for s in [-1.0, 1.0]:
		_shape(ci, _ell(_p(b, 0.5, 0.43) + Vector2(s * h * 0.163, 0), h * 0.03, h * 0.042, 12), skin, ow * 0.9)
	# La cabeza: redonda, la barbilla un poco mas estrecha.
	var hc := _p(b, 0.5, 0.39)
	var head := PackedVector2Array()
	for i in 32:
		var a := TAU * float(i) / 32.0
		var squeeze := 1.0 - 0.13 * maxf(0.0, sin(a))
		head.append(hc + Vector2(cos(a) * h * 0.165 * squeeze, sin(a) * h * 0.18))
	_shape(ci, head, skin, ow, sh)
	# Mejillas y pecas.
	for s in [-1.0, 1.0]:
		ci.draw_colored_polygon(_ell(_p(b, 0.5 + s * 0.135, 0.485), h * 0.03, h * 0.019, 12), CHEEK)
		for f in [[0.11, 0.468], [0.15, 0.476], [0.13, 0.457]]:
			ci.draw_circle(_p(b, 0.5 + s * float(f[0]), float(f[1])), h * 0.0055, HAIR_ADA.darkened(0.25))
	# Ojos (guino al estar contenta), pestana y cejas.
	var pose := _eye_pose(e)
	for s in [-1.0, 1.0]:
		var c := _p(b, 0.5 + s * 0.088, 0.428)
		if e == "happy" and s > 0.0:
			_eye_closed(ci, c, h * 0.04, h * 0.05, ow)
		else:
			_eye(ci, c, h * 0.04, h * 0.05, EYES_ADA, pose, s, skin, ow)
			var big: float = pose["big"]
			ci.draw_line(c + Vector2(s * h * 0.034 * big, -h * 0.03 * big), c + Vector2(s * h * 0.052 * big, -h * 0.045 * big), INK, ow * 1.2, true)
		_brow(ci, c, h * 0.04, h * 0.05, s, e, HAIR_ADA.darkened(0.35), h * 0.017, ow)
	# Nariz de boton.
	var nc := _p(b, 0.515, 0.482)
	ci.draw_colored_polygon(_ell(nc, h * 0.019, h * 0.015, 12), skin.lerp(Color("d9785a"), 0.4))
	ci.draw_arc(nc, h * 0.019, -PI * 0.35, PI * 0.3, 6, INK, ow * 0.8, true)
	# El flequillo, que cae hacia un lado.
	_shape(ci, _poly(b, [0.30, 0.28, 0.70, 0.28, 0.69, 0.335, 0.64, 0.315, 0.58, 0.345, 0.52, 0.31, 0.45, 0.345,
		0.38, 0.33, 0.33, 0.375, 0.30, 0.35]), HAIR_ADA, ow, sh * 0.6)
	_cap_ada(ci, b, h, ow, sh)
	if arms:
		_gesture_ada(ci, b, e, coat, skin, sw, hr, h, ow)
	# Las charreteras, encima del arranque de los brazos.
	_epaulette(ci, _p(b, 0.155, 0.675), h, 0.42, ow)
	_epaulette(ci, _p(b, 0.845, 0.675), h, -0.42, ow)
	_marks(ci, b, e, h, ow)

## La gorra de plato, ladeada con gracia.
static func _cap_ada(ci: CanvasItem, b: Rect2, h: float, ow: float, sh: float) -> void:
	var piv := _p(b, 0.5, 0.27)
	var ang := -0.08
	var crown := _ell(_p(b, 0.5, 0.19), h * 0.255, h * 0.12, 20, PI, TAU)
	crown.append(_p(b, 0.70, 0.235))
	crown.append(_p(b, 0.30, 0.235))
	_shape(ci, _rot(crown, piv, ang), COAT_ADA, ow, sh)
	# Las gafas de aviador sobre la copa, con su correa.
	_limb(ci, _rot(_poly(b, [0.205, 0.18, 0.5, 0.17, 0.795, 0.18]), piv, ang), LEATHER, h * 0.024, ow * 0.7)
	for u in [0.415, 0.585]:
		var g := piv + (_p(b, u, 0.165) - piv).rotated(ang)
		ci.draw_circle(g, h * 0.045 + ow * 0.6, INK)
		ci.draw_circle(g, h * 0.045, BRASS)
		ci.draw_circle(g, h * 0.03, LENS)
		ci.draw_arc(g, h * 0.03, 0.0, TAU, 16, INK, ow * 0.7, true)
		ci.draw_arc(g, h * 0.018, PI * 1.1, PI * 1.6, 6, WHITE, ow * 1.1, true)
	# La cinta con la rueda dentada y la visera.
	_shape(ci, _rot(_poly(b, [0.30, 0.225, 0.70, 0.225, 0.705, 0.285, 0.295, 0.285]), piv, ang), SLATE.lightened(0.08), ow)
	_limb(ci, _rot(_poly(b, [0.31, 0.232, 0.69, 0.232]), piv, ang), BRASS, ow * 0.9, 0.0)
	_cog(ci, piv + (_p(b, 0.5, 0.256) - piv).rotated(ang), h * 0.032, ow * 0.7)
	_shape(ci, _rot(_poly(b, [0.285, 0.28, 0.715, 0.28, 0.75, 0.30, 0.64, 0.325, 0.36, 0.325, 0.25, 0.30]), piv, ang), SLATE, ow)
	ci.draw_polyline(_rot(_poly(b, [0.35, 0.297, 0.5, 0.302, 0.63, 0.297]), piv, ang), Color(1, 1, 1, 0.28), ow, true)

static func _gesture_ada(ci: CanvasItem, b: Rect2, e: String, coat: Color, skin: Color, sw: float, hr: float, h: float, ow: float) -> void:
	match e:
		"point":
			_arm(ci, b, [0.86, 0.69, 0.93, 0.58, 0.87, 0.47], coat, skin, BRASS, "point", Vector2(1, -0.35), sw, hr, ow)
		"happy":
			# Sujeta la bandera de la colonia: asta, banderin de dos puntas y
			# remate de laton.
			_limb(ci, _poly(b, [0.925, 0.99, 0.925, 0.05]), WOOD, h * 0.022, ow * 0.8)
			var flag := _poly(b, [0.925, 0.045, 0.82, 0.062, 0.70, 0.05, 0.755, 0.107, 0.70, 0.168, 0.82, 0.152, 0.925, 0.172])
			_shape(ci, flag, AMBER, ow, h * 0.02)
			_fill_in(ci, _rect_poly(Rect2(_p(b, 0.6, 0.088), Vector2(b.size.x * 0.4, h * 0.036))), flag, STEEL)
			_outline(ci, flag, ow)
			ci.draw_circle(_p(b, 0.925, 0.04), h * 0.02 + ow * 0.6, INK)
			ci.draw_circle(_p(b, 0.925, 0.04), h * 0.02, BRASS)
			_arm(ci, b, [0.86, 0.69, 0.95, 0.65, 0.925, 0.585], coat, skin, BRASS, "fist", Vector2.ZERO, sw, hr, ow)
		"salute":
			_arm(ci, b, [0.86, 0.69, 0.93, 0.52, 0.81, 0.355], coat, skin, BRASS, "flat", Vector2.ZERO, sw, hr, ow)
		"angry":
			# La llave inglesa en alto (de broma).
			var hc := _p(b, 0.91, 0.205)
			_limb(ci, PackedVector2Array([_p(b, 0.895, 0.53), hc + Vector2(0, h * 0.04)]), WRENCH, h * 0.03, ow)
			var jaw := _ell(hc, h * 0.045, h * 0.045, 14, -PI * 0.3, PI * 1.3)
			var inner := _ell(hc, h * 0.022, h * 0.022, 8, PI * 1.3, -PI * 0.3)
			jaw.append_array(inner)
			_shape(ci, jaw, WRENCH, ow, h * 0.012)
			_arm(ci, b, [0.86, 0.69, 0.95, 0.60, 0.90, 0.48], coat, skin, BRASS, "fist", Vector2.ZERO, sw, hr, ow)
		"surprised":
			_arm(ci, b, [0.86, 0.69, 0.94, 0.62, 0.89, 0.53], coat, skin, BRASS, "open", Vector2.ZERO, sw, hr, ow)

# ── El Sargento Mayor Casimiro Bombarda ──────────────────────────────
#
# Veterano corpulento a juego: casco de acero remachado con la estrella de
# laton y barboquejo, cejas de cepillo, nariz de patata, bigote de manillar con
# las puntas enroscadas y una cerilla mordida (apagada) en la comisura,
# capote oliva con insignias rojas, galones de ambar en la manga y medallas.

static func _figure_bombarda(ci: CanvasItem, b: Rect2, e: String, arms: bool) -> void:
	var h := b.size.y
	var ow := _ow(h)
	var sh := h * 0.03
	var skin := SKIN_BOMB
	var coat := COAT_BOMB
	var sw := h * 0.1
	var hr := h * 0.045
	# Cuello de toro y el capote.
	_shape(ci, _poly(b, [0.37, 0.54, 0.63, 0.54, 0.65, 0.64, 0.35, 0.64]), skin, ow)
	ci.draw_colored_polygon(_ell(_p(b, 0.5, 0.61), h * 0.08, h * 0.028, 14), skin.darkened(0.22))
	_shape(ci, _poly(b, [0.03, 1.0, 0.035, 0.74, 0.1, 0.66, 0.33, 0.615, 0.67, 0.615, 0.9, 0.66, 0.965, 0.74, 0.97, 1.0]), coat, ow, sh)
	# Las solapas con las insignias rojas.
	for s in [-1.0, 1.0]:
		var lap := _poly(b, [0.5 + s * 0.17, 0.615, 0.5, 0.668, 0.5 + s * 0.05, 0.722, 0.5 + s * 0.20, 0.655])
		_shape(ci, lap, coat.lightened(0.1), ow)
		_shape(ci, _poly(b, [0.5 + s * 0.15, 0.636, 0.5 + s * 0.09, 0.652, 0.5 + s * 0.1, 0.677, 0.5 + s * 0.16, 0.662]), COLLAR_TAB, ow * 0.7)
	for v in [0.735, 0.772]:
		_button(ci, _p(b, 0.5, v), h * 0.016, ow)
	# Dos medallas con su cinta.
	for i in 2:
		var u := 0.25 + 0.075 * float(i)
		var rib := Rect2(_p(b, u, 0.69) - Vector2(h * 0.026, 0), Vector2(h * 0.052, h * 0.03))
		_shape(ci, _rect_poly(rib), COLLAR_TAB if i == 0 else STEEL, ow * 0.7)
		ci.draw_line(Vector2(rib.get_center().x, rib.position.y), Vector2(rib.get_center().x, rib.end.y), AMBER, h * 0.01)
		if i == 0:
			_shape(ci, _ell(_p(b, u, 0.745), h * 0.022, h * 0.022, 14), BRASS, ow * 0.7)
		else:
			_star(ci, _p(b, u, 0.745), h * 0.027, BRASS, ow * 0.7)
	# El cinturon, que se curva sobre la barriga.
	_shape(ci, _poly(b, [0.036, 0.772, 0.5, 0.788, 0.964, 0.772, 0.966, 0.822, 0.5, 0.838, 0.034, 0.822]), LEATHER, ow, sh * 0.4)
	var bk := Rect2(_p(b, 0.5, 0.812) - Vector2(h * 0.045, h * 0.03), Vector2(h * 0.09, h * 0.06))
	_shape(ci, _rect_poly(bk), BRASS, ow * 0.8)
	_fill(ci, _rect_poly(bk.grow(-h * 0.015)), LEATHER.darkened(0.2))
	if arms:
		_arm(ci, b, [0.14, 0.675, 0.075, 0.755, 0.18, 0.80], coat, skin, coat.darkened(0.25), "fist", Vector2.ZERO, sw, hr, ow, true)
		if e == "worried":
			_arm(ci, b, [0.86, 0.68, 0.95, 0.52, 0.81, 0.37], coat, skin, coat.darkened(0.25), "fist", Vector2.ZERO, sw, hr, ow, true)
	# Orejas grandes y la cabeza: mandibula cuadrada.
	for s in [-1.0, 1.0]:
		_shape(ci, _ell(_p(b, 0.5, 0.425) + Vector2(s * h * 0.182, 0), h * 0.036, h * 0.05, 12), skin, ow * 0.9)
	var c := _p(b, 0.5, 0.385)
	var rx := h * 0.185
	var head := _ell(c, rx, h * 0.17, 18, PI, TAU)
	for q in [[1.0, 0.0], [0.98, 0.11], [0.84, 0.19], [0.5, 0.228], [-0.5, 0.228], [-0.84, 0.19], [-0.98, 0.11]]:
		head.append(c + Vector2(rx * float(q[0]), h * float(q[1])))
	_shape(ci, head, skin, ow, sh)
	# La barba de tres dias, mas oscura en la quijada.
	_fill_in(ci, _ell(_p(b, 0.5, 0.605), h * 0.15, h * 0.05, 18), head, Color(0.3, 0.2, 0.15, 0.14))
	# La cicatriz de la mejilla y los coloretes.
	ci.draw_line(_p(b, 0.335, 0.455), _p(b, 0.37, 0.505), skin.darkened(0.3), ow, true)
	for t in [0.33, 0.66]:
		var m := _p(b, 0.335, 0.455).lerp(_p(b, 0.37, 0.505), t)
		ci.draw_line(m + Vector2(-h * 0.009, h * 0.004), m + Vector2(h * 0.009, -h * 0.004), skin.darkened(0.3), ow * 0.7, true)
	for s in [-1.0, 1.0]:
		ci.draw_colored_polygon(_ell(_p(b, 0.5 + s * 0.155, 0.5), h * 0.032, h * 0.02, 12), CHEEK)
	# Ojos de parpado pesado (rien entornados) y cejas de cepillo.
	var pose := _eye_pose(e)
	for s in [-1.0, 1.0]:
		var ec := _p(b, 0.5 + s * 0.09, 0.42)
		if e == "happy":
			_eye_closed(ci, ec, h * 0.037, h * 0.042, ow)
		else:
			_eye(ci, ec, h * 0.037, h * 0.042, EYES_BOMB, pose, s, skin, ow, 0.24)
		_brow(ci, ec, h * 0.04, h * 0.042, s, e, MOUSTACHE.darkened(0.3), h * 0.036, ow)
	# Nariz de patata, colorada.
	_shape(ci, _ell(_p(b, 0.515, 0.472), h * 0.052, h * 0.042, 18), skin.lerp(Color("d0604e"), 0.35), ow, h * 0.012)
	ci.draw_circle(_p(b, 0.5, 0.46), h * 0.01, Color(1, 1, 1, 0.45))
	# El bigote de manillar con las puntas enroscadas.
	var mo := _poly(b, [0.5, 0.497, 0.6, 0.487, 0.70, 0.497, 0.78, 0.49, 0.83, 0.455, 0.825, 0.50, 0.76, 0.532,
		0.66, 0.542, 0.57, 0.537, 0.5, 0.522, 0.43, 0.537, 0.34, 0.542, 0.24, 0.532, 0.175, 0.50, 0.17, 0.455,
		0.22, 0.49, 0.30, 0.497, 0.40, 0.487])
	_shape(ci, mo, MOUSTACHE, ow, h * 0.014)
	for s in [-1.0, 1.0]:
		ci.draw_arc(_p(b, 0.5 + s * 0.315, 0.44), h * 0.016, 0.0, TAU, 10, INK, ow * 0.9, true)
		ci.draw_line(_p(b, 0.5 + s * 0.11, 0.507), _p(b, 0.5 + s * 0.18, 0.522), INK, ow * 0.6, true)
	_helmet(ci, b, h, ow, sh)
	if arms:
		_gesture_bombarda(ci, b, e, coat, skin, sw, hr, h, ow)
	_marks(ci, b, e, h, ow)

static func _helmet(ci: CanvasItem, b: Rect2, h: float, ow: float, sh: float) -> void:
	_shape(ci, _ell(_p(b, 0.5, 0.29), h * 0.27, h * 0.048, 24), HELMET.darkened(0.15), ow, h * 0.01)
	var dome := _ell(_p(b, 0.5, 0.29), h * 0.205, h * 0.2, 20, PI, TAU)
	_shape(ci, dome, HELMET, ow, sh)
	# La cresta del centro, la banda remachada y la estrella de laton.
	_fill_in(ci, _rect_poly(Rect2(_p(b, 0.5, 0.0) - Vector2(h * 0.026, 0), Vector2(h * 0.052, h * 0.29))), dome, HELMET.lightened(0.12))
	_fill_in(ci, _rect_poly(Rect2(_p(b, 0.0, 0.235), Vector2(b.size.x, h * 0.045))), dome, HELMET.darkened(0.1))
	_outline(ci, dome, ow)
	for i in 7:
		var u := 0.31 + 0.063 * float(i)
		if i == 3:
			continue
		ci.draw_circle(_p(b, u, 0.258), h * 0.011 + ow * 0.4, INK)
		ci.draw_circle(_p(b, u, 0.258), h * 0.011, BRASS)
	_star(ci, _p(b, 0.5, 0.2), h * 0.048, BRASS, ow * 0.8)

static func _gesture_bombarda(ci: CanvasItem, b: Rect2, e: String, coat: Color, skin: Color, sw: float, hr: float, h: float, ow: float) -> void:
	var cuff := coat.darkened(0.25)
	match e:
		"point":
			_arm(ci, b, [0.86, 0.68, 0.93, 0.58, 0.87, 0.47], coat, skin, cuff, "point", Vector2(1, -0.35), sw, hr, ow, true)
		"happy":
			_arm(ci, b, [0.86, 0.68, 0.95, 0.64, 0.89, 0.57], coat, skin, cuff, "thumb", Vector2.ZERO, sw, hr, ow, true)
		"salute":
			_arm(ci, b, [0.86, 0.68, 0.94, 0.52, 0.84, 0.385], coat, skin, cuff, "flat", Vector2.ZERO, sw, hr, ow, true)
		"angry":
			# El puno que tiembla.
			var f := _arm(ci, b, [0.86, 0.68, 0.95, 0.58, 0.90, 0.46], coat, skin, cuff, "fist", Vector2.ZERO, sw, hr, ow, true)
			for k in 2:
				var rr := hr * (1.7 + 0.55 * float(k))
				ci.draw_arc(f, rr, -PI * 0.95, -PI * 0.6, 6, INK, ow * 1.2, true)
				ci.draw_arc(f, rr, -PI * 0.4, -PI * 0.05, 6, INK, ow * 1.2, true)
		"surprised":
			_arm(ci, b, [0.86, 0.68, 0.94, 0.62, 0.89, 0.53], coat, skin, cuff, "open", Vector2.ZERO, sw, hr, ow, true)

# ── La boca ──────────────────────────────────────────────────────────

## La boca, en su propio nodo: es lo unico que se repinta mientras habla.
static func draw_mouth(ci: CanvasItem, area: Rect2, id: String, e: String, dir: int, open: bool) -> void:
	if area.size.x < 24.0 or area.size.y < 30.0:
		return
	var bw := 3.0 if UITheme.high_contrast else 2.0
	_mirror(ci, area, dir)
	_mouth_shape(ci, area.grow(-bw), id, e, open)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func _mouth_shape(ci: CanvasItem, b: Rect2, id: String, e: String, open: bool) -> void:
	var h := b.size.y
	var ow := _ow(h)
	var c := _p(b, 0.5, MOUTH_V_COMBAT if id == COMBAT else MOUTH_V_COLONY)
	var w := h * (0.07 if id == COMBAT else 0.07)
	if open:
		var m: PackedVector2Array
		match e:
			"surprised":
				m = _ell(c + Vector2(0, w * 0.2), w * 0.45, w * 0.62, 16)
			"worried":
				m = _rot(_ell(c + Vector2(0, w * 0.15), w * 0.62, w * 0.42, 16), c, 0.15)
			"angry":
				m = PackedVector2Array([c + Vector2(-w, -w * 0.35), c + Vector2(w, -w * 0.35), c + Vector2(w * 0.72, w * 0.6), c + Vector2(-w * 0.72, w * 0.6)])
			_:
				# Sonrisa abierta, un pelo torcida hacia la tarjeta.
				m = _rot(_ell(c + Vector2(0, -w * 0.15), w, w * 0.72, 18, 0.0, PI), c, -0.1)
		_fill(ci, m, MOUTH_IN)
		if e != "surprised":
			_fill_in(ci, _rect_poly(Rect2(c - Vector2(w * 1.2, w * 0.8), Vector2(w * 2.4, w * 0.62))), m, WHITE)
		if e == "angry":
			_fill_in(ci, _rect_poly(Rect2(c + Vector2(-w * 1.2, w * 0.38), Vector2(w * 2.4, w * 0.4))), m, WHITE)
		else:
			_fill_in(ci, _ell(c + Vector2(0, w * 0.62), w * 0.5, w * 0.3, 12), m, TONGUE)
		_outline(ci, m, ow * 0.9)
	else:
		match e:
			"surprised":
				_shape(ci, _ell(c + Vector2(0, w * 0.1), w * 0.26, w * 0.32, 12), MOUTH_IN, ow * 0.8)
			"worried":
				ci.draw_polyline(PackedVector2Array([c + Vector2(-w * 0.7, w * 0.15), c + Vector2(-w * 0.3, -w * 0.08),
					c + Vector2(w * 0.2, w * 0.18), c + Vector2(w * 0.65, -w * 0.05)]), INK, ow * 1.1, true)
			"angry":
				ci.draw_arc(c + Vector2(0, w * 0.75), w * 0.72, PI * 1.22, PI * 1.78, 10, INK, ow * 1.2, true)
			_:
				# Media sonrisa picara: la comisura de la tarjeta sube, con hoyuelo.
				ci.draw_polyline(PackedVector2Array([c + Vector2(-w * 0.72, -w * 0.02), c + Vector2(-w * 0.3, w * 0.24),
					c + Vector2(w * 0.25, w * 0.22), c + Vector2(w * 0.72, -w * 0.3)]), INK, ow * 0.9, true)
	if id == COMBAT:
		# La cerilla mordida, apagada, en la comisura.
		var a := c + Vector2(w * 0.7, w * 0.05)
		var z := c + Vector2(w * 2.1, -w * 0.4)
		_limb(ci, PackedVector2Array([a, z]), WOOD.lightened(0.15), h * 0.013, ow * 0.6)
		ci.draw_circle(z, h * 0.011 + ow * 0.5, INK)
		ci.draw_circle(z, h * 0.011, MATCH_TIP)

class _Mouth extends Control:
	## El InstructorBust padre (sin tipo: draw_mouth es suya, no de Control).
	var bust = null

	func _draw() -> void:
		if bust == null:
			return
		bust.draw_mouth(self, Rect2(Vector2.ZERO, size), bust.who, bust.expression, bust.facing, bust.mouth_open)
