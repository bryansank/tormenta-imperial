extends Node2D
## La isla vista desde arriba: agua, espuma, arena y hierba.
##
## La silueta sale de las mismas funciones puras que usa la isla 3D
## (IslandGenerator.border_points, rounded_square_radius, make_wobble), asi que
## las dos vistas cumplen la misma promesa: la hierba cubre todas las celdas de
## la rejilla (su tamano y la forma salen de GridManager) y la costa empieza
## fuera de ella. La hierba es una textura de ruido generada
## una vez y pegada al poligono; el resto son primitivas de _draw, que Godot
## guarda y no vuelve a calcular mientras nada cambie.
##
## Maqueta (arte, 2026-10-05, docs/21 §12): la misma paleta calida que la isla
## 3D (tres verdes, zonas secas, calvas de tierra y flores en la textura), el
## canto de tierra asomando por el sur como el de una placa de diorama, y un
## mar turquesa junto a la costa.

const Island := preload("res://scripts/map/IslandGenerator.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")

const WATER := Color(0.12, 0.50, 0.66)
const WATER_SHALLOW := Color(0.18, 0.64, 0.72)
const WATER_DEEP := Color(0.06, 0.28, 0.52)
const FOAM := Color(0.95, 0.98, 1.0, 0.75)
const SAND := Color(0.93, 0.81, 0.57)
const SAND_WET := Color(0.70, 0.60, 0.43)
const GRASS_1 := Color(0.42, 0.66, 0.22)
const GRASS_2 := Color(0.33, 0.57, 0.18)
const GRASS_3 := Color(0.25, 0.46, 0.15)
const GRASS_DRY := Color(0.66, 0.68, 0.30)
const DIRT := Color(0.58, 0.44, 0.28)
const EARTH := Color(0.45, 0.31, 0.19)
const FLOWERS := [Color(0.98, 0.96, 0.9), Color(1.0, 0.82, 0.25), Color(0.95, 0.5, 0.62)]
## Cuanto asoma el canto de tierra por debajo del cesped, en px de mapa.
const CLIFF_PX := 7.0

## Los mismos parametros por defecto que IslandGenerator.
const LAND_MARGIN := 3.0
const CORNER_RADIUS := 8.0
const WOBBLE := 2.0
const SHORE_WIDTH := 4.5

## Resolucion de la textura de hierba: un texel cada 4 px de mapa.
const GRASS_TEXEL_PX := 4.0

var _seed_val := 0.0
var _margin := LAND_MARGIN
var _radius := CORNER_RADIUS
var _wobble: Array = []
var _grass_pts := PackedVector2Array()
var _grass_tex: Texture2D = null
var _grass_bounds := Rect2()
var _tufts: Array = []
var _waves: Array = []

func _ready() -> void:
	z_index = -20
	EventBus.grid_resized.connect(_on_grid_resized)
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
	_grass_pts = polygon_px(0.0)
	_grass_bounds = _bounds(_grass_pts)
	_grass_tex = _make_grass_texture(_grass_bounds)
	_tufts.clear()
	_waves.clear()
	_scatter_details()
	queue_redraw()

## Borde de la isla en pixeles de mapa, crecido `expand` unidades de mundo.
func polygon_px(expand: float) -> PackedVector2Array:
	var half := Island.grid_half_extents()
	var radius := minf(_radius, Island.max_corner_radius(_margin))
	var pts := Island.border_points(half.x, half.y, _margin, radius, _wobble, expand)
	var out := PackedVector2Array()
	for p in pts:
		out.append(p * View2D.PX_PER_UNIT)
	return out

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
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var fine := FastNoiseLite.new()
	fine.seed = noise.seed + 7
	fine.frequency = 0.25
	var patches := FastNoiseLite.new()
	patches.seed = noise.seed + 13
	patches.frequency = 0.06
	for y in range(h):
		for x in range(w):
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var f := fine.get_noise_2d(x, y) * 0.5 + 0.5
			var pt := patches.get_noise_2d(x, y) * 0.5 + 0.5
			var col := GRASS_1.lerp(GRASS_2, smoothstep(0.38, 0.62, n))
			col = col.lerp(GRASS_3, smoothstep(0.62, 0.8, n) * 0.6)
			col = col.lerp(GRASS_DRY, smoothstep(0.66, 0.8, pt) * 0.45)
			col = col.lerp(DIRT, smoothstep(0.8, 0.86, 1.0 - pt) * 0.85)
			col = col.lerp(col.darkened(0.14), f * 0.5)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _scatter_details() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_seed_val * 7919.0)
	var b := _grass_bounds
	for i in range(900):
		var p := b.position + Vector2(rng.randf() * b.size.x, rng.randf() * b.size.y)
		if Geometry2D.is_point_in_polygon(p, _grass_pts):
			_tufts.append({"p": p, "k": rng.randi_range(0, 3), "c": rng.randf()})
	var outer := polygon_px(SHORE_WIDTH + 1.0)
	for i in range(260):
		var p := Vector2(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6)) * b.size * 0.5
		if not Geometry2D.is_point_in_polygon(p, outer):
			_waves.append({"p": p, "w": rng.randf_range(8.0, 18.0)})

func _draw() -> void:
	# Agua, mas oscura lejos de la costa
	var far := _grass_bounds.grow(_grass_bounds.size.x * 1.5)
	draw_rect(far, WATER_DEEP)
	draw_colored_polygon(polygon_px(SHORE_WIDTH + 12.0), WATER.lerp(WATER_DEEP, 0.6))
	draw_colored_polygon(polygon_px(SHORE_WIDTH + 7.0), WATER)
	draw_colored_polygon(polygon_px(SHORE_WIDTH + 3.0), WATER_SHALLOW)
	for wv in _waves:
		var p: Vector2 = wv["p"]
		var w: float = wv["w"]
		draw_arc(p, w, PI * 1.15, PI * 1.85, 6, Color(0.6, 0.75, 0.85, 0.22), 1.5)
	# Espuma, arena mojada, arena
	draw_colored_polygon(polygon_px(SHORE_WIDTH + 1.0), FOAM)
	draw_polyline(_closed(polygon_px(SHORE_WIDTH + 1.6)), Color(FOAM, 0.35), 2.0, true)
	draw_colored_polygon(polygon_px(SHORE_WIDTH), SAND_WET)
	draw_colored_polygon(polygon_px(SHORE_WIDTH - 0.8), SAND)
	# El canto de la maqueta: el cesped desplazado hacia abajo, en tierra.
	var cliff := PackedVector2Array()
	for p in _grass_pts:
		cliff.append(p + Vector2(0, CLIFF_PX))
	draw_colored_polygon(cliff, EARTH)
	# Hierba con su textura de ruido
	var uvs := PackedVector2Array()
	for p in _grass_pts:
		uvs.append((p - _grass_bounds.position) / _grass_bounds.size)
	draw_colored_polygon(_grass_pts, Color.WHITE, uvs, _grass_tex)
	draw_polyline(_closed(_grass_pts), Color(0.24, 0.42, 0.14, 0.9), 2.0, true)
	# Matas de hierba
	for t in _tufts:
		var p: Vector2 = t["p"]
		var col := GRASS_3.darkened(0.2).lerp(GRASS_2.lightened(0.15), float(t["c"]))
		match int(t["k"]):
			0:
				draw_line(p, p + Vector2(-2, -4), col, 1.0)
				draw_line(p, p + Vector2(0, -5), col, 1.0)
				draw_line(p, p + Vector2(2, -4), col, 1.0)
			1:
				draw_circle(p, 1.4, col)
			2:
				draw_circle(p, 1.0, Color(0.85, 0.8, 0.45, 0.8))
			_:
				# Flor: un punto de color con el centro amarillo.
				draw_circle(p, 1.6, FLOWERS[int(float(t["c"]) * 2.99)])
				draw_circle(p, 0.6, Color(1.0, 0.85, 0.2))

func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out
