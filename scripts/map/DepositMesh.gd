extends RefCounted
## Los yacimientos 3D en "maqueta" (docs/02, "Yacimientos en el mapa"; guia de
## estilo de edificios): bosque, veta de oro, hierro y pozo de petroleo como
## miniaturas de juguete con la paleta comun (ToyPalette), los mismos dos
## materiales que los edificios horneados y su parcela.
##
## Cada yacimiento es UNA malla con color por vertice (LotMesh): una llamada de
## dibujo (dos en el oro, cuyas pepitas y destellos brillan sin luz). Nada por
## fotograma: la malla sale de una cache por tipo, tamano, variante (de la
## semilla de la celda) y ETAPA de agotamiento (4 = entero ... 1 = casi
## gastado); MapGenerator la cambia solo cuando la etapa cambia al minarlo. Todo es pieza propia (cajas, cilindros,
## conos, bolas de LotMesh): sin modelos ajenos.
##
## Marco: centro de la huella en el origen, suelo en y = 0, X a lo largo de las
## columnas de la rejilla y Z de las filas (+Z es lo que ve la camara). La malla
## mide su huella (`dep_size` celdas de `cell`), sin estirar nada: un yacimiento
## de 3x2 tiene mas piezas que uno de 2x2, no piezas deformadas.
##
## Pura: sin nodos ni autoloads, para que la prueben headless (tests/map).

const MeshKit := preload("res://scripts/buildings/LotMesh.gd")
const Palette := preload("res://scripts/buildings/ToyPalette.gd")
const S := Palette.Slot

## Etapas de agotamiento: 4 entero, 1 el ultimo uso.
const STAGES := 4

## Alturas de las capas de suelo (por encima de la isla, como la parcela).
const Y_RIM := 0.010
const Y_FLOOR := 0.016
const Y_POOL := 0.024

## Oscurecimiento de contacto: lo que queda por debajo de AO_HEIGHT (y por
## encima del suelo) se oscurece hasta AO_DARK al tocarlo. Ancla las piezas.
const AO_HEIGHT := 0.22
const AO_DARK := 0.24

const IDS := ["forest", "gold_vein", "iron_deposit", "oil_well"]

## La etapa de un yacimiento con `uses` de `max_uses`: 4 entero, 1 el ultimo
## uso, 0 agotado (no se dibuja).
static func stage_of(uses: int, max_uses: int) -> int:
	if uses <= 0:
		return 0
	if max_uses <= 0:
		return STAGES
	return clampi(ceili(float(STAGES) * float(uses) / float(max_uses)), 1, STAGES)

## La semilla de un yacimiento: su celda (la misma regla que la vista 2D).
static func seed_for(cell: Vector2i) -> int:
	return cell.x * 73856093 ^ cell.y * 19349663

## Variantes por tipo y tamano: la semilla de la celda elige una. Dos
## yacimientos iguales en tipo, tamano, variante y etapa comparten la malla.
const VARIANTS := 4

## (tipo, ancho, fondo, variante, etapa, celda) -> ArrayMesh. Como mucho
## 4 tipos x 9-16 tamanos x 4 variantes x 4 etapas, y en la practica las pocas
## que hay en el mapa.
static var _cache := {}

## La variante de una semilla (0..VARIANTS-1).
static func variant_of(seed_val: int) -> int:
	return posmod(seed_val, VARIANTS)

## La malla compartida (cacheada) del yacimiento: lo que usa el mapa.
static func mesh_for(deposit_id: String, dep_size: Vector2i, seed_val: int, stage := STAGES, cell := 2.0) -> ArrayMesh:
	if stage <= 0:
		return null
	var v := variant_of(seed_val)
	var key := "%s|%d|%d|%d|%d|%.2f" % [deposit_id, dep_size.x, dep_size.y, v, stage, cell]
	if not _cache.has(key):
		_cache[key] = build(deposit_id, dep_size, v, stage, cell)
	return _cache[key]

## Vacia la cache (pruebas).
static func clear_cache() -> void:
	_cache.clear()

## La malla del yacimiento `deposit_id` de `dep_size` celdas, con su semilla y
## su etapa, recien montada (sin cache). Null para un tipo desconocido o la
## etapa 0. La misma semilla da siempre la misma malla.
static func build(deposit_id: String, dep_size: Vector2i, seed_val: int, stage := STAGES, cell := 2.0) -> ArrayMesh:
	if stage <= 0 or not IDS.has(deposit_id):
		return null
	var mk := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([deposit_id, seed_val])
	var w := float(dep_size.x) * cell
	var d := float(dep_size.y) * cell
	var f := float(clampi(stage, 1, STAGES)) / float(STAGES)
	match deposit_id:
		"forest": _forest(mk, rng, w, d, f)
		"gold_vein": _gold(mk, rng, w, d, f)
		"iron_deposit": _iron(mk, rng, w, d, f)
		"oil_well": _oil(mk, rng, w, d, f)
	_contact_shade(mk)
	var mesh := mk.commit()
	if mesh != null:
		mesh.resource_name = "deposit_%s" % deposit_id
	return mesh

# ── Colores ───────────────────────────────────────────────────────────

static func C(slot: int, delta := 0.0) -> Color:
	return Palette.tint(slot, delta)

# ── Bosque ────────────────────────────────────────────────────────────
# Acento verde. Un soto apretado de pinos de tres pisos y algun arbol de copa
# redonda (uno de cada ocho, de otono), con el pino mas alto atras (lo
# exagerado: un 35 % mas alto). Al talarlo, los arboles pasan a tocones y el
# claro se ve crecer; una pila de troncos en el borde dice "madera".

static func _forest(mk, rng: RandomNumberGenerator, w: float, d: float, f: float) -> void:
	_ground(mk, rng, w, d, 0.22, C(S.GREEN, -0.24), C(S.GREEN, -0.42))
	var pts := _points(rng, w, d, 1.2, 0.55)
	# El arbol heroe: el punto mas atras (Z menor), siempre en pie.
	var hero := 0
	for i in pts.size():
		if (pts[i] as Vector3).z < (pts[hero] as Vector3).z:
			hero = i
	var kept := maxi(1, ceili(float(pts.size()) * f))
	var order: Array = range(pts.size())
	order.erase(hero)
	order.push_front(hero)
	# Un azar propio por arbol: talar uno no cambia a los demas entre etapas.
	var tree_rngs: Array = []
	for i in pts.size():
		tree_rngs.append(_fork(rng))
	for k in order.size():
		var i: int = order[k]
		var p: Vector3 = pts[i]
		var tr: RandomNumberGenerator = tree_rngs[i]
		var h := tr.randf_range(1.15, 1.6)
		var round_tree := tr.randf() < 0.3
		if k >= kept:
			_stump(mk, p, tr)
			continue
		if i == hero:
			_pine(mk, p, h * 1.35, tr)
		elif round_tree:
			_round_tree(mk, p, h * 0.85, tr)
		else:
			_pine(mk, p, h, tr)
	# Matorral en los huecos del borde y la pila de troncos delante.
	for k in maxi(2, int(w * d / 6.0)):
		var b := Vector3(rng.randf_range(-0.42, 0.42) * w, 0, rng.randf_range(-0.42, 0.42) * d)
		mk.ball(b + Vector3(0, 0.08, 0), 0.2, C(S.GREEN, rng.randf_range(-0.2, -0.05)), Vector3(1.2, 0.6, 1.1))
	var pile := Vector3(w * 0.5 - 0.5, 0, d * 0.5 - 0.5)
	for k in 3:
		var off: Vector3 = [Vector3(-0.1, 0.1, 0), Vector3(0.1, 0.1, 0), Vector3(0, 0.27, 0)][k]
		_log(mk, pile + off, 0.7, 90.0)
	# Dos setas rojas: el detalle de juguete.
	for k in 2:
		var m := Vector3(rng.randf_range(-0.35, 0.35) * w, 0, rng.randf_range(-0.35, 0.35) * d)
		mk.cyl(m, 0.025, 0.07, C(S.CREAM), 5)
		mk.ball(m + Vector3(0, 0.08, 0), 0.06, C(S.RED), Vector3(1.0, 0.6, 1.0))

static func _pine(mk, p: Vector3, h: float, rng: RandomNumberGenerator) -> void:
	mk.cyl(p, 0.08, h * 0.3, C(S.WOOD, -0.22), 6)
	var base := C(S.GREEN, rng.randf_range(-0.26, -0.12))
	for t in 3:
		var y := h * (0.2 + float(t) * 0.22)
		var r := h * (0.34 - float(t) * 0.075)
		mk.cyl(p + Vector3(0, y, 0), r, h * (0.42 - float(t) * 0.04), base.lightened(0.05 * float(t)), 7, Vector3.UP, 0.0)

static func _round_tree(mk, p: Vector3, h: float, rng: RandomNumberGenerator) -> void:
	mk.cyl(p, 0.07, h * 0.45, C(S.WOOD, -0.18), 6)
	var leaf := C(S.GREEN, rng.randf_range(-0.04, 0.08))
	if rng.randf() < 0.28:
		leaf = C(S.BRASS, -0.06) if rng.randf() < 0.5 else C(S.TERRACOTTA, 0.02)
	mk.ball(p + Vector3(0, h * 0.62, 0), h * 0.32, leaf, Vector3(1.0, 0.9, 1.0))
	mk.ball(p + Vector3(-0.08, h * 0.8, 0.06), h * 0.18, leaf.lightened(0.1))

static func _stump(mk, p: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(0.1, 0.18)
	# Barato a proposito: un tocon cuesta la mitad que un pino (talar aligera).
	mk.cyl(p, 0.12, h, C(S.WOOD, -0.18), 6)
	mk.cyl(p + Vector3(0, h, 0), 0.095, 0.012, C(S.CREAM, -0.1), 5)

## Un tronco tumbado de `length` con sus cortes claros, girado `rot` grados.
static func _log(mk, c: Vector3, length: float, rot: float) -> void:
	var dir := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(rot))
	var a := c - dir * length * 0.5
	mk.cyl(a, 0.1, length, C(S.WOOD, -0.12), 7, dir, -1.0, false, true)
	mk.cyl(a - dir * 0.01, 0.08, 0.012, C(S.CREAM, -0.1), 7, -dir, -1.0)
	mk.cyl(a + dir * (length - 0.002), 0.08, 0.012, C(S.CREAM, -0.1), 7, dir, -1.0)

# ── Veta de oro ───────────────────────────────────────────────────────
# Acento laton. Peñas de piedra calida, clara, sobre un cascajo arenoso; en
# medio el racimo de cristales de oro (lo exagerado: casi un metro), pepitas a
# sus pies, dos destellos sin luz y la estaca de concesion con su banderin
# rojo. Al minarla se van los cristales y las pepitas; las peñas quedan.

static func _gold(mk, rng: RandomNumberGenerator, w: float, d: float, f: float) -> void:
	_ground(mk, rng, w, d, 0.2, C(S.STONE, -0.1), C(S.STONE, -0.32))
	_patches(mk, rng, w, d, 3, C(S.CREAM, -0.14))
	# Lo grande no crece sin tope: en un 3x3 la peña no pasa de un edificio.
	var m := minf(minf(w, d), 4.6)
	var rock := C(S.STONE, 0.02)
	# La peña madre y sus vecinas
	_rock(mk, Vector3(0, 0, -0.1 * d), m * 0.26, m * 0.2, rock, rng, 6)
	var tops: Array = []
	for p in _points(rng, w, d, 1.25, 0.55):
		var v: Vector3 = p
		if Vector2(v.x, v.z - (-0.1 * d)).length() < m * 0.3:
			continue
		var rh := rng.randf_range(0.25, 0.5)
		_rock(mk, v, rng.randf_range(0.2, 0.36), rh, rock.darkened(rng.randf_range(0.0, 0.12)), rng, 5)
		tops.append(v + Vector3(0, rh - 0.06, 0))
	# El racimo de cristales: cuantos quedan depende de la etapa.
	var top := Vector3(0, m * 0.2, -0.1 * d)
	var crystals := maxi(1, int(round(6.0 * f)))
	var h0 := m * 0.3
	# Azar aparte para lo que se gasta (cristales, vetas, pepitas): las peñas
	# y el resto no cambian de una etapa a otra.
	var crng := _fork(rng)
	var vrng := _fork(rng)
	var nrng := _fork(rng)
	for k in crystals:
		var a := TAU * float(k) / 6.0 + crng.randf_range(-0.3, 0.3)
		var lean := 0.0 if k == 0 else 0.45
		var dir := Vector3(cos(a) * lean, 1.0, sin(a) * lean).normalized()
		var at := top + Vector3(cos(a), 0, sin(a)) * (0.0 if k == 0 else m * 0.09)
		var h := h0 if k == 0 else crng.randf_range(0.45, 0.7) * h0
		_crystal(mk, at - dir * 0.05, dir, h, maxf(0.07, h * 0.24), C(S.BRASS, 0.14), C(S.BRASS, -0.1))
	# Vetas en las peñas pequenas: un cristal en la cima de algunas.
	for k in mini(tops.size(), int(round(3.0 * f))):
		_crystal(mk, tops[k], Vector3(vrng.randf_range(-0.4, 0.4), 1, vrng.randf_range(-0.4, 0.4)).normalized(), 0.3, 0.075, C(S.BRASS, 0.1), C(S.BRASS, -0.12))
	# Pepitas al pie
	for k in int(round(9.0 * f)):
		var a := nrng.randf() * TAU
		var r := nrng.randf_range(m * 0.28, m * 0.42)
		var p := Vector3(cos(a) * r, 0.05, -0.1 * d + sin(a) * r * 0.9)
		var size := nrng.randf_range(0.05, 0.08)
		# Una de cada tres brilla sin luz: el oro se ve tambien de noche y en la Tormenta.
		if k % 3 == 0:
			mk.ball(p, size * 0.9, C(S.GLOW), Vector3(1.0, 0.7, 1.0), true)
		else:
			mk.ball(p, size, C(S.BRASS, 0.12), Vector3(1.0, 0.7, 1.0))
	# Destellos (sin luz): la cima del cristal mayor y otro.
	if f > 0.3:
		mk.box(top + Vector3(0, h0 - 0.06, 0), Vector3(0.07, 0.07, 0.07), C(S.GLOW), true)
		mk.box(top + Vector3(0, h0 * 0.35, h0 * 0.24 + 0.01), Vector3(0.05, 0.05, 0.03), C(S.GLOW), true)
	_claim_stake(mk, Vector3(w * 0.5 - 0.4, 0, d * 0.5 - 0.35), C(S.RED))
	# El pico clavado delante de la peña madre
	var foot := Vector3(-m * 0.22, 0, d * 0.5 - 0.5)
	mk.beam(foot, foot + Vector3(0.15, 0.6, -0.12), 0.05, C(S.WOOD, 0.05))
	mk.beam(foot + Vector3(-0.1, 0.62, -0.08), foot + Vector3(0.38, 0.56, -0.16), 0.06, C(S.SLATE, -0.1))

static func _crystal(mk, base: Vector3, dir: Vector3, h: float, r: float, lit: Color, dark: Color) -> void:
	# Prisma de cuatro caras con punta: cuerpo y piramide.
	mk.cyl(base, r, h * 0.6, dark, 4, dir, r * 0.9)
	mk.cyl(base + dir * h * 0.6, r * 0.9, h * 0.4, lit, 4, dir, 0.0)

## Estaca de concesion: poste y banderin triangular (dos caras).
static func _claim_stake(mk, p: Vector3, col: Color) -> void:
	mk.cyl(p, 0.035, 0.85, C(S.WOOD, -0.05), 5)
	var t := p + Vector3(0, 0.82, 0)
	var a := t
	var b := t + Vector3(0, -0.24, 0)
	var c := t + Vector3(0.36, -0.1, 0.04)
	mk._tri(a, b, c, Vector3.BACK, col, false)
	mk._tri(a, c, b, Vector3.FORWARD, col.darkened(0.15), false)

# ── Hierro ────────────────────────────────────────────────────────────
# Acento rojo oxido. Crestas de roca oscura, pizarra y hierro, en angulo, con
# bandas de oxido; en medio dos agujas que se inclinan una contra otra (lo
# exagerado) y delante un monton de mineral rojizo. Al minarlo, las crestas
# bajan a tocones de roca y el monton mengua.

static func _iron(mk, rng: RandomNumberGenerator, w: float, d: float, f: float) -> void:
	_ground(mk, rng, w, d, 0.2, C(S.STONE, -0.34), C(S.IRON, -0.08))
	_patches(mk, rng, w, d, 4, C(S.TERRACOTTA, -0.34))
	var m := minf(minf(w, d), 4.6)
	# Las dos agujas
	for side in [-1.0, 1.0]:
		var base := Vector3(side * m * 0.13, 0, -0.08 * d)
		var tilt := Vector3(-side * 0.2, 1.0, -0.08).normalized()
		var h := (m * 0.38 if side < 0.0 else m * 0.3) * lerpf(0.45, 1.0, f)
		var needle := C(S.SLATE, -0.12) if side < 0.0 else C(S.TERRACOTTA, -0.3)
		_crag(mk, base, m * 0.15, h, tilt, needle, 5, rng.randf_range(0.0, 60.0))
	# Crestas alrededor: las que no "quedan" bajan a tocon.
	var pts := _points(rng, w, d, 1.15, 0.5)
	var kept := maxi(1, ceili(float(pts.size()) * f))
	var k := 0
	for p in pts:
		var v: Vector3 = p
		if Vector2(v.x, v.z + 0.08 * d).length() < m * 0.28:
			continue
		var h := rng.randf_range(0.4, 0.8) * (1.0 if k < kept else 0.35)
		# Mitad pizarra, mitad roca roja de oxido: el hierro se lee por el rojo.
		var roll := rng.randf()
		var col := C(S.SLATE, rng.randf_range(-0.2, 0.0))
		if roll < 0.45:
			col = C(S.TERRACOTTA, rng.randf_range(-0.36, -0.22))
		elif roll < 0.6:
			col = C(S.IRON, 0.12)
		_crag(mk, v, rng.randf_range(0.17, 0.27), h, Vector3(rng.randf_range(-0.2, 0.2), 1.0, rng.randf_range(-0.2, 0.2)).normalized(), col, rng.randi_range(4, 5), rng.randf_range(0.0, 90.0))
		k += 1
	# El monton de mineral, delante
	var pile := Vector3(m * 0.18, 0, d * 0.5 - 0.5)
	for i in int(round(10.0 * f)) + 2:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.28)
		var y := 0.06 + (0.1 if r < 0.12 else 0.0)
		var s := rng.randf_range(0.1, 0.16)
		var saved: Transform3D = mk.xf
		var spin_axis := Vector3(rng.randf() + 0.1, rng.randf() + 0.1, rng.randf() + 0.1).normalized()
		mk.xf = saved * Transform3D(Basis(spin_axis, rng.randf() * TAU), pile + Vector3(cos(a) * r, y, sin(a) * r))
		mk.box(Vector3.ZERO, Vector3(s, s * 0.8, s), C(S.TERRACOTTA, rng.randf_range(-0.42, -0.24)))
		mk.xf = saved

## Una cresta: tronco de piramide de `sides` caras, inclinada hacia `axis`,
## con dos bandas de oxido y la cima oxidada.
static func _crag(mk, base: Vector3, r: float, h: float, axis: Vector3, col: Color, sides: int, rot: float) -> void:
	var saved: Transform3D = mk.xf
	var spin := Basis(Vector3.UP, deg_to_rad(rot))
	mk.xf = saved * Transform3D(spin, base)
	# El giro solo reparte las caras: la inclinacion se queda donde se pidio.
	axis = (spin.inverse() * axis).normalized()
	var top_r := r * 0.42
	mk.cyl(Vector3.ZERO, r, h, col, sides, axis, top_r)
	var rust := C(S.TERRACOTTA, -0.3)
	# En una cresta ya roja, las bandas van en hierro oscuro (si no, no se ven).
	if col.r > col.b + 0.12:
		rust = C(S.IRON, 0.06)
	for t in [0.38, 0.7]:
		if h < 0.3:
			break
		var r0 := lerpf(r, top_r, t) * 1.05
		var r1 := lerpf(r, top_r, t + 0.07) * 1.05
		mk.cyl(axis * h * t, r0, h * 0.07, rust, sides, axis, r1)
	mk.cyl(axis * h, top_r, 0.05, rust.lightened(0.06), sides, axis, top_r * 0.6)
	mk.xf = saved

# ── Petroleo ──────────────────────────────────────────────────────────
# Acento rojo. Una balsa negra y brillante sobre tierra parda, con su borde de
# brea, burbujas y dos manchas de brillo; detras una torreta de prospeccion de
# madera de cuatro patas (lo exagerado) con la polea roja, el cubo colgando y
# el banderin, y a un lado dos bidones rojos (uno volcado) y juncos. Al
# gastarse, la balsa encoge y se secan los charcos de alrededor.

static func _oil(mk, rng: RandomNumberGenerator, w: float, d: float, f: float) -> void:
	_ground(mk, rng, w, d, 0.2, C(S.WOOD, -0.36), C(S.IRON, -0.05))
	var shrink := lerpf(0.5, 1.0, f)
	var pc := Vector3(0, 0, 0.08 * d)
	var rx := w * 0.3 * shrink
	var rz := d * 0.27 * shrink
	var tar := C(S.IRON, -0.12)
	var oil := C(S.IRON, -0.32)
	_blob(mk, rng, pc, rx + 0.12, rz + 0.1, Y_POOL - 0.004, tar)
	_blob(mk, rng, pc, rx, rz, Y_POOL, oil)
	# Brillo: un reflejo de cielo oscuro y dos chispas claras.
	_blob(mk, rng, pc + Vector3(-rx * 0.25, 0, -rz * 0.25), rx * 0.42, rz * 0.32, Y_POOL + 0.002, oil.lerp(C(S.SKY, -0.3), 0.45))
	mk.flat(pc + Vector3(-rx * 0.35, Y_POOL + 0.004, -rz * 0.4), Vector2(0.2, 0.05), C(S.SKY, 0.1))
	mk.flat(pc + Vector3(-rx * 0.1, Y_POOL + 0.004, -rz * 0.5), Vector2(0.08, 0.04), C(S.SKY, 0.1))
	# Burbujas
	for k in 3:
		var a := rng.randf() * TAU
		var p := pc + Vector3(cos(a) * rx * 0.5, Y_POOL, sin(a) * rz * 0.5)
		mk.ball(p, rng.randf_range(0.06, 0.1), C(S.IRON, 0.02), Vector3(1.0, 0.55, 1.0))
	# Charcos satelite (solo mientras queda mucho)
	var srng := _fork(rng)
	if f > 0.5:
		for k in 2:
			var sx := (-1.0 if k == 0 else 1.0)
			var sp := Vector3(sx * w * 0.32, 0, -sx * d * 0.22 + 0.15 * d)
			_blob(mk, srng, sp, w * 0.08, d * 0.07, Y_POOL - 0.002, oil)
	# Piedras manchadas alrededor
	for k in 4:
		var a := TAU * float(k) / 4.0 + rng.randf_range(-0.4, 0.4)
		var p := pc + Vector3(cos(a) * (rx + 0.2), 0, sin(a) * (rz + 0.18))
		_rock(mk, p, rng.randf_range(0.1, 0.16), rng.randf_range(0.08, 0.14), C(S.STONE, -0.3), rng, 5)
	# Juncos en el borde de delante
	for k in 6:
		var a := rng.randf_range(0.3, 2.6)
		var p := pc + Vector3(cos(a) * (rx + 0.05), 0, sin(a) * (rz + 0.06))
		var lean := Vector3(rng.randf_range(-0.25, 0.25), 1.0, rng.randf_range(-0.25, 0.25)).normalized()
		mk.beam(p, p + lean * rng.randf_range(0.28, 0.42), 0.035, C(S.GREEN, rng.randf_range(-0.3, -0.1)))
	# La torreta de prospeccion: cuatro patas de madera, dos pisos de
	# travesanos, polea arriba y el cubo colgando; banderin rojo en la punta.
	var tp := Vector3(0, 0, pc.z - rz - 0.3)
	var apex := tp + Vector3(0, 2.0, 0)
	var timber := C(S.WOOD, -0.08)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var foot: Vector3 = tp + Vector3(sx * 0.42, 0, sz * 0.32)
			mk.beam(foot, apex + Vector3(sx * 0.1, 0, sz * 0.08), 0.08, timber)
	for y in [0.6, 1.25]:
		var t: float = y / 2.0
		var hx := lerpf(0.42, 0.1, t)
		var hz := lerpf(0.32, 0.08, t)
		for sz in [-1.0, 1.0]:
			mk.box(tp + Vector3(0, y, sz * hz), Vector3(hx * 2.0 + 0.08, 0.06, 0.06), timber.darkened(0.08))
		for sx in [-1.0, 1.0]:
			mk.box(tp + Vector3(sx * hx, y, 0), Vector3(0.06, 0.06, hz * 2.0 + 0.08), timber.darkened(0.08))
	mk.box(apex + Vector3(0, 0.04, 0), Vector3(0.32, 0.1, 0.26), C(S.IRON, 0.1))
	mk.cyl(apex + Vector3(-0.1, 0.14, 0), 0.12, 0.2, C(S.RED, -0.05), 8, Vector3.RIGHT, -1.0, false, true)
	mk.beam(apex, apex + Vector3(0, -1.1, 0), 0.02, C(S.IRON, 0.2))
	mk.cyl(apex + Vector3(0, -1.3, 0), 0.1, 0.2, C(S.SLATE, 0.05), 7)
	mk.box(apex + Vector3(0, -1.11, 0), Vector3(0.22, 0.02, 0.02), C(S.IRON, 0.2))
	_claim_stake(mk, apex + Vector3(0.1, -0.2, 0.08), C(S.RED))
	# Bidones: uno de pie y otro volcado
	var bx := w * 0.5 - 0.45
	_drum(mk, Vector3(bx, 0, -d * 0.18), Vector3.UP)
	_drum(mk, Vector3(bx - 0.05, 0.16, d * 0.12 - 0.2), Vector3(-0.3, 0, 1).normalized())

static func _drum(mk, base: Vector3, axis: Vector3) -> void:
	var red := C(S.RED, -0.1)
	mk.cyl(base, 0.16, 0.42, red, 8, axis, -1.0, false, axis != Vector3.UP)
	for t in [0.28, 0.68]:
		mk.cyl(base + axis * 0.42 * t, 0.165, 0.035, red.darkened(0.25), 8, axis)
	mk.cyl(base + axis * 0.42, 0.13, 0.01, C(S.IRON, 0.1), 8, axis)

# ── Piezas comunes ────────────────────────────────────────────────────

## Una peña: tronco de piramide de `sides` caras, algo girado e inclinado.
static func _rock(mk, p: Vector3, r: float, h: float, col: Color, rng: RandomNumberGenerator, sides: int) -> void:
	var saved: Transform3D = mk.xf
	var ta := rng.randf() * TAU
	var tilt := Basis(Vector3(cos(ta), 0, sin(ta)), rng.randf_range(0.0, 0.18))
	mk.xf = saved * Transform3D(tilt * Basis(Vector3.UP, rng.randf() * TAU), p + Vector3(0, -0.02, 0))
	mk.cyl(Vector3.ZERO, r, h, col, sides, Vector3.UP, r * rng.randf_range(0.5, 0.7))
	mk.xf = saved

## El suelo del yacimiento: una mancha de borde irregular que llena casi toda
## la huella, con un reborde mas oscuro debajo (regla 5: separarlo de la isla).
static func _ground(mk, rng: RandomNumberGenerator, w: float, d: float, inset: float, floor_col: Color, rim_col: Color) -> void:
	var jitter := _jitter(rng, 20)
	_superblob(mk, Vector3.ZERO, w * 0.5 - inset + 0.08, d * 0.5 - inset + 0.08, Y_RIM, rim_col, jitter)
	_superblob(mk, Vector3.ZERO, w * 0.5 - inset, d * 0.5 - inset, Y_FLOOR, floor_col, jitter)

## Manchas planas sueltas sobre el suelo (arena, oxido).
static func _patches(mk, rng: RandomNumberGenerator, w: float, d: float, n: int, col: Color) -> void:
	for k in n:
		var p := Vector3(rng.randf_range(-0.3, 0.3) * w, 0, rng.randf_range(-0.3, 0.3) * d)
		_blob(mk, rng, p, rng.randf_range(0.25, 0.45), rng.randf_range(0.18, 0.35), Y_FLOOR + 0.002, col)

## Un azar hijo: se saca siempre (gaste o no quien lo usa), asi lo que viene
## despues no cambia con la etapa de agotamiento.
static func _fork(rng: RandomNumberGenerator) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = rng.randi()
	return r

## Mancha oval irregular (abanico de triangulos) a la altura `y`.
static func _blob(mk, rng: RandomNumberGenerator, c: Vector3, rx: float, rz: float, y: float, col: Color) -> void:
	var n := 14
	var prev := Vector3.ZERO
	var first := Vector3.ZERO
	var mid := Vector3(c.x, y, c.z)
	for i in n + 1:
		var a := TAU * float(i % n) / float(n)
		var k := 1.0 if i == n else rng.randf_range(0.85, 1.05)
		var p := Vector3(c.x + cos(a) * rx * k, y, c.z + sin(a) * rz * k)
		if i == n:
			p = first
		elif i == 0:
			first = p
		if i > 0:
			mk._tri(mid, prev, p, Vector3.UP, col, false)
		prev = p

static func _jitter(rng: RandomNumberGenerator, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in n:
		out.append(rng.randf_range(0.9, 1.0))
	return out

## Mancha de forma "casi rectangulo" (superelipse) para llenar la huella.
static func _superblob(mk, c: Vector3, hx: float, hz: float, y: float, col: Color, jitter: PackedFloat32Array) -> void:
	var n := jitter.size()
	var mid := Vector3(c.x, y, c.z)
	var pts: Array = []
	for i in n:
		var a := TAU * float(i) / float(n)
		var ca := cos(a)
		var sa := sin(a)
		var r := pow(pow(absf(ca), 4.0) + pow(absf(sa), 4.0), -0.25)
		pts.append(Vector3(c.x + ca * r * hx * jitter[i], y, c.z + sa * r * hz * jitter[i]))
	for i in n:
		mk._tri(mid, pts[i], pts[(i + 1) % n], Vector3.UP, col, false)

## Puntos repartidos por la huella (rejilla con jitter), en orden al azar.
static func _points(rng: RandomNumberGenerator, w: float, d: float, spacing: float, margin: float) -> Array:
	var nx := maxi(1, int(floor((w - margin * 2.0) / spacing)) + 1)
	var nz := maxi(1, int(floor((d - margin * 2.0) / spacing)) + 1)
	var sx := (w - margin * 2.0) / float(maxi(1, nx - 1)) if nx > 1 else 0.0
	var sz := (d - margin * 2.0) / float(maxi(1, nz - 1)) if nz > 1 else 0.0
	var out: Array = []
	for iz in nz:
		for ix in nx:
			var x := -w * 0.5 + margin + sx * float(ix) if nx > 1 else 0.0
			var z := -d * 0.5 + margin + sz * float(iz) if nz > 1 else 0.0
			x += rng.randf_range(-0.22, 0.22) * spacing
			z += rng.randf_range(-0.22, 0.22) * spacing
			out.append(Vector3(clampf(x, -w * 0.5 + margin * 0.6, w * 0.5 - margin * 0.6), 0, clampf(z, -d * 0.5 + margin * 0.6, d * 0.5 - margin * 0.6)))
	# Barajado con la misma semilla (shuffle() usaria el azar global).
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = out[i]
		out[i] = out[j]
		out[j] = t
	return out

## Oscurece lo que toca el suelo (sin tocar el suelo mismo).
static func _contact_shade(mk) -> void:
	var v: PackedVector3Array = mk._sv
	var n: PackedVector3Array = mk._sn
	var c: PackedColorArray = mk._sc
	for i in v.size():
		var y := v[i].y
		if y >= AO_HEIGHT:
			continue
		# Las capas de suelo (planas, mirando arriba, a ras) no se tocan.
		if n[i].y > 0.99 and y <= Y_POOL + 0.008:
			continue
		c[i] = c[i].darkened(AO_DARK * clampf(1.0 - y / AO_HEIGHT, 0.0, 1.0))
	mk._sc = c
