extends RefCounted
## Carpa de feria (n.º 19): la tienda de lona de Survival Kit, pasada a crema y
## rojo, con mastil, banderines y vientos propios. Piezas: sur:tent-canvas (148).
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D2.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "fair_tent", true)
	kit.put(mk, "sur:tent-canvas", Vector3.ZERO, 2.7, 0.0, {"map": {S.WOOD: S.CREAM, S.TERRACOTTA: S.RED}, "noglow": true})
	return {}
