extends SceneTree
## Herramienta re-ejecutable: dibuja los iconos pequenos del HUD con primitivas
## (nada descargado) y los guarda en assets/textures/ui/icons/*.png.
## Run: godot --headless --path . --script res://tools/gen_resource_icons.gd
##
## Cada recurso tiene una FORMA distinta, no solo un color: moneda (oro),
## tronco (madera), lingote (acero), gota (petroleo). Quien no distinga el
## amarillo del marron tiene que poder leer el recurso igual. Se dibuja a 4x
## y se reduce con Lanczos para que los bordes salgan suaves a 32 px.
##
## Hermano de tools/gen_ui_textures.gd (placas metalicas 9-patch).

const OUT_DIR := "res://assets/textures/ui/icons/"
const SIZE := 32
const SS := 4  # supersampling

var _img: Image
var _w: int

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_draw_icon("gold", _paint_coin)
	_draw_icon("wood", _paint_log)
	_draw_icon("steel", _paint_ingot)
	_draw_icon("oil", _paint_drop)
	_draw_icon("move", _paint_move_arrows)
	_draw_icon("drag", _paint_drag_grip)
	print("GEN_ICONS_DONE")
	quit()

func _draw_icon(fname: String, painter: Callable) -> void:
	_w = SIZE * SS
	_img = Image.create(_w, _w, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0))
	painter.call()
	_img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	var err := _img.save_png(ProjectSettings.globalize_path(OUT_DIR + fname + ".png"))
	print("GEN_ICON %s.png err=%d" % [fname, err])

# ── Primitivas (en coordenadas 0..1 del lienzo) ─────────────────────

func _px(u: float) -> float:
	return u * float(_w)

## Rellena cada pixel cuyo centro cumpla `inside(p)`; `p` en 0..1.
func _fill(inside: Callable, col: Color) -> void:
	for y in _w:
		for x in _w:
			var p := Vector2((float(x) + 0.5) / float(_w), (float(y) + 0.5) / float(_w))
			if inside.call(p):
				_img.set_pixel(x, y, col)

func _circle(c: Vector2, r: float, col: Color) -> void:
	_fill(func(p: Vector2) -> bool: return p.distance_to(c) <= r, col)

func _ring(c: Vector2, r_out: float, r_in: float, col: Color) -> void:
	_fill(func(p: Vector2) -> bool:
		var d := p.distance_to(c)
		return d <= r_out and d >= r_in, col)

func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	_fill(func(p: Vector2) -> bool:
		var dx := (p.x - c.x) / rx
		var dy := (p.y - c.y) / ry
		return dx * dx + dy * dy <= 1.0, col)

func _rect(x0: float, y0: float, x1: float, y1: float, col: Color) -> void:
	_fill(func(p: Vector2) -> bool: return p.x >= x0 and p.x <= x1 and p.y >= y0 and p.y <= y1, col)

## Poligono convexo o concavo por regla par-impar.
func _poly(points: PackedVector2Array, col: Color) -> void:
	_fill(func(p: Vector2) -> bool: return Geometry2D.is_point_in_polygon(p, points), col)

func _rounded_rect(x0: float, y0: float, x1: float, y1: float, r: float, col: Color) -> void:
	_fill(func(p: Vector2) -> bool:
		if p.x < x0 or p.x > x1 or p.y < y0 or p.y > y1:
			return false
		var cx := clampf(p.x, x0 + r, x1 - r)
		var cy := clampf(p.y, y0 + r, y1 - r)
		return p.distance_to(Vector2(cx, cy)) <= r, col)

# ── Iconos ───────────────────────────────────────────────────────────

## Moneda: disco dorado con canto oscuro, anillo interior y brillo.
func _paint_coin() -> void:
	var c := Vector2(0.5, 0.5)
	_circle(c, 0.44, Color(0.55, 0.40, 0.08))              # canto
	_circle(c, 0.38, Color(1.0, 0.85, 0.2))                 # cara
	_ring(c, 0.30, 0.26, Color(0.75, 0.58, 0.12))           # anillo grabado
	_rect(0.46, 0.30, 0.54, 0.70, Color(0.75, 0.58, 0.12))  # barra central
	_rect(0.36, 0.30, 0.64, 0.37, Color(0.75, 0.58, 0.12))  # cabeza de la "T"
	_ellipse(Vector2(0.36, 0.34), 0.10, 0.06, Color(1.0, 0.97, 0.7, 0.9))  # brillo

## Tronco: cilindro tumbado, corteza con vetas y el corte con anillos.
func _paint_log() -> void:
	var bark := Color(0.45, 0.28, 0.13)
	var bark_dark := Color(0.33, 0.20, 0.09)
	var cut := Color(0.85, 0.66, 0.38)
	var ring := Color(0.62, 0.44, 0.22)
	_rounded_rect(0.08, 0.30, 0.78, 0.70, 0.06, bark)
	# vetas
	_rect(0.14, 0.38, 0.62, 0.41, bark_dark)
	_rect(0.20, 0.52, 0.66, 0.55, bark_dark)
	_rect(0.12, 0.62, 0.56, 0.65, bark_dark)
	# corte del extremo derecho
	_ellipse(Vector2(0.78, 0.50), 0.14, 0.20, bark_dark)
	_ellipse(Vector2(0.78, 0.50), 0.11, 0.17, cut)
	_ellipse(Vector2(0.78, 0.50), 0.07, 0.11, ring)
	_ellipse(Vector2(0.78, 0.50), 0.04, 0.06, cut)

## Lingote: bloque trapezoidal con cara superior clara y frente sombreado.
func _paint_ingot() -> void:
	var top := Color(0.85, 0.88, 0.92)
	var front := Color(0.58, 0.63, 0.70)
	var side := Color(0.42, 0.47, 0.54)
	var edge := Color(0.25, 0.28, 0.33)
	# frente (trapecio, mas ancho abajo)
	_poly(PackedVector2Array([Vector2(0.18, 0.46), Vector2(0.72, 0.46), Vector2(0.82, 0.78), Vector2(0.08, 0.78)]), edge)
	_poly(PackedVector2Array([Vector2(0.20, 0.49), Vector2(0.70, 0.49), Vector2(0.79, 0.75), Vector2(0.11, 0.75)]), front)
	# cara superior (paralelogramo hacia atras-derecha)
	_poly(PackedVector2Array([Vector2(0.18, 0.46), Vector2(0.72, 0.46), Vector2(0.86, 0.26), Vector2(0.34, 0.26)]), edge)
	_poly(PackedVector2Array([Vector2(0.22, 0.44), Vector2(0.69, 0.44), Vector2(0.82, 0.29), Vector2(0.37, 0.29)]), top)
	# lateral derecho
	_poly(PackedVector2Array([Vector2(0.72, 0.46), Vector2(0.86, 0.26), Vector2(0.92, 0.56), Vector2(0.82, 0.78)]), side)
	# brillo en la cara superior
	_rect(0.40, 0.33, 0.62, 0.36, Color(1, 1, 1, 0.7))

## Gota: circulo mas punta, con reflejo. Petroleo: violeta grisaceo.
func _paint_drop() -> void:
	var body := Color(0.50, 0.45, 0.58)
	var rim := Color(0.28, 0.24, 0.34)
	var c := Vector2(0.5, 0.62)
	_circle(c, 0.30, rim)
	_poly(PackedVector2Array([Vector2(0.21, 0.58), Vector2(0.5, 0.06), Vector2(0.79, 0.58)]), rim)
	_circle(c, 0.26, body)
	_poly(PackedVector2Array([Vector2(0.25, 0.58), Vector2(0.5, 0.12), Vector2(0.75, 0.58)]), body)
	_ellipse(Vector2(0.40, 0.62), 0.07, 0.11, Color(0.85, 0.82, 0.92, 0.85))

## Cuatro flechas en cruz: el icono del boton MOVER del panel de edificio.
func _paint_move_arrows() -> void:
	var col := Color(0.95, 0.90, 0.80)
	var c := Vector2(0.5, 0.5)
	var shaft := 0.055
	var head := 0.17
	var tip := 0.06
	# ejes
	_rect(c.x - shaft, tip + head * 0.6, c.x + shaft, 1.0 - tip - head * 0.6, col)
	_rect(tip + head * 0.6, c.y - shaft, 1.0 - tip - head * 0.6, c.y + shaft, col)
	# puntas
	_poly(PackedVector2Array([Vector2(0.5, tip), Vector2(0.5 - head * 0.8, tip + head), Vector2(0.5 + head * 0.8, tip + head)]), col)
	_poly(PackedVector2Array([Vector2(0.5, 1.0 - tip), Vector2(0.5 - head * 0.8, 1.0 - tip - head), Vector2(0.5 + head * 0.8, 1.0 - tip - head)]), col)
	_poly(PackedVector2Array([Vector2(tip, 0.5), Vector2(tip + head, 0.5 - head * 0.8), Vector2(tip + head, 0.5 + head * 0.8)]), col)
	_poly(PackedVector2Array([Vector2(1.0 - tip, 0.5), Vector2(1.0 - tip - head, 0.5 - head * 0.8), Vector2(1.0 - tip - head, 0.5 + head * 0.8)]), col)
	_circle(c, 0.09, col)

## Asa de arrastre: seis puntos en dos columnas, como en cualquier barra movible.
func _paint_drag_grip() -> void:
	var col := Color(0.77, 0.59, 0.16)
	for row in [0.25, 0.5, 0.75]:
		_circle(Vector2(0.36, row), 0.09, col)
		_circle(Vector2(0.64, row), 0.09, col)

func _process(_delta: float) -> bool:
	return true
