extends RefCounted
## Nucleo (civico, acento laton, 3x3): el corazon de la isla. La sala de
## maquinas de la colonia, ahora MONUMENTAL (2026-10-14, el dueno: "que domine
## la colonia"): sobre una escalinata circular, un tambor alto de enlucido con
## dos pisos de ventanas y su anillo de columnas, una gran cupula de laton con
## linterna y, encima, el MASTIL DE LA BANDERA DEL PAIS (Marker3D "FlagAnchor"
## en lo alto: ColonyFlag3D cuelga la bandera de ahi y no pone mastil propio).
## Detras, las calderas con sus chimeneas altas (de ahi el humo). Ocupa las
## mismas 3x3 casillas: crece hacia arriba, nunca hacia los lados.
##
## Alturas (marco de la receta, suelo en y = 0): escalinata 0,56; tambor hasta
## 2,9; cupula hasta ~5,1; linterna hasta ~6,1; mastil hasta ~8,8. El
## `mesh_height` de data/buildings/nucleo.tres sigue a la cupula.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

## Alto del tambor y de la escalinata.
const DRUM_H := 2.3
const STEP_H := 0.2
## El mastil de la bandera, por encima de la linterna.
const MAST_H := 2.7

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var brass := P.C(S.BRASS)
	var cream := P.C(S.CREAM, -0.02)
	var stone := P.C(S.STONE, -0.04)
	# Peana cuadrada y escalinata circular de dos peldanos
	P.block(mk, Vector3.ZERO, Vector3(4.6, 0.16, 4.6), P.C(S.STONE, -0.2))
	mk.cyl(Vector3(0, 0.16, 0.2), 2.1, STEP_H, stone.darkened(0.04), 14)
	mk.cyl(Vector3(0, 0.16 + STEP_H, 0.2), 1.95, STEP_H, stone, 14)
	# Calderas detras, con chimeneas altas y tuberia al tambor
	var mouth := Vector3.ZERO
	for sx in [-1.0, 1.0]:
		var bc := Vector3(sx * 1.5, 0.16, -1.5)
		P.block(mk, bc, Vector3(1.1, 0.95, 0.9), P.C(S.SLATE, -0.05))
		mk.cyl(bc + Vector3(-0.45, 1.05, 0), 0.38, 0.9, P.C(S.TERRACOTTA, -0.12), 10, Vector3.RIGHT, -1.0, false, true)
		var m := P.stack(mk, bc + Vector3(sx * 0.2, 0.95, -0.15), 0.19, 2.6, P.iron(0.1), brass)
		if sx < 0:
			mouth = m
		P.pipe_run(mk, [bc + Vector3(-sx * 0.55, 0.7, 0.2), bc + Vector3(-sx * 0.75, 0.7, 0.65)], 0.09, brass.darkened(0.2))
	# El tambor alto con su anillo de columnas
	var dc := Vector3(0, 0.16 + STEP_H * 2.0, 0.2)
	mk.cyl(dc, 1.45, DRUM_H, cream, 12)
	# Zocalo y cinturon de piedra a media altura (separa los dos pisos)
	mk.cyl(dc, 1.5, 0.22, stone.darkened(0.06), 12)
	mk.cyl(dc + Vector3(0, DRUM_H * 0.52, 0), 1.52, 0.12, stone.lightened(0.04), 12)
	for k in 12:
		var a := TAU * float(k) / 12.0 + PI / 12.0
		var dir := Vector3(cos(a), 0, sin(a))
		mk.cyl(dc + dir * 1.66, 0.11, DRUM_H, stone.lightened(0.1), 6)
		mk.box(dc + dir * 1.66 + Vector3(0, DRUM_H - 0.05, 0), Vector3(0.3, 0.1, 0.3), stone)
	mk.cyl(dc + Vector3(0, DRUM_H, 0), 1.86, 0.2, stone, 12)
	mk.cyl(dc + Vector3(0, DRUM_H + 0.2, 0), 1.76, 0.12, brass.darkened(0.2), 12)
	# Ventanas encendidas: dos pisos
	for row in 2:
		var wy := 0.75 if row == 0 else DRUM_H * 0.52 + 0.6
		for k in 5:
			var a := PI * 0.5 + (float(k) - 2.0) * 0.55
			# Delante: abajo la puerta, arriba el manometro.
			if k == 2:
				continue
			var dir := Vector3(cos(a), 0, sin(a))
			P.window(mk, dc + dir * 1.44 + Vector3(0, wy, 0), dir, 0.28, 0.44, stone.darkened(0.1))
	# La cupula (exagerada): gajos de laton escalonados y nervios oscuros
	var tiers := [[0.0, 1.66], [0.55, 1.56], [1.05, 1.28], [1.48, 0.86], [1.72, 0.34]]
	var y0 := dc.y + DRUM_H + 0.32
	for i in tiers.size() - 1:
		mk.cyl(Vector3(0, y0 + float(tiers[i][0]), dc.z), float(tiers[i][1]), float(tiers[i + 1][0]) - float(tiers[i][0]), brass.lightened(0.04 * i), 12, Vector3.UP, float(tiers[i + 1][1]))
	for k in 8:
		var a := TAU * float(k) / 8.0
		var dir := Vector3(cos(a), 0, sin(a))
		for i in tiers.size() - 1:
			mk.beam(Vector3(0, y0 + float(tiers[i][0]), dc.z) + dir * (float(tiers[i][1]) + 0.02), Vector3(0, y0 + float(tiers[i + 1][0]), dc.z) + dir * (float(tiers[i + 1][1]) + 0.02), 0.07, brass.darkened(0.3))
	# Linterna encendida en lo alto, con su balconcillo
	var lt := Vector3(0, y0 + 1.72, dc.z)
	mk.cyl(lt, 0.42, 0.08, P.iron(), 10)
	mk.cyl(lt + Vector3(0, 0.08, 0), 0.28, 0.5, P.C(S.GLOW), 8, Vector3.UP, -1.0, true)
	for k in 6:
		var a := TAU * float(k) / 6.0
		mk.box(lt + Vector3(cos(a) * 0.29, 0.33, sin(a) * 0.29), Vector3(0.06, 0.5, 0.06), P.iron())
	mk.cyl(lt + Vector3(0, 0.58, 0), 0.36, 0.08, P.iron(), 8)
	mk.cyl(lt + Vector3(0, 0.66, 0), 0.24, 0.3, brass, 8, Vector3.UP, 0.05)
	# El mastil de la bandera del pais: sale de la punta de la linterna. La
	# bandera la cuelga ColonyFlag3D del FlagAnchor (en lo alto), hacia +X.
	var mast_base := lt + Vector3(0, 0.96, 0)
	mk.cyl(mast_base, 0.08, 0.16, brass.darkened(0.15), 8)
	mk.cyl(mast_base + Vector3(0, 0.16, 0), 0.055, MAST_H, P.iron(0.15), 6, Vector3.UP, 0.04)
	var mast_top := mast_base + Vector3(0, 0.16 + MAST_H, 0)
	mk.ball(mast_top + Vector3(0, 0.06, 0), 0.1, P.C(S.BRASS, 0.08))
	# Puerta grande con escalinata frontal y el manometro (exagerado) encima
	var fz := dc.z + 1.45
	P.block(mk, Vector3(0, 0, fz + 0.75), Vector3(1.5, 0.2, 0.5), stone.darkened(0.04))
	P.block(mk, Vector3(0, 0, fz + 0.45), Vector3(1.4, 0.4, 0.4), stone)
	P.door(mk, dc + Vector3(0, 0.0, 1.45 - 0.06), Vector3.BACK, 0.8, 1.15, P.C(S.WOOD, -0.2), brass)
	var gc := Vector3(0, dc.y + 1.85, fz + 0.12)
	mk.cyl(gc - Vector3(0, 0, 0.1), 0.52, 0.12, brass, 12, Vector3.BACK, -1.0, false, true)
	mk.cyl(gc + Vector3(0, 0, 0.02), 0.44, 0.03, P.C(S.CREAM, 0.1), 12, Vector3.BACK)
	mk.beam(gc + Vector3(0, 0, 0.07), gc + Vector3(0.24, 0.26, 0.07), 0.05, P.C(S.RED))
	for k in 5:
		var a := PI * 0.85 - k * PI * 0.17
		mk.box(gc + Vector3(cos(a) * 0.35, sin(a) * 0.35, 0.06), Vector3(0.05, 0.05, 0.02), P.iron())
	# Faroles a los lados de la puerta
	for sx in [-1.0, 1.0]:
		var lp := Vector3(sx * 0.62, 0.0, fz + 0.62)
		mk.cyl(lp + Vector3(0, 0.4, 0), 0.05, 0.9, P.iron(), 6)
		mk.box(lp + Vector3(0, 1.38, 0), Vector3(0.16, 0.2, 0.16), P.C(S.GLOW), true)
		mk.box(lp + Vector3(0, 1.52, 0), Vector3(0.22, 0.06, 0.22), P.iron())
	return {"fx": mouth, "flag": mast_top}
