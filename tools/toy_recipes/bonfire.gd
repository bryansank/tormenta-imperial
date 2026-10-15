extends RefCounted
## Hoguera (n.º 8): corro de piedras propio, el soporte de fuego de Survival,
## la llama encendida (brillo, sin luz real) y lena para sentarse a cada lado.
## Piezas: sur:campfire-stand (76), sur:resource-wood (64) x2. ~320 triangulos.
const D := preload("res://scripts/buildings/DecorMesh.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	for i in 8:
		var a := TAU * float(i) / 8.0
		mk.box(Vector3(cos(a) * 0.55, 0.08, sin(a) * 0.55), Vector3(0.24, 0.16, 0.2), D.C(S.STONE, -0.08 + 0.04 * (i % 3)))
	D.block(mk, Vector3.ZERO, Vector3(0.8, 0.03, 0.8), D.C(S.IRON, -0.1))
	kit.put(mk, "sur:campfire-stand", Vector3(0, 0.03, 0), 1.1, 0.0, {"noglow": true})
	D.flame(mk, Vector3(0, 0.05, 0), 0.26, 0.65)
	kit.put(mk, "sur:resource-wood", Vector3(-0.1, 0, 1.1), 1.0, 0.0, {"noglow": true})
	kit.put(mk, "sur:resource-wood", Vector3(0.1, 0, -1.1), 1.0, 180.0, {"noglow": true})
	return {}
