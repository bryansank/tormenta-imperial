extends RefCounted
## Letrero de la colonia (n.º 6): el poste indicador de Survival y, al lado,
## un mastil corto; la bandera del pais la cuelga ColonyFlag3D del FlagAnchor
## (lo alto del mastil): no se hornea tela. Piezas: sur:signpost (44),
## kc:bush (72). ~170 triangulos.
const D := preload("res://scripts/buildings/DecorMesh.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	K.put_h(mk, kit, "sur:signpost", Vector3(-0.3, 0, 0.1), 1.7, 0.0)
	mk.cyl(Vector3(0.6, 0, 0), 0.05, 2.3, D.C(S.IRON, 0.05), 6)
	mk.cyl(Vector3(0.6, 2.3, 0), 0.08, 0.1, D.C(S.BRASS), 6, Vector3.UP, 0.0)
	kit.put(mk, "kc:bush", Vector3(-0.8, 0, 0.6), 0.5, 0.0, {"noglow": true})
	return {"flag": Vector3(0.6, 2.3, 0)}
