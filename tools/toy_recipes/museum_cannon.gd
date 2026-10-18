extends RefCounted
## Canon de museo (n.º 22): peana, placa y balas propias y el canon de Pirate
## Kit. Piezas: pir:cannon (232).
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D2.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "museum_cannon", true)
	kit.put(mk, "pir:cannon", Vector3(0, 0.44, -0.05), 1.55, 0.0, {"noglow": true})
	return {}
