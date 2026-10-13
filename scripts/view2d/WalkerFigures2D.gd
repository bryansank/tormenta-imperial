extends Node2D
## Las figuras de WorkerWalkers en la vista 2D: todas en un solo _draw, como
## munecos de maqueta vistos desde arriba y un poco desde el sur (como los
## edificios 2D): sombra en el suelo, cuerpo y cabeza encima. Las mismas cuatro
## siluetas que en 3D: obrero (casco amarillo y caja de herramientas),
## ciudadano (sombrero de ala), ciudadana (falda ancha y mono) y nino (mas
## pequeno, con gorra). Entrar y salir por la puerta encoge y desvanece; andar
## da un saltito.
##
## Barato (la 2D es la vista de los equipos flojos): cada pieza es un rectangulo
## con UNA textura pequena (un disco blanco con su contorno, generado una vez)
## tenido con el color de la figura, asi que una figura son 4 o 5 cuadrados que
## el renderizador junta en un solo lote. Los colores de WalkerActor se pasan a
## la casilla mas cercana de la paleta de la maqueta (ToyPalette), con cache.
## Como mucho se pintan `_cap` figuras (el tope del perfil de dispositivo,
## GameConfig.life_figure_cap) y, si `max_fps` > 0, se repinta a ese ritmo.

const View2D := preload("res://scripts/view2d/View2D.gd")
const Actor := preload("res://scripts/map/WalkerActor.gd")
const Toy := preload("res://scripts/buildings/ToyPalette.gd")

const WORKER := 0
const MAN := 1
const WOMAN := 2
const CHILD := 3

## Repintados por segundo como mucho (0 = cada fotograma).
static var max_fps := 0
## Lado de la textura del disco, en px.
const DISC_PX := 32

static var _disc: Texture2D = null
static var _soft: Texture2D = null
## Color crudo (rgba32) -> color de la paleta.
static var _toy := {}

var _actors: Array = []
var _shown := 0
var _cap := 999
var _since := 0.0

func setup(cap: int) -> void:
	z_index = 30
	_cap = maxi(1, cap)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_ensure_textures()

func render(actors: Array) -> void:
	_actors = actors
	var n := 0
	for a: Actor in actors:
		if a.out:
			n += 1
	if max_fps > 0:
		_since += get_process_delta_time()
		if _since < 1.0 / float(max_fps) and n > 0:
			return
		_since = 0.0
	# Sin nadie en la calle no se redibuja (salvo para borrar al ultimo).
	if n > 0 or _shown > 0:
		queue_redraw()
	_shown = mini(n, _cap)

func visible_count() -> int:
	return _shown

## El color de la paleta mas cercano (por casilla de ToyPalette).
static func toy_color(c: Color) -> Color:
	var k := c.to_rgba32()
	if not _toy.has(k):
		var slot := Toy.slot_of(c)
		_toy[k] = Toy.tint(slot, Toy.shade(c) * 0.5) if slot != Toy.Slot.GLOW else Toy.color(Toy.Slot.BRASS)
	return _toy[k]

## Un disco blanco con su contorno oscuro (se tine con el color de la pieza y se
## estira para hacer cuerpos, faldas y alas) y una mancha suave para la sombra.
static func _ensure_textures() -> void:
	if _disc != null:
		return
	var img := Image.create_empty(DISC_PX, DISC_PX, false, Image.FORMAT_RGBA8)
	var soft := Image.create_empty(DISC_PX, DISC_PX, false, Image.FORMAT_RGBA8)
	var c := (DISC_PX - 1) * 0.5
	for y in DISC_PX:
		for x in DISC_PX:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf((1.0 - d) * c, 0.0, 1.0)
			var col := Color(1, 1, 1) if d < 0.74 else Color(0.16, 0.12, 0.1)
			if d >= 0.74 and d < 0.8:
				col = Color(0.16, 0.12, 0.1).lerp(Color(1, 1, 1), (0.8 - d) / 0.06)
			img.set_pixel(x, y, Color(col, a))
			soft.set_pixel(x, y, Color(0, 0, 0, clampf(1.0 - d, 0.0, 1.0) * 0.8))
	img.generate_mipmaps()
	soft.generate_mipmaps()
	_disc = ImageTexture.create_from_image(img)
	_soft = ImageTexture.create_from_image(soft)

## Una pieza: el disco estirado a `size` centrado en `c`, tenido `col`.
func _piece(c: Vector2, size: Vector2, col: Color) -> void:
	draw_texture_rect(_disc, Rect2(c - size * 0.5, size), false, col)

func _draw() -> void:
	if _disc == null:
		_ensure_textures()
	var px: float = View2D.cell_px()
	var base: Vector2 = View2D.cell_origin_px(Vector2i.ZERO)
	var drawn := 0
	for a: Actor in _actors:
		if not a.out:
			continue
		drawn += 1
		if drawn > _cap:
			break
		var s: float = clampf(a.scale, 0.0, 1.0)
		var kind: int = a.kind
		# Un adulto mide algo menos de media celda: se ve desde el zoom de
		# siempre sin tapar la calle.
		var w: float = px * (0.17 if kind == CHILD else 0.22) * s
		var walking: bool = a.state == Actor.WALKING
		var hop: float = absf(sin(a.phase)) * w * 0.35 if walking else 0.0
		var feet: Vector2 = base + a.pos * px
		var alpha: float = s
		var body := toy_color(a.body)
		body.a = alpha
		var acc := toy_color(a.accent)
		acc.a = alpha
		var skin := Color8(240, 200, 160).lerp(Color8(150, 98, 62), a.skin)
		skin.a = alpha
		var d: Vector2 = a.dir
		draw_texture_rect(_soft, Rect2(feet - Vector2(w * 0.75, w * 0.32), Vector2(w * 1.5, w * 0.64)), false, Color(1, 1, 1, 0.5 * alpha))
		var torso := feet - Vector2(0, w * 0.6 + hop)
		var head := torso - Vector2(0, w * 0.72)
		match kind:
			WORKER:
				# Caja de herramientas a un lado, mono y casco amarillo.
				_piece(torso + Vector2(signf(d.x + 0.01) * w * 0.55, w * 0.2), Vector2(w * 0.5, w * 0.42), acc)
				_piece(torso, Vector2(w, w * 1.25), body)
				_piece(head, Vector2(w * 0.72, w * 0.72), skin)
				_piece(head - Vector2(0, w * 0.18), Vector2(w * 0.8, w * 0.5), acc)
			MAN:
				_piece(torso, Vector2(w, w * 1.25), body)
				_piece(head, Vector2(w * 0.7, w * 0.7), skin)
				_piece(head - Vector2(0, w * 0.2), Vector2(w * 1.05, w * 0.42), acc)
				_piece(head - Vector2(0, w * 0.32), Vector2(w * 0.55, w * 0.4), acc.lightened(0.15))
			WOMAN:
				_piece(torso + Vector2(0, w * 0.12), Vector2(w * 1.25, w * 1.2), body)
				_piece(head, Vector2(w * 0.68, w * 0.68), skin)
				_piece(head - Vector2(0, w * 0.3) - d * w * 0.2, Vector2(w * 0.42, w * 0.38), acc)
			_:
				_piece(torso, Vector2(w, w * 1.15), body)
				_piece(head, Vector2(w * 0.74, w * 0.74), skin)
				_piece(head - Vector2(0, w * 0.22) + d * w * 0.12, Vector2(w * 0.68, w * 0.4), acc)
