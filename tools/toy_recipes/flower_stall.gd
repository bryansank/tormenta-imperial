extends RefCounted
## Puesto de flores (n.º 9, feat/decoraciones-y-trafico): todo propio (mostrador,
## toldo a rayas, cajas y cubos de flores; no hay flores CC0). ~490 triangulos.
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D2.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "flower_stall", false)
	return {}
