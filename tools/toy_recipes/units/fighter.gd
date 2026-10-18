extends RefCounted
## Caza (aire): biplano dieselpunk. Fuselaje corto y gordo, motor redondo con
## la helice ENORME (lo exagerado: "esto va deprisa"), dos alas con montantes,
## la de arriba del color del bando con su escarapela, y el timon. Sin peana:
## la vista lo sube a su altura y le pone la sombra en el suelo (redonda los
## nuestros, en rombo la Regencia). La Regencia: tubos de escape de laton y
## franja de laton en el timon. ~360 triangulos.
const U := preload("res://tools/toy_recipes/units/_unit_parts.gd")
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, team, ctx: Dictionary) -> Dictionary:
	var side: String = ctx.get("side", "player")
	var regency := side == "regency"
	var y := U.AIR_Y + 0.25
	# Fuselaje: morro gordo y cola en punta
	team.cyl(Vector3(0, y, -0.15), 0.15, 0.6, U.T(0.08), 8, Vector3.BACK, 0.16)
	team.cyl(Vector3(0, y, -0.15), 0.15, 0.62, U.T(0.16), 8, Vector3.FORWARD, 0.035)
	# Motor redondo y helice
	mk.cyl(Vector3(0, y, 0.42), 0.18, 0.12, P.C(S.SLATE, 0.04), 10, Vector3.BACK)
	U.prop(mk, Vector3(0, y, 0.62), 0.42)
	# Cabina
	mk.box(Vector3(0, y + 0.16, -0.08), Vector3(0.16, 0.08, 0.2), P.C(S.SKY, 0.1))
	mk.ball(Vector3(0, y + 0.19, -0.2), 0.07, P.C(S.CREAM, -0.08))
	# Alas: abajo de lona, arriba del bando; montantes entre las dos
	mk.box(Vector3(0, y - 0.1, 0.12), Vector3(1.5, 0.05, 0.3), P.C(S.CREAM, -0.1))
	team.box(Vector3(0, y + 0.26, 0.16), Vector3(1.6, 0.05, 0.32), U.T(0.0))
	for sx in [-0.55, 0.55]:
		mk.beam(Vector3(sx, y - 0.08, 0.12), Vector3(sx, y + 0.24, 0.16), 0.035, P.wood(-0.1))
		U.roundel(mk, team, Vector3(sx, y + 0.285, 0.16), 0.11)
	# Cola: plano y timon
	mk.box(Vector3(0, y + 0.02, -0.7), Vector3(0.6, 0.04, 0.16), P.C(S.CREAM, -0.1))
	team.box(Vector3(0, y + 0.14, -0.72), Vector3(0.04, 0.24, 0.18), U.T(0.1))
	if regency:
		mk.box(Vector3(0, y + 0.23, -0.72), Vector3(0.05, 0.05, 0.19), P.C(S.BRASS, 0.05))
		for sx in [-0.17, 0.17]:
			mk.cyl(Vector3(sx, y + 0.04, 0.38), 0.03, 0.26, P.C(S.BRASS, -0.05), 5, Vector3.FORWARD)
	else:
		P.hazard(mk, Vector3(0, y + 0.29, 0.16), 0.3, 0.012, 0.32, 3)
	# Ametralladoras sobre el motor: de ahi sale el disparo
	return {"muzzle": Vector3(0, y + 0.12, 0.6), "top": Vector3(0, y + 0.42, 0)}
