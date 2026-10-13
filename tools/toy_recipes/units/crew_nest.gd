extends RefCounted
## Nido de una dotacion de torre (atrezo que la vista pone bajo su canon): media
## luna de sacos terreros por delante y un poste con la franja militar. Dice
## "esta pieza vino de una torre, no del cuartel" sin una palabra. ~200 tri.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, team, ctx: Dictionary) -> Dictionary:
	for k in 7:
		var a := PI * (0.15 + 0.7 * float(k) / 6.0)
		var dir := Vector3(cos(a), 0, sin(a))
		P.sandbag(mk, dir * 0.92, -rad_to_deg(a) + 90.0, P.C(S.CREAM, -0.2 - 0.04 * float(k % 2)))
	P.post(mk, Vector3(-0.85, 0, -0.6), 0.6, 0.08, P.iron(0.05))
	P.hazard(mk, Vector3(-0.85, 0.5, -0.55), 0.3, 0.08, 0.04, 3)
	return {}
