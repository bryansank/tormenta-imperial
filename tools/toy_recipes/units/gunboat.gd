extends RefCounted
## Canonera (mar): casco mediano, castillo con puente y una chimenea alta, y la
## torreta de proa con UN canon gordo y largo (lo exagerado). Los nuestros,
## franja de peligro en la cubierta de proa; la Regencia, chimenea doble con
## aros de laton y el faro de su caldera de cobro. ~330 triangulos.
const U := preload("res://tools/toy_recipes/units/_unit_parts.gd")
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, team, ctx: Dictionary) -> Dictionary:
	var side: String = ctx.get("side", "player")
	var regency := side == "regency"
	var l := 1.5
	U.sea_stand(mk, team, side, 0.84, l)
	var deck := U.hull(mk, team, l, 0.6, 0.34, P.wood(0.0))
	# Castillo y puente
	var house := Vector3(0, deck, -0.22)
	P.block(mk, house, Vector3(0.42, 0.22, 0.46), P.C(S.STONE, 0.02))
	P.block(mk, house + Vector3(0, 0.22, 0.06), Vector3(0.32, 0.16, 0.22), P.C(S.CREAM, -0.04))
	mk.box(house + Vector3(0, 0.39, 0.06), Vector3(0.38, 0.04, 0.28), P.C(S.SLATE, -0.06))
	mk.box(house + Vector3(0, 0.31, 0.171), Vector3(0.24, 0.05, 0.01), P.C(S.GLOW), true)
	# Chimenea(s)
	if regency:
		for sx in [-0.09, 0.09]:
			U.funnel(mk, house + Vector3(sx, 0.22, -0.16), 0.065, 0.34, P.C(S.BRASS, 0.05), 0.05)
		mk.cyl(house + Vector3(0.14, 0.42, 0.18), 0.05, 0.05, P.C(S.GLOW), 6, Vector3.BACK, -1.0, true)
	else:
		U.funnel(mk, house + Vector3(0, 0.22, -0.16), 0.085, 0.4, P.C(S.RED, 0.0), 0.06)
		P.hazard(mk, Vector3(0, deck + 0.01, 0.5), 0.4, 0.02, 0.06, 4)
	# Mastil a popa
	mk.cyl(Vector3(0, deck, -0.6), 0.025, 0.5, P.iron(0.1), 5)
	mk.box(Vector3(0, deck + 0.42, -0.6), Vector3(0.24, 0.025, 0.025), P.iron(0.1))
	# Torreta de proa con su canon
	var muzzle := U.turret(mk, team, Vector3(0, deck, 0.3), 0.17, 1, 0.5, 0.06)
	return {"muzzle": muzzle, "top": Vector3(0, deck + 0.78, 0)}
