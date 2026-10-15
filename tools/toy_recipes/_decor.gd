extends RefCounted
## Ayudas de las recetas de las decoraciones baratas (feat/decoraciones-1).
## Las piezas propias (flores, pacas, llama, bandera) estan en
## scripts/buildings/DecorMesh.gd, que tambien hace la version procedural que se
## ve en el juego hasta que se hornea.

## Coloca la pieza CC0 `name` apoyada en `pos` con `height` de alto (en vez del
## lado mayor en planta que pide kit.put: farolas, arboles y mastiles son altos
## y estrechos).
static func put_h(mk, kit, name: String, pos: Vector3, height: float, rot_deg := 0.0, opts := {}) -> Transform3D:
	var a: AABB = kit.aabb(name)
	var o: Dictionary = opts.duplicate()
	o["scale"] = height / maxf(0.001, a.size.y)
	return kit.put(mk, name, pos, 0.0, rot_deg, o)
