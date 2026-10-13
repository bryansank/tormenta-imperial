extends RefCounted
## Aserradero (industrial, acento rojo): cobertizo ABIERTO, tejado de chapa de
## una sola agua sobre postes, sin pared delante: se ve la mesa con el tronco y
## la sierra. Fuera, la maquina de vapor con su volante, tablones y troncos.
## Exagerado: la hoja de la sierra (buje rojo), casi tan alta como el alero.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var red := P.C(S.RED)
	var post := P.wood(-0.15)
	var c := Vector3(-0.3, 0, -0.35)
	var sw := 2.0
	var sd := 1.75
	# Tarima
	P.block(mk, c, Vector3(sw + 0.1, 0.1, sd + 0.1), P.wood(-0.25))
	# Pared de tablas solo atras y media a la izquierda (el frente, abierto)
	P.block(mk, c + Vector3(0, 0.1, -sd * 0.5 + 0.05), Vector3(sw, 1.1, 0.1), P.wood(-0.05))
	P.block(mk, c + Vector3(-sw * 0.5 + 0.05, 0.1, -0.35), Vector3(0.1, 0.7, sd - 0.7), P.wood(-0.05))
	# Postes atras (altos) bajo la media cubierta de chapa; delante, solo dos
	# postes de esquina con las cerchas al aire: ninguna viga corta la vista de
	# la sierra desde la camara.
	var rz := c.z - sd * 0.5 + 0.5
	for sx in [-1.0, 0.0, 1.0]:
		P.post(mk, c + Vector3(sx * (sw * 0.5 - 0.06), 0.1, -sd * 0.5 + 0.06), 2.0, 0.13, post)
		P.post(mk, Vector3(c.x + sx * (sw * 0.5 - 0.06), 0.1, rz + 0.45), 1.75, 0.12, post)
	P.shed_roof(mk, Vector3(c.x, 0, rz), sw, 1.0, 2.15, 1.85, P.C(S.SLATE, 0.05))
	mk.box(Vector3(c.x, 1.8, rz + 0.58), Vector3(sw + 0.3, 0.08, 0.06), red)
	for sx in [-1.0, 1.0]:
		P.post(mk, c + Vector3(sx * (sw * 0.5 - 0.06), 0.1, sd * 0.5 - 0.06), 1.0, 0.12, post)
		mk.beam(c + Vector3(sx * (sw * 0.5 - 0.06), 1.08, sd * 0.5 - 0.06), Vector3(c.x + sx * (sw * 0.5 - 0.06), 1.8, rz + 0.45), 0.09, post)
	# Mesa de la sierra, el tronco y el tablon recien cortado
	var tz := c.z + 0.6
	P.block(mk, Vector3(c.x, 0.1, tz), Vector3(1.7, 0.45, 0.4), P.wood(0.0))
	mk.box(Vector3(c.x, 0.57, tz), Vector3(1.78, 0.05, 0.46), P.wood(0.1))
	P.trunk(mk, Vector3(c.x - 0.45, 0.78, tz), 0.85, 0.18)
	mk.box(Vector3(c.x + 0.6, 0.63, tz), Vector3(0.55, 0.06, 0.3), P.wood(0.15))
	# La sierra (exagerada): hoja de acero dentada, buje rojo
	var blade := Vector3(c.x + 0.1, 0.98, tz + 0.02)
	P.gear(mk, blade, 0.6, 0.06, P.C(S.CREAM, -0.15), Vector3.BACK, 18)
	mk.cyl(blade + Vector3(0, 0, -0.12), 0.13, 0.3, red, 8, Vector3.BACK, -1.0, false, true)
	mk.box(blade + Vector3(0, 0.25, -0.18), Vector3(0.3, 0.08, 0.08), P.iron())
	# Maquina de vapor con volante, a la derecha, y la correa hasta la sierra
	var eng := Vector3(1.05, 0, -0.75)
	P.block(mk, eng, Vector3(0.5, 0.2, 0.9), P.iron(0.05))
	mk.cyl(eng + Vector3(0, 0.45, -0.42), 0.24, 0.8, red, 10, Vector3.BACK, -1.0, false, true)
	P.stack(mk, eng + Vector3(0, 0.6, -0.25), 0.08, 0.95, P.iron(0.1), P.C(S.BRASS))
	P.wheel(mk, eng + Vector3(-0.32, 0.55, 0.25), 0.3, P.iron(0.15), Vector3.RIGHT, 6, 0.07)
	mk.beam(eng + Vector3(-0.36, 0.84, 0.25), blade + Vector3(0.3, 0.05, -0.15), 0.04, P.iron(-0.1))
	# Tablones y troncos fuera
	P.plank_stack(mk, Vector3(0.8, 0, 0.95), 0.95, 0.75, 4)
	kit.put(mk, "kk:resource_lumber", Vector3(-0.75, 0, 1.0), 1.1, 0.0, {"noglow": true})
	kit.put(mk, "kk:tree_single_A_cut", Vector3(0.05, 0, 1.05), 0.26, 0.0, {"noglow": true})
	return {"fx": blade + Vector3(0, 0.45, 0.1)}
