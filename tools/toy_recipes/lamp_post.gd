extends RefCounted
## Farola (doc 21 §6.4, n.º 1): peana de piedra, la farola de KayKit alta (lo
## exagerado) y un farol de Kenney a sus pies. Piezas: kc:streetlight (176),
## ft:lantern (158). ~360 triangulos.
##
## Colores (--dump=kc:streetlight,ft:lantern): la farola sale casi toda STONE y
## SLATE (gris de ciudad) y pasa a IRON con el pie en SLATE; sus caras de luz
## (TERRACOTTA y BRASS, a 0,9 m) pasan a GLOW. El farol sale SLATE (cuerpo,
## pasa a IRON) con el cristal CREAM, que pasa a GLOW: se enciende como el de
## la version procedural.
const D := preload("res://scripts/buildings/DecorMesh.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D.block(mk, Vector3.ZERO, Vector3(0.6, 0.18, 0.6), D.C(S.STONE, -0.05))
	K.put_h(mk, kit, "kc:streetlight", Vector3(0, 0.18, 0), 2.7, 0.0,
		{"map": {S.STONE: S.IRON, S.TERRACOTTA: S.GLOW, S.BRASS: S.GLOW}})
	K.put_h(mk, kit, "ft:lantern", Vector3(0.55, 0, 0.5), 0.55, 30.0,
		{"map": {S.SLATE: S.IRON, S.CREAM: S.GLOW}})
	return {}
