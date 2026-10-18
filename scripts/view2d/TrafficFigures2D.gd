extends Node2D
## Los camiones de RoadTraffic en la vista 2D: todos en un solo _draw, como
## camioncitos de maqueta vistos desde arriba: sombra, chasis oscuro, cabina
## con su ventanilla, caja y, si va cargado, el bulto del color del recurso.
## Cada camion son seis rectangulos girados con draw_set_transform (sin
## texturas): el renderizador los junta en un lote. Como mucho `_cap`
## camiones; sin ninguno en la carretera no se repinta.

const View2D := preload("res://scripts/view2d/View2D.gd")
const Truck := preload("res://scripts/map/TruckActor.gd")

const OUTLINE := Color(0.13, 0.09, 0.08, 0.95)
const CHASSIS := Color(0.18, 0.15, 0.14)
const GLASS := Color(0.62, 0.78, 0.86)
const SHADOW := Color(0.14, 0.07, 0.03, 0.26)

var _trucks: Array = []
var _shown := 0
var _cap := 999

func setup(cap: int) -> void:
	z_index = 29
	_cap = maxi(1, cap)

func render(trucks: Array) -> void:
	_trucks = trucks
	var n := 0
	for t: Truck in trucks:
		if t.out:
			n += 1
	if n > 0 or _shown > 0:
		queue_redraw()
	_shown = mini(n, _cap)

func visible_count() -> int:
	return _shown

func _draw() -> void:
	var px: float = View2D.cell_px()
	var base: Vector2 = View2D.cell_origin_px(Vector2i.ZERO)
	var drawn := 0
	for t: Truck in _trucks:
		if not t.out:
			continue
		drawn += 1
		if drawn > _cap:
			break
		var s: float = clampf(t.scale, 0.0, 1.0)
		# Largo ~0,7 celda, ancho ~0,34: cabe en su carril.
		var l: float = px * 0.7 * s
		var w: float = px * 0.34 * s
		var c: Vector2 = base + t.pos * px
		# Marco local: +x hacia donde va.
		draw_set_transform(c, t.dir.angle(), Vector2.ONE)
		draw_rect(Rect2(Vector2(-l * 0.5, -w * 0.5) + Vector2(w * 0.12, w * 0.2), Vector2(l, w)), SHADOW)
		draw_rect(Rect2(-l * 0.5 - 1.0, -w * 0.5 - 1.0, l + 2.0, w + 2.0), OUTLINE)
		draw_rect(Rect2(-l * 0.5, -w * 0.5, l, w), CHASSIS)
		var paint := Color(t.paint, s)
		# Cabina delante (el tercio de la punta) con la ventanilla.
		draw_rect(Rect2(l * 0.12, -w * 0.44, l * 0.36, w * 0.88), paint)
		draw_rect(Rect2(l * 0.14, -w * 0.32, l * 0.08, w * 0.64), GLASS)
		# Caja detras; la carga encima si va cargado.
		draw_rect(Rect2(-l * 0.48, -w * 0.46, l * 0.56, w * 0.92), paint.darkened(0.18))
		if t.loaded:
			draw_rect(Rect2(-l * 0.43, -w * 0.33, l * 0.46, w * 0.66), Color(t.cargo, s))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
