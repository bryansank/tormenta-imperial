extends RefCounted
## Telegrafo (civico, acento laton; feat/edificios-defensa-vida). Cuerpo de
## DefenseToys (oficina de ladrillo, mastil de celosia con aisladores, lampara
## roja de senales, hilos); atrezo CC0: la farola `kc:streetlight` delante, el
## farol `ft:lantern` y una caja `kk:crate_A_small` de rollos de cable.
## Presupuesto ~1.200 triangulos.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S
const D := preload("res://scripts/buildings/DefenseToys.gd")

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = D.build_core(mk, "telegraph", false)
	kit.put(mk, "kc:streetlight", Vector3(1.0, 0.06, 0.95), 0.5, 0.0, {"noglow": true})
	kit.put(mk, "ft:lantern", Vector3(-1.05, 0.06, 1.0), 0.22, 0.0)
	kit.put(mk, "kk:crate_A_small", Vector3(0.75, 0.06, 0.2), 0.3, 15.0, {"noglow": true})
	return out
