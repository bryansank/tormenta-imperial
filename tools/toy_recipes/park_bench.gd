extends RefCounted
## Banco (n.º 2): dos bancos de KayKit frente a frente, una mata en maceta en
## medio y una papelera. Piezas: kc:bench (44) x2, kc:bush (72). ~250 triangulos.
const D := preload("res://scripts/buildings/DecorMesh.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	kit.put(mk, "kc:bench", Vector3(0, 0, -0.75), 1.4, 0.0)
	kit.put(mk, "kc:bench", Vector3(0, 0, 0.75), 1.4, 180.0)
	mk.cyl(Vector3.ZERO, 0.24, 0.32, D.C(S.TERRACOTTA, -0.05), 6, Vector3.UP, 0.3)
	kit.put(mk, "kc:bush", Vector3(0, 0.3, 0), 0.6, 20.0, {"noglow": true})
	mk.cyl(Vector3(1.0, 0, 0), 0.14, 0.5, D.C(S.SLATE), 6)
	return {}
