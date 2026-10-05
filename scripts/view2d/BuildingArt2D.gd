extends RefCounted
## El dibujo de los edificios y yacimientos de la vista 2D, en codigo.
##
## Sin pipeline de arte: cada edificio es su huella exacta vista desde arriba,
## con una silueta que se reconoce de un vistazo (la cupula del Nucleo, las
## chimeneas de la Fundicion, los tanques de la Refineria...) en la paleta
## dieselpunk de DieselpunkBuildingFactory y UITheme: hierro, laton, oxido,
## hormigon, fuego.
##
## Todo se dibuja centrado en (0, 0) sobre un CanvasItem, con la huella SIN girar
## (`size` en pixeles); quien llama aplica el giro con draw_set_transform. Lo usan
## Building2D (el mapa), el fantasma de colocacion y el icono del menu de
## construccion, asi que las tres cosas son siempre el mismo dibujo.

# ── Paleta (la de DieselpunkBuildingFactory, vista desde arriba) ─────────
const IRON := Color(0.22, 0.20, 0.22)
const GUNMETAL := Color(0.30, 0.30, 0.33)
const STEEL := Color(0.46, 0.47, 0.50)
const BRASS := Color(0.77, 0.59, 0.16)
const BRASS_LIGHT := Color(0.93, 0.78, 0.32)
const COPPER := Color(0.65, 0.38, 0.22)
const RUST := Color(0.50, 0.28, 0.15)
const DARK_WOOD := Color(0.30, 0.20, 0.10)
const WOOD := Color(0.52, 0.36, 0.19)
const LIGHT_WOOD := Color(0.66, 0.50, 0.30)
const CONCRETE := Color(0.46, 0.44, 0.41)
const CONCRETE_DARK := Color(0.33, 0.31, 0.29)
const FIRE := Color(1.0, 0.50, 0.08)
const FIRE_CORE := Color(1.0, 0.85, 0.35)
const OIL_BLACK := Color(0.08, 0.08, 0.10)
const OLIVE := Color(0.33, 0.37, 0.20)
const OLIVE_DARK := Color(0.23, 0.26, 0.14)
const TILE_RED := Color(0.55, 0.22, 0.15)
const TILE_RED_DARK := Color(0.42, 0.16, 0.11)
const MARBLE := Color(0.84, 0.80, 0.73)
const WATER := Color(0.25, 0.55, 0.78)
const LEAF := Color(0.26, 0.50, 0.18)
const LEAF_DARK := Color(0.16, 0.34, 0.11)
const OUTLINE := Color(0.05, 0.045, 0.035, 0.95)
const SHADOW := Color(0.0, 0.0, 0.0, 0.28)
const IMPERIAL_RED := Color(0.72, 0.13, 0.10)
## Obra: tierra removida y el amarillo de peligro (el de la grua en 3D).
const SITE_DIRT := Color(0.40, 0.30, 0.20)
const HAZARD := Color(0.95, 0.75, 0.12)

## Hueco entre la huella y el borde del dibujo, para que dos edificios pegados
## se lean como dos.
const INSET := 2.0

# ── Entrada ───────────────────────────────────────────────────────────

## Dibuja el edificio `id` con huella `size` (px, sin girar) centrado en el origen.
## `opts`: "road_mask" (int, calzadas), "level" (int), "shadow" (bool, por defecto true).
static func draw_building(ci: CanvasItem, id: String, size: Vector2, opts: Dictionary = {}) -> void:
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	if id == "road":
		_road(ci, Rect2(-size * 0.5, size), int(opts.get("road_mask", 0)))
		return
	if bool(opts.get("shadow", true)):
		ci.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), SHADOW)
	match id:
		"nucleo": _nucleo(ci, r)
		"house": _house(ci, r)
		"sawmill": _sawmill(ci, r)
		"gold_mine": _gold_mine(ci, r)
		"warehouse": _warehouse(ci, r)
		"market": _market(ci, r)
		"laboratory": _laboratory(ci, r)
		"foundry": _foundry(ci, r)
		"barracks": _barracks(ci, r)
		"refinery": _refinery(ci, r)
		"tower": _tower(ci, r)
		"headquarters": _headquarters(ci, r)
		"garden": _garden(ci, r)
		"fountain": _fountain(ci, r)
		"statue": _statue(ci, r)
		_:
			_plate(ci, r, CONCRETE, IRON)
	var level: int = int(opts.get("level", 1))
	if level > 1:
		_level_chevrons(ci, r, level)

# ── Primitivas ────────────────────────────────────────────────────────

static func _plate(ci: CanvasItem, r: Rect2, fill: Color, border: Color, width: float = 2.0) -> void:
	ci.draw_rect(r, fill)
	# Luz arriba-izquierda, sombra abajo-derecha: relieve sin 3D.
	ci.draw_line(r.position + Vector2(1, 1), Vector2(r.end.x - 1, r.position.y + 1), fill.lightened(0.25), 2.0)
	ci.draw_line(r.position + Vector2(1, 1), Vector2(r.position.x + 1, r.end.y - 1), fill.lightened(0.18), 2.0)
	ci.draw_line(Vector2(r.position.x + 1, r.end.y - 1), r.end - Vector2(1, 1), fill.darkened(0.35), 2.0)
	ci.draw_line(Vector2(r.end.x - 1, r.position.y + 1), r.end - Vector2(1, 1), fill.darkened(0.3), 2.0)
	ci.draw_rect(r, border, false, width)

static func _rivets(ci: CanvasItem, r: Rect2, color: Color = BRASS, inset: float = 4.0) -> void:
	for p in [r.position + Vector2(inset, inset), Vector2(r.end.x - inset, r.position.y + inset),
			Vector2(r.position.x + inset, r.end.y - inset), r.end - Vector2(inset, inset)]:
		ci.draw_circle(p, 1.6, color)
		ci.draw_circle(p + Vector2(-0.4, -0.4), 0.7, color.lightened(0.5))

static func _disc(ci: CanvasItem, c: Vector2, radius: float, fill: Color, outline := OUTLINE, width := 1.5) -> void:
	ci.draw_circle(c, radius, fill)
	ci.draw_arc(c, radius, 0.0, TAU, maxi(12, int(radius * 1.5)), outline, width, true)

static func _shaded_disc(ci: CanvasItem, c: Vector2, radius: float, fill: Color) -> void:
	ci.draw_circle(c, radius, fill.darkened(0.2))
	ci.draw_circle(c - Vector2(radius, radius) * 0.18, radius * 0.78, fill)
	ci.draw_circle(c - Vector2(radius, radius) * 0.38, radius * 0.3, fill.lightened(0.35))
	ci.draw_arc(c, radius, 0.0, TAU, maxi(12, int(radius * 1.5)), OUTLINE, 1.5, true)

static func _poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, outline := OUTLINE, width := 1.5) -> void:
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, outline, width, true)

static func _level_chevrons(ci: CanvasItem, r: Rect2, level: int) -> void:
	for i in range(level - 1):
		var base := Vector2(r.end.x - 6.0 - i * 7.0, r.end.y - 5.0)
		var pts := PackedVector2Array([base + Vector2(-3, 0), base + Vector2(0, -3), base + Vector2(3, 0), base + Vector2(3, 2), base + Vector2(0, -1), base + Vector2(-3, 2)])
		ci.draw_colored_polygon(pts, BRASS_LIGHT)

static func _smoke(ci: CanvasItem, c: Vector2, s: float) -> void:
	ci.draw_circle(c + Vector2(2, -2) * s, 3.2 * s, Color(0.75, 0.75, 0.72, 0.45))
	ci.draw_circle(c + Vector2(5, -5) * s, 2.4 * s, Color(0.8, 0.8, 0.78, 0.35))

# ── Edificios ─────────────────────────────────────────────────────────

static func _nucleo(ci: CanvasItem, r: Rect2) -> void:
	var c := r.get_center()
	var h := minf(r.size.x, r.size.y) * 0.5
	# Base octogonal de hormigon
	var oct := PackedVector2Array()
	for i in range(8):
		var a := TAU * (i + 0.5) / 8.0
		oct.append(c + Vector2(cos(a), sin(a)) * h * 1.06)
	_poly(ci, oct, CONCRETE, OUTLINE, 2.0)
	# Tuberias a las esquinas
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		ci.draw_line(c + d * h * 0.35, c + d * h * 0.8, COPPER.darkened(0.2), 5.0)
		ci.draw_line(c + d * h * 0.35, c + d * h * 0.8, COPPER, 3.0)
		_disc(ci, c + d * h * 0.8, 3.5, IRON)
	# Anillo de laton y cupula
	_disc(ci, c, h * 0.66, BRASS, OUTLINE, 2.0)
	_shaded_disc(ci, c, h * 0.55, GUNMETAL.lightened(0.1))
	# Engranaje imperial
	for i in range(10):
		var a := TAU * i / 10.0
		ci.draw_line(c + Vector2(cos(a), sin(a)) * h * 0.16, c + Vector2(cos(a), sin(a)) * h * 0.3, BRASS_LIGHT, 3.0)
	_disc(ci, c, h * 0.2, BRASS, OUTLINE, 1.5)
	_disc(ci, c, h * 0.08, IMPERIAL_RED, OUTLINE, 1.0)

static func _house(ci: CanvasItem, r: Rect2) -> void:
	var c := r.get_center()
	ci.draw_rect(r, TILE_RED)
	# Dos aguas: mitad en sombra
	ci.draw_rect(Rect2(Vector2(r.position.x, c.y), Vector2(r.size.x, r.size.y * 0.5)), TILE_RED_DARK)
	# Tejas
	var rows := 4
	for i in range(1, rows):
		var y := r.position.y + r.size.y * i / float(rows)
		ci.draw_line(Vector2(r.position.x + 1, y), Vector2(r.end.x - 1, y), TILE_RED.darkened(0.35), 1.0)
	ci.draw_line(Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), BRASS.darkened(0.2), 2.0)
	ci.draw_rect(r, OUTLINE, false, 2.0)
	# Chimenea
	var ch := Rect2(Vector2(r.end.x - r.size.x * 0.34, r.position.y + r.size.y * 0.12), Vector2(r.size.x * 0.18, r.size.y * 0.2))
	ci.draw_rect(ch, CONCRETE_DARK)
	ci.draw_rect(ch, OUTLINE, false, 1.0)
	_smoke(ci, ch.get_center(), 0.8)

static func _sawmill(ci: CanvasItem, r: Rect2) -> void:
	var long_x := r.size.x >= r.size.y
	_plate(ci, r, WOOD, OUTLINE)
	# Tablones
	var n := 7
	for i in range(1, n):
		if long_x:
			var y := r.position.y + r.size.y * i / float(n)
			ci.draw_line(Vector2(r.position.x + 2, y), Vector2(r.end.x - 2, y), DARK_WOOD, 1.0)
		else:
			var x := r.position.x + r.size.x * i / float(n)
			ci.draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2), DARK_WOOD, 1.0)
	# Pila de troncos en un extremo, sierra en el otro
	var a := r.position + r.size * (Vector2(0.27, 0.5) if long_x else Vector2(0.5, 0.27))
	var b := r.position + r.size * (Vector2(0.72, 0.5) if long_x else Vector2(0.5, 0.72))
	var lr := minf(r.size.x, r.size.y) * 0.17
	for off in [Vector2(-1, -0.5), Vector2(1, -0.5), Vector2(0, 0.55)]:
		var p: Vector2 = a + off * lr * 1.05
		_disc(ci, p, lr, LIGHT_WOOD)
		ci.draw_arc(p, lr * 0.55, 0.0, TAU, 12, DARK_WOOD, 1.0)
		ci.draw_circle(p, lr * 0.15, DARK_WOOD)
	var sr := minf(r.size.x, r.size.y) * 0.34
	for i in range(16):
		var ang := TAU * i / 16.0
		ci.draw_line(b + Vector2(cos(ang), sin(ang)) * sr * 0.8, b + Vector2(cos(ang + 0.2), sin(ang + 0.2)) * sr, STEEL.lightened(0.2), 2.0)
	_disc(ci, b, sr * 0.82, STEEL)
	ci.draw_arc(b, sr * 0.55, 0.0, TAU, 16, STEEL.lightened(0.3), 1.0)
	_disc(ci, b, sr * 0.2, BRASS)

static func _gold_mine(ci: CanvasItem, r: Rect2) -> void:
	var c := r.get_center()
	_plate(ci, r, Color(0.45, 0.38, 0.28), OUTLINE)
	# Vias de vagoneta
	ci.draw_line(Vector2(r.position.x + 4, c.y + r.size.y * 0.28), Vector2(r.end.x - 4, c.y + r.size.y * 0.28), IRON, 2.0)
	ci.draw_line(Vector2(r.position.x + 4, c.y + r.size.y * 0.36), Vector2(r.end.x - 4, c.y + r.size.y * 0.36), IRON, 2.0)
	for i in range(8):
		var x := r.position.x + 6 + i * (r.size.x - 12) / 7.0
		ci.draw_line(Vector2(x, c.y + r.size.y * 0.25), Vector2(x, c.y + r.size.y * 0.39), DARK_WOOD, 2.0)
	# Pozo y castillete
	var shaft := Rect2(c - Vector2(r.size.x * 0.17, r.size.y * 0.3), Vector2(r.size.x * 0.34, r.size.y * 0.34))
	ci.draw_rect(shaft, Color(0.04, 0.03, 0.03))
	ci.draw_rect(shaft, OUTLINE, false, 1.5)
	ci.draw_line(shaft.position, shaft.end, DARK_WOOD.lightened(0.2), 3.0)
	ci.draw_line(Vector2(shaft.end.x, shaft.position.y), Vector2(shaft.position.x, shaft.end.y), DARK_WOOD.lightened(0.2), 3.0)
	_disc(ci, shaft.get_center(), 4.0, BRASS)
	# Vagoneta con oro y pepitas sueltas
	var cart := Rect2(Vector2(r.position.x + r.size.x * 0.62, c.y + r.size.y * 0.2), Vector2(r.size.x * 0.22, r.size.y * 0.2))
	ci.draw_rect(cart, RUST)
	ci.draw_rect(cart, OUTLINE, false, 1.5)
	for p in [Vector2(0.3, 0.4), Vector2(0.6, 0.35), Vector2(0.45, 0.65)]:
		ci.draw_circle(cart.position + cart.size * p, 2.6, BRASS_LIGHT)
	for p in [Vector2(0.18, 0.2), Vector2(0.82, 0.24), Vector2(0.15, 0.62)]:
		ci.draw_circle(r.position + r.size * p, 2.2, BRASS_LIGHT)
		ci.draw_circle(r.position + r.size * p, 1.0, Color(1, 0.95, 0.7))

## Mercado visto desde arriba: tres toldos a rayas sobre un entarimado.
static func _market(ci: CanvasItem, r: Rect2) -> void:
	_plate(ci, r, LIGHT_WOOD.darkened(0.25), OUTLINE)
	var cols := [Color(0.72, 0.18, 0.12), Color(0.85, 0.7, 0.25), Color(0.2, 0.42, 0.6)]
	for i in 3:
		var w := r.size.x * 0.28
		var tr := Rect2(Vector2(r.position.x + r.size.x * (0.06 + 0.32 * i), r.position.y + r.size.y * (0.12 if i != 1 else 0.45)), Vector2(w, r.size.y * 0.4))
		ci.draw_rect(tr, cols[i])
		for k in range(1, 4):
			var x := tr.position.x + tr.size.x * k / 4.0
			ci.draw_line(Vector2(x, tr.position.y), Vector2(x, tr.end.y), Color(1, 1, 1, 0.35), 2.0)
		ci.draw_rect(tr, OUTLINE, false, 1.0)

## Laboratorio: hormigon con una cupula de cristal que brilla.
static func _laboratory(ci: CanvasItem, r: Rect2) -> void:
	_plate(ci, r, CONCRETE, OUTLINE)
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) * 0.28
	ci.draw_circle(c, rad + 2.0, OUTLINE)
	ci.draw_circle(c, rad, Color(0.35, 0.8, 0.95))
	ci.draw_circle(c + Vector2(-rad * 0.3, -rad * 0.3), rad * 0.3, Color(0.85, 0.97, 1.0, 0.7))
	ci.draw_line(Vector2(r.end.x - 6, r.position.y + 5), Vector2(r.end.x - 6, r.position.y + r.size.y * 0.4), IRON, 2.0)
	_rivets(ci, r)

static func _warehouse(ci: CanvasItem, r: Rect2) -> void:
	_plate(ci, r, GUNMETAL, OUTLINE)
	# Chapa ondulada
	var n := 6
	for i in range(1, n):
		var x := r.position.x + r.size.x * i / float(n)
		ci.draw_line(Vector2(x, r.position.y + 3), Vector2(x, r.end.y - 3), GUNMETAL.lightened(0.18), 1.0)
	# Franja de laton y portón
	ci.draw_rect(Rect2(Vector2(r.position.x, r.get_center().y - 2), Vector2(r.size.x, 4)), BRASS)
	var door := Rect2(Vector2(r.get_center().x - r.size.x * 0.2, r.end.y - r.size.y * 0.3), Vector2(r.size.x * 0.4, r.size.y * 0.3))
	ci.draw_rect(door, RUST)
	ci.draw_rect(door, OUTLINE, false, 1.0)
	_rivets(ci, r)

static func _foundry(ci: CanvasItem, r: Rect2) -> void:
	var long_x := r.size.x >= r.size.y
	_plate(ci, r, Color(0.45, 0.25, 0.18), OUTLINE)
	# Ladrillo
	var rows := 5
	for i in range(1, rows):
		if long_x:
			var y := r.position.y + r.size.y * i / float(rows)
			ci.draw_line(Vector2(r.position.x + 2, y), Vector2(r.end.x - 2, y), Color(0.32, 0.17, 0.12), 1.0)
		else:
			var x := r.position.x + r.size.x * i / float(rows)
			ci.draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2), Color(0.32, 0.17, 0.12), 1.0)
	# Boca del horno encendida en el centro
	var c := r.get_center()
	var m := minf(r.size.x, r.size.y)
	var mouth := Rect2(c - Vector2(m * 0.3, m * 0.22), Vector2(m * 0.6, m * 0.44))
	ci.draw_rect(mouth, IRON)
	ci.draw_rect(mouth.grow(-3), FIRE)
	ci.draw_rect(mouth.grow(-6), FIRE_CORE)
	ci.draw_rect(mouth, OUTLINE, false, 1.5)
	# Dos chimeneas en los extremos
	var ends: Array = [Vector2(0.14, 0.5), Vector2(0.86, 0.5)] if long_x else [Vector2(0.5, 0.14), Vector2(0.5, 0.86)]
	for e in ends:
		var p: Vector2 = r.position + r.size * (e as Vector2)
		_disc(ci, p, m * 0.26, CONCRETE_DARK)
		ci.draw_circle(p, m * 0.15, Color(0.08, 0.06, 0.05))
		ci.draw_circle(p, m * 0.07, FIRE)
		_smoke(ci, p, 1.0)

static func _barracks(ci: CanvasItem, r: Rect2) -> void:
	var c := r.get_center()
	# Sacos terreros alrededor
	ci.draw_rect(r, Color(0.55, 0.50, 0.36))
	var step := 8.0
	var x := r.position.x + 1
	while x < r.end.x - 4:
		ci.draw_rect(Rect2(Vector2(x, r.position.y + 1), Vector2(step - 1, 5)), Color(0.65, 0.58, 0.40))
		ci.draw_rect(Rect2(Vector2(x, r.end.y - 6), Vector2(step - 1, 5)), Color(0.65, 0.58, 0.40))
		x += step
	ci.draw_rect(r, OUTLINE, false, 2.0)
	# Tejado verde oliva con la estrella
	var roof := r.grow(-8)
	_plate(ci, roof, OLIVE, OUTLINE)
	ci.draw_line(Vector2(roof.position.x, c.y), Vector2(roof.end.x, c.y), OLIVE_DARK, 2.0)
	_star(ci, c, minf(roof.size.x, roof.size.y) * 0.24, BRASS_LIGHT)
	# Mastil con bandera
	var pole := Vector2(roof.end.x - 5, roof.position.y + 4)
	ci.draw_line(pole, pole + Vector2(0, 14), IRON, 2.0)
	ci.draw_colored_polygon(PackedVector2Array([pole, pole + Vector2(-11, 3), pole + Vector2(0, 6)]), IMPERIAL_RED)

static func _refinery(ci: CanvasItem, r: Rect2) -> void:
	_plate(ci, r, CONCRETE_DARK, OUTLINE)
	var m := minf(r.size.x, r.size.y)
	var t1 := r.position + r.size * Vector2(0.3, 0.32)
	var t2 := r.position + r.size * Vector2(0.3, 0.72)
	var t3 := r.position + r.size * Vector2(0.7, 0.62)
	# Tuberias entre tanques
	for pair in [[t1, t3], [t2, t3], [t1, t2]]:
		ci.draw_line(pair[0], pair[1], COPPER.darkened(0.25), 5.0)
		ci.draw_line(pair[0], pair[1], COPPER, 3.0)
	for t in [t1, t2]:
		_shaded_disc(ci, t, m * 0.17, STEEL)
		ci.draw_arc(t, m * 0.1, 0.0, TAU, 16, STEEL.darkened(0.3), 1.0)
	_shaded_disc(ci, t3, m * 0.22, Color(0.55, 0.52, 0.45))
	ci.draw_arc(t3, m * 0.13, 0.0, TAU, 16, RUST, 2.0)
	# Antorcha de gas
	var flare := r.position + r.size * Vector2(0.78, 0.2)
	_disc(ci, flare, 4.0, IRON)
	ci.draw_circle(flare + Vector2(0, -1), 3.2, FIRE)
	ci.draw_circle(flare + Vector2(0, -1.5), 1.6, FIRE_CORE)
	_rivets(ci, r, BRASS, 4.0)

static func _tower(ci: CanvasItem, r: Rect2) -> void:
	var c := r.get_center()
	var h := minf(r.size.x, r.size.y) * 0.5
	ci.draw_rect(r.grow(-2), CONCRETE_DARK.darkened(0.2))
	ci.draw_rect(r.grow(-2), OUTLINE, false, 1.5)
	_shaded_disc(ci, c, h * 0.8, CONCRETE)
	# Almenas
	for i in range(8):
		var a := TAU * i / 8.0
		ci.draw_circle(c + Vector2(cos(a), sin(a)) * h * 0.72, 1.8, CONCRETE_DARK)
	# Cañon y reflector
	ci.draw_line(c, c + Vector2(h * 0.95, -h * 0.35), IRON, 4.0)
	ci.draw_line(c, c + Vector2(h * 0.95, -h * 0.35), GUNMETAL.lightened(0.2), 2.0)
	_disc(ci, c, h * 0.3, GUNMETAL)
	ci.draw_circle(c + Vector2(-h * 0.35, h * 0.35), 3.0, Color(1.0, 0.95, 0.7))

static func _headquarters(ci: CanvasItem, r: Rect2) -> void:
	var c := r.get_center()
	_plate(ci, r, MARBLE.darkened(0.15), OUTLINE, 2.5)
	var inner := r.grow(-6)
	_plate(ci, inner, MARBLE, BRASS, 2.0)
	# Estandartes imperiales
	var bw := inner.size.x * 0.16
	for fx in [0.12, 0.72]:
		var band := Rect2(Vector2(inner.position.x + inner.size.x * fx, inner.position.y + 3), Vector2(bw, inner.size.y - 6))
		ci.draw_rect(band, IMPERIAL_RED)
		ci.draw_rect(Rect2(band.position + Vector2(bw * 0.4, 0), Vector2(bw * 0.2, band.size.y)), BRASS)
		ci.draw_rect(band, OUTLINE, false, 1.0)
	# Aguila / estrella al centro, con neon ambar
	_disc(ci, c, minf(inner.size.x, inner.size.y) * 0.24, Color(0.18, 0.18, 0.2), BRASS, 2.0)
	_star(ci, c, minf(inner.size.x, inner.size.y) * 0.18, Color(1.0, 0.75, 0.15))
	_rivets(ci, r, BRASS_LIGHT, 3.5)

static func _garden(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, LEAF_DARK)
	ci.draw_rect(r.grow(-3), LEAF)
	var pts := [Vector2(0.25, 0.3), Vector2(0.7, 0.25), Vector2(0.5, 0.55), Vector2(0.28, 0.75), Vector2(0.75, 0.72)]
	var cols := [Color(0.95, 0.35, 0.3), Color(0.98, 0.85, 0.3), Color(0.85, 0.45, 0.85), Color(1, 1, 0.95), Color(0.95, 0.55, 0.2)]
	for i in range(pts.size()):
		var p: Vector2 = r.position + r.size * (pts[i] as Vector2)
		ci.draw_circle(p, 3.2, LEAF_DARK)
		ci.draw_circle(p, 2.0, cols[i])
	ci.draw_rect(r, OUTLINE, false, 1.5)

static func _fountain(ci: CanvasItem, r: Rect2) -> void:
	var c := r.get_center()
	var h := minf(r.size.x, r.size.y) * 0.5
	ci.draw_rect(r, CONCRETE.lightened(0.1))
	ci.draw_rect(r, OUTLINE, false, 1.5)
	_disc(ci, c, h * 0.86, MARBLE.darkened(0.1))
	ci.draw_circle(c, h * 0.68, WATER)
	ci.draw_arc(c, h * 0.45, 0.4, 2.2, 10, WATER.lightened(0.4), 1.0)
	ci.draw_arc(c, h * 0.3, 3.5, 5.2, 10, WATER.lightened(0.4), 1.0)
	_disc(ci, c, h * 0.18, MARBLE)
	ci.draw_circle(c, h * 0.08, Color(0.85, 0.95, 1.0))

static func _statue(ci: CanvasItem, r: Rect2) -> void:
	var c := r.get_center()
	var h := minf(r.size.x, r.size.y) * 0.5
	_plate(ci, r.grow(-1), CONCRETE, OUTLINE)
	_plate(ci, r.grow(-h * 0.35), MARBLE.darkened(0.08), OUTLINE, 1.5)
	# Figura vista desde arriba: hombros, cabeza y laurel dorado
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.42, h * 0.12), c + Vector2(h * 0.42, h * 0.12), c + Vector2(h * 0.3, h * 0.3), c + Vector2(-h * 0.3, h * 0.3)]), MARBLE)
	_disc(ci, c + Vector2(0, -h * 0.05), h * 0.2, MARBLE.lightened(0.1))
	ci.draw_arc(c + Vector2(0, -h * 0.05), h * 0.22, PI * 0.9, PI * 2.1, 10, BRASS_LIGHT, 2.0)

## Calzada: adoquin oscuro, con un brazo hacia cada vecino que tambien es calzada.
static func _road(ci: CanvasItem, cell_rect: Rect2, mask: int) -> void:
	# La celda entera, como en 3D: los tramos vecinos se tocan y la red se lee
	# como una sola carretera. Acera clara en los lados que no siguen la calle.
	var base := Color(0.36, 0.34, 0.31)
	var curb := Color(0.64, 0.6, 0.54)
	var line := Color(0.85, 0.72, 0.3)
	ci.draw_rect(cell_rect, base)
	# Adoquines
	var y := cell_rect.position.y + 3.0
	var row := 0
	while y < cell_rect.end.y - 2.0:
		var x := cell_rect.position.x + (3.0 if row % 2 == 0 else 6.0)
		while x < cell_rect.end.x - 2.0:
			ci.draw_rect(Rect2(Vector2(x, y), Vector2(4, 3)), base.lightened(0.1))
			x += 6.0
		y += 5.0
		row += 1
	var cw := cell_rect.size.x * 0.16
	var p0 := cell_rect.position
	var sz := cell_rect.size
	if not (mask & 1):
		ci.draw_rect(Rect2(p0, Vector2(sz.x, cw)), curb)
	if not (mask & 4):
		ci.draw_rect(Rect2(Vector2(p0.x, p0.y + sz.y - cw), Vector2(sz.x, cw)), curb)
	if not (mask & 2):
		ci.draw_rect(Rect2(Vector2(p0.x + sz.x - cw, p0.y), Vector2(cw, sz.y)), curb)
	if not (mask & 8):
		ci.draw_rect(Rect2(p0, Vector2(cw, sz.y)), curb)
	var c := cell_rect.get_center()
	if (mask & 1) and (mask & 4) and not (mask & 2) and not (mask & 8):
		ci.draw_rect(Rect2(Vector2(c.x - 1.0, p0.y), Vector2(2.0, sz.y)), line)
	elif (mask & 2) and (mask & 8) and not (mask & 1) and not (mask & 4):
		ci.draw_rect(Rect2(Vector2(p0.x, c.y - 1.0), Vector2(sz.x, 2.0)), line)

static func _star(ci: CanvasItem, c: Vector2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var a := -PI * 0.5 + TAU * i / 10.0
		var rr := radius if i % 2 == 0 else radius * 0.42
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	_poly(ci, pts, color, OUTLINE, 1.0)

# ── Estados encima del dibujo ─────────────────────────────────────────

## Obra: rayas de peligro en el borde, andamio en aspa y barra de progreso.
static func draw_construction(ci: CanvasItem, size: Vector2, progress: float) -> void:
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	ci.draw_rect(r, Color(0.12, 0.1, 0.06, 0.45))
	# Andamio
	ci.draw_line(r.position, r.end, LIGHT_WOOD, 2.0)
	ci.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), LIGHT_WOOD, 2.0)
	# Rayas amarillo/negro por el borde
	var stripe := 6.0
	var t := 0.0
	var perimeter := 2.0 * (r.size.x + r.size.y)
	var i := 0
	while t < perimeter:
		var col := Color(0.95, 0.75, 0.12) if i % 2 == 0 else Color(0.08, 0.07, 0.05)
		var a := _perimeter_point(r, t)
		var b := _perimeter_point(r, minf(t + stripe, perimeter))
		ci.draw_line(a, b, col, 3.0)
		t += stripe
		i += 1
	# Barra de progreso bajo la huella
	var bar := Rect2(Vector2(r.position.x + 3, r.end.y - 7), Vector2(r.size.x - 6, 4))
	ci.draw_rect(bar.grow(1), OUTLINE)
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(progress, 0.0, 1.0), bar.size.y)), Color(1.0, 0.8, 0.2))

static func _perimeter_point(r: Rect2, t: float) -> Vector2:
	if t <= r.size.x:
		return r.position + Vector2(t, 0)
	t -= r.size.x
	if t <= r.size.y:
		return Vector2(r.end.x, r.position.y + t)
	t -= r.size.y
	if t <= r.size.x:
		return Vector2(r.end.x - t, r.end.y)
	t -= r.size.x
	return Vector2(r.position.x, r.end.y - t)

## Dano: ceniza encima en proporcion a lo perdido (como la capa 3D); en ruinas,
## el dibujo de ruina (draw_ruin). Mas una barra de vida si esta tocado.
## `n`: clase de huella (1, 2, 3), para el tamano de los escombros de la ruina.
static func draw_damage(ci: CanvasItem, size: Vector2, ratio: float, ruined: bool, seed_val: int, n: int = 2) -> void:
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	if ratio >= 1.0 and not ruined:
		return
	ci.draw_rect(r, Color(0.10, 0.09, 0.08, (1.0 - ratio) * 0.75))
	if ruined:
		# La ruina tiene dibujo propio (muro roto, cascotes, vigas); el humo
		# negro lo anima Building2D con la hoja de BuildingFx.
		draw_ruin(ci, size, seed_val, n)
	# Barra de vida
	var bar := Rect2(Vector2(r.position.x + 3, r.position.y + 3), Vector2(r.size.x - 6, 4))
	ci.draw_rect(bar.grow(1), OUTLINE)
	var col := Color(0.85, 0.2, 0.15) if ratio < 0.34 else (Color(0.95, 0.65, 0.15) if ratio < 0.67 else Color(0.4, 0.8, 0.3))
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(ratio, 0.0, 1.0), bar.size.y)), col)

## Borde de seleccion en laton.
static func draw_selection(ci: CanvasItem, size: Vector2, pulse: float) -> void:
	var r := Rect2(-size * 0.5, size).grow(1.0 + pulse * 2.0)
	ci.draw_rect(r, Color(0, 0, 0, 0.6), false, 4.0)
	ci.draw_rect(r, Color(BRASS_LIGHT, 0.75 + pulse * 0.25), false, 2.0)

# ── Obra por fases (compartida por huella) ────────────────────────────

## Las tres fases de obra vistas desde arriba, compartidas por HUELLA como en
## 3D (DieselpunkBuildingFactory.create_construction_phase): 0 valla con
## materiales, 1 solar con cimientos, 2 estructura a medio levantar. Se pinta EN
## LUGAR del edificio; `n` es la clase de huella (1, 2, 3: cuantas pilas,
## cuantos pilares). Lleva debajo la barra de progreso.
static func draw_construction_phase(ci: CanvasItem, size: Vector2, phase: int, progress: float, n: int = 2) -> void:
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	ci.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), SHADOW)
	ci.draw_rect(r, SITE_DIRT)
	# Terrones: la tierra removida se lee como obra, no como cesped.
	for i in range(6 * n):
		var p := r.position + r.size * Vector2(fposmod(i * 0.381, 1.0), fposmod(i * 0.617 + 0.13, 1.0))
		ci.draw_circle(p, 1.4, SITE_DIRT.darkened(0.25))
	match phase:
		0: _site_fence(ci, r, n)
		1: _site_foundation(ci, r, n)
		_: _site_frame(ci, r, n)
	ci.draw_rect(r, OUTLINE, false, 1.5)
	var bar := Rect2(Vector2(r.position.x + 3, r.end.y - 7), Vector2(r.size.x - 6, 4))
	ci.draw_rect(bar.grow(1), OUTLINE)
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(progress, 0.0, 1.0), bar.size.y)), HAZARD)

## Fase 0: valla de tablas con puerta abajo y pilas de material dentro.
static func _site_fence(ci: CanvasItem, r: Rect2, n: int) -> void:
	var fence := r.grow(-2)
	var gate_half := fence.size.x * 0.16
	var gate_c := fence.get_center().x
	# Travesanos
	ci.draw_line(fence.position, Vector2(fence.end.x, fence.position.y), LIGHT_WOOD, 2.0)
	ci.draw_line(fence.position, Vector2(fence.position.x, fence.end.y), LIGHT_WOOD, 2.0)
	ci.draw_line(Vector2(fence.end.x, fence.position.y), fence.end, LIGHT_WOOD, 2.0)
	ci.draw_line(Vector2(fence.position.x, fence.end.y), Vector2(gate_c - gate_half, fence.end.y), LIGHT_WOOD, 2.0)
	ci.draw_line(Vector2(gate_c + gate_half, fence.end.y), fence.end, LIGHT_WOOD, 2.0)
	# Postes
	var step := 7.0
	var t := 0.0
	var perimeter := 2.0 * (fence.size.x + fence.size.y)
	while t < perimeter:
		var p := _perimeter_point(fence, t)
		if not (absf(p.y - fence.end.y) < 0.5 and absf(p.x - gate_c) < gate_half):
			ci.draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), DARK_WOOD)
		t += step
	# Cinta de peligro en la puerta
	ci.draw_line(Vector2(gate_c - gate_half, fence.end.y), Vector2(gate_c + gate_half, fence.end.y), HAZARD, 2.0)
	# Pilas: tablones, vigas, ladrillo
	var spots := [Vector2(0.3, 0.32), Vector2(0.7, 0.58), Vector2(0.32, 0.7)]
	var m := minf(r.size.x, r.size.y)
	for k in n:
		var c: Vector2 = r.position + r.size * (spots[k % spots.size()] as Vector2)
		var pile := Rect2(c - Vector2(m * 0.17, m * 0.1), Vector2(m * 0.34, m * 0.2))
		match k % 3:
			0:
				ci.draw_rect(pile, LIGHT_WOOD)
				for j in range(1, 4):
					var y := pile.position.y + pile.size.y * j / 4.0
					ci.draw_line(Vector2(pile.position.x, y), Vector2(pile.end.x, y), DARK_WOOD, 1.0)
			1:
				for j in 3:
					ci.draw_rect(Rect2(pile.position + Vector2(0, j * pile.size.y / 3.0), Vector2(pile.size.x, pile.size.y / 3.0 - 1.0)), STEEL)
			2:
				ci.draw_rect(pile, TILE_RED)
				ci.draw_line(Vector2(pile.get_center().x, pile.position.y), Vector2(pile.get_center().x, pile.end.y), TILE_RED_DARK, 1.0)
				ci.draw_line(Vector2(pile.position.x, pile.get_center().y), Vector2(pile.end.x, pile.get_center().y), TILE_RED_DARK, 1.0)
		ci.draw_rect(pile, OUTLINE, false, 1.0)

## Fase 1: losa de hormigon con zapatas y esperas de ferralla, conos en dos esquinas.
static func _site_foundation(ci: CanvasItem, r: Rect2, n: int) -> void:
	var slab := r.grow(-r.size.x * 0.08)
	_plate(ci, slab, CONCRETE.lightened(0.2), OUTLINE, 1.5)
	for p in _site_points(slab.grow(-slab.size.x * 0.08), n):
		ci.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), CONCRETE_DARK)
		ci.draw_circle(p + Vector2(-1.5, -1.5), 1.3, RUST)
		ci.draw_circle(p + Vector2(1.5, 1.5), 1.3, RUST)
	for c in [r.position + Vector2(4, 4), r.end - Vector2(4, 10)]:
		_cone(ci, c)

## Fase 2: pilares, medio forjado arriba, vigas de borde, andamio abajo y grua.
static func _site_frame(ci: CanvasItem, r: Rect2, n: int) -> void:
	var slab := r.grow(-r.size.x * 0.08)
	_plate(ci, slab, CONCRETE.lightened(0.2), OUTLINE, 1.5)
	# Medio forjado (mitad de arriba)
	var deck := Rect2(slab.position, Vector2(slab.size.x, slab.size.y * 0.48))
	ci.draw_rect(deck, CONCRETE)
	ci.draw_rect(deck, OUTLINE, false, 1.0)
	# Vigas de borde
	ci.draw_rect(slab.grow(-2), GUNMETAL, false, 3.0)
	for p in _site_points(slab.grow(-slab.size.x * 0.08), n):
		ci.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), GUNMETAL.lightened(0.15))
		ci.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), OUTLINE, false, 1.0)
	# Andamio: tablones en el borde de abajo
	var plank_y := slab.end.y - 6.0
	ci.draw_rect(Rect2(Vector2(slab.position.x + 2, plank_y), Vector2(slab.size.x - 4, 4)), LIGHT_WOOD)
	ci.draw_rect(Rect2(Vector2(slab.position.x + 2, plank_y), Vector2(slab.size.x - 4, 4)), OUTLINE, false, 1.0)
	if n >= 2:
		# Grua: mastil en la esquina de arriba a la derecha, pluma cruzando la obra.
		var mast := Vector2(slab.end.x - 4, slab.position.y + 4)
		var tip := mast + Vector2(-slab.size.x * 0.85, slab.size.y * 0.35)
		ci.draw_line(mast + Vector2(3, 4), tip + Vector2(3, 4), SHADOW, 4.0)
		ci.draw_line(mast, tip, OUTLINE, 4.0)
		ci.draw_line(mast, tip, HAZARD, 2.5)
		ci.draw_rect(Rect2(mast - Vector2(4, 4), Vector2(8, 8)), HAZARD)
		ci.draw_rect(Rect2(mast - Vector2(4, 4), Vector2(8, 8)), OUTLINE, false, 1.0)

## Puntos de pilar: esquinas para la clase 1, rejilla 3x3 para la 2, 4x4 la 3.
static func _site_points(r: Rect2, n: int) -> Array:
	var per := clampi(n, 1, 3) + 1
	var pts: Array = []
	for i in per:
		for j in per:
			pts.append(r.position + r.size * Vector2(float(i) / float(per - 1), float(j) / float(per - 1)))
	return pts

static func _cone(ci: CanvasItem, c: Vector2) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(3, 3), c + Vector2(-3, 3)]), Color(1.0, 0.45, 0.08))
	ci.draw_line(c + Vector2(-2, 1), c + Vector2(2, 1), Color(1, 1, 1, 0.9), 1.0)

# ── Ruina ─────────────────────────────────────────────────────────────

## Ruina: encima del dibujo del edificio, tizne, un muro roto, cascotes y vigas
## carbonizadas con ascuas. Mucho mas oscura y quebrada que un edificio tocado,
## para que se distinga desde lejos. Determinista por `seed_val`.
static func draw_ruin(ci: CanvasItem, size: Vector2, seed_val: int, n: int = 2) -> void:
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	ci.draw_rect(r, Color(0.06, 0.05, 0.04, 0.72))
	# Manchas de hollin que se salen un poco de la huella
	for k in range(3 + n):
		var p := r.position + Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y)
		ci.draw_circle(p, rng.randf_range(5.0, 9.0) * (0.8 + 0.2 * n), Color(0.02, 0.02, 0.02, 0.55))
	# Muro roto: borde superior dentado
	var wall := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y)])
	var x := r.end.x
	var steps := 5 + n
	for i in steps + 1:
		x = r.end.x - r.size.x * float(i) / float(steps)
		wall.append(Vector2(x, r.position.y + rng.randf_range(3.0, 10.0)))
	ci.draw_colored_polygon(wall, CONCRETE_DARK)
	ci.draw_polyline(wall, OUTLINE, 1.5)
	# Cascotes
	for k in range(6 + 3 * n):
		var c := r.position + Vector2(rng.randf_range(0.1, 0.9) * r.size.x, rng.randf_range(0.2, 0.9) * r.size.y)
		var rad := rng.randf_range(2.0, 4.5)
		var pts := PackedVector2Array()
		for s in 5:
			var a := TAU * s / 5.0 + rng.randf_range(-0.3, 0.3)
			pts.append(c + Vector2(cos(a), sin(a)) * rad * rng.randf_range(0.7, 1.1))
		_poly(ci, pts, CONCRETE if k % 2 == 0 else CONCRETE_DARK.lightened(0.1), OUTLINE, 1.0)
	# Vigas carbonizadas cruzadas, con ascuas en la punta
	for k in range(2 + n):
		var a0 := r.position + Vector2(rng.randf_range(0.1, 0.9) * r.size.x, rng.randf_range(0.3, 0.9) * r.size.y)
		var dir := Vector2.from_angle(rng.randf() * TAU) * minf(r.size.x, r.size.y) * rng.randf_range(0.35, 0.55)
		ci.draw_line(a0, a0 + dir, OUTLINE, 5.0)
		ci.draw_line(a0, a0 + dir, Color(0.16, 0.11, 0.08), 3.0)
		ci.draw_circle(a0 + dir, 1.6, FIRE)
	# Grietas
	for k in range(3):
		var p := r.position + Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y)
		var crack := PackedVector2Array([p])
		for j in range(4):
			p += Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
			crack.append(p)
		ci.draw_polyline(crack, Color(0.02, 0.02, 0.02), 1.5)

# ── Actividad ─────────────────────────────────────────────────────────

## Donde sale el humo (o la luz) de cada edificio, en fracciones de su huella
## SIN girar: las chimeneas y bocas del propio dibujo de arriba.
static func fx_anchors(id: String) -> Array:
	match id:
		"foundry": return [Vector2(0.14, 0.5), Vector2(0.86, 0.5)]
		"refinery": return [Vector2(0.78, 0.2)]
		"gold_mine": return [Vector2(0.5, 0.37)]
		"sawmill": return [Vector2(0.72, 0.5)]
		"barracks": return [Vector2(0.5, 0.35)]
		"tower": return [Vector2(0.33, 0.67)]
		"warehouse": return [Vector2(0.5, 0.85)]
	return [Vector2(0.5, 0.45)]

# ── Yacimientos ───────────────────────────────────────────────────────

## Dibuja el yacimiento `deposit_id` sobre `size` px centrado en el origen.
## Determinista por `seed_val` (la celda): el mismo bosque siempre igual.
static func draw_deposit(ci: CanvasItem, deposit_id: String, size: Vector2, seed_val: int) -> void:
	var r := Rect2(-size * 0.5, size).grow(-1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	match deposit_id:
		"forest": _forest(ci, r, rng)
		"gold_vein": _rocks(ci, r, rng, Color(0.42, 0.37, 0.32), BRASS_LIGHT, true)
		"iron_deposit": _rocks(ci, r, rng, Color(0.36, 0.37, 0.43), Color(0.72, 0.74, 0.82), false)
		"oil_well": _oil(ci, r, rng)
		_:
			ci.draw_rect(r, Color(0.5, 0.5, 0.5, 0.6))

static func _forest(ci: CanvasItem, r: Rect2, rng: RandomNumberGenerator) -> void:
	# Suelo de bosque
	ci.draw_rect(r.grow(-2), Color(0.17, 0.30, 0.12, 0.55))
	var trees: Array = []
	var cells := r.size / 32.0
	var count := int(cells.x * cells.y * 3.2) + 3
	for i in range(count):
		trees.append({
			"p": r.position + Vector2(rng.randf_range(0.14, 0.86) * r.size.x, rng.randf_range(0.14, 0.86) * r.size.y),
			"r": rng.randf_range(7.0, 11.0),
			"tone": rng.randf(),
		})
	# De arriba a abajo, para que las copas de delante tapen a las de detras
	trees.sort_custom(func(a, b): return a["p"].y < b["p"].y)
	for t in trees:
		var p: Vector2 = t["p"]
		var rad: float = t["r"]
		ci.draw_circle(p + Vector2(2, 3), rad, Color(0, 0, 0, 0.25))
	for t in trees:
		var p: Vector2 = t["p"]
		var rad: float = t["r"]
		var base := LEAF_DARK.lerp(Color(0.22, 0.42, 0.14), float(t["tone"]))
		if float(t["tone"]) > 0.88:
			base = Color(0.48, 0.38, 0.12)  # algun arbol de otono
		ci.draw_circle(p, rad, OUTLINE)
		ci.draw_circle(p, rad - 1.2, base)
		ci.draw_circle(p - Vector2(rad, rad) * 0.25, rad * 0.55, base.lightened(0.18))
		ci.draw_circle(p - Vector2(rad, rad) * 0.4, rad * 0.2, base.lightened(0.35))

static func _rocks(ci: CanvasItem, r: Rect2, rng: RandomNumberGenerator, rock: Color, vein: Color, nuggets: bool) -> void:
	ci.draw_rect(r.grow(-3), Color(rock.darkened(0.3), 0.35))
	var cells := r.size / 32.0
	var count := int(cells.x * cells.y * 2.0) + 2
	for i in range(count):
		var c := r.position + Vector2(rng.randf_range(0.2, 0.8) * r.size.x, rng.randf_range(0.2, 0.8) * r.size.y)
		var rad := rng.randf_range(8.0, 13.0)
		var pts := PackedVector2Array()
		var sides := rng.randi_range(5, 7)
		for s in range(sides):
			var a := TAU * s / float(sides) + rng.randf_range(-0.25, 0.25)
			pts.append(c + Vector2(cos(a), sin(a)) * rad * rng.randf_range(0.7, 1.1))
		var shadow := PackedVector2Array()
		for p in pts:
			shadow.append(p + Vector2(2, 3))
		ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.3))
		var tone := rock.lerp(rock.lightened(0.15), rng.randf())
		_poly(ci, pts, tone, OUTLINE, 1.5)
		# Cara iluminada
		ci.draw_colored_polygon(PackedVector2Array([pts[0], pts[1], c]), tone.lightened(0.15))
		# Vetas
		var a0 := rng.randf() * TAU
		ci.draw_line(c + Vector2(cos(a0), sin(a0)) * rad * 0.6, c - Vector2(cos(a0), sin(a0)) * rad * 0.3, vein, 2.0)
		if not nuggets:
			ci.draw_line(c + Vector2(cos(a0 + 1.4), sin(a0 + 1.4)) * rad * 0.5, c, RUST.lightened(0.1), 1.5)
	if nuggets:
		for i in range(count + 2):
			var q := r.position + Vector2(rng.randf_range(0.12, 0.88) * r.size.x, rng.randf_range(0.12, 0.88) * r.size.y)
			ci.draw_circle(q, 2.4, OUTLINE)
			ci.draw_circle(q, 1.8, BRASS_LIGHT)
			ci.draw_circle(q - Vector2(0.5, 0.5), 0.7, Color(1, 0.97, 0.8))

static func _oil(ci: CanvasItem, r: Rect2, rng: RandomNumberGenerator) -> void:
	var c := r.get_center()
	var cells := r.size / 32.0
	var blobs := int(cells.x * cells.y) + 2
	for i in range(blobs):
		var p := c + Vector2(rng.randf_range(-0.28, 0.28) * r.size.x, rng.randf_range(-0.28, 0.28) * r.size.y)
		var rad := rng.randf_range(9.0, 15.0)
		var pts := PackedVector2Array()
		for s in range(14):
			var a := TAU * s / 14.0
			pts.append(p + Vector2(cos(a) * 1.25, sin(a) * 0.9) * rad * rng.randf_range(0.85, 1.05))
		_poly(ci, pts, OIL_BLACK, Color(0.18, 0.12, 0.25), 1.5)
		ci.draw_arc(p + Vector2(-rad * 0.2, -rad * 0.2), rad * 0.45, PI, PI * 1.6, 8, Color(0.45, 0.3, 0.6, 0.8), 2.0)
	# El respiradero con estacas de aviso
	_disc(ci, c, 5.0, GUNMETAL)
	ci.draw_circle(c, 2.5, Color(0.02, 0.02, 0.02))
	for i in range(4):
		var a := TAU * i / 4.0 + PI / 4.0
		var sp := c + Vector2(cos(a), sin(a)) * minf(r.size.x, r.size.y) * 0.36
		ci.draw_circle(sp, 2.6, OUTLINE)
		ci.draw_circle(sp, 1.9, Color(1.0, 0.35, 0.08))
