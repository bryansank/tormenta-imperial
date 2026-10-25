extends RefCounted
## Chatarreria (industrial, acento rojo; feat/edificios-defensa-vida). Cuerpo de
## DefenseToys (cobertizo de chapa, grua con electroiman, montones de chatarra,
## contenedor); atrezo CC0: un barril `kk:barrel` y el farol `ft:lantern` (las
## cajas de KayKit pasaban el horneado de 2.000 triangulos). Presupuesto ~1.400
## triangulos.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S
const D := preload("res://scripts/buildings/DefenseToys.gd")

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = D.build_core(mk, "scrapyard", false)
	kit.put(mk, "kk:barrel", Vector3(-1.05, 0.06, 0.95), 0.28, 0.0, {"noglow": true})
	kit.put(mk, "ft:lantern", Vector3(0.3, 0.06, -1.05), 0.22, 0.0)
	return out
