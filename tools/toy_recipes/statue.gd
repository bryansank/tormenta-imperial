extends RefCounted
## Estatua (civica, acento laton): pedestal escalonado de piedra con placa y,
## encima, un ingeniero de bronce con capote y gorra. Exagerado: la rueda
## dentada de laton que levanta con el brazo, mas grande que su cabeza.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var brass := P.C(S.BRASS)
	var bronze := P.C(S.BRASS, -0.22)
	var stone := P.C(S.STONE, 0.0)
	# Pedestal en tres escalones
	P.block(mk, Vector3.ZERO, Vector3(2.2, 0.16, 2.2), P.C(S.STONE, -0.15))
	P.block(mk, Vector3(0, 0.16, 0), Vector3(1.55, 0.3, 1.55), stone)
	P.block(mk, Vector3(0, 0.46, 0), Vector3(1.0, 0.75, 1.0), stone.lightened(0.05))
	P.block(mk, Vector3(0, 1.21, 0), Vector3(1.15, 0.12, 1.15), stone.darkened(0.05))
	mk.box(Vector3(0, 0.85, 0.51), Vector3(0.6, 0.28, 0.04), brass)
	mk.box(Vector3(0, 0.85, 0.535), Vector3(0.44, 0.06, 0.02), P.iron())
	# El ingeniero: botas, piernas, capote, cabeza, gorra
	var b := Vector3(0, 1.33, 0)
	for sx in [-1.0, 1.0]:
		P.block(mk, b + Vector3(sx * 0.13, 0, 0.04), Vector3(0.18, 0.14, 0.26), bronze.darkened(0.15))
		P.block(mk, b + Vector3(sx * 0.13, 0.14, 0), Vector3(0.16, 0.45, 0.18), bronze)
	mk.cyl(b + Vector3(0, 0.45, 0), 0.32, 0.55, bronze.darkened(0.05), 8, Vector3.UP, 0.24)
	P.block(mk, b + Vector3(0, 1.0, 0), Vector3(0.5, 0.18, 0.28), bronze)
	mk.ball(b + Vector3(0, 1.32, 0), 0.17, bronze.lightened(0.04))
	mk.cyl(b + Vector3(0, 1.42, 0), 0.19, 0.06, bronze.darkened(0.2), 8)
	mk.cyl(b + Vector3(0, 1.46, 0), 0.14, 0.1, bronze.darkened(0.1), 8)
	mk.box(b + Vector3(0, 1.42, 0.17), Vector3(0.22, 0.04, 0.12), bronze.darkened(0.2))
	# Brazo izquierdo abajo con una llave inglesa; derecho en alto
	mk.beam(b + Vector3(-0.3, 1.02, 0), b + Vector3(-0.36, 0.6, 0.04), 0.12, bronze)
	mk.beam(b + Vector3(-0.36, 0.6, 0.06), b + Vector3(-0.36, 0.3, 0.12), 0.06, bronze.lightened(0.1))
	mk.beam(b + Vector3(0.3, 1.02, 0), b + Vector3(0.42, 1.6, 0.05), 0.12, bronze)
	# La rueda dentada (exagerada), de cara a la camara
	P.gear(mk, b + Vector3(0.45, 1.98, 0.08), 0.36, 0.1, brass.lightened(0.05), Vector3.BACK, 10)
	# Setos en las esquinas del pedestal
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.put(mk, "kc:bush", Vector3(sx * 0.95, 0.16, sz * 0.95), 0.26, 45.0 * sx)
	return {}
