extends RefCounted
## Mastil con bandera (n.º 11): peana de dos escalones propia y el mastil alto
## con bandera de Pirate (lo exagerado). FlagAnchor arriba para la bandera del
## pais (ColonyFlag3D, pendiente). Piezas: pir:flag-high (144). ~170 triangulos.
## Ojo en el horneado: mirar con --dump=pir:flag-high a que casilla cae la tela
## y, si sale negra (IRON), pasarla a RED con "map".
const D := preload("res://scripts/buildings/DecorMesh.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D.block(mk, Vector3.ZERO, Vector3(1.0, 0.2, 1.0), D.C(S.STONE, -0.08))
	D.block(mk, Vector3(0, 0.2, 0), Vector3(0.6, 0.2, 0.6), D.C(S.STONE, 0.04))
	var xf := K.put_h(mk, kit, "pir:flag-high", Vector3(0, 0.4, 0), 3.4, 0.0, {"noglow": true})
	var top: float = (xf * kit.aabb("pir:flag-high")).end.y
	return {"flag": Vector3(0, top, 0)}
