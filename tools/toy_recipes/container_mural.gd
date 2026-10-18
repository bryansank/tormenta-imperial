extends RefCounted
## Mural de contenedores (n.º 23): todo propio (los contenedores de City Kit
## Industrial pesan 402 cada uno: no caben dos y el mural).
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")

func build(mk, _kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "container_mural", false)
	return {}
