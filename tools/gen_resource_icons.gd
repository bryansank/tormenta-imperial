extends SceneTree
## Herramienta re-ejecutable: dibuja los iconos pequenos del HUD con primitivas
## (nada descargado) y los guarda en assets/textures/ui/icons/*.png.
## Run: godot --headless --path . --script res://tools/gen_resource_icons.gd
##
## Lenguaje de la piel dieselpunk "D · Mezcla sobria" (docs/21 §17): iconos de
## LINEA, trazo grueso de puntas redondas en el claro de la paleta (hueso), con
## el color del recurso solo como acento pequeno (el centro de la moneda, el
## corte del tronco, el brillo del lingote, la gota por dentro...). Las formas
## son las de la maqueta (conceptos-dieselpunk.html, caja de 24 x 24), las
## mismas que CartoonIcon.gd dibuja en vivo.
##
## Cada recurso tiene una FORMA distinta, no solo un color: moneda (oro),
## tronco (madera), lingote (acero), gota (petroleo), espiga (comida). Quien no
## distinga el amarillo del marron tiene que poder leer el recurso igual.
##
## Estos PNG salen tambien sobre el mapa (la ficha de "listo para recoger" y
## los numeros flotantes), sobre la hierba y un disco claro: por eso cada icono
## lleva un halo de tinta (la Pizarra oscura) debajo del trazo y el cuerpo de
## las formas cerradas relleno de tinta. Sobre la Pizarra del HUD el halo no se
## ve. Se dibuja a 4x y se reduce con Lanczos para que los bordes salgan suaves.
##
## Hermano de tools/gen_ui_textures.gd (placas metalicas 9-patch).

const OUT_DIR := "res://assets/textures/ui/icons/"
const SIZE := 32
const SS := 4  # supersampling
## Escalas del sistema de iconos (24 / 42 / 60 / 96 px): cada icono sale tambien
## como `<id>_<px>.png`, trazado a esa medida (no reescalado del de 32), y
## UITheme.icon_texture(id, px) sirve la escala que toca. El `<id>.png` de 32 se
## queda como estaba para quien lo pida sin medida.
const SCALES := [24, 42, 60, 96]

## Paleta D (docs/24): hueso del texto, tinta de la Pizarra, laton.
const BONE := Color("eeeae1")
const INK := Color(0.075, 0.09, 0.106, 0.92)
const BRASS := Color("c99a45")
## Los acentos de recurso de la maqueta (--c-oro, --c-mad...).
const C_GOLD := Color("f0c350")
const C_WOOD := Color("d49a5c")
const C_FOOD := Color("d9d16c")
const C_STEEL := Color("afc5d4")
const C_OIL := Color("b9a6f3")
const C_MORALE := Color("f0937a")

## Trazo y halo, en unidades de la caja de 24. A 24 px el trazo pide algo mas
## para no quedarse en un pelo.
const STROKE := 2.3
const HALO := 1.3

var _img: Image
var _w: int
## Pasada en curso: "halo" (tinta debajo de todo) o "main" (trazo y acentos).
var _pass := "main"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_draw_icon("gold", _paint_coin)
	_draw_icon("wood", _paint_log)
	_draw_icon("steel", _paint_ingot)
	_draw_icon("oil", _paint_drop)
	_draw_icon("food", _paint_wheat)
	_draw_icon("workers", _paint_worker)
	_draw_icon("morale", _paint_heart)
	_draw_icon("move", _paint_move_arrows)
	_draw_icon("drag", _paint_drag_grip)
	print("GEN_ICONS_DONE")
	quit()

func _draw_icon(fname: String, painter: Callable) -> void:
	_draw_icon_at(fname + ".png", SIZE, painter)
	for px in SCALES:
		_draw_icon_at("%s_%d.png" % [fname, px], px, painter)

## El mismo pintor sirve a todas las medidas: halo primero, luego el dibujo.
func _draw_icon_at(out_name: String, px: int, painter: Callable) -> void:
	_w = px * SS
	_img = Image.create(_w, _w, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0))
	_pass = "halo"
	painter.call()
	_pass = "main"
	painter.call()
	_img.resize(px, px, Image.INTERPOLATE_LANCZOS)
	var err := _img.save_png(ProjectSettings.globalize_path(OUT_DIR + out_name))
	print("GEN_ICON %s err=%d" % [out_name, err])

# ── Primitivas (unidades de la caja de 24) ───────────────────────────

func _u() -> float:
	return float(_w) / 24.0

## Grosor del trazo en unidades: a 24 px algo mas grueso.
func _stroke() -> float:
	return STROKE * (1.15 if _w <= 24 * SS else 1.0)

func _plot(x: int, y: int, col: Color) -> void:
	if x < 0 or y < 0 or x >= _w or y >= _w:
		return
	_img.set_pixel(x, y, _img.get_pixel(x, y).blend(col))

## Pinta cada pixel de la caja [x0,x1]x[y0,y1] (unidades) cuyo centro cumple
## `inside(p)` (p en unidades).
func _region(x0: float, y0: float, x1: float, y1: float, inside: Callable, col: Color) -> void:
	var u := _u()
	var px0 := maxi(0, int(floor(x0 * u)))
	var py0 := maxi(0, int(floor(y0 * u)))
	var px1 := mini(_w - 1, int(ceil(x1 * u)))
	var py1 := mini(_w - 1, int(ceil(y1 * u)))
	for y in range(py0, py1 + 1):
		for x in range(px0, px1 + 1):
			var p := Vector2((float(x) + 0.5) / u, (float(y) + 0.5) / u)
			if inside.call(p):
				_plot(x, y, col)

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 0.0001 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func _to_pts(uv: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, uv.size(), 2):
		out.append(Vector2(float(uv[i]), float(uv[i + 1])))
	return out

## Trazo de polilinea (puntas y codos redondos: distancia al segmento). En la
## pasada de halo, mas ancho y en tinta; `col` solo cuenta en la de dibujo.
func _line(uv: Array, col: Color = BONE, closed := false, mult := 1.0) -> void:
	var pts := _to_pts(uv)
	if closed:
		pts.append(pts[0])
	var half := _stroke() * mult * 0.5
	var c := col
	if _pass == "halo":
		half += HALO
		c = INK
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		_region(minf(a.x, b.x) - half, minf(a.y, b.y) - half, maxf(a.x, b.x) + half, maxf(a.y, b.y) + half,
			func(p: Vector2) -> bool: return _seg_dist(p, a, b) <= half, c)

## Forma cerrada: en el halo se rellena de tinta (el cuerpo se lee sobre el
## mapa); en el dibujo solo se traza.
func _shape(uv: Array, col: Color = BONE) -> void:
	if _pass == "halo":
		_fill(uv, INK)
	_line(uv, col, true)

## Relleno de poligono. Los acentos solo se pintan en la pasada de dibujo.
func _fill(uv: Array, col: Color) -> void:
	if _pass == "halo" and col != INK:
		return
	var pts := _to_pts(uv)
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	_region(lo.x, lo.y, hi.x, hi.y, func(p: Vector2) -> bool: return Geometry2D.is_point_in_polygon(p, pts), col)

func _ring(cx: float, cy: float, r: float, col: Color = BONE, body := false) -> void:
	if body and _pass == "halo":
		_disc(cx, cy, r, INK)
	var half := _stroke() * 0.5
	var c := col
	if _pass == "halo":
		half += HALO
		c = INK
	var ctr := Vector2(cx, cy)
	_region(cx - r - half, cy - r - half, cx + r + half, cy + r + half,
		func(p: Vector2) -> bool: return absf(p.distance_to(ctr) - r) <= half, c)

func _disc(cx: float, cy: float, r: float, col: Color) -> void:
	if _pass == "halo" and col != INK:
		return
	var ctr := Vector2(cx, cy)
	_region(cx - r, cy - r, cx + r, cy + r, func(p: Vector2) -> bool: return p.distance_to(ctr) <= r, col)

## Puntos de un arco de elipse (unidades), para _line / _fill.
static func _ell(cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, n := 20) -> Array:
	var out := []
	for i in n + 1:
		var a := a0 + (a1 - a0) * float(i) / float(n)
		out.append(cx + cos(a) * rx)
		out.append(cy + sin(a) * ry)
	return out

# ── Iconos ───────────────────────────────────────────────────────────

## Moneda: canto en hueso y la cara de oro dentro (el acento).
func _paint_coin() -> void:
	_ring(12, 12, 8.5, BONE, true)
	_disc(12, 12, 4.6, C_GOLD)
	_ring(12, 12, 4.6, BONE)

## Tronco tumbado: el cuerpo en hueso y el corte de madera, con su anillo.
func _paint_log() -> void:
	var body := [17, 6, 7, 6] + _ell(7, 12, 3.5, 6, PI * 1.5, PI * 0.5) + [17, 18] + _ell(17, 12, 3.5, 6, PI * 0.5, -PI * 0.5)
	if _pass == "halo":
		_fill(body, INK)
	_line([17, 6, 7, 6] + _ell(7, 12, 3.5, 6, PI * 1.5, PI * 0.5) + [17, 18])
	var cut := _ell(17, 12, 3.5, 6, 0.0, TAU, 28)
	_fill(cut, C_WOOD)
	_line(cut)
	_line(_ell(17, 12, 1.2, 2.2, 0.0, TAU, 16), BONE, false, 0.8)

## Lingote: el trapecio en hueso, un velo de acero dentro y su brillo.
func _paint_ingot() -> void:
	var bar := [2.5, 18.5, 6, 9, 18, 9, 21.5, 18.5]
	if _pass == "halo":
		_fill(bar, INK)
	_fill(bar, Color(C_STEEL, 0.32))
	_line(bar, BONE, true)
	_line([8, 12.5, 12.5, 12.5], C_STEEL)

## Gota de petroleo: contorno en hueso, el petroleo por dentro y su reflejo.
func _paint_drop() -> void:
	var drop := [12, 3, 14.6, 6.1, 16.8, 9.1, 18.2, 11.8, 18.5, 14.3] + _ell(12, 14.3, 6.5, 6.5, 0.0, PI) \
		+ [5.5, 14.3, 5.8, 11.8, 7.2, 9.1, 9.4, 6.1]
	if _pass == "halo":
		_fill(drop, INK)
	var inner := [12, 7.2, 13.6, 9.2, 15.2, 11.6, 15.6, 14.3] + _ell(12, 14.3, 3.6, 3.6, 0.0, PI, 12) \
		+ [8.4, 14.3, 8.8, 11.6, 10.4, 9.2]
	_fill(inner, Color(C_OIL, 0.55))
	_line(drop, BONE, true)
	_line(_ell(12, 15, 3, 3, PI, PI * 0.5, 8), C_OIL, false, 0.85)

## Espiga: el tallo y las hojas en hueso, los granos de trigo por dentro.
func _paint_wheat() -> void:
	_line([12, 21.5, 12, 6])
	_line([12, 3, 12, 4.2])
	for oy in [0.0, 5.0, 10.0]:
		var y: float = 9.0 + oy
		for side in [-1.0, 1.0]:
			var leaf := [12, y, 12 + side * 2.5, y - 0.7, 12 + side * 4.1, y - 2.4, 12 + side * 4.5, y - 4.5,
				12 + side * 2.0, y - 3.8, 12 + side * 0.4, y - 2.1]
			if _pass == "halo":
				_fill(leaf, INK)
			_fill(leaf, Color(C_FOOD, 0.75))
			_line(leaf, BONE, true, 0.85)

## Trabajador: cabeza y hombros en hueso, el casco de laton.
func _paint_worker() -> void:
	var shoulders := _ell(12, 21.8, 7.6, 7.2, PI, TAU)
	if _pass == "halo":
		_fill(shoulders, INK)
	_line(shoulders)
	_ring(12, 10, 3.6, BONE, true)
	var helmet := _ell(12, 8.6, 4.4, 4.2, PI, TAU, 14)
	if _pass == "halo":
		_fill(helmet, INK)
	_fill(helmet, Color(BRASS, 0.85))
	_line(helmet, BRASS, true, 0.9)
	_line([6.6, 8.6, 17.4, 8.6], BRASS)

## Corazon de la moral: contorno en hueso y un corazon pequeno de color dentro.
func _paint_heart() -> void:
	var outer := _heart(12, 12.4, 0.52)
	if _pass == "halo":
		_fill(outer, INK)
	_fill(_heart(12, 11.8, 0.27), C_MORALE)
	_line(outer, BONE, true)

## Puntos de un corazon (curva clasica) centrado en (cx, cy), escala `k`.
static func _heart(cx: float, cy: float, k: float) -> Array:
	var out := []
	for i in 40:
		var t := TAU * float(i) / 40.0
		var x := 16.0 * pow(sin(t), 3)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		out.append(cx + x * k)
		out.append(cy - y * k)
	return out

## Cuatro flechas en cruz: el icono del boton MOVER del panel de edificio.
func _paint_move_arrows() -> void:
	_line([12, 2.8, 12, 21.2])
	_line([2.8, 12, 21.2, 12])
	_line([9, 5.8, 12, 2.8, 15, 5.8])
	_line([9, 18.2, 12, 21.2, 15, 18.2])
	_line([5.8, 9, 2.8, 12, 5.8, 15])
	_line([18.2, 9, 21.2, 12, 18.2, 15])
	_disc(12, 12, 1.7, BRASS)

## Asa de arrastre: seis remaches de laton en dos columnas.
func _paint_drag_grip() -> void:
	for row in [6.0, 12.0, 18.0]:
		for x in [8.6, 15.4]:
			if _pass == "halo":
				_disc(x, row, 2.2 + HALO, INK)
			_disc(x, row, 2.2, BRASS)

func _process(_delta: float) -> bool:
	return true
