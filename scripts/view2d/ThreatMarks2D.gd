extends Node2D
## Las marcas de las amenazas de costa en la vista 2D (feat/amenazas-costa).
## Solo vista: lee ThreatManager y se repinta con EventBus.threats_changed, nunca
## por fotograma (sin _process). Un solo _draw para todas (2-3 a la vez).
##
## Dibujo propio, plano y de juguete (vista cenital), en el mismo idioma que las
## de 3D: bote con bandera pirata (en la playa o en el agua), tienda con el
## estandarte morado de la Regencia, y el casco roto del pecio.

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")

const WOOD_DARK := Color(0.33, 0.21, 0.12)
const WOOD := Color(0.52, 0.35, 0.2)
const WOOD_LIGHT := Color(0.66, 0.5, 0.32)
const FLAG_BLACK := Color(0.08, 0.08, 0.09)
const BONE := Color(0.92, 0.9, 0.82)
const FIRE := Color(0.98, 0.55, 0.12)
const CANVAS := Color(0.72, 0.68, 0.6)
const REGENCY := Color(0.42, 0.16, 0.5)
const BRASS := Color(0.78, 0.62, 0.28)
const SAND := Color(0.68, 0.6, 0.42)
const SHADOW := Color(0, 0, 0, 0.25)
const FOAM := Color(1, 1, 1, 0.35)

var _threats: Array = []

func _ready() -> void:
	# Encima de los yacimientos (0) y debajo de los edificios (2).
	z_index = 1
	EventBus.threats_changed.connect(sync)
	EventBus.grid_resized.connect(func(_w, _h): sync())
	sync.call_deferred()

func sync() -> void:
	_threats = ThreatManager.get_threats()
	queue_redraw()

func mark_count() -> int:
	return _threats.size()

func _draw() -> void:
	var u: float = View2D.cell_px() / 32.0
	for threat in _threats:
		var cell: Vector2i = threat.get("cell", Vector2i.ZERO)
		var c: Vector2 = View2D.footprint_center_px(cell, Vector2i.ONE)
		var water: bool = bool(threat.get("water", false))
		match String(threat.get("type", "")):
			Generator.THREAT_VANGUARD:
				_draw_vanguard(c, u)
			Generator.THREAT_WRECK:
				_draw_wreck(c, u)
			_:
				_draw_raiders(c, u, water)

func _draw_raiders(c: Vector2, u: float, water: bool) -> void:
	if water:
		# Estela de espuma alrededor del bote.
		draw_circle(c, 20.0 * u, FOAM)
	else:
		draw_circle(c + Vector2(2, 3) * u, 17.0 * u, SHADOW)
	_hull(c, Vector2(30, 13) * u, WOOD_DARK, WOOD_LIGHT)
	draw_rect(Rect2(c + Vector2(-6, -6) * u, Vector2(2.5, 12) * u), WOOD)
	draw_rect(Rect2(c + Vector2(5, -6) * u, Vector2(2.5, 12) * u), WOOD)
	_pirate_flag(c + Vector2(0, -2) * u, u)
	if not water:
		# Hoguera y cajas del saqueo.
		draw_circle(c + Vector2(-13, 13) * u, 4.5 * u, WOOD_DARK)
		draw_circle(c + Vector2(-13, 13) * u, 2.5 * u, FIRE)
		draw_rect(Rect2(c + Vector2(10, 9) * u, Vector2(7, 7) * u), WOOD_LIGHT)
		draw_rect(Rect2(c + Vector2(10, 9) * u, Vector2(7, 7) * u), WOOD_DARK, false, 1.0)

func _draw_vanguard(c: Vector2, u: float) -> void:
	draw_circle(c + Vector2(2, 3) * u, 17.0 * u, SHADOW)
	# La tienda vista desde arriba: dos faldones y la cumbrera.
	draw_rect(Rect2(c + Vector2(-12, -9) * u, Vector2(24, 9) * u), CANVAS)
	draw_rect(Rect2(c + Vector2(-12, 0) * u, Vector2(24, 9) * u), CANVAS.darkened(0.15))
	draw_line(c + Vector2(-12, 0) * u, c + Vector2(12, 0) * u, WOOD_DARK, 1.5 * u)
	# Sacos terreros delante.
	for i in range(3):
		draw_circle(c + Vector2(-8 + 8 * i, 14) * u, 3.5 * u, SAND)
	# Estandarte morado con remate de laton.
	var pole: Vector2 = c + Vector2(14, -10) * u
	draw_line(pole, pole + Vector2(0, -14) * u, WOOD_DARK, 1.5 * u)
	draw_rect(Rect2(pole + Vector2(1, -14) * u, Vector2(10, 7) * u), REGENCY)
	draw_rect(Rect2(pole + Vector2(1, -11) * u, Vector2(10, 1.5) * u), BRASS)
	draw_circle(pole + Vector2(0, -15) * u, 1.8 * u, BRASS)

func _draw_wreck(c: Vector2, u: float) -> void:
	draw_circle(c + Vector2(2, 3) * u, 18.0 * u, SHADOW)
	# Casco roto y ladeado.
	var xf := Transform2D(-0.35, c)
	draw_set_transform_matrix(xf)
	_hull(Vector2.ZERO, Vector2(32, 14) * u, WOOD_DARK, WOOD_DARK.darkened(0.2))
	# Cuadernas al aire.
	for i in range(4):
		draw_line(Vector2(-9 + 6 * i, -7) * u, Vector2(-9 + 6 * i, 2) * u, WOOD_LIGHT, 1.5 * u)
	# El mastil partido, cruzado.
	draw_line(Vector2(-4, 4) * u, Vector2(14, 14) * u, WOOD, 2.5 * u)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# Un barril suelto.
	draw_circle(c + Vector2(-15, 12) * u, 3.5 * u, WOOD)
	draw_arc(c + Vector2(-15, 12) * u, 3.5 * u, 0.0, TAU, 12, BRASS.darkened(0.3), 1.0)

## Un casco de barca visto desde arriba: elipse con la borda.
func _hull(c: Vector2, size: Vector2, body: Color, rim: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(14):
		var a: float = TAU * float(i) / 14.0
		# Proa en punta a la derecha.
		var x: float = cos(a) * size.x * 0.5
		var y: float = sin(a) * size.y * 0.5 * (1.0 - 0.35 * maxf(0.0, cos(a)))
		pts.append(c + Vector2(x, y))
	draw_colored_polygon(pts, body)
	pts.append(pts[0])
	draw_polyline(pts, rim, 1.5)

## Mastil con la bandera pirata: negra con la calavera.
func _pirate_flag(base: Vector2, u: float) -> void:
	draw_line(base, base + Vector2(0, -18) * u, WOOD, 1.5 * u)
	draw_rect(Rect2(base + Vector2(1, -18) * u, Vector2(11, 8) * u), FLAG_BLACK)
	draw_circle(base + Vector2(6.5, -14.5) * u, 2.0 * u, BONE)
	draw_line(base + Vector2(3.5, -11.5) * u, base + Vector2(9.5, -11.5) * u, BONE, 1.0 * u)
