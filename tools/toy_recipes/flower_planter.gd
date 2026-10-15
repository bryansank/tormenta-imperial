extends RefCounted
## Macetero (n.º 5): tres macetas de barro propias, cada una con una mata de
## KayKit y flores de colores (no hay flores CC0: cubitos, doc 22 §3.5). Sin el
## taburete de Fantasy Town, que pasaba el presupuesto. Piezas: kc:bush (72) x3.
## ~400 triangulos.
const D := preload("res://scripts/buildings/DecorMesh.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	var pots := [[Vector3(-0.55, 0, 0.25), 0.36, 0.5], [Vector3(0.5, 0, 0.35), 0.3, 0.38], [Vector3(0.05, 0, -0.5), 0.42, 0.62]]
	var i := 0
	for p in pots:
		var base: Vector3 = p[0]
		var r: float = p[1]
		var h: float = p[2]
		mk.cyl(base, r * 0.8, h, D.C(S.TERRACOTTA, -0.04 + 0.03 * i), 8, Vector3.UP, r)
		kit.put(mk, "kc:bush", base + Vector3(0, h - 0.02, 0), r * 1.7, 40.0 * i, {"noglow": true})
		D.flowers(mk, base + Vector3(0, h + 0.3, 0), r * 0.55, 3 + (i % 2), i)
		i += 1
	return {}
