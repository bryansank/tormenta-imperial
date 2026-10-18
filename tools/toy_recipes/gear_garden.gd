extends RefCounted
## Jardin de engranajes (n.º 17): dos engranajes de Factory Kit de pie y pasados
## a laton, el pequeno propio, la peana y los setos. Piezas: fac:cog-a (160), fac:cog-c (160).
const D2 := preload("res://scripts/buildings/DecorMesh2.gd")
const K := preload("res://tools/toy_recipes/_decor.gd")
const S := D2.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	D2.build(mk, "gear_garden", true)
	_cog(mk, kit, "fac:cog-a", Vector3(-0.55, 0.31, -0.1), 1.7)
	_cog(mk, kit, "fac:cog-c", Vector3(0.78, 0.31, -0.1), 1.24)
	return {}

## El engranaje de pie (la pieza viene tumbada: se gira 90 grados sobre X),
## con `size` de diametro y el borde de abajo apoyado en `base`.
func _cog(mk, kit, name: String, base: Vector3, size: float) -> void:
	var a: AABB = kit.aabb(name)
	var s := size / maxf(0.001, maxf(a.size.x, a.size.z))
	var b := Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(s, s, s))
	var xf := Transform3D(b, base + Vector3(0, size * 0.5, 0) - b * a.get_center())
	kit.add(mk, name, xf, {"map": {S.SLATE: S.BRASS}, "noglow": true})
