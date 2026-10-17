extends RefCounted
## Seto (n.º 3): seto en U abierto hacia delante, de Fantasy Town, y un
## arbolito en maceta en medio (bola recortada, lo exagerado). Piezas:
## ft:hedge-large (90) x2 detras y ft:hedge (54) x2 a los lados, estirado a lo
## largo (con cuatro sueltos pasaba de 600 triangulos con el borde de contacto).
## ~490 triangulos.
const D := preload("res://scripts/buildings/DecorMesh.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	for sx in [-0.62, 0.62]:
		kit.put(mk, "ft:hedge-large", Vector3(sx, 0, -1.05), 1.25, 0.0, {"noglow": true})
	for sx in [-1.05, 1.05]:
		kit.put(mk, "ft:hedge", Vector3(sx, 0, 0.1), 0.9, 90.0, {"noglow": true, "stretch": Vector3(2.0, 1.0, 1.0)})
	mk.cyl(Vector3(0, 0, 0.2), 0.22, 0.3, D.C(S.TERRACOTTA, -0.05), 6, Vector3.UP, 0.28)
	mk.cyl(Vector3(0, 0.3, 0.2), 0.04, 0.45, D.C(S.WOOD, -0.15), 4)
	mk.ball(Vector3(0, 0.85, 0.2), 0.3, D.C(S.GREEN, 0.02))
	return {}
