extends RefCounted
## Fuente pequena (n.º 12): la pila cuadrada de Fantasy Town y la columnita
## propia con su taza y el chorro. Piezas: ft:fountain-square (270).
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D2.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "small_fountain", true)
	kit.put(mk, "ft:fountain-square", Vector3.ZERO, 2.3, 0.0, {"noglow": true})
	return {}
