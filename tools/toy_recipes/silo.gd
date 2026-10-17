extends RefCounted
## Silo (residencial). Cuerpo de UtilityToys (los dos silos de chapa, la
## tolva y la caseta de carga) con el atrezo CC0: sacos `kk:sack`, caja
## `kk:crate_A_small` y un deposito pequeno `kn:detail-tank` para el agua.
## Presupuesto ~900 triangulos.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S
const U := preload("res://scripts/buildings/UtilityToys.gd")

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = U.build_core(mk, "silo", false)
	kit.put(mk, "kk:sack", Vector3(-0.6, 0.12, 0.8), 0.32, 10.0, {"noglow": true})
	kit.put(mk, "kk:sack", Vector3(-0.88, 0.12, 0.62), 0.3, -25.0, {"noglow": true})
	kit.put(mk, "kk:sack", Vector3(-0.36, 0.12, 0.98), 0.3, 40.0, {"noglow": true})
	kit.put(mk, "kk:crate_A_small", Vector3(-1.05, 0.12, 0.98), 0.28, 15.0, {"noglow": true})
	kit.put(mk, "kn:detail-tank", Vector3(1.05, 0.12, -1.0), 0.45, 0.0, {"noglow": true, "map": {S.SKY: S.SLATE}})
	return out
