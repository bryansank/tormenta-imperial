extends RefCounted
## Campo de tiro (militar, 1.2, feat/edificios-militares). Una calle de tierra
## apisonada con sus rayas de distancia. Al fondo, el talud de tierra con
## hierba y tres DIANAS grandes en sus postes (lo exagerado: rojo y crema que
## se leen desde lejos; `kk:target` recoloreado). Delante, la linea de tiro de
## sacos terreros, el armero (`kk:weaponrack`), una caja larga de municion
## (propia, de pizarra) y la caseta del instructor con tejado de una
## sola agua y su banderin amarillo.
## ~1.300 triangulos.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var w := float(ctx.get("w", 2.8))
	var d := float(ctx.get("d", 2.8))
	var hw := w * 0.5
	var hd := d * 0.5
	# ── La calle de tierra y sus rayas ──
	P.block(mk, Vector3.ZERO, Vector3(w, 0.05, d), P.wood(-0.18))
	for k in 3:
		var z := -hd + 0.95 + k * 0.45
		mk.box(Vector3(0.15, 0.06, z), Vector3(w * 0.7, 0.012, 0.05), P.C(S.CREAM, -0.05))
	# ── El talud del fondo con las dianas ──
	P.block(mk, Vector3(0, 0, -hd + 0.25), Vector3(w, 0.5, 0.5), P.C(S.GREEN, -0.22))
	P.block(mk, Vector3(0, 0.5, -hd + 0.18), Vector3(w - 0.1, 0.12, 0.34), P.C(S.GREEN, -0.1))
	for k in 3:
		var x := -hw + 0.55 + k * 0.85
		kit.put(mk, "kk:target", Vector3(x, 0.05, -hd + 0.62), 0.62, 0.0,
			{"noglow": true, "map": {S.TERRACOTTA: S.RED, S.WOOD: S.WOOD}})
	# ── La linea de tiro ──
	P.sandbag_wall(mk, Vector3(-hw + 0.15, 0.05, 0.5), Vector3(0.55, 0.05, 0.5), 2)
	kit.put(mk, "kk:weaponrack", Vector3(-0.9, 0.05, 1.05), 0.46, 0.0, {"noglow": true})
	# Caja larga de municion (propia: la de KayKit pesa 500 triangulos).
	var ammo := Vector3(-0.15, 0.05, 1.05)
	P.block(mk, ammo, Vector3(0.5, 0.16, 0.24), P.C(S.SLATE, -0.05))
	mk.box(ammo + Vector3(0, 0.12, 0), Vector3(0.52, 0.04, 0.26), P.C(S.BRASS, -0.05))
	# ── La caseta del instructor (a la derecha, delante) ──
	var h := Vector3(hw - 0.5, 0.05, 0.75)
	P.block(mk, h, Vector3(0.75, 0.7, 0.7), P.wood(0.02))
	P.shed_roof(mk, h, 0.75, 0.7, 0.92, 0.78, P.C(S.SLATE, 0.02))
	P.window(mk, Vector3(h.x, 0.45, h.z + 0.35), Vector3.BACK, 0.3, 0.18, P.wood(-0.2), true)
	P.flag(mk, h + Vector3(0.3, 0.75, -0.3), 0.7, P.C(S.BRASS, 0.05), P.C(S.IRON, 0.1), Vector2(0.36, 0.24), -1.0)
	return {}
