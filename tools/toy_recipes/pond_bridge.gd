extends RefCounted
## Estanque con puente (n.º 20): todo propio (estanque, nenufares, juncos y el
## puente en arco; el de KayKit pasa de 604 y las plantas de agua no cabian).
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")

func build(mk, _kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "pond_bridge", false)
	return {}
