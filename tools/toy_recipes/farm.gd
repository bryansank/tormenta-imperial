extends RefCounted
## Granja (residencial, acento verde): cuatro bancales de tierra delante a la
## izquierda, el cobertizo de tablas con tejado verde y puertas en aspa atras a
## la derecha, pacas de heno, el abrevadero y la valla del huerto. Exagerado: el
## molino de bombeo, una torre de celosia con la rueda de aspas casi tan ancha
## como el cobertizo.
##
## Lo que crece NO va en la malla del edificio: los tres cultivos (lechugas,
## patatas, trigo) y el rotor del molino van en la malla aparte de los bancales
## (tools/toy_crops.gd), que el shader `toy_crops.gdshader` hace crecer, madurar
## y girar (FarmCrops3D). La receta la devuelve en "crops".
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S
const Crops := preload("res://tools/toy_crops.gd")

## Bancales: filas a lo largo de X, delante a la izquierda.
const BED_ROWS := 4
const BED_TOP := 0.1

func build(mk, kit, ctx: Dictionary) -> Dictionary:
	var hw := float(ctx["w"]) * 0.5
	var hd := float(ctx["d"]) * 0.5
	var crops := Crops.new()
	var soil := P.C(S.WOOD, -0.32)
	var earth := P.C(S.WOOD, -0.22)
	# ── Huerto: tierra batida y cuatro bancales elevados ──
	var fx0 := -hw + 0.08
	var fx1 := 0.3
	var fz0 := -0.18
	var fz1 := hd - 0.08
	var fcx := (fx0 + fx1) * 0.5
	P.block(mk, Vector3(fcx, 0, (fz0 + fz1) * 0.5), Vector3(fx1 - fx0, 0.03, fz1 - fz0), earth)
	var row_z: Array = []
	for k in BED_ROWS:
		var z := lerpf(fz0 + 0.2, fz1 - 0.16, float(k) / float(BED_ROWS - 1))
		row_z.append(z)
		P.block(mk, Vector3(fcx, 0, z), Vector3(fx1 - fx0 - 0.12, BED_TOP, 0.27), soil)
		# Caballon: una raya mas clara a lo largo del bancal.
		mk.box(Vector3(fcx, BED_TOP + 0.005, z), Vector3(fx1 - fx0 - 0.2, 0.012, 0.06), soil.lightened(0.1))
	_plants(crops, fx0 + 0.16, fx1 - 0.16, row_z)
	# Valla del huerto: la pieza CC0 detras y una baranda baja a la derecha.
	kit.put(mk, "kk:fence_wood_straight", Vector3(fcx, 0, fz0 - 0.06), fx1 - fx0, 90.0, {"noglow": true})
	var rx := fx1 + 0.04
	for k in 4:
		P.post(mk, Vector3(rx, 0, lerpf(fz0, fz1 - 0.05, float(k) / 3.0)), 0.32, 0.06, P.wood(-0.05))
	mk.box(Vector3(rx, 0.24, (fz0 + fz1) * 0.5), Vector3(0.04, 0.05, fz1 - fz0), P.wood(0.05))
	mk.box(Vector3(rx, 0.12, (fz0 + fz1) * 0.5), Vector3(0.04, 0.05, fz1 - fz0), P.wood(0.0))
	# ── Cobertizo atras a la derecha ──
	var bc := Vector3(hw - 0.72, 0, -hd + 0.62)
	var bw := 1.2
	var bd := 0.95
	var bh := 0.85
	P.block(mk, bc, Vector3(bw + 0.1, 0.08, bd + 0.1), P.C(S.STONE, -0.15))
	P.block(mk, bc + Vector3(0, 0.08, 0), Vector3(bw, bh, bd), P.wood(0.0))
	for x in [-bw * 0.48, bw * 0.48]:
		P.post(mk, bc + Vector3(x, 0.08, bd * 0.5), bh, 0.08, P.C(S.CREAM, -0.05))
	P.gable(mk, bc + Vector3(0, 0.08 + bh, 0), bd, bw, 0.6, P.C(S.GREEN, -0.15), P.wood(0.0), true)
	var front := bc.z + bd * 0.5
	mk.box(Vector3(bc.x, 0.47, front + 0.01), Vector3(0.62, 0.72, 0.04), P.wood(-0.15))
	mk.beam(Vector3(bc.x - 0.28, 0.14, front + 0.05), Vector3(bc.x + 0.28, 0.8, front + 0.05), 0.05, P.C(S.CREAM))
	mk.beam(Vector3(bc.x + 0.28, 0.14, front + 0.05), Vector3(bc.x - 0.28, 0.8, front + 0.05), 0.05, P.C(S.CREAM))
	mk.box(Vector3(bc.x, 0.47, front + 0.035), Vector3(0.66, 0.05, 0.02), P.C(S.CREAM))
	P.window(mk, Vector3(bc.x, 0.08 + bh + 0.26, front), Vector3.BACK, 0.2, 0.16, P.C(S.CREAM, -0.05))
	# ── Pacas de heno y el abrevadero delante del cobertizo ──
	var hx := hw - 0.62
	for k in 3:
		mk.cyl(Vector3(hx - 0.32 + k * 0.32, 0.15, 0.12 + (k % 2) * 0.08), 0.15, 0.28, P.C(S.BRASS, -0.08), 8, Vector3.BACK, -1.0, false, true)
	mk.cyl(Vector3(hx - 0.16, 0.43, 0.16), 0.15, 0.28, P.C(S.BRASS, -0.04), 8, Vector3.BACK, -1.0, false, true)
	P.block(mk, Vector3(hx, 0, hd - 0.3), Vector3(0.7, 0.24, 0.3), P.wood(-0.1))
	mk.box(Vector3(hx, 0.23, hd - 0.3), Vector3(0.6, 0.03, 0.2), P.C(S.SKY, 0.0))
	kit.put(mk, "kk:sack", Vector3(hx + 0.05, 0, 0.62), 0.28, 30.0, {"noglow": true})
	# ── El molino de bombeo (exagerado): torre de celosia, cola y bomba ──
	var mc := Vector3(-hw + 0.68, 0, -hd + 0.55)
	var mh := 2.3
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mk.beam(mc + Vector3(sx * 0.3, 0, sz * 0.3), mc + Vector3(sx * 0.08, mh, sz * 0.08), 0.06, P.iron(0.15))
	for y in [0.55, 1.1, 1.65]:
		var s := lerpf(0.3, 0.08, y / mh)
		for sz in [-1.0, 1.0]:
			mk.box(mc + Vector3(0, y, sz * s), Vector3(s * 2.0, 0.04, 0.04), P.iron(0.15))
		for sx in [-1.0, 1.0]:
			mk.box(mc + Vector3(sx * s, y, 0), Vector3(0.04, 0.04, s * 2.0), P.iron(0.15))
	# Bomba al pie y su caño sobre una pila
	P.block(mk, mc + Vector3(0.0, 0, 0.0), Vector3(0.2, 0.3, 0.2), P.C(S.RED, -0.1))
	mk.box(mc + Vector3(0.0, 0.26, 0.2), Vector3(0.05, 0.05, 0.24), P.iron(0.1))
	P.block(mk, mc + Vector3(0.0, 0, 0.42), Vector3(0.36, 0.12, 0.2), P.C(S.STONE, -0.1))
	# Cabeza: caja del engranaje y la cola (fijas; el rotor gira en los bancales)
	var hub := mc + Vector3(0, mh + 0.15, 0.2)
	mk.box(hub + Vector3(0, -0.05, -0.22), Vector3(0.16, 0.16, 0.45), P.iron())
	mk.box(hub + Vector3(0, 0.02, -0.66), Vector3(0.04, 0.38, 0.42), P.C(S.GREEN, -0.1))
	_rotor(crops, hub)
	return {"crops": crops}

## Las plantas de los tres cultivos en las filas de los bancales. Lechugas y
## patatas, cinco por fila; el trigo, mas tupido.
func _plants(crops, x0: float, x1: float, rows: Array) -> void:
	var g: Color = Crops.gray()
	for zi in rows.size():
		var z: float = rows[zi]
		for i in 5:
			var t := float(i) / 4.0
			var base := Vector3(lerpf(x0, x1, t), BED_TOP, z + (0.02 if (i + zi) % 2 == 0 else -0.02))
			# Lechuga: roseta baja y su cogollo.
			var m: RefCounted = Crops.kit()
			m.cyl(Vector3.ZERO, 0.13, 0.11, g, 6, Vector3.UP, 0.09)
			crops.add(base, Crops.Variant.LETTUCE, m)
			m = Crops.kit()
			m.cyl(Vector3(0, 0.1, 0), 0.075, 0.06, g, 5, Vector3.UP, 0.03)
			crops.add(base, Crops.Variant.LETTUCE, m, 1.0)
			# Patata: mata redonda y la flor encima.
			m = Crops.kit()
			m.cyl(Vector3.ZERO, 0.15, 0.2, g, 6, Vector3.UP, 0.07)
			crops.add(base, Crops.Variant.POTATO, m)
			m = Crops.kit()
			m.box(Vector3(0.02, 0.22, 0.0), Vector3(0.07, 0.06, 0.07), g)
			crops.add(base, Crops.Variant.POTATO, m, 1.0)
		for i in 8:
			var t := float(i) / 7.0
			var base := Vector3(lerpf(x0 - 0.04, x1 + 0.04, t), BED_TOP, z + (0.05 if (i + zi) % 2 == 0 else -0.05))
			# Trigo: macolla de tallos y la espiga.
			var m: RefCounted = Crops.kit()
			m.cyl(Vector3.ZERO, 0.07, 0.4, g, 4, Vector3.UP, 0.04)
			crops.add(base, Crops.Variant.WHEAT, m)
			m = Crops.kit()
			m.cyl(Vector3(0, 0.36, 0), 0.06, 0.2, g, 4, Vector3.UP, 0.015)
			crops.add(base, Crops.Variant.WHEAT, m, 1.0)

## La rueda de aspas del molino, alrededor de su eje (mira a +Z).
func _rotor(crops, hub: Vector3) -> void:
	var m: RefCounted = Crops.kit()
	var n := 8
	for k in n:
		var a := TAU * float(k) / float(n)
		var dir := Vector3(cos(a), sin(a), 0)
		m.beam(dir * 0.1, dir * 0.62, 0.045, P.iron(0.2))
		m.box(dir * 0.44 + Vector3(0, 0, 0.03), Vector3(0.17, 0.17, 0.02), P.C(S.CREAM, -0.05) if k % 2 == 0 else P.C(S.GREEN, -0.05))
	m.cyl(Vector3.ZERO, 0.1, 0.1, P.C(S.GREEN, -0.1), 8, Vector3.BACK, -1.0, false, true)
	crops.add(hub, Crops.Variant.ROTOR, m)
