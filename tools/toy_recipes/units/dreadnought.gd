extends RefCounted
## Acorazado (mar): el gordo. Casco largo y ancho, superestructura escalonada,
## dos chimeneas, palo con cofa y DOS torretas de canones dobles (proa y popa):
## lo exagerado son los canones, largos, que dicen "esto pega muy fuerte y muy
## lejos". La Regencia: chimeneas con aros de laton, una corona de laton en la
## cofa y un faro encendido. ~480 triangulos.
const U := preload("res://tools/toy_recipes/units/_unit_parts.gd")
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, team, ctx: Dictionary) -> Dictionary:
	var side: String = ctx.get("side", "player")
	var regency := side == "regency"
	var l := 1.66
	U.sea_stand(mk, team, side, 0.9, l)
	var deck := U.hull(mk, team, l, 0.74, 0.36, P.C(S.STONE, -0.08))
	# Superestructura escalonada
	var mid := Vector3(0, deck, -0.08)
	P.block(mk, mid, Vector3(0.5, 0.18, 0.62), P.C(S.SLATE, 0.08))
	P.block(mk, mid + Vector3(0, 0.18, 0.08), Vector3(0.38, 0.16, 0.34), P.C(S.SLATE, 0.14))
	P.block(mk, mid + Vector3(0, 0.34, 0.14), Vector3(0.28, 0.12, 0.16), P.C(S.CREAM, -0.06))
	mk.box(mk_v(mid, 0.46, 0.14), Vector3(0.32, 0.03, 0.2), P.C(S.SLATE, -0.04))
	mk.box(mid + Vector3(0, 0.41, 0.221), Vector3(0.2, 0.04, 0.01), P.C(S.GLOW), true)
	# Chimeneas
	var band := P.C(S.BRASS, 0.05) if regency else P.C(S.RED, -0.02)
	U.funnel(mk, mid + Vector3(0, 0.18, -0.12), 0.08, 0.36, band, 0.05)
	U.funnel(mk, mid + Vector3(0, 0.18, -0.3), 0.075, 0.3, band, 0.05)
	# Palo con cofa
	var mast := mid + Vector3(0, 0.46, 0.14)
	mk.cyl(mast, 0.025, 0.42, P.iron(0.1), 5)
	mk.cyl(mast + Vector3(0, 0.3, 0), 0.07, 0.06, P.C(S.SLATE, 0.0), 6)
	if regency:
		for k in 3:
			var a := TAU * float(k) / 3.0
			mk.box(mast + Vector3(cos(a) * 0.06, 0.4, sin(a) * 0.06), Vector3(0.04, 0.07, 0.04), P.C(S.BRASS, 0.08))
		mk.cyl(mid + Vector3(0.16, 0.3, 0.2), 0.05, 0.05, P.C(S.GLOW), 6, Vector3.BACK, -1.0, true)
	else:
		P.hazard(mk, Vector3(0, deck + 0.01, 0.66), 0.4, 0.02, 0.05, 4)
	# Torretas dobles: proa y popa (la de popa mira atras)
	var muzzle := U.turret(mk, team, Vector3(0, deck, 0.42), 0.18, 2, 0.48, 0.045)
	U.turret(mk, team, Vector3(0, deck, -0.58), 0.16, 2, 0.36, 0.04, true)
	return {"muzzle": muzzle, "top": Vector3(0, deck + 0.95, 0)}

static func mk_v(c: Vector3, y: float, z: float) -> Vector3:
	return c + Vector3(0, y, z)
