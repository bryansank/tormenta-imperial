extends RefCounted
## Faro / torre de vigia (militar, acento amarillo). La torre es
## `pir:tower-complete-small` pasada a piedra; encima, el fanal de UtilityToys
## (lo exagerado, encendido sin luz real) y la banderola `pir:flag-high`.
## Presupuesto ~1.000 triangulos.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S
const U := preload("res://scripts/buildings/UtilityToys.gd")

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = U.build_core(mk, "lighthouse", false)
	var base := Vector3(-0.15, 0.12, -0.2)
	var size := 1.35
	var a: AABB = kit.aabb("pir:tower-complete-small")
	var s := size / maxf(0.001, maxf(a.size.x, a.size.z))
	kit.put(mk, "pir:tower-complete-small", base, size, 0.0,
		{"noglow": true, "map": {S.SLATE: S.STONE, S.SKY: S.CREAM}})
	var top := base + Vector3(0, a.size.y * s, 0)
	U.lighthouse_lamp(mk, top)
	kit.put(mk, "pir:flag-high", Vector3(0.95, 0.12, -0.95), 0.5, 0.0, {"noglow": true})
	return out
