extends RefCounted
## Junta piezas low-poly (cajas, cilindros, conos, bolas) en UNA malla con color
## por vertice y, como mucho, dos superficies: "solida" (con luz) y "brillo"
## (sin luz: ventanas, brasas, la luz del laboratorio). La parcela entera de un
## edificio, o su pieza exagerada, es asi una sola llamada de dibujo con dos
## materiales compartidos por todo el mapa: lo que pide el renderizador Mobile.
##
## Las piezas se colocan con `xf` (la transformacion en curso): el atrezo se
## gira, se vuelca o se parte cambiandola, sin repetir la geometria.

static var _mat_solid: StandardMaterial3D = null
static var _mat_glow: StandardMaterial3D = null

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

static func solid_material() -> StandardMaterial3D:
	if _mat_solid == null:
		_mat_solid = StandardMaterial3D.new()
		_mat_solid.vertex_color_use_as_albedo = true
		_mat_solid.roughness = 0.85
		_mat_solid.metallic = 0.1
	return _mat_solid

static func glow_material() -> StandardMaterial3D:
	if _mat_glow == null:
		_mat_glow = StandardMaterial3D.new()
		_mat_glow.vertex_color_use_as_albedo = true
		_mat_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _mat_glow

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
