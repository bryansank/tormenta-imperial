extends Node2D
## Las figuras de WorkerWalkers en la vista 2D: todas en un solo _draw, vistas
## desde arriba. Las mismas cuatro siluetas que en 3D: obrero (casco amarillo y
## caja de herramientas), ciudadano (sombrero de ala), ciudadana (falda ancha y
## mono) y nino (mas pequeno, con gorra). Entrar y salir por la puerta encoge y
## desvanece; andar da un saltito.

const View2D := preload("res://scripts/view2d/View2D.gd")
const Actor := preload("res://scripts/map/WalkerActor.gd")

const WORKER := 0
const MAN := 1
const WOMAN := 2
const CHILD := 3

var _actors: Array = []
var _shown := 0

func setup(_cap: int) -> void:
	z_index = 30

func render(actors: Array) -> void:
	_actors = actors
	var n := 0
	for a: Actor in actors:
		if a.out:
			n += 1
	# Sin nadie en la calle no se redibuja (salvo para borrar al ultimo).
	if n > 0 or _shown > 0:
		queue_redraw()
	_shown = n

func visible_count() -> int:
	return _shown

func _draw() -> void:
	var px: float = View2D.cell_px()
	var base: Vector2 = View2D.cell_origin_px(Vector2i.ZERO)
	var shadow := Color(0, 0, 0, 0.3)
	for a: Actor in _actors:
		if not a.out:
			continue
		var s: float = clampf(a.scale, 0.0, 1.0)
		var kind: int = a.kind
		# Un quinto de celda el adulto: se ve desde el zoom de siempre sin tapar la calle.
		var r: float = px * (0.14 if kind == CHILD else 0.2) * s
		var walking: bool = a.state == Actor.WALKING
		var hop: float = absf(sin(a.phase)) * r * 0.35 if walking else 0.0
		var p: Vector2 = base + a.pos * px
		var top := p - Vector2(0, hop)
		var alpha: float = s
		var body: Color = a.body
		body.a = alpha
		var acc: Color = a.accent
		acc.a = alpha
		var skin := Color(0.90, 0.74, 0.60).lerp(Color(0.46, 0.31, 0.22), a.skin)
		skin.a = alpha
		var d: Vector2 = a.dir
		draw_circle(p + Vector2(0, r * 0.35), r * 1.15, Color(shadow.r, shadow.g, shadow.b, shadow.a * alpha))
		match kind:
			WORKER:
				draw_rect(Rect2(top - d * r * 0.9 - Vector2(r, r) * 0.38, Vector2(r, r) * 0.76), acc)
				draw_circle(top + Vector2(0, r * 0.2), r, body)
				draw_circle(top + Vector2(0, -r * 0.4), r * 0.62, acc)
			MAN:
				draw_circle(top + Vector2(0, r * 0.2), r, body)
				draw_circle(top + Vector2(0, -r * 0.4), r * 0.78, acc)
				draw_circle(top + Vector2(0, -r * 0.4), r * 0.42, acc.lightened(0.18))
			WOMAN:
				draw_circle(top + Vector2(0, r * 0.25), r * 1.12, body)
				draw_circle(top + Vector2(0, -r * 0.4), r * 0.55, skin)
				draw_circle(top + Vector2(0, -r * 0.4) - d * r * 0.45, r * 0.32, acc)
			_:
				draw_circle(top + Vector2(0, r * 0.2), r, body)
				draw_circle(top + Vector2(0, -r * 0.4), r * 0.6, skin)
				draw_circle(top + Vector2(0, -r * 0.4) + d * r * 0.2, r * 0.45, acc)
