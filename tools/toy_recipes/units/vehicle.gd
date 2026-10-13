extends RefCounted
## Vehiculo: el blindado dieselpunk. Casco bajo y ancho sobre dos orugas, torreta
## con su canon y la chimenea del motor diesel. Exagerado: la chimenea, que es lo
## que lo hace de este mundo. La Regencia lo lleva como su "caldera de cobro":
## casco mas alto, dos chimeneas con aros de laton y un faro. ~640 triangulos.
const U := preload("res://tools/toy_recipes/units/_unit_parts.gd")
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, team, ctx: Dictionary) -> Dictionary:
	var side: String = ctx.get("side", "player")
	var regency := side == "regency"
	U.stand(mk, team, side, 0.82)
	var y := 0.11
	# Orugas: banda oscura con tres ruedas a la vista por lado
	for sx in [-1.0, 1.0]:
		P.block(mk, Vector3(sx * 0.5, y, 0), Vector3(0.26, 0.3, 1.36), P.C(S.IRON, 0.02))
		for k in 3:
			mk.cyl(Vector3(sx * 0.64, y + 0.15, -0.42 + k * 0.42), 0.12, 0.03, P.C(S.SLATE, -0.1), 8, Vector3.RIGHT * sx)
	# Casco del bando
	var hull_h := 0.34 if not regency else 0.44
	P.block(team, Vector3(0, y + 0.22, 0), Vector3(0.78, hull_h, 1.24), U.T(0.0))
	# Frente en cuna (placa inclinada)
	team.beam(Vector3(0, y + 0.3, 0.62), Vector3(0, y + 0.22 + hull_h, 0.5), 0.74, U.T(0.12))
	# Remaches de laton en el costado
	for sx in [-1.0, 1.0]:
		mk.box(Vector3(sx * 0.395, y + 0.22 + hull_h * 0.6, 0), Vector3(0.02, 0.05, 1.0), P.C(S.BRASS, -0.05))
	var deck := y + 0.22 + hull_h
	# Torreta y canon
	var tur := Vector3(0, deck, -0.05)
	mk.cyl(tur, 0.3, 0.22, P.C(S.SLATE, 0.02), 8)
	team.box(tur + Vector3(0, 0.24, 0), Vector3(0.36, 0.06, 0.36), U.T(0.2))
	var gun0 := tur + Vector3(0, 0.12, 0.25)
	var gun1 := tur + Vector3(0, 0.15, 0.95)
	mk.cyl(gun0, 0.07, gun0.distance_to(gun1), P.iron(0.08), 8, (gun1 - gun0).normalized())
	mk.cyl(gun1 - (gun1 - gun0).normalized() * 0.1, 0.09, 0.12, P.iron(-0.05), 8, (gun1 - gun0).normalized())
	# Chimenea(s) del diesel, atras
	if regency:
		for sx in [-0.2, 0.2]:
			P.stack(mk, Vector3(sx, deck, -0.48), 0.08, 0.46, P.C(S.SLATE, -0.15), P.C(S.BRASS, 0.0))
		mk.cyl(Vector3(0.3, deck - 0.05, 0.6), 0.07, 0.06, P.C(S.GLOW), 8, Vector3.BACK, -1.0, true)
	else:
		P.stack(mk, Vector3(0.24, deck, -0.48), 0.09, 0.42, P.C(S.SLATE, -0.15), P.C(S.RED, 0.0))
		P.hazard(mk, Vector3(0, y + 0.3, 0.66), 0.6, 0.06, 0.02, 6)
	return {"muzzle": gun1, "top": Vector3(0, deck + 0.55, 0)}
