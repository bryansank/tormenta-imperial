extends RefCounted
## Fundicion (industrial, acento rojo): nave de ladrillo con lucernario en
## diente de sierra y, delante, el horno con la boca al rojo, el crisol que
## vierte y los lingotes apilados. Exagerado: la boca del horno, que ocupa
## media fachada. La chimenea alta la pone la parcela (esquina NE); el humo
## de "trabajando" sale de la del horno.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

const EMBER := Color(1.0, 0.48, 0.12)
const MOLTEN := Color(1.0, 0.72, 0.25)

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var red := P.C(S.RED)
	var brick := P.C(S.TERRACOTTA, -0.2)
	# La nave
	var c := Vector3(-0.3, 0, -0.5)
	var w := 2.1
	var d := 1.7
	P.block(mk, c, Vector3(w + 0.1, 0.14, d + 0.1), P.C(S.STONE, -0.15))
	P.block(mk, c + Vector3(0, 0.14, 0), Vector3(w, 1.2, d), brick)
	mk.box(c + Vector3(0, 1.3, 0), Vector3(w + 0.08, 0.1, d + 0.08), P.iron(0.05))
	# Diente de sierra: dos aguas cortas con su vidriera encendida
	for k in 2:
		var z0 := c.z - d * 0.5 + d * 0.25 + k * d * 0.5
		P.shed_roof(mk, Vector3(c.x, 0, z0), w, d * 0.5 - 0.02, 1.35, 1.9, P.C(S.SLATE, 0.12), 0.06, 0.1)
		# Vidriera del diente (mira atras, como en las naves de verdad)
		mk.box(Vector3(c.x, 1.6, z0 - d * 0.25 + 0.02), Vector3(w - 0.1, 0.46, 0.05), P.iron(-0.05))
		mk.box(Vector3(c.x, 1.6, z0 - d * 0.25 - 0.01), Vector3(w - 0.3, 0.34, 0.03), P.C(S.SKY, -0.2))
	# El horno delante a la derecha: bloque de piedra oscura con la boca al rojo
	var fc := Vector3(0.55, 0, 0.35)
	P.block(mk, fc, Vector3(1.4, 1.25, 1.0), P.C(S.SLATE, -0.12))
	mk.box(fc + Vector3(0, 1.0, 0.51), Vector3(1.42, 0.14, 0.04), red)
	# Boca (exagerada): arco de ladrillo y fuego sin luz
	mk.box(fc + Vector3(0, 0.5, 0.52), Vector3(0.95, 0.75, 0.06), brick.darkened(0.1))
	mk.box(fc + Vector3(0, 0.46, 0.55), Vector3(0.72, 0.56, 0.04), EMBER, true)
	mk.box(fc + Vector3(0, 0.4, 0.57), Vector3(0.48, 0.32, 0.03), MOLTEN, true)
	mk.box(fc + Vector3(0, 0.85, 0.56), Vector3(1.0, 0.1, 0.08), P.iron())
	# Chimenea del horno (de aqui el humo)
	var mouth := P.stack(mk, fc + Vector3(0.35, 1.25, -0.2), 0.16, 1.15, P.iron(0.12), red)
	# Crisol colgado de un brazo, vertiendo en la lingotera
	var arm := fc + Vector3(-0.85, 0, 0.55)
	P.post(mk, arm, 1.5, 0.1, P.iron(0.1))
	mk.beam(arm + Vector3(0, 1.45, 0), arm + Vector3(0.45, 1.45, 0), 0.08, P.iron(0.1))
	mk.beam(arm + Vector3(0.42, 1.45, 0), arm + Vector3(0.42, 1.05, 0), 0.03, P.iron(-0.1))
	mk.cyl(arm + Vector3(0.42, 0.8, 0), 0.17, 0.25, P.iron(0.05), 8, Vector3.UP, 0.21)
	mk.cyl(arm + Vector3(0.42, 1.04, 0), 0.17, 0.02, MOLTEN, 8, Vector3.UP, -1.0, true)
	mk.beam(arm + Vector3(0.55, 0.95, 0), arm + Vector3(0.62, 0.32, 0.05), 0.06, EMBER, true)
	P.block(mk, arm + Vector3(0.62, 0, 0.05), Vector3(0.45, 0.28, 0.3), P.iron(0.05))
	mk.box(arm + Vector3(0.62, 0.29, 0.05), Vector3(0.32, 0.02, 0.18), EMBER, true)
	# Lingotes apilados (uno todavia al rojo)
	var ing := Vector3(-0.95, 0, 0.9)
	for l in 3:
		for i in 3 - l:
			var col := P.C(S.CREAM, -0.25) if l < 2 else EMBER
			mk.box(ing + Vector3((i - (2 - l) * 0.5) * 0.24, 0.07 + l * 0.13, 0), Vector3(0.2, 0.12, 0.42), col, l == 2)
	kit.put(mk, "kk:barrel", Vector3(-0.35, 0, 1.15), 0.28, 0.0, {"noglow": true, "map": {S.WOOD: S.SLATE}})
	return {"fx": mouth}
