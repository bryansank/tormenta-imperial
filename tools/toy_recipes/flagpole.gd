extends RefCounted
## Mastil con bandera (n.º 11): peana de dos escalones propia y el mastil alto
## de Pirate (lo exagerado), SIN su tela: la bandera del pais la cuelga
## ColonyFlag3D del FlagAnchor (lo alto del palo), como en el Nucleo y el
## Cuartel General. Piezas: pir:flag-high (144, sin la tela CREAM, ~40).
##
## Colores (--dump=pir:flag-high): el palo sale WOOD y pasa a IRON (el hierro de
## la farola y del mastil procedural), la abrazadera de la base sale SLATE y
## pasa a BRASS; la tela es la casilla CREAM y se salta ("skip").
const D := preload("res://scripts/buildings/DecorMesh.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D.S
const PIECE := "pir:flag-high"

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D.block(mk, Vector3.ZERO, Vector3(1.0, 0.2, 1.0), D.C(S.STONE, -0.08))
	D.block(mk, Vector3(0, 0.2, 0), Vector3(0.6, 0.2, 0.6), D.C(S.STONE, 0.04))
	var xf := K.put_h(mk, kit, PIECE, Vector3(0, 0.4, 0), 3.4, 0.0,
		{"noglow": true, "skip": [S.CREAM], "map": {S.WOOD: S.IRON, S.SLATE: S.BRASS}})
	# Lo alto del palo (sin la tela, la pieza acaba ahi).
	var top: float = (xf * kit.slot_aabb(PIECE, S.WOOD)).end.y
	# Remate de laton encima: la bandera cuelga justo debajo.
	mk.cyl(Vector3(0, top, 0), 0.1, 0.16, D.C(S.BRASS), 6, Vector3.UP, 0.0)
	return {"flag": Vector3(0, top, 0)}
