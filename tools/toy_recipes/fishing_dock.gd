extends RefCounted
## Muelle de pesca (residencial: da de comer, acento verde en la parcela). Va
## en la orilla, pegado a un banco de peces (feat/muelle-pesca).
##
## Atras a la izquierda, el ahumadero propio: caseta de tablas con tejado rojo a
## dos aguas y su chimenea de piedra (de ahi sale el humo de "trabajando",
## FxAnchor). Delante a la derecha, la pasarela de tablas sobre pilotes, propia
## (lo exagerado: se lee "muelle" desde lejos), con la
## barca `pir:boat-row-small` varada delante. Atras a la derecha, el tendedero
## de pescado (postes, cuerda y peces propios, baratos) y, junto a la puerta, el
## cubo `sur:bucket` con un pez y un barril `pir:barrel`.
## ~1.330 triangulos horneados (con el borde de contacto).
const P := preload("res://tools/toy_recipes/_parts.gd")
const S := P.S

func build(mk, kit, _ctx: Dictionary) -> Dictionary:
	var out := {}
	var wood := P.wood(0.04)
	var dark := P.wood(-0.22)
	var roof := P.C(S.TERRACOTTA, -0.04)
	# ── El ahumadero ──
	var hut := Vector3(-0.6, 0, -0.55)
	var hw := 1.3
	var hd := 1.0
	var wall_h := 0.85
	P.block(mk, hut, Vector3(hw, 0.08, hd), P.C(S.STONE, -0.12))
	P.block(mk, hut + Vector3(0, 0.08, 0), Vector3(hw - 0.08, wall_h, hd - 0.08), wood)
	P.door(mk, Vector3(hut.x + 0.25, 0.08, hut.z + hd * 0.5 - 0.03), Vector3.BACK, 0.34, 0.58, dark, P.wood(-0.32), true)
	P.window(mk, Vector3(hut.x - 0.3, 0.55, hut.z + hd * 0.5 - 0.03), Vector3.BACK, 0.26, 0.2, dark, true)
	P.gable(mk, hut + Vector3(0, 0.08 + wall_h, 0), hw - 0.08, hd - 0.08, 0.5, roof, wood)
	var mouth: Vector3 = P.chimney(mk, hut + Vector3(-hw * 0.5 + 0.22, 0.08, -hd * 0.5 + 0.22), 0.26, 1.55,
		P.C(S.STONE, -0.05), P.C(S.STONE, -0.25))
	out["fx"] = mouth
	# ── La pasarela sobre pilotes (lo exagerado) y la barca ──
	_pier(mk, Vector3(0.78, 0, 0.05), 1.15, 1.75, 0.5, dark)
	kit.put(mk, "pir:boat-row-small", Vector3(-0.5, 0, 0.95), 1.25, 8.0, {"noglow": true})
	# ── El tendedero de pescado ──
	var ra := Vector3(0.25, 0, -1.15)
	var rb := Vector3(1.25, 0, -1.15)
	P.post(mk, ra, 0.95, 0.07, dark)
	P.post(mk, rb, 0.95, 0.07, dark)
	mk.box((ra + rb) * 0.5 + Vector3(0, 0.92, 0), Vector3(rb.x - ra.x + 0.1, 0.04, 0.04), dark)
	for k in 3:
		var p := ra.lerp(rb, 0.2 + 0.3 * float(k)) + Vector3(0, 0.7, 0)
		mk.box(p + Vector3(0, 0.12, 0), Vector3(0.015, 0.2, 0.015), P.C(S.CREAM, -0.2))
		_hung_fish(mk, p, P.C(S.SLATE, 0.22 if k % 2 == 0 else 0.1))
	# ── Junto a la puerta: cubo con la pesca y un barril ──
	kit.put(mk, "sur:bucket", Vector3(0.05, 0, 0.12), 0.24, 0.0, {"noglow": true})
	_hung_fish(mk, Vector3(0.05, 0.38, 0.12), P.C(S.TERRACOTTA, 0.1))
	kit.put(mk, "pir:barrel", Vector3(-1.3, 0, 0.2), 0.36, 0.0, {"noglow": true})
	return out

## Un pez colgado de la cola (cabeza abajo): cuerpo de bola alargada y cola.
static func _hung_fish(mk, top: Vector3, col: Color) -> void:
	mk.ball(top + Vector3(0, -0.06, 0), 0.07, col, Vector3(0.7, 1.7, 0.45))
	mk.cyl(top + Vector3(0, 0.04, 0), 0.06, 0.08, col.darkened(0.15), 4, Vector3.UP, 0.0)

## La pasarela: tarima de tablas sobre seis pilotes, con las juntas marcadas y
## un noray de hierro en la punta. `c` es el centro en el suelo; `w` x `d` la
## planta (a lo largo de Z); `h` la altura de la tarima.
static func _pier(mk, c: Vector3, w: float, d: float, h: float, dark: Color) -> void:
	var deck := P.wood(0.1)
	for sx in [-1.0, 1.0]:
		for t in [-0.45, 0.0, 0.45]:
			P.post(mk, c + Vector3(sx * (w * 0.5 - 0.08), 0, t * d), h, 0.11, dark)
	P.block(mk, c + Vector3(0, h, 0), Vector3(w, 0.08, d), deck)
	for k in 4:
		var z: float = c.z - d * 0.5 + d * float(k + 1) / 5.0
		mk.box(Vector3(c.x, h + 0.085, z), Vector3(w - 0.04, 0.01, 0.03), dark)
	mk.cyl(c + Vector3(w * 0.3, h + 0.08, d * 0.5 - 0.15), 0.06, 0.14, P.iron(0.05), 6)
