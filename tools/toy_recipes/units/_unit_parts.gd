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
