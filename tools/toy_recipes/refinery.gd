extends RefCounted
## Refineria (industrial, acento rojo): la columna de destilacion, dos depositos,
## una cisterna, tuberias con valvulas rojas y la caseta de control. Exagerado:
## la columna, la pieza mas alta del barrio, con aros rojos y antorcha arriba
## (de ahi el humo). El colector con la gran valvula lo pone la parcela (SE).
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var red := P.C(S.RED)
	var steel := P.C(S.SLATE, 0.08)
	var copper := P.C(S.TERRACOTTA, -0.15)
	# Losa de hormigon
	P.block(mk, Vector3.ZERO, Vector3(2.75, 0.1, 2.75), P.C(S.STONE, -0.15))
	# La columna (exagerada)
	var cc := Vector3(-0.75, 0.1, -0.6)
	var ch := 3.1
	mk.cyl(cc, 0.42, 0.25, P.iron(0.05), 10)
	mk.cyl(cc + Vector3(0, 0.25, 0), 0.34, ch - 0.25, steel, 10)
	for t in [0.3, 0.55, 0.8]:
		mk.cyl(cc + Vector3(0, ch * t, 0), 0.37, 0.12, red, 10)
	for t in [0.42, 0.68]:
		mk.cyl(cc + Vector3(0, ch * t, 0), 0.55, 0.05, P.iron(0.1), 10)
	mk.ball(cc + Vector3(0, ch, 0), 0.34, steel, Vector3(1, 0.5, 1))
	mk.cyl(cc + Vector3(0, ch + 0.1, 0), 0.06, 0.45, P.iron(0.1), 6)
	var flare := cc + Vector3(0, ch + 0.58, 0)
	mk.cyl(cc + Vector3(0, ch + 0.5, 0), 0.08, 0.1, Color(1.0, 0.55, 0.15), 6, Vector3.UP, 0.02, true)
	# Escalera por delante de la columna
	for sx in [-1.0, 1.0]:
		mk.box(cc + Vector3(sx * 0.1, ch * 0.45, 0.4), Vector3(0.03, ch * 0.85, 0.03), P.iron(0.15))
	for k in 9:
		mk.box(cc + Vector3(0, 0.25 + k * 0.3, 0.4), Vector3(0.2, 0.025, 0.025), P.iron(0.15))
	# Dos depositos verticales, crema con aro rojo
	P.tank(mk, Vector3(0.6, 0.1, -0.75), 0.5, 1.1, P.C(S.CREAM, -0.05), red)
	P.tank(mk, Vector3(0.95, 0.1, 0.2), 0.36, 0.8, P.C(S.CREAM, -0.08), red)
	# Cisterna horizontal de Kenney, a la paleta
	kit.put(mk, "kn:detail-tank", Vector3(-0.35, 0.1, 0.85), 1.05, 0.0, {"noglow": true, "map": {S.TERRACOTTA: S.RED}})
	# Tuberias: columna -> deposito grande -> deposito chico, con valvulas
	P.pipe_run(mk, [cc + Vector3(0.34, 1.6, 0), Vector3(0.1, 1.7, -0.6), Vector3(0.1, 1.0, -0.6), Vector3(0.1, 1.0, -0.75) + Vector3(0.0, 0, 0)], 0.07, copper)
	P.pipe_run(mk, [Vector3(0.6, 0.45, -0.25), Vector3(0.6, 0.45, 0.2), Vector3(0.6, 0.45, 0.2)], 0.06, copper)
	P.pipe_run(mk, [cc + Vector3(0.0, 0.5, 0.34), Vector3(-0.75, 0.5, 0.35), Vector3(0.35, 0.5, 0.35), Vector3(0.6, 0.5, 0.2)], 0.06, copper)
	P.valve(mk, Vector3(-0.2, 0.5, 0.47), 0.17, red)
	P.valve(mk, Vector3(0.1, 1.25, -0.46), 0.15, red)
	P.valve(mk, Vector3(0.6, 0.45, 0.0) + Vector3(0.14, 0, 0), 0.13, red, Vector3.RIGHT)
	# Caseta de control con ojo de buey encendido
	var hc := Vector3(-1.05, 0.1, 0.45)
	P.block(mk, hc, Vector3(0.55, 0.65, 0.55), P.C(S.SLATE, -0.05))
	mk.box(hc + Vector3(0, 0.7, 0), Vector3(0.65, 0.08, 0.65), red)
	P.porthole(mk, hc + Vector3(0, 0.38, 0.28), Vector3.BACK, 0.11, P.iron(0.1))
	kit.put(mk, "kk:barrel", Vector3(1.15, 0.1, 1.05), 0.28, 0.0, {"noglow": true, "map": {S.WOOD: S.RED, S.STONE: S.IRON}})
	return {"fx": flare}
