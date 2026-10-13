extends RefCounted
## Artilleria: canon de campana con escudo, dos ruedas macizas, la cola apoyada
## en el suelo y un artillero detras. Exagerado: el tubo, largo y grueso, que
## dice "esto dispara lejos". El escudo lleva el color del bando; la Regencia
## lo remata con una corona de laton (su recaudacion), los nuestros con franja
## de peligro. ~520 triangulos.
const U := preload("res://tools/toy_recipes/units/_unit_parts.gd")
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, team, ctx: Dictionary) -> Dictionary:
	var side: String = ctx.get("side", "player")
	U.stand(mk, team, side, 0.78)
	var y := 0.11
	var axle := Vector3(0, y + 0.36, 0.05)
	# Ruedas
	for sx in [-1.0, 1.0]:
		U.wheel_disc(mk, axle + Vector3(sx * 0.44, 0, 0), 0.34, 0.09, P.wood(-0.1), Vector3.RIGHT * sx)
	mk.beam(axle + Vector3(-0.42, 0, 0), axle + Vector3(0.42, 0, 0), 0.07, P.iron(0.05))
	# Cola (dos largueros que bajan hacia atras)
	for sx in [-0.12, 0.12]:
		mk.beam(axle + Vector3(sx, 0, 0), Vector3(sx * 0.4, y + 0.05, -0.62), 0.08, P.C(S.SLATE, -0.1))
	# Cuna y tubo, apuntando al frente y algo arriba
	var breech := axle + Vector3(0, 0.12, -0.2)
	var muzzle := axle + Vector3(0, 0.34, 0.78)
	var dir := (muzzle - breech).normalized()
	P.block(mk, axle + Vector3(0, 0.02, -0.12), Vector3(0.26, 0.16, 0.36), P.C(S.SLATE, -0.05))
	mk.cyl(breech, 0.11, breech.distance_to(muzzle), P.C(S.SLATE, 0.05), 8, dir, 0.085)
	mk.cyl(muzzle - dir * 0.12, 0.11, 0.14, P.iron(-0.05), 8, dir)
	# Escudo del bando, con su remate
	team.box(axle + Vector3(0, 0.22, 0.22), Vector3(0.74, 0.44, 0.06), U.T(0.05))
	if side == "regency":
		for k in 3:
			mk.box(axle + Vector3(-0.2 + k * 0.2, 0.5, 0.22), Vector3(0.1, 0.14 if k == 1 else 0.1, 0.06), P.C(S.BRASS, 0.05))
	else:
		P.hazard(mk, axle + Vector3(0, 0.0, 0.26), 0.74, 0.07, 0.02, 6)
	# Municion junto a la cola
	mk.cyl(Vector3(0.4, y, -0.45), 0.07, 0.24, P.C(S.BRASS, -0.05), 6)
	# El artillero, detras y a un lado, sin fusil
	U.soldier(mk, team, Vector3(-0.42, y, -0.38), 20.0, side, false, 0.95)
	return {"muzzle": muzzle + dir * 0.05, "top": Vector3(0, 1.05, 0)}
