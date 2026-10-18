extends Node2D
## La isla vista desde arriba: agua, espuma, arena y hierba.
##
## La silueta sale de las mismas funciones puras que usa la isla 3D
## (IslandGenerator.border_points, rounded_square_radius, make_wobble), asi que
## las dos vistas cumplen la misma promesa: la hierba cubre todas las celdas de
## la rejilla (su tamano y la forma salen de GridManager) y la costa empieza
## fuera de ella. La hierba es una textura de ruido generada una vez y pegada
## al poligono.
##
## Maqueta de juguete (2026-10-12): los colores salen de la paleta comun
## (ToyPalette): cesped GREEN en tres tonos con zonas secas hacia el laton y
## calvas de tierra, arena crema, mar SKY turquesa junto a la costa que se
## hunde hacia el azul, y el canto de la placa de diorama (tierra WOOD con su
## franja oscura) asomando por el sur.
##
## Isla irregular (2026-10-12): con GridManager.is_irregular() la silueta es la
## costa de la mascara de tierra (IslandGenerator.coast_for_grid, la misma que
## la 3D) y los anillos de arena, espuma y agua son ese contorno crecido con
## Geometry2D.offset_polygon (calculados una vez por forma). Las matas y flores
## solo caen en celdas de tierra. Una partida de isla cuadrada (sin "shape" en
## el guardado) sigue con el cuadrado redondeado de siempre.
##
## Rendimiento: el agua, la costa y el cesped son siete poligonos y una
## textura. El detalle menudo (matas, flores, olas) va en trozos (`CHUNKS` x
## `CHUNKS` nodos hijos): Godot descarta los trozos que no se ven, y al
## alejarse mucho (zoom < `DETAIL_MIN_ZOOM`) se ocultan, porque ya no se
## distinguen. Nada se repinta despues de crearse.

const Island := preload("res://scripts/map/IslandGenerator.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")
const Toy := preload("res://scripts/buildings/ToyPalette.gd")

const WATER := Color8(60, 140, 186)          # SKY oscuro
const WATER_SHALLOW := Color8(98, 190, 204)  # SKY claro, hacia el verde
const WATER_DEEP := Color8(40, 92, 140)      # SKY hondo
const FOAM := Color(1.0, 0.98, 0.93, 0.85)   # CREAM casi blanco
const SAND := Color8(240, 216, 164)          # CREAM
const SAND_WET := Color8(206, 172, 120)      # CREAM oscuro
const GRASS_1 := Color8(132, 190, 76)        # GREEN claro
const GRASS_2: Color = Toy.COLORS[Toy.Slot.GREEN]
const GRASS_3 := Color8(84, 146, 50)         # GREEN oscuro
const GRASS_DRY := Color8(196, 184, 84)      # GREEN hacia BRASS
const DIRT := Color8(190, 140, 88)           # WOOD claro
const EARTH: Color = Toy.COLORS[Toy.Slot.WOOD]
const EARTH_DARK := Color8(112, 66, 36)      # WOOD oscuro
const FLOWERS := [Color8(255, 246, 226), Color8(250, 210, 120), Color8(232, 110, 92)]
## Cuanto asoma el canto de tierra por debajo del cesped, en px de mapa.
const CLIFF_PX := 8.0

## Los mismos parametros por defecto que IslandGenerator.
const LAND_MARGIN := 3.0
const CORNER_RADIUS := 8.0
const WOBBLE := 2.0
const SHORE_WIDTH := 4.5

## Resolucion de la textura de hierba: un texel cada 6 px de mapa (con filtro
## lineal no se nota y cuesta la mitad de generar que a 4).
const GRASS_TEXEL_PX := 6.0
## Trozos por lado del detalle menudo.
const CHUNKS := 6
## Por debajo de este zoom de camara el detalle menudo no se pinta.
const DETAIL_MIN_ZOOM := 0.55

var _seed_val := 0.0
var _margin := LAND_MARGIN
var _radius := CORNER_RADIUS
var _wobble: Array = []
var _grass_pts := PackedVector2Array()
var _grass_tex: Texture2D = null
var _grass_bounds := Rect2()
var _details: Node2D = null
## Isla irregular: la costa en px de mapa y los anillos ya crecidos (expand ->
## poligono). Vacia con la isla cuadrada.
var _coast_px := PackedVector2Array()
var _ring_cache := {}
var _check := 0
## Bancos de peces (1.1): sus rectangulos de mundo (Vector4: centro x, z y
## semiejes), las calas que abren en la arena (px de mapa) y los anillos de
## orilla ya recortados por ellas (expand -> Array de poligonos), calculados una
## vez por cambio. Ver set_sand_holes.
var _hole_rects: Array = []
var _coves: Array = []
var _cut_cache := {}

func _ready() -> void:
	z_index = -20
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	EventBus.grid_resized.connect(_on_grid_resized)
	_details = Node2D.new()
	_details.name = "Details"
	add_child(_details)
	_rebuild()

func _on_grid_resized(_w: int, _h: int) -> void:
	_rebuild()

## Forma (de GridManager.island_seed, la misma que la isla 3D) y dibujo. Se
## rehace cuando la rejilla cambia de tamano.
func _rebuild() -> void:
	var amplitude := WOBBLE
	var detail := 1.0
	_margin = LAND_MARGIN
	_radius = CORNER_RADIUS
	if GridManager.island_seed >= 0:
		var shape: Dictionary = Island.shape_for_seed(GridManager.island_seed)
		_seed_val = shape["seed_val"]
		_margin = shape["margin"]
		_radius = shape["radius"]
		amplitude = shape["amplitude"]
		detail = shape["detail"]
	elif _seed_val == 0.0:
		_seed_val = randf() * 100.0
	_wobble = Island.make_wobble(Island.SEGMENTS, _seed_val, amplitude, detail)
	_ring_cache.clear()
	_coast_px = PackedVector2Array()
	for p in Island.coast_for_grid():
		_coast_px.append(p * View2D.PX_PER_UNIT)
	_grass_pts = polygon_px(0.0)
	_grass_bounds = _bounds(_grass_pts)
	_grass_tex = _make_grass_texture(_grass_bounds)
	_rebuild_coves()
	_scatter_details()
	queue_redraw()

# ── Calas sobre los bancos de peces (feat/vista2d-y-prologo) ─────────
# Los bancos van en la primera franja de agua, pegados a la tierra, y la playa
# 2D (SHORE_WIDTH, mas de dos casillas) los tapaba: parecian charcos sobre la
# arena. Como la 3D (island_sand.gdshader, `holes`), la isla abre una cala: la
# espuma y la arena se recortan con un poligono que cubre el banco y sale hacia
# el mar, asi que la orilla se estrecha justo ahi y el banco queda en el agua.
# Se calcula una vez por cambio (bancos o forma); _draw solo pinta lo guardado.

## MapGenerator2D._push_sand_holes: los rectangulos de mundo de los bancos.
func set_sand_holes(rects: Array) -> void:
	if rects == _hole_rects:
		return
	_hole_rects = rects.duplicate()
	_rebuild_coves()
	queue_redraw()

## Las calas en px de mapa (una por banco). Publico para las pruebas.
func coves() -> Array:
	return _coves

func _rebuild_coves() -> void:
	_coves.clear()
	_cut_cache.clear()
	if _grass_pts.is_empty():
		return
	for r in _hole_rects:
		var v: Vector4 = r
		var center := Vector2(v.x, v.y) * View2D.PX_PER_UNIT
		var half := Vector2(v.z, v.w) * View2D.PX_PER_UNIT
		_coves.append(cove_polygon(center, half, _sea_dir(center, half), (SHORE_WIDTH + 2.0) * View2D.PX_PER_UNIT, View2D.cell_px()))

## Hacia donde queda el mar desde un banco: lejos de las casillas de tierra que
## lo rodean (o, si no se sabe, lejos del centro de la isla).
func _sea_dir(center: Vector2, half: Vector2) -> Vector2:
	var cell := View2D.cell_px()
	var dir := Vector2.ZERO
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		var reach: Vector2 = half + Vector2.ONE * cell * 0.5
		var across := Vector2(-d.y, d.x)
		for t in [-0.6, 0.0, 0.6]:
			var p: Vector2 = center + d * reach + across * half * float(t)
			if GridManager.is_land_cell(View2D.px_to_cell(p)):
				dir -= d
	if dir.length() < 0.01:
		dir = center - _grass_bounds.get_center()
	return dir.normalized() if dir.length() > 0.01 else Vector2.DOWN

## La cala de un banco: el ovalo que lo cubre (con un poco de margen) unido a
## ese mismo ovalo llevado `reach` px hacia el mar. Pura, para las pruebas.
static func cove_polygon(center: Vector2, half: Vector2, sea_dir: Vector2, reach: float, cell: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rx := half.x + cell * 0.3
	var ry := half.y + cell * 0.3
	for i in 16:
		var a := TAU * float(i) / 16.0
		var p := center + Vector2(cos(a) * rx, sin(a) * ry)
		pts.append(p)
		pts.append(p + sea_dir * reach)
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	return hull

## Un anillo de orilla (`expand`) con las calas recortadas. Si un recorte no da
## un solo poligono limpio (una cala que no llega al mar), ese anillo se pinta
## entero: mejor charco que agujero.
func _shore_ring(expand: float) -> Array:
	if _cut_cache.has(expand):
		return _cut_cache[expand]
	var polys: Array = [polygon_px(expand)]
	for cove in _coves:
		var next: Array = []
		for p in polys:
			var cut := Geometry2D.clip_polygons(p, cove)
			if cut.size() == 1:
				next.append(cut[0])
			else:
				next.append(p)
		polys = next
	_cut_cache[expand] = polys
	return polys

## Borde de la isla en pixeles de mapa, crecido `expand` unidades de mundo.
func polygon_px(expand: float) -> PackedVector2Array:
	if not _coast_px.is_empty():
		return _coast_ring_px(expand)
	var half := Island.grid_half_extents()
	var radius := minf(_radius, Island.max_corner_radius(_margin))
	var pts := Island.border_points(half.x, half.y, _margin, radius, _wobble, expand)
	var out := PackedVector2Array()
	for p in pts:
		out.append(p * View2D.PX_PER_UNIT)
	return out

## La costa irregular crecida `expand` unidades de mundo (esquinas redondas).
## De lo que devuelve offset_polygon se queda el contorno mas grande (un
## agujero, si lo hubiera, siempre es menor que el contorno de fuera).
func _coast_ring_px(expand: float) -> PackedVector2Array:
	if expand <= 0.0:
		return _coast_px
	if _ring_cache.has(expand):
		return _ring_cache[expand]
	var best := _coast_px
	var best_area := -1.0
	for poly in Geometry2D.offset_polygon(_coast_px, expand * View2D.PX_PER_UNIT, Geometry2D.JOIN_ROUND):
		var r := _bounds(poly)
		var area := r.size.x * r.size.y
		if area > best_area:
			best_area = area
			best = poly
	_ring_cache[expand] = best
	return best

## ¿Cae el punto (px de mapa) sobre tierra? En la isla cuadrada, todo lo que
## esta dentro de la hierba lo es.
func _on_land_px(p: Vector2) -> bool:
	if _coast_px.is_empty():
		return true
	return GridManager.is_land_cell(View2D.px_to_cell(p))

func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r

func _make_grass_texture(bounds: Rect2) -> Texture2D:
	var w := int(ceil(bounds.size.x / GRASS_TEXEL_PX))
	var h := int(ceil(bounds.size.y / GRASS_TEXEL_PX))
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = int(_seed_val * 1000.0)
	noise.frequency = 0.035 * GRASS_TEXEL_PX / 4.0
	noise.fractal_octaves = 3
	var patches := FastNoiseLite.new()
	patches.seed = noise.seed + 13
	patches.frequency = 0.06 * GRASS_TEXEL_PX / 4.0
	# El ruido fino es barato: un hash por texel en vez de un tercer ruido.
	for y in range(h):
		for x in range(w):
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var pt := patches.get_noise_2d(x, y) * 0.5 + 0.5
			var f := fposmod(sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453, 1.0)
			var col := GRASS_1.lerp(GRASS_2, smoothstep(0.38, 0.62, n))
			col = col.lerp(GRASS_3, smoothstep(0.62, 0.8, n) * 0.6)
			col = col.lerp(GRASS_DRY, smoothstep(0.66, 0.8, pt) * 0.4)
			col = col.lerp(DIRT, smoothstep(0.8, 0.86, 1.0 - pt) * 0.8)
			col = col.lerp(col.darkened(0.1), f * 0.4)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Reparte matas, flores y olas en trozos: cada trozo es un nodo con su
## propio _draw, que Godot descarta si no se ve.
func _scatter_details() -> void:
	for c in _details.get_children():
		_details.remove_child(c)
		c.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_seed_val * 7919.0)
	var b := _grass_bounds
	var area := b.grow(b.size.x * 0.25)
	var chunk := area.size / float(CHUNKS)
	var buckets: Array = []
	for i in CHUNKS * CHUNKS:
		buckets.append({"tufts": [], "waves": []})
	var bucket_of := func(p: Vector2) -> int:
		var cx := clampi(int((p.x - area.position.x) / chunk.x), 0, CHUNKS - 1)
		var cy := clampi(int((p.y - area.position.y) / chunk.y), 0, CHUNKS - 1)
		return cy * CHUNKS + cx
	for i in range(900):
		var p := b.position + Vector2(rng.randf() * b.size.x, rng.randf() * b.size.y)
		if Geometry2D.is_point_in_polygon(p, _grass_pts) and _on_land_px(p):
			buckets[bucket_of.call(p)]["tufts"].append([p, rng.randi_range(0, 3), rng.randf()])
	var outer := polygon_px(SHORE_WIDTH + 1.0)
	for i in range(220):
		var p := area.position + Vector2(rng.randf() * area.size.x, rng.randf() * area.size.y)
		if not Geometry2D.is_point_in_polygon(p, outer):
			buckets[bucket_of.call(p)]["waves"].append([p, rng.randf_range(8.0, 18.0)])
	for i in buckets.size():
		var bk: Dictionary = buckets[i]
		if (bk["tufts"] as Array).is_empty() and (bk["waves"] as Array).is_empty():
			continue
		var node := Node2D.new()
		node.name = "Chunk%d" % i
		var tufts: Array = bk["tufts"]
		var waves: Array = bk["waves"]
		node.draw.connect(func() -> void: _draw_chunk(node, tufts, waves))
		_details.add_child(node)
		node.queue_redraw()

static func _draw_chunk(ci: CanvasItem, tufts: Array, waves: Array) -> void:
	var wave_col := Color(1.0, 0.98, 0.92, 0.28)
	for wv in waves:
		var p: Vector2 = wv[0]
		var w: float = wv[1]
		ci.draw_polyline(PackedVector2Array([p + Vector2(-w, 1.5), p + Vector2(-w * 0.4, -1.0), p + Vector2(w * 0.4, -1.0), p + Vector2(w, 1.5)]), wave_col, 1.5)
	for t in tufts:
		var p: Vector2 = t[0]
		var tone: float = t[2]
		var col := GRASS_3.darkened(0.15).lerp(GRASS_1.lightened(0.12), tone)
		match int(t[1]):
			0:
				ci.draw_line(p, p + Vector2(-2, -4), col, 1.0)
				ci.draw_line(p, p + Vector2(0, -5), col, 1.0)
				ci.draw_line(p, p + Vector2(2, -4), col, 1.0)
			1:
				ci.draw_rect(Rect2(p - Vector2(1.3, 1.3), Vector2(2.6, 2.6)), col)
			2:
				ci.draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(GRASS_DRY.lightened(0.2), 0.85))
			_:
				# Flor: un punto de color con el centro amarillo.
				ci.draw_rect(Rect2(p - Vector2(1.6, 1.6), Vector2(3.2, 3.2)), FLOWERS[int(tone * 2.99)])
				ci.draw_rect(Rect2(p - Vector2(0.6, 0.6), Vector2(1.2, 1.2)), Toy.COLORS[Toy.Slot.BRASS])

## Oculta el detalle menudo al alejarse mucho (mirado cada pocos fotogramas).
func _process(_delta: float) -> void:
	_check += 1
	if _check % 15 != 0:
		return
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		var want := cam.zoom.x >= DETAIL_MIN_ZOOM
		if _details.visible != want:
			_details.visible = want

func _draw() -> void:
	# Agua, mas honda lejos de la costa
	var far := _grass_bounds.grow(_grass_bounds.size.x * 1.5)
	draw_rect(far, WATER_DEEP)
	draw_colored_polygon(polygon_px(SHORE_WIDTH + 14.0), WATER_DEEP.lerp(WATER, 0.5))
	draw_colored_polygon(polygon_px(SHORE_WIDTH + 8.0), WATER)
	draw_colored_polygon(polygon_px(SHORE_WIDTH + 3.0), WATER_SHALLOW)
	# Espuma, arena mojada, arena (con las calas de los bancos recortadas)
	for p in _shore_ring(SHORE_WIDTH + 1.0):
		draw_colored_polygon(p, FOAM)
	draw_polyline(_closed(polygon_px(SHORE_WIDTH + 1.7)), Color(FOAM, 0.4), 2.0, true)
	for p in _shore_ring(SHORE_WIDTH):
		draw_colored_polygon(p, SAND_WET)
	for p in _shore_ring(SHORE_WIDTH - 0.8):
		draw_colored_polygon(p, SAND)
	# La orilla nueva de cada cala: una linea de espuma donde corta la arena.
	var sand_outer := polygon_px(SHORE_WIDTH + 1.0)
	for cove in _coves:
		for seg in Geometry2D.intersect_polyline_with_polygon(_closed(cove), sand_outer):
			draw_polyline(seg, Color(FOAM, 0.75), 2.5, true)
	# El canto de la maqueta: el cesped desplazado hacia abajo, en tierra, con
	# su franja oscura al pie.
	var cliff := PackedVector2Array()
	var cliff_dark := PackedVector2Array()
	for p in _grass_pts:
		cliff.append(p + Vector2(0, CLIFF_PX))
		cliff_dark.append(p + Vector2(0, CLIFF_PX + 2.0))
	draw_colored_polygon(cliff_dark, EARTH_DARK)
	draw_colored_polygon(cliff, EARTH)
	# Hierba con su textura de ruido
	var uvs := PackedVector2Array()
	for p in _grass_pts:
		uvs.append((p - _grass_bounds.position) / _grass_bounds.size)
	draw_colored_polygon(_grass_pts, Color.WHITE, uvs, _grass_tex)
	draw_polyline(_closed(_grass_pts), Color(GRASS_3.darkened(0.25), 0.9), 2.0, true)

func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out
