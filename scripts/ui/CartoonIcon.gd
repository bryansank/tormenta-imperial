extends Control
## Iconos de interfaz del estilo "maqueta" (docs/28-guia-ui.md §8): formas
## gordas de juguete con contorno de tinta, dibujadas en _draw (sin imagenes:
## escalan sin pixelarse y no pesan en el APK, como InstructorBust).
##
## Un icono = un id de GLYPHS. Se dibuja en una caja de 0..1 y se escala al
## tamano del Control. Los recursos y las unidades NO van aqui: tienen sus PNG
## de siempre (UITheme.icon_texture / unit_icon).
##
## Sin _process ni animacion: se pinta al cambiar de id, color o tamano.

const GLYPHS := ["build", "army", "missions", "market", "research", "help", "menu",
	"settings", "upgrade", "move", "demolish", "close", "lock", "star", "clock",
	"sound", "music", "screen", "controls", "access", "game", "anchor", "plane",
	"tank", "raid", "check", "storm", "plus", "minus", "back", "next", "workers_off", "sun", "wrench"]

## Tinta del contorno: la de la piel dieselpunk (CartoonTheme.INK, Pizarra muy
## oscura; antes el marron de los instructores).
const INK := Color("13171b")

var glyph := "build":
	set(v):
		glyph = v
		queue_redraw()
## Color principal del relleno. Sin fijar, cada icono usa el suyo de serie.
var tint := Color(0, 0, 0, 0):
	set(v):
		tint = v
		queue_redraw()
## Con false, el icono va sin contorno (sobre un boton que ya lo lleva).
var outlined := true

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

static func make(id: String, px: float, color: Color = Color(0, 0, 0, 0)) -> Control:
	var icon = load("res://scripts/ui/CartoonIcon.gd").new()
	icon.glyph = id
	icon.tint = color
	icon.custom_minimum_size = Vector2(px, px)
	icon.size = Vector2(px, px)
	return icon

func _c(fallback: Color) -> Color:
	return tint if tint.a > 0.0 else fallback

func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 1.0:
		return
	var off := (size - Vector2(s, s)) * 0.5
	draw_glyph(self, Rect2(off, Vector2(s, s)), glyph, tint, outlined)

# ── Primitivas ─────────────────────────────────────────────────────────

static func _p(r: Rect2, u: float, v: float) -> Vector2:
	return r.position + Vector2(u * r.size.x, v * r.size.y)

static func _pts(r: Rect2, uv: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, uv.size(), 2):
		out.append(_p(r, uv[i], uv[i + 1]))
	return out

static func _w(r: Rect2) -> float:
	return maxf(1.5, r.size.x * 0.075)

static func _shape(ci: CanvasItem, pts: PackedVector2Array, fill: Color, r: Rect2, ink: bool) -> void:
	ci.draw_colored_polygon(pts, fill)
	if ink:
		var closed := pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, INK, _w(r), true)

static func _circle(ci: CanvasItem, c: Vector2, rad: float, fill: Color, r: Rect2, ink: bool) -> void:
	ci.draw_circle(c, rad, fill, true, -1.0, true)
	if ink:
		ci.draw_arc(c, rad, 0.0, TAU, 40, INK, _w(r), true)

static func _rect(ci: CanvasItem, r: Rect2, u0: float, v0: float, u1: float, v1: float, fill: Color, ink: bool, round_px: float = 0.0) -> void:
	var box := Rect2(_p(r, u0, v0), _p(r, u1, v1) - _p(r, u0, v0))
	if round_px <= 0.0:
		_shape(ci, PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end,
			Vector2(box.position.x, box.end.y)]), fill, r, ink)
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(round_px))
	sb.anti_aliasing = true
	if ink:
		sb.border_color = INK
		sb.set_border_width_all(int(maxf(1.0, _w(r) * 0.8)))
	ci.draw_style_box(sb, box)

static func _line(ci: CanvasItem, r: Rect2, uv: Array, col: Color, width_k: float = 1.0) -> void:
	ci.draw_polyline(_pts(r, uv), col, _w(r) * width_k, true)

static func _ell(c: Vector2, rx: float, ry: float, from := 0.0, to := TAU, n := 28) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := from + (to - from) * float(i) / float(n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out

# ── Los iconos ─────────────────────────────────────────────────────────

## Pinta el icono `id` dentro de `r` (cuadrado). Estatico: lo usan tambien
## los botones redondos sin crear un nodo por icono.
static func draw_glyph(ci: CanvasItem, r: Rect2, id: String, tint: Color = Color(0, 0, 0, 0), ink: bool = true) -> void:
	var t := tint
	var has_t := t.a > 0.0
	var W := Color(0.99, 0.97, 0.92)
	match id:
		"build":
			# Martillo: mango de madera en diagonal y cabeza de acero.
			_shape(ci, _pts(r, [0.22, 0.86, 0.14, 0.78, 0.56, 0.36, 0.64, 0.44]), Color(0.78, 0.5, 0.25), r, ink)
			_shape(ci, _pts(r, [0.38, 0.30, 0.58, 0.10, 0.92, 0.44, 0.72, 0.64]), t if has_t else Color(0.72, 0.77, 0.82), r, ink)
		"army":
			# Casco con barboquejo.
			var c := _p(r, 0.5, 0.6)
			var dome := _ell(c, r.size.x * 0.34, r.size.y * 0.36, PI, TAU)
			_shape(ci, dome, t if has_t else Color(0.42, 0.55, 0.3), r, ink)
			_rect(ci, r, 0.08, 0.58, 0.92, 0.7, (t if has_t else Color(0.42, 0.55, 0.3)).darkened(0.2), ink, r.size.x * 0.05)
			_circle(ci, _p(r, 0.5, 0.42), r.size.x * 0.07, Color(0.97, 0.78, 0.2), r, ink)
		"missions":
			# Banderin en su mastil.
			_rect(ci, r, 0.2, 0.1, 0.28, 0.92, Color(0.55, 0.38, 0.22), ink)
			_shape(ci, _pts(r, [0.28, 0.14, 0.86, 0.28, 0.28, 0.5]), t if has_t else Color(0.88, 0.25, 0.2), r, ink)
			_rect(ci, r, 0.1, 0.84, 0.42, 0.94, Color(0.55, 0.38, 0.22), ink, r.size.x * 0.03)
		"market":
			# Pila de monedas y bolsa.
			_shape(ci, _ell(_p(r, 0.62, 0.62), r.size.x * 0.26, r.size.y * 0.27), Color(0.8, 0.62, 0.38), r, ink)
			_shape(ci, _pts(r, [0.5, 0.3, 0.74, 0.3, 0.68, 0.4, 0.56, 0.4]), Color(0.8, 0.62, 0.38), r, ink)
			for i in 3:
				var y := 0.82 - float(i) * 0.12
				_shape(ci, _ell(_p(r, 0.3, y), r.size.x * 0.2, r.size.y * 0.08), t if has_t else Color(1.0, 0.8, 0.2), r, ink)
		"research":
			# Matraz redondo con liquido.
			_rect(ci, r, 0.4, 0.08, 0.6, 0.42, Color(0.85, 0.93, 0.97), ink)
			_shape(ci, _ell(_p(r, 0.5, 0.64), r.size.x * 0.3, r.size.y * 0.28), Color(0.85, 0.93, 0.97), r, ink)
			_shape(ci, _ell(_p(r, 0.5, 0.66), r.size.x * 0.24, r.size.y * 0.22, 0.15, PI - 0.15), t if has_t else Color(0.35, 0.8, 0.45), r, false)
			_rect(ci, r, 0.34, 0.06, 0.66, 0.14, Color(0.85, 0.93, 0.97), ink, r.size.x * 0.03)
		"help":
			_circle(ci, _p(r, 0.5, 0.5), r.size.x * 0.42, t if has_t else Color(0.2, 0.56, 0.85), r, ink)
			_glyph_text(ci, r, "?", W)
		"menu":
			for i in 3:
				var y := 0.24 + float(i) * 0.24
				_rect(ci, r, 0.14, y, 0.86, y + 0.12, t if has_t else W, ink, r.size.x * 0.06)
		"settings":
			var col := t if has_t else Color(0.72, 0.77, 0.82)
			var c := _p(r, 0.5, 0.5)
			var pts := PackedVector2Array()
			for i in 16:
				var a := TAU * float(i) / 16.0
				var rad := r.size.x * (0.44 if i % 2 == 0 else 0.33)
				pts.append(c + Vector2(cos(a), sin(a)) * rad)
			_shape(ci, pts, col, r, ink)
			_circle(ci, c, r.size.x * 0.13, Color(0.3, 0.3, 0.3) if ink else col.darkened(0.4), r, ink)
		"upgrade":
			_shape(ci, _pts(r, [0.5, 0.08, 0.9, 0.5, 0.66, 0.5, 0.66, 0.9, 0.34, 0.9, 0.34, 0.5, 0.1, 0.5]),
				t if has_t else Color(0.3, 0.75, 0.35), r, ink)
		"move":
			var col := t if has_t else W
			_shape(ci, _pts(r, [0.5, 0.04, 0.68, 0.24, 0.57, 0.24, 0.57, 0.43, 0.76, 0.43, 0.76, 0.32,
				0.96, 0.5, 0.76, 0.68, 0.76, 0.57, 0.57, 0.57, 0.57, 0.76, 0.68, 0.76, 0.5, 0.96,
				0.32, 0.76, 0.43, 0.76, 0.43, 0.57, 0.24, 0.57, 0.24, 0.68, 0.04, 0.5, 0.24, 0.32,
				0.24, 0.43, 0.43, 0.43, 0.43, 0.24, 0.32, 0.24]), col, r, ink)
		"demolish":
			# Bomba con mecha.
			_circle(ci, _p(r, 0.44, 0.6), r.size.x * 0.32, t if has_t else Color(0.25, 0.25, 0.28), r, ink)
			_rect(ci, r, 0.52, 0.2, 0.7, 0.34, Color(0.45, 0.45, 0.5), ink)
			_line(ci, r, [0.62, 0.2, 0.7, 0.1, 0.82, 0.12], Color(0.6, 0.45, 0.3))
			_circle(ci, _p(r, 0.85, 0.1), r.size.x * 0.07, Color(1.0, 0.6, 0.1), r, false)
			_circle(ci, _p(r, 0.34, 0.5), r.size.x * 0.06, Color(1, 1, 1, 0.6), r, false)
		"close":
			var col := t if has_t else W
			_shape(ci, _pts(r, [0.2, 0.08, 0.5, 0.38, 0.8, 0.08, 0.92, 0.2, 0.62, 0.5, 0.92, 0.8, 0.8, 0.92,
				0.5, 0.62, 0.2, 0.92, 0.08, 0.8, 0.38, 0.5, 0.08, 0.2]), col, r, ink)
		"lock":
			ci.draw_arc(_p(r, 0.5, 0.42), r.size.x * 0.2, PI, TAU, 20, INK, _w(r) * 2.2, true)
			ci.draw_arc(_p(r, 0.5, 0.42), r.size.x * 0.2, PI, TAU, 20, Color(0.7, 0.72, 0.75), _w(r) * 0.9, true)
			_rect(ci, r, 0.18, 0.42, 0.82, 0.9, t if has_t else Color(1.0, 0.75, 0.2), ink, r.size.x * 0.08)
			_circle(ci, _p(r, 0.5, 0.62), r.size.x * 0.06, INK, r, false)
		"star":
			var c := _p(r, 0.5, 0.54)
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2.0 + TAU * float(i) / 10.0
				pts.append(c + Vector2(cos(a), sin(a)) * r.size.x * (0.46 if i % 2 == 0 else 0.2))
			_shape(ci, pts, t if has_t else Color(1.0, 0.8, 0.15), r, ink)
		"clock":
			_circle(ci, _p(r, 0.5, 0.5), r.size.x * 0.42, t if has_t else W, r, ink)
			_line(ci, r, [0.5, 0.22, 0.5, 0.5, 0.7, 0.62], INK, 1.0)
		"sound", "music":
			var col := t if has_t else W
			if id == "sound":
				_shape(ci, _pts(r, [0.1, 0.38, 0.28, 0.38, 0.52, 0.16, 0.52, 0.84, 0.28, 0.62, 0.1, 0.62]), col, r, ink)
				# Las ondas: trazo de color con contorno de tinta (como el ancla),
				# para que se vean tambien sobre las ventanas oscuras.
				for rad_k in [0.2, 0.36]:
					if ink:
						ci.draw_arc(_p(r, 0.52, 0.5), r.size.x * rad_k, -0.8, 0.8, 16, INK, _w(r) * 2.0, true)
					ci.draw_arc(_p(r, 0.52, 0.5), r.size.x * rad_k, -0.8, 0.8, 16, col, _w(r) * 0.8, true)
			else:
				_rect(ci, r, 0.36, 0.14, 0.44, 0.72, col, ink)
				_rect(ci, r, 0.74, 0.08, 0.82, 0.62, col, ink)
				_shape(ci, _pts(r, [0.36, 0.14, 0.82, 0.04, 0.82, 0.2, 0.36, 0.3]), col, r, ink)
				_shape(ci, _ell(_p(r, 0.28, 0.76), r.size.x * 0.16, r.size.y * 0.12), col, r, ink)
				_shape(ci, _ell(_p(r, 0.66, 0.66), r.size.x * 0.16, r.size.y * 0.12), col, r, ink)
		"screen":
			_rect(ci, r, 0.08, 0.16, 0.92, 0.7, t if has_t else Color(0.35, 0.62, 0.9), ink, r.size.x * 0.06)
			_rect(ci, r, 0.42, 0.7, 0.58, 0.82, Color(0.55, 0.55, 0.6), ink)
			_rect(ci, r, 0.26, 0.82, 0.74, 0.9, Color(0.55, 0.55, 0.6), ink, r.size.x * 0.03)
		"controls":
			_rect(ci, r, 0.06, 0.3, 0.94, 0.76, t if has_t else Color(0.6, 0.62, 0.68), ink, r.size.x * 0.18)
			_rect(ci, r, 0.2, 0.47, 0.38, 0.55, INK, false)
			_rect(ci, r, 0.25, 0.42, 0.33, 0.6, INK, false)
			_circle(ci, _p(r, 0.66, 0.46), r.size.x * 0.05, Color(0.9, 0.3, 0.25), r, false)
			_circle(ci, _p(r, 0.76, 0.56), r.size.x * 0.05, Color(0.3, 0.7, 0.35), r, false)
		"access":
			_shape(ci, _ell(_p(r, 0.5, 0.5), r.size.x * 0.44, r.size.y * 0.26), W, r, ink)
			_circle(ci, _p(r, 0.5, 0.5), r.size.x * 0.17, t if has_t else Color(0.25, 0.55, 0.85), r, ink)
			_circle(ci, _p(r, 0.5, 0.5), r.size.x * 0.07, INK, r, false)
		"game":
			# Bandera de la colonia: la partida.
			_rect(ci, r, 0.14, 0.1, 0.22, 0.92, Color(0.55, 0.38, 0.22), ink)
			_shape(ci, _pts(r, [0.22, 0.12, 0.88, 0.12, 0.76, 0.32, 0.88, 0.52, 0.22, 0.52]), t if has_t else Color(0.25, 0.6, 0.9), r, ink)
		"anchor":
			var col := t if has_t else W
			_circle(ci, _p(r, 0.5, 0.16), r.size.x * 0.09, col, r, ink)
			_rect(ci, r, 0.45, 0.24, 0.55, 0.86, col, ink)
			_rect(ci, r, 0.3, 0.34, 0.7, 0.42, col, ink)
			ci.draw_arc(_p(r, 0.5, 0.56), r.size.x * 0.32, 0.25, PI - 0.25, 20, INK if ink else col, _w(r) * 2.2, true)
			ci.draw_arc(_p(r, 0.5, 0.56), r.size.x * 0.32, 0.25, PI - 0.25, 20, col, _w(r) * 0.9, true)
		"plane":
			var col := t if has_t else W
			_shape(ci, _pts(r, [0.5, 0.06, 0.58, 0.18, 0.58, 0.4, 0.94, 0.56, 0.94, 0.64, 0.58, 0.56,
				0.56, 0.78, 0.7, 0.88, 0.7, 0.94, 0.5, 0.88, 0.3, 0.94, 0.3, 0.88, 0.44, 0.78,
				0.42, 0.56, 0.06, 0.64, 0.06, 0.56, 0.42, 0.4, 0.42, 0.18]), col, r, ink)
		"tank":
			var col := t if has_t else W
			_rect(ci, r, 0.08, 0.56, 0.92, 0.82, col, ink, r.size.x * 0.12)
			_rect(ci, r, 0.26, 0.36, 0.68, 0.58, col, ink, r.size.x * 0.06)
			_rect(ci, r, 0.66, 0.42, 0.96, 0.5, col, ink)
		"raid":
			_shape(ci, _pts(r, [0.58, 0.04, 0.2, 0.56, 0.46, 0.56, 0.36, 0.96, 0.82, 0.4, 0.54, 0.4, 0.7, 0.04]),
				t if has_t else Color(1.0, 0.78, 0.15), r, ink)
		"check":
			_shape(ci, _pts(r, [0.08, 0.52, 0.22, 0.38, 0.4, 0.56, 0.78, 0.16, 0.92, 0.3, 0.4, 0.84]),
				t if has_t else Color(0.3, 0.75, 0.35), r, ink)
		"storm":
			var col := t if has_t else Color(0.55, 0.6, 0.7)
			_circle(ci, _p(r, 0.34, 0.46), r.size.x * 0.2, col, r, ink)
			_circle(ci, _p(r, 0.6, 0.38), r.size.x * 0.25, col, r, ink)
			_rect(ci, r, 0.14, 0.46, 0.86, 0.64, col, ink, r.size.x * 0.09)
			ci.draw_circle(_p(r, 0.5, 0.48), r.size.x * 0.16, col)
			_shape(ci, _pts(r, [0.52, 0.56, 0.38, 0.78, 0.5, 0.78, 0.42, 0.98, 0.66, 0.7, 0.54, 0.7, 0.62, 0.56]),
				Color(1.0, 0.8, 0.15), r, ink)
		"sun":
			var c := _p(r, 0.5, 0.5)
			for i in 8:
				var a := TAU * float(i) / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * r.size.x * 0.3, c + Vector2(cos(a), sin(a)) * r.size.x * 0.46,
					t if has_t else Color(1.0, 0.75, 0.1), _w(r) * 1.4, true)
			_circle(ci, c, r.size.x * 0.24, t if has_t else Color(1.0, 0.82, 0.2), r, ink)
		"plus", "minus":
			var col := t if has_t else W
			_rect(ci, r, 0.14, 0.4, 0.86, 0.6, col, ink, r.size.x * 0.04)
			if id == "plus":
				_rect(ci, r, 0.4, 0.14, 0.6, 0.86, col, ink, r.size.x * 0.04)
				_rect(ci, r, 0.16, 0.42, 0.84, 0.58, col, false)
		"back":
			_shape(ci, _pts(r, [0.08, 0.5, 0.46, 0.12, 0.46, 0.34, 0.92, 0.34, 0.92, 0.66, 0.46, 0.66, 0.46, 0.88]),
				t if has_t else W, r, ink)
		"next":
			_shape(ci, _pts(r, [0.92, 0.5, 0.54, 0.12, 0.54, 0.34, 0.08, 0.34, 0.08, 0.66, 0.54, 0.66, 0.54, 0.88]),
				t if has_t else W, r, ink)
		"wrench":
			# Llave inglesa en diagonal: reparar.
			var col := t if has_t else Color(0.72, 0.77, 0.82)
			_shape(ci, _pts(r, [0.16, 0.74, 0.56, 0.34, 0.66, 0.44, 0.26, 0.84]), col, r, ink)
			# La cabeza en C, abierta hacia arriba a la derecha.
			var hc := _p(r, 0.68, 0.32)
			var a0 := -PI * 0.25 + 0.75
			var a1 := -PI * 0.25 + TAU - 0.75
			if ink:
				ci.draw_arc(hc, r.size.x * 0.16, a0, a1, 24, INK, r.size.x * 0.17 + _w(r) * 2.0, true)
			ci.draw_arc(hc, r.size.x * 0.16, a0, a1, 24, col, r.size.x * 0.17, true)
		"workers_off":
			var col := t if has_t else W
			_circle(ci, _p(r, 0.42, 0.24), r.size.x * 0.14, col, r, ink)
			_shape(ci, _ell(_p(r, 0.42, 0.78), r.size.x * 0.28, r.size.y * 0.3, PI, TAU), col, r, ink)
			_rect(ci, r, 0.62, 0.62, 0.96, 0.74, Color(0.9, 0.3, 0.25), ink, r.size.x * 0.04)

## Un caracter centrado (el "?" de la ayuda) en la letra de titulos.
static func _glyph_text(ci: CanvasItem, r: Rect2, txt: String, col: Color) -> void:
	var f: Font = CartoonTheme.title_font()
	if f == null:
		return
	var fs := int(r.size.y * 0.66)
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := _p(r, 0.5, 0.5) + Vector2(-w * 0.5, fs * 0.36)
	ci.draw_string_outline(f, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(fs * 0.16)), INK)
	ci.draw_string(f, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
