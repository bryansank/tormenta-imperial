extends RefCounted
## Arco de entrada (n.º 13): pilares de piedra de Fantasy Town, dintel y placa
## propios y el estandarte rojo colgando. Piezas: ft:pillar-stone (124) x2, ft:banner-red (98).
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D2.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "entrance_arch", true)
	for sx in [-1.0, 1.0]:
		K.put_h(mk, kit, "ft:pillar-stone", Vector3(sx * 1.05, 0.3, 0), 2.2, 0.0, {"stretch": Vector3(1.6, 1.0, 1.6), "noglow": true})
	kit.put(mk, "ft:banner-red", Vector3(0, 1.52, 0), 0.0, 90.0, {"scale": 1.1, "noglow": true})
	return {}
