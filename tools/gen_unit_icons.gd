extends SceneTree
## Herramienta re-ejecutable: dibuja las siluetas de las unidades que el tablero
## de combate usa en vez de la inicial del nombre
## (assets/textures/ui/units/*.png, leidas por UITheme.unit_icon).
##
## Son mascaras de un solo color — RGB blanco y un alfa suavizado — para que un
## unico PNG sirva a los dos bandos: quien la pinta la tine con el color de su
## ejercito. Todo se traza a 4x sobre una mascara y luego se promedia por bloques
## de 4x4, que es lo que mantiene el borde limpio cuando la franja de iniciativa
## la encoge a 24 px.
##
## Mismo camino que tools/gen_ui_textures.gd: aqui no hay artista, hay codigo.
## Ejecutar: godot --headless --path . --script res://tools/gen_unit_icons.gd

const OUT_DIR := "res://assets/textures/ui/units/"
const SIZE := 64          ## Lado del PNG final, en pixeles.
const SS := 4             ## Supermuestreo: se traza a SIZE*SS y se promedia.

var _canvas: int = SIZE * SS
var _mask: PackedByteArray

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	_draw_infantry()
	_save("infantry.png")
	_draw_artillery()
	_save("artillery.png")
	_draw_vehicle()
	_save("vehicle.png")

	print("GEN_DONE")

# ── Siluetas ─────────────────────────────────────────────────────────
# Todas las coordenadas van en el espacio logico de 64x64 del icono final, no en
# el lienzo grande. Cada icono busca una forma general distinta para que los tres
# se separen a 24 px sin mirar el detalle: la infanteria es alta y estrecha con
# una cupula arriba, la artilleria es un circulo con una diagonal, y el vehiculo
# es una masa ancha y baja.

## Fusilero con casco de ala, fusil al hombro y bayoneta calada.
func _draw_infantry() -> void:
	_clear()
	# Casco: cupula mas ala saliente a los dos lados.
	_disc(30.0, 20.0, 11.5)
	_capsule(Vector2(17.5, 21.5), Vector2(42.5, 21.5), 2.6)
	# Cuello.
	_box(26.0, 22.0, 34.0, 31.0)
	# Hombros y tronco: un trapecio que se abre hacia abajo.
	_poly([
		Vector2(13.0, 58.0), Vector2(15.0, 40.0), Vector2(23.0, 31.0),
		Vector2(37.0, 31.0), Vector2(45.0, 40.0), Vector2(47.0, 58.0),
	])
	# Fusil terciado: nace dentro del tronco y asoma por encima del casco.
	_capsule(Vector2(24.0, 50.0), Vector2(50.0, 12.0), 2.4)
	_capsule(Vector2(50.0, 12.0), Vector2(56.0, 4.0), 1.3)

## Pieza de campana: rueda radiada, tubo en alto y cola con reja.
func _draw_artillery() -> void:
	_clear()
	# Rueda: llanta, radios y buje.
	_ring(23.0, 42.0, 16.0, 10.0)
	for i in range(6):
		var angle: float = TAU * float(i) / 6.0
		var rim := Vector2(23.0, 42.0) + Vector2(cos(angle), sin(angle)) * 14.0
		_capsule(Vector2(23.0, 42.0), rim, 1.8)
	_disc(23.0, 42.0, 5.0)
	# Cierre y cuna.
	_disc(25.0, 34.0, 8.0)
	# Tubo hacia arriba y a la derecha, con freno de boca.
	_capsule(Vector2(25.0, 34.0), Vector2(54.0, 15.0), 4.2)
	_capsule(Vector2(49.0, 18.0), Vector2(56.0, 14.0), 5.5)
	# Cola y reja, que es lo que le da la diagonal larga hacia abajo.
	_capsule(Vector2(20.0, 44.0), Vector2(6.0, 57.0), 3.0)
	_disc(6.0, 57.0, 4.5)

## Blindado sobre orugas con torreta, canon y chimenea de escape.
func _draw_vehicle() -> void:
	_clear()
	# Orugas: dos ruedas motrices gordas y el tramo recto entre ellas.
	_disc(12.0, 47.5, 8.5)
	_disc(52.0, 47.5, 8.5)
	_box(12.0, 39.0, 52.0, 56.0)
	# Casco con glacis inclinado hacia la derecha.
	_poly([
		Vector2(7.0, 41.0), Vector2(12.0, 27.0), Vector2(44.0, 27.0),
		Vector2(57.0, 35.0), Vector2(59.0, 41.0),
	])
	# Torreta y canon.
	_capsule(Vector2(28.0, 21.0), Vector2(38.0, 21.0), 6.5)
	_capsule(Vector2(44.0, 20.0), Vector2(60.0, 20.0), 2.6)
	# Chimenea: el detalle dieselpunk que lo separa de un tanque cualquiera.
	_capsule(Vector2(17.0, 26.0), Vector2(17.0, 12.0), 2.6)
	_disc(17.0, 10.5, 4.0)

# ── Primitivas de trazado ────────────────────────────────────────────

func _clear() -> void:
	_mask = PackedByteArray()
	_mask.resize(_canvas * _canvas)
	_mask.fill(0)

func _plot(x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= _canvas or y >= _canvas:
		return
	_mask[y * _canvas + x] = 1

## Devuelve el centro del pixel (x, y) del lienzo grande en coordenadas logicas.
func _at(x: int, y: int) -> Vector2:
	return Vector2((float(x) + 0.5) / float(SS), (float(y) + 0.5) / float(SS))

## Rango de pixeles del lienzo grande que cubre un rectangulo logico.
func _span(lo: float, hi: float) -> Vector2i:
	return Vector2i(int(floor(lo * SS)) - 1, int(ceil(hi * SS)) + 1)

func _disc(cx: float, cy: float, r: float) -> void:
	var xs := _span(cx - r, cx + r)
	var ys := _span(cy - r, cy + r)
	for y in range(ys.x, ys.y):
		for x in range(xs.x, xs.y):
			if _at(x, y).distance_squared_to(Vector2(cx, cy)) <= r * r:
				_plot(x, y)

func _ring(cx: float, cy: float, r_out: float, r_in: float) -> void:
	var xs := _span(cx - r_out, cx + r_out)
	var ys := _span(cy - r_out, cy + r_out)
	for y in range(ys.x, ys.y):
		for x in range(xs.x, xs.y):
			var d := _at(x, y).distance_squared_to(Vector2(cx, cy))
			if d <= r_out * r_out and d >= r_in * r_in:
				_plot(x, y)

func _box(x0: float, y0: float, x1: float, y1: float) -> void:
	var xs := _span(x0, x1)
	var ys := _span(y0, y1)
	for y in range(ys.x, ys.y):
		for x in range(xs.x, xs.y):
			var p := _at(x, y)
			if p.x >= x0 and p.x <= x1 and p.y >= y0 and p.y <= y1:
				_plot(x, y)

## Segmento grueso con extremos redondeados: la brocha de casi todo el arte.
func _capsule(a: Vector2, b: Vector2, r: float) -> void:
	var xs := _span(minf(a.x, b.x) - r, maxf(a.x, b.x) + r)
	var ys := _span(minf(a.y, b.y) - r, maxf(a.y, b.y) + r)
	var ab := b - a
	var len_sq: float = maxf(ab.length_squared(), 0.0001)
	for y in range(ys.x, ys.y):
		for x in range(xs.x, xs.y):
			var p := _at(x, y)
			var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
			if p.distance_squared_to(a + ab * t) <= r * r:
				_plot(x, y)

## Poligono relleno por regla par-impar. Los puntos van en orden, sin repetir el
## primero al final.
func _poly(points: Array) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var xs := _span(lo.x, hi.x)
	var ys := _span(lo.y, hi.y)
	for y in range(ys.x, ys.y):
		for x in range(xs.x, xs.y):
			if _inside(_at(x, y), points):
				_plot(x, y)

func _inside(p: Vector2, points: Array) -> bool:
	var hit := false
	var n: int = points.size()
	var j: int = n - 1
	for i in range(n):
		var a: Vector2 = points[i]
		var b: Vector2 = points[j]
		if (a.y > p.y) != (b.y > p.y):
			var cut: float = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
			if p.x < cut:
				hit = not hit
		j = i
	return hit

# ── Salida ───────────────────────────────────────────────────────────

## Promedia bloques de SSxSS para sacar el alfa. El RGB queda blanco tambien
## donde el alfa es cero: si no, el filtrado bilineal del motor arrastraria un
## halo negro por todo el contorno al escalar el icono.
func _save(fname: String) -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var samples := float(SS * SS)
	for y in range(SIZE):
		for x in range(SIZE):
			var hits := 0
			for sy in range(SS):
				for sx in range(SS):
					if _mask[(y * SS + sy) * _canvas + (x * SS + sx)] == 1:
						hits += 1
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, float(hits) / samples))
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + fname))

func _process(_delta: float) -> bool:
	return true
