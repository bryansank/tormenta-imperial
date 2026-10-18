extends RefCounted
## Herreria militar (militar, 1.2, feat/edificios-militares). Atras a la
## izquierda, la nave de piedra con tejado de pizarra, franja de peligro y su
## chimenea de ladrillo (de ahi el humo de "trabajando", FxAnchor). A la
## derecha, el cobertizo abierto con la FRAGUA encendida (lo exagerado: boca
## grande de brasas que brilla sin luz real) y su fuelle. Delante, el YUNQUE
## enorme sobre su tajo, la muela de afilar (rueda de piedra), el armero
## (`kk:weaponrack`) y el barril de templar (`kk:barrel`).
## ~1.400 triangulos.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	var stone := P.C(S.STONE, -0.04)
	var roof := P.C(S.SLATE, -0.04)
	# ── La nave ──
	var c := Vector3(-0.42, 0, -0.55)
	var w := 1.8
	var d := 1.3
	var fz := c.z + d * 0.5
	P.block(mk, c, Vector3(w + 0.1, 0.12, d + 0.1), P.C(S.STONE, -0.2))
	P.block(mk, c + Vector3(0, 0.12, 0), Vector3(w, 0.9, d), stone)
	P.hazard(mk, Vector3(c.x, 0.9, fz + 0.02), w, 0.12, 0.05, 9)
	P.gable(mk, c + Vector3(0, 1.02, 0), w, d, 0.55, roof, stone)
	P.door(mk, Vector3(c.x + 0.3, 0.12, fz), Vector3.BACK, 0.5, 0.7, P.wood(-0.18), P.iron())
	P.window(mk, Vector3(c.x - 0.45, 0.62, fz), Vector3.BACK, 0.26, 0.24, P.iron(0.1), true)
	var mouth: Vector3 = P.chimney(mk, c + Vector3(-0.6, 0.95, -0.3), 0.28, 1.15,
		P.C(S.TERRACOTTA, -0.15), P.iron())
	# ── El cobertizo con la fragua (lo exagerado) ──
	var f := Vector3(0.95, 0, -0.55)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			P.post(mk, f + Vector3(sx * 0.4, 0, sz * 0.45), 1.05, 0.08, P.wood(-0.2))
	P.shed_roof(mk, f, 0.95, 1.05, 1.2, 0.98, P.C(S.SLATE, 0.08))
	P.block(mk, f + Vector3(0, 0, -0.1), Vector3(0.7, 0.5, 0.6), P.C(S.STONE, -0.25))
	P.block(mk, f + Vector3(0, 0.5, -0.1), Vector3(0.5, 0.06, 0.42), P.C(S.GLOW), true)
	mk.box(f + Vector3(0, 0.56, -0.1), Vector3(0.36, 0.05, 0.28), P.C(S.RED, 0.1), true)
	mk.box(f + Vector3(0, 0.3, 0.205), Vector3(0.34, 0.16, 0.02), P.C(S.GLOW), true)
	# El fuelle de cuero junto a la fragua
	mk.box(f + Vector3(-0.42, 0.42, -0.1), Vector3(0.12, 0.16, 0.36), P.wood(-0.3))
	mk.cyl(f + Vector3(-0.36, 0.42, -0.1), 0.03, 0.12, P.iron(), 6, Vector3.RIGHT)
	# ── Delante: el yunque, la muela, el armero y el barril ──
	var a := Vector3(-0.1, 0, 0.6)
	mk.cyl(a, 0.2, 0.32, P.wood(-0.1), 8)
	mk.box(a + Vector3(0, 0.38, 0), Vector3(0.2, 0.12, 0.2), P.iron(0.05))
	mk.box(a + Vector3(0, 0.49, 0), Vector3(0.5, 0.1, 0.22), P.iron(0.15))
	mk.cyl(a + Vector3(0.25, 0.49, 0), 0.07, 0.18, P.iron(0.15), 6, Vector3.RIGHT, 0.0)
	# El martillo encima
	mk.box(a + Vector3(-0.08, 0.58, 0.02), Vector3(0.1, 0.07, 0.07), P.iron(-0.05))
	mk.box(a + Vector3(0.05, 0.58, 0.02), Vector3(0.24, 0.03, 0.03), P.wood(0.05))
	# Muela de afilar
	var g := Vector3(0.75, 0, 0.75)
	for sz in [-1.0, 1.0]:
		P.post(mk, g + Vector3(0, 0, sz * 0.12), 0.4, 0.05, P.wood(-0.2))
	mk.cyl(g + Vector3(0, 0.38, -0.05), 0.22, 0.1, P.C(S.STONE, 0.05), 12, Vector3.BACK, -1.0, false, true)
	mk.cyl(g + Vector3(0, 0.38, -0.12), 0.04, 0.24, P.iron(), 6, Vector3.BACK)
	kit.put(mk, "kk:weaponrack", Vector3(-1.05, 0, 0.75), 0.48, 0.0, {"noglow": true})
	kit.put(mk, "kk:barrel", Vector3(0.35, 0, 0.95), 0.3, 0.0, {"noglow": true})
	return {"fx": mouth}
