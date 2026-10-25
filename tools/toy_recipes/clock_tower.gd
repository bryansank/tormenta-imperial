extends RefCounted
## Torre del reloj (n.º 24): base, fuste y esferas propias y el tejado en punta
## de Fantasy Town. Piezas: ft:roof-high-point (44).
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D2.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "clock_tower", true)
	kit.put(mk, "ft:roof-high-point", Vector3(0, 3.9, 0), 1.9, 0.0, {"stretch": Vector3(1.0, 0.55, 1.0), "noglow": true})
	return {}
