extends RefCounted
## Nucleo (civico, acento laton, 3x3): la sala de maquinas de la colonia, un
## tambor de enlucido rodeado de columnas bajo una gran cupula de laton con
## linterna, las calderas detras con sus chimeneas (de ahi el humo) y el
## manometro sobre la puerta. Exagerado: la cupula y el manometro.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var brass := P.C(S.BRASS)
	var cream := P.C(S.CREAM, -0.02)
	var stone := P.C(S.STONE, -0.04)
	# Peana escalonada
	P.block(mk, Vector3.ZERO, Vector3(4.6, 0.16, 4.6), P.C(S.STONE, -0.2))
	mk.cyl(Vector3(0, 0.16, 0.2), 1.95, 0.16, stone, 12)
	# Calderas detras, con chimeneas y tuberia al tambor
	var mouth := Vector3.ZERO
	for sx in [-1.0, 1.0]:
		var bc := Vector3(sx * 1.45, 0.16, -1.45)
		P.block(mk, bc, Vector3(1.1, 0.75, 0.9), P.C(S.SLATE, -0.05))
		mk.cyl(bc + Vector3(-0.45, 0.85, 0), 0.38, 0.9, P.C(S.TERRACOTTA, -0.12), 10, Vector3.RIGHT, -1.0, false, true)
		var m := P.stack(mk, bc + Vector3(sx * 0.2, 0.75, -0.15), 0.17, 1.6, P.iron(0.1), brass)
		if sx < 0:
			mouth = m
		P.pipe_run(mk, [bc + Vector3(-sx * 0.55, 0.5, 0.2), bc + Vector3(-sx * 0.75, 0.5, 0.65)], 0.09, brass.darkened(0.2))
	# El tambor con su anillo de columnas
	var dc := Vector3(0, 0.32, 0.2)
	mk.cyl(dc, 1.45, 1.4, cream, 12)
	for k in 12:
		var a := TAU * float(k) / 12.0 + PI / 12.0
		var dir := Vector3(cos(a), 0, sin(a))
		mk.cyl(dc + dir * 1.62, 0.1, 1.4, stone.lightened(0.1), 6)
	mk.cyl(dc + Vector3(0, 1.4, 0), 1.8, 0.18, stone, 12)
	mk.cyl(dc + Vector3(0, 1.58, 0), 1.72, 0.1, brass.darkened(0.2), 12)
	# Ventanas encendidas en el tambor
	for k in 5:
		var a := PI * 0.5 + (float(k) - 2.0) * 0.55
		if k == 2:
			continue
		var dir := Vector3(cos(a), 0, sin(a))
		P.window(mk, dc + dir * 1.44 + Vector3(0, 0.85, 0), dir, 0.28, 0.42, stone.darkened(0.1))
	# La cupula (exagerada): gajos de laton escalonados y nervios oscuros
	var tiers := [[0.0, 1.62], [0.45, 1.5], [0.85, 1.18], [1.15, 0.75], [1.3, 0.3]]
	var y0 := dc.y + 1.68
	for i in tiers.size() - 1:
		mk.cyl(Vector3(0, y0 + float(tiers[i][0]), dc.z), float(tiers[i][1]), float(tiers[i + 1][0]) - float(tiers[i][0]), brass.lightened(0.04 * i), 12, Vector3.UP, float(tiers[i + 1][1]))
	for k in 8:
		var a := TAU * float(k) / 8.0
		var dir := Vector3(cos(a), 0, sin(a))
		for i in tiers.size() - 1:
			mk.beam(Vector3(0, y0 + float(tiers[i][0]), dc.z) + dir * (float(tiers[i][1]) + 0.02), Vector3(0, y0 + float(tiers[i + 1][0]), dc.z) + dir * (float(tiers[i + 1][1]) + 0.02), 0.07, brass.darkened(0.3))
	# Linterna encendida en lo alto
	var lt := Vector3(0, y0 + 1.3, dc.z)
	mk.cyl(lt, 0.26, 0.38, P.C(S.GLOW), 8, Vector3.UP, -1.0, true)
	mk.cyl(lt + Vector3(0, 0.38, 0), 0.34, 0.08, P.iron(), 8)
	mk.cyl(lt + Vector3(0, 0.46, 0), 0.22, 0.25, brass, 8, Vector3.UP, 0.0)
	# Puerta grande con escalinata y el manometro (exagerado) encima
	var fz := dc.z + 1.45
	P.block(mk, Vector3(0, 0, fz + 0.45), Vector3(1.3, 0.24, 0.5), stone)
	P.block(mk, Vector3(0, 0, fz + 0.8), Vector3(1.1, 0.12, 0.3), stone.lightened(0.05))
	P.door(mk, Vector3(0, 0.32, fz - 0.06), Vector3.BACK, 0.7, 0.9, P.C(S.WOOD, -0.2), brass)
	var gc := Vector3(0, 1.75, fz + 0.12)
	mk.cyl(gc - Vector3(0, 0, 0.1), 0.48, 0.12, brass, 12, Vector3.BACK, -1.0, false, true)
	mk.cyl(gc + Vector3(0, 0, 0.02), 0.4, 0.03, P.C(S.CREAM, 0.1), 12, Vector3.BACK)
	mk.beam(gc + Vector3(0, 0, 0.07), gc + Vector3(0.22, 0.24, 0.07), 0.05, P.C(S.RED))
	for k in 5:
		var a := PI * 0.85 - k * PI * 0.17
		mk.box(gc + Vector3(cos(a) * 0.32, sin(a) * 0.32, 0.06), Vector3(0.05, 0.05, 0.02), P.iron())
	# La bandera: en lo alto del mastil de la colonia (ColonyFlag3D, esquina NE,
	# 2,4 por encima de la cima); el mastil no es del modelo.
	return {"fx": mouth, "flag_over_top": Vector3(6.0 * 0.38, 2.4 - 0.05, -6.0 * 0.38)}
