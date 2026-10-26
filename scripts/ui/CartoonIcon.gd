extends Control
## Iconos de interfaz de la piel dieselpunk "D · Mezcla sobria" (docs/21 §17):
## iconos de LINEA, trazo grueso de puntas redondas, en uno o dos tonos de la
## paleta (el claro del texto, o la tinta sobre laton, y un detalle de laton).
## El color de un recurso solo aparece como acento pequeno (el corte de los
## tablones, el brillo del lingote). Antes eran formas gordas de juguete y de
## colores; el nombre de la clase se queda (docs/28 §8).
##
## Un icono = un id de GLYPHS. Se dibuja en una caja de 24 x 24 unidades (la
## de la maqueta, conceptos-dieselpunk.html) y se escala al tamano del Control.
## Los recursos y las unidades NO van aqui: tienen sus PNG (UITheme.icon_texture
## / unit_icon), que tools/gen_resource_icons.gd dibuja con el mismo lenguaje.
##
## Coste: draw_polyline / draw_arc / draw_circle, sin texturas ni shaders. Sin
## _process ni animacion: se pinta al cambiar de id, color o tamano, y Godot
## guarda las ordenes de dibujo.

const GLYPHS := ["build", "army", "missions", "market", "research", "help", "menu",
	"settings", "upgrade", "move", "demolish", "close", "lock", "star", "clock",
	"sound", "music", "screen", "controls", "access", "game", "anchor", "plane",
	"tank", "raid", "check", "storm", "plus", "minus", "back", "next", "workers_off", "sun", "wrench",
	# Materiales del taller (feat/recetas-tarjetas): no tienen PNG como los
	# recursos; la tarjeta de receta los pide con CartoonTheme.res_glyph().
	"mat_planks", "mat_ingots", "mat_beams", "mat_fuel"]

## Tinta de la piel (CartoonTheme.INK, Pizarra muy oscura). La usan quienes
## dibujan sobre laton; los iconos de linea la toman del boton que los lleva.
const INK := Color("13171b")

## Grosor del trazo en unidades de la caja de 24 (la maqueta usa 2).
const STROKE := 2.2

var glyph := "build":
	set(v):
		glyph = v
		queue_redraw()
## Color del trazo. Sin fijar, el claro del texto de `role` (y el detalle en
## laton). Fijado, trazo y detalle van de ese color (sobre un boton de laton,
## la tinta).
var tint := Color(0, 0, 0, 0):
	set(v):
		tint = v
		queue_redraw()
## De donde toma el color de serie: "window" (ventanas; en el tema claro, la
## tinta) o "hud" (siempre oscuro).
var role := "window":
	set(v):
		role = v
		queue_redraw()
## Se conserva por compatibilidad (los iconos de juguete llevaban contorno de
## tinta); los de linea no lo usan.
var outlined := true

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

static func make(id: String, px: float, color: Color = Color(0, 0, 0, 0), role_s: String = "window") -> Control:
	var icon = load("res://scripts/ui/CartoonIcon.gd").new()
	icon.glyph = id
	icon.tint = color
	icon.role = role_s
	icon.custom_minimum_size = Vector2(px, px)
	icon.size = Vector2(px, px)
	return icon

func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 1.0:
		return
	var off := (size - Vector2(s, s)) * 0.5
	draw_glyph(self, Rect2(off, Vector2(s, s)), glyph, tint, outlined, role)

# ── Primitivas (unidades de la caja de 24) ─────────────────────────────

static func _q(r: Rect2, x: float, y: float) -> Vector2:
	return r.position + Vector2(x, y) * (r.size.x / 24.0)

static func _k(r: Rect2) -> float:
	return r.size.x / 24.0

## Ancho del trazo en pixeles: nunca por debajo de 1,5 px (a 16 px se leen).
static func _w(r: Rect2, mult: float = 1.0) -> float:
	return maxf(1.5, STROKE * _k(r) * mult)

## Polilinea con puntas y codos redondos (un circulo en cada vertice).
static func _pl(ci: CanvasItem, r: Rect2, uv: Array, col: Color, closed := false, mult := 1.0) -> void:
	var pts := PackedVector2Array()
	for i in range(0, uv.size(), 2):
		pts.append(_q(r, float(uv[i]), float(uv[i + 1])))
	if closed and pts.size() > 2:
		pts.append(pts[0])
	var w := _w(r, mult)
	ci.draw_polyline(pts, col, w, true)
	for p in pts:
		ci.draw_circle(p, w * 0.5, col, true, -1.0, true)

## Relleno plano (las siluetas de acento, siempre con poca opacidad o pequenas).
static func _fill(ci: CanvasItem, r: Rect2, uv: Array, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(0, uv.size(), 2):
		pts.append(_q(r, float(uv[i]), float(uv[i + 1])))
	if pts.size() >= 3 and Geometry2D.triangulate_polygon(pts).size() > 0:
		ci.draw_colored_polygon(pts, col)

static func _ring(ci: CanvasItem, r: Rect2, cx: float, cy: float, rad: float, col: Color, mult := 1.0) -> void:
	ci.draw_arc(_q(r, cx, cy), rad * _k(r), 0.0, TAU, 40, col, _w(r, mult), true)

static func _dot(ci: CanvasItem, r: Rect2, cx: float, cy: float, rad: float, col: Color) -> void:
	ci.draw_circle(_q(r, cx, cy), maxf(1.0, rad * _k(r)), col, true, -1.0, true)

## Arco abierto con las puntas redondas. Angulos de Godot (0 a la derecha, PI/2
## abajo).
static func _arc(ci: CanvasItem, r: Rect2, cx: float, cy: float, rad: float, a0: float, a1: float, col: Color, mult := 1.0) -> void:
	var c := _q(r, cx, cy)
	var rr := rad * _k(r)
	var w := _w(r, mult)
	ci.draw_arc(c, rr, a0, a1, 28, col, w, true)
	ci.draw_circle(c + Vector2(cos(a0), sin(a0)) * rr, w * 0.5, col, true, -1.0, true)
	ci.draw_circle(c + Vector2(cos(a1), sin(a1)) * rr, w * 0.5, col, true, -1.0, true)

## Puntos de una elipse (en unidades), para _pl / _fill.
static func _ell(cx: float, cy: float, rx: float, ry: float, a0 := 0.0, a1 := TAU, n := 24) -> Array:
	var out := []
	for i in n + 1:
		var a := a0 + (a1 - a0) * float(i) / float(n)
		out.append(cx + cos(a) * rx)
		out.append(cy + sin(a) * ry)
	return out

# ── Los iconos ─────────────────────────────────────────────────────────

## El claro del texto de `role_s` (o la tinta, en el tema claro de las ventanas).
static func default_ink(role_s: String = "window") -> Color:
	return CartoonTheme.text(role_s)

## El laton del detalle.
static func default_accent() -> Color:
	return CartoonTheme.sem("ACCENT")

## Pinta el icono `id` dentro de `r` (cuadrado). Estatico: lo usan tambien
## los botones sin crear un nodo por icono.
static func draw_glyph(ci: CanvasItem, r: Rect2, id: String, tint: Color = Color(0, 0, 0, 0),
		_ink: bool = true, role_s: String = "window") -> void:
	var has_t := tint.a > 0.0
	var m: Color = tint if has_t else default_ink(role_s)
	var a: Color = tint if has_t else default_accent()
	var soft := Color(a, 0.28)
	match id:
		"build":
			# Martillo: cabeza en bloque y mango en diagonal.
			_fill(ci, r, [13, 4, 17.5, 3, 21.5, 7, 20.5, 11.5, 18, 9, 16.2, 10.8, 12.5, 7, 14.3, 5.2], soft)
			_pl(ci, r, [13, 4, 17.5, 3, 21.5, 7, 20.5, 11.5, 18, 9, 16.2, 10.8, 12.5, 7, 14.3, 5.2], m, true)
			_pl(ci, r, [12.5, 7, 3.6, 15.9, 3.6, 18, 6, 20.4, 8.1, 20.4, 17, 11.5], m)
		"army":
			# Casco: cupula, ala y las nervaduras de laton.
			_pl(ci, r, _ell(12, 15, 7.5, 7, PI, TAU), m)
			_pl(ci, r, [2.5, 15, 21.5, 15, 21.5, 18, 2.5, 18], m, true)
			_pl(ci, r, [12, 8.5, 12, 12], a)
			_pl(ci, r, [9, 9.6, 9, 12], a)
			_pl(ci, r, [15, 9.6, 15, 12], a)
		"missions":
			# Banderin en su mastil.
			_fill(ci, r, [5, 4, 17.5, 4, 15, 8, 17.5, 12, 5, 12], soft)
			_pl(ci, r, [5, 21, 5, 3.5], m)
			_pl(ci, r, [5, 4, 17.5, 4, 15, 8, 17.5, 12, 5, 12], m)
		"market":
			# Balanza: astil, fiel y dos platillos.
			_pl(ci, r, [12, 4, 12, 20], m)
			_pl(ci, r, [8, 20, 16, 20], m)
			_pl(ci, r, [4.5, 7, 19.5, 7], m)
			for cx in [4.5, 19.5]:
				var pan := [cx, 7, cx - 2.5, 13] + _ell(cx, 13, 2.5, 2.5, PI, 0.0, 10) + [cx, 7]
				_fill(ci, r, [cx - 2.5, 13] + _ell(cx, 13, 2.5, 2.5, PI, 0.0, 10), soft)
				_pl(ci, r, pan, m)
		"research":
			# Matraz con su liquido (el liquido, en laton).
			_fill(ci, r, [7.4, 15, 16.6, 15, 19, 18.4, 18.6, 20.2, 17.2, 21, 6.8, 21, 5.4, 20.2, 5, 18.4], soft)
			_pl(ci, r, [9, 3, 15, 3], m)
			_pl(ci, r, [10, 3, 10, 9.5, 5, 18.2, 5.4, 20.2, 6.8, 21, 17.2, 21, 18.6, 20.2, 19, 18.2, 14, 9.5, 14, 3], m)
			_pl(ci, r, [7.4, 15, 16.6, 15], a)
		"help":
			_ring(ci, r, 12, 12, 9, m)
			_arc(ci, r, 12.1, 9.6, 2.8, PI, TAU + 0.55, a)
			_pl(ci, r, [14.4, 11.2, 12.4, 12.6, 12, 13.6, 12, 14.2], a)
			_dot(ci, r, 12, 17.3, 1.4, a)
		"menu":
			for y in [6.5, 12.0, 17.5]:
				_pl(ci, r, [4, y, 20, y], m)
		"settings":
			# Engranaje: cubo de laton, aro y ocho dientes.
			_ring(ci, r, 12, 12, 3, a)
			_ring(ci, r, 12, 12, 6.5, m)
			for i in 8:
				var ang := TAU * float(i) / 8.0
				var d := Vector2(cos(ang), sin(ang))
				_pl(ci, r, [12 + d.x * 6.8, 12 + d.y * 6.8, 12 + d.x * 9.4, 12 + d.y * 9.4], m)
		"upgrade":
			# Flecha arriba sobre su base.
			_pl(ci, r, [12, 19, 12, 5], m)
			_pl(ci, r, [6.5, 10.5, 12, 5, 17.5, 10.5], m)
			_pl(ci, r, [6, 21, 18, 21], a)
		"move":
			_pl(ci, r, [12, 2.8, 12, 21.2], m)
			_pl(ci, r, [2.8, 12, 21.2, 12], m)
			_pl(ci, r, [9, 5.8, 12, 2.8, 15, 5.8], m)
			_pl(ci, r, [9, 18.2, 12, 21.2, 15, 18.2], m)
			_pl(ci, r, [5.8, 9, 2.8, 12, 5.8, 15], m)
			_pl(ci, r, [18.2, 9, 21.2, 12, 18.2, 15], m)
			_dot(ci, r, 12, 12, 1.6, a)
		"demolish":
			# Cubo de derribo: tapa, asa y dos vetas.
			_pl(ci, r, [4, 7, 20, 7], m)
			_pl(ci, r, [9.5, 7, 9.5, 4, 14.5, 4, 14.5, 7], m)
			_pl(ci, r, [6, 7, 7, 20.5, 17, 20.5, 18, 7], m)
			_pl(ci, r, [10, 11, 10, 17], a)
			_pl(ci, r, [14, 11, 14, 17], a)
		"close":
			_pl(ci, r, [6, 6, 18, 18], m, false, 1.1)
			_pl(ci, r, [18, 6, 6, 18], m, false, 1.1)
		"lock":
			_fill(ci, r, [5, 10.5, 19, 10.5, 19, 20.5, 5, 20.5], soft)
			_pl(ci, r, [5, 10.5, 19, 10.5, 19, 20.5, 5, 20.5], m, true)
			_pl(ci, r, [8, 10.5, 8, 7.5], m)
			_arc(ci, r, 12, 7.5, 4, PI, TAU, m)
			_pl(ci, r, [16, 7.5, 16, 10.5], m)
			_pl(ci, r, [12, 14.5, 12, 17], a)
		"star":
			var st := [12, 3, 14.7, 8.6, 20.8, 9.4, 16.3, 13.6, 17.4, 19.7, 12, 16.8, 6.6, 19.7, 7.7, 13.6, 3.2, 9.4, 9.3, 8.6]
			_fill(ci, r, st, Color(a, 0.45))
			_pl(ci, r, st, m if not has_t else a, true)
		"clock":
			_ring(ci, r, 12, 13, 8, m)
			_pl(ci, r, [12, 9, 12, 13.2, 14.8, 15], a)
			_pl(ci, r, [10, 2.5, 14, 2.5], m)
		"sound", "music":
			if id == "sound":
				_fill(ci, r, [4, 9.5, 7.5, 9.5, 12, 5.5, 12, 18.5, 7.5, 14.5, 4, 14.5], soft)
				_pl(ci, r, [4, 9.5, 7.5, 9.5, 12, 5.5, 12, 18.5, 7.5, 14.5, 4, 14.5], m, true)
				_arc(ci, r, 12, 12, 4, -0.75, 0.75, a)
				_arc(ci, r, 12, 12, 7.5, -0.8, 0.8, a)
			else:
				_pl(ci, r, [9, 18, 9, 5, 19, 3, 19, 16], m)
				_pl(ci, r, [9, 8.6, 19, 6.6], a)
				_ring(ci, r, 6.8, 18, 2.3, m)
				_ring(ci, r, 16.8, 16, 2.3, m)
		"screen":
			_pl(ci, r, [3, 4.5, 21, 4.5, 21, 16, 3, 16], m, true)
			_pl(ci, r, [12, 16, 12, 19.5], m)
			_pl(ci, r, [8, 19.5, 16, 19.5], m)
			_pl(ci, r, [6, 13, 9.5, 9.5, 12, 11.5, 15.5, 7.5, 18, 10], a)
		"controls":
			# Mando: cuerpo, cruceta y dos botones de laton.
			_pl(ci, r, [6.5, 7.5, 17.5, 7.5, 20.5, 12, 21.5, 16.5, 19.5, 18.5, 16.5, 17.5, 14.5, 14.5,
				9.5, 14.5, 7.5, 17.5, 4.5, 18.5, 2.5, 16.5, 3.5, 12], m, true)
			_pl(ci, r, [6, 11.2, 9.6, 11.2], m)
			_pl(ci, r, [7.8, 9.4, 7.8, 13], m)
			_dot(ci, r, 15.6, 10.4, 1.3, a)
			_dot(ci, r, 17.6, 12.4, 1.3, a)
		"access":
			# Ojo.
			var eye := []
			for i in 13:
				var t := float(i) / 12.0
				eye.append(2.5 + 19.0 * t)
				eye.append(12.0 - 6.2 * sin(PI * t))
			for i in range(11, 0, -1):
				var t := float(i) / 12.0
				eye.append(2.5 + 19.0 * t)
				eye.append(12.0 + 6.2 * sin(PI * t))
			_pl(ci, r, eye, m, true)
			_ring(ci, r, 12, 12, 3.2, m)
			_dot(ci, r, 12, 12, 1.4, a)
		"game":
			# El mapa plegado: la partida.
			_fill(ci, r, [9, 3.5, 15, 6.5, 15, 20.5, 9, 17.5], soft)
			_pl(ci, r, [3, 6.5, 9, 3.5, 15, 6.5, 21, 3.5, 21, 17.5, 15, 20.5, 9, 17.5, 3, 20.5], m, true)
			_pl(ci, r, [9, 3.5, 9, 17.5], m)
			_pl(ci, r, [15, 6.5, 15, 20.5], m)
		"anchor":
			_ring(ci, r, 12, 4.8, 2, a)
			_pl(ci, r, [12, 6.8, 12, 21], m)
			_pl(ci, r, [8, 10, 16, 10], m)
			_arc(ci, r, 12, 13, 8, 0.35, PI - 0.35, m)
			_pl(ci, r, [17.6, 14.4, 19.5, 15.7, 20.4, 13.4], m)
			_pl(ci, r, [6.4, 14.4, 4.5, 15.7, 3.6, 13.4], m)
		"plane":
			# Avion visto desde arriba: fuselaje, ala, cola y helice de laton.
			_pl(ci, r, [2.5, 10.5, 10.6, 9, 10.8, 5, 12, 3.5, 13.2, 5, 13.4, 9, 21.5, 10.5, 21.5, 12.8, 13.3, 13,
				12.8, 18, 15.8, 19.6, 15.8, 21, 8.2, 21, 8.2, 19.6, 11.2, 18, 10.7, 13, 2.5, 12.8], m, true)
			_pl(ci, r, [9, 2, 15, 2], a)
		"tank":
			var track := _ell(5.7, 17.2, 2.2, 2.2, PI * 0.5, PI * 1.5, 10) + _ell(18.3, 17.2, 2.2, 2.2, -PI * 0.5, PI * 0.5, 10)
			_pl(ci, r, track, m, true)
			_pl(ci, r, [6, 15, 6, 11.5, 15.5, 11.5, 15.5, 15], m)
			_pl(ci, r, [15.5, 12.8, 21, 12.8], m)
			_pl(ci, r, [8.5, 11.5, 8.5, 9, 13.5, 9, 13.5, 11.5], m)
			for x in [8.5, 12.0, 15.5]:
				_dot(ci, r, x, 17.2, 1.1, a)
		"raid":
			# Rayo: el asalto.
			var bolt := [14, 2.5, 5.5, 13.5, 11.5, 13.5, 9.5, 21.5, 18.5, 10, 12.5, 10]
			_fill(ci, r, bolt, Color(a, 0.45))
			_pl(ci, r, bolt, m if not has_t else a, true)
		"check":
			_pl(ci, r, [4.5, 12.5, 9.5, 17.5, 19.5, 6.5], m, false, 1.15)
		"storm":
			# Nube abierta por abajo y el rayo de laton.
			_arc(ci, r, 7, 12.3, 4.2, PI * 0.5, PI * 1.5, m)
			_arc(ci, r, 11.9, 8.6, 5.6, PI * 1.02, PI * 1.97, m)
			_arc(ci, r, 17.2, 12.4, 4.1, -PI * 0.5, PI * 0.5, m)
			_pl(ci, r, [12.8, 11.5, 10, 16.5, 13.5, 16.5, 11.2, 21], a)
		"sun":
			_ring(ci, r, 12, 12, 4.5, m)
			for i in 8:
				var ang := TAU * float(i) / 8.0
				var d := Vector2(cos(ang), sin(ang))
				_pl(ci, r, [12 + d.x * 7.2, 12 + d.y * 7.2, 12 + d.x * 9.8, 12 + d.y * 9.8], a)
		"plus":
			_pl(ci, r, [12, 5, 12, 19], m, false, 1.1)
			_pl(ci, r, [5, 12, 19, 12], m, false, 1.1)
		"minus":
			_pl(ci, r, [5, 12, 19, 12], m, false, 1.1)
		"back":
			_pl(ci, r, [20, 12, 5, 12], m)
			_pl(ci, r, [10.5, 6.5, 5, 12, 10.5, 17.5], m)
		"next":
			_pl(ci, r, [4, 12, 19, 12], m)
			_pl(ci, r, [13.5, 6.5, 19, 12, 13.5, 17.5], m)
		"wrench":
			# Llave fija: mango en diagonal y boca abierta arriba a la derecha.
			_pl(ci, r, [4.5, 19.5, 12.6, 11.4], m, false, 1.25)
			_arc(ci, r, 15.6, 8.4, 4.4, -PI * 0.25 + 0.8, -PI * 0.25 + TAU - 0.8, m)
			_dot(ci, r, 5.6, 18.4, 0.9, a)
		"workers_off":
			# Un trabajador y la raya de "retirados".
			_ring(ci, r, 10, 7.5, 3.5, m)
			_arc(ci, r, 10, 20.5, 7, PI, TAU, m)
			_pl(ci, r, [15.5, 12.5, 21.5, 12.5], CartoonTheme.sem("DANGER") if not has_t else a)
		"mat_planks":
			var wood := a if has_t else UITheme.resource_color("planks")
			_pl(ci, r, [3, 6.5, 21, 6.5, 21, 11, 3, 11], m, true)
			_pl(ci, r, [3, 13, 21, 13, 21, 17.5, 3, 17.5], m, true)
			_pl(ci, r, [8, 6.5, 8, 11], wood)
			_pl(ci, r, [16, 13, 16, 17.5], wood)
		"mat_ingots":
			var gold := a if has_t else UITheme.resource_color("ingots")
			var bar := [2.5, 18.5, 6, 9, 18, 9, 21.5, 18.5]
			_fill(ci, r, bar, Color(gold, 0.3))
			_pl(ci, r, bar, m, true)
			_pl(ci, r, [8, 12.5, 12, 12.5], gold)
		"mat_beams":
			var steel := a if has_t else UITheme.resource_color("beams")
			var beam := [4, 4, 20, 4, 20, 7.5, 14, 7.5, 14, 16.5, 20, 16.5, 20, 20, 4, 20, 4, 16.5, 10, 16.5, 10, 7.5, 4, 7.5]
			_fill(ci, r, [10, 7.5, 14, 7.5, 14, 16.5, 10, 16.5], Color(steel, 0.35))
			_pl(ci, r, beam, m, true)
		"mat_fuel":
			var fuel := a if has_t else UITheme.resource_color("fuel")
			_pl(ci, r, [5, 7, 14, 7, 19, 11, 19, 21, 5, 21], m, true)
			_pl(ci, r, [7, 7, 7, 3.5, 11.5, 3.5, 11.5, 7], m)
			_pl(ci, r, [15.5, 6, 18.5, 3], m)
			_pl(ci, r, [8.5, 12, 15.5, 18], fuel)
			_pl(ci, r, [15.5, 12, 8.5, 18], fuel)
