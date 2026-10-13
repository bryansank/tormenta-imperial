extends RefCounted
## Mercado (civico, acento laton): la caseta de la lonja atras y puestos con
## toldos a rayas y mercancia a la vista. Exagerado: la gran sombrilla a gajos
## laton y crema en el centro, por encima de los puestos.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var brass := P.C(S.BRASS)
	var cream := P.C(S.CREAM)
	# La lonja: caseta de enlucido con tejado de teja, atras
	var lc := Vector3(0, 0, -0.95)
	P.block(mk, lc, Vector3(2.5, 0.12, 0.85), P.C(S.STONE, -0.1))
	P.block(mk, lc + Vector3(0, 0.12, 0), Vector3(2.3, 0.9, 0.7), cream)
	P.gable(mk, lc + Vector3(0, 1.02, 0), 2.3, 0.7, 0.42, P.C(S.TERRACOTTA), cream)
	for x in [-0.75, 0.0, 0.75]:
		P.window(mk, Vector3(x, 0.62, lc.z + 0.35), Vector3.BACK, 0.4, 0.34, P.wood(-0.15))
	P.awning(mk, Vector3(0, 1.0, lc.z + 0.36), 2.3, 0.4, 0.22, brass, cream, 9)
	# Dos puestos laterales con su toldo y su mercancia
	for side in [-1.0, 1.0]:
		var sc := Vector3(side * 0.85, 0, 0.35)
		P.block(mk, sc + Vector3(0, 0, -0.05), Vector3(0.95, 0.45, 0.45), P.wood(-0.05))
		mk.box(sc + Vector3(0, 0.47, -0.05), Vector3(1.0, 0.05, 0.5), P.wood(0.08))
		for px in [-0.44, 0.44]:
			P.post(mk, sc + Vector3(px, 0, -0.3), 1.15, 0.07, P.wood(-0.2))
		var a := P.C(S.TERRACOTTA) if side < 0 else P.C(S.GREEN, -0.05)
		P.awning(mk, sc + Vector3(0, 1.15, -0.32), 1.05, 0.62, 0.3, a, cream, 5)
		kit.put(mk, "kk:crate_long_A" if side < 0 else "kk:crate_long_B", sc + Vector3(0, 0.5, -0.05), 0.75, 0.0, {"noglow": true})
	# La sombrilla grande (exagerada) sobre una mesa redonda
	var uc := Vector3(0.0, 0, 0.55)
	mk.cyl(uc, 0.32, 0.42, P.wood(-0.05), 8)
	mk.cyl(uc + Vector3(0, 0.42, 0), 0.4, 0.05, P.wood(0.08), 8)
	mk.cyl(uc, 0.045, 1.6, P.iron(0.1), 6)
	P.parasol(mk, uc + Vector3(0, 1.45, 0), 0.82, 0.45, brass, cream, 10)
	kit.put(mk, "kk:crate_open", uc + Vector3(0, 0.47, 0), 0.32, 30.0, {"noglow": true})
	# Sacos y barriles delante
	kit.put(mk, "kk:sack", Vector3(-1.15, 0, 1.05), 0.3, 20.0, {"noglow": true})
	kit.put(mk, "kk:sack", Vector3(-0.85, 0, 1.15), 0.3, -40.0, {"noglow": true})
	kit.put(mk, "kk:barrel", Vector3(1.15, 0, 1.05), 0.3, 0.0, {"noglow": true})
	kit.put(mk, "kk:crate_A_small", Vector3(0.82, 0, 1.12), 0.26, 15.0, {"noglow": true})
	return {}
