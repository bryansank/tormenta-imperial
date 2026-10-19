extends RefCounted
## Mina de oro (industrial, acento rojo): colina de roca con la boca apuntalada,
## railes que salen con la vagoneta cargada de pepitas, el castillete y la
## caldera que tira del cable. Exagerado: la rueda roja del castillete.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var red := P.C(S.RED)
	var rock := P.C(S.STONE, -0.12)
	var timber := P.wood(-0.12)
	# La colina
	mk.cyl(Vector3(-0.35, 0, -0.42), 0.98, 1.25, rock, 7, Vector3.UP, 0.42)
	mk.cyl(Vector3(0.45, 0, -0.85), 0.5, 0.85, rock.darkened(0.06), 6, Vector3.UP, 0.25)
	mk.cyl(Vector3(-0.95, 0, -0.95), 0.4, 0.55, rock.lightened(0.05), 6, Vector3.UP, 0.15)
	kit.put(mk, "kk:rock_single_E", Vector3(-1.05, 0, 0.1), 0.5, 20.0, {"noglow": true})
	# La boca: hueco oscuro, marco de vigas y farol
	var mz := 0.28
	P.block(mk, Vector3(-0.35, 0, mz - 0.25), Vector3(0.62, 0.78, 0.5), P.iron(-0.05))
	for sx in [-1.0, 1.0]:
		P.post(mk, Vector3(-0.35 + sx * 0.37, 0, mz + 0.02), 0.9, 0.13, timber)
	mk.box(Vector3(-0.35, 0.92, mz + 0.02), Vector3(0.95, 0.15, 0.17), timber)
	mk.box(Vector3(-0.35, 1.04, mz + 0.05), Vector3(0.5, 0.12, 0.06), red)
	mk.ball(Vector3(0.12, 0.75, mz + 0.12), 0.07, P.C(S.GLOW), Vector3.ONE, true)
	# Railes hasta el borde
	for sx in [-1.0, 1.0]:
		mk.box(Vector3(-0.35 + sx * 0.16, 0.04, mz + 0.55), Vector3(0.05, 0.05, 1.0), P.iron(0.15))
	for k in 5:
		mk.box(Vector3(-0.35, 0.015, mz + 0.15 + k * 0.21), Vector3(0.5, 0.03, 0.08), timber)
	# Vagoneta con pepitas
	var cart := Vector3(-0.35, 0.12, mz + 0.75)
	mk.box(cart + Vector3(0, 0.15, 0), Vector3(0.44, 0.26, 0.52), P.iron(0.12))
	mk.box(cart + Vector3(0, 0.27, 0), Vector3(0.48, 0.04, 0.56), red)
	for k in 5:
		mk.ball(cart + Vector3(-0.12 + (k % 3) * 0.12, 0.32 + (k / 3) * 0.05, -0.1 + (k % 2) * 0.2), 0.09, P.C(S.BRASS, 0.1))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mk.cyl(cart + Vector3(sx * 0.2, 0.0, sz * 0.15), 0.07, 0.05, P.iron(-0.05), 6, Vector3(sx, 0, 0), -1.0, false, true)
	# Castillete: cuatro patas, riostras, la rueda (exagerada) y el cable
	var hf := Vector3(0.75, 0, 0.15)
	var top := hf + Vector3(0, 2.2, 0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mk.beam(hf + Vector3(sx * 0.42, 0, sz * 0.38), top + Vector3(sx * 0.12, 0, sz * 0.12), 0.1, timber)
	for y in [0.7, 1.4]:
		var s := lerpf(0.42, 0.12, y / 2.2)
		var zz := lerpf(0.38, 0.12, y / 2.2)
		mk.box(hf + Vector3(0, y, zz), Vector3(s * 2.0 + 0.1, 0.08, 0.08), timber)
		mk.box(hf + Vector3(0, y, -zz), Vector3(s * 2.0 + 0.1, 0.08, 0.08), timber)
	mk.box(top, Vector3(0.42, 0.12, 0.42), P.iron())
	P.wheel(mk, top + Vector3(0, 0.42, 0.0), 0.5, red, Vector3.BACK, 6, 0.09)
	mk.beam(top + Vector3(0.48, 0.42, 0), hf + Vector3(0.45, 0.55, 0), 0.03, P.iron(-0.1))
	mk.beam(top + Vector3(-0.1, 0, 0), hf + Vector3(-0.1, 0.25, 0), 0.03, P.iron(-0.1))
	P.block(mk, hf + Vector3(-0.1, 0, 0), Vector3(0.34, 0.3, 0.34), P.iron(0.1))
	# Caldera del torno, con su chimenea (de ahi el humo)
	var boil := Vector3(0.95, 0, -0.85)
	P.block(mk, boil, Vector3(0.7, 0.55, 0.6), P.C(S.SLATE))
	mk.box(boil + Vector3(0, 0.5, 0.31), Vector3(0.7, 0.1, 0.02), red)
	var mouth := P.stack(mk, boil + Vector3(0.12, 0.55, -0.05), 0.11, 1.2, P.iron(0.1), red)
	kit.put(mk, "kk:wheelbarrow", Vector3(0.75, 0, 1.0), 0.45, 200.0, {"noglow": true})
	return {"fx": mouth}
