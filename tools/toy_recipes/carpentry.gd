extends RefCounted
## Carpinteria (industrial, acento rojo). Cuerpo de UtilityToys (cobertizo
## abierto, banco, el caballete de tablones exagerado); atrezo CC0: tablones
## `kk:resource_lumber`, palet `kk:pallet` y caja `kk:crate_open`.
## Presupuesto ~800 triangulos.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S
const U := preload("res://scripts/buildings/UtilityToys.gd")

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = U.build_core(mk, "carpentry", false)
	kit.put(mk, "kk:pallet", Vector3(-0.95, 0.1, 0.75), 0.6, 0.0, {"noglow": true})
	kit.put(mk, "kk:resource_lumber", Vector3(-0.95, 0.2, 0.75), 0.6, 90.0, {"noglow": true})
	kit.put(mk, "kk:crate_open", Vector3(0.1, 0.1, 0.95), 0.32, 20.0, {"noglow": true})
	P.trunk(mk, Vector3(-1.2, 0.25, 0.25), 0.7, 0.13, Vector3.BACK)
	return out
