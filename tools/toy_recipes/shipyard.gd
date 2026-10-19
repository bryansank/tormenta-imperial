extends RefCounted
## Astillero (militar, mar; 1.1, feat/aire-mar-vista). Va en la costa: la mitad
## de delante (+Z) es su darsena, un vaso de agua entre muelles de piedra con la
## grada que baja al agua y un casco a medio hacer encima (las cuadernas a la
## vista, la quilla en rojo de imprimacion). La mitad de atras, tierra: la nave
## del taller con su chimenea, pilas de chapa y tablones. Lo exagerado: la GRUA
## de portico amarilla que cruza por encima del casco.
##
## Al colocarlo, el lado del agua (+Z del modelo) es el que debe dar al mar: la
## regla "toca la costa" es de la rama de reglas (PlacementRules); el modelo
## solo la dibuja.
##
## Todo propio (LotMesh + _parts), sin piezas CC0. ~1.300 triangulos.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var w := float(ctx.get("w", 2.8))
	var d := float(ctx.get("d", 2.8))
	var hw := w * 0.5
	var hd := d * 0.5
	var stone := P.C(S.STONE, -0.06)
	var yellow := P.C(S.BRASS, 0.05)
	# Tierra de atras: zocalo de piedra
	var land_d := d * 0.46
	P.block(mk, Vector3(0, 0, -hd + land_d * 0.5), Vector3(w, 0.14, land_d), P.C(S.STONE, -0.18))
	# La darsena: muelles a los lados y el agua entre ellos, mas baja
	var dock_z := -hd + land_d
	var dock_d := d - land_d
	var quay := 0.36
	for sx in [-1.0, 1.0]:
		P.block(mk, Vector3(sx * (hw - quay * 0.5), 0, dock_z + dock_d * 0.5), Vector3(quay, 0.14, dock_d), stone)
		# Norays en el canto del muelle
		for k in 2:
			mk.cyl(Vector3(sx * (hw - quay + 0.08), 0.14, dock_z + 0.45 + k * 0.7), 0.05, 0.1, P.iron(0.05), 6)
	var water_w := w - quay * 2.0
	mk.flat(Vector3(0, 0.03, dock_z + dock_d * 0.5), Vector2(water_w, dock_d), P.C(S.SKY, -0.16))
	mk.flat(Vector3(0.2, 0.035, dock_z + dock_d * 0.78), Vector2(0.5, 0.05), P.C(S.SKY, 0.1))
	mk.flat(Vector3(-0.3, 0.035, dock_z + dock_d * 0.6), Vector2(0.4, 0.05), P.C(S.SKY, 0.08))
	# Espuma contra los muelles
	for sx in [-1.0, 1.0]:
		mk.box(Vector3(sx * (water_w * 0.5 - 0.04), 0.04, dock_z + dock_d * 0.5), Vector3(0.08, 0.025, dock_d), P.C(S.CREAM, 0.08))
	# La grada: rampa de tablones que baja de la tierra al agua
	var slip0 := Vector3(0, 0.16, dock_z - 0.2)
	var slip1 := Vector3(0, 0.02, hd - 0.15)
	var sdir := (slip1 - slip0)
	for sx in [-0.28, 0.28]:
		mk.beam(slip0 + Vector3(sx, 0, 0), slip1 + Vector3(sx, 0, 0), 0.09, P.wood(-0.1))
	for k in 6:
		var p := slip0 + sdir * (float(k) + 0.5) / 6.0
		mk.box(p, Vector3(0.74, 0.05, 0.1), P.wood(-0.02))
	# El casco a medio hacer sobre la grada: quilla roja, costados de chapa a
	# media altura y las cuadernas que asoman por encima
	var hull_c := slip0 + sdir * 0.45 + Vector3(0, 0.18, 0)
	var hull_l := 1.5
	# Inclinado como la grada: la proa (+Z) baja hacia el agua.
	var tilt := Basis(Vector3.RIGHT, atan2(-sdir.y, sdir.z))
	var s0 := P.push(mk, Transform3D(tilt, hull_c))
	mk.box(Vector3(0, -0.1, 0), Vector3(0.12, 0.12, hull_l), P.C(S.RED, -0.1))
	for sx in [-1.0, 1.0]:
		mk.box(Vector3(sx * 0.24, 0.06, -0.15), Vector3(0.05, 0.26, hull_l * 0.7), P.C(S.SLATE, 0.06))
	for k in 7:
		var z := -hull_l * 0.45 + hull_l * 0.9 * float(k) / 6.0
		var half := 0.26 * (1.0 - 0.55 * pow(maxf(0.0, (z - 0.2) / (hull_l * 0.5)), 2.0))
		mk.beam(Vector3(-half, -0.04, z), Vector3(-half, 0.34, z), 0.05, P.wood(-0.06))
		mk.beam(Vector3(half, -0.04, z), Vector3(half, 0.34, z), 0.05, P.wood(-0.06))
		mk.beam(Vector3(-half, -0.06, z), Vector3(half, -0.06, z), 0.05, P.wood(-0.1))
	# Roda de laton en la proa
	mk.beam(Vector3(0, -0.1, hull_l * 0.5), Vector3(0, 0.38, hull_l * 0.5 + 0.08), 0.06, P.C(S.BRASS, -0.05))
	P.pop(mk, s0)
	# Puntales que sujetan el casco
	for sx in [-1.0, 1.0]:
		for t in [0.25, 0.6]:
			var p: Vector3 = slip0 + sdir * t
			mk.beam(p + Vector3(sx * 0.48, -0.02, 0), p + Vector3(sx * 0.27, 0.32, 0), 0.05, P.wood(-0.14))
	# La nave del taller, atras a la izquierda, con su chimenea
	var shed := Vector3(-hw + 0.62, 0.14, -hd + 0.5)
	P.block(mk, shed, Vector3(1.1, 0.6, 0.78), P.C(S.CREAM, -0.08))
	P.gable(mk, shed + Vector3(0, 0.6, 0), 1.1, 0.78, 0.32, P.C(S.SLATE, 0.02), P.C(S.CREAM, -0.08))
	P.door(mk, shed + Vector3(0.2, 0, 0.39), Vector3.BACK, 0.36, 0.44, P.wood(-0.1), P.iron())
	P.window(mk, shed + Vector3(-0.28, 0.36, 0.39), Vector3.BACK, 0.18, 0.16, P.iron(0.1), true)
	var smoke := P.stack(mk, shed + Vector3(-0.32, 0.6, -0.18), 0.08, 0.7, P.C(S.SLATE, -0.15), P.C(S.RED, 0.0))
	# Chapa y tablones apilados, atras a la derecha
	P.plank_stack(mk, Vector3(hw - 0.55, 0.14, -hd + 0.32), 0.7, 0.36, 3)
	for k in 3:
		mk.box(Vector3(hw - 0.5, 0.17 + k * 0.05, -hd + 0.8), Vector3(0.6, 0.04, 0.34), P.C(S.SLATE, 0.1 - k * 0.05))
	# La grua de portico (lo exagerado): dos patas sobre los muelles, la viga
	# por encima del casco y el carro con el gancho colgando
	var gz := dock_z + dock_d * 0.42
	var top_y := 1.75
	for sx in [-1.0, 1.0]:
		var foot := Vector3(sx * (hw - quay * 0.5), 0.14, gz)
		mk.beam(foot + Vector3(0, 0, -0.18), Vector3(foot.x * 0.96, top_y, gz), 0.1, yellow)
		mk.beam(foot + Vector3(0, 0, 0.18), Vector3(foot.x * 0.96, top_y, gz), 0.1, yellow)
		mk.box(foot + Vector3(0, 0.05, 0), Vector3(0.26, 0.1, 0.5), P.iron(0.02))
		P.hazard(mk, foot + Vector3(0, 0.16, 0.26), 0.24, 0.1, 0.02, 2)
	mk.box(Vector3(0, top_y + 0.08, gz), Vector3(w - quay * 0.6, 0.16, 0.2), yellow)
	mk.box(Vector3(0, top_y + 0.17, gz), Vector3(w - quay * 0.6, 0.03, 0.24), P.C(S.BRASS, -0.12))
	var trolley := Vector3(0.12, top_y - 0.04, gz)
	mk.box(trolley, Vector3(0.28, 0.14, 0.3), P.C(S.SLATE, -0.05))
	mk.box(trolley + Vector3(0, -0.45, 0), Vector3(0.02, 0.8, 0.02), P.iron(-0.1))
	mk.box(trolley + Vector3(0, -0.88, 0), Vector3(0.12, 0.08, 0.06), P.C(S.RED, 0.0))
	# Bandera del astillero en el poste de la esquina
	P.flag(mk, Vector3(hw - 0.15, 0.14, -0.1), 1.0, P.C(S.SKY, 0.05), P.C(S.CREAM, 0.0), Vector2(0.4, 0.26), -1.0)
	return {"fx": smoke}
