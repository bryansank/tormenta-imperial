extends RefCounted
## Vivienda (residencial, acento verde): casita de enlucido con tejado de teja,
## ventanas encendidas, puerta y contraventanas verdes, jardincito delante.
## Exagerado: la chimenea de ladrillo, un tercio mas alta de lo que pediria.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var green := P.C(S.GREEN, -0.08)
	var base := Vector3(-0.2, 0.12, -0.3)
	P.block(mk, Vector3(-0.2, 0, -0.3), Vector3(2.25, 0.12, 1.85), P.C(S.STONE, -0.12))
	P.block(mk, base, Vector3(2.0, 1.05, 1.6), P.C(S.CREAM))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			P.post(mk, base + Vector3(sx * 0.97, 0, sz * 0.77), 1.05, 0.12, P.wood(-0.1))
	P.block(mk, base + Vector3(0, 0.98, 0), Vector3(2.04, 0.08, 1.64), P.wood(-0.1))
	# Chimenea (exagerada), por detras de la cumbrera.
	P.chimney(mk, Vector3(0.45, 1.0, -0.72), 0.4, 1.55, P.C(S.TERRACOTTA, -0.14), P.C(S.STONE, 0.05))
	P.gable(mk, base + Vector3(0, 1.05, 0), 2.0, 1.6, 0.85, P.C(S.TERRACOTTA), P.C(S.CREAM))
	var fz := base.z + 0.8
	P.door(mk, Vector3(-0.6, 0.12, fz), Vector3.BACK, 0.42, 0.72, green, P.wood(-0.15))
	for x in [0.15, 0.62]:
		P.window(mk, Vector3(x, 0.75, fz), Vector3.BACK, 0.34, 0.34, P.wood(-0.15))
		for sx in [-1.0, 1.0]:
			mk.box(Vector3(x + sx * 0.25, 0.75, fz + 0.04), Vector3(0.1, 0.42, 0.05), green)
		# Jardinera bajo la ventana
		mk.box(Vector3(x, 0.47, fz + 0.1), Vector3(0.42, 0.1, 0.14), P.wood(-0.05))
		for k in 3:
			mk.ball(Vector3(x - 0.12 + k * 0.12, 0.55, fz + 0.1), 0.065, P.C(S.RED if k % 2 == 0 else S.BRASS, 0.05))
	P.window(mk, Vector3(base.x + 1.0, 0.75, -0.3), Vector3.RIGHT, 0.34, 0.34, P.wood(-0.15))
	P.window(mk, Vector3(base.x - 1.0, 0.75, -0.3), Vector3.LEFT, 0.34, 0.34, P.wood(-0.15))
	# Escalon y camino de losas hasta el borde
	P.block(mk, Vector3(-0.6, 0, fz + 0.14), Vector3(0.6, 0.08, 0.26), P.C(S.STONE))
	for k in 2:
		P.block(mk, Vector3(-0.6 + (k % 2) * 0.08, 0, fz + 0.42 + k * 0.26), Vector3(0.38, 0.03, 0.2), P.C(S.STONE, 0.05))
	# Jardincito: seto y flores a la derecha de la puerta
	P.block(mk, Vector3(0.65, 0, 1.15), Vector3(1.25, 0.26, 0.24), green)
	P.block(mk, Vector3(1.22, 0, 0.8), Vector3(0.24, 0.26, 0.5), green)
	for k in 4:
		mk.ball(Vector3(0.2 + k * 0.28, 0.12, 0.8), 0.09, P.C(S.RED if k % 2 == 0 else S.CREAM, 0.05))
	kit.put(mk, "kc:bush", Vector3(1.2, 0, 0.35), 0.32, 30.0)
	kit.put(mk, "kk:barrel", Vector3(-1.2, 0, 0.7), 0.3, 0.0, {"noglow": true})
	return {}
