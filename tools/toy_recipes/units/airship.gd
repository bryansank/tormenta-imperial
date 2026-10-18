extends RefCounted
## Dirigible (aire): la envuelta grande de lona (lo exagerado: el volumen), con
## tres franjas del color del bando y cuatro aletas en cruz; la barquilla de
## madera con ventanas encendidas, dos motores laterales con helice y el canon
## de la barquilla. La Regencia: envuelta mas oscura, aletas moradas y la
## caperuza de laton en la proa (su recaudacion). ~480 triangulos.
const U := preload("res://tools/toy_recipes/units/_unit_parts.gd")
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, team, ctx: Dictionary) -> Dictionary:
	var side: String = ctx.get("side", "player")
	var regency := side == "regency"
	var c := Vector3(0, U.AIR_Y + 0.62, 0)
	var rx := 0.4
	var rz := 0.86
	var cloth := P.C(S.STONE, -0.14) if regency else P.C(S.CREAM, -0.04)
	U.ellipsoid(mk, c, rx, rx, rz, cloth, 10, 6)
	# Franjas del bando: anillos un pelo mas gordos que la envuelta
	for z in [-0.42, 0.0, 0.42]:
		var k := sqrt(maxf(0.0, 1.0 - (z * z) / (rz * rz)))
		team.cyl(c + Vector3(0, 0, z - 0.04), rx * k + 0.012, 0.08, U.T(0.04), 10, Vector3.BACK)
	# Aletas en cruz, a popa
	var tail := c + Vector3(0, 0, -rz + 0.16)
	for a in 4:
		var d := Vector3(cos(a * PI * 0.5), sin(a * PI * 0.5), 0)
		var fin_c := tail + d * 0.3 + Vector3(0, 0, -0.06)
		# Las de los lados, planas; la de arriba y la de abajo, de canto.
		var size := Vector3(0.26, 0.04, 0.28) if absf(d.x) > 0.5 else Vector3(0.04, 0.26, 0.28)
		team.box(fin_c, size, U.T(0.12))
	# Barquilla y sus cables
	var g := c + Vector3(0, -rx - 0.2, 0.05)
	P.block(mk, g, Vector3(0.24, 0.16, 0.5), P.wood(-0.02))
	mk.box(g + Vector3(0, 0.17, 0), Vector3(0.28, 0.03, 0.54), P.C(S.SLATE, -0.04))
	for sx in [-1.0, 1.0]:
		mk.box(g + Vector3(sx * 0.121, 0.09, 0.05), Vector3(0.01, 0.05, 0.3), P.C(S.GLOW), true)
	for z in [-0.18, 0.18]:
		mk.beam(g + Vector3(0, 0.18, z), c + Vector3(0, -rx * 0.9, z * 1.3), 0.02, P.iron(0.1))
	# Motores en sus brazos, a cada lado
	for sx in [-1.0, 1.0]:
		var m := g + Vector3(sx * 0.36, 0.1, -0.12)
		mk.beam(g + Vector3(sx * 0.12, 0.1, -0.12), m, 0.03, P.iron(0.05))
		mk.cyl(m + Vector3(0, 0, -0.12), 0.06, 0.22, P.C(S.SLATE, 0.0), 6, Vector3.BACK, 0.05)
		U.prop(mk, m + Vector3(0, 0, -0.16), 0.15, Vector3.FORWARD)
	# Canon de la barquilla
	var gun0 := g + Vector3(0, 0.04, 0.25)
	mk.cyl(gun0, 0.035, 0.18, P.iron(0.08), 6, Vector3(0, -0.4, 1).normalized())
	if regency:
		# Caperuza de laton en la proa
		mk.cyl(c + Vector3(0, 0, rz - 0.12), 0.17, 0.11, P.C(S.BRASS, 0.05), 8, Vector3.BACK, 0.06)
	return {"muzzle": gun0 + Vector3(0, -0.07, 0.17), "top": c + Vector3(0, rx + 0.08, 0)}
