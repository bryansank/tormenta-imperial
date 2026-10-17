extends RefCounted
## Taberna (civico, acento laton). Cuerpo de UtilityToys (dos plantas con
## entramado, letrero exagerado con la jarra, chimenea); el atrezo CC0:
## barriles `pir:barrel`, el farol `ft:lantern`. Presupuesto ~1.000 triangulos
## (doc 22 §3.1: nunca el `kk:building_tavern`, 2.992).
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S
const U := preload("res://scripts/buildings/UtilityToys.gd")

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = U.build_core(mk, "tavern", false)
	var fz := -0.35 + 0.75
	kit.put(mk, "pir:barrel", Vector3(-0.95, 0, fz + 0.95), 0.3, 0.0, {"noglow": true})
	kit.put(mk, "pir:barrel", Vector3(-0.62, 0, fz + 1.0), 0.3, 40.0, {"noglow": true})
	kit.put(mk, "ft:lantern", Vector3(1.15, 0, fz + 1.0), 0.22, 0.0)
	return out
