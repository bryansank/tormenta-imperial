extends RefCounted
## Marca del jefe (atrezo que la vista pone sobre la unidad): aro de laton
## alrededor de la peana y un estandarte alto con banderin morado de la Regencia.
## Es lo mismo que el halo de laton del tablero 2D (UITheme.mark_boss): el
## jefe se distingue de lejos por la silueta del estandarte. ~190 triangulos.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S
const U := preload("res://tools/toy_recipes/units/_unit_parts.gd")

func build(mk, team, ctx: Dictionary) -> Dictionary:
	P.ring(mk, Vector3(0, 0.12, 0), 0.9, 0.07, P.C(S.BRASS, 0.08), 12)
	var base := Vector3(-0.62, 0.0, -0.55)
	mk.cyl(base, 0.05, 1.7, P.iron(0.1), 6)
	mk.ball(base + Vector3(0, 1.75, 0), 0.08, P.C(S.BRASS, 0.1))
	team.box(base + Vector3(0.26, 1.48, 0), Vector3(0.46, 0.36, 0.04), U.T(0.0))
	mk.box(base + Vector3(0.26, 1.28, 0), Vector3(0.46, 0.06, 0.05), P.C(S.BRASS, 0.0))
	return {"top": Vector3(0, 1.9, 0)}
