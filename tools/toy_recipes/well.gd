extends RefCounted
## Pozo (civico, acento laton). Cuerpo de UtilityToys (brocal, tejadillo,
## bomba de laton exagerada, liston de cubos); atrezo CC0: el cubo de agua
## `kk:bucket_water` y un barril `kk:barrel`. Los cubos rojos son propios.
## No se usa `kk:building_well_*`: trae su loseta hexagonal y es 1x1 (doc 22).
## Presupuesto ~700 triangulos.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S
const U := preload("res://scripts/buildings/UtilityToys.gd")

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = U.build_core(mk, "well", false)
	for k in 3:
		mk.cyl(Vector3(-1.1 + k * 0.25, 0.42, 0.88), 0.08, 0.18, P.C(S.RED), 8, Vector3.UP, 0.1)
	kit.put(mk, "kk:bucket_water", Vector3(0.2, 0.08, 0.55), 0.26, 0.0, {"noglow": true})
	kit.put(mk, "kk:barrel", Vector3(0.95, 0.08, -0.8), 0.3, 0.0, {"noglow": true})
	return out
