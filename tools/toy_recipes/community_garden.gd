extends RefCounted
## Huerto vecinal (n.º 10): todo propio (bancales, hileras, valla y azada): la
## valla de Survival Kit pasaba el presupuesto con el borde de contacto.
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")

func build(mk, _kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "community_garden", false)
	return {}
