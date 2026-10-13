extends RefCounted
## Laboratorio (civico, acento laton): edificio de piedra con ojos de buey de luz
## azulada, bobina de cobre y la cupula de cristal. Exagerado: la cupula, mas
## ancha que la mitad del edificio, con nervios de laton y linterna encendida.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var brass := P.C(S.BRASS)
	var stone := P.C(S.STONE, 0.02)
	var c := Vector3(0, 0, -0.25)
	var w := 2.4
	var d := 1.9
	var fz := c.z + d * 0.5
	P.block(mk, c, Vector3(w + 0.1, 0.18, d + 0.1), P.C(S.STONE, -0.15))
	P.block(mk, c + Vector3(0, 0.18, 0), Vector3(w, 1.05, d), stone)
	P.block(mk, c + Vector3(0, 1.2, 0), Vector3(w + 0.12, 0.1, d + 0.12), brass.darkened(0.2))
	P.flat_roof(mk, c + Vector3(0, 1.3, 0), w, d, P.C(S.SLATE))
	# Ojos de buey (luz azulada) y puerta de laton con escalones
	for x in [-0.8, 0.8]:
		P.porthole(mk, Vector3(x, 0.78, fz), Vector3.BACK, 0.2, brass, true, S.SKY)
	for z in [-0.6, 0.15]:
		P.porthole(mk, Vector3(c.x + w * 0.5, 0.78, z), Vector3.RIGHT, 0.18, brass, true, S.SKY)
	P.door(mk, Vector3(0, 0.18, fz), Vector3.BACK, 0.5, 0.78, P.C(S.SLATE, 0.05), brass)
	P.block(mk, Vector3(0, 0, fz + 0.15), Vector3(0.8, 0.12, 0.3), P.C(S.STONE, 0.05))
	# La cupula (exagerada): tambor, cristal azul, nervios de laton, linterna
	var dc := c + Vector3(0, 1.4, -0.05)
	mk.cyl(dc, 0.82, 0.22, brass.darkened(0.15), 12)
	var r := 0.8
	var tiers := [[0.0, 1.0], [0.3, 0.93], [0.55, 0.75], [0.72, 0.5], [0.8, 0.2]]
	for i in tiers.size() - 1:
		var y0: float = tiers[i][0]
		var y1: float = tiers[i + 1][0]
		mk.cyl(dc + Vector3(0, 0.22 + y0, 0), r * float(tiers[i][1]), y1 - y0, P.C(S.SKY, 0.1 - 0.04 * i), 12, Vector3.UP, r * float(tiers[i + 1][1]))
	for k in 6:
		var a := TAU * float(k) / 6.0
		var dir := Vector3(cos(a), 0, sin(a))
		for i in tiers.size() - 1:
			mk.beam(dc + Vector3(0, 0.22 + float(tiers[i][0]), 0) + dir * (r * float(tiers[i][1]) + 0.02), dc + Vector3(0, 0.22 + float(tiers[i + 1][0]), 0) + dir * (r * float(tiers[i + 1][1]) + 0.02), 0.05, brass)
	mk.cyl(dc + Vector3(0, 1.02, 0), 0.14, 0.2, brass, 8)
	mk.ball(dc + Vector3(0, 1.32, 0), 0.13, P.C(S.SKY, 0.2), Vector3.ONE, true)
	# Bobina de cobre en la esquina del tejado
	var tc := c + Vector3(0.85, 1.4, 0.55)
	mk.cyl(tc, 0.14, 0.12, P.iron(), 8)
	mk.cyl(tc + Vector3(0, 0.12, 0), 0.09, 0.5, P.C(S.TERRACOTTA, -0.1), 8)
	for k in 4:
		mk.cyl(tc + Vector3(0, 0.18 + k * 0.1, 0), 0.12, 0.04, brass, 8)
	mk.ball(tc + Vector3(0, 0.72, 0), 0.13, brass.lightened(0.1))
	# Tuberia de gas por la fachada y dos botellas
	P.pipe_run(mk, [Vector3(-1.0, 0.18, fz + 0.06), Vector3(-1.0, 1.1, fz + 0.06), Vector3(-0.55, 1.1, fz + 0.06)], 0.045, P.C(S.TERRACOTTA, -0.1))
	for k in 2:
		mk.cyl(Vector3(0.95 + k * 0.22, 0, fz + 0.3), 0.09, 0.5, P.C(S.SKY, -0.1) if k == 0 else brass, 8)
		mk.ball(Vector3(0.95 + k * 0.22, 0.5, fz + 0.3), 0.09, P.iron(0.1))
	return {}
