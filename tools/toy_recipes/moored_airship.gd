extends RefCounted
## Dirigible amarrado (n.º 27): mastil de celosia y dirigible propios (no hay
## dirigible CC0) y un barril de combustible de Pirate Kit. Piezas: pir:barrel (148).
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D2.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "moored_airship", true)
	kit.put(mk, "pir:barrel", Vector3(-0.5, 0.15, 0.6), 0.42, 0.0, {"noglow": true})
	return {}
