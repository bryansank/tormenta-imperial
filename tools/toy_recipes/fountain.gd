extends RefCounted
## Fuente (civica, acento laton): pilon redondo de piedra con brocal de laton,
## dos tazas y los chorros cayendo al agua. Exagerado: el surtidor central,
## alto y rematado por una bola de laton.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var brass := P.C(S.BRASS)
	var stone := P.C(S.STONE, 0.0)
	var water := P.C(S.SKY, 0.05)
	var jet := P.C(S.SKY, 0.2)
	var r := minf(float(ctx["w"]), float(ctx["d"])) * 0.5 - 0.12
	# Losa y pilon
	mk.cyl(Vector3.ZERO, r + 0.08, 0.08, P.C(S.STONE, -0.15), 12)
	mk.cyl(Vector3(0, 0.08, 0), r, 0.32, stone, 12)
	P.ring(mk, Vector3(0, 0.43, 0), r - 0.04, 0.09, brass, 12)
	mk.cyl(Vector3(0, 0.405, 0), r - 0.1, 0.015, water, 12)
	# Fuste y tazas
	mk.cyl(Vector3(0, 0.38, 0), 0.22, 0.75, stone.lightened(0.05), 8, Vector3.UP, 0.16)
	mk.cyl(Vector3(0, 1.05, 0), 0.25, 0.18, stone, 10, Vector3.UP, 0.7)
	P.ring(mk, Vector3(0, 1.25, 0), 0.68, 0.07, brass, 10)
	mk.cyl(Vector3(0, 1.237, 0), 0.64, 0.015, water, 10)
	mk.cyl(Vector3(0, 1.22, 0), 0.1, 0.55, stone.lightened(0.05), 8)
	mk.cyl(Vector3(0, 1.72, 0), 0.12, 0.12, stone, 8, Vector3.UP, 0.38)
	P.ring(mk, Vector3(0, 1.86, 0), 0.36, 0.06, brass, 8)
	mk.cyl(Vector3(0, 1.847, 0), 0.34, 0.015, water, 8)
	# Surtidor (exagerado) y bola de laton
	mk.cyl(Vector3(0, 1.86, 0), 0.07, 0.75, jet, 6, Vector3.UP, 0.03, true)
	mk.ball(Vector3(0, 2.68, 0), 0.13, brass.lightened(0.1))
	# Chorros: de la taza alta a la baja y de la baja al pilon
	for k in 6:
		var a := TAU * float(k) / 6.0
		var dir := Vector3(cos(a), 0, sin(a))
		mk.beam(dir * 0.38 + Vector3(0, 1.86, 0), dir * 0.55 + Vector3(0, 1.26, 0), 0.04, jet, true)
		var b := a + PI / 6.0
		var dir2 := Vector3(cos(b), 0, sin(b))
		mk.beam(dir2 * 0.7 + Vector3(0, 1.24, 0), dir2 * 0.95 + Vector3(0, 0.38, 0), 0.05, jet, true)
	# Nenufares
	kit.put(mk, "kk:waterplant_A", Vector3(-0.75, 0.41, 0.55), 0.28, 0.0, {"noglow": true})
	kit.put(mk, "kk:waterplant_A", Vector3(0.8, 0.41, -0.35), 0.24, 60.0, {"noglow": true})
	return {}
