extends RefCounted
## Granja (residencial, acento verde): surcos de hortalizas y trigo, el granero
## de tablas con tejado verde y puertas en aspa, pacas de heno y el abrevadero.
## Exagerado: el molino de bombeo, una torre de celosia con la rueda de aspas
## mas grande que el granero de ancho.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var green := P.C(S.GREEN, -0.05)
	var soil := P.C(S.WOOD, -0.32)
	var hw := float(ctx["w"]) * 0.5
	var hd := float(ctx["d"]) * 0.5
	# Huerto: surcos delante a la izquierda, mitad hortaliza y mitad trigo
	var fx0 := -hw + 0.1
	var fx1 := 0.15
	for k in 5:
		var z := 0.0 + k * 0.33
		P.block(mk, Vector3((fx0 + fx1) * 0.5, 0, z), Vector3(fx1 - fx0, 0.08, 0.24), soil)
		var n := 6
		for i in n:
			var x := lerpf(fx0 + 0.12, fx1 - 0.12, float(i) / float(n - 1))
			if k < 3:
				mk.ball(Vector3(x, 0.16, z), 0.1, green.lightened(0.04 * (i % 2)), Vector3(1, 0.8, 1))
			else:
				mk.box(Vector3(x, 0.24, z), Vector3(0.12, 0.3, 0.14), P.C(S.BRASS, 0.05 - 0.05 * (i % 2)))
	# Granero atras a la derecha
	var bc := Vector3(0.55, 0, -0.75)
	P.block(mk, bc, Vector3(1.6, 0.1, 1.2), P.C(S.STONE, -0.15))
	P.block(mk, bc + Vector3(0, 0.1, 0), Vector3(1.5, 0.95, 1.1), P.wood(0.0))
	for x in [-0.72, 0.72]:
		P.post(mk, bc + Vector3(x, 0.1, 0.55), 0.95, 0.09, P.C(S.CREAM, -0.05))
	P.gable(mk, bc + Vector3(0, 1.05, 0), 1.1, 1.5, 0.75, P.C(S.GREEN, -0.15), P.wood(0.0), true)
	var fz := bc.z + 0.55
	mk.box(bc + Vector3(0, 0.55, 0.56), Vector3(0.75, 0.85, 0.04), P.wood(-0.15))
	mk.beam(bc + Vector3(-0.35, 0.18, 0.6), bc + Vector3(0.35, 0.92, 0.6), 0.06, P.C(S.CREAM))
	mk.beam(bc + Vector3(0.35, 0.18, 0.6), bc + Vector3(-0.35, 0.92, 0.6), 0.06, P.C(S.CREAM))
	mk.box(bc + Vector3(0, 0.55, 0.585), Vector3(0.8, 0.06, 0.02), P.C(S.CREAM))
	P.window(mk, bc + Vector3(0, 1.35, 0.55), Vector3.BACK, 0.26, 0.22, P.C(S.CREAM, -0.05))
	# Pacas de heno y el abrevadero delante del granero
	for k in 3:
		mk.cyl(Vector3(0.45 + k * 0.38, 0.17, 0.25 + (k % 2) * 0.1), 0.17, 0.32, P.C(S.BRASS, -0.08), 8, Vector3.BACK, -1.0, false, true)
	mk.cyl(Vector3(0.82, 0.5, 0.3), 0.17, 0.32, P.C(S.BRASS, -0.04), 8, Vector3.BACK, -1.0, false, true)
	P.block(mk, Vector3(1.05, 0, 1.05), Vector3(0.8, 0.26, 0.32), P.wood(-0.1))
	mk.box(Vector3(1.05, 0.25, 1.05), Vector3(0.68, 0.03, 0.2), P.C(S.SKY, 0.0))
	# El molino de bombeo (exagerado): torre de celosia, rueda de aspas, cola
	var mc := Vector3(-0.95, 0, -1.0)
	var mh := 2.4
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mk.beam(mc + Vector3(sx * 0.32, 0, sz * 0.32), mc + Vector3(sx * 0.08, mh, sz * 0.08), 0.06, P.iron(0.15))
	for y in [0.6, 1.2, 1.8]:
		var s := lerpf(0.32, 0.08, y / mh)
		mk.box(mc + Vector3(0, y, s), Vector3(s * 2.0, 0.04, 0.04), P.iron(0.15))
		mk.box(mc + Vector3(0, y, -s), Vector3(s * 2.0, 0.04, 0.04), P.iron(0.15))
	var hub := mc + Vector3(0, mh + 0.15, 0.18)
	mk.box(hub + Vector3(0, -0.05, -0.2), Vector3(0.16, 0.16, 0.45), P.iron())
	for k in 12:
		var a := TAU * float(k) / 12.0
		var tip := hub + Vector3(cos(a), sin(a), 0) * 0.68
		mk.beam(hub + Vector3(cos(a), sin(a), 0) * 0.12, tip, 0.05, P.iron(0.2))
		mk.box(hub + Vector3(cos(a), sin(a), 0) * 0.48 + Vector3(0, 0, 0.03), Vector3(0.14, 0.14, 0.02), P.C(S.CREAM, -0.05) if k % 2 == 0 else P.C(S.GREEN, -0.05))
	mk.cyl(hub, 0.1, 0.1, P.C(S.GREEN, -0.1), 8, Vector3.BACK, -1.0, false, true)
	mk.box(hub + Vector3(0, 0.02, -0.65), Vector3(0.04, 0.4, 0.45), P.C(S.GREEN, -0.1))
	# Valla del huerto (CC0) y un saco
	kit.put(mk, "kk:fence_wood_straight", Vector3((fx0 + fx1) * 0.5, 0, -0.27), 1.7, 90.0, {"noglow": true})
	kit.put(mk, "kk:sack", Vector3(0.35, 0, 1.2), 0.3, 30.0, {"noglow": true})
	return {}
