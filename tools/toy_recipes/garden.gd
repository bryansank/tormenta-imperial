extends RefCounted
## Jardin (residencial, acento verde): cuatro parterres con seto y flores, paseo
## en cruz de losas y, en el centro, el arco de hierro con enredadera.
## Exagerado: el arbol recortado en bolas del centro, bajo el arco.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var green := P.C(S.GREEN, -0.05)
	var hedge := P.C(S.GREEN, -0.18)
	var stone := P.C(S.STONE, 0.02)
	var h := minf(float(ctx["w"]), float(ctx["d"])) * 0.5 - 0.05
	# Paseo en cruz
	P.block(mk, Vector3.ZERO, Vector3(h * 2.0, 0.04, 0.5), stone)
	P.block(mk, Vector3.ZERO, Vector3(0.5, 0.04, h * 2.0), stone)
	# Parterres: seto bajo en L, cesped y flores
	var flowers := [S.RED, S.BRASS, S.CREAM, S.TERRACOTTA]
	var q := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var pc := Vector3(sx * (h + 0.25) * 0.5, 0, sz * (h + 0.25) * 0.5)
			var s := h - 0.3
			P.block(mk, pc, Vector3(s, 0.08, s), green)
			P.block(mk, pc + Vector3(sx * s * 0.5 - sx * 0.08, 0, 0), Vector3(0.16, 0.3, s), hedge)
			P.block(mk, pc + Vector3(0, 0, sz * s * 0.5 - sz * 0.08), Vector3(s, 0.3, 0.16), hedge)
			for k in 5:
				var fx := pc + Vector3(-sx * (0.12 + (k % 3) * 0.2), 0.14, -sz * (0.12 + (k / 3) * 0.25 + (k % 2) * 0.1))
				mk.ball(fx, 0.08, P.C(flowers[(q + k) % flowers.size()], 0.08))
			q += 1
	# Dos arbolitos CC0 en las esquinas de atras
	kit.put(mk, "kk:tree_single_B", Vector3(-h + 0.35, 0, -h + 0.35), 0.6, 15.0, {"noglow": true})
	kit.put(mk, "kk:tree_single_B", Vector3(h - 0.35, 0, -h + 0.35), 0.55, 70.0, {"noglow": true})
	# Arbol recortado en bolas (exagerado), en su maceta
	mk.cyl(Vector3.ZERO, 0.3, 0.3, P.C(S.TERRACOTTA, -0.05), 8, Vector3.UP, 0.36)
	mk.cyl(Vector3(0, 0.3, 0), 0.05, 1.3, P.wood(-0.15), 6)
	mk.ball(Vector3(0, 0.75, 0), 0.26, green.lightened(0.04))
	mk.ball(Vector3(0, 1.25, 0), 0.36, green)
	mk.ball(Vector3(0, 1.7, 0), 0.24, green.lightened(0.06))
	# Arco de hierro con enredadera por encima del paseo
	for sz in [-1.0, 1.0]:
		var bz: float = sz * 0.85
		for sx in [-1.0, 1.0]:
			mk.box(Vector3(sx * 0.32, 0.8, bz), Vector3(0.06, 1.6, 0.06), P.iron(0.1))
		mk.beam(Vector3(-0.32, 1.6, bz), Vector3(0, 1.85, bz), 0.06, P.iron(0.1))
		mk.beam(Vector3(0, 1.85, bz), Vector3(0.32, 1.6, bz), 0.06, P.iron(0.1))
		for k in 4:
			mk.ball(Vector3(-0.32 + k * 0.21, 1.62 + (0.2 if k == 1 or k == 2 else 0.0), bz), 0.1, green.lightened(0.05))
	kit.put(mk, "kc:bench", Vector3(0.55, 0, 0.45), 0.42, 90.0)
	return {}
