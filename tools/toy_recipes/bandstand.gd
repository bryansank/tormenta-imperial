extends RefCounted
## Quiosco de musica (n.º 14): tarima, columnas y tuba propias y el tejado en
## punta de Fantasy Town, pasado a rojo. Piezas: ft:roof-point (44).
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D2.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "bandstand", true)
	kit.put(mk, "ft:roof-point", Vector3(0, 1.95, 0), 3.0, 0.0, {"stretch": Vector3(1.0, 0.6, 1.0), "map": {S.GREEN: S.RED}, "noglow": true})
	return {}
