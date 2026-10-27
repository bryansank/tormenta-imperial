extends RefCounted
## Plaza del Gobernador (n.º 28, 3x3): losas, estatua, farolas y parterres
## propios y la fuente de Fantasy Town ampliada. Piezas: ft:fountain-square (270).
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D2.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "governor_plaza", true)
	kit.put(mk, "ft:fountain-square", Vector3(0, 0.1, 0), 2.8, 0.0, {"noglow": true})
	return {}
