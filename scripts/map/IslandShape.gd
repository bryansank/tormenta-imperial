extends RefCounted
## La forma de la isla: que celdas de la rejilla son tierra (isla irregular,
## 2026-10-12, docs/02 "Mapa aleatorio").
##
## Todo aqui es estatico y puro: sale de (ancho, alto, semilla, parametros) y de
## nada mas. Sin RNG global, sin nodos, sin autoloads: un test lo llama tantas
## veces como quiera y la misma semilla da siempre la misma isla. GridManager lo
## usa para la mascara de tierra; IslandGenerator (3D) e Island2D dibujan la
## costa con coast_polygon(), asi que las dos vistas ensenan la misma isla.
##
## Como se hace la costa:
##  1. Un campo por celda: una superelipse (lo "redondo" de la isla) cuyo radio
##     cambia con el angulo (armonicos de 2 a 6 lobulos), ruido fractal para la
##     costa menuda, bahias que muerden el borde y cabos que salen de el.
##  2. El umbral se elige por cuantil: se queda tierra justo el numero de celdas
##     buscado (area objetivo, entre land_min y land_max).
##  3. Limpieza morfologica: un cierre (rellena entrantes mas estrechos que unas
##     5 celdas, donde la arena de las dos orillas se pisaria) y una apertura
##     (quita lenguas de tierra de menos de 3 celdas: toda celda de tierra cabe
##     en un bloque de 3x3 de tierra). Se queda la masa que toca el Nucleo y se
##     rellenan los lagos interiores: una sola isla, sin agujeros.
##  4. El Nucleo y su acera, con margen, siempre son tierra; el borde de la
##     rejilla (edge_water celdas) siempre es agua: el mar entra en la rejilla.
##
## Version de forma: SQUARE es la isla de antes (toda la rejilla es tierra, la
## de las partidas guardadas sin "shape"); IRREGULAR es esta. Si algun dia el
## algoritmo cambia, se anade otra version y se deja esta tal cual: las
## partidas guardadas con ella tienen que seguir saliendo identicas.

const SQUARE := 1
const IRREGULAR := 2
const CURRENT := IRREGULAR

## Parametros por defecto (GameConfig.island_coast los copia; se guardan con la
## partida para que retocar el balance no mueva la costa de una partida vieja).
const DEFAULTS := {
	"edge_water": 3,        # celdas de agua en el borde de la rejilla
	"core_size": 3,         # lado del Nucleo
	"core_margin": 3,       # tierra garantizada alrededor de la acera del Nucleo
	"fraction_min": 0.46,   # parte de la rejilla util (sin el borde) que es tierra
	"fraction_max": 0.58,
	"land_min": 1550,       # celdas de tierra, minimo y maximo
	"land_max": 2300,
	"power_min": 2.0,       # superelipse: 2 = elipse, mas = mas cuadrada
	"power_max": 3.0,
	"harmonic_amp": 0.30,   # lobulos grandes (2-6 por vuelta)
	"noise_amp": 0.30,      # costa menuda
	"noise_freq": 0.05,     # por celda
	"bays_min": 2,
	"bays_max": 4,
	"bay_size_min": 0.20,   # radio de la bahia, en radios de isla
	"bay_size_max": 0.36,
	"capes_min": 1,
	"capes_max": 3,
	"cape_length_min": 1.00, # hasta donde llega el cabo, en radios de isla
	"cape_length_max": 1.25,
	"cape_width_min": 0.08,
	"cape_width_max": 0.14,
	"close_radius": 2.5,    # celdas
	"open_radius": 1.5,     # celdas
}

## Celdas junto al borde de mar en las que el campo baja (sin esto la costa
## se aplastaba contra el limite de la rejilla en lineas rectas).
const EDGE_SOFT := 7.0

const N8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
const N4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# ── Parametros ────────────────────────────────────────────────────────

## `p` completado con los valores por defecto (un guardado con parametros de
## una version anterior trae solo los que tenia).
static func with_defaults(p: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate()
	for k in p:
		if out.has(k):
			# Del JSON todo vuelve como float: cada valor con el tipo del de por
			# defecto, para que dos copias iguales se comparen iguales.
			out[k] = int(p[k]) if typeof(DEFAULTS[k]) == TYPE_INT else float(p[k])
	return out

## Rectangulo del Nucleo para una rejilla w x h: la misma cuenta que
## GameManager._new_game() (origen en w/2, h/2).
static func core_rect(w: int, h: int, core_size: int = 3) -> Rect2i:
	return Rect2i(Vector2i(w / 2, h / 2), Vector2i(core_size, core_size))

## Lo que siempre es tierra: Nucleo + acera + margen.
static func core_keep_rect(w: int, h: int, p: Dictionary) -> Rect2i:
	var q := with_defaults(p)
	return core_rect(w, h, int(q["core_size"])).grow(1 + int(q["core_margin"]))

## Celdas de tierra que se buscan para una rejilla w x h con esta semilla.
static func target_land(w: int, h: int, island_seed: int, p: Dictionary) -> int:
	var q := with_defaults(p)
	var edge: int = int(q["edge_water"])
	var usable: int = maxi(0, w - 2 * edge) * maxi(0, h - 2 * edge)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("island_area:%d" % island_seed)
	var frac: float = rng.randf_range(float(q["fraction_min"]), float(q["fraction_max"]))
	var t: int = int(round(usable * frac))
	return clampi(t, mini(int(q["land_min"]), usable), mini(int(q["land_max"]), usable))

# ── Mascara ───────────────────────────────────────────────────────────

## Mascara de tierra (1 = tierra, 0 = agua), fila a fila: indice y * w + x.
## SQUARE (o semilla < 0): toda la rejilla es tierra.
static func build_mask(w: int, h: int, island_seed: int, p: Dictionary = {}, version: int = CURRENT) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(w * h)
	if version == SQUARE or island_seed < 0 or w <= 0 or h <= 0:
		mask.fill(1)
		return mask
	var q := with_defaults(p)
	var field := _field(w, h, island_seed, q)
	var target: int = target_land(w, h, island_seed, q)
	# Valores ordenados de mayor a menor: el umbral para quedarse con k celdas.
	var sorted := field.duplicate()
	sorted.sort()
	var k := target
	var best := PackedByteArray()
	var best_err := 1 << 30
	for attempt in range(5):
		k = clampi(k, 1, sorted.size())
		var thr: float = sorted[sorted.size() - k]
		var m := PackedByteArray()
		m.resize(w * h)
		for i in range(w * h):
			m[i] = 1 if field[i] >= thr else 0
		m = _clean(m, w, h, q)
		var n := count_land(m)
		var err := absi(n - target)
		if err < best_err:
			best_err = err
			best = m
		if err <= maxi(8, int(target * 0.02)):
			break
		k += target - n
	return best

static func count_land(mask: PackedByteArray) -> int:
	var n := 0
	for v in mask:
		n += v
	return n

## El campo continuo: alto = tierra. Las celdas del borde llevan -INF (agua
## segura) y las del Nucleo +INF (tierra segura).
static func _field(w: int, h: int, island_seed: int, q: Dictionary) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("island_shape:%d" % island_seed)
	var edge: int = int(q["edge_water"])
	var hx: float = maxf(1.0, w * 0.5 - edge)
	var hy: float = maxf(1.0, h * 0.5 - edge)
	var power: float = rng.randf_range(float(q["power_min"]), float(q["power_max"]))
	var harmonics: Array = []
	for k in [2, 3, 4, 5, 6]:
		var amp: float = float(q["harmonic_amp"]) * rng.randf_range(0.25, 1.0) * 2.0 / float(k)
		harmonics.append([float(k), amp, rng.randf() * TAU])
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = float(q["noise_freq"])
	noise.fractal_octaves = 3
	var bays: Array = []
	for i in range(rng.randi_range(int(q["bays_min"]), int(q["bays_max"]))):
		var a: float = rng.randf() * TAU
		var size: float = rng.randf_range(float(q["bay_size_min"]), float(q["bay_size_max"]))
		var dist: float = rng.randf_range(0.72, 0.95)
		bays.append([Vector2(cos(a), sin(a)) * dist, size])
	var capes: Array = []
	for i in range(rng.randi_range(int(q["capes_min"]), int(q["capes_max"]))):
		var a: float = rng.randf() * TAU
		var dir := Vector2(cos(a), sin(a))
		var length: float = rng.randf_range(float(q["cape_length_min"]), float(q["cape_length_max"]))
		var width: float = rng.randf_range(float(q["cape_width_min"]), float(q["cape_width_max"]))
		capes.append([dir * 0.5, dir * length, width])
	var keep := core_keep_rect(w, h, q)
	var noise_amp: float = float(q["noise_amp"])
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in range(h):
		for x in range(w):
			var i := y * w + x
			if x < edge or y < edge or x >= w - edge or y >= h - edge:
				out[i] = -1.0e9
				continue
			if keep.has_point(Vector2i(x, y)):
				out[i] = 1.0e9
				continue
			var u: float = (x + 0.5 - w * 0.5) / hx
			var v: float = (y + 0.5 - h * 0.5) / hy
			var r: float = pow(pow(absf(u), power) + pow(absf(v), power), 1.0 / power)
			var ang: float = atan2(v, u)
			var rad := 1.0
			for hm in harmonics:
				rad += float(hm[1]) * sin(float(hm[0]) * ang + float(hm[2]))
			var f: float = rad - r + noise_amp * noise.get_noise_2d(float(x), float(y))
			var pt := Vector2(u, v)
			for b in bays:
				var d: float = pt.distance_to(b[0])
				var s: float = b[1]
				if d < s:
					f -= 0.9 * (1.0 - smoothstep(0.0, s, d))
			for c in capes:
				var ds: float = _dist_to_segment(pt, c[0], c[1])
				var cw: float = c[2]
				if ds < cw:
					f += 0.55 * (1.0 - ds / cw)
			# Cerca del borde de mar, cuesta abajo: la costa no se aplasta contra
			# el limite de la rejilla en una recta.
			var to_edge: float = float(mini(mini(x - edge, w - 1 - edge - x), mini(y - edge, h - 1 - edge - y)))
			f -= 0.7 * (1.0 - smoothstep(0.0, EDGE_SOFT, to_edge))
			out[i] = f
	return out

static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Cierre, apertura, una sola masa (la del Nucleo), sin lagos; borde de agua y
## Nucleo en tierra por encima de todo.
static func _clean(m: PackedByteArray, w: int, h: int, q: Dictionary) -> PackedByteArray:
	var edge: int = int(q["edge_water"])
	var keep := core_keep_rect(w, h, q)
	for pass_i in range(2):
		m = _close(m, w, h, float(q["close_radius"]))
		m = _open(m, w, h, float(q["open_radius"]))
		_force(m, w, h, edge, keep)
		m = _keep_core_component(m, w, h, keep.get_center())
		m = _fill_holes(m, w, h)
	return m

static func _force(m: PackedByteArray, w: int, h: int, edge: int, keep: Rect2i) -> void:
	for y in range(h):
		for x in range(w):
			if x < edge or y < edge or x >= w - edge or y >= h - edge:
				m[y * w + x] = 0
			elif keep.has_point(Vector2i(x, y)):
				m[y * w + x] = 1

## Distancia (chaflan 1 / raiz de 2, en celdas) de cada celda a la celda con
## valor `target` mas cercana. `outside_is_target`: lo de fuera de la rejilla
## cuenta como tal (el agua sigue mas alla del borde).
static func distance_to(m: PackedByteArray, w: int, h: int, target: int, outside_is_target: bool) -> PackedFloat32Array:
	var big := 1.0e6
	var d := PackedFloat32Array()
	d.resize(w * h)
	for i in range(w * h):
		d[i] = 0.0 if m[i] == target else big
	if outside_is_target:
		for y in range(h):
			for x in range(w):
				if x == 0 or y == 0 or x == w - 1 or y == h - 1:
					var i := y * w + x
					d[i] = minf(d[i], 1.0)
	var s2 := sqrt(2.0)
	# Pasada hacia delante
	for y in range(h):
		for x in range(w):
			var i := y * w + x
			var v: float = d[i]
			if x > 0: v = minf(v, d[i - 1] + 1.0)
			if y > 0:
				v = minf(v, d[i - w] + 1.0)
				if x > 0: v = minf(v, d[i - w - 1] + s2)
				if x < w - 1: v = minf(v, d[i - w + 1] + s2)
			d[i] = v
	# Pasada hacia atras
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			var v: float = d[i]
			if x < w - 1: v = minf(v, d[i + 1] + 1.0)
			if y < h - 1:
				v = minf(v, d[i + w] + 1.0)
				if x < w - 1: v = minf(v, d[i + w + 1] + s2)
				if x > 0: v = minf(v, d[i + w - 1] + s2)
			d[i] = v
	return d

static func _dilate(m: PackedByteArray, w: int, h: int, r: float) -> PackedByteArray:
	var d := distance_to(m, w, h, 1, false)
	var out := PackedByteArray()
	out.resize(w * h)
	for i in range(w * h):
		out[i] = 1 if d[i] <= r + 0.01 else 0
	return out

static func _erode(m: PackedByteArray, w: int, h: int, r: float) -> PackedByteArray:
	var d := distance_to(m, w, h, 0, true)
	var out := PackedByteArray()
	out.resize(w * h)
	for i in range(w * h):
		out[i] = 1 if d[i] > r + 0.01 else 0
	return out

static func _close(m: PackedByteArray, w: int, h: int, r: float) -> PackedByteArray:
	return _erode(_dilate(m, w, h, r), w, h, r)

static func _open(m: PackedByteArray, w: int, h: int, r: float) -> PackedByteArray:
	return _dilate(_erode(m, w, h, r), w, h, r)

## Solo la masa de tierra (4 vecinos) que contiene `seed_cell`.
static func _keep_core_component(m: PackedByteArray, w: int, h: int, seed_cell: Vector2i) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	if seed_cell.x < 0 or seed_cell.y < 0 or seed_cell.x >= w or seed_cell.y >= h:
		return out
	if m[seed_cell.y * w + seed_cell.x] == 0:
		return out
	var queue: Array = [seed_cell]
	out[seed_cell.y * w + seed_cell.x] = 1
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for dv in N4:
			var n: Vector2i = c + dv
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			var i := n.y * w + n.x
			if m[i] == 1 and out[i] == 0:
				out[i] = 1
				queue.append(n)
	return out

## El agua que no llega al borde de la rejilla (4 vecinos) se vuelve tierra.
static func _fill_holes(m: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var sea := PackedByteArray()
	sea.resize(w * h)
	var queue: Array = []
	for y in range(h):
		for x in range(w):
			if (x == 0 or y == 0 or x == w - 1 or y == h - 1) and m[y * w + x] == 0:
				sea[y * w + x] = 1
				queue.append(Vector2i(x, y))
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for dv in N4:
			var n: Vector2i = c + dv
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			var i := n.y * w + n.x
			if m[i] == 0 and sea[i] == 0:
				sea[i] = 1
				queue.append(n)
	var out := PackedByteArray()
	out.resize(w * h)
	for i in range(w * h):
		out[i] = 0 if sea[i] == 1 else 1
	return out

# ── Consultas sobre una mascara ───────────────────────────────────────

static func is_land(mask: PackedByteArray, w: int, h: int, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= w or cell.y >= h:
		return false
	return mask.size() != w * h or mask[cell.y * w + cell.x] == 1

## Rectangulo (en celdas) que contiene toda la tierra.
static func land_bounds(mask: PackedByteArray, w: int, h: int) -> Rect2i:
	if mask.size() != w * h:
		return Rect2i(0, 0, w, h)
	var lo := Vector2i(w, h)
	var hi := Vector2i(-1, -1)
	for y in range(h):
		for x in range(w):
			if mask[y * w + x] == 1:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		return Rect2i(0, 0, w, h)
	return Rect2i(lo, hi - lo + Vector2i.ONE)

## Numero de masas de tierra (4 vecinos). Para los tests: tiene que ser 1.
static func land_components(mask: PackedByteArray, w: int, h: int) -> int:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var count := 0
	for start in range(w * h):
		if mask[start] == 0 or seen[start] == 1:
			continue
		count += 1
		var queue: Array = [Vector2i(start % w, start / w)]
		seen[start] = 1
		var head := 0
		while head < queue.size():
			var c: Vector2i = queue[head]
			head += 1
			for dv in N4:
				var n: Vector2i = c + dv
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
					continue
				var i := n.y * w + n.x
				if mask[i] == 1 and seen[i] == 0:
					seen[i] = 1
					queue.append(n)
	return count

## Celdas de agua que no llegan al mar abierto (lagos). Tiene que ser 0.
static func lake_cells(mask: PackedByteArray, w: int, h: int) -> int:
	var filled := _fill_holes(mask, w, h)
	return count_land(filled) - count_land(mask)

# ── Costa (poligono) ──────────────────────────────────────────────────

## El contorno de la hierba, en coordenadas de mundo (XZ como Vector2), en
## sentido antihorario (area con signo positiva). Pasa a media celda de la
## tierra por fuera: marching squares sobre las esquinas de celda, contando como
## "dentro" cada esquina que toca una celda de tierra, y dos pasadas de Chaikin
## para redondear la escalera. Toda celda de tierra queda dentro entera (lo
## comprueba un test). Vacio si no hay tierra.
static func coast_polygon(mask: PackedByteArray, w: int, h: int, cell_size: float, origin: Vector2, smooth_passes: int = 2) -> PackedVector2Array:
	var vw := w + 1
	var vin := PackedByteArray()
	vin.resize(vw * (h + 1))
	for y in range(h):
		for x in range(w):
			if mask[y * w + x] == 1:
				vin[y * vw + x] = 1
				vin[y * vw + x + 1] = 1
				vin[(y + 1) * vw + x] = 1
				vin[(y + 1) * vw + x + 1] = 1
	# Segmentos entre puntos medios de aristas de la red (claves dobladas).
	var adj := {}
	for j in range(-1, h + 1):
		for i in range(-1, w + 1):
			var a := _vin(vin, vw, w, h, i, j)
			var b := _vin(vin, vw, w, h, i + 1, j)
			var c := _vin(vin, vw, w, h, i + 1, j + 1)
			var d := _vin(vin, vw, w, h, i, j + 1)
			var e0 := Vector2i(2 * i + 1, 2 * j)
			var e1 := Vector2i(2 * i + 2, 2 * j + 1)
			var e2 := Vector2i(2 * i + 1, 2 * j + 2)
			var e3 := Vector2i(2 * i, 2 * j + 1)
			var cross: Array = []
			if a != b: cross.append(e0)
			if b != c: cross.append(e1)
			if c != d: cross.append(e2)
			if d != a: cross.append(e3)
			if cross.size() == 2:
				_link(adj, cross[0], cross[1])
			elif cross.size() == 4:
				# Silla: las esquinas de dentro en diagonal quedan unidas (la
				# tierra es una sola masa), asi que se aislan las de fuera.
				if a:
					_link(adj, e0, e1)
					_link(adj, e2, e3)
				else:
					_link(adj, e3, e0)
					_link(adj, e1, e2)
	# Lazos; el de mayor area es la costa.
	var best := PackedVector2Array()
	var best_area := 0.0
	var used := {}
	for start in adj:
		if used.has(start):
			continue
		var loop := PackedVector2Array()
		var prev: Variant = null
		var cur: Vector2i = start
		while true:
			used[cur] = true
			loop.append(Vector2(cur) * 0.5)
			var nbrs: Array = adj[cur]
			var nxt: Vector2i = nbrs[0]
			if prev != null and nxt == prev and nbrs.size() > 1:
				nxt = nbrs[1]
			if nxt == start or used.has(nxt):
				break
			prev = cur
			cur = nxt
		var area := absf(signed_area(loop))
		if area > best_area:
			best_area = area
			best = loop
	if best.size() < 3:
		return PackedVector2Array()
	if signed_area(best) < 0.0:
		best.reverse()
	for s in range(smooth_passes):
		best = chaikin(best)
	best = relax(best, mask, w, h, RELAX_STEPS)
	best = wobble_out(best, hash("coast:%d:%d" % [w, h]) + count_land(mask), WOBBLE_CELLS)
	var out := PackedVector2Array()
	out.resize(best.size())
	for k in range(best.size()):
		out[k] = origin + best[k] * cell_size
	return out

## Pasadas de suavizado (Laplace) sobre la costa: quitan la escalera y los
## chaflanes de 45 grados que deja la red de celdas.
const RELAX_STEPS := 10
## Holgura minima (en celdas) entre la costa y cualquier celda de tierra: un
## paso de suavizado que acercase un punto mas que esto se deshace.
const COAST_CLEARANCE := 0.2
## Ondulacion de la costa hacia fuera (en celdas): rompe las rectas largas.
## Solo hacia fuera, asi que no puede meter agua en una celda de tierra.
const WOBBLE_CELLS := 0.25

## Suaviza el contorno (en coordenadas de celda) sin dejar que se acerque a la
## tierra mas de COAST_CLEARANCE: cada punto va hacia el medio de sus vecinos y,
## si con eso pisaria la holgura, se queda donde estaba.
static func relax(poly: PackedVector2Array, mask: PackedByteArray, w: int, h: int, steps: int) -> PackedVector2Array:
	var n := poly.size()
	var cur := poly
	for it in range(steps):
		var nxt := PackedVector2Array()
		nxt.resize(n)
		for i in range(n):
			var mid := (cur[(i - 1 + n) % n] + cur[(i + 1) % n]) * 0.5
			var cand := cur[i].lerp(mid, 0.5)
			nxt[i] = cand if land_clearance(mask, w, h, cand) >= COAST_CLEARANCE else cur[i]
		cur = nxt
	return cur

## Distancia (en celdas) de un punto (coordenadas de celda) a la celda de
## tierra mas cercana, mirando solo las de alrededor (vale hasta ~1 celda).
static func land_clearance(mask: PackedByteArray, w: int, h: int, pt: Vector2) -> float:
	var cx := floori(pt.x)
	var cy := floori(pt.y)
	var best := 2.0
	for y in range(cy - 1, cy + 2):
		for x in range(cx - 1, cx + 2):
			if x < 0 or y < 0 or x >= w or y >= h or mask[y * w + x] == 0:
				continue
			var dx: float = maxf(maxf(x - pt.x, 0.0), pt.x - (x + 1))
			var dy: float = maxf(maxf(y - pt.y, 0.0), pt.y - (y + 1))
			best = minf(best, sqrt(dx * dx + dy * dy))
	return best

## Empuja cada punto hacia fuera una cantidad entre 0 y `amp` que cambia
## despacio a lo largo de la costa (suma de senos con fases de la semilla).
static func wobble_out(poly: PackedVector2Array, seed_value: int, amp: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 3 or amp <= 0.0:
		return poly
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var p3 := rng.randf() * TAU
	var normals := outward_normals(poly, 2)
	var total := 0.0
	for i in range(n):
		total += poly[i].distance_to(poly[(i + 1) % n])
	# Un numero entero de ondas por vuelta: la costa cierra sin escalon.
	var k1 := maxf(1.0, round(total / 14.0))
	var k2 := maxf(1.0, round(total / 5.7))
	var k3 := maxf(1.0, round(total / 2.7))
	var out := PackedVector2Array()
	out.resize(n)
	var along := 0.0
	for i in range(n):
		if i > 0:
			along += poly[i].distance_to(poly[i - 1])
		var t := TAU * along / maxf(total, 1e-6)
		var v := sin(t * k1 + p1) * 0.5 + sin(t * k2 + p2) * 0.3 + sin(t * k3 + p3) * 0.2
		out[i] = poly[i] + normals[i] * amp * (0.5 + 0.5 * v)
	return out

static func _vin(vin: PackedByteArray, vw: int, w: int, h: int, i: int, j: int) -> bool:
	if i < 0 or j < 0 or i > w or j > h:
		return false
	return vin[j * vw + i] == 1

static func _link(adj: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if not adj.has(a):
		adj[a] = []
	if not adj.has(b):
		adj[b] = []
	adj[a].append(b)
	adj[b].append(a)

static func signed_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	var n := poly.size()
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		s += a.x * b.y - b.x * a.y
	return s * 0.5

## Una pasada de Chaikin sobre un poligono cerrado (cada punto nuevo cae sobre
## una arista del viejo, a 1/4 y 3/4).
static func chaikin(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out

## Normales hacia fuera, una por vertice, suavizadas con `window` vecinos a
## cada lado (asi el anillo de playa no se cruza en las curvas cerradas). El
## poligono tiene que venir antihorario (signed_area > 0).
static func outward_normals(poly: PackedVector2Array, window: int = 3) -> PackedVector2Array:
	var n := poly.size()
	var raw := PackedVector2Array()
	raw.resize(n)
	var sign_f := 1.0 if signed_area(poly) >= 0.0 else -1.0
	for i in range(n):
		var t := poly[(i + 1) % n] - poly[(i - 1 + n) % n]
		raw[i] = Vector2(t.y, -t.x).normalized() * sign_f
	var out := PackedVector2Array()
	out.resize(n)
	for i in range(n):
		var acc := Vector2.ZERO
		for k in range(-window, window + 1):
			acc += raw[(i + k + n) % n]
		out[i] = acc.normalized() if acc.length_squared() > 1e-9 else raw[i]
	return out

## El poligono crecido `dist` hacia fuera a lo largo de sus normales (mismo
## numero de puntos y en el mismo orden: sirve para tender anillos de malla).
static func offset_along(poly: PackedVector2Array, normals: PackedVector2Array, dist: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in range(poly.size()):
		out[i] = poly[i] + normals[i] * dist
	return out

## Distancia aproximada al borde de la hierba, en unidades de mundo, por celda
## de una rejilla ampliada `pad` celdas por cada lado (para el agua de la 3D:
## mas clara junto a la costa). 0 sobre la tierra.
static func water_distance(mask: PackedByteArray, w: int, h: int, cell_size: float, pad: int) -> PackedFloat32Array:
	var pw := w + 2 * pad
	var ph := h + 2 * pad
	var big := PackedByteArray()
	big.resize(pw * ph)
	for y in range(h):
		for x in range(w):
			if is_land(mask, w, h, Vector2i(x, y)):
				big[(y + pad) * pw + x + pad] = 1
	var d := distance_to(big, pw, ph, 1, false)
	for i in range(d.size()):
		# Del centro de la celda de tierra a la hierba hay media celda, y la
		# hierba asoma otra media por fuera.
		d[i] = maxf(0.0, (d[i] - 1.0) * cell_size)
	return d
