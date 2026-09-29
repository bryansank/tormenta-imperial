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

## "Fundicion + Aserradero": los requisitos de `building_id` con el nombre que
## lee el jugador, no el id interno ("foundry + sawmill").
static func prerequisite_names(building_id: String) -> String:
	var names: Array = []
	for req_id in GameConfig.get_prerequisites(building_id):
		var req := load_building_data(String(req_id))
		names.append(req.get_display_name() if req != null else String(req_id))
	return " + ".join(names)

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
	if not is_connected_spot(building_id, cell, size, ignore_building):
		# Carretera automatica: si hay camino libre hasta la red, el sitio vale y
		# el veredicto lleva los tramos a tender (se pagan al colocar, 1 oro cada
		# uno). Una carretera no se tiende a si misma: esa si tiene que tocar la red.
		if building_id != ROAD_ID:
			var route: Variant = road_route(cell, size)
			if route != null:
				return {"ok": true, "reason": "", "deposit": deposit, "route": route}
		return {"ok": false, "reason": "road", "deposit": deposit}
	return {"ok": true, "reason": "", "deposit": deposit, "route": []}

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

## Tras colocar `data`, se sigue con otro en la mano? Solo lo que se pone en
## serie: decoraciones y caminos (is_decoration), o un edificio que lo pida con
## `repeat_placement`. Una casa, un aserradero o una mina se colocan de uno en
## uno: seguir con el fantasma pegado al cursor invitaba a gastar sin querer.
static func keeps_placing(data: BuildingData) -> bool:
	return data != null and (data.is_decoration or data.repeat_placement)

## Por que no se puede comprar `data` ahora mismo, como texto para el jugador, o
## "" si nada lo impide. En el mismo orden en que lo comprobaba BuildingPlacer:
## tope, requisitos, obreros y coste. No cobra nada.
static func purchase_block_message(data: BuildingData) -> String:
	if not check_building_limit(data.id):
		return Tr.t("LBL_LIMIT_REACHED") % [count_building(data.id), GameConfig.get_building_limit(data.id)]
	if not check_prerequisites(data.id):
		return Tr.t("LBL_REQUIRES") % prerequisite_names(data.id)
	if data.workers_required > 0 and PopulationManager.get_free_workers() < data.workers_required:
		return Tr.t("LBL_NO_WORKERS")
	var cost := data.get_cost()
	if not cost.is_empty() and not ResourceManager.can_afford(cost):
		return Tr.t("LBL_NOT_ENOUGH_RESOURCES")
	return ""

## Coste de `data` por nombre de recurso ("gold" -> 50), en el orden de
## BuildingData.get_cost(). Para ensenarlo con Tr.amount_list().
static func cost_by_name(data: BuildingData) -> Dictionary:
	var out := {}
	var cost := data.get_cost()
	for type in cost:
		out[ResourceManager.get_type_name(type)] = int(cost[type])
	return out

## Lo que le falta al jugador para pagar `data`, por nombre de recurso. {} si llega.
static func missing_cost(data: BuildingData) -> Dictionary:
	var out := {}
	var cost := data.get_cost()
	for type in cost:
		var short: int = int(cost[type]) - ResourceManager.get_amount(type)
		if short > 0:
			out[ResourceManager.get_type_name(type)] = short
	return out

## Como purchase_block_message, pero si lo que falta son recursos dice cuales y
## cuantos ("Te falta: 20 Madera"): "Recursos insuficientes" a secas no dice que
## hacer. Es lo que ven el detalle de CONSTRUIR y el aviso al colocar.
##
## Dice TODO lo que falta, una cosa por linea: el recurso sin desbloquear y
## como se desbloquea, los edificios que faltan antes, el tope, los
## trabajadores y el coste. El Cuartel General al empezar pide acero, petroleo,
## un Cuartel y una Refineria, y antes solo se veia una tarjeta gris.
static func purchase_block_detail(data: BuildingData) -> String:
	return "\n".join(block_reasons(data))

## Lo que impide construir `data` ahora, en frases para el jugador. [] si nada.
static func block_reasons(data: BuildingData) -> Array:
	var out: Array = []
	# Lo que falta de un recurso aun bloqueado se explica como "llega con...":
	# "te faltan 100 de acero" sin acero en el juego no dice que hacer. Si ya lo
	# tienes (del mercado, de un evento) no se bloquea nada: solo falta lo que falta.
	var locked: Array = []
	var short := missing_cost(data)
	for res_id in short.keys():
		if not ResourceManager.is_unlocked_by_name(String(res_id)):
			locked.append(Tr.t("LBL_NEEDS_UNLOCK_ONE") % [Tr.res_name(res_id), Tr.t("UNLOCK_HINT_" + String(res_id).to_upper())])
			short.erase(res_id)
	if not locked.is_empty():
		out.append(Tr.t("LBL_NEEDS_UNLOCK") % Tr.t("LBL_AND_JOIN").join(locked))
	if not check_prerequisites(data.id):
		out.append(Tr.t("LBL_NEEDS_FIRST") % missing_prerequisite_names(data.id))
	if not check_building_limit(data.id):
		out.append(Tr.t("LBL_LIMIT_REACHED") % [count_building(data.id), GameConfig.get_building_limit(data.id)])
	if data.workers_required > 0 and PopulationManager.get_free_workers() < data.workers_required:
		out.append(Tr.t("LBL_NEEDS_WORKERS") % [data.workers_required, PopulationManager.get_free_workers()])
	if not short.is_empty():
		out.append(Tr.t("OBJ_MISSING") % Tr.amount_list(short))
	return out

## Los requisitos que aun no estan en pie, con su nombre.
static func missing_prerequisite_names(building_id: String) -> String:
	var names: Array = []
	for req_id in GameConfig.get_prerequisites(building_id):
		if count_building(String(req_id)) < 1:
			var req := load_building_data(String(req_id))
			names.append(req.get_display_name() if req != null else String(req_id))
	return " + ".join(names)

# ── Red de carreteras (2026-09-28) ─────────────────────────────────────
#
# Todo edificio tiene que tocar una carretera unida al Nucleo, y toda carretera
# nueva tiene que tocar la red (o el propio Nucleo). La partida empieza con una
# acera alrededor del Nucleo (GameManager.pave_core_ring), asi que la red
# siempre nace de el. Sin Nucleo en la rejilla (una escena de prueba montada a
# mano) no hay red que exigir y la regla no se aplica.

const ROAD_ID := "road"
const NEIGHBORS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Las celdas del Nucleo, o [] si no hay.
static func core_cells() -> Array:
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info.get("data")
		if data != null and data.is_core:
			return info.get("cells", [])
	return []

## Las celdas de carretera unidas al Nucleo (celda -> true). `ignore` es una
## carretera que no cuenta: la que se esta moviendo o se quiere quitar.
static func connected_roads(ignore: Node = null) -> Dictionary:
	var core := core_cells()
	var out := {}
	if core.is_empty():
		return out
	var queue: Array = []
	for c in core:
		for d in NEIGHBORS4:
			var n: Vector2i = c + d
			if not out.has(n) and _is_road_cell(n, ignore):
				out[n] = true
				queue.append(n)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in NEIGHBORS4:
			var n: Vector2i = cur + d
			if not out.has(n) and _is_road_cell(n, ignore):
				out[n] = true
				queue.append(n)
	return out

static func _is_road_cell(cell: Vector2i, ignore: Node) -> bool:
	var node := GridManager.get_building_at(cell)
	if node == null or node == ignore:
		return false
	var info := GridManager.get_building_info(node)
	return not info.is_empty() and (info["data"] as BuildingData).id == ROAD_ID

## La huella toca la red (celdas de `connected_roads()`)?
static func touches_network(cells: Array, network: Dictionary) -> bool:
	return _touches(cells, network)

## Algun vecino (4 lados) de la huella esta en `targets`.
static func _touches(cells: Array, targets: Dictionary) -> bool:
	for c in cells:
		for d in NEIGHBORS4:
			if targets.has(c + d):
				return true
	return false

## Se puede plantar `building_id` en esa huella sin quedar suelto de la red?
static func is_connected_spot(building_id: String, cell: Vector2i, size: Vector2i, ignore: Node = null) -> bool:
	var core := core_cells()
	if core.is_empty():
		return true
	var data := load_building_data(building_id)
	if data != null and data.is_core:
		return true
	var cells: Array = GridManager.cells_for(cell, size)
	var network := connected_roads(ignore)
	if building_id == ROAD_ID:
		var core_set := {}
		for c in core:
			core_set[c] = true
		return _touches(cells, network) or _touches(cells, core_set)
	return _touches(cells, network)

## Quitar esta carretera dejaria algun edificio sin conexion? Devuelve el
## primero que se quedaria suelto, o null.
static func road_removal_strands(road: Node) -> Node:
	if core_cells().is_empty():
		return null
	var network := connected_roads(road)
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info.get("data")
		if data == null or data.is_core or info.get("node") == road:
			continue
		if data.id == ROAD_ID:
			# Una carretera que se queda suelta no rompe nada por si sola: lo que
			# importa es el edificio al que llevaba.
			continue
		if not _touches(info.get("cells", []), network):
			# Ya estaba suelto antes (partida cargada): no es culpa de esta.
			if _touches(info.get("cells", []), connected_roads()):
				return info.get("node")
	return null

## Las celdas libres que hay que pavimentar para unir una huella a la red, por
## el camino mas corto (sin pisar edificios, yacimientos ni la propia huella).
## [] si ya toca la red; null si no hay camino. Lo usan las pruebas y las sondas
## que juegan solas, y el aviso de "te falta carretera".
static func road_route(cell: Vector2i, size: Vector2i) -> Variant:
	var footprint := {}
	for c in GridManager.cells_for(cell, size):
		footprint[c] = true
	var network := connected_roads()
	if network.is_empty():
		var core := core_cells()
		for c in core:
			network[c] = true
	if _touches(footprint.keys(), network):
		return []
	# BFS desde las celdas libres pegadas a la huella hasta tocar la red.
	var came := {}
	var queue: Array = []
	for c in footprint:
		for d in NEIGHBORS4:
			var n: Vector2i = c + d
			if not footprint.has(n) and not came.has(n) and GridManager.is_valid_cell(n) and GridManager.is_cell_free(n):
				came[n] = null
				queue.append(n)
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for d in NEIGHBORS4:
			if network.has(cur + d):
				var path: Array = []
				var step: Variant = cur
				while step != null:
					path.append(step)
					step = came[step]
				return path
		for d in NEIGHBORS4:
			var n: Vector2i = cur + d
			if not footprint.has(n) and not came.has(n) and GridManager.is_valid_cell(n) and GridManager.is_cell_free(n):
				came[n] = cur
				queue.append(n)
	return null

## Lo que cuestan los tramos de `route` (Type -> cantidad).
static func route_cost(route: Array) -> Dictionary:
	var out := {}
	if route.is_empty():
		return out
	var road := load_building_data(ROAD_ID)
	if road == null:
		return out
	var one := road.get_cost()
	for type in one:
		out[type] = int(one[type]) * route.size()
	return out

## El coste del edificio mas el de su carretera automatica.
static func cost_with_route(data: BuildingData, route: Array) -> Dictionary:
	var total := data.get_cost()
	var extra := route_cost(route)
	for type in extra:
		total[type] = int(total.get(type, 0)) + int(extra[type])
	return total

## Tiende (y cobra) los tramos de la carretera automatica con `placer` (el de 3D
## o el de 2D: los dos tienen place_building_at). Emite building_placed por cada
## tramo, como si el jugador lo hubiera puesto: guardado, trabajadores y
## trabajadores que andan se enteran. Devuelve cuantos puso.
static func pave_route(placer: Node, route: Array) -> int:
	var road := load_building_data(ROAD_ID)
	if road == null or route.is_empty():
		return 0
	var cost := route_cost(route)
	if not cost.is_empty():
		ResourceManager.spend_cost(cost)
	var n := 0
	for c in route:
		if placer.place_building_at(road, c) != null:
			n += 1
			EventBus.building_placed.emit(road, c)
	return n

## Un extractor (Aserradero, Mina de oro, Fundicion) necesita su veta viva al
## lado para funcionar (2026-09-28): si se agota a mano, se para. Los que no
## tienen regla, y la Refineria (que se come su pozo al colocarse), siempre
## tienen. Sin generador de mapa (pruebas sueltas) no se exige.
static func has_its_deposit(data: BuildingData, cells: Array, map_gen: Node) -> bool:
	var rule: Dictionary = GameConfig.get_deposit_rule(data.id)
	if rule.is_empty() or bool(rule.get("consumes", false)):
		return true
	if map_gen == null or not is_instance_valid(map_gen) or not map_gen.has_method("find_deposit_near_cells"):
		return true
	return map_gen.find_deposit_near_cells(String(rule["deposit"]), cells, int(rule["reach"])) != null

## La ruta a pie del Nucleo a `target` por la red: celdas de carretera, de la
## que toca el Nucleo a la que toca el edificio. [] si no hay (sin Nucleo, sin
## red, o el edificio suelto). La usan los trabajadores que se ven andar.
static func walk_route(target: Node) -> Array:
	var info := GridManager.get_building_info(target)
	if info.is_empty():
		return []
	var network := connected_roads()
	if network.is_empty():
		return []
	var goal := {}
	for c in info.get("cells", []):
		for d in NEIGHBORS4:
			if network.has(c + d):
				goal[c + d] = true
	if goal.is_empty():
		return []
	var core := core_cells()
	var came := {}
	var queue: Array = []
	for c in core:
		for d in NEIGHBORS4:
			var n: Vector2i = c + d
			if network.has(n) and not came.has(n):
				came[n] = null
				queue.append(n)
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if goal.has(cur):
			var path: Array = []
			var step: Variant = cur
			while step != null:
				path.push_front(step)
				step = came[step]
			return path
		for d in NEIGHBORS4:
			var n: Vector2i = cur + d
			if network.has(n) and not came.has(n):
				came[n] = cur
				queue.append(n)
	return []

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
	if data.id == ROAD_ID and road_removal_strands(building) != null:
		return {"blocked": Tr.t("LBL_ROAD_NEEDED_BY")}
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
	# El jugador le retiro los trabajadores: se guarda solo si es asi.
	if bool(building.get_meta("workers_off", false)):
		entry["workers_off"] = true
	# Solo se guarda si esta tocado: un save viejo sin la clave significa
	# "entero", que es exactamente lo que queremos por defecto.
	if building.has_meta("health"):
		var hp: int = building.get_meta("health")
		if hp < data.max_health:
			entry["health"] = hp
	if ProductionManager.is_constructing(building):
		entry["construction_remaining"] = ProductionManager.get_construction_remaining(building)
		# Una mejora en obras no es una obra: sin esto volvia de la carga
		# como construccion normal y el edificio nunca subia de nivel.
		var upgrade_to: int = ProductionManager.get_upgrade_target(building)
		if upgrade_to > 0:
			entry["upgrade_to"] = upgrade_to
	return entry
