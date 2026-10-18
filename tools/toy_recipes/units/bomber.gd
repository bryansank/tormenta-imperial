extends RefCounted
## Bombardero (aire): bimotor pesado. Fuselaje largo con el morro acristalado,
## un ala recta y ancha del color del bando, dos motores con sus helices y doble
## timon; bajo la panza, las DOS bombas gordas (lo exagerado: "esto suelta
## cosas"). La Regencia: motores con capot de laton y un faro en el morro.
## ~490 triangulos.
const U := preload("res://tools/toy_recipes/units/_unit_parts.gd")
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, team, ctx: Dictionary) -> Dictionary:
	var side: String = ctx.get("side", "player")
	var regency := side == "regency"
	var y := U.AIR_Y + 0.28
	# Fuselaje
	team.cyl(Vector3(0, y, -0.2), 0.17, 0.62, U.T(0.06), 8, Vector3.BACK, 0.15)
	team.cyl(Vector3(0, y, -0.2), 0.17, 0.62, U.T(0.16), 8, Vector3.FORWARD, 0.05)
	mk.cyl(Vector3(0, y, 0.42), 0.15, 0.2, P.C(S.SKY, 0.12), 8, Vector3.BACK, 0.06)
	if regency:
		mk.cyl(Vector3(0, y - 0.08, 0.5), 0.04, 0.06, P.C(S.GLOW), 6, Vector3.BACK, -1.0, true)
	# Ala recta, del bando, con escarapelas
	team.box(Vector3(0, y + 0.02, 0.08), Vector3(1.7, 0.06, 0.4), U.T(0.0))
	for sx in [-0.62, 0.62]:
		U.roundel(mk, team, Vector3(sx, y + 0.05, 0.08), 0.12)
	# Motores
	for sx in [-0.42, 0.42]:
		var cowl := P.C(S.BRASS, -0.05) if regency else P.C(S.SLATE, 0.02)
		mk.cyl(Vector3(sx, y - 0.04, -0.12), 0.11, 0.48, P.C(S.SLATE, -0.06), 8, Vector3.BACK, 0.1)
		mk.cyl(Vector3(sx, y - 0.04, 0.32), 0.12, 0.08, cowl, 8, Vector3.BACK)
		U.prop(mk, Vector3(sx, y - 0.04, 0.44), 0.26)
	# Cola: plano y doble timon del bando
	mk.box(Vector3(0, y + 0.04, -0.78), Vector3(0.7, 0.04, 0.18), P.C(S.CREAM, -0.1))
	for sx in [-0.33, 0.33]:
		team.box(Vector3(sx, y + 0.14, -0.8), Vector3(0.04, 0.24, 0.18), U.T(0.1))
	# Las bombas, colgadas bajo la panza
	for sx in [-0.09, 0.09]:
		var b := Vector3(sx, y - 0.21, -0.18)
		mk.cyl(b, 0.065, 0.3, P.iron(0.05), 6, Vector3.BACK, 0.065)
		mk.cyl(b + Vector3(0, 0, 0.3), 0.065, 0.08, P.iron(0.05), 6, Vector3.BACK, 0.0)
		mk.box(b + Vector3(0, 0, -0.02), Vector3(0.14, 0.02, 0.06), P.C(S.RED, 0.0))
	if not regency:
		P.hazard(mk, Vector3(0, y + 0.06, -0.62), 0.3, 0.012, 0.12, 3)
	return {"muzzle": Vector3(0, y - 0.24, 0.0), "top": Vector3(0, y + 0.36, 0)}
