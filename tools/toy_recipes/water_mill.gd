extends RefCounted
## Molino de agua (n.º 21): casita, canal y rueda propios (la rueda de Fantasy
## Town pesa 600 sola) y dos sacos de harina de KayKit en la puerta. Piezas: kk:sack (92) x2.
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D2.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "water_mill", false)
	kit.put(mk, "kk:sack", Vector3(-0.05, 0, 0.95), 0.45, 15.0, {"noglow": true})
	kit.put(mk, "kk:sack", Vector3(-0.55, 0, 1.0), 0.4, -30.0, {"noglow": true})
	return {}
