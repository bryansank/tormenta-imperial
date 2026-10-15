extends RefCounted
## Carro de heno (n.º 7): el carro propio de DecorMesh (madera, dos ruedas, el
## heno amontonado, lo exagerado, y dos pacas) con el saco de KayKit en vez de
## la bola de lona. ft:cart (608) y kk:wheelbarrow (396) pasaban, con el borde
## de contacto (V8), el presupuesto de una decoracion. Piezas: kk:sack (92).
## ~580 triangulos.
const D := preload("res://scripts/buildings/DecorMesh.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D._hay_cart(mk, false)
	kit.put(mk, "kk:sack", Vector3(-0.9, 0, 0.85), 0.45, 30.0)
	return {}
