extends RefCounted
## Deposito de combustible (industrial, acento rojo). Los tanques son
## `kn:detail-tank-large` (lo exagerado, con franja de peligro propia) y
## `kn:detail-tank`; el colector, las valvulas y la boca de carga, de
## UtilityToys; bidones `pir:barrel`. Presupuesto ~1.270 triangulos (doc 22:
## sin `fac:pipe-large-valve`, que lo dejaba justo en 1.480).
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S
const U := preload("res://scripts/buildings/UtilityToys.gd")

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = U.build_core(mk, "fuel_depot", false)
	kit.put(mk, "kn:detail-tank-large", Vector3(-0.45, 0.1, -0.35), 1.5, 0.0, {"noglow": true})
	kit.put(mk, "kn:detail-tank", Vector3(0.8, 0.1, -0.55), 0.9, 0.0, {"noglow": true})
	P.hazard(mk, Vector3(-0.45, 0.35, 0.42), 1.0, 0.12, 0.04, 6)
	kit.put(mk, "pir:barrel", Vector3(-0.9, 0.1, 0.9), 0.3, 0.0, {"noglow": true, "map": {S.WOOD: S.RED}})
	kit.put(mk, "pir:barrel", Vector3(-0.6, 0.1, 0.98), 0.3, 30.0, {"noglow": true, "map": {S.WOOD: S.RED}})
	kit.put(mk, "pir:barrel", Vector3(-0.3, 0.1, 0.9), 0.3, 60.0, {"noglow": true, "map": {S.WOOD: S.RED}})
	return out
