extends RefCounted
## Piezas propias de las recetas "maqueta" (tools/build_toy_models.gd): tejados,
## ventanas encendidas, chimeneas, tuberias, valvulas, depositos, toldos, pilas
## de troncos... Todas sobre un LotMesh (`mk`) y con los colores de ToyPalette,
## en el marco del modelo: centro en el origen, suelo en y = 0, frente hacia +Z
## (lo que ve la camara).
##
## Reglas de la guia de estilo que estas piezas ya cumplen: volumenes gruesos
## (nada mas fino de 0.05), pocos detalles que desaparecen al alejar, la luz de
## las ventanas sin sombreado (superficie de brillo).

const Palette := preload("res://scripts/buildings/ToyPalette.gd")
const S := Palette.Slot

# ── Colores ───────────────────────────────────────────────────────────

## Casilla de la paleta con su matiz (-0.25 .. 0.2).
static func C(slot: int, d := 0.0) -> Color:
	return Palette.tint(slot, d)

## La madera de las piezas propias, un pelo mas oscura que la casilla.
static func wood(d := 0.0) -> Color:
	return C(S.WOOD, d - 0.04)

static func iron(d := 0.0) -> Color:
	return C(S.IRON, d)

# ── Transformaciones ──────────────────────────────────────────────────

static func xf_at(pos: Vector3, rot_deg := 0.0, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(rot_deg)) * Basis.from_scale(scale), pos)

## Pone `xf` encima de la de mk y devuelve la anterior (para `pop`).
static func push(mk, xf: Transform3D) -> Transform3D:
	var saved: Transform3D = mk.xf
	mk.xf = saved * xf
	return saved

static func pop(mk, saved: Transform3D) -> void:
	mk.xf = saved

# ── Volumenes ─────────────────────────────────────────────────────────

## Caja apoyada en el suelo (o en `y`), centrada en planta.
static func block(mk, pos: Vector3, size: Vector3, col: Color, glow := false) -> void:
	mk.box(pos + Vector3(0, size.y * 0.5, 0), size, col, glow)

## Zocalo de piedra con su labio: la maqueta apoya en una peana.
static func plinth(mk, w: float, d: float, h := 0.16, col := Color()) -> void:
	if col == Color():
		col = C(S.STONE, -0.08)
	block(mk, Vector3.ZERO, Vector3(w, h, d), col)
	block(mk, Vector3(0, h, 0), Vector3(w - 0.08, 0.03, d - 0.08), col.lightened(0.08))

## Tejado a dos aguas: losas gruesas con alero y los dos piñones rellenos.
## `c`: centro a la altura del alero; `w` a lo largo de la cumbrera (X, o Z con
## `along_z`), `d` de alero a alero; `h` lo que sube la cumbrera.
static func gable(mk, c: Vector3, w: float, d: float, h: float, roof: Color, wall: Color, along_z := false, o := 0.14, t := 0.12) -> void:
	var saved := push(mk, Transform3D(Basis(Vector3.UP, PI * 0.5) if along_z else Basis.IDENTITY, c))
	var hd := d * 0.5
	var a := atan2(h, hd)
	var run := hd + o
	var slab := run / cos(a)
	for side in [1.0, -1.0]:
		var mid_z: float = side * run * 0.5
		var mid_y := h - run * 0.5 * tan(a)
		var n := Vector3(0, cos(a), side * sin(a))
		var b := Basis(Vector3.RIGHT, a * side)
		var s2 := push(mk, Transform3D(b, Vector3(0, mid_y, mid_z) + n * t * 0.5))
		mk.box(Vector3.ZERO, Vector3(w + o * 2.0, t, slab), roof if side > 0 else roof.darkened(0.06), false, true)
		pop(mk, s2)
	# Cumbrera
	mk.box(Vector3(0, h + t * 0.6, 0), Vector3(w + o * 2.0 + 0.02, t * 0.9, t * 1.4), roof.darkened(0.18))
	# Pinones
	for sx in [-1.0, 1.0]:
		var x: float = sx * w * 0.5
		mk._tri(Vector3(x, 0, -hd), Vector3(x, 0, hd), Vector3(x, h, 0), Vector3(sx, 0, 0), wall.darkened(0.04), false)
	pop(mk, saved)

## Tejado de una sola agua: baja de `y_back` (atras, -Z) a `y_front` (+Z).
static func shed_roof(mk, c: Vector3, w: float, d: float, y_back: float, y_front: float, roof: Color, o := 0.14, t := 0.12) -> void:
	var rise := y_back - y_front
	var a := atan2(rise, d)
	var slab := (d + o * 2.0) / cos(a)
	var mid_y := (y_back + y_front) * 0.5
	var n := Vector3(0, cos(a), sin(a))
	var saved := push(mk, Transform3D(Basis(Vector3.RIGHT, a), Vector3(c.x, mid_y, c.z) + n * t * 0.5))
	mk.box(Vector3.ZERO, Vector3(w + o * 2.0, t, slab), roof, false, true)
	pop(mk, saved)

## Tejado plano con peto (lo industrial y lo militar).
static func flat_roof(mk, c: Vector3, w: float, d: float, col: Color, lip := 0.12) -> void:
	mk.box(c + Vector3(0, 0.05, 0), Vector3(w, 0.1, d), col.darkened(0.08))
	for sz in [-1.0, 1.0]:
		mk.box(c + Vector3(0, 0.1 + lip * 0.5, sz * (d * 0.5 - 0.05)), Vector3(w, lip, 0.1), col)
	for sx in [-1.0, 1.0]:
		mk.box(c + Vector3(sx * (w * 0.5 - 0.05), 0.1 + lip * 0.5, 0), Vector3(0.1, lip, d - 0.2), col)

# ── Fachada ───────────────────────────────────────────────────────────

## Ventana en una pared: `pos` es el centro sobre la cara de la pared, `n` la
## normal hacia fuera (eje). Marco grueso, cristal encendido (sin luz) y
## alfeizar. `lit = false`: cristal oscuro.
static func window(mk, pos: Vector3, n: Vector3, w: float, h: float, frame: Color, lit := true) -> void:
	var saved := push(mk, Transform3D(_face_basis(n), pos))
	mk.box(Vector3(0, 0, 0.03), Vector3(w + 0.1, h + 0.1, 0.06), frame)
	mk.box(Vector3(0, 0, 0.065), Vector3(w, h, 0.02), C(S.GLOW) if lit else C(S.SLATE, -0.15), lit)
	mk.box(Vector3(0, 0, 0.08), Vector3(0.05, h, 0.02), frame)
	mk.box(Vector3(0, -h * 0.5 - 0.06, 0.07), Vector3(w + 0.18, 0.06, 0.12), frame.darkened(0.1))
	pop(mk, saved)

## Ventana redonda (ojo de buey): laboratorio, refineria.
static func porthole(mk, pos: Vector3, n: Vector3, r: float, frame: Color, lit := true, glass := -1) -> void:
	var saved := push(mk, Transform3D(_face_basis(n), pos))
	mk.cyl(Vector3.ZERO, r + 0.05, 0.06, frame, 10, Vector3.BACK)
	var gc := C(S.GLOW) if glass < 0 else C(glass, 0.1)
	mk.cyl(Vector3(0, 0, 0.05), r, 0.03, gc if lit else C(S.SLATE, -0.15), 10, Vector3.BACK, -1.0, lit)
	pop(mk, saved)

## Puerta: hoja con marco, `open` la deja abierta (hueco oscuro).
static func door(mk, pos: Vector3, n: Vector3, w: float, h: float, leaf: Color, frame: Color, open := false) -> void:
	var saved := push(mk, Transform3D(_face_basis(n), pos + Vector3(0, h * 0.5, 0)))
	mk.box(Vector3(0, 0.03, 0.02), Vector3(w + 0.12, h + 0.06, 0.05), frame)
	if open:
		mk.box(Vector3(0, 0, 0.04), Vector3(w, h, 0.02), iron(-0.05))
	else:
		mk.box(Vector3(0, 0, 0.05), Vector3(w, h, 0.04), leaf)
		mk.box(Vector3(w * 0.3, 0, 0.08), Vector3(0.05, 0.05, 0.04), C(S.BRASS))
	pop(mk, saved)

## Base que orienta una pieza plana de cara a `n` (su +Z local mira a n).
static func _face_basis(n: Vector3) -> Basis:
	n = n.normalized()
	var x := Vector3.UP.cross(n)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, n.cross(x).normalized(), n)

## Franja de peligro amarilla y negra a lo largo de X (lo militar).
static func hazard(mk, c: Vector3, w: float, h: float, d: float, n := 6) -> void:
	var seg := w / float(n)
	for i in n:
		var col := C(S.BRASS, 0.05) if i % 2 == 0 else iron()
		mk.box(c + Vector3(-w * 0.5 + seg * (i + 0.5), 0, 0), Vector3(seg, h, d), col)

## Toldo a rayas: baja desde `top` (pegado a la pared, +Z hacia fuera) `depth`
## hacia delante y `drop` hacia abajo, con faldon.
static func awning(mk, top: Vector3, w: float, depth: float, drop: float, a: Color, b: Color, stripes := 6) -> void:
	var ang := atan2(drop, depth)
	var slab := sqrt(depth * depth + drop * drop)
	var seg := w / float(stripes)
	var saved := push(mk, Transform3D(Basis(Vector3.RIGHT, ang), top + Vector3(0, -drop * 0.5, depth * 0.5)))
	for i in stripes:
		mk.box(Vector3(-w * 0.5 + seg * (i + 0.5), 0, 0), Vector3(seg, 0.06, slab), a if i % 2 == 0 else b, false, true)
	pop(mk, saved)
	for i in stripes:
		mk.box(top + Vector3(-w * 0.5 + seg * (i + 0.5), -drop - 0.07, depth), Vector3(seg, 0.16, 0.04), a if i % 2 == 0 else b)

# ── Industria ─────────────────────────────────────────────────────────

## Tuberia de `a` a `b` con bridas en los extremos.
static func pipe(mk, a: Vector3, b: Vector3, r: float, col: Color, flanges := true) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.001:
		return
	var ax := d / len
	mk.cyl(a, r, len, col, 8, ax)
	if flanges:
		mk.cyl(a, r * 1.45, 0.06, col.darkened(0.2), 8, ax, -1.0, false, true)
		mk.cyl(b - ax * 0.06, r * 1.45, 0.06, col.darkened(0.2), 8, ax, -1.0, false, true)

## Tuberia en L o en varios tramos (`pts`), con un codo de bola en cada vertice.
static func pipe_run(mk, pts: Array, r: float, col: Color) -> void:
	for i in pts.size() - 1:
		pipe(mk, pts[i], pts[i + 1], r, col, i == 0 or i == pts.size() - 2)
	for i in range(1, pts.size() - 1):
		mk.ball(pts[i], r * 1.15, col)

## Rueda de valvula (o volante): aro de vigas, dos radios y buje, de cara a `n`.
static func valve(mk, c: Vector3, r: float, col: Color, n := Vector3.BACK, w := 0.07) -> void:
	var saved := push(mk, Transform3D(_face_basis(n), c))
	var seg := 10
	for i in seg:
		var a0 := TAU * float(i) / seg
		var a1 := TAU * float(i + 1) / seg
		mk.beam(Vector3(cos(a0), sin(a0), 0) * r, Vector3(cos(a1), sin(a1), 0) * r, w, col)
	mk.beam(Vector3(-r, 0, 0), Vector3(r, 0, 0), w * 0.7, col.darkened(0.1))
	mk.beam(Vector3(0, -r, 0), Vector3(0, r, 0), w * 0.7, col.darkened(0.1))
	mk.cyl(Vector3(0, 0, -0.08), w * 1.3, 0.16, col.darkened(0.25), 8, Vector3.BACK)
	pop(mk, saved)

## Rueda de radios (castillete de la mina, molino): aro, radios, eje a lo largo de `axis`.
static func wheel(mk, c: Vector3, r: float, col: Color, axis := Vector3.RIGHT, spokes := 6, w := 0.08) -> void:
	var saved := push(mk, Transform3D(_face_basis(axis), c))
	var seg := 14
	for i in seg:
		var a0 := TAU * float(i) / seg
		var a1 := TAU * float(i + 1) / seg
		mk.beam(Vector3(cos(a0), sin(a0), 0) * r, Vector3(cos(a1), sin(a1), 0) * r, w, col)
	for i in spokes:
		var a := TAU * float(i) / spokes
		mk.beam(Vector3.ZERO, Vector3(cos(a), sin(a), 0) * r, w * 0.6, col.darkened(0.12))
	mk.cyl(Vector3(0, 0, -0.1), w * 1.4, 0.2, iron(), 8, Vector3.BACK, -1.0, false, true)
	pop(mk, saved)

## Rueda dentada (engranaje): disco con dientes, de cara a `n`.
static func gear(mk, c: Vector3, r: float, thick: float, col: Color, n := Vector3.BACK, teeth := 10) -> void:
	var saved := push(mk, Transform3D(_face_basis(n), c))
	mk.cyl(Vector3(0, 0, -thick * 0.5), r, thick, col, teeth * 2, Vector3.BACK, -1.0, false, true)
	for i in teeth:
		var a := TAU * float(i) / teeth
		var s2 := push(mk, Transform3D(Basis(Vector3.BACK, a), Vector3.ZERO))
		mk.box(Vector3(r + r * 0.12, 0, 0), Vector3(r * 0.26, r * 0.24, thick), col)
		pop(mk, s2)
	mk.cyl(Vector3(0, 0, -thick * 0.5 - 0.01), r * 0.35, thick + 0.02, col.darkened(0.25), 10, Vector3.BACK, -1.0, false, true)
	pop(mk, saved)

## Deposito vertical: cuerpo, cupula, aros y patas cortas.
static func tank(mk, base: Vector3, r: float, h: float, col: Color, band: Color, legs := true) -> void:
	var y0 := 0.18 if legs else 0.0
	if legs:
		for i in 4:
			var a := TAU * float(i) / 4.0 + PI * 0.25
			mk.box(base + Vector3(cos(a) * r * 0.75, 0.09, sin(a) * r * 0.75), Vector3(0.12, 0.18, 0.12), iron())
	mk.cyl(base + Vector3(0, y0, 0), r, h, col, 12)
	mk.ball(base + Vector3(0, y0 + h, 0), r, col.lightened(0.05), Vector3(1, 0.45, 1))
	for t in [0.18, 0.82]:
		mk.cyl(base + Vector3(0, y0 + h * t - 0.05, 0), r + 0.03, 0.1, band, 12)

## Deposito horizontal (cisterna) a lo largo de X sobre dos cunas.
static func drum_tank(mk, c: Vector3, len: float, r: float, col: Color, band: Color) -> void:
	for sx in [-0.3, 0.3]:
		mk.box(c + Vector3(sx * len, r * 0.35, 0), Vector3(0.14, r * 0.7, r * 1.6), iron())
	mk.cyl(c + Vector3(-len * 0.5, r + 0.05, 0), r, len, col, 12, Vector3.RIGHT, -1.0, false, true)
	for sx in [-0.42, 0.0, 0.42]:
		mk.cyl(c + Vector3(sx * len - 0.04, r + 0.05, 0), r + 0.03, 0.08, band, 12, Vector3.RIGHT)

## Chimenea de ladrillo cuadrada con remate y banda de acento. Devuelve la boca.
static func chimney(mk, base: Vector3, s: float, h: float, brick: Color, band: Color) -> Vector3:
	mk.box(base + Vector3(0, h * 0.5, 0), Vector3(s, h, s), brick)
	mk.box(base + Vector3(0, h * 0.72, 0), Vector3(s + 0.04, 0.14, s + 0.04), band)
	mk.box(base + Vector3(0, h + 0.06, 0), Vector3(s + 0.12, 0.12, s + 0.12), brick.darkened(0.25))
	mk.box(base + Vector3(0, h + 0.13, 0), Vector3(s - 0.08, 0.02, s - 0.08), iron(-0.1))
	return base + Vector3(0, h + 0.14, 0)

## Chimenea redonda de chapa con aros (la de las calderas). Devuelve la boca.
static func stack(mk, base: Vector3, r: float, h: float, col: Color, band: Color) -> Vector3:
	mk.cyl(base, r, h, col, 10, Vector3.UP, r * 0.88)
	mk.cyl(base + Vector3(0, h * 0.6, 0), r * 0.98, 0.12, band, 10)
	mk.cyl(base + Vector3(0, h - 0.04, 0), r * 1.12, 0.14, col.darkened(0.3), 10)
	return base + Vector3(0, h + 0.1, 0)

# ── Madera y carga ────────────────────────────────────────────────────

## Tronco tumbado a lo largo de `axis` con las testas claras.
static func trunk(mk, c: Vector3, len: float, r: float, axis := Vector3.RIGHT) -> void:
	axis = axis.normalized()
	mk.cyl(c - axis * len * 0.5, r, len, wood(-0.12), 7, axis)
	for s in [-1.0, 1.0]:
		var p: Vector3 = c + axis * (len * 0.5 * s)
		mk.cyl(p - axis * 0.01 * (1.0 if s < 0 else 0.0), r * 0.82, 0.02, C(S.CREAM, -0.1), 7, axis * s)

## Pila de troncos en piramide (`rows` filas) a lo largo de X.
static func log_pile(mk, c: Vector3, len: float, r: float, rows := 3) -> void:
	for row in rows:
		var n := rows - row
		for i in n:
			var x := (float(i) - float(n - 1) * 0.5) * r * 2.02
			trunk(mk, c + Vector3(0, r + row * r * 1.72, x), len, r, Vector3.RIGHT)

## Pila de tablones a lo largo de X: capas cruzadas.
static func plank_stack(mk, c: Vector3, len: float, w: float, layers := 4) -> void:
	for l in layers:
		for i in 3:
			var z := (float(i) - 1.0) * w * 0.36
			mk.box(c + Vector3(0, 0.05 + l * 0.1, z), Vector3(len, 0.09, w * 0.32), wood(0.08 - 0.04 * (l % 2)))
	mk.box(c + Vector3(len * 0.35, 0.03, 0), Vector3(0.07, 0.06, w * 1.1), wood(-0.2))
	mk.box(c + Vector3(-len * 0.35, 0.03, 0), Vector3(0.07, 0.06, w * 1.1), wood(-0.2))

## Poste vertical (madera o hierro).
static func post(mk, base: Vector3, h: float, s: float, col: Color) -> void:
	mk.box(base + Vector3(0, h * 0.5, 0), Vector3(s, h, s), col)

## Mastil con bandera de dos franjas que ondea hacia `dir` (+X por defecto).
static func flag(mk, base: Vector3, h: float, a: Color, b: Color, size := Vector2(0.7, 0.45), dir := 1.0) -> void:
	mk.cyl(base, 0.045, h, iron(0.1), 6)
	mk.ball(base + Vector3(0, h + 0.05, 0), 0.07, C(S.BRASS))
	var fc := base + Vector3(dir * (size.x * 0.5 + 0.04), h - size.y * 0.5 - 0.05, 0)
	mk.box(fc + Vector3(0, size.y * 0.25, 0), Vector3(size.x, size.y * 0.5, 0.04), a)
	mk.box(fc - Vector3(0, size.y * 0.25, 0), Vector3(size.x, size.y * 0.5, 0.04), b)

## Sombrilla / carpa de gajos alternos (`segs` par): cono de `r` y `h` con la
## base en `c` (el borde) y faldon corto.
static func parasol(mk, c: Vector3, r: float, h: float, a: Color, b: Color, segs := 8) -> void:
	var top := c + Vector3(0, h, 0)
	for i in segs:
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		var p0 := c + Vector3(cos(a0), 0, sin(a0)) * r
		var p1 := c + Vector3(cos(a1), 0, sin(a1)) * r
		var col := a if i % 2 == 0 else b
		var n := (p0 + p1 - c * 2.0).normalized() * h + Vector3(0, r, 0)
		mk._tri(p0, p1, top, n.normalized(), col, false)
		mk._tri(p0, p1, top, -n.normalized(), col.darkened(0.3), false)
		mk._quad(p0, p1, p1 - Vector3(0, 0.12, 0), p0 - Vector3(0, 0.12, 0), (p0 + p1 - c * 2.0).normalized(), col.darkened(0.08), false)
	mk.ball(top, 0.06, C(S.BRASS))

## Saco terrero (caja achatada y redondeada a la vista).
static func sandbag(mk, c: Vector3, rot_deg: float, col: Color) -> void:
	var saved := push(mk, xf_at(c, rot_deg))
	mk.box(Vector3(0, 0.08, 0), Vector3(0.34, 0.16, 0.2), col)
	mk.box(Vector3(0, 0.17, 0), Vector3(0.28, 0.03, 0.15), col.lightened(0.06))
	pop(mk, saved)

## Hilera de sacos de `a` a `b` (en el suelo, o a la altura de `a.y`), `rows` filas.
static func sandbag_wall(mk, a: Vector3, b: Vector3, rows := 2, col := Color()) -> void:
	if col == Color():
		col = C(S.CREAM, -0.18)
	var d := b - a
	d.y = 0.0
	var len := d.length()
	var n := maxi(1, int(len / 0.33))
	var rot := rad_to_deg(atan2(-d.z, d.x))
	for r in rows:
		for i in n:
			var t := (float(i) + 0.5 + (0.5 if r % 2 == 1 else 0.0)) / float(n)
			if t > 1.0:
				continue
			sandbag(mk, a + d * t + Vector3(0, r * 0.17, 0), rot, col.darkened(0.04 * ((i + r) % 2)))

## Aro de vigas horizontal (brocal, barandilla redonda) de radio `r` en `c`.
static func ring(mk, c: Vector3, r: float, w: float, col: Color, segs := 12) -> void:
	for i in segs:
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		mk.beam(c + Vector3(cos(a0), 0, sin(a0)) * r, c + Vector3(cos(a1), 0, sin(a1)) * r, w, col)
