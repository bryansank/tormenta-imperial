extends RefCounted
## Bote varado (n.º 16, costa): corro de arena y remo propios, el bote de remos
## de Pirate Kit y una roca de playa. Piezas: pir:boat-row-large (174), sur:rock-sand-a (92).
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D2.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "beached_boat", true)
	kit.put(mk, "pir:boat-row-large", Vector3(0, 0.05, -0.1), 2.3, 30.0, {"noglow": true})
	kit.put(mk, "sur:rock-sand-a", Vector3(-0.95, 0.05, 0.85), 0.6, 0.0, {"noglow": true})
	return {}
