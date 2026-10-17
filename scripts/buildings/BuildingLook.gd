extends RefCounted
## El aspecto de un edificio en el mapa, en las dos vistas: obra (con su fase),
## mejora, ruina, trabajando o quieto. Es la regla, pura y estatica: de los
## hechos del edificio al aspecto. Quien lo pinta es BuildingLookVisual (3D) y
## Building2D (2D); los dos preguntan aqui, asi que nunca discrepan.
##
## Las tres fases de obra son las mismas para todos (valla -> cimientos ->
## estructura) y la huella decide el tamano y cuantas piezas lleva (postes,
## pilas, pilares). Encima, dos capas de variacion, las dos decididas AQUI para
## que 3D y 2D coincidan:
## - **Estilo por tipo** (site_style): que materiales se apilan, de que es la
##   valla, el color de la lona, la silueta de la estructura y que se anima.
##   Tabla en GameConfig.construction_style.
## - **Disposicion por instancia** (site_layout): una semilla determinista por
##   edificio y celda (site_seed) coloca las pilas, la puerta, el andamio, la
##   grua y el desorden. Estable entre frames, recargas y guardados: sale de la
##   celda de origen, que viaja en la partida.

const Badge := preload("res://scripts/buildings/BuildingStatusBadge.gd")

enum Look { IDLE, CONSTRUCTION, UPGRADE, RUIN, ACTIVE }

## Fase 0: valla con materiales apilados. 1: solar despejado con cimientos.
## 2: estructura a medio levantar (pilares, forjado y andamio).
const PHASE_FENCE := 0
const PHASE_FOUNDATION := 1
const PHASE_FRAME := 2
const PHASE_COUNT := 3

## Fase de obra para un progreso 0..1, con los umbrales de GameConfig.
static func phase_for(progress: float, thresholds: Array = []) -> int:
	if thresholds.is_empty():
		thresholds = GameConfig.construction_phase_thresholds
	var phase := 0
	for t in thresholds:
		if progress >= float(t):
			phase += 1
	return clampi(phase, 0, PHASE_COUNT - 1)

## Clase de huella: 1, 2 o 3 (el lado mayor, recortado). Una 2x1 es de las de 2.
static func footprint_class(size: Vector2i) -> int:
	return clampi(maxi(size.x, size.y), 1, 3)

## El efecto de actividad de un edificio ("smoke", "dust", "glow") o "".
static func fx_kind(building_id: String) -> String:
	return String(GameConfig.building_active_fx.get(building_id, ""))

## Las esquinas de la parcela, en signos (unidades de media huella).
const CORNERS := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
## Donde pueden ir las pilas de la fase 0, en fracciones de la huella centrada.
const PILE_SPOTS := [Vector2(-0.22, -0.2), Vector2(0.22, 0.15), Vector2(-0.2, 0.22), Vector2(0.21, -0.21)]

# ── Obra: estilo por tipo y disposicion por instancia ─────────────────

## El estilo de obra de `building_id`: su fila de GameConfig.construction_style
## sobre construction_style_default (lo que no diga sale del defecto).
static func site_style(building_id: String) -> Dictionary:
	var style: Dictionary = GameConfig.construction_style_default.duplicate(true)
	style.merge(GameConfig.construction_style.get(building_id, {}), true)
	return style

## Semilla de la obra de un edificio: FNV-1a del id y la celda de origen. La
## misma instancia da siempre la misma (no depende de la sesion ni del orden de
## carga: ni hash() ni randi()); dos casas en celdas distintas, distintas.
static func site_seed(building_id: String, cell: Vector2i) -> int:
	var h := 0x811C9DC5
	for b in building_id.to_utf8_buffer():
		h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
	for v in [cell.x, cell.y]:
		for shift in [0, 8]:
			h = ((h ^ ((int(v) >> shift) & 0xFF)) * 0x01000193) & 0xFFFFFFFF
	h ^= h >> 15
	h = (h * 0x2C1B3C6D) & 0xFFFFFFFF
	h ^= h >> 12
	return h & 0x7FFFFFFF

## La semilla de un edificio real: por su celda de origen en la rejilla (la
## misma en 3D y en 2D, y la que se guarda). Fuera de la rejilla (sondas,
## pruebas, el instante antes de registrarse) sale de su posicion.
static func seed_of(node: Node, data: BuildingData) -> int:
	var id := data.id if data else ""
	var info: Dictionary = GridManager.get_building_info(node)
	if info.has("origin_cell"):
		return site_seed(id, info["origin_cell"])
	var cell := Vector2i.ZERO
	if node is Node3D:
		var p: Vector3 = (node as Node3D).position
		cell = Vector2i(roundi(p.x * 4.0), roundi(p.z * 4.0)) + Vector2i(1 << 12, 1 << 12)
	elif node is Node2D:
		var q: Vector2 = (node as Node2D).position
		cell = Vector2i(roundi(q.x), roundi(q.y)) + Vector2i(1 << 13, 1 << 13)
	return site_seed(id, cell)

## La disposicion de una obra, en el marco SIN girar del edificio y en
## fracciones de su huella centrada (-0.5..0.5): las dos vistas la leen igual.
## Lados: 0 delante (+Z en 3D, abajo en 2D), 1 derecha (+X), 2 detras, 3 izquierda.
## - "gate_side": lado de la puerta de la valla; "flag_post": a que lado de la
##   puerta va el banderin (-1/1).
## - "post_step": separacion de los postes (unidades 3D; mas o menos postes).
## - "piles": [{kind, pos, yaw, scale}], tantas como la clase de huella (+0/1).
## - "tarp_pile": que pila lleva lona encima (-1: ninguna).
## - "clutter": [{kind ("barrel", "crate", "cone"), pos}], el pequeno desorden.
## - "scaffold_side", "crane_corner" (signos), "crane_yaw" (rad),
##   "cone_corners" (dos esquinas), "leftover_corner", "fx_spot", "lean".
static func site_layout(seed_val: int, style: Dictionary, n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var kinds: Array = style.get("piles", ["planks"])
	if kinds.is_empty():
		kinds = ["planks"]
	var spots: Array = PILE_SPOTS.duplicate()
	# Barajado propio (Array.shuffle usa el azar global: no seria estable).
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	var mirror := Vector2(-1.0 if rng.randf() < 0.5 else 1.0, -1.0 if rng.randf() < 0.5 else 1.0)
	var first := rng.randi_range(0, kinds.size() - 1)
	var count := clampi(n + rng.randi_range(0, 1), 1, spots.size())
	var piles: Array = []
	for k in count:
		var s: Vector2 = spots[k] * mirror
		piles.append({
			"kind": String(kinds[(first + k) % kinds.size()]),
			"pos": s + Vector2(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.04, 0.04)),
			"yaw": rng.randf_range(-0.35, 0.35) + (PI * 0.5 if rng.randf() < 0.35 else 0.0),
			"scale": rng.randf_range(0.85, 1.15),
		})
	var clutter: Array = []
	var clutter_kinds := ["barrel", "crate", "cone"]
	for k in rng.randi_range(1, 3):
		clutter.append({
			"kind": clutter_kinds[rng.randi_range(0, clutter_kinds.size() - 1)],
			"pos": Vector2(rng.randf_range(-0.38, 0.38), rng.randf_range(-0.38, 0.38)),
		})
	var corners: Array = CORNERS.duplicate()
	var c0 := rng.randi_range(0, 3)
	var c1 := (c0 + rng.randi_range(1, 3)) % 4
	return {
		"seed": seed_val,
		"gate_side": rng.randi_range(0, 3),
		"flag_post": -1 if rng.randf() < 0.5 else 1,
		"post_step": rng.randf_range(0.7, 1.1),
		"piles": piles,
		"tarp_pile": rng.randi_range(-1, count - 1),
		"clutter": clutter,
		"scaffold_side": rng.randi_range(0, 3),
		"crane_corner": corners[rng.randi_range(0, 3)],
		"crane_yaw": rng.randf() * TAU,
		"cone_corners": [corners[c0], corners[c1]],
		"leftover_corner": corners[(c0 + 2) % 4],
		"fx_spot": Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25)),
		"lean": rng.randf_range(-0.06, 0.06),
	}

## Normal hacia fuera del lado `side` (0 +Z/abajo, 1 +X, 2 -Z/arriba, 3 -X).
static func side_normal(side: int) -> Vector2:
	match posmod(side, 4):
		1: return Vector2(1, 0)
		2: return Vector2(0, -1)
		3: return Vector2(-1, 0)
	return Vector2(0, 1)

## Etapas de dano (docs/03, "Etapas de dano"): sano, leve, grave y ruina. Van
## ENCIMA del aspecto (un edificio grave puede seguir trabajando y echar su humo
## ademas del negro); la ruina es ademas su propio aspecto (Look.RUIN).
const DAMAGE_NONE := 0
const DAMAGE_LIGHT := 1
const DAMAGE_HEAVY := 2
const DAMAGE_RUIN := 3

## Etapa de dano para una proporcion de vida 0..1, con los umbrales de
## GameConfig.damage_stage_thresholds ([leve, grave]: por debajo de cada uno).
static func damage_stage(ratio: float, ruined: bool = false, thresholds: Array = []) -> int:
	if ruined or ratio <= 0.0:
		return DAMAGE_RUIN
	if thresholds.is_empty():
		thresholds = GameConfig.damage_stage_thresholds
	var stage := DAMAGE_NONE
	if thresholds.size() > 0 and ratio < float(thresholds[0]):
		stage = DAMAGE_LIGHT
	if thresholds.size() > 1 and ratio < float(thresholds[1]):
		stage = DAMAGE_HEAVY
	return stage

## Regla: hechos -> {"look": Look, "phase": int, "damage": etapa}.
## Hechos: "under_construction", "upgrade" (la obra es una mejora), "progress"
## (0..1), "ruined", "working" (el badge dice trabajando), "fx" (tiene efecto),
## "health_ratio" (0..1, sin la clave 1).
## Orden: la obra manda (una torre a medio levantar no es una ruina aunque la
## tormenta la tocara), luego la ruina, luego la actividad. El dano leve o
## grave solo se ve en pie (quieto o trabajando): la obra y el andamio de
## mejora lo tapan.
static func derive(facts: Dictionary) -> Dictionary:
	if bool(facts.get("under_construction", false)):
		if bool(facts.get("upgrade", false)):
			return {"look": Look.UPGRADE, "phase": PHASE_FRAME, "damage": DAMAGE_NONE}
		return {"look": Look.CONSTRUCTION, "phase": phase_for(float(facts.get("progress", 0.0))), "damage": DAMAGE_NONE}
	if bool(facts.get("ruined", false)):
		return {"look": Look.RUIN, "phase": 0, "damage": DAMAGE_RUIN}
	var damage := damage_stage(float(facts.get("health_ratio", 1.0)))
	if bool(facts.get("working", false)) and String(facts.get("fx", "")) != "":
		return {"look": Look.ACTIVE, "phase": 0, "damage": damage}
	return {"look": Look.IDLE, "phase": 0, "damage": damage}

## Los hechos de un edificio real (3D o 2D: los dos llevan las mismas metas y
## un hijo "StatusBadge" con get_status()).
static func facts_of(node: Node, data: BuildingData) -> Dictionary:
	var building := node.has_meta("under_construction")
	var working := false
	var badge := node.get_node_or_null("StatusBadge")
	if badge != null and badge.has_method("get_status"):
		working = int(badge.get_status()) == Badge.Status.WORKING
	return {
		"under_construction": building,
		"upgrade": building and ProductionManager.get_upgrade_target(node) > 0,
		"progress": ProductionManager.get_construction_progress(node) if building else 1.0,
		"ruined": BuildingHealth.is_ruined(node),
		"health_ratio": BuildingHealth.get_health_ratio(node),
		"working": working,
		"fx": fx_kind(data.id) if data else "",
	}
