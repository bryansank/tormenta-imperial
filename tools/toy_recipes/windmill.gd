extends RefCounted
## Molino (residencial, acento verde). El cuerpo es el de UtilityToys (torre
## encalada, caperuza, cobertizo del grano); aqui se ponen encima las piezas
## CC0: las aspas `ft:windmill` (lo exagerado), sacos `kk:sack` y el granero
## `kk:building_grain`. Presupuesto ~1.050 triangulos (doc 22 §3.1).
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S
const U := preload("res://scripts/buildings/UtilityToys.gd")

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = U.build_core(mk, "windmill", false)
	# Las aspas: la pieza va en su plano XY, de cara a +Z; se apoya de forma que
	# su centro caiga en el buje (fit apoya la base: se baja medio alto).
	var span := U.WINDMILL_BLADE * 2.2
	var a: AABB = kit.aabb("ft:windmill")
	var s := span / maxf(0.001, maxf(a.size.x, a.size.z))
	var hub: Vector3 = U.WINDMILL_HUB
	kit.put(mk, "ft:windmill", Vector3(hub.x, hub.y - a.size.y * s * 0.5, hub.z + 0.04), span, 0.0,
		{"noglow": true, "map": {S.TERRACOTTA: S.WOOD}})
	kit.put(mk, "kk:building_grain", Vector3(-0.85, 0, 0.75), 0.6, 20.0, {"noglow": true})
	kit.put(mk, "kk:sack", Vector3(-0.4, 0, 0.95), 0.32, 15.0, {"noglow": true})
	kit.put(mk, "kk:sack", Vector3(-0.15, 0, 1.05), 0.3, -30.0, {"noglow": true})
	kit.put(mk, "kk:barrel", Vector3(0.55, 0, 1.0), 0.3, 0.0, {"noglow": true})
	return out
