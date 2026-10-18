extends RefCounted
## Piezas de las unidades de juguete del tablero 3D (tools/build_toy_models.gd
## -- --units). Mismo vocabulario que las de los edificios (_parts.gd): volumenes
## gruesos, la paleta comun y pocos triangulos. Lo que lleva el color del bando
## va en el LotMesh `team`, pintado en GRISES (`T()`): el horneado lo multiplica
## por el color de la colonia (jugador) o por el morado de la Regencia.
##
## Marco de la unidad: centro en el origen, suelo en y = 0, frente hacia +Z.
## Presupuesto: <= 800 triangulos por unidad (lo imprime el horneador).

const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

## Gris de equipo: 1.0 es el color del bando tal cual, menos lo oscurece.
static func T(d := 0.0) -> Color:
	return Color(1, 1, 1).darkened(d)

static func skin() -> Color:
	return P.C(S.CREAM, -0.08)

## La peana de juguete: redonda la del jugador, en rombo la de la Regencia. El
## bando se lee por la FORMA, no solo por el color (como las marcas del tablero
## 2D: circulo los nuestros, rombo los suyos). El canto lleva el color del bando.
static func stand(mk, team, side: String, r: float) -> void:
	if side == "regency":
		# Cuatro lados con las esquinas en los ejes: un rombo visto desde la camara.
		mk.cyl(Vector3.ZERO, r * 1.12, 0.07, P.C(S.IRON, 0.05), 4)
		team.cyl(Vector3(0, 0.07, 0), r * 1.04, 0.04, T(0.1), 4)
	else:
		mk.cyl(Vector3.ZERO, r, 0.07, P.C(S.IRON, 0.05), 12)
		team.cyl(Vector3(0, 0.07, 0), r * 0.93, 0.04, T(0.1), 12)

## Un soldadito de plomo: botas, guerrera del bando, cinturon, brazos, cabeza y
## tocado. `side` "player": casco de plato y mochila; "regency": el recaudador,
## levita larga y chacó alto con placa de laton. `rifle`: fusil al frente.
## ~150 triangulos.
static func soldier(mk, team, pos: Vector3, rot_deg: float, side: String, rifle := true, s := 1.0) -> void:
	var xf := P.xf_at(pos, rot_deg, Vector3(s, s, s))
	var a := P.push(mk, xf)
	var b := P.push(team, xf)
	var boots := P.C(S.IRON, 0.08)
	# Piernas
	for sx in [-0.075, 0.075]:
		P.block(mk, Vector3(sx, 0, 0), Vector3(0.11, 0.3, 0.13), boots)
	if side == "regency":
		# Levita hasta la rodilla
		P.block(team, Vector3(0, 0.18, -0.01), Vector3(0.34, 0.42, 0.22), T(0.0))
	else:
		P.block(team, Vector3(0, 0.29, 0), Vector3(0.32, 0.31, 0.2), T(0.0))
	# Cinturon
	mk.box(Vector3(0, 0.36, 0), Vector3(0.35, 0.05, 0.23), P.wood(-0.15) if side != "regency" else P.C(S.BRASS, -0.05))
	# Brazos, hacia delante sujetando el arma
	for sx in [-0.2, 0.2]:
		team.beam(Vector3(sx, 0.56, 0.0), Vector3(sx * 0.6, 0.42, 0.16), 0.09, T(0.12))
	# Cabeza
	mk.cyl(Vector3(0, 0.6, 0), 0.085, 0.15, skin(), 6)
	if side == "regency":
		# Chaco alto del bando, visera y placa de laton
		team.cyl(Vector3(0, 0.73, 0), 0.1, 0.2, T(0.2), 8, Vector3.UP, 0.11)
		mk.box(Vector3(0, 0.82, 0.1), Vector3(0.09, 0.09, 0.02), P.C(S.BRASS, 0.05))
		mk.box(Vector3(0, 0.74, 0.1), Vector3(0.18, 0.025, 0.08), P.C(S.IRON))
	else:
		# Casco de plato (ala ancha y copa baja)
		mk.cyl(Vector3(0, 0.73, 0), 0.17, 0.03, P.C(S.SLATE, -0.05), 8)
		mk.cyl(Vector3(0, 0.75, 0), 0.105, 0.07, P.C(S.SLATE, 0.0), 8, Vector3.UP, 0.06)
		# Mochila
		P.block(mk, Vector3(0, 0.3, -0.15), Vector3(0.22, 0.22, 0.09), P.wood(-0.05))
	if rifle:
		var stock := Vector3(0.05, 0.4, 0.06)
		var muzzle := Vector3(0.05, 0.5, 0.5)
		mk.beam(stock, stock.lerp(muzzle, 0.45), 0.06, P.wood(0.0))
		mk.beam(stock.lerp(muzzle, 0.4), muzzle, 0.035, P.iron(0.1))
	P.pop(mk, a)
	P.pop(team, b)

## Rueda maciza de canon o camion: disco con buje, de cara a `axis`.
## ~60 triangulos.
static func wheel_disc(mk, c: Vector3, r: float, w: float, col: Color, axis := Vector3.RIGHT) -> void:
	mk.cyl(c - axis * w * 0.5, r, w, col, 10, axis, -1.0, false, true)
	mk.cyl(c + axis * w * 0.5, r * 0.35, 0.04, P.C(S.BRASS, -0.1), 6, axis)

# ── Mar y aire (1.1, feat/aire-mar-vista) ─────────────────────────────
#
# Las piezas de mar llevan la linea de flotacion en y = 0.08 (la vista las
# baja a la lamina de agua, BoardLayout3D.DOMAIN_HEIGHT["sea"]): lo de debajo
# queda bajo el agua. Las de aire se montan desde AIR_Y para arriba: la vista
# ya las sube a su altura y les pone la sombra en el suelo, y asi el
# oscurecimiento de contacto del horneado (lo que queda por debajo de 0.22) no
# les ensucia las alas.

const WATERLINE := 0.08
const AIR_Y := 0.3

## Una cara plana (3 o mas puntos en orden, convexa) con la normal hacia fuera
## de `center`. LotMesh ya da la vuelta al triangulo si llega al reves.
static func face(mk, pts: Array, center: Vector3, col: Color) -> void:
	var a: Vector3 = pts[0]
	var n: Vector3 = (pts[1] - a).cross(pts[2] - a)
	if n.length() < 0.000001:
		return
	n = n.normalized()
	var mid := Vector3.ZERO
	for p in pts:
		mid += p
	mid /= float(pts.size())
	if n.dot(mid - center) < 0.0:
		n = -n
	for i in range(1, pts.size() - 1):
		mk._tri(a, pts[i], pts[i + 1], n, col, false)

## Prisma entre dos contornos del mismo numero de puntos (`lo` abajo, `hi`
## arriba): solo los costados. 2 triangulos por lado.
static func loft(mk, lo: Array, hi: Array, center: Vector3, col: Color, shade := true) -> void:
	var n := lo.size()
	for i in n:
		var j := (i + 1) % n
		var c := col
		if shade:
			# Luz de juguete: lo que mira atras (-Z) y a la derecha, mas oscuro.
			var side: Vector3 = ((lo[i] + lo[j]) * 0.5 - center)
			c = col.darkened(0.1 if side.z < -0.05 else (0.04 if side.x > 0.05 else 0.0))
		face(mk, [lo[i], lo[j], hi[j], hi[i]], center, c)

## Contorno de un casco visto desde arriba a la altura `y`: popa recta, costados
## y proa en punta (5 puntos). `l` eslora, `w` manga, `bow` lo que mide la proa.
static func hull_ring(l: float, w: float, y: float, bow: float, z0 := 0.0) -> Array:
	var hl := l * 0.5
	var hw := w * 0.5
	return [Vector3(-hw, y, z0 - hl), Vector3(hw, y, z0 - hl), Vector3(hw, y, z0 + hl - bow),
		Vector3(0, y, z0 + hl), Vector3(-hw, y, z0 + hl - bow)]

## Un casco de juguete: obra viva oscura (de la quilla a la flotacion, casi
## toda bajo el agua), obra muerta del color del bando hasta la cubierta y la
## cubierta de tablas. La proa sube un poco (arrufo). ~40 triangulos.
static func hull(mk, team, l: float, w: float, h: float, deck_col: Color, z0 := 0.0) -> float:
	var bow := w * 0.85
	var keel := hull_ring(l * 0.86, w * 0.5, 0.0, bow * 0.6, z0 - l * 0.02)
	var water := hull_ring(l * 0.97, w * 0.92, WATERLINE + 0.04, bow * 0.95, z0)
	var deck := hull_ring(l, w, h, bow, z0)
	deck[3] = deck[3] + Vector3(0, 0.06, 0.02)
	var center := Vector3(0, h * 0.5, z0)
	loft(mk, keel, water, center, P.C(S.IRON, 0.02))
	loft(team, water, deck, center, T(0.06))
	face(mk, deck, center + Vector3(0, -1, 0), deck_col)
	return h

## La peana de un barco: una mancha de espuma del agua (la estela, abierta en V
## por la popa) con el canto del color del bando, redonda los nuestros y en
## rombo la Regencia, como las peanas de tierra. ~70 triangulos.
static func sea_stand(mk, team, side: String, r: float, l: float) -> void:
	var foam := P.C(S.CREAM, 0.08)
	var sides := 4 if side == "regency" else 12
	var saved := P.push(mk, Transform3D(Basis.from_scale(Vector3(0.62, 1.0, 1.0)), Vector3.ZERO))
	mk.cyl(Vector3(0, WATERLINE - 0.02, 0), r, 0.03, foam, sides)
	P.pop(mk, saved)
	saved = P.push(team, Transform3D(Basis.from_scale(Vector3(0.62, 1.0, 1.0)), Vector3.ZERO))
	team.cyl(Vector3(0, WATERLINE + 0.01, 0), r * 0.9, 0.025, T(0.1), sides)
	P.pop(team, saved)
	# La estela: dos lenguas de espuma que se abren detras de la popa.
	for sx in [-1.0, 1.0]:
		mk.beam(Vector3(sx * 0.12, WATERLINE, -l * 0.42), Vector3(sx * 0.42, WATERLINE - 0.01, -l * 0.5 - 0.35), 0.07, foam.darkened(0.04))

## Chimenea de barco con su aro (laton los nuestros, morado... la Regencia lo
## lleva en laton tambien, con la boca roja de su caldera).
static func funnel(mk, base: Vector3, r: float, h: float, band: Color, rake := 0.0) -> void:
	var top := base + Vector3(0, h, -rake)
	mk.cyl(base, r, base.distance_to(top), P.C(S.SLATE, -0.12), 8, (top - base).normalized())
	mk.cyl(top - (top - base).normalized() * 0.08, r * 1.08, 0.08, band, 8, (top - base).normalized())

## Torreta con canones: cuerpo cilindrico, frente plano del color del bando y
## `guns` tubos hacia +Z (o -Z con `back`). Devuelve la boca del primer tubo.
static func turret(mk, team, c: Vector3, r: float, guns: int, gun_len: float, gun_r: float, back := false) -> Vector3:
	var dir := Vector3.BACK * (-1.0 if back else 1.0)
	mk.cyl(c, r, r * 0.6, P.C(S.SLATE, 0.04), 8)
	team.box(c + Vector3(0, r * 0.62, 0), Vector3(r * 1.1, 0.04, r * 1.1), T(0.18))
	var muzzle := Vector3.ZERO
	for g in guns:
		var x := (float(g) - float(guns - 1) * 0.5) * gun_r * 2.6
		var b0 := c + Vector3(x, r * 0.32, 0) + dir * r * 0.7
		mk.cyl(b0, gun_r, gun_len, P.iron(0.08), 6, dir)
		if g == 0:
			muzzle = b0 + dir * gun_len
	return muzzle

## Helice de dos palas en cruz con su buje, de cara a `axis` (+Z por defecto).
## ~30 triangulos.
static func prop(mk, c: Vector3, r: float, axis := Vector3.BACK) -> void:
	mk.cyl(c - axis * 0.04, r * 0.22, 0.1, P.C(S.BRASS, 0.05), 6, axis, r * 0.08)
	var u := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var v := axis.cross(u).normalized()
	mk.beam(c - u * r, c + u * r, 0.05, P.wood(-0.1))
	mk.beam(c - v * r * 0.9, c + v * r * 0.9, 0.05, P.wood(-0.12))

## Elipsoide a lo largo de Z (la envuelta del dirigible, la cabina de un
## avion): `segs` x `rings`, radios `rx`, `ry` y `rz`. 2*segs*(rings-1) tris.
static func ellipsoid(mk, c: Vector3, rx: float, ry: float, rz: float, col: Color, segs := 10, rings := 6) -> void:
	for j in rings:
		var t0 := PI * float(j) / float(rings)
		var t1 := PI * float(j + 1) / float(rings)
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var p00 := _ell(a0, t0, rx, ry, rz)
			var p10 := _ell(a1, t0, rx, ry, rz)
			var p11 := _ell(a1, t1, rx, ry, rz)
			var p01 := _ell(a0, t1, rx, ry, rz)
			var n := (p00 + p10 + p11 + p01).normalized()
			# Arriba algo mas claro, la panza mas oscura: se lee el volumen.
			var shade := col.darkened(0.16 * clampf(-n.y, 0.0, 1.0)).lightened(0.06 * clampf(n.y, 0.0, 1.0))
			if j == 0:
				mk._tri(c + p00, c + p11, c + p01, n, shade, false)
			elif j == rings - 1:
				mk._tri(c + p00, c + p10, c + p11, n, shade, false)
			else:
				mk._quad(c + p00, c + p10, c + p11, c + p01, n, shade, false)

## Punto de un elipsoide: `t` va de la proa (+Z, 0) a la popa (-Z, PI).
static func _ell(a: float, t: float, rx: float, ry: float, rz: float) -> Vector3:
	return Vector3(sin(t) * cos(a) * rx, sin(t) * sin(a) * ry, cos(t) * rz)

## Escarapela plana (el redondel de un ala): disco del bando con un centro de
## laton, encima de una superficie a la altura `c.y`.
static func roundel(mk, team, c: Vector3, r: float) -> void:
	team.cyl(c, r, 0.012, T(0.0), 8)
	mk.cyl(c, r * 0.42, 0.018, P.C(S.CREAM, 0.05), 6)
