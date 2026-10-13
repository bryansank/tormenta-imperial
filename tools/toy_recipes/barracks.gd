extends RefCounted
## Cuartel (militar, acento amarillo y negro): nave de piedra con tejado de
## chapa, franja de peligro y patio de practicas con diana, armero y sacos.
## Exagerado: el porton con su marco a franjas y el galon amarillo encima, mas
## alto que el alero. El mastil con la bandera lo pone la parcela (NE).
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var yellow := P.C(S.BRASS, 0.05)
	var c := Vector3(0, 0, -0.55)
	var w := 2.6
	var d := 1.4
	var fz := c.z + d * 0.5
	P.block(mk, c, Vector3(w + 0.1, 0.14, d + 0.1), P.C(S.STONE, -0.18))
	P.block(mk, c + Vector3(0, 0.14, 0), Vector3(w, 0.95, d), P.C(S.STONE, -0.02))
	P.hazard(mk, Vector3(0, 0.95, fz + 0.02), w, 0.14, 0.05, 12)
	P.gable(mk, c + Vector3(0, 1.09, 0), w, d, 0.6, P.C(S.SLATE, -0.04), P.C(S.STONE, -0.02))
	# Chimenea del rancho (de aqui el humo)
	var mouth := P.chimney(mk, c + Vector3(-0.85, 1.0, -0.3), 0.26, 0.95, P.C(S.STONE, -0.2), P.iron())
	# Ventanas estrechas con reja
	for x in [-0.95, -0.55, 0.55, 0.95]:
		P.window(mk, Vector3(x, 0.6, fz), Vector3.BACK, 0.22, 0.34, P.iron(0.1))
	# El porton (exagerado): marco a franjas y galon encima
	var gw := 0.75
	var gh := 1.0
	P.door(mk, Vector3(0, 0.14, fz), Vector3.BACK, gw, gh, P.C(S.SLATE, 0.05), P.iron())
	for sx in [-1.0, 1.0]:
		for k in 5:
			mk.box(Vector3(sx * (gw * 0.5 + 0.1), 0.14 + 0.1 + k * 0.2, fz + 0.06), Vector3(0.14, 0.2, 0.08), yellow if k % 2 == 0 else P.iron())
	var top := Vector3(0, 0.14 + gh + 0.12, fz + 0.06)
	mk.box(top, Vector3(gw + 0.4, 0.18, 0.08), P.iron())
	P.hazard(mk, top + Vector3(0, 0, 0.05), gw + 0.34, 0.1, 0.02, 7)
	# Galon (dos cheurones) sobre un escudo
	var sh := Vector3(0, 1.62, fz + 0.12)
	mk.box(sh, Vector3(0.6, 0.55, 0.06), P.iron())
	for k in 2:
		var y := sh.y + 0.1 - k * 0.2
		mk.beam(Vector3(-0.22, y - 0.08, sh.z + 0.05), Vector3(0.0, y + 0.08, sh.z + 0.05), 0.08, yellow)
		mk.beam(Vector3(0.0, y + 0.08, sh.z + 0.05), Vector3(0.22, y - 0.08, sh.z + 0.05), 0.08, yellow)
	# Patio de practicas
	P.sandbag_wall(mk, Vector3(-1.3, 0, 0.55), Vector3(-0.55, 0, 0.55), 2)
	kit.put(mk, "kk:target", Vector3(0.9, 0, 0.75), 0.5, 0.0, {"noglow": true, "map": {S.TERRACOTTA: S.BRASS, S.CREAM: S.CREAM}})
	kit.put(mk, "kk:weaponrack", Vector3(-0.9, 0, 0.95), 0.45, 0.0, {"noglow": true})
	kit.put(mk, "kk:crate_long_A", Vector3(0.2, 0, 0.95), 0.5, 0.0, {"noglow": true, "map": {S.TERRACOTTA: S.SLATE, S.BRASS: S.BRASS}})
	return {"fx": mouth}
