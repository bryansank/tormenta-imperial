extends RefCounted
## Torre (militar, acento amarillo y negro): fuste de piedra que se estrecha,
## plataforma de chapa con nido de sacos terreros y el canon a la vista.
## Exagerado: el canon de la plataforma, largo y grueso, asomando por delante.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var yellow := P.C(S.BRASS, 0.05)
	var stone := P.C(S.STONE, -0.06)
	# Fuste
	P.block(mk, Vector3.ZERO, Vector3(1.9, 0.2, 1.9), P.C(S.STONE, -0.2))
	mk.cyl(Vector3(0, 0.2, 0), 0.92, 1.5, stone, 8, Vector3.UP, 0.78)
	P.hazard(mk, Vector3(0, 0.4, 0.86), 0.9, 0.12, 0.05, 6)
	P.door(mk, Vector3(0, 0.2, 0.83), Vector3.BACK, 0.4, 0.62, P.C(S.SLATE, 0.05), P.iron())
	for a in [-50.0, 50.0]:
		var dir := Vector3(sin(deg_to_rad(a)), 0, cos(deg_to_rad(a)))
		P.window(mk, Vector3(0, 1.15, 0) + dir * 0.82, dir, 0.12, 0.3, P.iron(0.1), true)
	# Plataforma de chapa con su borde a franjas
	var py := 1.7
	mk.cyl(Vector3(0, py, 0), 1.25, 0.16, P.C(S.SLATE, 0.0), 8)
	for k in 16:
		var a0 := TAU * float(k) / 16.0
		var a1 := TAU * float(k + 1) / 16.0
		mk.beam(Vector3(cos(a0), 0, sin(a0)) * 1.24 + Vector3(0, py + 0.08, 0), Vector3(cos(a1), 0, sin(a1)) * 1.24 + Vector3(0, py + 0.08, 0), 0.1, yellow if k % 2 == 0 else P.iron())
	# Mensulas bajo la plataforma
	for k in 8:
		var a := TAU * float(k) / 8.0 + PI / 8.0
		var dir := Vector3(cos(a), 0, sin(a))
		mk.beam(dir * 0.8 + Vector3(0, py - 0.45, 0), dir * 1.15 + Vector3(0, py, 0), 0.1, P.iron(0.05))
	# Nido de sacos terreros, abierto por delante para el canon
	for k in 12:
		var a := TAU * float(k) / 12.0
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.6:
			continue
		var dir := Vector3(cos(a), 0, sin(a))
		P.sandbag(mk, dir * 1.0 + Vector3(0, py + 0.16, 0), -rad_to_deg(a) + 90.0, P.C(S.CREAM, -0.18))
		P.sandbag(mk, dir * 1.0 + Vector3(0, py + 0.33, 0), -rad_to_deg(a) + 90.0 + 15.0, P.C(S.CREAM, -0.22))
	# El canon (exagerado) en su cureña giratoria, asomando hacia delante
	var base := Vector3(0, py + 0.16, -0.1)
	mk.cyl(base, 0.48, 0.18, P.iron(0.05), 10)
	P.block(mk, base + Vector3(0, 0.18, 0), Vector3(0.62, 0.36, 0.6), P.C(S.SLATE, -0.08))
	mk.box(base + Vector3(0, 0.5, 0.05), Vector3(0.66, 0.08, 0.64), yellow)
	# Mas largo (de la culata, atras, a la boca, asomando por delante) y con
	# laton: aros, boca y una franja amarilla por encima que se lee desde arriba.
	var breech := base + Vector3(0, 0.5, -0.75)
	var muzzle := base + Vector3(0, 1.0, 1.5)
	var ax := (muzzle - breech).normalized()
	var blen := breech.distance_to(muzzle)
	mk.cyl(breech, 0.25, blen, P.C(S.SLATE, -0.05), 10, ax, 0.17, false, true)
	mk.ball(breech, 0.25, P.C(S.SLATE, -0.1))
	var brass := P.C(S.BRASS, 0.08)
	for t in [0.12, 0.42, 0.7]:
		mk.cyl(breech + ax * blen * t, 0.25 - 0.08 * t + 0.035, 0.1, brass, 10, ax)
	mk.cyl(muzzle - ax * 0.2, 0.22, 0.22, brass, 10, ax, -1.0, false, true)
	mk.cyl(muzzle + ax * 0.005, 0.12, 0.02, P.iron(-0.2), 8, ax)
	var up := ax.cross(Vector3.RIGHT).normalized()
	mk.beam(breech + ax * blen * 0.15 + up * 0.24, breech + ax * blen * 0.9 + up * 0.18, 0.08, yellow)
	# Escudo del canon
	mk.box(base + Vector3(0, 0.6, 0.38), Vector3(0.9, 0.42, 0.06), P.C(S.SLATE, -0.1))
	P.hazard(mk, base + Vector3(0, 0.78, 0.42), 0.9, 0.08, 0.02, 6)
	# Municion en la plataforma
	for k in 3:
		mk.cyl(Vector3(-0.55 + k * 0.13, py + 0.16, -0.55), 0.06, 0.28, P.C(S.BRASS, -0.05), 6)
		mk.ball(Vector3(-0.55 + k * 0.13, py + 0.44, -0.55), 0.06, P.iron(0.1), Vector3(1, 1.4, 1))
	return {}
