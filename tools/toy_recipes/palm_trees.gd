extends RefCounted
## Palmeras (n.º 15): parche de arena de Pirate, una palmera de Pirate y otra
## mas baja e inclinada, propia (dos de Pirate pasaban el presupuesto).
## Piezas: pir:patch-sand (108), pir:palm-straight (338). ~590 triangulos.
const D := preload("res://scripts/buildings/DecorMesh.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	kit.put(mk, "pir:patch-sand", Vector3.ZERO, 2.6, 0.0, {"noglow": true})
	K.put_h(mk, kit, "pir:palm-straight", Vector3(-0.45, 0, -0.3), 2.6, 25.0, {"noglow": true})
	D._palm(mk, Vector3(0.55, 0.03, 0.35), Vector3(0.35, 1, 0.2).normalized(), 1.8)
	return {}
