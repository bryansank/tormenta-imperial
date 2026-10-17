extends RefCounted
## Palmeras (n.º 15): corro de arena propio, una palmera de Pirate y otra mas
## baja e inclinada, propia (dos de Pirate pasaban el presupuesto; el parche de
## arena de Pirate tambien, con el borde de contacto). Solo en la costa
## (PlacementRules.needs_shore). Piezas: pir:palm-straight (338). ~590 triangulos.
const D := preload("res://scripts/buildings/DecorMesh.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	mk.cyl(Vector3.ZERO, 1.3, 0.05, D.C(S.CREAM, -0.08), 8)
	K.put_h(mk, kit, "pir:palm-straight", Vector3(-0.45, 0, -0.3), 2.6, 25.0, {"noglow": true})
	D._palm(mk, Vector3(0.55, 0.03, 0.35), Vector3(0.35, 1, 0.2).normalized(), 1.8, false)
	return {}
