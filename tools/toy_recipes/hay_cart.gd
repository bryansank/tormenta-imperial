extends RefCounted
## Carro de heno (n.º 7): la carretilla de KayKit con el heno amontonado (lo
## exagerado), un saco y dos pacas. ft:cart (608) pasaba el presupuesto de una
## decoracion. Piezas: kk:wheelbarrow (396), kk:sack (92). ~590 triangulos.
const D := preload("res://scripts/buildings/DecorMesh.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	var xf: Transform3D = kit.put(mk, "kk:wheelbarrow", Vector3(-0.1, 0, 0), 1.6, 0.0)
	var top: float = (xf * kit.aabb("kk:wheelbarrow")).end.y
	mk.ball(Vector3(-0.1, top, 0), 0.5, D.C(S.BRASS, -0.02), Vector3(1.1, 0.6, 0.8))
	kit.put(mk, "kk:sack", Vector3(-0.95, 0, 0.8), 0.45, 30.0)
	D.hay_bale(mk, Vector3(0.45, 0, -0.95), Vector3(0.8, 0.4, 0.5), 10.0)
	D.hay_bale(mk, Vector3(0.9, 0, 0.8), Vector3(0.8, 0.4, 0.5), -25.0)
	return {}
