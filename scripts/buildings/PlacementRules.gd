extends RefCounted
## Las reglas de colocar, mover, demoler y guardar edificios, sin vista.
##
## Antes vivian dentro de BuildingPlacer, mezcladas con rayos, fantasmas y
## mallas. La vista 2D (docs/18-vista-2d.md) necesita exactamente las mismas
## reglas con otro dibujo, asi que salen aqui: estaticas, sin nodos propios y sin
## suponer 3D. BuildingPlacer (3D) y BuildingPlacer2D las llaman por igual; una
## regla que cambia aqui cambia en las dos vistas a la vez.
##
## Se carga por preload (sin class_name), como StatusBadge o PointerMath, para no
## depender de la cache global de clases del editor.

## Vecinos de una calzada: NORTE=1 (Z-), ESTE=2 (X+), SUR=4 (Z+), OESTE=8 (X-).
const ROAD_DIRS: Array = [
	{"bit": 1, "offset": Vector2i(0, -1)},
	{"bit": 2, "offset": Vector2i(1, 0)},
	{"bit": 4, "offset": Vector2i(0, 1)},
	{"bit": 8, "offset": Vector2i(-1, 0)},
]

# ── Huella y giro ─────────────────────────────────────────────────────

## Huella efectiva con el giro aplicado (90 y 270 intercambian ancho y alto).
static func rotated_size(data: BuildingData, rotation_steps: int) -> Vector2i:
	if data == null:
		return Vector2i(1, 1)
	if rotation_steps % 2 == 1:
		return Vector2i(data.grid_size.y, data.grid_size.x)
	return data.grid_size

## Copia de `data` con la huella girada, para que GridManager ocupe las celdas
## correctas.
static func rotated_data(data: BuildingData) -> BuildingData:
	var rotated := data.duplicate()
	rotated.grid_size = Vector2i(data.grid_size.y, data.grid_size.x)
	return rotated

## Los datos que se le pasan a GridManager para un giro dado.
static func placement_data(data: BuildingData, rotation_steps: int) -> BuildingData:
	return rotated_data(data) if rotation_steps % 2 == 1 else data

## BuildingData original (sin girar) desde su .tres, o null.
static func load_building_data(building_id: String) -> BuildingData:
	var path := "res://data/buildings/%s.tres" % building_id
	if ResourceLoader.exists(path):
		return load(path) as BuildingData
	return null

# ── Veredicto de colocacion ───────────────────────────────────────────

## Veredicto completo para `building_id` con huella `size` en `cell`: la regla de
## yacimiento de GameConfig (alcance / encima) Y celdas libres. `ignore_building`
## es el edificio que se esta moviendo (sus celdas cuentan como libres).
## Devuelve {"ok": bool, "reason": "" | "deposit" | "occupied", "deposit": Node}.
static func evaluate_placement(building_id: String, cell: Vector2i, size: Vector2i, map_gen: Node, ignore_building: Node = null) -> Dictionary:
	var rule: Dictionary = GameConfig.get_deposit_rule(building_id)
	var deposit: Node = null
	if not rule.is_empty():
		var cells: Array = GridManager.cells_for(cell, size)
		if map_gen != null and map_gen.has_method("find_deposit_near_cells"):
			deposit = map_gen.find_deposit_near_cells(String(rule["deposit"]), cells, int(rule["reach"]))
		if deposit == null:
			return {"ok": false, "reason": "deposit", "deposit": null}
	# Un yacimiento que se consume queda debajo del edificio: sus celdas valen.
	var ignore_obstacle: Node = deposit if bool(rule.get("consumes", false)) else null
	if not GridManager.can_place(cell, size, ignore_building, ignore_obstacle):
		return {"ok": false, "reason": "occupied", "deposit": deposit}
	return {"ok": true, "reason": "", "deposit": deposit}

## Quita el yacimiento sobre el que se planta un edificio que lo consume (la
## Refineria). Solo tras pasar todas las comprobaciones.
static func consume_deposit_if_required(building_id: String, verdict: Dictionary, map_gen: Node) -> void:
	var rule: Dictionary = GameConfig.get_deposit_rule(building_id)
	var deposit: Node = verdict.get("deposit", null)
	if deposit != null and bool(rule.get("consumes", false)) and map_gen != null:
		map_gen.remove_deposit(deposit)

## El mensaje (ya traducido) con el que se rechaza un clic por la regla de yacimiento.
static func deposit_reject_message(building_id: String) -> String:
	var rule: Dictionary = GameConfig.get_deposit_rule(building_id)
	return Tr.t(String(rule.get("message", "LBL_REQUIRES_DEPOSIT")))

# ── Topes, requisitos y bolsa ─────────────────────────────────────────

## Cuantos hay en pie de este tipo, preguntado a GridManager (ver la nota
## historica en BuildingPlacer.count_building: el nombre del nodo no sirve).
static func count_building(building_id: String) -> int:
	var count := 0
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info.get("data")
		if data != null and data.id == building_id:
			count += 1
	return count

static func check_building_limit(building_id: String) -> bool:
	var limit := GameConfig.get_building_limit(building_id)
	if limit < 0:
		return true
	return count_building(building_id) < limit

static func check_prerequisites(building_id: String) -> bool:
	for req_id in GameConfig.get_prerequisites(building_id):
		if count_building(req_id) < 1:
			return false
	return true

## Por que no se puede comprar `data` ahora mismo, como texto para el jugador, o
## "" si nada lo impide. En el mismo orden en que lo comprobaba BuildingPlacer:
## tope, requisitos, obreros y coste. No cobra nada.
static func purchase_block_message(data: BuildingData) -> String:
	if not check_building_limit(data.id):
		return Tr.t("LBL_LIMIT_REACHED") % [count_building(data.id), GameConfig.get_building_limit(data.id)]
	if not check_prerequisites(data.id):
		return Tr.t("LBL_REQUIRES") % " + ".join(GameConfig.get_prerequisites(data.id))
	if data.workers_required > 0 and PopulationManager.get_free_workers() < data.workers_required:
		return Tr.t("LBL_NO_WORKERS")
	var cost := data.get_cost()
	if not cost.is_empty() and not ResourceManager.can_afford(cost):
		return Tr.t("LBL_NOT_ENOUGH_RESOURCES")
	return ""

# ── Calzadas ──────────────────────────────────────────────────────────

static func is_road_at(cell: Vector2i) -> bool:
	var node := GridManager.get_building_at(cell)
	if node == null:
		return false
	var info := GridManager.get_building_info(node)
	return not info.is_empty() and info["data"].id == "road"

## Mascara de vecinos-calzada de la celda (bits de ROAD_DIRS).
static func road_neighbor_mask(cell: Vector2i) -> int:
	var mask := 0
	for d in ROAD_DIRS:
		if is_road_at(cell + d["offset"]):
			mask |= d["bit"]
	return mask

## Las calzadas vecinas de `cell` (nodo + celda), para repintar sus uniones.
static func neighbor_roads(cell: Vector2i) -> Array:
	var out: Array = []
	for d in ROAD_DIRS:
		var c: Vector2i = cell + d["offset"]
		if is_road_at(c):
			out.append({"node": GridManager.get_building_at(c), "cell": c})
	return out

# ── Demoler ───────────────────────────────────────────────────────────

## La parte de demoler que no es dibujo: devuelve la parte del coste, saca el
## edificio de produccion, cancela (con reembolso) lo que tuviera en marcha y lo
## quita de la rejilla. Devuelve {"data", "cell"} o {} si no se puede demoler (no
## es un edificio, o es el Nucleo). Quien llama libera el nodo, repinta lo suyo,
## recuenta almacenes y emite building_demolished.
static func demolish(building: Node) -> Dictionary:
	var info := GridManager.get_building_info(building)
	if info.is_empty():
		return {}
	var data: BuildingData = info["data"]
	if data.is_core:
		return {}
	var cell: Vector2i = info["origin_cell"]
	var cost := data.get_cost()
	for type in cost:
		ResourceManager.add(type, int(cost[type] * GameConfig.demolish_refund_ratio))
	ProductionManager.unregister(building)
	# Demoler con algo en curso ya no lo quema: el proceso se cancela como
	# cualquier otro y devuelve su parte (la Tasa de Corrupcion).
	ProcessManager.cancel(building)
	GridManager.remove_building(building)
	return {"data": data, "cell": cell}

# ── Guardado ──────────────────────────────────────────────────────────

## La entrada de guardado de un edificio. Es el formato de `buildings` en
## save_game.json, identico en las dos vistas: una partida guardada en 3D se
## carga en 2D y al reves porque ninguna de las dos guarda nada propio.
## Devuelve {} si el nodo no es un edificio registrado.
static func serialize_building(building: Node) -> Dictionary:
	var info := GridManager.get_building_info(building)
	if info.is_empty():
		return {}
	var origin: Vector2i = info["origin_cell"]
	var data: BuildingData = info["data"]
	var entry := { "id": data.id, "cell_x": origin.x, "cell_y": origin.y }
	var rot: int = building.get_meta("rotation_steps", 0)
	if rot != 0:
		entry["rotation"] = rot
	var level: int = building.get_meta("level", 1)
	if level > 1:
		entry["level"] = level
	if building.has_meta("custom_name"):
		entry["custom_name"] = building.get_meta("custom_name")
	# Solo se guarda si esta tocado: un save viejo sin la clave significa
	# "entero", que es exactamente lo que queremos por defecto.
	if building.has_meta("health"):
		var hp: int = building.get_meta("health")
		if hp < data.max_health:
			entry["health"] = hp
	if ProductionManager.is_constructing(building):
		entry["construction_remaining"] = ProductionManager.get_construction_remaining(building)
	return entry
