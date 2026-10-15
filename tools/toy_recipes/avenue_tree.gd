extends RefCounted
## Arbol de paseo (n.º 4): alcorque de hierro con su tierra y cuatro bolardos,
## y el arbol alto y redondo de Fantasy Town (lo exagerado). Piezas:
## ft:tree-high-round (126). ~200 triangulos.
const D := preload("res://scripts/buildings/DecorMesh.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D.block(mk, Vector3.ZERO, Vector3(1.1, 0.08, 1.1), D.C(S.IRON, 0.08))
	D.block(mk, Vector3(0, 0.08, 0), Vector3(0.9, 0.02, 0.9), D.C(S.WOOD, -0.2))
	K.put_h(mk, kit, "ft:tree-high-round", Vector3(0, 0.08, 0), 2.8, 15.0, {"noglow": true})
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			D.block(mk, Vector3(sx * 0.62, 0, sz * 0.62), Vector3(0.07, 0.45, 0.07), D.C(S.IRON, 0.05))
	return {}
