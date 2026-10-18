extends RefCounted
## Bastion (militar, acento amarillo; feat/edificios-defensa-vida). Cuerpo de
## DefenseToys (sillares, almenas, fleje de laton, sacos, franja de peligro);
## atrezo CC0: dos tramos de `kk:fence_stone_straight` como antepecho detras del
## camino de ronda, la banderola `pir:flag-high` y el farol `ft:lantern`.
## ~1.500 triangulos horneado (los dos tramos de valla de KayKit pesan).
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S
const D := preload("res://scripts/buildings/DefenseToys.gd")

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = D.build_core(mk, "bastion", false)
	var top := D.BASTION_H + 0.06
	for sx in [-0.9, 0.9]:
		kit.put(mk, "kk:fence_stone_straight", Vector3(sx, top, -0.4), 0.9, 0.0, {"noglow": true})
	kit.put(mk, "pir:flag-high", Vector3(1.55, top, -0.3), 0.45, 0.0, {"noglow": true})
	kit.put(mk, "ft:lantern", Vector3(-1.55, top, -0.3), 0.2, 0.0)
	return out
