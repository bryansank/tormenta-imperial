extends Control
## La ilustracion de cada folio del prologo: un grabado a tinta sobre el papel,
## de la misma mano que el sello de lacre (RegenciaSeal): todo sale de _draw,
## sin imagenes, asi que escala sin pixelarse en PC, tableta y telefono.
##
## Estilo de grabado: contornos de tinta, rellenos de trazos paralelos
## (`_hatch`, que recorta cada linea contra el poligono con
## Geometry2D.intersect_polyline_with_polygon) y cruzados donde hay sombra, y
## una plancha con doble filete alrededor. Un solo acento rojo de lacre por
## lamina (el sello, la cinta, la bandera...). Nada se mueve: se pinta al
## cambiar de folio o de tamano y Godot guarda las ordenes de dibujo; no hay
## _process.
##
## | Folio | Lamina |
## |---|---|
## | 1 La firma del Emperador | medallon con el busto coronado y la cinta de luto; el decreto con la firma y la pluma en el tintero |
## | 2 La Tormenta | nubes de ceniza sobre las casas, ceniza que cae y el dirigible de los Cobradores |
## | 3 Quienes somos | la isla con sus chimeneas humeando, los nuestros en la orilla y el barco que se fue |
## | 4 Desde cero | el Nucleo con andamio, los arboles, el monton de ladrillos y el martillo, con el sol detras |
## | B En tramite | el vigia de costa con su catalejo y el humo lejano de la isla |
##
## Las funciones de dibujo son estaticas y reciben el CanvasItem y el
## rectangulo: las pruebas las llaman sobre un lienzo cualquiera.

const SCENES := ["1", "2", "3", "4", "B"]

## Tinta y acento (los mismos tonos del papel del prologo).
const INK := Color(0.17, 0.11, 0.06)
const INK_SOFT := Color(0.17, 0.11, 0.06, 0.55)
const INK_FAINT := Color(0.17, 0.11, 0.06, 0.3)
const RED := Color(0.6, 0.1, 0.07)

var folio := ""

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	resized.connect(queue_redraw)

func set_folio(id: String) -> void:
	if id == folio:
		return
	folio = id
	queue_redraw()

static func has_scene(id: String) -> bool:
	return id in SCENES

func _draw() -> void:
	if not has_scene(folio):
		return
	draw_plate(self, Rect2(Vector2.ZERO, size), folio)

## La lamina entera de `id` dentro de `area`: cuadrada (o casi), centrada, con
## su plancha. Devuelve el rectangulo de la plancha (vacio si no cabe).
static func draw_plate(ci: CanvasItem, area: Rect2, id: String) -> Rect2:
	var side := minf(area.size.x, area.size.y * 1.1)
	if side < 48.0 or not has_scene(id):
		return Rect2()
	var h := minf(area.size.y, side / 1.1)
	var plate := Rect2(area.position + (area.size - Vector2(side, h)) * 0.5, Vector2(side, h))
	var k := side / 300.0
	# La plancha: doble filete y un margen en blanco.
	ci.draw_rect(plate, INK_SOFT, false, maxf(1.0, 1.4 * k))
	ci.draw_rect(plate.grow(-4.0 * k), INK_FAINT, false, maxf(1.0, 0.8 * k))
	var box := plate.grow(-10.0 * k)
	match id:
		"1": _emperor(ci, box, k)
		"2": _storm(ci, box, k)
		"3": _island(ci, box, k)
		"4": _from_scratch(ci, box, k)
		"B": _lookout(ci, box, k)
	return plate

# ── Utilidades de grabado ────────────────────────────────────────────

## Punto (u, v) en [0, 1] dentro de `box`.
static func _p(box: Rect2, u: float, v: float) -> Vector2:
	return box.position + Vector2(u, v) * box.size

static func _pts(box: Rect2, uv: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, uv.size(), 2):
		out.append(_p(box, float(uv[i]), float(uv[i + 1])))
	return out

static func _ellipse(c: Vector2, rx: float, ry: float, n: int = 28, from := 0.0, to := TAU) -> PackedVector2Array:
	var out := PackedVector2Array()
	var full := is_equal_approx(to - from, TAU)
	var count := n if full else n + 1
	for i in count:
		var a := from + (to - from) * float(i) / float(n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out

static func _stroke(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, closed := true) -> void:
	if pts.size() < 2:
		return
	var line := pts
	if closed:
		line = pts.duplicate()
		line.append(pts[0])
	ci.draw_polyline(line, col, w, true)

## Rellena `poly` con trazos paralelos a `angle_deg`, separados `gap` px.
static func _hatch(ci: CanvasItem, poly: PackedVector2Array, angle_deg: float, gap: float, col: Color, w: float) -> void:
	if poly.size() < 3:
		return
	# En un telefono la lamina es pequena: el trazo no se apelmaza.
	gap = maxf(gap, 1.6)
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	var c := r.get_center()
	var reach := r.size.length() * 0.5 + 2.0
	var d := Vector2.from_angle(deg_to_rad(angle_deg))
	var n := Vector2(-d.y, d.x)
	var t := -reach
	while t <= reach:
		var a := c + n * t - d * reach
		var b := c + n * t + d * reach
		for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), poly):
			if (seg as PackedVector2Array).size() >= 2:
				ci.draw_polyline(seg, col, w, false)
		t += gap

## Sombra de grabado: trazos en dos direcciones.
static func _crosshatch(ci: CanvasItem, poly: PackedVector2Array, gap: float, col: Color, w: float) -> void:
	_hatch(ci, poly, 35.0, gap, col, w)
	_hatch(ci, poly, -35.0, gap, col, w)

## Una nube de grabado: discos solapados, contorno arriba y sombra rayada abajo.
static func _cloud(ci: CanvasItem, c: Vector2, rx: float, ry: float, k: float, dark: bool) -> void:
	var lumps: Array = [Vector3(-0.55, 0.15, 0.5), Vector3(-0.15, -0.2, 0.62), Vector3(0.3, -0.05, 0.55), Vector3(0.62, 0.2, 0.42)]
	for l in lumps:
		var lc := c + Vector2(l.x * rx, l.y * ry)
		var e := _ellipse(lc, l.z * rx, l.z * ry * 1.25, 22)
		ci.draw_colored_polygon(e, UITheme.PARCHMENT)
		if dark:
			_hatch(ci, e, 0.0, 3.2 * k, INK_SOFT, maxf(1.0, 0.8 * k))
		_stroke(ci, _ellipse(lc, l.z * rx, l.z * ry * 1.25, 22, PI * 1.05, TAU * 0.98), INK, maxf(1.0, 1.3 * k), false)
	# La panza: una linea casi recta y sombra debajo.
	var belly := PackedVector2Array([c + Vector2(-rx * 1.05, ry * 0.55), c + Vector2(rx * 1.05, ry * 0.55)])
	ci.draw_polyline(belly, INK, maxf(1.0, 1.2 * k), true)

## Una casa de juguete vista de frente: muro, tejado a dos aguas, puerta y ventana.
static func _house(ci: CanvasItem, base: Vector2, w: float, h: float, k: float, broken := false) -> void:
	var wall := PackedVector2Array([base + Vector2(-w * 0.5, 0), base + Vector2(w * 0.5, 0), base + Vector2(w * 0.5, -h), base + Vector2(-w * 0.5, -h)])
	ci.draw_colored_polygon(wall, UITheme.PARCHMENT)
	_hatch(ci, wall, 90.0, 3.0 * k, INK_FAINT, maxf(1.0, 0.7 * k))
	_stroke(ci, wall, INK, maxf(1.0, 1.2 * k))
	var roof: PackedVector2Array
	if broken:
		roof = PackedVector2Array([base + Vector2(-w * 0.62, -h), base + Vector2(-w * 0.1, -h - h * 0.62), base + Vector2(w * 0.05, -h - h * 0.35), base + Vector2(w * 0.2, -h - h * 0.5), base + Vector2(w * 0.62, -h)])
	else:
		roof = PackedVector2Array([base + Vector2(-w * 0.62, -h), base + Vector2(0, -h - h * 0.62), base + Vector2(w * 0.62, -h)])
	ci.draw_colored_polygon(roof, UITheme.PARCHMENT)
	_crosshatch(ci, roof, 2.6 * k, INK_SOFT, maxf(1.0, 0.7 * k))
	_stroke(ci, roof, INK, maxf(1.0, 1.2 * k))
	ci.draw_rect(Rect2(base + Vector2(-w * 0.12, -h * 0.5), Vector2(w * 0.24, h * 0.5)), INK)
	ci.draw_rect(Rect2(base + Vector2(w * 0.2, -h * 0.82), Vector2(w * 0.18, h * 0.2)), INK_SOFT)

## Un pino de grabado: tres pisos de triangulo rayado y el tronco.
static func _tree(ci: CanvasItem, base: Vector2, h: float, k: float) -> void:
	ci.draw_line(base, base + Vector2(0, -h * 0.25), INK, maxf(1.5, 2.2 * k))
	for i in 3:
		var y0 := -h * (0.18 + 0.24 * float(i))
		var half := h * (0.3 - 0.06 * float(i))
		var tri := PackedVector2Array([base + Vector2(-half, y0), base + Vector2(half, y0), base + Vector2(0, y0 - h * 0.38)])
		ci.draw_colored_polygon(tri, UITheme.PARCHMENT)
		_hatch(ci, tri, -55.0, 2.4 * k, INK_SOFT, maxf(1.0, 0.75 * k))
		_stroke(ci, tri, INK, maxf(1.0, 1.1 * k))

## Una columna de humo: bolas que crecen y se inclinan con el viento.
static func _smoke(ci: CanvasItem, from: Vector2, k: float, rise: float, lean: float) -> void:
	for i in 5:
		var t := float(i) / 4.0
		var c := from + Vector2(lean * t * t, -rise * t)
		var r := (3.0 + 6.0 * t) * k
		_stroke(ci, _ellipse(c, r, r * 0.8, 14), INK_SOFT, maxf(1.0, 0.9 * k))

## Olas de grabado: lineas onduladas paralelas entre v0 y v1.
static func _sea(ci: CanvasItem, box: Rect2, v0: float, v1: float, k: float, rows: int) -> void:
	for i in rows:
		var v := lerpf(v0, v1, float(i) / float(maxi(1, rows - 1)))
		var line := PackedVector2Array()
		var amp := (1.0 + 1.6 * float(i) / float(rows)) * k
		for s in 25:
			var u := float(s) / 24.0
			line.append(_p(box, u, v) + Vector2(0, sin(u * 34.0 + float(i) * 1.7) * amp))
		ci.draw_polyline(line, INK_SOFT if i % 2 == 0 else INK_FAINT, maxf(1.0, 0.8 * k), true)

# ── Laminas ──────────────────────────────────────────────────────────

## Folio 1: el busto coronado en su medallon, con la cinta de luto, y el
## decreto firmado con la pluma en el tintero.
static func _emperor(ci: CanvasItem, box: Rect2, k: float) -> void:
	var lw := maxf(1.0, 1.4 * k)
	var c := _p(box, 0.5, 0.33)
	var rx := box.size.x * 0.27
	var ry := box.size.y * 0.3
	var oval := _ellipse(c, rx, ry, 40)
	# Fondo del medallon rayado en horizontal, como un grabado de moneda.
	_hatch(ci, oval, 0.0, 3.0 * k, INK_FAINT, maxf(1.0, 0.7 * k))
	# El busto de perfil: cabeza, cuello y hombros, en sombra cruzada.
	var bust := PackedVector2Array([
		c + Vector2(-rx * 0.62, ry * 0.95), c + Vector2(-rx * 0.55, ry * 0.55),
		c + Vector2(-rx * 0.22, ry * 0.38), c + Vector2(-rx * 0.16, ry * 0.18),
		c + Vector2(-rx * 0.34, ry * 0.02), c + Vector2(-rx * 0.38, -ry * 0.28),
		c + Vector2(-rx * 0.18, -ry * 0.5), c + Vector2(rx * 0.12, -ry * 0.48),
		c + Vector2(rx * 0.3, -ry * 0.3), c + Vector2(rx * 0.34, -ry * 0.1),
		c + Vector2(rx * 0.46, ry * 0.02), c + Vector2(rx * 0.33, ry * 0.08),
		c + Vector2(rx * 0.32, ry * 0.2), c + Vector2(rx * 0.16, ry * 0.3),
		c + Vector2(rx * 0.18, ry * 0.42), c + Vector2(rx * 0.58, ry * 0.58),
		c + Vector2(rx * 0.66, ry * 0.95),
	])
	var inside := Geometry2D.intersect_polygons(bust, oval)
	for part in inside:
		ci.draw_colored_polygon(part, UITheme.PARCHMENT)
		_crosshatch(ci, part, 2.2 * k, INK, maxf(1.0, 0.8 * k))
	# La corona: cinco puntas sobre la cabeza.
	var crown := PackedVector2Array()
	var cb := c + Vector2(-rx * 0.28, -ry * 0.46)
	var cw := rx * 0.5
	crown.append(cb)
	for i in 5:
		var x := cw * float(i) / 4.0
		crown.append(cb + Vector2(x, -ry * (0.26 if i % 2 == 0 else 0.15)))
	crown.append(cb + Vector2(cw, 0))
	ci.draw_colored_polygon(crown, UITheme.PARCHMENT)
	_stroke(ci, crown, INK, lw)
	ci.draw_line(cb + Vector2(0, -ry * 0.04), cb + Vector2(cw, -ry * 0.04), INK, lw)
	# El marco del medallon: dos aros.
	_stroke(ci, oval, INK, maxf(1.5, 2.2 * k))
	_stroke(ci, _ellipse(c, rx * 1.07, ry * 1.06, 40), INK, lw)
	# La cinta de luto, cruzando la esquina del marco.
	var a := c + Vector2(rx * 0.55, -ry * 1.05)
	var b := c + Vector2(rx * 1.15, -ry * 0.45)
	var band := PackedVector2Array([a, a + Vector2(rx * 0.2, -ry * 0.03), b + Vector2(rx * 0.04, ry * 0.2), b])
	ci.draw_colored_polygon(band, INK)
	# El decreto: hoja inclinada con renglones y la firma.
	var sheet := _pts(box, [0.08, 0.78, 0.66, 0.72, 0.7, 0.98, 0.12, 1.0])
	ci.draw_colored_polygon(sheet, UITheme.PARCHMENT.lightened(0.06))
	_stroke(ci, sheet, INK, lw)
	for i in 3:
		var v := 0.8 + 0.035 * float(i)
		ci.draw_line(_p(box, 0.14, v + 0.004), _p(box, 0.58 - 0.08 * float(i), v - 0.004 * float(i) - 0.002), INK_FAINT, maxf(1.0, 0.9 * k))
	var sig := PackedVector2Array()
	for s in 30:
		var t := float(s) / 29.0
		sig.append(_p(box, 0.2 + 0.36 * t, 0.925 - 0.02 * t) + Vector2(0, sin(t * 19.0) * 5.0 * k * (1.0 - t * 0.5)))
	ci.draw_polyline(sig, INK, maxf(1.2, 1.6 * k), true)
	# El lacre al pie del decreto (el unico rojo).
	var wax := _ellipse(_p(box, 0.6, 0.92), 8.0 * k, 7.0 * k, 16)
	ci.draw_colored_polygon(wax, RED)
	_stroke(ci, wax, INK, maxf(1.0, k))
	# El tintero y la pluma.
	var well := _pts(box, [0.76, 0.98, 0.92, 0.98, 0.89, 0.88, 0.79, 0.88])
	ci.draw_colored_polygon(well, UITheme.PARCHMENT)
	_crosshatch(ci, well, 2.0 * k, INK, maxf(1.0, 0.8 * k))
	_stroke(ci, well, INK, lw)
	var quill := _pts(box, [0.84, 0.88, 0.97, 0.5, 0.99, 0.56, 0.95, 0.68, 0.85, 0.88])
	ci.draw_colored_polygon(quill, UITheme.PARCHMENT)
	_hatch(ci, quill, -20.0, 2.0 * k, INK_SOFT, maxf(1.0, 0.7 * k))
	_stroke(ci, quill, INK, lw)
	ci.draw_line(_p(box, 0.84, 0.88), _p(box, 0.98, 0.52), INK, lw)

## Folio 2: la ceniza cae sobre las casas y el dirigible de los Cobradores
## asoma entre las nubes.
static func _storm(ci: CanvasItem, box: Rect2, k: float) -> void:
	var lw := maxf(1.0, 1.3 * k)
	# El cielo cargado: rayado horizontal que se espesa arriba.
	var sky := _pts(box, [0, 0, 1, 0, 1, 0.72, 0, 0.72])
	_hatch(ci, sky, 0.0, 4.2 * k, INK_FAINT, maxf(1.0, 0.7 * k))
	_hatch(ci, _pts(box, [0, 0, 1, 0, 1, 0.3, 0, 0.3]), 0.0, 4.2 * k, INK_FAINT, maxf(1.0, 0.7 * k))
	# El dirigible: casco, aletas, gondola y su bandera roja.
	var hull_c := _p(box, 0.66, 0.3)
	var hull := _ellipse(hull_c, box.size.x * 0.24, box.size.y * 0.08, 32)
	ci.draw_colored_polygon(hull, UITheme.PARCHMENT)
	_hatch(ci, _ellipse(hull_c + Vector2(0, box.size.y * 0.03), box.size.x * 0.22, box.size.y * 0.05, 24), 0.0, 2.2 * k, INK_SOFT, maxf(1.0, 0.8 * k))
	_stroke(ci, hull, INK, maxf(1.2, 1.6 * k))
	for i in 3:
		var u := 0.52 + 0.1 * float(i)
		ci.draw_line(_p(box, u, 0.225), _p(box, u, 0.375), INK_SOFT, maxf(1.0, 0.8 * k))
	var fin := PackedVector2Array([hull_c + Vector2(box.size.x * 0.2, -box.size.y * 0.02), hull_c + Vector2(box.size.x * 0.29, -box.size.y * 0.1), hull_c + Vector2(box.size.x * 0.27, box.size.y * 0.01)])
	ci.draw_colored_polygon(fin, INK)
	var gondola := Rect2(hull_c + Vector2(-box.size.x * 0.06, box.size.y * 0.09), Vector2(box.size.x * 0.12, box.size.y * 0.04))
	ci.draw_rect(gondola, INK)
	ci.draw_line(hull_c + Vector2(-box.size.x * 0.05, box.size.y * 0.06), gondola.position, INK, maxf(1.0, k))
	ci.draw_line(hull_c + Vector2(box.size.x * 0.05, box.size.y * 0.06), gondola.position + Vector2(gondola.size.x, 0), INK, maxf(1.0, k))
	var pole := gondola.position + Vector2(0, gondola.size.y)
	ci.draw_line(pole, pole + Vector2(-box.size.x * 0.05, box.size.y * 0.02), INK, maxf(1.0, k))
	var flag := PackedVector2Array([pole + Vector2(-box.size.x * 0.05, box.size.y * 0.02), pole + Vector2(-box.size.x * 0.1, box.size.y * 0.03), pole + Vector2(-box.size.x * 0.05, box.size.y * 0.06)])
	ci.draw_colored_polygon(flag, RED)
	# Las nubes de ceniza, delante del dirigible a medias.
	_cloud(ci, _p(box, 0.22, 0.17), box.size.x * 0.2, box.size.y * 0.09, k, true)
	_cloud(ci, _p(box, 0.86, 0.43), box.size.x * 0.16, box.size.y * 0.07, k, true)
	_cloud(ci, _p(box, 0.4, 0.42), box.size.x * 0.14, box.size.y * 0.06, k, false)
	# La ceniza que cae, sesgada por el viento (semilla fija: siempre la misma).
	var rng := RandomNumberGenerator.new()
	rng.seed = 2602
	for i in 70:
		var p := _p(box, rng.randf(), rng.randf_range(0.45, 0.9))
		ci.draw_line(p, p + Vector2(2.2, 4.2) * k, INK_SOFT, maxf(1.0, 0.9 * k))
	# El suelo y las casas; una con el tejado roto.
	ci.draw_line(_p(box, 0.0, 0.93), _p(box, 1.0, 0.93), INK, lw)
	_hatch(ci, _pts(box, [0, 0.93, 1, 0.93, 1, 1, 0, 1]), 20.0, 3.0 * k, INK_SOFT, maxf(1.0, 0.7 * k))
	var hw := box.size.x * 0.13
	_house(ci, _p(box, 0.14, 0.93), hw, hw * 0.75, k)
	_house(ci, _p(box, 0.36, 0.93), hw * 0.9, hw * 0.7, k, true)
	_house(ci, _p(box, 0.6, 0.93), hw, hw * 0.8, k)
	_house(ci, _p(box, 0.84, 0.93), hw * 0.85, hw * 0.68, k)

## Folio 3: la isla con sus chimeneas, los nuestros en la orilla y, en el
## horizonte, el barco de los que se fueron.
static func _island(ci: CanvasItem, box: Rect2, k: float) -> void:
	var lw := maxf(1.0, 1.4 * k)
	# Horizonte y mar.
	ci.draw_line(_p(box, 0.0, 0.52), _p(box, 1.0, 0.52), INK, maxf(1.0, k))
	_sea(ci, box, 0.56, 0.98, k, 9)
	# El barco que se fue, pequeno en el horizonte, con su humo.
	var ship := _pts(box, [0.8, 0.5, 0.93, 0.5, 0.91, 0.52, 0.82, 0.52])
	ci.draw_colored_polygon(ship, INK)
	ci.draw_rect(Rect2(_p(box, 0.855, 0.47), Vector2(box.size.x * 0.018, box.size.y * 0.03)), INK)
	_smoke(ci, _p(box, 0.865, 0.465), k * 0.6, box.size.y * 0.1, box.size.x * 0.06)
	# La isla: un monte con la ladera en sombra.
	var land := _pts(box, [0.04, 0.8, 0.12, 0.66, 0.24, 0.58, 0.38, 0.5, 0.5, 0.47, 0.62, 0.52, 0.74, 0.62, 0.82, 0.74, 0.86, 0.8])
	ci.draw_colored_polygon(land, UITheme.PARCHMENT)
	_hatch(ci, _pts(box, [0.5, 0.47, 0.62, 0.52, 0.74, 0.62, 0.82, 0.74, 0.86, 0.8, 0.5, 0.8]), -40.0, 2.4 * k, INK_SOFT, maxf(1.0, 0.8 * k))
	_hatch(ci, land, 0.0, 5.0 * k, INK_FAINT, maxf(1.0, 0.6 * k))
	_stroke(ci, land, INK, lw, false)
	ci.draw_line(_p(box, 0.04, 0.8), _p(box, 0.86, 0.8), INK, lw)
	# La fabrica en lo alto: nave con dientes de sierra y tres chimeneas que humean.
	var shed := _pts(box, [0.3, 0.55, 0.3, 0.45, 0.36, 0.41, 0.36, 0.45, 0.42, 0.41, 0.42, 0.45, 0.48, 0.41, 0.48, 0.5])
	ci.draw_colored_polygon(shed, UITheme.PARCHMENT)
	_hatch(ci, shed, 90.0, 2.6 * k, INK_SOFT, maxf(1.0, 0.7 * k))
	_stroke(ci, shed, INK, lw)
	for u in [0.52, 0.57, 0.62]:
		var top := _p(box, u, 0.3 + (u - 0.52) * 0.6)
		var stack := PackedVector2Array([top + Vector2(-2.6 * k, 0), top + Vector2(2.6 * k, 0), _p(box, u + 0.008, 0.52), _p(box, u - 0.008, 0.52)])
		ci.draw_colored_polygon(stack, INK)
		_smoke(ci, top + Vector2(0, -3.0 * k), k, box.size.y * 0.2, box.size.x * 0.12)
	# Los nuestros en la orilla, mirando al mar (munecos de tinta).
	for i in 4:
		var foot := _p(box, 0.12 + 0.07 * float(i), 0.8)
		var hgt := box.size.y * (0.075 + 0.01 * float(i % 2))
		ci.draw_line(foot, foot + Vector2(0, -hgt * 0.7), INK, maxf(1.5, 2.2 * k))
		ci.draw_circle(foot + Vector2(0, -hgt * 0.85), hgt * 0.15, INK)
		ci.draw_line(foot + Vector2(0, -hgt * 0.55), foot + Vector2(hgt * 0.25, -hgt * 0.4), INK, maxf(1.0, 1.3 * k))
	# La bandera de los nuestros sobre la nave (el acento rojo).
	var mast := _p(box, 0.33, 0.43)
	ci.draw_line(mast, mast + Vector2(0, -box.size.y * 0.1), INK, maxf(1.0, 1.2 * k))
	var flag := PackedVector2Array([mast + Vector2(0, -box.size.y * 0.1), mast + Vector2(box.size.x * 0.06, -box.size.y * 0.085), mast + Vector2(0, -box.size.y * 0.065)])
	ci.draw_colored_polygon(flag, RED)

## Folio 4: el Nucleo a medio levantar con su andamio, los arboles, los
## ladrillos y el martillo, y el sol que sale detras.
static func _from_scratch(ci: CanvasItem, box: Rect2, k: float) -> void:
	var lw := maxf(1.0, 1.4 * k)
	# El sol: medio disco en el horizonte y sus rayos.
	var sun_c := _p(box, 0.56, 0.62)
	var sun_r := box.size.x * 0.17
	for i in 15:
		var a := PI + PI * float(i + 0.5) / 15.0
		var d := Vector2.from_angle(a)
		ci.draw_line(sun_c + d * sun_r * 1.15, sun_c + d * sun_r * (1.55 + 0.25 * float(i % 2)), INK_SOFT, maxf(1.0, 1.1 * k))
	_stroke(ci, _ellipse(sun_c, sun_r, sun_r, 32, PI, TAU), INK, lw, false)
	# El suelo.
	ci.draw_line(_p(box, 0.0, 0.62), _p(box, 1.0, 0.62), INK, lw)
	_hatch(ci, _pts(box, [0, 0.62, 1, 0.62, 1, 1, 0, 1]), 12.0, 4.0 * k, INK_FAINT, maxf(1.0, 0.7 * k))
	# El Nucleo: tambor, cupula a medias y el andamio.
	var drum := _pts(box, [0.42, 0.62, 0.42, 0.44, 0.7, 0.44, 0.7, 0.62])
	ci.draw_colored_polygon(drum, UITheme.PARCHMENT)
	_hatch(ci, _pts(box, [0.6, 0.62, 0.6, 0.44, 0.7, 0.44, 0.7, 0.62]), 90.0, 2.2 * k, INK_SOFT, maxf(1.0, 0.8 * k))
	for i in 4:
		var v := 0.47 + 0.04 * float(i)
		ci.draw_line(_p(box, 0.42, v), _p(box, 0.7, v), INK_FAINT, maxf(1.0, 0.8 * k))
	ci.draw_rect(Rect2(_p(box, 0.535, 0.53), Vector2(box.size.x * 0.05, box.size.y * 0.09)), INK)
	_stroke(ci, drum, INK, lw)
	var dome_c := _p(box, 0.56, 0.44)
	var dome := _ellipse(dome_c, box.size.x * 0.14, box.size.y * 0.13, 24, PI, TAU)
	dome.append(dome_c + Vector2(box.size.x * 0.14, 0))
	ci.draw_colored_polygon(dome, UITheme.PARCHMENT)
	# Solo media cupula tiene chapa: la otra mitad son nervios al aire.
	var half := PackedVector2Array([dome_c])
	half.append_array(_ellipse(dome_c, box.size.x * 0.14, box.size.y * 0.13, 12, PI, PI * 1.5))
	_crosshatch(ci, half, 2.4 * k, INK_SOFT, maxf(1.0, 0.7 * k))
	_stroke(ci, _ellipse(dome_c, box.size.x * 0.14, box.size.y * 0.13, 24, PI, TAU), INK, lw, false)
	for i in 4:
		var a := PI * 1.5 + PI * 0.5 * float(i) / 4.0
		ci.draw_line(dome_c, dome_c + Vector2(cos(a) * box.size.x * 0.14, sin(a) * box.size.y * 0.13), INK, maxf(1.0, 0.9 * k))
	# El andamio a la derecha: pies, travesanos y una cruz.
	for u in [0.72, 0.8]:
		ci.draw_line(_p(box, u, 0.62), _p(box, u, 0.36), INK, maxf(1.0, 1.2 * k))
	for v in [0.42, 0.52]:
		ci.draw_line(_p(box, 0.68, v), _p(box, 0.82, v), INK, maxf(1.0, 1.2 * k))
	ci.draw_line(_p(box, 0.72, 0.62), _p(box, 0.8, 0.52), INK_SOFT, maxf(1.0, k))
	ci.draw_line(_p(box, 0.72, 0.52), _p(box, 0.8, 0.42), INK_SOFT, maxf(1.0, k))
	# La bandera roja en lo alto del andamio.
	var top := _p(box, 0.8, 0.36)
	ci.draw_line(top, top + Vector2(0, -box.size.y * 0.08), INK, maxf(1.0, k))
	var flag := PackedVector2Array([top + Vector2(0, -box.size.y * 0.08), top + Vector2(box.size.x * 0.07, -box.size.y * 0.065), top + Vector2(0, -box.size.y * 0.045)])
	ci.draw_colored_polygon(flag, RED)
	# Los arboles a la izquierda.
	_tree(ci, _p(box, 0.1, 0.64), box.size.y * 0.3, k)
	_tree(ci, _p(box, 0.22, 0.63), box.size.y * 0.24, k)
	_tree(ci, _p(box, 0.32, 0.65), box.size.y * 0.18, k)
	# Delante: el monton de ladrillos y el martillo.
	for row in 3:
		for i in 4 - row:
			var bx := 0.12 + 0.075 * float(i) + 0.037 * float(row)
			var by := 0.9 - 0.045 * float(row)
			var brick := Rect2(_p(box, bx, by), Vector2(box.size.x * 0.07, box.size.y * 0.04))
			ci.draw_rect(brick, UITheme.PARCHMENT)
			_hatch(ci, PackedVector2Array([brick.position, brick.position + Vector2(brick.size.x, 0), brick.end, brick.position + Vector2(0, brick.size.y)]), 45.0, 2.4 * k, INK_SOFT, maxf(1.0, 0.7 * k))
			ci.draw_rect(brick, INK, false, maxf(1.0, k))
	var handle_a := _p(box, 0.62, 0.95)
	var handle_b := _p(box, 0.84, 0.8)
	ci.draw_line(handle_a, handle_b, INK, maxf(2.0, 3.0 * k))
	var dir := (handle_b - handle_a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var head := PackedVector2Array([handle_b + side * 9.0 * k - dir * 3.0 * k, handle_b + side * 9.0 * k + dir * 5.0 * k, handle_b - side * 7.0 * k + dir * 5.0 * k, handle_b - side * 7.0 * k - dir * 3.0 * k])
	ci.draw_colored_polygon(head, INK)

## Folio B (Constructor): el vigia de costa mira con su catalejo el humo
## lejano de la isla.
static func _lookout(ci: CanvasItem, box: Rect2, k: float) -> void:
	var lw := maxf(1.0, 1.4 * k)
	ci.draw_line(_p(box, 0.0, 0.55), _p(box, 1.0, 0.55), INK, maxf(1.0, k))
	_sea(ci, box, 0.6, 0.98, k, 8)
	# La isla lejana con su humo.
	var far := _pts(box, [0.6, 0.55, 0.68, 0.5, 0.78, 0.48, 0.88, 0.52, 0.94, 0.55])
	ci.draw_colored_polygon(far, UITheme.PARCHMENT)
	_hatch(ci, far, 0.0, 2.2 * k, INK_SOFT, maxf(1.0, 0.7 * k))
	_stroke(ci, far, INK, maxf(1.0, k), false)
	_smoke(ci, _p(box, 0.77, 0.48), k, box.size.y * 0.24, box.size.x * 0.1)
	# La roca del vigia, en primer plano a la izquierda.
	var rock := _pts(box, [0.0, 1.0, 0.0, 0.62, 0.12, 0.58, 0.3, 0.64, 0.42, 0.76, 0.46, 1.0])
	ci.draw_colored_polygon(rock, UITheme.PARCHMENT)
	_crosshatch(ci, rock, 2.8 * k, INK_SOFT, maxf(1.0, 0.75 * k))
	_stroke(ci, rock, INK, lw)
	# El vigia: muneco de tinta con gorra y el catalejo hacia la isla.
	var foot := _p(box, 0.2, 0.6)
	var hgt := box.size.y * 0.2
	ci.draw_line(foot, foot + Vector2(0, -hgt * 0.65), INK, maxf(2.0, 3.0 * k))
	ci.draw_circle(foot + Vector2(0, -hgt * 0.8), hgt * 0.12, INK)
	ci.draw_rect(Rect2(foot + Vector2(-hgt * 0.13, -hgt * 0.96), Vector2(hgt * 0.26, hgt * 0.06)), INK)
	var eye := foot + Vector2(hgt * 0.08, -hgt * 0.8)
	var tip := eye + (_p(box, 0.77, 0.47) - eye).normalized() * hgt * 0.7
	ci.draw_line(eye, tip, INK, maxf(2.0, 3.4 * k))
	ci.draw_line(foot + Vector2(0, -hgt * 0.5), eye + (tip - eye) * 0.4, INK, maxf(1.0, 1.4 * k))
	# El acento rojo: el libro de cuentas abierto a sus pies.
	var book := PackedVector2Array([foot + Vector2(hgt * 0.15, 0), foot + Vector2(hgt * 0.55, -hgt * 0.04), foot + Vector2(hgt * 0.55, hgt * 0.08), foot + Vector2(hgt * 0.15, hgt * 0.1)])
	ci.draw_colored_polygon(book, RED)
	_stroke(ci, book, INK, maxf(1.0, k))
