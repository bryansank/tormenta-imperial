extends RefCounted
## Columna de la Tormenta (n.º 26): peana, capitel y rayo propios y la columna
## de piedra de Fantasy Town. Piezas: ft:pillar-stone (124).
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D2.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "storm_column", true)
	K.put_h(mk, kit, "ft:pillar-stone", Vector3(0, 0.75, 0), 2.4, 0.0, {"stretch": Vector3(1.5, 1.0, 1.5), "noglow": true})
	return {}
