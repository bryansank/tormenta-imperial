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

## La obra: estilo y disposicion compartidos con 3D (docs/03).
const LookRule := preload("res://scripts/buildings/BuildingLook.gd")
const SiteFx := preload("res://scripts/buildings/SiteFx.gd")

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

## La plantilla de la parcela (compartida con la 3D).
const LotPlanRef := preload("res://scripts/buildings/LotPlan.gd")

# ── Entrada ───────────────────────────────────────────────────────────

## Dibuja el edificio `id` con huella `size` (px, sin girar) centrado en el origen.
## `opts`: "road_mask" (int, calzadas), "level" (int), "shadow" (bool, por defecto true),
## "inset" (px por lado: el patio de la parcela, que el edificio deja libre).
static func draw_building(ci: CanvasItem, id: String, size: Vector2, opts: Dictionary = {}) -> void:
	var r := Rect2(-size * 0.5, size).grow(-INSET - float(opts.get("inset", 0.0)))
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

## Aserradero abierto (2026-10-04), como el 3D: la media cubierta de chapa
## atras, las cerchas al aire delante y, a la vista, la mesa con el tronco, el
## tablon cortado y la sierra GRANDE de buje rojo, que es lo que se reconoce.
static func _sawmill(ci: CanvasItem, r: Rect2) -> void:
	_plate(ci, r, WOOD, OUTLINE)
	# Tablas del suelo
	for i in range(1, 8):
		var y := r.position.y + r.size.y * i / 8.0
		ci.draw_line(Vector2(r.position.x + 2, y), Vector2(r.end.x - 2, y), DARK_WOOD, 1.0)
	var m := minf(r.size.x, r.size.y)
	# Media cubierta (atras = arriba), con su sombra sobre el suelo
	var roof := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.4))
	ci.draw_rect(Rect2(roof.position + Vector2(0, roof.size.y), Vector2(roof.size.x, m * 0.06)), Color(0, 0, 0, 0.3))
	ci.draw_rect(roof, Color(0.42, 0.30, 0.22))
	for i in range(1, 9):
		var x := roof.position.x + roof.size.x * i / 9.0
		ci.draw_line(Vector2(x, roof.position.y + 1), Vector2(x, roof.end.y - 1), Color(0.55, 0.40, 0.30), 1.5)
	ci.draw_line(Vector2(roof.position.x, roof.end.y), roof.end, OUTLINE, 2.0)
	ci.draw_rect(roof, OUTLINE, false, 1.5)
	# Chimenea de la maquina de vapor asomando por la chapa
	var chim := roof.position + roof.size * Vector2(0.78, 0.45)
	_disc(ci, chim, m * 0.07, IRON)
	ci.draw_circle(chim, m * 0.035, IMPERIAL_RED)
	# Cerchas al aire sobre la zona de trabajo
	for fx in [0.03, 0.36, 0.64, 0.97]:
		var x: float = r.position.x + r.size.x * fx
		ci.draw_line(Vector2(x, roof.end.y), Vector2(x, r.end.y - 1), DARK_WOOD.darkened(0.2), 2.0)
	ci.draw_line(Vector2(r.position.x, r.end.y - 2), Vector2(r.end.x, r.end.y - 2), DARK_WOOD.darkened(0.2), 3.0)
	# Mesa de la sierra, de lado a lado
	var ty := r.position.y + r.size.y * 0.63
	var table := Rect2(Vector2(r.position.x + r.size.x * 0.08, ty - m * 0.09), Vector2(r.size.x * 0.84, m * 0.18))
	ci.draw_rect(table, GUNMETAL)
	ci.draw_rect(table, OUTLINE, false, 1.0)
	# Tronco entrando por la izquierda y tablon saliendo por la derecha
	var log_r := Rect2(Vector2(table.position.x + 2, ty - m * 0.07), Vector2(r.size.x * 0.32, m * 0.14))
	ci.draw_rect(log_r, Color(0.42, 0.28, 0.15))
	ci.draw_rect(log_r, OUTLINE, false, 1.0)
	ci.draw_circle(Vector2(log_r.position.x + 2, ty), m * 0.06, LIGHT_WOOD)
	var plank := Rect2(Vector2(r.position.x + r.size.x * 0.62, ty - m * 0.05), Vector2(r.size.x * 0.28, m * 0.1))
	ci.draw_rect(plank, LIGHT_WOOD)
	ci.draw_rect(plank, OUTLINE, false, 1.0)
	# Pila de troncos delante a la izquierda, tablones delante a la derecha
	var lr := m * 0.07
	for k in 3:
		var p := Vector2(r.position.x + r.size.x * 0.12 + k * lr * 1.9, r.end.y - lr * 1.7)
		_disc(ci, p, lr, LIGHT_WOOD, OUTLINE, 1.0)
		ci.draw_circle(p, lr * 0.3, DARK_WOOD)
	var stack := Rect2(Vector2(r.position.x + r.size.x * 0.66, r.end.y - m * 0.2), Vector2(r.size.x * 0.26, m * 0.15))
	ci.draw_rect(stack, LIGHT_WOOD)
	for j in range(1, 4):
		var y := stack.position.y + stack.size.y * j / 4.0
		ci.draw_line(Vector2(stack.position.x, y), Vector2(stack.end.x, y), DARK_WOOD, 1.0)
	ci.draw_rect(stack, OUTLINE, false, 1.0)
	# La sierra: el elemento exagerado. Dientes, disco y buje rojo.
	var b := Vector2(r.get_center().x, ty)
	var sr := m * 0.27
	for i in range(18):
		var ang := TAU * i / 18.0
		ci.draw_line(b + Vector2(cos(ang), sin(ang)) * sr * 0.8, b + Vector2(cos(ang + 0.22), sin(ang + 0.22)) * sr * 1.06, STEEL.lightened(0.3), 2.5)
	_disc(ci, b, sr * 0.86, STEEL.lightened(0.15), OUTLINE, 2.0)
	ci.draw_arc(b, sr * 0.55, 0.0, TAU, 18, STEEL.lightened(0.4), 1.0)
	ci.draw_arc(b, sr * 0.86, PI * 1.1, PI * 1.6, 8, Color(1, 1, 1, 0.6), 1.5)
	_disc(ci, b, sr * 0.24, IMPERIAL_RED, OUTLINE, 1.5)
	ci.draw_circle(b, sr * 0.08, BRASS_LIGHT)

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

# ── Obra por fases (estilo por tipo, disposicion por instancia) ───────

## Colores de obra vistos desde arriba (los de la paleta de obra 3D).
const SITE_STONE := Color(0.64, 0.61, 0.55)
const SITE_STONE_DARK := Color(0.47, 0.45, 0.41)
const SITE_SACK := Color(0.78, 0.68, 0.48)
const SITE_SANDBAG := Color(0.62, 0.57, 0.40)
const SITE_SAWDUST := Color(0.86, 0.74, 0.52)
const SITE_GRAVEL := Color(0.50, 0.48, 0.45)
const SITE_SOIL := Color(0.24, 0.17, 0.11)
const SITE_SHEET := Color(0.44, 0.46, 0.48)
const SITE_CRATE := Color(0.47, 0.32, 0.16)
const SITE_LOG := Color(0.42, 0.28, 0.15)
const SITE_DRUM := Color(0.22, 0.30, 0.25)

## Las tres fases de obra vistas desde arriba, como en 3D
## (DieselpunkBuildingFactory.create_construction_phase): 0 valla con
## materiales, 1 solar con cimientos, 2 estructura a medio levantar. El estilo
## de `building_id` (BuildingLook.site_style: materiales, valla, lona, silueta)
## y la semilla `seed_val` (BuildingLook.site_layout: donde va cada cosa) son
## los mismos que en 3D. Se pinta EN LUGAR del edificio; `n` es la clase de
## huella. Lleva debajo la barra de progreso. Lo que se mueve (pluma de la
## grua, banderin, chispas/polvo) no se pinta aqui: son nodos animados por
## shader que pone Building2D en los puntos de site_anchors().
static func draw_construction_phase(ci: CanvasItem, size: Vector2, phase: int, progress: float, n: int = 2,
		building_id: String = "", seed_val: int = 0) -> void:
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	var style := LookRule.site_style(building_id)
	var layout := LookRule.site_layout(seed_val, style, n)
	ci.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), SHADOW)
	ci.draw_rect(r, SITE_DIRT)
	# Terrones: la tierra removida se lee como obra, no como cesped.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for i in range(6 * n):
		var p := r.position + r.size * Vector2(rng.randf(), rng.randf())
		ci.draw_circle(p, 1.4, SITE_DIRT.darkened(0.25))
	var anchors := site_anchors(size, phase, n, style, layout)
	match phase:
		0: _site_fence(ci, r, n, style, layout)
		1: _site_foundation(ci, r, n, style, layout)
		_: _site_frame(ci, r, n, style, layout, anchors)
	# El palo del banderin (la tela la mueve Building2D).
	var flag: Vector2 = anchors["flag"]
	ci.draw_circle(flag, 2.2, OUTLINE)
	ci.draw_circle(flag, 1.4, DARK_WOOD.lightened(0.2))
	ci.draw_rect(r, OUTLINE, false, 1.5)
	var bar := Rect2(Vector2(r.position.x + 3, r.end.y - 7), Vector2(r.size.x - 6, 4))
	ci.draw_rect(bar.grow(1), OUTLINE)
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(progress, 0.0, 1.0), bar.size.y)), HAZARD)

## Donde van las piezas animadas de una obra 2D, en px del marco SIN girar y
## centrado: "flag" (pie del banderin), "fx" (chispas/polvo, o "" si no hay),
## "fx_kind", y "crane" ({mast, jib, angle}, o {} sin grua: solo desde 2x2 y en
## la fase 2). Mismos sitios que en 3D, porque salen de la misma disposicion.
static func site_anchors(size: Vector2, phase: int, n: int, style: Dictionary, layout: Dictionary) -> Dictionary:
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	var half := r.size * 0.5
	var flag := Vector2.ZERO
	match phase:
		0:
			var gn := LookRule.side_normal(int(layout["gate_side"]))
			var glen := r.size.x if gn.x == 0.0 else r.size.y
			var off := half.y if gn.x == 0.0 else half.x
			flag = gn * (off - 2.0) + Vector2(-gn.y, gn.x) * glen * 0.2 * float(layout["flag_post"])
		1:
			flag = (layout["cone_corners"][1] as Vector2) * half * 0.8
		_:
			flag = Vector2.ZERO if String(style["frame"]) == "mast" else -(layout["crane_corner"] as Vector2) * half * 0.8
	var crane := {}
	if phase == 2 and n >= 2:
		var cc: Vector2 = layout["crane_corner"]
		var yaw := atan2(-cc.y, cc.x) + (float(layout["crane_yaw"]) / TAU - 0.5) * 1.2
		crane = {"mast": cc * half * 0.84, "jib": r.size.x * 0.7, "angle": atan2(sin(yaw), -cos(yaw))}
	return {
		"flag": flag,
		"fx": (layout["fx_spot"] as Vector2) * r.size,
		"fx_kind": SiteFx.fx_for(style, phase),
		"crane": crane,
	}

## Recorre los cuatro lados: [normal, inicio, fin] en px.
static func _sides(r: Rect2) -> Array:
	var out: Array = []
	var c := r.get_center()
	for side in 4:
		var nrm := LookRule.side_normal(side)
		var along := Vector2(-nrm.y, nrm.x)
		var length := r.size.x if nrm.x == 0.0 else r.size.y
		var off := r.size.y * 0.5 if nrm.x == 0.0 else r.size.x * 0.5
		var mid := c + nrm * off
		out.append([nrm, mid - along * length * 0.5, mid + along * length * 0.5])
	return out

## Fase 0: valla (tablas, chapa o lona) con la puerta en su lado y las pilas
## del estilo donde diga la semilla, una con lona, mas el desorden.
static func _site_fence(ci: CanvasItem, r: Rect2, n: int, style: Dictionary, layout: Dictionary) -> void:
	var fence := r.grow(-2)
	var kind := String(style["fence"])
	var col := LIGHT_WOOD
	var width := 2.0
	var post_col := DARK_WOOD
	match kind:
		"dark_planks": col = DARK_WOOD.lightened(0.15)
		"sheet":
			col = SITE_SHEET
			width = 3.0
			post_col = IRON
		"canvas":
			col = style["tarp"]
			width = 3.5
	var gate := int(layout["gate_side"])
	var step := 7.0 * float(layout["post_step"]) / 0.9
	var sides := _sides(fence)
	for side in 4:
		var s: Array = sides[side]
		var a: Vector2 = s[1]
		var b: Vector2 = s[2]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var gap := length * 0.16
		var mid := (a + b) * 0.5
		if side == gate:
			ci.draw_line(a, mid - dir * gap, col, width)
			ci.draw_line(mid + dir * gap, b, col, width)
			ci.draw_line(mid - dir * gap, mid + dir * gap, HAZARD, 2.0)
		else:
			ci.draw_line(a, b, col, width)
		var t := 0.0
		while t <= length:
			var p := a + dir * t
			if not (side == gate and absf(t - length * 0.5) < gap):
				ci.draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), post_col)
			t += step
	var m := minf(r.size.x, r.size.y)
	var piles: Array = layout["piles"]
	for k in piles.size():
		var p: Dictionary = piles[k]
		var c: Vector2 = r.get_center() + (p["pos"] as Vector2) * r.size
		var turned := absf(float(p["yaw"])) > PI * 0.25
		var dims := Vector2(m * 0.34, m * 0.2) * float(p["scale"])
		if turned:
			dims = Vector2(dims.y, dims.x)
		_pile_2d(ci, String(p["kind"]), Rect2(c - dims * 0.5, dims), turned)
		if k == int(layout["tarp_pile"]):
			var tarp := Rect2(c - dims * 0.5 + Vector2(dims.x * 0.3, -1), Vector2(dims.x * 0.75, dims.y + 2))
			ci.draw_rect(tarp, style["tarp"])
			ci.draw_line(tarp.position, tarp.end, (style["tarp"] as Color).darkened(0.3), 1.0)
			ci.draw_rect(tarp, OUTLINE, false, 1.0)
	for c in layout["clutter"]:
		var q: Vector2 = r.get_center() + (c["pos"] as Vector2) * r.size
		match String(c["kind"]):
			"barrel": _disc(ci, q, 2.6, SITE_DRUM, OUTLINE, 1.0)
			"crate":
				ci.draw_rect(Rect2(q - Vector2(3, 3), Vector2(6, 6)), SITE_CRATE)
				ci.draw_rect(Rect2(q - Vector2(3, 3), Vector2(6, 6)), OUTLINE, false, 1.0)
			_: _cone(ci, q)

## Una pila de material vista desde arriba en `p` (`turned`: tumbada en vertical).
static func _pile_2d(ci: CanvasItem, kind: String, p: Rect2, turned: bool) -> void:
	var long_axis := Vector2(0, 1) if turned else Vector2(1, 0)
	var across := Vector2(1, 0) if turned else Vector2(0, 1)
	var long_len := p.size.y if turned else p.size.x
	var across_len := p.size.x if turned else p.size.y
	var c := p.get_center()
	match kind:
		"planks":
			ci.draw_rect(p, LIGHT_WOOD)
			for j in range(1, 4):
				var o := c + across * (across_len * (j / 4.0 - 0.5))
				ci.draw_line(o - long_axis * long_len * 0.5, o + long_axis * long_len * 0.5, DARK_WOOD, 1.0)
		"beams", "pipes":
			var count := 3 if kind == "beams" else 4
			var bar_col := STEEL if kind == "beams" else COPPER
			for j in count:
				var o := c + across * (across_len * ((j + 0.5) / count - 0.5))
				var a := o - long_axis * long_len * 0.5
				var b := o + long_axis * long_len * 0.5
				ci.draw_line(a, b, OUTLINE, across_len / count + 1.0)
				ci.draw_line(a, b, bar_col, across_len / count - 1.0)
				if kind == "pipes":
					ci.draw_circle(b, across_len / count * 0.35, bar_col.darkened(0.45))
			return
		"logs":
			for j in 3:
				var o := c + across * (across_len * ((j + 0.5) / 3.0 - 0.5))
				var a := o - long_axis * long_len * 0.5
				var b := o + long_axis * long_len * 0.5
				ci.draw_line(a, b, OUTLINE, across_len / 3.0 + 1.0)
				ci.draw_line(a, b, SITE_LOG, across_len / 3.0 - 1.0)
				ci.draw_circle(b, across_len / 6.0, LIGHT_WOOD)
			return
		"bricks":
			ci.draw_rect(p, TILE_RED)
			ci.draw_line(Vector2(c.x, p.position.y), Vector2(c.x, p.end.y), TILE_RED_DARK, 1.0)
			ci.draw_line(Vector2(p.position.x, c.y), Vector2(p.end.x, c.y), TILE_RED_DARK, 1.0)
		"sawdust", "gravel", "soil":
			var fill: Color = {"sawdust": SITE_SAWDUST, "gravel": SITE_GRAVEL}.get(kind, SITE_SOIL)
			var rad := minf(p.size.x, p.size.y) * 0.75
			_disc(ci, c, rad, fill, OUTLINE, 1.0)
			ci.draw_circle(c - Vector2(rad, rad) * 0.25, rad * 0.45, fill.lightened(0.15))
			if kind == "gravel":
				for j in 5:
					ci.draw_circle(c + Vector2(cos(j * 1.3), sin(j * 1.3)) * rad * 0.55, 0.9, fill.darkened(0.4))
			return
		"rivets":
			var box := Rect2(p.position, Vector2(p.size.x * 0.45, p.size.y))
			ci.draw_rect(box, SITE_CRATE)
			ci.draw_rect(box, OUTLINE, false, 1.0)
			for j in 3:
				_disc(ci, Vector2(p.position.x + p.size.x * (0.6 + 0.14 * j), c.y + (j - 1) * 2.0), 2.2, RUST, OUTLINE, 1.0)
			return
		"drums":
			var rad := minf(p.size.x, p.size.y) * 0.32
			for o in [Vector2(-0.28, -0.1), Vector2(0.05, 0.12), Vector2(0.32, -0.12)]:
				_disc(ci, c + o * p.size, rad, SITE_DRUM, OUTLINE, 1.0)
				ci.draw_circle(c + o * p.size, rad * 0.4, SITE_DRUM.lightened(0.25))
			return
		"sacks", "sandbags":
			var fill := SITE_SACK if kind == "sacks" else SITE_SANDBAG
			var per := 3 if kind == "sacks" else 4
			for row in 2:
				for j in per:
					var o := c + long_axis * long_len * ((j + 0.5) / per - 0.5) + across * across_len * (row - 0.5) * 0.5
					_disc(ci, o, minf(long_len / per, across_len * 0.5) * 0.55, fill, OUTLINE, 1.0)
			return
		"stone":
			ci.draw_rect(Rect2(p.position, p.size * Vector2(0.55, 1.0)), SITE_STONE)
			ci.draw_rect(Rect2(p.position + p.size * Vector2(0.5, 0.15), p.size * Vector2(0.5, 0.75)), SITE_STONE_DARK)
			ci.draw_rect(Rect2(p.position, p.size * Vector2(0.55, 1.0)), OUTLINE, false, 1.0)
		"crates":
			for j in 2:
				var box := Rect2(p.position + Vector2(p.size.x * 0.5 * j, 0), Vector2(p.size.x * 0.5 - 1, p.size.y))
				ci.draw_rect(box, SITE_CRATE)
				ci.draw_line(box.position, box.end, DARK_WOOD, 1.0)
				ci.draw_line(Vector2(box.end.x, box.position.y), Vector2(box.position.x, box.end.y), DARK_WOOD, 1.0)
				ci.draw_rect(box, OUTLINE, false, 1.0)
			return
		_:
			ci.draw_rect(p, CONCRETE_DARK)
	ci.draw_rect(p, OUTLINE, false, 1.0)

## Fase 1: losa (de piedra en los de piedra) con zapatas, esperas de ferralla o
## estacas, conos y lo que sobro de la primera pila.
static func _site_foundation(ci: CanvasItem, r: Rect2, n: int, style: Dictionary, layout: Dictionary) -> void:
	var stone := String(style["frame_mat"]) == "stone"
	var slab := r.grow(-r.size.x * 0.08)
	_plate(ci, slab, SITE_STONE if stone else CONCRETE.lightened(0.2), OUTLINE, 1.5)
	var wood := String(style["frame_mat"]) == "wood"
	_foundation_hint_2d(ci, slab, style, layout)
	for p in _frame_points_2d(slab.grow(-slab.size.x * 0.08), n, String(style["frame"])):
		ci.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), SITE_STONE_DARK if stone else CONCRETE_DARK)
		if wood:
			ci.draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), DARK_WOOD)
		else:
			ci.draw_circle(p + Vector2(-1.5, -1.5), 1.3, RUST)
			ci.draw_circle(p + Vector2(1.5, 1.5), 1.3, RUST)
	var half := r.size * 0.5
	var piles: Array = layout["piles"]
	if not piles.is_empty():
		var c: Vector2 = r.get_center() + (layout["leftover_corner"] as Vector2) * half * 0.72
		var m := minf(r.size.x, r.size.y)
		var dims := Vector2(m * 0.24, m * 0.14)
		_pile_2d(ci, String(piles[0]["kind"]), Rect2(c - dims * 0.5, dims), false)
	for corner in layout["cone_corners"]:
		_cone(ci, r.get_center() + (corner as Vector2) * (half - Vector2(5, 7)))

## Lo que ya asoma en los cimientos de cada silueta (como en 3D): base de la
## chimenea, anillos, zapata de la torre, escalon, bancales, durmientes.
static func _foundation_hint_2d(ci: CanvasItem, slab: Rect2, style: Dictionary, layout: Dictionary) -> void:
	var c := slab.get_center()
	var cc: Vector2 = layout["crane_corner"]
	var m := minf(slab.size.x, slab.size.y)
	match String(style["frame"]):
		"chimney":
			_disc(ci, c - cc * slab.size * 0.26, m * 0.19, TILE_RED, OUTLINE, 1.0)
		"tanks":
			for side in [-1.0, 1.0]:
				_disc(ci, c + Vector2(side * slab.size.x * 0.24, 0), m * 0.2, CONCRETE_DARK, OUTLINE, 1.0)
		"dome", "basin":
			ci.draw_arc(c, m * 0.4, 0.0, TAU, 28, OUTLINE, 5.0)
			ci.draw_arc(c, m * 0.4, 0.0, TAU, 28, SITE_STONE_DARK if style["frame_mat"] == "stone" else CONCRETE_DARK, 3.5)
		"tower":
			var pad := Rect2(c - slab.size * 0.3, slab.size * 0.6)
			ci.draw_rect(pad, CONCRETE_DARK)
			ci.draw_rect(pad, OUTLINE, false, 1.0)
		"plinth":
			var step := Rect2(c - slab.size * 0.4, slab.size * 0.8)
			ci.draw_rect(step, SITE_STONE.darkened(0.08))
			ci.draw_rect(step, OUTLINE, false, 1.0)
		"low":
			for zs in [-1.0, 1.0]:
				var bed := Rect2(Vector2(c.x - slab.size.x * 0.3, c.y + zs * slab.size.y * 0.18 - 4), Vector2(slab.size.x * 0.6, 8))
				ci.draw_rect(bed, SITE_SOIL)
				ci.draw_rect(bed, OUTLINE, false, 1.0)
		"headframe":
			for zs in [-1.0, 1.0]:
				for xs in [-1.0, 1.0]:
					var p := c + Vector2(xs * slab.size.x * 0.35, zs * slab.size.y * 0.18)
					ci.draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), CONCRETE_DARK)
					ci.draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), OUTLINE, false, 1.0)
		"gable", "hall":
			var sill := slab.grow(-slab.size.x * 0.08)
			ci.draw_rect(sill, OUTLINE, false, 4.0)
			ci.draw_rect(sill, DARK_WOOD.lightened(0.2) if style["frame_mat"] == "wood" else GUNMETAL, false, 2.5)
		"mast":
			_disc(ci, c, 5.0, CONCRETE_DARK, OUTLINE, 1.0)

## Fase 2: losa, la silueta del edificio, andamio en su lado y el mastil de la
## grua (la pluma la anima Building2D).
static func _site_frame(ci: CanvasItem, r: Rect2, n: int, style: Dictionary, layout: Dictionary, anchors: Dictionary) -> void:
	var slab := r.grow(-r.size.x * 0.08)
	var stone := String(style["frame_mat"]) == "stone"
	_plate(ci, slab, SITE_STONE if stone else CONCRETE.lightened(0.2), OUTLINE, 1.5)
	var mat_col: Color = {"wood": WOOD, "stone": SITE_STONE_DARK}.get(String(style["frame_mat"]), GUNMETAL)
	var inner := slab.grow(-slab.size.x * 0.08)
	var c := slab.get_center()
	var cc: Vector2 = layout["crane_corner"]
	match String(style["frame"]):
		"chimney":
			_site_box(ci, slab, inner, n, mat_col)
			var ch := c - cc * slab.size * 0.26
			var rad := minf(slab.size.x, slab.size.y) * 0.17
			_disc(ci, ch, rad, TILE_RED, OUTLINE, 1.5)
			ci.draw_arc(ch, rad * 0.8, 0.0, TAU, 16, GUNMETAL, 1.5)
			_disc(ci, ch, rad * 0.5, OIL_BLACK, OUTLINE, 1.0)
		"gable", "hall":
			for p in _site_points(inner, n):
				_pillar_2d(ci, p, mat_col)
			var count := n + 2
			for i in count:
				var x := lerpf(inner.position.x, inner.end.x, float(i) / float(count - 1))
				ci.draw_line(Vector2(x, slab.position.y + 2), Vector2(x, slab.end.y - 2), OUTLINE, 3.0)
				ci.draw_line(Vector2(x, slab.position.y + 2), Vector2(x, slab.end.y - 2), mat_col.lightened(0.15), 1.6)
			if String(style["frame"]) == "gable":
				# Medio faldon ya entablado: el tejado a dos aguas que viene.
				var plank := Rect2(Vector2(inner.position.x, slab.position.y + 2), Vector2(inner.size.x * 0.55, c.y - slab.position.y - 2))
				ci.draw_rect(plank, LIGHT_WOOD)
				for j in range(1, 5):
					var y := plank.position.y + plank.size.y * j / 5.0
					ci.draw_line(Vector2(plank.position.x, y), Vector2(plank.end.x, y), DARK_WOOD, 1.0)
				ci.draw_rect(plank, OUTLINE, false, 1.0)
			else:
				# Cerchas en aspa de nave.
				for i in count - 1:
					var x0 := lerpf(inner.position.x, inner.end.x, float(i) / float(count - 1))
					var x1 := lerpf(inner.position.x, inner.end.x, float(i + 1) / float(count - 1))
					ci.draw_line(Vector2(x0, inner.position.y), Vector2(x1, inner.end.y), mat_col, 1.2)
					ci.draw_line(Vector2(x1, inner.position.y), Vector2(x0, inner.end.y), mat_col, 1.2)
			ci.draw_line(Vector2(slab.position.x + 2, c.y), Vector2(slab.end.x - 2, c.y), OUTLINE, 4.0)
			ci.draw_line(Vector2(slab.position.x + 2, c.y), Vector2(slab.end.x - 2, c.y), mat_col.lightened(0.3), 2.4)
		"tower":
			var outer := Rect2(c - slab.size * 0.3, slab.size * 0.6)
			var top := Rect2(c - slab.size * 0.18, slab.size * 0.36)
			ci.draw_rect(top, mat_col.darkened(0.1))
			for k in 4:
				var a: Vector2 = c + (LookRule.CORNERS[k] as Vector2) * slab.size * 0.3
				var b: Vector2 = c + (LookRule.CORNERS[k] as Vector2) * slab.size * 0.18
				var a2: Vector2 = c + (LookRule.CORNERS[(k + 1) % 4] as Vector2) * slab.size * 0.18
				ci.draw_line(a, b, mat_col, 3.0)
				ci.draw_line(a, a2, mat_col.lightened(0.2), 1.2)
			ci.draw_rect(outer, mat_col, false, 2.0)
			ci.draw_rect(top, OUTLINE, false, 1.0)
		"tanks":
			var rad := minf(slab.size.x, slab.size.y) * 0.2
			for side in [-1.0, 1.0]:
				var tc := c + Vector2(side * slab.size.x * 0.24, 0)
				if side > 0.0:
					_disc(ci, tc, rad, SITE_SHEET, OUTLINE, 1.0)
				ci.draw_arc(tc, rad, 0.0, TAU, 20, OUTLINE, 3.0)
				ci.draw_arc(tc, rad, 0.0, TAU, 20, mat_col.lightened(0.2), 1.8)
				for k in 6:
					ci.draw_circle(tc + Vector2.from_angle(TAU * k / 6.0) * rad, 1.6, mat_col)
			ci.draw_line(c + Vector2(-slab.size.x * 0.24, slab.size.y * 0.12), c + Vector2(slab.size.x * 0.24, slab.size.y * 0.12), COPPER, 2.5)
		"dome":
			var rad := minf(slab.size.x, slab.size.y) * 0.4
			for p in _frame_points_2d(inner, n, "dome"):
				_pillar_2d(ci, p, mat_col)
			ci.draw_arc(c, rad, 0.0, TAU, 28, OUTLINE, 3.5)
			ci.draw_arc(c, rad, 0.0, TAU, 28, mat_col.lightened(0.2), 2.0)
			for k in 6:
				var tip := c + Vector2.from_angle(TAU * k / 6.0) * rad
				ci.draw_line(tip, c, mat_col.lightened(0.1), 1.6)
			_disc(ci, c, 3.0, mat_col, OUTLINE, 1.0)
		"plinth":
			for i in 3:
				var s := 0.8 - 0.18 * i
				var step := Rect2(c - slab.size * s * 0.5, slab.size * s)
				ci.draw_rect(step, SITE_STONE if i % 2 == 0 else SITE_STONE_DARK)
				ci.draw_rect(step, OUTLINE, false, 1.0)
			var fig := Rect2(c - Vector2(5, 5), Vector2(10, 10))
			ci.draw_rect(fig, style["tarp"])
			ci.draw_rect(fig, OUTLINE, false, 1.0)
			for k in 4:
				ci.draw_circle(c + (LookRule.CORNERS[k] as Vector2) * slab.size * 0.3, 1.8, DARK_WOOD)
		"basin":
			var count := 10 + 2 * n
			for k in count:
				if k % 5 == 4:
					continue
				var p := c + Vector2.from_angle(TAU * k / count) * slab.size * 0.38
				ci.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), SITE_STONE)
				ci.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), OUTLINE, false, 1.0)
			for k in 3:
				ci.draw_line(c + Vector2.from_angle(TAU * k / 3.0 + 0.3) * slab.size * 0.32, c, DARK_WOOD, 1.6)
			_disc(ci, c, 2.5, COPPER, OUTLINE, 1.0)
		"headframe":
			for p in _site_points(inner, 1):
				_pillar_2d(ci, p, mat_col)
			for zs in [-1.0, 1.0]:
				for xs in [-1.0, 1.0]:
					ci.draw_line(c + Vector2(xs * slab.size.x * 0.35, zs * slab.size.y * 0.18), c + Vector2(0, zs * slab.size.y * 0.1), mat_col, 2.4)
			ci.draw_line(c + Vector2(-5, 0), c + Vector2(5, 0), OUTLINE, 4.0)
			ci.draw_arc(c, 4.0, 0.0, TAU, 12, STEEL, 1.5)
		"low":
			for zs in [-1.0, 1.0]:
				var bed := Rect2(Vector2(c.x - slab.size.x * 0.3, c.y + zs * slab.size.y * 0.18 - 4), Vector2(slab.size.x * 0.6, 8))
				ci.draw_rect(bed, SITE_SOIL)
				ci.draw_rect(bed, OUTLINE, false, 1.0)
			for i in 4:
				var x := lerpf(c.x - slab.size.x * 0.32, c.x + slab.size.x * 0.32, float(i) / 3.0)
				ci.draw_line(Vector2(x, c.y - slab.size.y * 0.32), Vector2(x, c.y + slab.size.y * 0.32), mat_col, 1.4)
			for k in 4:
				_pillar_2d(ci, c + (LookRule.CORNERS[k] as Vector2) * slab.size * 0.32, mat_col)
		"mast":
			_site_box(ci, slab, inner, n, mat_col)
			_disc(ci, c, 3.0, STEEL, OUTLINE, 1.0)
		_:
			_site_box(ci, slab, inner, n, mat_col)
	# Andamio: tablones en el lado de la semilla.
	var side: Array = _sides(slab.grow(-4))[int(layout["scaffold_side"])]
	var a: Vector2 = side[1]
	var b: Vector2 = side[2]
	ci.draw_line(a, b, OUTLINE, 6.0)
	ci.draw_line(a, b, LIGHT_WOOD, 4.0)
	var crane: Dictionary = anchors["crane"]
	if not crane.is_empty():
		var mast: Vector2 = crane["mast"]
		var col: Color = style["crane"]
		ci.draw_rect(Rect2(mast - Vector2(4, 4), Vector2(8, 8)), col)
		ci.draw_rect(Rect2(mast - Vector2(4, 4), Vector2(8, 8)), OUTLINE, false, 1.0)

## La estructura de caja: medio forjado arriba, vigas de borde y pilares.
static func _site_box(ci: CanvasItem, slab: Rect2, inner: Rect2, n: int, mat_col: Color) -> void:
	var deck := Rect2(slab.position, Vector2(slab.size.x, slab.size.y * 0.48))
	ci.draw_rect(deck, CONCRETE)
	ci.draw_rect(deck, OUTLINE, false, 1.0)
	ci.draw_rect(slab.grow(-2), mat_col, false, 3.0)
	for p in _site_points(inner, n):
		_pillar_2d(ci, p, mat_col)

static func _pillar_2d(ci: CanvasItem, p: Vector2, col: Color) -> void:
	ci.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), col.lightened(0.15))
	ci.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), OUTLINE, false, 1.0)

## Puntos de pilar: esquinas para la clase 1, rejilla 3x3 para la 2, 4x4 la 3.
static func _site_points(r: Rect2, n: int) -> Array:
	var per := clampi(n, 1, 3) + 1
	var pts: Array = []
	for i in per:
		for j in per:
			pts.append(r.position + r.size * Vector2(float(i) / float(per - 1), float(j) / float(per - 1)))
	return pts

## Como en 3D: rejilla, o anillo para las siluetas redondas.
static func _frame_points_2d(r: Rect2, n: int, shape: String) -> Array:
	if shape in ["dome", "basin", "tanks"]:
		var pts: Array = []
		var count := 4 + 2 * n
		for k in count:
			pts.append(r.get_center() + Vector2.from_angle(TAU * k / count) * r.size * 0.48)
		return pts
	return _site_points(r, n)

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
		"sawmill": return [Vector2(0.5, 0.63)]
		"barracks": return [Vector2(0.5, 0.35)]
		"tower": return [Vector2(0.33, 0.67)]
		"warehouse": return [Vector2(0.5, 0.85)]
	return [Vector2(0.5, 0.45)]

# ── Parcela y atrezo (docs/03, "Parcela y atrezo") ────────────────────

const LOT_CHAR := Color(0.07, 0.06, 0.05)
const LOT_BORDER := Color(0.10, 0.085, 0.07, 0.95)

## El suelo de la parcela, su borde oscuro y el remate de los lados sin
## calzada, para un plan de LotPlan. `size`: la huella SIN girar (px). Va
## debajo del edificio.
static func draw_lot_ground(ci: CanvasItem, plan: Dictionary, size: Vector2) -> void:
	if plan.is_empty():
		return
	var lot := Rect2(-size * 0.5, size)
	var cell := size.x / maxf(1.0, (plan["lot"] as Vector2).x)
	var state := String(plan["state"])
	var kind := String(plan["ground"])
	var base := _ground_color(kind)
	if state == "ruin":
		base = base.lerp(LOT_CHAR, 0.45)
	ci.draw_rect(lot, base)
	_ground_pattern(ci, lot, kind, cell, base)
	for run in plan["trim_runs"]:
		_trim_2d(ci, String(plan["trim"]), run, cell, plan["accent"])
	ci.draw_rect(lot.grow(-0.75), LOT_BORDER, false, 1.5)

## Sombra de contacto bajo el edificio: una mancha oscura que lo ancla al suelo
## y un filo mas oscuro donde lo toca (el borde que lo separa del fondo).
static func draw_lot_shadow(ci: CanvasItem, model_px: Rect2) -> void:
	ci.draw_rect(model_px.grow(3.0), Color(0, 0, 0, 0.16))
	ci.draw_rect(model_px.grow(1.5), Color(0, 0, 0, 0.22))
	ci.draw_rect(model_px.grow(1.0), Color(0, 0, 0, 0.55), false, 2.0)

## El atrezo del patio. Va encima del edificio (no se tocan: el plan lo deja
## en el patio) y, en ruina, encima de los escombros.
static func draw_lot_props(ci: CanvasItem, plan: Dictionary, size: Vector2) -> void:
	if plan.is_empty():
		return
	var cell := size.x / maxf(1.0, (plan["lot"] as Vector2).x)
	var accent: Color = plan["accent"]
	for p in plan["props"]:
		var c: Vector2 = (p["pos"] as Vector2) * cell
		var rad := float(p["radius"]) * cell
		draw_lot_prop(ci, String(p["kind"]), c, rad, float(p["rot"]), accent,
			bool(p.get("toppled", false)), bool(p.get("snapped", false)), bool(p.get("burnt", false)))
	draw_lot_signature(ci, plan, size)

static func _ground_color(kind: String) -> Color:
	match kind:
		"dirt": return Color(0.47, 0.37, 0.25)
		"plate": return Color(0.40, 0.41, 0.43)
		"grass": return Color(0.31, 0.50, 0.21)
	return Color(0.60, 0.58, 0.54)

static func _ground_pattern(ci: CanvasItem, lot: Rect2, kind: String, cell: float, base: Color) -> void:
	match kind:
		"slabs", "plate":
			var step := cell * 0.5
			var line := base.darkened(0.35) if kind == "slabs" else base.darkened(0.45)
			var x := lot.position.x + step
			while x < lot.end.x - 1.0:
				ci.draw_line(Vector2(x, lot.position.y), Vector2(x, lot.end.y), line, 1.0)
				x += step
			var y := lot.position.y + step
			while y < lot.end.y - 1.0:
				ci.draw_line(Vector2(lot.position.x, y), Vector2(lot.end.x, y), line, 1.0)
				y += step
			if kind == "plate":
				var yy := lot.position.y + step * 0.15
				while yy < lot.end.y:
					var xx := lot.position.x + step * 0.15
					while xx < lot.end.x:
						ci.draw_circle(Vector2(xx, yy), 0.9, BRASS.darkened(0.1))
						xx += step * 0.7
					yy += step * 0.7
		"dirt":
			for i in int(lot.size.x * lot.size.y / 90.0):
				var p := lot.position + lot.size * Vector2(fposmod(i * 0.381, 1.0), fposmod(i * 0.617 + 0.21, 1.0))
				ci.draw_circle(p, 1.1, base.darkened(0.22) if i % 3 else base.lightened(0.18))
		"grass":
			for i in int(lot.size.x * lot.size.y / 70.0):
				var p := lot.position + lot.size * Vector2(fposmod(i * 0.437, 1.0), fposmod(i * 0.719 + 0.07, 1.0))
				ci.draw_line(p, p + Vector2(0.6, -2.2), base.lightened(0.18) if i % 2 else base.darkened(0.2), 1.0)

static func _trim_2d(ci: CanvasItem, trim: String, run: Dictionary, cell: float, accent: Color) -> void:
	var a: Vector2 = (run["a"] as Vector2) * cell
	var b: Vector2 = (run["b"] as Vector2) * cell
	var broken := int(run.get("broken", 0))
	var segs := maxi(2, int(a.distance_to(b) / (cell * 0.25)))
	var w := cell * 0.06
	for i in segs:
		if broken != 0 and (broken >> (i % 30)) & 1 == 1 and (broken >> ((i + 7) % 30)) & 1 == 1:
			continue
		var p0 := a.lerp(b, float(i) / float(segs))
		var p1 := a.lerp(b, float(i + 1) / float(segs))
		var dim := 0.55 if broken != 0 else 0.0
		match trim:
			"fence":
				ci.draw_line(p0, p1, LIGHT_WOOD.lerp(LOT_CHAR, dim), maxf(1.5, w))
				ci.draw_rect(Rect2(p0 - Vector2(1.5, 1.5), Vector2(3, 3)), DARK_WOOD)
			"rail":
				ci.draw_line(p0, p1, IRON.lightened(0.15).lerp(LOT_CHAR, dim), maxf(1.5, w * 0.8))
				ci.draw_circle(p0, 1.6, IRON)
			"sandbags":
				var mid := (p0 + p1) * 0.5
				var sack := Color(0.66, 0.58, 0.40).lerp(LOT_CHAR, dim)
				ci.draw_circle(mid, maxf(2.0, w * 1.1), sack.darkened(0.25))
				ci.draw_circle(mid - Vector2(0.4, 0.4), maxf(1.6, w * 0.9), sack)
			"pipes":
				ci.draw_line(p0, p1, COPPER.darkened(0.25).lerp(LOT_CHAR, dim), maxf(2.5, w * 1.2))
				ci.draw_line(p0, p1, COPPER.lerp(LOT_CHAR, dim), maxf(1.2, w * 0.6))
				if i % 3 == 1:
					_disc(ci, (p0 + p1) * 0.5, maxf(2.0, w), accent, OUTLINE, 1.0)
			_:
				ci.draw_line(p0, p1, (Color(0.74, 0.71, 0.66) if i % 2 == 0 else Color(0.66, 0.63, 0.58)).lerp(LOT_CHAR, dim), maxf(2.0, w * 1.4))

## Una pieza de atrezo vista desde arriba, en `c` con radio `rad` (px). Volcada:
## tumbada a lo largo de su lado; partida: un munon; quemada: hacia el carbon.
static func draw_lot_prop(ci: CanvasItem, kind: String, c: Vector2, rad: float, rot: float, accent: Color, toppled := false, snapped := false, burnt := false) -> void:
	var dim := 0.6 if burnt else 0.0
	var col := _prop_color(kind, accent).lerp(LOT_CHAR, dim)
	ci.draw_circle(c + Vector2(1.2, 1.6), rad, Color(0, 0, 0, 0.25))
	if snapped:
		_disc(ci, c, rad * 0.45, col, OUTLINE, 1.0)
		ci.draw_line(c, c + Vector2.from_angle(rot) * rad * 1.4, col.darkened(0.2), 2.0)
		return
	if toppled:
		var d := Vector2.from_angle(rot)
		ci.draw_line(c - d * rad * 1.1, c + d * rad * 1.1, OUTLINE, rad * 1.2)
		ci.draw_line(c - d * rad * 1.0, c + d * rad * 1.0, col, rad * 0.9)
		return
	match kind:
		"barrel", "drums":
			var n := 2 if kind == "drums" else 1
			for k in n:
				var o := Vector2.from_angle(rot) * rad * (0.5 if n == 2 else 0.0) * (1.0 if k == 0 else -1.0)
				var cc := (accent if (kind == "drums" and k == 0) else col).lerp(LOT_CHAR, dim)
				_disc(ci, c + o, rad * (0.55 if n == 2 else 0.8), cc, OUTLINE, 1.0)
				ci.draw_arc(c + o, rad * (0.35 if n == 2 else 0.5), 0.0, TAU, 10, cc.darkened(0.3), 1.0)
		"crate", "ammo", "goods", "pallet":
			_rot_rect(ci, c, Vector2(rad * 1.5, rad * 1.5), rot, col)
			if kind == "ammo":
				_rot_rect(ci, c, Vector2(rad * 1.5, rad * 0.35), rot, accent.lerp(LOT_CHAR, dim), false)
			elif kind == "goods":
				for k in 3:
					ci.draw_circle(c + Vector2.from_angle(rot) * rad * (k - 1) * 0.45, rad * 0.28, [Color(0.85, 0.18, 0.12), Color(0.95, 0.75, 0.15), Color(0.4, 0.65, 0.2)][k].lerp(LOT_CHAR, dim))
			elif kind == "pallet":
				_rot_rect(ci, c, Vector2(rad * 1.2, rad * 1.2), rot, Color(0.66, 0.63, 0.58).lerp(LOT_CHAR, dim))
			else:
				var d := Vector2.from_angle(rot) * rad * 0.7
				var e := Vector2.from_angle(rot + PI * 0.5) * rad * 0.7
				ci.draw_line(c - d - e, c + d + e, DARK_WOOD, 1.0)
				ci.draw_line(c - d + e, c + d - e, DARK_WOOD, 1.0)
		"logs", "planks":
			var d := Vector2.from_angle(rot)
			var e := Vector2.from_angle(rot + PI * 0.5)
			for k in 3:
				var o := e * rad * (k - 1) * 0.6
				ci.draw_line(c + o - d * rad, c + o + d * rad, OUTLINE, rad * 0.62)
				ci.draw_line(c + o - d * rad * 0.95, c + o + d * rad * 0.95, col if k % 2 == 0 else col.lightened(0.12), rad * 0.45)
				if kind == "logs":
					ci.draw_circle(c + o + d * rad, rad * 0.24, LIGHT_WOOD.lerp(LOT_CHAR, dim))
		"sacks", "ore", "coal":
			for k in 3:
				var o := Vector2.from_angle(rot + TAU * k / 3.0) * rad * 0.4
				_disc(ci, c + o, rad * 0.5, col if k != 1 else col.lightened(0.1), OUTLINE, 1.0)
			if kind == "ore":
				for k in 3:
					ci.draw_circle(c + Vector2.from_angle(rot + 1.0 + TAU * k / 3.0) * rad * 0.35, rad * 0.18, BRASS_LIGHT.lerp(LOT_CHAR, dim))
		"cart":
			_rot_rect(ci, c, Vector2(rad * 1.8, rad * 0.9), rot, Color(0.25, 0.22, 0.22), false)
			_rot_rect(ci, c, Vector2(rad * 1.2, rad * 1.0), rot, RUST.lerp(LOT_CHAR, dim))
			ci.draw_circle(c, rad * 0.3, BRASS_LIGHT.lerp(LOT_CHAR, dim))
		"ingots":
			var d := Vector2.from_angle(rot + PI * 0.5)
			for k in 3:
				_rot_rect(ci, c + d * rad * (k - 1) * 0.45, Vector2(rad * 1.5, rad * 0.35), rot, (Color(1.0, 0.55, 0.12) if k == 1 else STEEL).lerp(LOT_CHAR, dim))
		"lamp":
			if not burnt:
				ci.draw_circle(c, rad * 1.5, Color(1.0, 0.82, 0.45, 0.22))
			_disc(ci, c, rad * 0.45, IRON, OUTLINE, 1.0)
			ci.draw_circle(c, rad * 0.25, Color(1.0, 0.85, 0.5).lerp(LOT_CHAR, dim))
		"bench":
			_rot_rect(ci, c, Vector2(rad * 2.0, rad * 0.7), rot, col)
		"planter":
			_rot_rect(ci, c, Vector2(rad * 1.3, rad * 1.3), rot, Color(0.62, 0.32, 0.20).lerp(LOT_CHAR, dim))
			_disc(ci, c, rad * 0.55, LEAF.lerp(LOT_CHAR, dim), LEAF_DARK, 1.0)
			ci.draw_circle(c + Vector2(rad * 0.2, -rad * 0.15), rad * 0.15, Color(0.95, 0.35, 0.3).lerp(LOT_CHAR, dim))
		"gas":
			var d := Vector2.from_angle(rot)
			for k in 3:
				_disc(ci, c + d * rad * (k - 1) * 0.6, rad * 0.3, (Color(0.25, 0.5, 0.42) if k != 1 else Color(0.3, 0.45, 0.7)).lerp(LOT_CHAR, dim), OUTLINE, 1.0)
		"dummy":
			_disc(ci, c, rad * 0.45, Color(0.72, 0.62, 0.42).lerp(LOT_CHAR, dim), OUTLINE, 1.0)
			var d := Vector2.from_angle(rot) * rad * 0.85
			ci.draw_line(c - d, c + d, DARK_WOOD, 2.0)
		"target":
			_disc(ci, c, rad * 0.9, Color(0.92, 0.9, 0.84).lerp(LOT_CHAR, dim), OUTLINE, 1.0)
			ci.draw_circle(c, rad * 0.62, Color(0.8, 0.15, 0.1).lerp(LOT_CHAR, dim))
			ci.draw_circle(c, rad * 0.35, Color(0.92, 0.9, 0.84).lerp(LOT_CHAR, dim))
			ci.draw_circle(c, rad * 0.15, accent.lerp(LOT_CHAR, dim))
		"flag":
			ci.draw_circle(c, rad * 0.3, IRON)
			var tip := c + Vector2.from_angle(rot) * rad * 1.3
			ci.draw_colored_polygon(PackedVector2Array([c, tip + Vector2(0, -rad * 0.3), tip + Vector2(0, rad * 0.5)]), accent.lerp(LOT_CHAR, dim))
		"clothesline":
			var d := Vector2.from_angle(rot) * rad
			ci.draw_line(c - d, c + d, Color(0.85, 0.82, 0.75), 1.0)
			for k in 3:
				_rot_rect(ci, c + d * (k - 1) * 0.6, Vector2(rad * 0.4, rad * 0.25), rot, [Color(0.92, 0.9, 0.84), accent, Color(0.35, 0.45, 0.7)][k].lerp(LOT_CHAR, dim))
		"valve":
			_disc(ci, c, rad * 0.55, accent.lerp(LOT_CHAR, dim), OUTLINE, 1.0)
			ci.draw_line(c - Vector2(rad * 0.5, 0), c + Vector2(rad * 0.5, 0), COPPER, 1.5)
			ci.draw_line(c - Vector2(0, rad * 0.5), c + Vector2(0, rad * 0.5), COPPER, 1.5)
		"stake":
			ci.draw_circle(c, rad * 0.22, LIGHT_WOOD)
			ci.draw_colored_polygon(PackedVector2Array([c, c + Vector2(rad * 0.7, -rad * 0.2), c + Vector2(0, -rad * 0.45)]), Color(1.0, 0.45, 0.08))
		_:
			_disc(ci, c, rad * 0.7, col, OUTLINE, 1.0)

## El elemento exagerado visto desde arriba (la chimenea, la grua, la antena,
## el emblema...), en su esquina del patio: el mismo que en 3D (BuildingLot).
static func draw_lot_signature(ci: CanvasItem, plan: Dictionary, size: Vector2) -> void:
	var sig: Dictionary = plan.get("signature", {})
	if sig.is_empty():
		return
	var corners: Array = sig.get("corners", [])
	var cell := size.x / maxf(1.0, (plan["lot"] as Vector2).x)
	if bool(sig.get("on_roof", false)):
		var mr0: Rect2 = plan["model"]
		_emblem_2d(ci, mr0.get_center() * cell, minf(mr0.size.x, mr0.size.y) * cell * 0.26, plan["accent"], bool(sig.get("ruined", false)))
		return
	if corners.is_empty():
		return
	var yard := float(plan["yard"])
	var fp: Vector2i = plan["footprint"]
	var sgn: Vector2 = corners[0]
	var c: Vector2 = LotPlanRef.corner_center(fp, yard, sgn) * cell
	var r := yard * cell * 0.45
	var mr: Rect2 = plan["model"]
	var model := Rect2(mr.position * cell, mr.size * cell)
	var ruined := bool(sig.get("ruined", false))
	var dim := 0.65 if ruined else 0.0
	var accent: Color = plan["accent"]
	match String(sig["kind"]):
		"chimney":
			ci.draw_circle(c + Vector2(3, 4), r * 1.05, Color(0, 0, 0, 0.3))
			_disc(ci, c, r, Color(0.56, 0.26, 0.17).lerp(LOT_CHAR, dim), OUTLINE, 1.5)
			if not ruined:
				ci.draw_arc(c, r * 0.78, 0.0, TAU, 14, accent, 2.0)
				ci.draw_circle(c, r * 0.55, Color(0.08, 0.06, 0.05))
				ci.draw_circle(c, r * 0.3, FIRE)
				_smoke(ci, c, 1.2)
		"crane":
			var yellow := Color(0.95, 0.72, 0.12).lerp(LOT_CHAR, dim)
			var tip := Vector2(model.get_center().x, model.end.y + yard * cell * 0.5)
			if not ruined:
				ci.draw_line(c + Vector2(4, 5), tip + Vector2(4, 5), Color(0, 0, 0, 0.3), 4.0)
				ci.draw_line(c, tip, OUTLINE, 4.5)
				ci.draw_line(c, tip, yellow, 2.5)
				var back := c + (c - tip).normalized() * cell * 0.25
				ci.draw_line(c, back, OUTLINE, 4.0)
				ci.draw_line(c, back, yellow, 2.2)
				ci.draw_rect(Rect2(back - Vector2(3, 3), Vector2(6, 6)), CONCRETE_DARK)
				_rot_rect(ci, tip, Vector2(r * 1.3, r * 1.3), 0.0, WOOD)
			ci.draw_rect(Rect2(c - Vector2(r * 0.6, r * 0.6), Vector2(r * 1.2, r * 1.2)), yellow)
			ci.draw_rect(Rect2(c - Vector2(r * 0.6, r * 0.6), Vector2(r * 1.2, r * 1.2)), OUTLINE, false, 1.5)
		"antenna":
			var pts := PackedVector2Array()
			for i in 3:
				pts.append(c + Vector2.from_angle(TAU * i / 3.0 + 0.3) * r)
			ci.draw_colored_polygon(pts, Color(0, 0, 0, 0.2))
			for i in 3:
				ci.draw_line(pts[i], pts[(i + 1) % 3], COPPER.lerp(LOT_CHAR, dim), 1.5)
				ci.draw_line(pts[i], c, IRON, 1.5)
			if not ruined:
				ci.draw_circle(c, r * 0.9, Color(0.45, 0.85, 1.0, 0.25))
				ci.draw_circle(c, r * 0.35, Color(0.45, 0.85, 1.0))
		"flag":
			ci.draw_rect(Rect2(c - Vector2(r * 0.5, r * 0.5), Vector2(r, r)), Color(0.64, 0.61, 0.56).lerp(LOT_CHAR, dim))
			ci.draw_circle(c, 2.0, IRON)
			if not ruined:
				var d := -1.0 if sgn.x > 0 else 1.0
				var f := PackedVector2Array([c, c + Vector2(d * cell * 0.62, -r * 0.4), c + Vector2(d * cell * 0.62, r * 0.9), c + Vector2(0, r * 0.6)])
				_poly(ci, f, accent, OUTLINE, 1.0)
				ci.draw_line(c + Vector2(0, r * 0.15), c + Vector2(d * cell * 0.62, r * 0.25), OUTLINE, 2.0)
		"manifold":
			var to := Vector2(model.end.x if sgn.x > 0 else model.position.x, c.y - r * 0.5)
			if not ruined:
				ci.draw_line(c - Vector2(0, r * 0.5), to, COPPER.darkened(0.25), 4.0)
				ci.draw_line(c - Vector2(0, r * 0.5), to, COPPER, 2.0)
			for p in [Vector2(-0.55, -0.5), Vector2(0.55, -0.5), Vector2(0, 0.45)]:
				_disc(ci, c + p * r, 2.5, COPPER.lerp(LOT_CHAR, dim), OUTLINE, 1.0)
			if not ruined:
				var w := c + Vector2(0, r * 0.45)
				ci.draw_arc(w, r * 0.62, 0.0, TAU, 14, OUTLINE, 3.5)
				ci.draw_arc(w, r * 0.62, 0.0, TAU, 14, Color(0.82, 0.12, 0.08), 2.2)
				for i in 3:
					ci.draw_line(w, w + Vector2.from_angle(TAU * i / 3.0) * r * 0.6, Color(0.82, 0.12, 0.08), 1.5)
		"ore_heap":
			_disc(ci, c, r * 1.1, Color(0.47, 0.39, 0.28).lerp(LOT_CHAR, dim), OUTLINE, 1.5)
			for p in [Vector2(-0.35, 0.2), Vector2(0.3, -0.25), Vector2(0.05, 0.05), Vector2(0.45, 0.35), Vector2(-0.3, -0.4)]:
				ci.draw_circle(c + p * r * 1.2, r * 0.22, BRASS_LIGHT.lerp(LOT_CHAR, dim))
			if not ruined:
				ci.draw_circle(c + Vector2(0.05, 0.05) * r, r * 0.12, Color(1, 0.97, 0.8))
				ci.draw_line(c + Vector2(r * 0.6, 0), c + Vector2(r * 0.1, -r * 0.6), WOOD, 2.0)
		"cannon":
			for i in 9:
				var p := c + Vector2.from_angle(TAU * i / 9.0) * r * 1.05
				_disc(ci, p, r * 0.3, Color(0.62, 0.55, 0.38).lerp(LOT_CHAR, dim), OUTLINE, 1.0)
			_disc(ci, c, r * 0.45, OLIVE.lerp(LOT_CHAR, dim), OUTLINE, 1.0)
			if not ruined:
				var out := sgn.normalized()
				ci.draw_line(c - out * r * 0.4, c + out * r * 1.3, OUTLINE, 5.0)
				ci.draw_line(c - out * r * 0.4, c + out * r * 1.3, GUNMETAL.lightened(0.1), 3.0)

## Emblema de la Regencia visto desde arriba: rueda dentada de laton, disco
## rojo y el rayo de la Tormenta.
static func _emblem_2d(ci: CanvasItem, e: Vector2, re: float, accent: Color, ruined: bool) -> void:
	if ruined:
		_disc(ci, e, re * 0.5, Color(0.2, 0.18, 0.16), OUTLINE, 1.0)
		return
	ci.draw_circle(e + Vector2(3, 4), re * 1.1, Color(0, 0, 0, 0.3))
	for i in 14:
		var a := TAU * i / 14.0
		ci.draw_line(e + Vector2.from_angle(a) * re * 0.8, e + Vector2.from_angle(a) * re * 1.14, BRASS, 3.5)
	_disc(ci, e, re * 0.92, BRASS, OUTLINE, 1.5)
	_disc(ci, e, re * 0.64, Color(0.75, 0.12, 0.09), OUTLINE, 1.0)
	ci.draw_polyline(PackedVector2Array([e + Vector2(-0.12, -0.45) * re, e + Vector2(0.12, -0.05) * re, e + Vector2(-0.1, 0.02) * re, e + Vector2(0.14, 0.45) * re]), accent.lightened(0.15), 3.0)

static func _prop_color(kind: String, accent: Color) -> Color:
	match kind:
		"barrel": return RUST
		"drums": return Color(0.2, 0.22, 0.25)
		"crate", "bench": return WOOD
		"goods", "pallet": return LIGHT_WOOD
		"ammo": return OLIVE
		"logs": return Color(0.42, 0.28, 0.15)
		"planks": return LIGHT_WOOD
		"sacks": return Color(0.72, 0.62, 0.42)
		"ore": return Color(0.48, 0.40, 0.30)
		"coal": return Color(0.14, 0.13, 0.13)
		"cart": return RUST
		"lamp": return IRON
	return accent

## Rectangulo girado `rot` centrado en `c`, con contorno.
static func _rot_rect(ci: CanvasItem, c: Vector2, size: Vector2, rot: float, fill: Color, outline := true) -> void:
	var d := Vector2.from_angle(rot) * size.x * 0.5
	var e := Vector2.from_angle(rot + PI * 0.5) * size.y * 0.5
	var pts := PackedVector2Array([c - d - e, c + d - e, c + d + e, c - d + e])
	if outline:
		_poly(ci, pts, fill, OUTLINE, 1.0)
	else:
		ci.draw_colored_polygon(pts, fill)

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
