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
## Escalas del sistema de iconos (24 / 42 / 60 / 96 px): cada silueta sale
## tambien como `<id>_<px>.png`, trazada a esa medida desde las mismas
## coordenadas logicas de 64. UITheme.unit_icon(id, px) sirve la que toca.
const SCALES := [24, 42, 60, 96]

## Medida de salida en curso y su lienzo grande (_out * SS).
var _out: int = SIZE
var _canvas: int = SIZE * SS
var _mask: PackedByteArray

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var sizes: Array = [SIZE]
	sizes.append_array(SCALES)
	for px in sizes:
		_out = px
		_canvas = px * SS
		var suffix := "" if px == SIZE else "_%d" % px
		_draw_infantry()
		_save("infantry%s.png" % suffix)
		_draw_artillery()
		_save("artillery%s.png" % suffix)
		_draw_vehicle()
		_save("vehicle%s.png" % suffix)
		# Mar y aire (1.1, feat/aire-mar-vista). Los barcos de perfil con la proa
		# a la derecha (como el canon y el blindado); los aviones vistos desde
		# arriba (la cruz de las alas es lo que se lee a 24 px); el dirigible de
		# perfil (su globo es la forma).
		_draw_torpedo_boat()
		_save("torpedo_boat%s.png" % suffix)
		_draw_gunboat()
		_save("gunboat%s.png" % suffix)
		_draw_dreadnought()
		_save("dreadnought%s.png" % suffix)
		_draw_fighter()
		_save("fighter%s.png" % suffix)
		_draw_bomber()
		_save("bomber%s.png" % suffix)
		_draw_airship()
		_save("airship%s.png" % suffix)

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

# ── Mar ──────────────────────────────────────────────────────────────
# Tres cascos de perfil que se separan por el largo y por lo que llevan
# encima: la lancha es baja y lleva un tubo largo en cubierta; la canonera, un
# castillo con una chimenea y una torreta delante; el acorazado, el mas largo,
# con dos chimeneas, palo y torretas a proa y a popa.

## Lancha torpedera: casco bajo y fino, garita a popa con su chimenea y el tubo
## lanzatorpedos en cubierta.
func _draw_torpedo_boat() -> void:
	_clear()
	_poly([Vector2(3.0, 37.0), Vector2(50.0, 37.0), Vector2(62.0, 31.0), Vector2(55.0, 47.0), Vector2(9.0, 47.0)])
	_box(10.0, 27.0, 24.0, 37.0)
	_capsule(Vector2(15.0, 27.0), Vector2(13.0, 17.0), 2.6)
	_capsule(Vector2(28.0, 33.0), Vector2(52.0, 33.0), 2.4)
	_disc(52.0, 33.0, 3.0)

## Canonera: casco medio, castillo con puente, chimenea alta y la torreta de
## proa con un canon gordo.
func _draw_gunboat() -> void:
	_clear()
	_poly([Vector2(2.0, 39.0), Vector2(50.0, 39.0), Vector2(63.0, 33.0), Vector2(55.0, 52.0), Vector2(7.0, 52.0)])
	_box(12.0, 28.0, 32.0, 39.0)
	_box(16.0, 21.0, 28.0, 28.0)
	_capsule(Vector2(22.0, 21.0), Vector2(20.0, 8.0), 3.4)
	_disc(43.0, 35.0, 5.5)
	_capsule(Vector2(44.0, 33.0), Vector2(61.0, 26.0), 2.6)

## Acorazado: el casco mas largo, superestructura escalonada, dos chimeneas,
## palo con cofa y torretas de dos canones a proa y a popa.
func _draw_dreadnought() -> void:
	_clear()
	_poly([Vector2(1.0, 41.0), Vector2(52.0, 41.0), Vector2(63.0, 36.0), Vector2(57.0, 54.0), Vector2(5.0, 54.0)])
	_box(19.0, 31.0, 43.0, 41.0)
	_box(23.0, 23.0, 38.0, 31.0)
	_capsule(Vector2(27.0, 23.0), Vector2(26.0, 11.0), 3.0)
	_capsule(Vector2(35.0, 23.0), Vector2(34.0, 13.0), 3.0)
	_capsule(Vector2(31.0, 23.0), Vector2(31.0, 3.0), 1.3)
	_box(28.0, 6.0, 34.0, 9.0)
	_disc(50.0, 38.0, 4.8)
	_capsule(Vector2(50.0, 36.0), Vector2(63.0, 32.0), 1.6)
	_capsule(Vector2(50.0, 39.0), Vector2(63.0, 35.0), 1.6)
	_disc(11.0, 38.0, 4.5)
	_capsule(Vector2(11.0, 36.0), Vector2(1.0, 32.0), 1.5)

# ── Aire ─────────────────────────────────────────────────────────────

## Caza: biplano visto desde arriba. Fuselaje corto, ala recta, helice ancha
## (la barra de arriba) y el plano de cola.
func _draw_fighter() -> void:
	_clear()
	_capsule(Vector2(32.0, 12.0), Vector2(32.0, 56.0), 5.5)
	_box(5.0, 20.0, 59.0, 31.0)
	_box(19.0, 50.0, 45.0, 56.0)
	_capsule(Vector2(19.0, 6.0), Vector2(45.0, 6.0), 2.4)
	_disc(32.0, 9.0, 4.0)

## Bombardero: visto desde arriba, ala mas larga y ancha, dos motores con su
## helice delante del ala y doble timon en la cola.
func _draw_bomber() -> void:
	_clear()
	_capsule(Vector2(32.0, 8.0), Vector2(32.0, 60.0), 6.5)
	_box(1.0, 25.0, 63.0, 36.0)
	for x in [16.0, 48.0]:
		_capsule(Vector2(x, 15.0), Vector2(x, 34.0), 4.6)
		_capsule(Vector2(x - 8.0, 13.0), Vector2(x + 8.0, 13.0), 1.8)
	_box(17.0, 53.0, 47.0, 58.0)
	_box(15.0, 49.0, 20.0, 61.0)
	_box(44.0, 49.0, 49.0, 61.0)

## Dirigible: de perfil, el globo grande con las aletas de cola, la barquilla
## colgada y su helice.
func _draw_airship() -> void:
	_clear()
	_ellipse(33.0, 25.0, 28.0, 15.0)
	_poly([Vector2(9.0, 25.0), Vector2(1.0, 9.0), Vector2(11.0, 15.0)])
	_poly([Vector2(9.0, 25.0), Vector2(1.0, 41.0), Vector2(11.0, 35.0)])
	_capsule(Vector2(26.0, 38.0), Vector2(24.0, 44.0), 1.2)
	_capsule(Vector2(40.0, 38.0), Vector2(42.0, 44.0), 1.2)
	_box(21.0, 43.0, 45.0, 51.0)
	_capsule(Vector2(17.0, 47.0), Vector2(21.0, 47.0), 1.6)
	_capsule(Vector2(16.0, 41.0), Vector2(16.0, 53.0), 1.8)

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
	return Vector2((float(x) + 0.5) / _px_per_unit(), (float(y) + 0.5) / _px_per_unit())

## Pixeles del lienzo grande por unidad logica (64 unidades de lado).
func _px_per_unit() -> float:
	return float(_canvas) / float(SIZE)

## Rango de pixeles del lienzo grande que cubre un rectangulo logico.
func _span(lo: float, hi: float) -> Vector2i:
	return Vector2i(int(floor(lo * _px_per_unit())) - 1, int(ceil(hi * _px_per_unit())) + 1)

func _disc(cx: float, cy: float, r: float) -> void:
	var xs := _span(cx - r, cx + r)
	var ys := _span(cy - r, cy + r)
	for y in range(ys.x, ys.y):
		for x in range(xs.x, xs.y):
			if _at(x, y).distance_squared_to(Vector2(cx, cy)) <= r * r:
				_plot(x, y)

## Elipse rellena de semiejes `rx` y `ry` (el globo del dirigible).
func _ellipse(cx: float, cy: float, rx: float, ry: float) -> void:
	var xs := _span(cx - rx, cx + rx)
	var ys := _span(cy - ry, cy + ry)
	for y in range(ys.x, ys.y):
		for x in range(xs.x, xs.y):
			var p := _at(x, y)
			var dx := (p.x - cx) / rx
			var dy := (p.y - cy) / ry
			if dx * dx + dy * dy <= 1.0:
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
	var img := Image.create(_out, _out, false, Image.FORMAT_RGBA8)
	var samples := float(SS * SS)
	for y in range(_out):
		for x in range(_out):
			var hits := 0
			for sy in range(SS):
				for sx in range(SS):
					if _mask[(y * SS + sy) * _canvas + (x * SS + sx)] == 1:
						hits += 1
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, float(hits) / samples))
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + fname))

func _process(_delta: float) -> bool:
	return true
