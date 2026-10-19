extends RefCounted
## Cuartel General (militar, acento amarillo y negro, el remate del juego):
## palacio de dos plantas con alas, porche de columnas y una torre central de
## tejado plano (ahi pone la parcela el emblema de la Regencia). Exagerado: la
## torre central y los dos estandartes amarillos y negros de la fachada.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var yellow := P.C(S.BRASS, 0.05)
	var wall := P.C(S.CREAM, -0.04)
	var stone := P.C(S.STONE, -0.05)
	var c := Vector3(0, 0, -0.3)
	var w := 2.8
	var d := 1.8
	var fz := c.z + d * 0.5
	P.block(mk, c, Vector3(w, 0.22, d), P.C(S.STONE, -0.18))
	# Cuerpo de dos plantas
	P.block(mk, c + Vector3(0, 0.22, 0), Vector3(w - 0.1, 1.5, d - 0.1), wall)
	mk.box(c + Vector3(0, 0.95, 0), Vector3(w - 0.04, 0.08, d - 0.04), stone)
	P.flat_roof(mk, c + Vector3(0, 1.72, 0), w - 0.02, d - 0.02, P.C(S.SLATE, -0.04))
	P.hazard(mk, Vector3(0, 1.68, fz - 0.02), w - 0.06, 0.1, 0.04, 14)
	# Ventanas encendidas: dos filas a cada lado del porche
	for x in [-1.18, -0.62, 0.62, 1.18]:
		for y in [0.58, 1.3]:
			P.window(mk, Vector3(x, y, fz - 0.05), Vector3.BACK, 0.22, 0.3, stone.darkened(0.1))
	# Torre central (exagerada), tejado plano para el emblema
	var tc := Vector3(0, 1.82, -0.4)
	P.block(mk, tc, Vector3(1.0, 1.05, 0.9), wall.lightened(0.04))
	mk.box(tc + Vector3(0, 1.08, 0), Vector3(1.12, 0.1, 1.02), stone.darkened(0.1))
	P.hazard(mk, tc + Vector3(0, 0.95, 0.46), 1.0, 0.1, 0.03, 8)
	# Emblema de la Regencia en la fachada de la torre: rueda dentada de laton,
	# disco rojo y el rayo de la Tormenta en amarillo.
	var em := tc + Vector3(0, 0.5, 0.47)
	P.gear(mk, em, 0.34, 0.08, P.C(S.BRASS, 0.05), Vector3.BACK, 10)
	mk.cyl(em + Vector3(0, 0, 0.04), 0.24, 0.03, P.C(S.RED), 12, Vector3.BACK)
	mk.beam(em + Vector3(0.07, 0.16, 0.08), em + Vector3(-0.06, -0.01, 0.08), 0.07, yellow)
	mk.beam(em + Vector3(-0.06, -0.01, 0.08), em + Vector3(0.06, 0.01, 0.08), 0.07, yellow)
	mk.beam(em + Vector3(0.06, 0.01, 0.08), em + Vector3(-0.07, -0.17, 0.08), 0.07, yellow)
	# Chimeneas detras (de ahi el humo)
	var mouth := P.chimney(mk, c + Vector3(-1.0, 1.72, -0.5), 0.24, 0.6, stone.darkened(0.15), P.iron())
	P.chimney(mk, c + Vector3(1.0, 1.72, -0.5), 0.24, 0.6, stone.darkened(0.15), P.iron())
	# Porche de columnas con cornisa a franjas y escalinata
	var pz := fz + 0.25
	P.block(mk, Vector3(0, 0, pz - 0.05), Vector3(1.05, 0.22, 0.6), stone)
	P.block(mk, Vector3(0, 0, pz + 0.36), Vector3(0.9, 0.11, 0.22), stone.lightened(0.05))
	for x in [-0.4, -0.13, 0.13, 0.4]:
		mk.cyl(Vector3(x, 0.22, pz + 0.12), 0.07, 0.95, stone.lightened(0.1), 8)
	mk.box(Vector3(0, 1.22, pz - 0.05), Vector3(1.1, 0.14, 0.6), stone.lightened(0.04))
	P.hazard(mk, Vector3(0, 1.22, pz + 0.26), 1.08, 0.1, 0.02, 7)
	P.door(mk, Vector3(0, 0.22, fz - 0.05), Vector3.BACK, 0.42, 0.75, P.C(S.SLATE, 0.0), yellow)
	# Estandartes (exagerados) entre las ventanas, del alero casi al zocalo
	for sx in [-1.0, 1.0]:
		var bx: float = sx * 0.9
		mk.box(Vector3(bx, 1.62, fz + 0.03), Vector3(0.34, 0.08, 0.1), P.iron())
		mk.box(Vector3(bx, 1.07, fz + 0.04), Vector3(0.26, 1.05, 0.03), yellow)
		mk.box(Vector3(bx, 1.3, fz + 0.06), Vector3(0.26, 0.14, 0.02), P.iron())
		mk.box(Vector3(bx, 0.62, fz + 0.06), Vector3(0.26, 0.08, 0.02), P.iron())
		mk._tri(Vector3(bx - 0.13, 0.545, fz + 0.04), Vector3(bx + 0.13, 0.545, fz + 0.04), Vector3(bx, 0.42, fz + 0.04), Vector3.BACK, yellow, false)
	# Sin mastil ni bandera del pais (Bryan, 2026-10-18): la bandera va en el
	# Nucleo y en los Cuarteles. El remate del CG es su torre y el emblema.
	return {"fx": mouth}
