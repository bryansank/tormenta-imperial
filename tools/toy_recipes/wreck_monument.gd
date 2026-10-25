extends RefCounted
## Pecio monumento (n.º 25, costa): todo propio (el pecio de Pirate Kit pasa de
## 2.282; su cofre, de 232, no cabia).
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")

func build(mk, _kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "wreck_monument", false)
	return {}
