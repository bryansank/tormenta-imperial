extends RefCounted
## Enfermeria (militar, 1.2, feat/edificios-militares). Atras, la tienda grande
## de lona clara a dos aguas sobre su tarima, con la puerta enrollada y dos
## ventanas encendidas. Lo exagerado: la CRUZ ROJA enorme en los dos faldones del
## tejado y en la bandera, que se lee desde lejos y de noche. Delante, dos
## camillas de lona con su manta, cajas de botiquin con su cruz y un barril de
## agua (`kk:barrel`, KayKit CC0). Lo demas, piezas propias. ~1.350 triangulos.
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	var canvas := P.C(S.CREAM, -0.02)
	var canvas_dark := P.C(S.CREAM, -0.16)
	var red := P.C(S.RED, 0.0)
	# ── La tarima y la tienda ──
	var c := Vector3(0, 0, -0.45)
	var w := 2.4
	var d := 1.45
	var fz := c.z + d * 0.5
	P.block(mk, c, Vector3(w + 0.16, 0.1, d + 0.16), P.wood(-0.12))
	P.block(mk, c + Vector3(0, 0.1, 0), Vector3(w, 0.62, d), canvas_dark)
	P.gable(mk, c + Vector3(0, 0.72, 0), w, d, 0.62, canvas, canvas_dark, false, 0.12, 0.08)
	# Cruces en los dos faldones (lo exagerado): dos barras sobre la lona.
	var slope := atan2(0.62, d * 0.5)
	for side in [1.0, -1.0]:
		var mid := c + Vector3(-0.35, 0.72 + 0.62 * 0.5 + 0.06, side * d * 0.25)
		var saved := P.push(mk, Transform3D(Basis(Vector3.RIGHT, slope * side), mid))
		mk.box(Vector3.ZERO, Vector3(0.62, 0.03, 0.2), red)
		mk.box(Vector3.ZERO, Vector3(0.2, 0.03, 0.62), red)
		P.pop(mk, saved)
	# La puerta de lona enrollada (abierta) y las ventanas
	P.door(mk, Vector3(0.35, 0.1, fz), Vector3.BACK, 0.5, 0.56, canvas, P.wood(-0.2), true)
	mk.cyl(Vector3(0.1, 0.7, fz + 0.06), 0.06, 0.5, canvas.darkened(0.1), 6, Vector3.RIGHT)
	for x in [-0.75, -0.25]:
		P.window(mk, Vector3(x, 0.45, fz), Vector3.BACK, 0.24, 0.2, P.wood(-0.2), true)
	# Tensores de la lona en las esquinas
	for sx in [-1.0, 1.0]:
		P.post(mk, Vector3(sx * (w * 0.5 + 0.12), 0, fz + 0.12), 0.5, 0.05, P.wood(-0.25))
	# ── Delante: dos camillas, botiquines y el barril ──
	for k in 2:
		_cot(mk, Vector3(-0.85 + k * 0.8, 0, 0.75))
	for p in [Vector3(0.9, 0, 0.55), Vector3(1.15, 0, 0.95)]:
		P.block(mk, p, Vector3(0.3, 0.28, 0.3), P.C(S.CREAM, -0.06))
		mk.box(p + Vector3(0, 0.29, 0), Vector3(0.32, 0.03, 0.32), P.C(S.CREAM, 0.04))
		mk.box(p + Vector3(0, 0.31, 0), Vector3(0.18, 0.02, 0.06), red)
		mk.box(p + Vector3(0, 0.31, 0), Vector3(0.06, 0.02, 0.18), red)
	kit.put(mk, "kk:barrel", Vector3(-1.25, 0, 0.3), 0.32, 0.0, {"noglow": true})
	# ── La bandera de la cruz ──
	var fb := Vector3(1.2, 0, 0.05)
	mk.cyl(fb, 0.04, 1.5, P.iron(0.1), 6)
	mk.ball(fb + Vector3(0, 1.55, 0), 0.06, P.C(S.BRASS))
	var fc := fb + Vector3(-0.3, 1.3, 0)
	mk.box(fc, Vector3(0.52, 0.34, 0.04), canvas)
	mk.box(fc + Vector3(0, 0, 0.025), Vector3(0.3, 0.09, 0.02), red)
	mk.box(fc + Vector3(0, 0, 0.025), Vector3(0.09, 0.26, 0.02), red)
	return {}

## Camilla de lona: dos varales, la lona y una manta doblada.
static func _cot(mk, c: Vector3) -> void:
	for sx in [-1.0, 1.0]:
		mk.box(c + Vector3(sx * 0.16, 0.18, 0), Vector3(0.04, 0.04, 0.72), P.wood(-0.15))
		for sz in [-1.0, 1.0]:
			P.post(mk, c + Vector3(sx * 0.16, 0, sz * 0.3), 0.18, 0.04, P.wood(-0.25))
	mk.box(c + Vector3(0, 0.19, 0), Vector3(0.3, 0.02, 0.62), P.C(S.CREAM, -0.08))
	mk.box(c + Vector3(0, 0.22, 0.12), Vector3(0.3, 0.05, 0.22), P.C(S.SKY, -0.25))
	mk.ball(c + Vector3(0, 0.24, -0.22), 0.08, P.C(S.CREAM, 0.05), Vector3(1.4, 0.6, 1.0))
