extends Control
## Los instructores (feat/instructores, docs/23 §9): un busto de medio cuerpo
## que acompana a las tarjetas que le hablan al jugador.
##
##   * **Capitana Ada Remache** (`COLONY`), Capitana de Ingenieros: la colonia.
##     Tutorial guiado de construccion y consejos de economia y edificios.
##     Trenza, gorra de faena con gafas de aviador encima y un lapiz detras de
##     la oreja. Desde la piel dieselpunk (docs/21 §17) es un **grabado a dos
##     tintas, estilo cartel**: la figura en laton, las tallas y el fondo en
##     Pizarra, rayos Art Deco detras de la cabeza y un rayado en la sombra.
##     Nada de piel, mejillas ni colores de caricatura.
##   * **Sargento Mayor Casimiro Bombarda** (`COMBAT`): el combate. Combate
##     guiado, consejos de Tormenta, Impuesto, ejercito y misiones, y los partes
##     de guerra. Casco remachado, bigote de manillar, nariz de patata, medallas.
##
## Todo sale de _draw, sin imagenes (como PrologueEngraving y RegenciaSeal):
## escala sin pixelarse y no pesa en el APK. Seis expresiones (EXPRESSIONS) con
## su gesto de brazo. Coste: el cuerpo se pinta al cambiar de quien, expresion,
## tamano u orientacion, y Godot guarda las ordenes de dibujo; no hay _process.
## Mientras habla (speak) un Timer de ~0,1 s abre y cierra la boca, que es un
## hijo aparte (`Mouth`): solo se repinta la boca. Al callarse, el Timer se para.
##
## El marco sigue a UITheme (laton para Remache, peligro para Bombarda; borde
## mas grueso en alto contraste). La figura es una ilustracion con su propia
## tinta, como las laminas del prologo: no cambia con la paleta de daltonismo
## (no lleva informacion de color).
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

## Tinta de la ilustracion (no es interfaz: ver la cabecera).
const INK := Color(0.12, 0.09, 0.06)
const WHITE := Color(0.98, 0.96, 0.92)
const SKIN_BOMB := Color(0.89, 0.67, 0.52)
const CHEEK := Color(0.93, 0.48, 0.42, 0.45)
const MOUSTACHE := Color(0.33, 0.21, 0.12)
const UNIFORM_BOMB := Color(0.33, 0.38, 0.45)
const COLLAR_TAB := Color(0.66, 0.17, 0.12)
const HELMET := Color(0.37, 0.41, 0.31)
const MOUTH_IN := Color(0.45, 0.10, 0.10)
const TONGUE := Color(0.88, 0.42, 0.42)
const SWEAT := Color(0.55, 0.80, 0.95)

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

func _draw() -> void:
	draw_bust(self, Rect2(Vector2.ZERO, size), who, expression, facing)

## El busto entero en `area`: marco, figura y placa con el nombre. Estatica
## para las pruebas y las capturas.
static func draw_bust(ci: CanvasItem, area: Rect2, id: String, e: String, dir: int) -> void:
	if area.size.x < 24.0 or area.size.y < 30.0:
		return
	var h := area.size.y
	var border: Color = UITheme.DANGER.lightened(0.15) if id == COMBAT else UITheme.ACCENT
	var bw := 3.0 if UITheme.high_contrast else 2.0
	# Fondo del marco: la superficie. Esquinas de la piel (4 px, no redondas).
	var bg := StyleBoxFlat.new()
	bg.bg_color = UITheme.SURFACE.lightened(0.1) if id == COMBAT else ada_slate()
	bg.border_color = border
	bg.set_border_width_all(int(bw))
	bg.set_corner_radius_all(4)
	ci.draw_style_box(bg, area)
	if id == COMBAT:
		ci.draw_circle(area.position + Vector2(area.size.x * 0.5, h * 0.36), h * 0.30, Color(UITheme.ACCENT, 0.16))
	else:
		_poster_rays(ci, area.grow(-bw), _p(area, 0.5, 0.36), h)
	# La figura, espejada si mira a la izquierda.
	var fig := area.grow(-bw)
	_mirror(ci, area, dir)
	if id == COMBAT:
		_draw_bombarda(ci, fig, e)
	else:
		_draw_ada(ci, fig, e)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# La placa con el nombre corto.
	var plate := Rect2(area.position.x + bw, area.end.y - h * 0.17 - bw, area.size.x - bw * 2.0, h * 0.17)
	ci.draw_rect(plate, UITheme.HUD_BG)
	ci.draw_line(plate.position, Vector2(plate.end.x, plate.position.y), border, bw)
	var font: Font = UITheme.bold_font()
	if font != null:
		var fs := int(clampf(h * 0.085, 9.0, 16.0))
		var text := Tr.t(short_key(id))
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base_y: float = plate.position.y + plate.size.y * 0.5 + fs * 0.36
		ci.draw_string(font, Vector2(plate.position.x + maxf(2.0, (plate.size.x - tw) * 0.5), base_y),
			text, HORIZONTAL_ALIGNMENT_LEFT, plate.size.x - 4.0, fs, UITheme.TEXT_BRIGHT)

static func _mirror(ci: CanvasItem, area: Rect2, dir: int) -> void:
	if dir < 0:
		ci.draw_set_transform(Vector2(area.position.x * 2.0 + area.size.x, 0.0), 0.0, Vector2(-1, 1))
	else:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ── Utilidades ───────────────────────────────────────────────────────

## Punto (u, v) en [0, 1] dentro de `box`.
static func _p(box: Rect2, u: float, v: float) -> Vector2:
	return box.position + Vector2(u * box.size.x, v * box.size.y)

static func _ell(c: Vector2, rx: float, ry: float, n: int = 24, from := 0.0, to := TAU) -> PackedVector2Array:
	var out := PackedVector2Array()
	var full := is_equal_approx(to - from, TAU)
	var count := n if full else n + 1
	for i in count:
		var a := from + (to - from) * float(i) / float(n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out

## Relleno con contorno de tinta.
static func _shape(ci: CanvasItem, pts: PackedVector2Array, fill: Color, ow: float, ink: Color = INK) -> void:
	if pts.size() < 3:
		return
	ci.draw_colored_polygon(pts, fill)
	var line := pts.duplicate()
	line.append(pts[0])
	ci.draw_polyline(line, ink, ow, true)

static func _poly(box: Rect2, uv: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, uv.size(), 2):
		out.append(_p(box, float(uv[i]), float(uv[i + 1])))
	return out

## Un trazo grueso (manga, dedo) con contorno: dos lineas, la de tinta debajo.
static func _limb(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, ow: float, ink: Color = INK) -> void:
	ci.draw_polyline(pts, ink, w + ow * 2.0, true)
	ci.draw_polyline(pts, col, w, true)
	for p in pts:
		ci.draw_circle(p, w * 0.5, col)

# ── Comun ────────────────────────────────────────────────────────────

## Torso, cuello y hombros con su uniforme. Devuelve nada; el cuello va encima.
static func _torso(ci: CanvasItem, b: Rect2, skin: Color, cloth: Color, ow: float) -> void:
	_shape(ci, _poly(b, [0.44, 0.52, 0.56, 0.52, 0.57, 0.66, 0.43, 0.66]), skin, ow)
	_shape(ci, _poly(b, [0.02, 0.98, 0.06, 0.76, 0.24, 0.64, 0.40, 0.61, 0.60, 0.61, 0.76, 0.64, 0.94, 0.76, 0.98, 0.98]), cloth, ow)
	# El cuello de la guerrera: dos solapas.
	_shape(ci, _poly(b, [0.40, 0.61, 0.50, 0.72, 0.45, 0.76, 0.36, 0.63]), cloth.lightened(0.12), ow * 0.8)
	_shape(ci, _poly(b, [0.60, 0.61, 0.50, 0.72, 0.55, 0.76, 0.64, 0.63]), cloth.lightened(0.12), ow * 0.8)

## Ojos segun la expresion. `ex` separacion de cada ojo al centro (en u).
static func _eyes(ci: CanvasItem, b: Rect2, e: String, cy: float, ex: float, h: float, ow: float) -> void:
	for side in [-1.0, 1.0]:
		var c := _p(b, 0.5 + side * ex, cy)
		match e:
			"happy":
				ci.draw_arc(c + Vector2(0, h * 0.012), h * 0.028, PI * 1.1, PI * 1.9, 10, INK, ow * 1.3, true)
			"surprised":
				ci.draw_circle(c, h * 0.036, WHITE)
				ci.draw_arc(c, h * 0.036, 0.0, TAU, 18, INK, ow, true)
				ci.draw_circle(c, h * 0.012, INK)
			"angry":
				ci.draw_circle(c, h * 0.026, WHITE)
				ci.draw_circle(c + Vector2(h * 0.006, h * 0.004), h * 0.013, INK)
				# Parpado bajado: una raya de tinta sobre la pupila.
				ci.draw_line(c + Vector2(-h * 0.03, -h * 0.006), c + Vector2(h * 0.03, -h * 0.006), INK, ow * 1.2)
			_:
				ci.draw_circle(c, h * 0.028, WHITE)
				ci.draw_arc(c, h * 0.028, 0.0, TAU, 16, INK, ow * 0.8, true)
				# La pupila mira hacia la tarjeta (a la derecha antes del espejo).
				ci.draw_circle(c + Vector2(h * 0.009, h * 0.003), h * 0.013, INK)

## Cejas: `thick` grosor. Inclinacion por expresion (y del extremo de dentro y
## de fuera, en v).
static func _brows(ci: CanvasItem, b: Rect2, e: String, cy: float, ex: float, thick: float, col: Color) -> void:
	var inner := cy - 0.055
	var outer := cy - 0.055
	match e:
		"angry":
			inner = cy - 0.035
			outer = cy - 0.07
		"worried":
			inner = cy - 0.075
			outer = cy - 0.045
		"surprised":
			inner = cy - 0.085
			outer = cy - 0.08
		"happy", "salute":
			inner = cy - 0.065
			outer = cy - 0.06
	for side in [-1.0, 1.0]:
		var a := _p(b, 0.5 + side * (ex * 0.35), inner)
		var o := _p(b, 0.5 + side * (ex * 1.55), outer)
		ci.draw_line(a, o, col, thick, true)
		ci.draw_circle(a, thick * 0.5, col)
		ci.draw_circle(o, thick * 0.5, col)

## Los gestos del brazo derecho (el del lado al que mira).
static func _gesture(ci: CanvasItem, b: Rect2, e: String, cloth: Color, skin: Color, h: float, ow: float,
		ink: Color = INK, drop: Color = SWEAT) -> void:
	var sleeve := h * 0.085
	match e:
		"point":
			_limb(ci, _poly(b, [0.86, 0.80, 0.90, 0.62, 0.92, 0.52]), cloth, sleeve, ow, ink)
			ci.draw_circle(_p(b, 0.925, 0.48), h * 0.036, skin)
			ci.draw_arc(_p(b, 0.925, 0.48), h * 0.036, 0.0, TAU, 14, ink, ow, true)
			# El indice, hacia la tarjeta.
			_limb(ci, _poly(b, [0.94, 0.47, 0.99, 0.45]), skin, h * 0.018, ow * 0.7, ink)
		"salute":
			_limb(ci, _poly(b, [0.86, 0.82, 0.95, 0.52, 0.78, 0.30]), cloth, sleeve, ow, ink)
			# La mano plana en la visera.
			var hand := _poly(b, [0.78, 0.27, 0.62, 0.22, 0.61, 0.26, 0.77, 0.33])
			_shape(ci, hand, skin, ow, ink)
		"happy":
			# Pulgar arriba.
			_limb(ci, _poly(b, [0.88, 0.96, 0.84, 0.72]), cloth, sleeve, ow, ink)
			var f := _p(b, 0.83, 0.66)
			ci.draw_circle(f, h * 0.04, skin)
			ci.draw_arc(f, h * 0.04, 0.0, TAU, 14, ink, ow, true)
			_limb(ci, PackedVector2Array([f + Vector2(-h * 0.01, -h * 0.03), f + Vector2(-h * 0.012, -h * 0.075)]), skin, h * 0.022, ow * 0.7, ink)
		"angry":
			# El puno en alto.
			_limb(ci, _poly(b, [0.88, 0.94, 0.92, 0.70, 0.90, 0.58]), cloth, sleeve, ow, ink)
			var f := _p(b, 0.90, 0.53)
			ci.draw_circle(f, h * 0.042, skin)
			ci.draw_arc(f, h * 0.042, 0.0, TAU, 14, ink, ow, true)
			ci.draw_line(f + Vector2(-h * 0.03, -h * 0.005), f + Vector2(h * 0.02, -h * 0.005), ink, ow * 0.7)
		"worried":
			# Una gota de sudor en la sien.
			var d := _p(b, 0.74, 0.30)
			var tear := PackedVector2Array([d + Vector2(0, -h * 0.04), d + Vector2(h * 0.016, -h * 0.005), d + Vector2(0, h * 0.012), d + Vector2(-h * 0.016, -h * 0.005)])
			_shape(ci, tear, drop, ow * 0.7, ink)
		"surprised":
			# Dos rayas de sorpresa sobre la cabeza.
			for i in 3:
				var a := _p(b, 0.80 + 0.06 * float(i), 0.10 + 0.03 * float(i))
				ci.draw_line(a, a + Vector2(h * 0.03, -h * 0.03), ink, ow * 1.2, true)

# ── La Capitana Ada Remache ──────────────────────────────────────────

## Las dos tintas del grabado de la Capitana: laton (la figura) y Pizarra
## (fondo y tallas). Siguen a UITheme (alto contraste incluido).
static func ada_brass() -> Color:
	return UITheme.ACCENT

static func ada_slate() -> Color:
	return UITheme.SURFACE.darkened(0.12)

## Rayos Art Deco de cartel detras de la cabeza: lineas finas de laton.
static func _poster_rays(ci: CanvasItem, box: Rect2, c: Vector2, h: float) -> void:
	var col := Color(ada_brass(), 0.22)
	var reach := h * 1.2
	for i in 14:
		var a := PI + PI * (float(i) + 0.5) / 14.0
		var tip := c + Vector2(cos(a), sin(a)) * reach
		# Recortado a la caja: los rayos no salen del marco.
		var t := 1.0
		if tip.y < box.position.y:
			t = minf(t, (c.y - box.position.y) / maxf(0.001, c.y - tip.y))
		if tip.x < box.position.x:
			t = minf(t, (c.x - box.position.x) / maxf(0.001, c.x - tip.x))
		if tip.x > box.end.x:
			t = minf(t, (box.end.x - c.x) / maxf(0.001, tip.x - c.x))
		ci.draw_line(c + (tip - c) * 0.32, c + (tip - c) * t, col, maxf(1.0, h * 0.012), true)
	ci.draw_arc(c, h * 0.27, PI, TAU, 32, col, maxf(1.0, h * 0.01), true)

## Ojos tallados (dos tintas): rayas y puntos de Pizarra sobre el laton.
static func _eyes_engraved(ci: CanvasItem, b: Rect2, e: String, cy: float, ex: float, h: float, ow: float, ink: Color) -> void:
	for side in [-1.0, 1.0]:
		var c := _p(b, 0.5 + side * ex, cy)
		match e:
			"happy":
				ci.draw_arc(c + Vector2(0, h * 0.012), h * 0.028, PI * 1.1, PI * 1.9, 10, ink, ow * 1.4, true)
			"surprised":
				ci.draw_arc(c, h * 0.034, 0.0, TAU, 18, ink, ow * 1.1, true)
				ci.draw_circle(c, h * 0.012, ink)
			"angry":
				ci.draw_circle(c + Vector2(h * 0.006, h * 0.006), h * 0.016, ink)
				ci.draw_line(c + Vector2(-h * 0.032, -h * 0.008), c + Vector2(h * 0.03, -h * 0.004), ink, ow * 1.3)
			_:
				# Mira hacia la tarjeta (a la derecha antes del espejo).
				ci.draw_colored_polygon(_ell(c + Vector2(h * 0.006, 0), h * 0.017, h * 0.022, 12), ink)

static func _draw_ada(ci: CanvasItem, b: Rect2, e: String) -> void:
	var h := b.size.y
	var ow := maxf(1.0, h * 0.014)
	var B := ada_brass()
	var S := ada_slate()
	var hatch := maxf(1.0, h * 0.009)
	# Torso y cuello: una silueta de laton con el filo tallado.
	_shape(ci, _poly(b, [0.44, 0.52, 0.56, 0.52, 0.57, 0.66, 0.43, 0.66]), B, ow, S)
	_shape(ci, _poly(b, [0.02, 0.98, 0.06, 0.76, 0.24, 0.64, 0.40, 0.61, 0.60, 0.61, 0.76, 0.64, 0.94, 0.76, 0.98, 0.98]), B, ow, S)
	# Las solapas de la guerrera y la botonadura, solo como tallas.
	ci.draw_polyline(_poly(b, [0.36, 0.63, 0.45, 0.76, 0.50, 0.72, 0.55, 0.76, 0.64, 0.63]), S, ow * 1.2, true)
	ci.draw_line(_p(b, 0.50, 0.72), _p(b, 0.50, 0.98), S, ow, true)
	for v in [0.82, 0.91]:
		for u in [0.45, 0.55]:
			ci.draw_circle(_p(b, u, v), h * 0.013, S)
	# Rayado de grabado en la sombra del hombro y bajo la barbilla.
	for i in 6:
		var u0 := 0.08 + 0.045 * float(i)
		ci.draw_line(_p(b, u0, 0.97), _p(b, u0 + 0.07, 0.80), S, hatch, true)
	for i in 3:
		var v := 0.55 + 0.035 * float(i)
		ci.draw_line(_p(b, 0.445, v), _p(b, 0.48, v), S, hatch, true)
	# La trenza, por delante del hombro: eslabones de laton tallados.
	for i in 6:
		var t := float(i) / 5.0
		var c := _p(b, 0.30 - 0.05 * t, 0.42 + 0.30 * t)
		_shape(ci, _ell(c, h * (0.048 - 0.008 * t), h * 0.040, 14), B, ow * 0.9, S)
	var knot := _p(b, 0.25, 0.75)
	for side in [-1.0, 1.0]:
		_shape(ci, PackedVector2Array([knot, knot + Vector2(side * h * 0.05, -h * 0.025),
			knot + Vector2(side * h * 0.05, h * 0.025)]), S, ow * 0.7, B)
	# La cabeza y la oreja.
	_shape(ci, _ell(_p(b, 0.5, 0.40), h * 0.17, h * 0.19, 30), B, ow, S)
	_shape(ci, _ell(_p(b, 0.70, 0.41), h * 0.025, h * 0.04, 12), B, ow * 0.8, S)
	# El lapiz detras de la oreja: una talla.
	ci.draw_line(_p(b, 0.66, 0.31), _p(b, 0.78, 0.40), S, h * 0.016, true)
	# Sombra de la cara (el lado de lejos), en rayado corto.
	for i in 3:
		var v := 0.38 + 0.04 * float(i)
		ci.draw_line(_p(b, 0.345, v), _p(b, 0.375, v + 0.02), S, hatch, true)
	# El flequillo bajo la gorra.
	_shape(ci, _poly(b, [0.33, 0.33, 0.36, 0.25, 0.64, 0.25, 0.68, 0.33, 0.60, 0.29, 0.52, 0.32, 0.44, 0.28, 0.38, 0.32]), B, ow, S)
	_eyes_engraved(ci, b, e, 0.38, 0.075, h, ow, S)
	_brows(ci, b, e, 0.38, 0.075, h * 0.014, S)
	# La nariz: una sola talla.
	ci.draw_polyline(_poly(b, [0.515, 0.40, 0.53, 0.445, 0.505, 0.455]), S, ow, true)
	# La gorra de faena: laton con la cinta rayada y la visera en Pizarra
	# maciza (el contraste del cartel).
	_shape(ci, _poly(b, [0.32, 0.27, 0.35, 0.15, 0.50, 0.11, 0.66, 0.14, 0.70, 0.27]), B, ow, S)
	for i in 4:
		var u := 0.38 + 0.07 * float(i)
		ci.draw_line(_p(b, u, 0.235), _p(b, u + 0.03, 0.265), S, hatch, true)
	_shape(ci, _poly(b, [0.48, 0.27, 0.70, 0.26, 0.80, 0.29, 0.70, 0.31, 0.50, 0.30]), S, ow * 0.8, S)
	# Las gafas de aviador sobre la gorra: aros tallados con la lente de laton.
	ci.draw_line(_p(b, 0.33, 0.20), _p(b, 0.69, 0.20), S, h * 0.022)
	for u in [0.43, 0.57]:
		var g := _p(b, u, 0.195)
		ci.draw_circle(g, h * 0.044, S)
		ci.draw_circle(g, h * 0.028, B)
		ci.draw_arc(g + Vector2(-h * 0.006, -h * 0.006), h * 0.014, PI * 1.1, PI * 1.6, 6, S, ow, true)
	_gesture(ci, b, e, B, B, h, ow, S, S)

# ── El Sargento Mayor Casimiro Bombarda ──────────────────────────────

static func _draw_bombarda(ci: CanvasItem, b: Rect2, e: String) -> void:
	var h := b.size.y
	var ow := maxf(1.0, h * 0.012)
	_torso(ci, b, SKIN_BOMB, UNIFORM_BOMB, ow)
	# Las insignias rojas del cuello y dos medallas.
	_shape(ci, _poly(b, [0.37, 0.64, 0.43, 0.66, 0.42, 0.70, 0.36, 0.68]), COLLAR_TAB, ow * 0.7)
	_shape(ci, _poly(b, [0.63, 0.64, 0.57, 0.66, 0.58, 0.70, 0.64, 0.68]), COLLAR_TAB, ow * 0.7)
	for i in 2:
		var u := 0.30 + 0.07 * float(i)
		ci.draw_rect(Rect2(_p(b, u - 0.02, 0.76), Vector2(b.size.x * 0.04, h * 0.03)), COLLAR_TAB if i == 0 else UITheme.INFO)
		ci.draw_circle(_p(b, u, 0.82), h * 0.02, UITheme.ACCENT)
		ci.draw_arc(_p(b, u, 0.82), h * 0.02, 0.0, TAU, 12, INK, ow * 0.7, true)
	ci.draw_circle(_p(b, 0.5, 0.84), h * 0.013, UITheme.ACCENT)
	ci.draw_circle(_p(b, 0.5, 0.93), h * 0.013, UITheme.ACCENT)
	# La cabeza: mandibula cuadrada.
	var c := _p(b, 0.5, 0.36)
	var rx := h * 0.18
	var head := _ell(c, rx, h * 0.16, 16, PI, TAU)
	head.append(c + Vector2(rx * 1.02, h * 0.10))
	head.append(c + Vector2(rx * 0.70, h * 0.20))
	head.append(c + Vector2(-rx * 0.70, h * 0.20))
	head.append(c + Vector2(-rx * 1.02, h * 0.10))
	_shape(ci, head, SKIN_BOMB, ow)
	_shape(ci, _ell(_p(b, 0.72, 0.40), h * 0.026, h * 0.042, 12), SKIN_BOMB, ow * 0.8)
	_eyes(ci, b, e, 0.37, 0.08, h, ow)
	_brows(ci, b, e, 0.37, 0.08, h * 0.03, MOUSTACHE)
	# Nariz de patata, colorada.
	_shape(ci, _ell(_p(b, 0.52, 0.44), h * 0.045, h * 0.036, 16), SKIN_BOMB.lerp(CHEEK, 0.35), ow)
	# El bigote de manillar, con las puntas enroscadas.
	var m := PackedVector2Array()
	for uv in [[0.50, 0.475], [0.60, 0.465], [0.70, 0.48], [0.76, 0.455], [0.78, 0.43], [0.80, 0.46], [0.74, 0.51],
			[0.62, 0.51], [0.50, 0.495], [0.38, 0.51], [0.26, 0.51], [0.20, 0.46], [0.22, 0.43], [0.24, 0.455], [0.30, 0.48], [0.40, 0.465]]:
		m.append(_p(b, uv[0], uv[1]))
	_shape(ci, m, MOUSTACHE, ow)
	ci.draw_arc(_p(b, 0.785, 0.425), h * 0.015, 0.0, TAU, 10, MOUSTACHE.darkened(0.3), ow, true)
	ci.draw_arc(_p(b, 0.215, 0.425), h * 0.015, 0.0, TAU, 10, MOUSTACHE.darkened(0.3), ow, true)
	# El barboquejo del casco, por los lados de la cara.
	ci.draw_line(_p(b, 0.31, 0.30), _p(b, 0.36, 0.53), INK.lightened(0.15), ow * 1.4)
	ci.draw_line(_p(b, 0.69, 0.30), _p(b, 0.64, 0.53), INK.lightened(0.15), ow * 1.4)
	# El casco remachado: ala ancha y copa, con el emblema de laton.
	_shape(ci, _ell(_p(b, 0.5, 0.27), h * 0.26, h * 0.04, 24), HELMET.darkened(0.1), ow)
	var dome := _ell(_p(b, 0.5, 0.26), h * 0.19, h * 0.16, 18, PI, TAU)
	_shape(ci, dome, HELMET, ow)
	for i in 5:
		var a := PI + PI * (0.15 + 0.175 * float(i))
		ci.draw_circle(_p(b, 0.5, 0.26) + Vector2(cos(a) * h * 0.15, sin(a) * h * 0.12), h * 0.008, UITheme.ACCENT.darkened(0.2))
	var star := _p(b, 0.5, 0.18)
	var sp := PackedVector2Array()
	for i in 10:
		var r := h * (0.03 if i % 2 == 0 else 0.013)
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		sp.append(star + Vector2(cos(a), sin(a)) * r)
	_shape(ci, sp, UITheme.ACCENT, ow * 0.6)
	_gesture(ci, b, e, UNIFORM_BOMB, SKIN_BOMB, h, ow)

## La boca, en su propio nodo: es lo unico que se repinta mientras habla.
static func draw_mouth(ci: CanvasItem, area: Rect2, id: String, e: String, dir: int, open: bool) -> void:
	if area.size.x < 24.0 or area.size.y < 30.0:
		return
	var bw := 3.0 if UITheme.high_contrast else 2.0
	var b := area.grow(-bw)
	var h := b.size.y
	var ow := maxf(1.0, h * 0.012)
	_mirror(ci, area, dir)
	var c := _p(b, 0.5, 0.505) if id == COLONY else _p(b, 0.5, 0.535)
	var w := h * (0.06 if id == COLONY else 0.07)
	if id == COLONY:
		_mouth_engraved(ci, c, w, e, ow, open)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if open:
		match e:
			"surprised", "worried":
				var o := _ell(c, w * 0.5, w * 0.6, 14)
				_shape(ci, o, MOUTH_IN, ow)
			"angry":
				var r := _poly(Rect2(c - Vector2(w, w * 0.45), Vector2(w * 2.0, w * 0.9)), [0.0, 0.0, 1.0, 0.0, 0.9, 1.0, 0.1, 1.0])
				_shape(ci, r, MOUTH_IN, ow)
				ci.draw_line(c + Vector2(-w * 0.85, -w * 0.2), c + Vector2(w * 0.85, -w * 0.2), WHITE, ow * 1.4)
			_:
				var d := _ell(c, w, w * 0.75, 16, 0.0, PI)
				d.append(c + Vector2(-w, 0))
				_shape(ci, d, MOUTH_IN, ow)
				ci.draw_colored_polygon(_ell(c + Vector2(0, w * 0.45), w * 0.5, w * 0.22, 10), TONGUE)
	else:
		match e:
			"surprised":
				ci.draw_arc(c, w * 0.3, 0.0, TAU, 12, INK, ow * 1.2, true)
			"worried":
				ci.draw_polyline(PackedVector2Array([c + Vector2(-w * 0.7, w * 0.1), c + Vector2(-w * 0.25, -w * 0.12),
					c + Vector2(w * 0.25, w * 0.12), c + Vector2(w * 0.7, -w * 0.1)]), INK, ow * 1.3, true)
			"angry":
				ci.draw_line(c + Vector2(-w * 0.7, w * 0.1), c + Vector2(w * 0.7, w * 0.1), INK, ow * 1.5, true)
			_:
				ci.draw_arc(c + Vector2(0, -w * 0.3), w * 0.8, PI * 0.15, PI * 0.85, 12, INK, ow * 1.4, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## La boca de la Capitana, tallada en Pizarra sobre el laton (sin rojos).
static func _mouth_engraved(ci: CanvasItem, c: Vector2, w: float, e: String, ow: float, open: bool) -> void:
	var S := ada_slate()
	var B := ada_brass()
	if open:
		match e:
			"surprised", "worried":
				ci.draw_colored_polygon(_ell(c, w * 0.45, w * 0.55, 14), S)
			"angry":
				ci.draw_colored_polygon(_poly(Rect2(c - Vector2(w, w * 0.45), Vector2(w * 2.0, w * 0.9)),
					[0.0, 0.0, 1.0, 0.0, 0.9, 1.0, 0.1, 1.0]), S)
				ci.draw_line(c + Vector2(-w * 0.8, -w * 0.15), c + Vector2(w * 0.8, -w * 0.15), B, ow)
			_:
				var d := _ell(c, w, w * 0.75, 16, 0.0, PI)
				d.append(c + Vector2(-w, 0))
				ci.draw_colored_polygon(d, S)
		return
	match e:
		"surprised":
			ci.draw_arc(c, w * 0.3, 0.0, TAU, 12, S, ow * 1.3, true)
		"worried":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-w * 0.7, w * 0.1), c + Vector2(-w * 0.25, -w * 0.12),
				c + Vector2(w * 0.25, w * 0.12), c + Vector2(w * 0.7, -w * 0.1)]), S, ow * 1.4, true)
		"angry":
			ci.draw_line(c + Vector2(-w * 0.7, w * 0.1), c + Vector2(w * 0.7, w * 0.1), S, ow * 1.6, true)
		_:
			ci.draw_arc(c + Vector2(0, -w * 0.3), w * 0.8, PI * 0.15, PI * 0.85, 12, S, ow * 1.5, true)

class _Mouth extends Control:
	## El InstructorBust padre (sin tipo: draw_mouth es suya, no de Control).
	var bust = null

	func _draw() -> void:
		if bust == null:
			return
		bust.draw_mouth(self, Rect2(Vector2.ZERO, size), bust.who, bust.expression, bust.facing, bust.mouth_open)
