extends RefCounted
## Aerodromo (militar, aire; 1.1, feat/aire-mar-vista). Delante (+Z), la pista:
## una franja de asfalto con las rayas blancas y las balizas encendidas en los
## extremos. Atras a la izquierda, el hangar de chapa ondulada con techo de
## media cana y el portalon abierto. Atras a la derecha, lo exagerado: el
## MASTIL de amarre, una torre de celosia con un dirigible pequeno amarrado de
## la proa. Y la manga de viento roja en su poste.
##
## Todo propio (LotMesh + _parts y el elipsoide de las unidades), sin piezas
## CC0. ~1.300 triangulos.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S
const U := preload("res://tools/toy_recipes/units/_unit_parts.gd")

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var w := float(ctx.get("w", 2.8))
	var d := float(ctx.get("d", 2.8))
	var hw := w * 0.5
	var hd := d * 0.5
	# Suelo de hierba apisonada y la pista
	P.block(mk, Vector3.ZERO, Vector3(w, 0.08, d), P.C(S.GREEN, -0.2))
	var rz := hd - 0.5
	P.block(mk, Vector3(0, 0.08, rz), Vector3(w, 0.04, 0.72), P.C(S.IRON, 0.12))
	for k in 5:
		mk.box(Vector3(-hw + 0.3 + k * (w - 0.6) / 4.0, 0.125, rz), Vector3(0.26, 0.012, 0.07), P.C(S.CREAM, 0.08))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mk.box(Vector3(sx * (hw - 0.08), 0.15, rz + sz * 0.3), Vector3(0.07, 0.07, 0.07), P.C(S.GLOW), true)
	# Hangar de media cana, abierto hacia la pista
	var hangar := Vector3(-hw + 0.72, 0.08, -hd + 0.68)
	var hr := 0.62
	var hl := 1.2
	mk.cyl(hangar + Vector3(0, 0, -hl * 0.5), hr, hl, P.C(S.SLATE, 0.08), 10, Vector3.BACK)
	# Costillas de la chapa ondulada
	for k in 4:
		var z := -hl * 0.5 + hl * (float(k) + 0.5) / 4.0
		mk.cyl(hangar + Vector3(0, 0, z - 0.02), hr + 0.015, 0.04, P.C(S.SLATE, -0.08), 10, Vector3.BACK)
	# El portalon: hueco oscuro, puertas abiertas a los lados y el morro de un avion
	mk.box(hangar + Vector3(0, 0.26, hl * 0.5 + 0.005), Vector3(0.84, 0.5, 0.02), P.C(S.IRON, -0.15))
	for sx in [-1.0, 1.0]:
		mk.box(hangar + Vector3(sx * 0.52, 0.24, hl * 0.5 + 0.02), Vector3(0.22, 0.48, 0.04), P.C(S.SLATE, -0.02))
	mk.cyl(hangar + Vector3(0, 0.2, hl * 0.5 - 0.1), 0.1, 0.22, P.C(S.CREAM, -0.1), 8, Vector3.BACK, 0.08)
	U.prop(mk, hangar + Vector3(0, 0.2, hl * 0.5 + 0.16), 0.16)
	P.hazard(mk, hangar + Vector3(0, 0.56, hl * 0.5 + 0.03), 0.84, 0.08, 0.03, 6)
	# El mastil de amarre (celosia de cuatro patas) y su plataforma
	var mast := Vector3(hw - 0.62, 0.08, -hd + 0.62)
	var mh := 1.85
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mk.beam(mast + Vector3(sx * 0.22, 0, sz * 0.22), mast + Vector3(sx * 0.07, mh, sz * 0.07), 0.05, P.C(S.BRASS, -0.02))
	for t in [0.33, 0.66]:
		var y: float = mh * t
		var r: float = 0.22 - 0.15 * t
		mk.box(mast + Vector3(0, y, r), Vector3(r * 2.0, 0.04, 0.04), P.iron(0.05))
		mk.box(mast + Vector3(0, y, -r), Vector3(r * 2.0, 0.04, 0.04), P.iron(0.05))
		mk.box(mast + Vector3(r, y, 0), Vector3(0.04, 0.04, r * 2.0), P.iron(0.05))
		mk.box(mast + Vector3(-r, y, 0), Vector3(0.04, 0.04, r * 2.0), P.iron(0.05))
	mk.cyl(mast + Vector3(0, mh, 0), 0.16, 0.06, P.C(S.SLATE, 0.0), 8)
	mk.cyl(mast + Vector3(0, mh + 0.06, 0), 0.04, 0.16, P.C(S.GLOW), 6, Vector3.UP, -1.0, true)
	# El dirigible amarrado de la proa: cuelga hacia el centro de la parcela
	var nose := mast + Vector3(-0.12, mh - 0.05, 0.1)
	var ship_c := nose + Vector3(-0.5, -0.02, 0.42)
	var ship_dir := (nose - ship_c).normalized()
	var s0 := P.push(mk, Transform3D(Basis.looking_at(-ship_dir, Vector3.UP), ship_c))
	U.ellipsoid(mk, Vector3.ZERO, 0.24, 0.24, 0.62, P.C(S.CREAM, -0.04), 10, 5)
	for z in [-0.22, 0.18]:
		var k := sqrt(maxf(0.0, 1.0 - (z * z) / (0.62 * 0.62)))
		mk.cyl(Vector3(0, 0, z - 0.03), 0.24 * k + 0.01, 0.06, P.C(S.RED, -0.05), 10, Vector3.BACK)
	for a in 4:
		var dd := Vector3(cos(a * PI * 0.5), sin(a * PI * 0.5), 0)
		var size := Vector3(0.18, 0.03, 0.2) if absf(dd.x) > 0.5 else Vector3(0.03, 0.18, 0.2)
		mk.box(dd * 0.2 + Vector3(0, 0, -0.5), size, P.C(S.RED, -0.1))
	P.block(mk, Vector3(0, -0.36, 0.04), Vector3(0.14, 0.1, 0.3), P.wood(-0.02))
	P.pop(mk, s0)
	# Manga de viento en su poste, junto a la pista
	var sock := Vector3(hw - 0.3, 0.08, 0.0)
	mk.cyl(sock, 0.03, 0.9, P.iron(0.1), 5)
	mk.cyl(sock + Vector3(0, 0.84, 0), 0.08, 0.32, P.C(S.RED, 0.02), 6, Vector3(-1, -0.15, 0).normalized(), 0.04)
	# Bidones de combustible y una caja junto al hangar
	for k in 3:
		mk.cyl(Vector3(-0.1 + k * 0.17, 0.08, -0.1), 0.07, 0.2, P.C(S.RED, -0.08) if k != 1 else P.C(S.GREEN, -0.05), 8)
	mk.box(Vector3(0.18, 0.18, 0.2), Vector3(0.26, 0.2, 0.22), P.wood(0.0))
	return {"fx": mast + Vector3(0, mh + 0.14, 0)}
