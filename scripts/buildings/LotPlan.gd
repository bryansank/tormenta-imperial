extends RefCounted
## La parcela de un edificio, en las dos vistas (docs/03, "Parcela y atrezo"):
## que suelo lleva, que remata su borde, cuanto patio deja alrededor del modelo
## y que atrezo hay en ese patio. Es la regla, pura y estatica; quien la pinta
## es BuildingLot (3D) y BuildingArt2D (2D), asi que las dos vistas ponen la
## misma pieza en el mismo sitio.
##
## Todo va en CASILLAS, en el marco LOCAL del edificio (sin girar), con el
## centro de la parcela en (0, 0): x a la derecha, y hacia delante (+Z en 3D,
## abajo en 2D). Los lados son bits: N=1 (atras), E=2, S=4 (delante), W=8.
##
## Reglas que la plantilla garantiza (y los tests comprueban):
## - Cada pieza cabe entera en el patio: ni pisa el rectangulo del modelo ni se
##   sale de la parcela (y por tanto nunca pisa una calzada vecina).
## - En los lados que dan a calzada no hay remate ni atrezo: es la entrada.
## - La misma semilla da la misma parcela; la obra y la ruina salen de la misma
##   colocacion que el edificio en pie (la ruina vuelca y quema esas piezas).

const LookRule := preload("res://scripts/buildings/BuildingLook.gd")

const SIDE_N := 1
const SIDE_E := 2
const SIDE_S := 4
const SIDE_W := 8

## Grosor del remate del borde, en casillas.
const TRIM_WIDTH := 0.06
## Radio maximo de una pieza respecto al patio (cabe con holgura).
const PROP_RADIUS := 0.42
## Piezas altas: en ruina se parten en vez de volcarse (tumbadas se saldrian
## del patio).
const TALL_PROPS := ["lamp", "flag", "dummy", "clothesline", "gas", "target"]

static func style_of(id: String) -> Dictionary:
	return GameConfig.building_lot_style.get(id, {})

static func has_lot(id: String) -> bool:
	return not style_of(id).is_empty()

## Patio en casillas (0 sin parcela).
static func yard_of(id: String) -> float:
	return float(style_of(id).get("yard", 0.0))

static func accent_of(id: String) -> Color:
	var family := String(style_of(id).get("accent", "civic"))
	return GameConfig.building_lot_accents.get(family, Color(0.8, 0.6, 0.2))

## Semilla de una instancia: la celda de origen y el id. Dos aserraderos en
## celdas distintas no se parecen; el mismo, tras guardar y cargar, si.
static func seed_for(cell: Vector2i, id: String) -> int:
	return hash("%s@%d,%d" % [id, cell.x, cell.y])

## Rectangulo libre para el modelo, en casillas y centrado.
static func model_rect(id: String, footprint: Vector2i) -> Rect2:
	var lot := Vector2(footprint)
	var y := yard_of(id)
	return Rect2(-lot * 0.5 + Vector2(y, y), lot - Vector2(y, y) * 2.0)

## Lado del mundo al que mira el lado local `side` con el edificio girado
## `steps` cuartos de vuelta. `clockwise`: true en 2D (y hacia abajo, el giro
## positivo va en el sentido del reloj), false en 3D (giro positivo sobre +Y,
## visto desde arriba va al reves).
static func world_side(side: int, steps: int, clockwise: bool) -> int:
	var idx := _side_index(side)
	var w := posmod(idx + steps if clockwise else idx - steps, 4)
	return 1 << w

## Pasa una mascara de lados del mundo al marco local del edificio.
static func local_sides(world_mask: int, steps: int, clockwise: bool) -> int:
	var out := 0
	for i in 4:
		if world_mask & world_side(1 << i, steps, clockwise):
			out |= 1 << i
	return out

static func _side_index(side: int) -> int:
	match side:
		SIDE_N: return 0
		SIDE_E: return 1
		SIDE_S: return 2
	return 3

## Lados del MUNDO de una huella (origen + tamano girado) que tocan calzada.
static func road_sides_of(origin: Vector2i, size: Vector2i) -> int:
	var mask := 0
	for x in size.x:
		if _is_road(origin + Vector2i(x, -1)): mask |= SIDE_N
		if _is_road(origin + Vector2i(x, size.y)): mask |= SIDE_S
	for y in size.y:
		if _is_road(origin + Vector2i(size.x, y)): mask |= SIDE_E
		if _is_road(origin + Vector2i(-1, y)): mask |= SIDE_W
	return mask

static func _is_road(cell: Vector2i) -> bool:
	if not GridManager.is_valid_cell(cell):
		return false
	var node := GridManager.get_building_at(cell)
	if node == null:
		return false
	var info := GridManager.get_building_info(node)
	return not info.is_empty() and (info["data"] as BuildingData).id == "road"

## Estado de la parcela para un aspecto de BuildingLook: "construction" (a medio
## preparar), "ruin" (atrezo volcado y quemado) o "idle" (lo demas: la mejora y
## el trabajo no tocan la parcela).
static func state_for(look: int) -> String:
	match look:
		LookRule.Look.CONSTRUCTION: return "construction"
		LookRule.Look.RUIN: return "ruin"
	return "idle"

## La parcela entera de una instancia.
## `road_sides`: lados LOCALES que dan a calzada. `state`: state_for().
## `phase`: la fase de obra (cuantos lados del remate ya estan puestos).
## Devuelve {"id", "footprint", "lot" (Vector2), "yard", "model" (Rect2),
## "ground", "trim", "accent", "state", "trim_runs" [{side, a, b, broken}],
## "props" [{kind, pos, radius, rot, along, toppled, snapped, burnt}]}.
static func plan(id: String, footprint: Vector2i, seed_val: int, road_sides: int = 0, state: String = "idle", phase: int = 0) -> Dictionary:
	var style := style_of(id)
	if style.is_empty():
		return {}
	var lot := Vector2(footprint)
	var yard := float(style.get("yard", 0.2))
	var out := {
		"id": id, "footprint": footprint, "lot": lot, "yard": yard,
		"model": model_rect(id, footprint), "ground": String(style.get("ground", "slabs")),
		"trim": String(style.get("trim", "curb")), "accent": accent_of(id), "state": state,
		"road_sides": road_sides, "trim_runs": [], "props": [],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var sig := signature_of(id)
	out["signature"] = sig
	var props := _place_props(style, lot, yard, road_sides, rng, sig.get("corners", []))
	var runs := _trim_runs(lot, road_sides)
	match state:
		"construction":
			out["ground"] = "dirt"
			# La obra pone el remate lado a lado: tantos lados como fases pasadas.
			var kept: Array = []
			for i in runs.size():
				if i < clampi(phase, 0, 3):
					kept.append(runs[i])
			out["trim_runs"] = kept
			out["props"] = _construction_props(lot, yard, road_sides)
			# Lo exagerado se levanta con el edificio: en obra no esta.
			out["signature"] = {}
		"ruin":
			var wreck := RandomNumberGenerator.new()
			wreck.seed = seed_val ^ 0x5eed
			for p in props:
				if wreck.randf() < 0.22:
					continue
				var tall := String(p["kind"]) in TALL_PROPS
				p["burnt"] = true
				p["snapped"] = tall
				p["toppled"] = not tall and wreck.randf() < 0.75
				out["props"].append(p)
			for r in runs:
				r["broken"] = wreck.randi()
				out["trim_runs"].append(r)
			if not sig.is_empty():
				out["signature"] = sig.merged({"ruined": true})
		_:
			out["props"] = props
			out["trim_runs"] = runs
	return out

## Huecos del patio: las cuatro esquinas y una fila por lado, en la linea media
## del patio. Se barajan con la semilla y se cogen `count`.
static func _slots(lot: Vector2, yard: float, road_sides: int) -> Array:
	var half := lot * 0.5
	var ring := half - Vector2(yard, yard) * 0.5
	var r := yard * PROP_RADIUS
	var slots: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var sides := (SIDE_N if sy < 0.0 else SIDE_S) | (SIDE_E if sx > 0.0 else SIDE_W)
			slots.append({"pos": Vector2(sx * ring.x, sy * ring.y), "sides": sides, "along": Vector2(1, 0)})
	var step := r * 2.3
	for side in [SIDE_N, SIDE_S, SIDE_E, SIDE_W]:
		var horizontal: bool = side == SIDE_N or side == SIDE_S
		var span := (ring.x if horizontal else ring.y) - r * 2.1
		var n := int(floor(span * 2.0 / step)) + 1
		for i in n:
			var t := -span + (span * 2.0) * (float(i) / float(maxi(1, n - 1))) if n > 1 else 0.0
			var pos := Vector2(t, -ring.y if side == SIDE_N else ring.y) if horizontal else Vector2(ring.x if side == SIDE_E else -ring.x, t)
			slots.append({"pos": pos, "sides": side, "along": Vector2(1, 0) if horizontal else Vector2(0, 1)})
	var free: Array = []
	for s in slots:
		if int(s["sides"]) & road_sides:
			continue
		free.append(s)
	return free

## El elemento exagerado de un edificio: {"kind", "corners": [Vector2 de signos
## (-1/1, -1/1)], "pos": [Vector2 en casillas, el centro de cada esquina]} o {}.
static func signature_of(id: String) -> Dictionary:
	var style := style_of(id)
	var kind := String(style.get("signature", ""))
	if kind == "":
		return {}
	var corner := String(style.get("corner", "NE"))
	if corner == "ROOF":
		return {"kind": kind, "corners": [], "on_roof": true}
	var signs: Array = []
	match corner:
		"N": signs = [Vector2(-1, -1), Vector2(1, -1)]
		"S": signs = [Vector2(-1, 1), Vector2(1, 1)]
		_:
			signs = [Vector2(1.0 if corner.contains("E") else -1.0, 1.0 if corner.begins_with("S") else -1.0)]
	return {"kind": kind, "corners": signs}

## Centro de la esquina `sign` del patio, en casillas.
static func corner_center(footprint: Vector2i, yard: float, sgn: Vector2) -> Vector2:
	var ring := Vector2(footprint) * 0.5 - Vector2(yard, yard) * 0.5
	return ring * sgn

static func _place_props(style: Dictionary, lot: Vector2, yard: float, road_sides: int, rng: RandomNumberGenerator, reserved: Array = []) -> Array:
	var kinds: Array = style.get("props", [])
	if kinds.is_empty():
		return []
	var slots := _slots(lot, yard, road_sides)
	# La esquina del elemento exagerado queda libre.
	var ring := lot * 0.5 - Vector2(yard, yard) * 0.5
	for sgn in reserved:
		var c := ring * (sgn as Vector2)
		slots = slots.filter(func(s): return (s["pos"] as Vector2).distance_to(c) > yard * 1.15)
	# Fisher-Yates con la semilla de la instancia.
	for i in range(slots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = slots[i]
		slots[i] = slots[j]
		slots[j] = tmp
	var cnt: Array = style.get("count", [4, 6])
	var want := rng.randi_range(int(cnt[0]), int(cnt[1]))
	# Las parcelas grandes llevan mas: el Nucleo no se queda con cuatro farolas.
	want = int(round(want * maxf(1.0, (lot.x + lot.y) / 4.0)))
	var r := yard * PROP_RADIUS
	var out: Array = []
	for i in mini(want, slots.size()):
		var s: Dictionary = slots[i]
		var kind: String = kinds[0] if i == 0 else String(kinds[rng.randi_range(0, kinds.size() - 1)])
		var scale := rng.randf_range(0.85, 1.08)
		var along: Vector2 = s["along"]
		# Un poco de holgura a lo largo del lado (nunca hacia el modelo).
		var jitter := along * rng.randf_range(-0.2, 0.2) * r if int(s["sides"]) in [SIDE_N, SIDE_E, SIDE_S, SIDE_W] else Vector2.ZERO
		var rot := atan2(along.y, along.x) + (PI if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.25, 0.25)
		out.append({
			"kind": kind, "pos": (s["pos"] as Vector2) + jitter, "radius": r * scale,
			"rot": rot, "along": along, "toppled": false, "snapped": false, "burnt": false,
		})
	return out

## Remate del borde: un tramo por lado que no da a calzada, pegado al filo
## exterior de la parcela. Orden fijo N, E, S, W (la obra los pone en ese orden).
static func _trim_runs(lot: Vector2, road_sides: int) -> Array:
	var half := lot * 0.5
	var e := half - Vector2(TRIM_WIDTH, TRIM_WIDTH) * 0.5
	var runs: Array = []
	var defs := [
		[SIDE_N, Vector2(-half.x, -e.y), Vector2(half.x, -e.y)],
		[SIDE_E, Vector2(e.x, -half.y), Vector2(e.x, half.y)],
		[SIDE_S, Vector2(-half.x, e.y), Vector2(half.x, e.y)],
		[SIDE_W, Vector2(-e.x, -half.y), Vector2(-e.x, half.y)],
	]
	for d in defs:
		if int(d[0]) & road_sides:
			continue
		runs.append({"side": int(d[0]), "a": d[1], "b": d[2], "broken": 0})
	return runs

## Obra: jalones con banderola en las esquinas libres y un palet de losas
## esperando en una de ellas.
static func _construction_props(lot: Vector2, yard: float, road_sides: int) -> Array:
	var half := lot * 0.5
	var ring := half - Vector2(yard, yard) * 0.5
	var r := yard * PROP_RADIUS
	var out: Array = []
	var first := true
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var sides := (SIDE_N if c.y < 0.0 else SIDE_S) | (SIDE_E if c.x > 0.0 else SIDE_W)
		if sides & road_sides:
			continue
		out.append({"kind": "pallet" if first else "stake", "pos": c * ring, "radius": r,
			"rot": 0.0, "along": Vector2(1, 0), "toppled": false, "snapped": false, "burnt": false})
		first = false
	return out
