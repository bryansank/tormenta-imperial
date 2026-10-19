extends RefCounted
## Almacen (civico, acento laton): nave de tablas sobre zocalo de piedra con el
## portalon abierto y cajas dentro y fuera, en un muelle de carga. Exagerado:
## el portalon con su marco de laton, mas de media fachada.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var brass := P.C(S.BRASS)
	var c := Vector3(0, 0, -0.3)
	var w := 2.6
	var d := 1.9
	var fz := c.z + d * 0.5
	P.block(mk, c, Vector3(w, 0.35, d), P.C(S.STONE, -0.08))
	P.block(mk, c + Vector3(0, 0.35, 0), Vector3(w - 0.08, 1.05, d - 0.08), P.wood(-0.02))
	for sx in [-1.0, -0.33, 0.33, 1.0]:
		P.post(mk, c + Vector3(sx * (w * 0.5 - 0.08), 0.35, d * 0.5 - 0.02), 1.05, 0.1, P.wood(-0.2))
	mk.box(c + Vector3(0, 1.4, d * 0.5 - 0.02), Vector3(w, 0.1, 0.08), P.wood(-0.2))
	P.gable(mk, c + Vector3(0, 1.4, 0), w - 0.08, d - 0.08, 0.8, P.C(S.SLATE, 0.04), P.wood(-0.02))
	# El portalon abierto (exagerado), marco de laton, interior oscuro
	var dw := 1.35
	var dh := 1.15
	mk.box(Vector3(0, 0.35 + dh * 0.5, fz + 0.01), Vector3(dw, dh, 0.04), P.iron(-0.08))
	for sx in [-1.0, 1.0]:
		mk.box(Vector3(sx * (dw * 0.5 + 0.06), 0.35 + dh * 0.5, fz + 0.04), Vector3(0.13, dh + 0.1, 0.1), brass)
	mk.box(Vector3(0, 0.35 + dh + 0.06, fz + 0.04), Vector3(dw + 0.25, 0.13, 0.1), brass)
	# La hoja corredera, apartada a un lado
	mk.box(Vector3(dw * 0.5 + 0.42, 0.35 + dh * 0.5, fz + 0.1), Vector3(0.72, dh, 0.06), P.wood(0.05))
	mk.beam(Vector3(dw * 0.5 + 0.08, 0.35 + dh, fz + 0.14), Vector3(dw * 0.5 + 0.76, 0.4, fz + 0.14), 0.05, P.wood(-0.2))
	# Rotulo con farol encima del portalon
	mk.box(Vector3(0, 1.72, fz + 0.06), Vector3(0.7, 0.24, 0.05), brass.darkened(0.15))
	mk.box(Vector3(0, 1.72, fz + 0.09), Vector3(0.5, 0.1, 0.02), P.iron())
	mk.ball(Vector3(0.5, 1.72, fz + 0.12), 0.07, P.C(S.GLOW), Vector3.ONE, true)
	# Muelle de carga delante y cajas dentro (asoman) y fuera
	P.block(mk, Vector3(0, 0, fz + 0.3), Vector3(2.3, 0.3, 0.6), P.C(S.STONE, -0.02))
	kit.put(mk, "kk:crate_A_big", Vector3(-0.3, 0.35, fz - 0.15), 0.42, 10.0, {"noglow": true})
	kit.put(mk, "kk:crate_B_big", Vector3(0.25, 0.35, fz - 0.2), 0.4, -8.0, {"noglow": true})
	kit.put(mk, "kk:crate_A_small", Vector3(-0.25, 0.77, fz - 0.15), 0.3, 30.0, {"noglow": true})
	kit.put(mk, "kk:pallet", Vector3(-0.7, 0.3, fz + 0.3), 0.5, 0.0, {"noglow": true})
	kit.put(mk, "kk:crate_A_big", Vector3(-0.7, 0.37, fz + 0.3), 0.4, 15.0, {"noglow": true})
	kit.put(mk, "kk:crate_B_small", Vector3(0.55, 0.3, fz + 0.32), 0.3, -20.0, {"noglow": true})
	kit.put(mk, "kk:sack", Vector3(0.9, 0.3, fz + 0.3), 0.32, 70.0, {"noglow": true})
	kit.put(mk, "kk:barrel", Vector3(-1.2, 0, fz + 0.32), 0.3, 0.0, {"noglow": true})
	return {}
