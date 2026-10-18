extends RefCounted
## Lancha torpedera (mar): casco corto y fino, la garita a popa, una chimenea y
## los DOS tubos lanzatorpedos en cubierta, que es lo exagerado (gordos, de
## laton en la boca): "esta pega desde el agua y deprisa". La Regencia la lleva
## con un faro encendido en la garita y la chimenea con aro de laton.
## ~350 triangulos.
const U := preload("res://tools/toy_recipes/units/_unit_parts.gd")
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, team, ctx: Dictionary) -> Dictionary:
	var side: String = ctx.get("side", "player")
	var regency := side == "regency"
	var l := 1.36
	U.sea_stand(mk, team, side, 0.78, l)
	var deck := U.hull(mk, team, l, 0.5, 0.3, P.wood(0.02))
	# Garita a popa con su techo y ventanitas encendidas
	var cab := Vector3(0, deck, -0.28)
	P.block(mk, cab, Vector3(0.34, 0.24, 0.3), P.C(S.CREAM, -0.05))
	mk.box(cab + Vector3(0, 0.26, 0), Vector3(0.4, 0.04, 0.36), P.C(S.SLATE, -0.05))
	mk.box(cab + Vector3(0, 0.15, 0.151), Vector3(0.24, 0.06, 0.01), P.C(S.GLOW), true)
	U.funnel(mk, cab + Vector3(0, 0.24, -0.1), 0.07, 0.3, P.C(S.BRASS, 0.0) if regency else P.C(S.RED, 0.0), 0.04)
	# Los tubos lanzatorpedos, a cada banda, apuntando a proa
	var muzzle := Vector3.ZERO
	for sx in [-1.0, 1.0]:
		var b0 := Vector3(sx * 0.15, deck + 0.07, -0.05)
		mk.cyl(b0, 0.065, 0.5, P.C(S.SLATE, 0.06), 8, Vector3.BACK)
		mk.cyl(b0 + Vector3(0, 0, 0.44), 0.075, 0.07, P.C(S.BRASS, 0.05), 8, Vector3.BACK)
		muzzle = b0 + Vector3(0, 0, 0.52)
	# Proa: tajamar de laton
	mk.beam(Vector3(0, U.WATERLINE + 0.06, l * 0.5 - 0.02), Vector3(0, deck + 0.05, l * 0.5 + 0.01), 0.04, P.C(S.BRASS, -0.05))
	if regency:
		mk.cyl(cab + Vector3(0.12, 0.3, 0.12), 0.05, 0.05, P.C(S.GLOW), 6, Vector3.BACK, -1.0, true)
	else:
		P.hazard(mk, Vector3(0, deck + 0.01, 0.42), 0.36, 0.02, 0.06, 4)
	return {"muzzle": Vector3(0.0, deck + 0.07, muzzle.z), "top": Vector3(0, deck + 0.62, 0)}
