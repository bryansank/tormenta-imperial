extends RefCounted
## Escenario de feria (n.º 18): tarima, telon y candilejas propios (el escenario
## de KayKit pasa de 784) y dos estandartes verdes de Fantasy Town. Piezas: ft:banner-green (102) x2.
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D2.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "fair_stage", true)
	for x in [-1.25, 1.25]:
		kit.put(mk, "ft:banner-green", Vector3(x, 1.5, -0.86), 0.0, 90.0, {"scale": 0.9, "noglow": true})
	return {}
