extends RefCounted
## Junta piezas low-poly (cajas, cilindros, conos, bolas) en UNA malla con color
## por vertice y, como mucho, dos superficies: "solida" (con luz) y "brillo"
## (sin luz: ventanas, brasas, la luz del laboratorio). La parcela entera de un
## edificio, o su pieza exagerada, es asi una sola llamada de dibujo con dos
## materiales compartidos por todo el mapa: lo que pide el renderizador Mobile.
##
## Las piezas se colocan con `xf` (la transformacion en curso): el atrezo se
## gira, se vuelca o se parte cambiandola, sin repetir la geometria.

const Palette := preload("res://scripts/buildings/ToyPalette.gd")

var xf := Transform3D.IDENTITY
## Quemado: los colores van hacia el carbon (ruina).
var burnt := 0.0

## Vertices, normales y colores de cada superficie, en arrays empaquetados
## (sin SurfaceTool: tres llamadas por vertice menos, la parcela se monta en
## la mitad de tiempo).
var _sv := PackedVector3Array()
var _sn := PackedVector3Array()
var _sc := PackedColorArray()
var _gv := PackedVector3Array()
var _gn := PackedVector3Array()
var _gc := PackedColorArray()

const CHAR := Color(0.08, 0.07, 0.06)

## Los dos materiales de la paleta comun (ToyPalette): los mismos que llevan
## los modelos horneados de los edificios, asi parcela y edificio comparten.
static func solid_material() -> Material:
	return Palette.solid_material()

static func glow_material() -> Material:
	return Palette.glow_material()

func is_empty() -> bool:
	return _sv.is_empty() and _gv.is_empty()

## La malla, o null si no hay nada. Superficie 0 la solida (si la hay).
func commit() -> ArrayMesh:
	if is_empty():
		return null
	var mesh := ArrayMesh.new()
	if not _sv.is_empty():
		_add_surface(mesh, _sv, _sn, _sc, solid_material())
	if not _gv.is_empty():
		_add_surface(mesh, _gv, _gn, _gc, glow_material())
	return mesh

static func _add_surface(mesh: ArrayMesh, v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, mat: Material) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)

# ── Triangulos ───────────────────────────────────────────────────────

## Un triangulo con su normal, en el orden de cara que usa Godot (horario visto
## desde delante): si llega al reves, se da la vuelta.
func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color, glow: bool) -> void:
	a = xf * a
	b = xf * b
	c = xf * c
	n = (xf.basis * n).normalized()
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	if glow:
		_gv.append(a)
		_gv.append(b)
		_gv.append(c)
		for i in 3:
			_gn.append(n)
			_gc.append(col)
	else:
		var final := col.lerp(CHAR, burnt) if burnt > 0.0 else col
		_sv.append(a)
		_sv.append(b)
		_sv.append(c)
		for i in 3:
			_sn.append(n)
			_sc.append(final)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color, glow: bool) -> void:
	_tri(a, b, c, n, col, glow)
	_tri(a, c, d, n, col, glow)

## Triangulos ya hechos (una pieza horneada, ver ToyPalette y
## tools/build_toy_models.gd): `v`, `n` y `c` de tres en tres, en el espacio de
## la pieza, colocados con `xf`. `glow` los manda a la superficie sin luz. El
## quemado de la ruina tambien les llega.
func append(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, glow := false) -> void:
	var nb := xf.basis.inverse().transposed()
	var flip := xf.basis.determinant() < 0.0
	var tv := _gv if glow else _sv
	var tn := _gn if glow else _sn
	var tc := _gc if glow else _sc
	var base := tv.size()
	tv.resize(base + v.size())
	tn.resize(base + v.size())
	tc.resize(base + v.size())
	var i := 0
	while i < v.size():
		for k in 3:
			var src := i + (k if not flip or k == 0 else 3 - k)
			var col: Color = c[src]
			if burnt > 0.0 and not glow:
				col = col.lerp(CHAR, burnt)
			tv[base + i + k] = xf * v[src]
			tn[base + i + k] = (nb * n[src]).normalized()
			tc[base + i + k] = col
		i += 3
	if glow:
		_gv = tv
		_gn = tn
		_gc = tc
	else:
		_sv = tv
		_sn = tn
		_sc = tc

## Lo mismo con una malla ya hecha (ArrayMesh horneada): la superficie que use
## el material sin luz va a "brillo", el resto a "solida".
func append_mesh(mesh: ArrayMesh) -> void:
	if mesh == null:
		return
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var glow := mesh.surface_get_material(s) == glow_material()
		append(arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_NORMAL], arr[Mesh.ARRAY_COLOR], glow)

# ── Borde de contacto (V8, regla 5 de la guia de estilo) ─────────────

## Oscurece la base de lo solido, horneado en el color de vertice (cero coste
## en el juego). Dos capas:
## - AO suave: todo lo que queda por debajo de `ao_h` se oscurece hasta `ao_dark`
##   en y = 0;
## - borde: las caras de pared (normal casi horizontal) se oscurecen ademas
##   hasta `edge_dark` en una franja fina de `edge_h`. Es la linea oscura que
##   separa el edificio del suelo en cualquier fondo, tambien en la Tormenta.
## Antes se cortan por y = `edge_h` las paredes que la cruzan: si no, una pared
## con vertices solo abajo y arriba llevaria el oscuro degradado por toda su
## altura en vez de en una franja. Solo se parten paredes de la base (lo plano
## y el AO suave no se cortan: seria pagar triangulos que no se ven).
## El color esta en sRGB, como lo escribe ToyPalette.
func contact_edge(ao_h: float, ao_dark: float, edge_h: float, edge_dark: float) -> void:
	var v := _sv
	var n := _sn
	var c := _sc
	var out := _split_at(v, n, c, edge_h)
	v = out[0]
	n = out[1]
	c = out[2]
	for i in v.size():
		var y := maxf(0.0, v[i].y)
		var k := 1.0
		if y < ao_h:
			k *= 1.0 - ao_dark * (1.0 - y / ao_h)
		if y < edge_h and absf(n[i].y) < 0.6:
			k *= 1.0 - edge_dark * (1.0 - y / edge_h)
		if k < 1.0:
			c[i] = Color(c[i].r * k, c[i].g * k, c[i].b * k, c[i].a)
	_sv = v
	_sn = n
	_sc = c

## Corta por el plano y = `h` las paredes (normal casi horizontal) que lo
## cruzan (de tres en tres), interpolando normal y color. Cada trozo se abre en abanico desde su primer
## vertice: el orden de cara se conserva.
static func _split_at(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, h: float) -> Array:
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var oc := PackedColorArray()
	var i := 0
	while i + 2 < v.size():
		var below := 0
		for k in 3:
			if v[i + k].y < h:
				below += 1
		var wall := absf((n[i] + n[i + 1] + n[i + 2]).normalized().y) < 0.6
		if below == 0 or below == 3 or not wall:
			for k in 3:
				ov.append(v[i + k]); on.append(n[i + k]); oc.append(c[i + k])
			i += 3
			continue
		for side in [true, false]:
			var pv := PackedVector3Array()
			var pn := PackedVector3Array()
			var pc := PackedColorArray()
			for k in 3:
				var a := i + k
				var b := i + (k + 1) % 3
				var a_in: bool = (v[a].y < h) == side
				var b_in: bool = (v[b].y < h) == side
				if a_in:
					pv.append(v[a]); pn.append(n[a]); pc.append(c[a])
				if a_in != b_in:
					var t := (h - v[a].y) / (v[b].y - v[a].y)
					pv.append(v[a].lerp(v[b], t))
					pn.append(n[a].lerp(n[b], t).normalized())
					pc.append(c[a].lerp(c[b], t))
			for k in range(1, pv.size() - 1):
				ov.append(pv[0]); on.append(pn[0]); oc.append(pc[0])
				ov.append(pv[k]); on.append(pn[k]); oc.append(pc[k])
				ov.append(pv[k + 1]); on.append(pn[k + 1]); oc.append(pc[k + 1])
		i += 3
	return [ov, on, oc]

# ── Primitivas ───────────────────────────────────────────────────────

## Caja centrada en `c`. Sin la cara de abajo (nunca se ve), salvo `bottom`.
func box(c: Vector3, size: Vector3, col: Color, glow := false, bottom := false) -> void:
	var h := size * 0.5
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
		c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	_quad(p[4], p[5], p[6], p[7], Vector3.UP, col.lightened(0.06), glow)
	_quad(p[3], p[2], p[6], p[7], Vector3.BACK, col, glow)
	_quad(p[0], p[1], p[5], p[4], Vector3.FORWARD, col.darkened(0.12), glow)
	_quad(p[1], p[2], p[6], p[5], Vector3.RIGHT, col.darkened(0.05), glow)
	_quad(p[0], p[3], p[7], p[4], Vector3.LEFT, col.darkened(0.08), glow)
	if bottom:
		_quad(p[0], p[1], p[2], p[3], Vector3.DOWN, col.darkened(0.3), glow)

## Cilindro (o cono con `top_r`) de `height` con la base en `base`, a lo largo
## de `axis` (normalizado). Con tapa arriba; abajo solo si `caps_both`.
func cyl(base: Vector3, radius: float, height: float, col: Color, sides := 8, axis := Vector3.UP, top_r := -1.0, glow := false, caps_both := false) -> void:
	if top_r < 0.0:
		top_r = radius
	axis = axis.normalized()
	var u := axis.cross(Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u).normalized()
	var top := base + axis * height
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var n := (d0 + d1).normalized()
		_quad(base + d0 * radius, base + d1 * radius, top + d1 * top_r, top + d0 * top_r, n, col, glow)
		if top_r > 0.001:
			_tri(top, top + d0 * top_r, top + d1 * top_r, axis, col.lightened(0.08), glow)
		if caps_both:
			_tri(base, base + d1 * radius, base + d0 * radius, -axis, col.darkened(0.15), glow)

## Bola low-poly (6 x 4), aplastada con `squash`.
func ball(c: Vector3, radius: float, col: Color, squash := Vector3.ONE, glow := false) -> void:
	var rings := 4
	var segs := 6
	for j in rings:
		var t0 := PI * float(j) / float(rings) - PI * 0.5
		var t1 := PI * float(j + 1) / float(rings) - PI * 0.5
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var p00 := _sph(a0, t0)
			var p10 := _sph(a1, t0)
			var p11 := _sph(a1, t1)
			var p01 := _sph(a0, t1)
			var n := (p00 + p10 + p11 + p01).normalized()
			var shade := col.darkened(0.15 * (1.0 - float(j) / float(rings - 1)))
			_quad(c + p00 * radius * squash, c + p10 * radius * squash, c + p11 * radius * squash, c + p01 * radius * squash, n, shade, glow)

static func _sph(a: float, t: float) -> Vector3:
	return Vector3(cos(t) * cos(a), sin(t), cos(t) * sin(a))

## Cuadro plano horizontal (marcas en el suelo).
func flat(c: Vector3, size: Vector2, col: Color, glow := false) -> void:
	var h := size * 0.5
	_quad(c + Vector3(-h.x, 0, -h.y), c + Vector3(h.x, 0, -h.y), c + Vector3(h.x, 0, h.y), c + Vector3(-h.x, 0, h.y), Vector3.UP, col, glow)

## Viga entre dos puntos (seccion cuadrada `w`).
func beam(a: Vector3, b: Vector3, w: float, col: Color, glow := false) -> void:
	var d := b - a
	var dist := d.length()
	if dist < 0.0001:
		return
	var saved := xf
	var fwd := d / dist
	var up := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := up.cross(fwd).normalized()
	var y := fwd.cross(x).normalized()
	xf = xf * Transform3D(Basis(x, y, fwd), (a + b) * 0.5)
	box(Vector3.ZERO, Vector3(w, w, dist), col, glow, true)
	xf = saved
