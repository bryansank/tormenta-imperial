extends RefCounted
## Infanteria: una escuadra de tres soldaditos de plomo sobre su peana, uno
## delante y dos detras, fusiles al frente. Exagerado: los tocados (casco de
## plato los nuestros, chaco alto los recaudadores), que son la silueta que se
## lee de lejos. ~550 triangulos.
const U := preload("res://tools/toy_recipes/units/_unit_parts.gd")

func build(mk, team, ctx: Dictionary) -> Dictionary:
	var side: String = ctx.get("side", "player")
	U.stand(mk, team, side, 0.72)
	var y := 0.11
	U.soldier(mk, team, Vector3(0.0, y, 0.28), 0.0, side, true, 1.05)
	U.soldier(mk, team, Vector3(-0.34, y, -0.2), 8.0, side, true, 1.0)
	U.soldier(mk, team, Vector3(0.34, y, -0.2), -8.0, side, true, 1.0)
	return {"muzzle": Vector3(0.05, 0.62, 0.85), "top": Vector3(0, 1.05, 0)}
