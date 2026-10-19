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

## BuildingData original (sin girar) desde su .tres, o null. Se recuerda por id:
## evaluate_placement la pide en cada casilla que mira el fantasma, y cada load()
## pagaba exists, formato de ruta y el cerrojo de la cache del motor (docs/26).
## Es el mismo recurso que daria load(): la cache solo lo mantiene vivo.
static var _data_cache: Dictionary = {}

static func load_building_data(building_id: String) -> BuildingData:
	if _data_cache.has(building_id):
		return _data_cache[building_id]
	var path := "res://data/buildings/%s.tres" % building_id
	var data: BuildingData = null
	if ResourceLoader.exists(path):
		data = load(path) as BuildingData
	if data != null:
		_data_cache[building_id] = data
	return data

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
## Devuelve {"ok": bool, "reason": "" | "water" | "deposit" | "occupied" | "road",
## "deposit": Node}. "water": alguna celda de la huella es agua (la de la isla
## irregular o la de fuera de la rejilla); ni edificios ni carreteras.
static func evaluate_placement(building_id: String, cell: Vector2i, size: Vector2i, map_gen: Node, ignore_building: Node = null) -> Dictionary:
	if not on_land(cell, size):
		return {"ok": false, "reason": "water", "deposit": null}
	var rule: Dictionary = GameConfig.get_deposit_rule(building_id)
	if (needs_shore(building_id) or bool(rule.get("shore", false))) and not touches_shore(cell, size):
		# El Muelle de pesca (regla "shore") dice su propia frase: "deposit".
		return {"ok": false, "reason": SHORE_REASON if rule.is_empty() else "deposit", "deposit": null}
	var deposit: Node = null
	if not rule.is_empty():
		var cells: Array = GridManager.cells_for(cell, size)
		if map_gen != null and map_gen.has_method("find_deposit_near_cells"):
			deposit = deposit_with_room(building_id, rule, cells, map_gen, ignore_building)
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

## El yacimiento que trabajaria `building_id` desde `cells`: el mas cercano a
## su alcance. Con tope por yacimiento (regla "per_deposit": un banco de peces
## sirve a 2 muelles, fix/peces-en-el-mar), el mas cercano que aun tiene sitio.
## "Tener sitio" no guarda a que banco va cada muelle: se reparte (un
## emparejamiento con capacidades, pocos muelles y pocos bancos) y el nuevo cabe
## si con el no queda ningun muelle de antes sin banco. Un muelle de una partida
## vieja que ya pasaba del tope no bloquea a los demas: solo cuenta lo que se
## pierde con el nuevo. Solo al evaluar un sitio, nunca por fotograma.
static func deposit_with_room(building_id: String, rule: Dictionary, cells: Array, map_gen: Node, ignore_building: Node = null) -> Node:
	var deposit_id := String(rule["deposit"])
	var reach := int(rule["reach"])
	var cap := int(rule.get("per_deposit", 0))
	if cap <= 0 or not map_gen.has_method("find_deposits_near_cells"):
		return map_gen.find_deposit_near_cells(deposit_id, cells, reach)
	var near: Array = map_gen.find_deposits_near_cells(deposit_id, cells, reach)
	if near.is_empty():
		return null
	var others: Array = []
	for info in GridManager.buildings_view():
		var data: BuildingData = info["data"]
		if data == null or data.id != building_id or info["node"] == ignore_building:
			continue
		var options: Array = map_gen.find_deposits_near_cells(deposit_id, info["cells"], reach)
		if not options.is_empty():
			others.append(options)
	if others.is_empty():
		return near[0]
	var before := _max_matching(others, cap, {})
	for dep in near:
		if _max_matching(others, cap, {dep: cap - 1}) == before:
			return dep
	return null

## Cuantos de `options` (por muelle, los yacimientos que alcanza) se pueden
## repartir sin pasar de `cap` por yacimiento (`caps` cambia el tope de alguno).
## Caminos de aumento (Kuhn): con 6 muelles y 5 bancos, unas decenas de pasos.
static func _max_matching(options: Array, cap: int, caps: Dictionary) -> int:
	var held := {}
	var n := 0
	for i in options.size():
		if _augment(i, options, cap, caps, held, {}):
			n += 1
	return n

static func _augment(i: int, options: Array, cap: int, caps: Dictionary, held: Dictionary, seen: Dictionary) -> bool:
	for dep in options[i]:
		if seen.has(dep):
			continue
		seen[dep] = true
		var list: Array = held.get(dep, [])
		if list.size() < int(caps.get(dep, cap)):
			list.append(i)
			held[dep] = list
			return true
		for j in list.duplicate():
			if _augment(j, options, cap, caps, held, seen):
				list.erase(j)
				list.append(i)
				held[dep] = list
				return true
	return false

## ¿Cae toda la huella en tierra?
static func on_land(cell: Vector2i, size: Vector2i) -> bool:
	for c in GridManager.cells_for(cell, size):
		if not GridManager.is_land_cell(c):
			return false
	return true

# ── Costa (feat/decoraciones-remates) ─────────────────────────────────

## Lo que solo se planta en la costa: las palmeras y el Astillero (aire y mar:
## los barcos salen al agua). Motivo del veredicto y su aviso (LBL_NEEDS_SHORE),
## el mismo en 3D y en 2D.
const SHORE_ONLY := ["palm_trees", "shipyard"]
const SHORE_REASON := "shore"
const NEIGHBORS8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

static func needs_shore(building_id: String) -> bool:
	return building_id in SHORE_ONLY

## ¿Es `cell` tierra pegada al agua (contando diagonales)? La misma franja que
## MapGenerator.is_shore_cell() con map_shore_band = 1: el agua de dentro de la
## rejilla y la de fuera (todo lo que no es celda de tierra).
static func is_coast_cell(cell: Vector2i) -> bool:
	if not GridManager.is_land_cell(cell):
		return false
	for d in NEIGHBORS8:
		if not GridManager.is_land_cell(cell + d):
			return true
	return false

## ¿Toca la huella la costa? Basta una de sus celdas pegada al agua.
static func touches_shore(cell: Vector2i, size: Vector2i) -> bool:
	for c in GridManager.cells_for(cell, size):
		if is_coast_cell(c):
			return true
	return false

## Lo que se orienta solo al agua al colocarlo: el Astillero tiene la darsena en
## su lado de delante (+Z del modelo 3D, +y local del dibujo 2D). El fantasma se
## gira para que mire al agua mas cercana; el jugador aun puede girarlo a mano
## (entonces deja de girarse solo hasta el proximo edificio).
const FACES_WATER := ["shipyard"]
## Hasta cuantas celdas fuera de la huella se busca el agua.
const FACE_WATER_REACH := 4
## Lados del mundo en orden de giro: N (-y), E (+x), S (+y), O (-x).
const SIDE_OFFSETS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

static func faces_water(building_id: String) -> bool:
	return building_id in FACES_WATER

## El lado del mundo (0 N, 1 E, 2 S, 3 O) con el agua mas cercana a la huella, o
## -1 si no hay agua a FACE_WATER_REACH celdas. Por anillos: gana el lado que ve
## agua a menos distancia; a igual distancia, el que ve mas celdas de agua (y a
## igualdad, S, E, N, O). Unas decenas de consultas, y solo cuando el fantasma
## cambia de celda: nada por fotograma.
static func water_side(origin: Vector2i, size: Vector2i) -> int:
	for d in range(1, FACE_WATER_REACH + 1):
		var best := -1
		var best_count := 0
		for side in [2, 1, 0, 3]:
			var count := 0
			for c in _side_strip(origin, size, side, d):
				if not GridManager.is_land_cell(c):
					count += 1
			if count > best_count:
				best = side
				best_count = count
		if best >= 0:
			return best
	return -1

## Las celdas a distancia `d` del lado `side` de la huella, una celda mas ancha
## por cada punta (las diagonales cuentan como de ese lado).
static func _side_strip(origin: Vector2i, size: Vector2i, side: int, d: int) -> Array:
	var cells: Array = []
	match side:
		0, 2:
			var y: int = origin.y - d if side == 0 else origin.y + size.y - 1 + d
			for x in range(origin.x - 1, origin.x + size.x + 1):
				cells.append(Vector2i(x, y))
		_:
			var x: int = origin.x + size.x - 1 + d if side == 1 else origin.x - d
			for y in range(origin.y - 1, origin.y + size.y + 1):
				cells.append(Vector2i(x, y))
	return cells

## Cuartos de vuelta para que el lado de delante del edificio mire al lado del
## mundo `side`. `clockwise` = false es el convenio de `rotation_steps` (el de la
## vista 3D, el que se guarda: los dos colocadores lo usan); true, el del giro de
## un Node2D, que es el que Building2D.view_steps() dibuja.
static func steps_to_face(side: int, clockwise: bool) -> int:
	return posmod(side - 2, 4) if clockwise else posmod(2 - side, 4)

## El giro que pone la darsena de `building_id` mirando al agua mas cercana
## desde `origin`, o -1 si no se orienta solo o no hay agua cerca.
static func steps_facing_water(building_id: String, origin: Vector2i, size: Vector2i, clockwise: bool) -> int:
	if not faces_water(building_id):
		return -1
	var side := water_side(origin, size)
	return -1 if side < 0 else steps_to_face(side, clockwise)

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
	return GridManager.count_by_id(building_id)

static func check_building_limit(building_id: String) -> bool:
	var limit := GameConfig.get_building_limit(building_id)
	if limit < 0:
		return true
	return count_building(building_id) < limit

## El rango del gobernador abre decoraciones y edificios opcionales
## (GameConfig.rank_rewards). Sandbox lo tiene todo abierto.
static func check_rank(building_id: String) -> bool:
	return RankManager.is_building_unlocked(building_id)

## "Necesitas rango 5": lo que dice el detalle de CONSTRUIR y el aviso al colocar.
static func rank_lock_text(building_id: String) -> String:
	return Tr.t("LBL_RANK_NEEDED") % RankManager.building_rank(building_id)

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
	if not check_rank(data.id):
		return rank_lock_text(data.id)
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
	# Bloqueado por rango: es lo primero y lo unico que importa, el resto llega
	# despues de subir.
	if not check_rank(data.id):
		out.append(rank_lock_text(data.id))
		return out
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

## Como block_reasons, en corto, para la linea junto al boton CONSTRUIR (la fila
## del coste ya marca en rojo lo que falta): el recurso bloqueado solo por su
## nombre (como llega va en el tooltip, que es block_reasons entero) y lo que
## falta separado por comas.
static func block_reasons_short(data: BuildingData) -> Array:
	var out: Array = []
	var locked: Array = []
	var short := missing_cost(data)
	for res_id in short.keys():
		if not ResourceManager.is_unlocked_by_name(String(res_id)):
			locked.append(Tr.res_name(res_id))
			short.erase(res_id)
	if not locked.is_empty():
		out.append(Tr.t("LBL_NEEDS_UNLOCK") % ", ".join(locked))
	if not check_prerequisites(data.id):
		out.append(Tr.t("LBL_NEEDS_FIRST") % missing_prerequisite_names(data.id))
	if not check_building_limit(data.id):
		out.append(Tr.t("LBL_LIMIT_REACHED") % [count_building(data.id), GameConfig.get_building_limit(data.id)])
	if data.workers_required > 0 and PopulationManager.get_free_workers() < data.workers_required:
		out.append(Tr.t("LBL_NEEDS_WORKERS") % [data.workers_required, PopulationManager.get_free_workers()])
	if not short.is_empty():
		var parts: Array = []
		for res_id in short:
			parts.append("%d %s" % [int(short[res_id]), Tr.res_name(res_id)])
		out.append(Tr.t("OBJ_MISSING") % ", ".join(parts))
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

# ── Caches de la red (docs/26 §6.5) ──
#
# El Nucleo, la red unida a el y las rutas del auto-road solo cambian cuando
# cambia que hay en alguna celda, y eso lo cuenta GridManager.map_version().
# Antes cada evaluate_placement hacia 2-3 recorridos de todos los edificios
# para encontrar el Nucleo y uno o dos BFS de la red; el fantasma lo pedia en
# cada casilla y PlacementAssist.valid_spots en 100-250 origenes seguidos. Ahora
# se calcula una vez por version del mapa y se reutiliza. Lo que se devuelve
# desde aqui es lo mismo que se calculaba; las vistas compartidas (network_view,
# core_cells) son de solo lectura.
static var _cache_version := -1
static var _core_cache: Variant = null      # Array o null (sin calcular)
static var _core_set_cache: Variant = null  # Dictionary celda -> true
static var _network_cache: Variant = null   # Dictionary celda -> true
static var _route_cache: Dictionary = {}    # Vector4i(celda, huella) -> Array o null
static var _reach_cache: Variant = null     # Dictionary: celdas libres que llegan a la red

static func _sync_cache() -> void:
	var v: int = GridManager.map_version()
	if v == _cache_version:
		return
	_cache_version = v
	_core_cache = null
	_core_set_cache = null
	_network_cache = null
	_route_cache.clear()
	_reach_cache = null

## Las celdas del Nucleo, o [] si no hay. De solo lectura (es la de la rejilla).
static func core_cells() -> Array:
	_sync_cache()
	if _core_cache == null:
		_core_cache = []
		for info in GridManager.buildings_view():
			var data: BuildingData = info.get("data")
			if data != null and data.is_core:
				_core_cache = info.get("cells", [])
				break
	return _core_cache

static func _core_set() -> Dictionary:
	_sync_cache()
	if _core_set_cache == null:
		var s := {}
		for c in core_cells():
			s[c] = true
		_core_set_cache = s
	return _core_set_cache

## La red unida al Nucleo SIN copiar, de solo lectura: para quien solo pregunta
## (recuento de trabajadores, minar a mano, rutas a pie). Para tocarla,
## connected_roads(), que da una copia.
static func network_view() -> Dictionary:
	_sync_cache()
	if _network_cache == null:
		_network_cache = _compute_network(null, {})
	return _network_cache

## Las celdas de carretera unidas al Nucleo (celda -> true). `ignore` es una
## carretera que no cuenta: la que se esta moviendo o se quiere quitar. `extra`
## (celda -> true) son celdas que cuentan como carretera aunque aun no lo sean:
## adonde se lleva la que se mueve. Devuelve un diccionario propio (se puede
## tocar); sin `ignore` de carretera ni `extra` sale de la cache.
static func connected_roads(ignore: Node = null, extra: Dictionary = {}) -> Dictionary:
	if extra.is_empty() and not _is_road_node(ignore):
		return network_view().duplicate()
	return _compute_network(ignore, extra)

## `node` es una carretera de la rejilla. Un `ignore` que no lo es no cambia la red.
static func _is_road_node(node: Node) -> bool:
	if node == null:
		return false
	var info := GridManager.get_building_info(node)
	return not info.is_empty() and (info["data"] as BuildingData).id == ROAD_ID

static func _compute_network(ignore: Node, extra: Dictionary) -> Dictionary:
	var core := core_cells()
	var out := {}
	if core.is_empty():
		return out
	var queue: Array = []
	for c in core:
		for d in NEIGHBORS4:
			var n: Vector2i = c + d
			if not out.has(n) and (extra.has(n) or _is_road_cell(n, ignore)):
				out[n] = true
				queue.append(n)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in NEIGHBORS4:
			var n: Vector2i = cur + d
			if not out.has(n) and (extra.has(n) or _is_road_cell(n, ignore)):
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
	var network: Dictionary = network_view() if not _is_road_node(ignore) else _compute_network(ignore, {})
	if building_id == ROAD_ID:
		return _touches(cells, network) or _touches(cells, _core_set())
	return _touches(cells, network)

## "Si quito un camino, primero me hace mover los edificios" (2026-10-04).
## Los edificios que se quedarian sin conexion al Nucleo si `road` desaparece, o
## si se lleva a `new_cells` (al MOVERla). Cuentan los edificios de verdad,
## tambien los que estan en obras; no cuentan el Nucleo, las decoraciones ni
## otras carreteras (una calle suelta no rompe nada por si sola), ni lo que ya
## estaba suelto antes (partida vieja): no es culpa de este tramo. [] si se puede
## quitar. La usan demoler y mover, en 3D y en 2D.
static func road_removal_stranded(road: Node, new_cells: Array = []) -> Array:
	var out: Array = []
	if road == null or core_cells().is_empty():
		return out
	var extra := {}
	for c in new_cells:
		extra[c] = true
	var before := network_view()
	var after := connected_roads(road, extra)
	for info in GridManager.buildings_view():
		var data: BuildingData = info.get("data")
		var node: Node = info.get("node")
		if data == null or data.is_core or data.is_decoration or node == road:
			continue
		var cells: Array = info.get("cells", [])
		if _touches(cells, before) and not _touches(cells, after):
			out.append(node)
	return out

## El primero de road_removal_stranded(), o null. Se queda por compatibilidad.
static func road_removal_strands(road: Node) -> Node:
	var stranded := road_removal_stranded(road)
	return stranded[0] if not stranded.is_empty() else null

## El aviso corto de "primero mueve": "Primero mueve: Aserradero, Mina de oro".
## Nombres sin repetir, como mucho `road_block_max_names`, y "+N" con el resto.
static func move_first_message(nodes: Array) -> String:
	var names: Array = []
	for n in nodes:
		var info := GridManager.get_building_info(n) if is_instance_valid(n) else {}
		if info.is_empty():
			continue
		var data: BuildingData = info["data"]
		var nm := data.get_display_name()
		if not names.has(nm):
			names.append(nm)
	var shown: Array = names.slice(0, GameConfig.road_block_max_names)
	var text := ", ".join(shown)
	if names.size() > shown.size():
		text += " +%d" % (names.size() - shown.size())
	return Tr.t("LBL_MOVE_FIRST") % text

## Las celdas libres que hay que pavimentar para unir una huella a la red, por
## el camino mas corto (sin pisar edificios, yacimientos ni la propia huella).
## [] si ya toca la red; null si no hay camino. Lo usan las pruebas y las sondas
## que juegan solas, y el aviso de "te falta carretera".
##
## El resultado se recuerda por version del mapa (celda + huella): el fantasma y
## valid_spots preguntan muchas veces por el mismo sitio sin que cambie nada.
static func road_route(cell: Vector2i, size: Vector2i) -> Variant:
	_sync_cache()
	var key := Vector4i(cell.x, cell.y, size.x, size.y)
	if _route_cache.has(key):
		var hit: Variant = _route_cache[key]
		return (hit as Array).duplicate() if hit != null else null
	var route: Variant = _compute_road_route(cell, size)
	_route_cache[key] = route
	return (route as Array).duplicate() if route != null else null

## Adonde tiene que llegar una ruta: la red o, sin red, el propio Nucleo.
static func _route_targets() -> Dictionary:
	var network := network_view()
	return network if not network.is_empty() else _core_set()

## Prepara una tanda de road_route() seguidas (PlacementAssist.valid_spots):
## calcula una vez las celdas libres desde las que se puede llegar a la red. Un
## sitio cuyas celdas de salida no estan en ese conjunto no tiene ruta, y se
## descarta sin el BFS por toda la rejilla libre que costaba antes cada fallo.
static func prepare_route_queries() -> void:
	_sync_cache()
	if _reach_cache != null:
		return
	var targets := _route_targets()
	var reach := {}
	var queue: Array = []
	for t in targets:
		for d in NEIGHBORS4:
			var n: Vector2i = t + d
			if not reach.has(n) and GridManager.is_cell_free(n):
				reach[n] = true
				queue.append(n)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in NEIGHBORS4:
			var n: Vector2i = cur + d
			if not reach.has(n) and GridManager.is_cell_free(n):
				reach[n] = true
				queue.append(n)
	_reach_cache = reach

static func _compute_road_route(cell: Vector2i, size: Vector2i) -> Variant:
	var footprint := {}
	for c in GridManager.cells_for(cell, size):
		footprint[c] = true
	var network := _route_targets()
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
	# Con la tanda preparada: si ninguna celda de salida llega a la red (ni
	# pasando por la huella), no hay ruta. Sin preparar, el BFS de siempre.
	if _reach_cache != null:
		var any := false
		for n in queue:
			if (_reach_cache as Dictionary).has(n):
				any = true
				break
		if not any:
			return null
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
##
## Los tramos van en una tanda (docs/26 §6.4): entre `placement_batch_started` y
## `placement_batch_finished` quien hace trabajo caro por building_placed
## (GameManager guarda, PopulationManager recuenta) solo apunta que hay algo, y
## lo hace UNA vez al cerrar la tanda, todavia dentro de esta llamada. Antes una
## ruta de 15 tramos eran 15 guardados y 15 recuentos en el mismo fotograma.
static func pave_route(placer: Node, route: Array) -> int:
	var road := load_building_data(ROAD_ID)
	if road == null or route.is_empty():
		return 0
	var cost := route_cost(route)
	if not cost.is_empty():
		ResourceManager.spend_cost(cost)
	var n := 0
	EventBus.placement_batch_started.emit()
	for c in route:
		if placer.place_building_at(road, c) != null:
			n += 1
			EventBus.building_placed.emit(road, c)
	EventBus.placement_batch_finished.emit(n)
	return n

# ── Carretera larga (2026-10-19, feat/carretera-arrastrar) ─────────────
#
# Con la carretera en la mano, arrastrar (raton) o tocar inicio y fin (dedo)
# tiende un tramo entero de una vez. Aqui viven las reglas, sin vista:
#
# - El camino es recto o en L, primero por el eje mas largo (`flip` cambia el
#   codo: R o ↻). Si esa L choca, se prueba la otra; si las dos chocan, el
#   camino mas corto por celdas libres (BFS). Si no hay ninguno, el tramo sale
#   rojo con la razon de la primera celda que estorba.
# - Las celdas que ya son carretera se atraviesan y no se cobran.
# - El tramo tiene que tocar la red unida al Nucleo (o el Nucleo) en algun
#   punto, como una carretera suelta. Sin Nucleo (escenas de prueba) no hay regla.
# - Se tiende en orden desde la red hacia fuera. Si el oro no llega para todo,
#   se ponen los tramos que se pueden pagar, los mas cercanos a la red (nunca
#   queda un trozo suelto), y se dice cuantos faltaron. Decision: mejor avanzar
#   hasta donde llegue que no poner nada.

## Las celdas de un tramo recto o en L de `a` a `b`, puntas incluidas: primero el
## eje mas largo (empate: horizontal); con `flip`, el otro.
static func road_line_cells(a: Vector2i, b: Vector2i, flip: bool = false) -> Array:
	var d := b - a
	var x_first := absi(d.x) >= absi(d.y)
	if flip:
		x_first = not x_first
	var out: Array = [a]
	var cur := a
	for axis in ([0, 1] if x_first else [1, 0]):
		if axis == 0:
			while cur.x != b.x:
				cur.x += signi(d.x)
				out.append(cur)
		else:
			while cur.y != b.y:
				cur.y += signi(d.y)
				out.append(cur)
	return out

## Se puede pasar por `c`: tierra y libre, o ya carretera.
static func _road_passable(c: Vector2i) -> bool:
	return GridManager.is_land_cell(c) and (GridManager.is_cell_free(c) or _is_road_cell(c, null))

## "" si todo el camino es transitable; si no, la razon de la primera celda que
## estorba ("water" o "occupied").
static func _road_line_blocker(cells: Array) -> String:
	for c in cells:
		if not GridManager.is_land_cell(c):
			return "water"
		if not _road_passable(c):
			return "occupied"
	return ""

## El camino mas corto de `a` a `b` por celdas transitables, o null.
static func _road_bfs(a: Vector2i, b: Vector2i) -> Variant:
	if not _road_passable(a) or not _road_passable(b):
		return null
	var came := {a: null}
	var queue: Array = [a]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur == b:
			var path: Array = []
			var step: Variant = cur
			while step != null:
				path.push_front(step)
				step = came[step]
			return path
		for d in NEIGHBORS4:
			var n: Vector2i = cur + d
			if not came.has(n) and _road_passable(n):
				came[n] = cur
				queue.append(n)
	return null

## Las celdas nuevas de `cells` (las que no son ya carretera), ordenadas por su
## distancia, a lo largo del camino, a un punto que toca la red: asi cualquier
## prefijo queda unido. null si el camino no toca la red ni el Nucleo.
static func _road_line_order(cells: Array) -> Variant:
	var n := cells.size()
	var anchor: Array = []
	anchor.resize(n)
	var any := false
	var free_rule := core_cells().is_empty()
	var network := network_view()
	var core := _core_set()
	for i in n:
		var c: Vector2i = cells[i]
		var a := (i == 0) if free_rule else (network.has(c) or _touches([c], network) or _touches([c], core))
		anchor[i] = a
		any = any or a
	if not any:
		return null
	# Distancia por el camino al ancla mas cercana: una pasada hacia delante y
	# otra hacia atras.
	var dist: Array = []
	dist.resize(n)
	var last := -1
	for i in n:
		if anchor[i]:
			last = i
		dist[i] = (i - last) if last >= 0 else n * 2
	last = -1
	for i in range(n - 1, -1, -1):
		if anchor[i]:
			last = i
		if last >= 0:
			dist[i] = mini(dist[i], last - i)
	var idx: Array = []
	for i in n:
		if not _is_road_cell(cells[i], null):
			idx.append(i)
	idx.sort_custom(func(p, q): return dist[p] < dist[q] or (dist[p] == dist[q] and p < q))
	var out: Array = []
	for i in idx:
		out.append(cells[i])
	return out

## El plan de una carretera larga de `a` a `b`:
## {"start", "end", "cells" (el camino, en orden), "new" (las celdas a tender,
## desde la red hacia fuera), "ok", "reason" ("" | "water" | "occupied" |
## "road" | "built"), "affordable" (cuantos tramos de "new" se pueden pagar)}.
## "built": todo el camino ya es carretera. Puro: no tiende ni cobra nada.
static func plan_road_line(a: Vector2i, b: Vector2i, flip: bool = false) -> Dictionary:
	var out := {"start": a, "end": b, "cells": [], "new": [], "ok": false, "reason": "", "affordable": 0}
	if not GridManager.is_valid_cell(a) or not GridManager.is_valid_cell(b):
		out["reason"] = "water"
		return out
	var first := road_line_cells(a, b, flip)
	var reason := _road_line_blocker(first)
	var cells: Variant = first
	if reason != "":
		var second := road_line_cells(a, b, not flip)
		cells = second if _road_line_blocker(second) == "" else _road_bfs(a, b)
	if cells == null:
		out["cells"] = first
		out["reason"] = reason
		return out
	out["cells"] = cells
	var ordered: Variant = _road_line_order(cells)
	if ordered == null:
		out["reason"] = "road"
		out["new"] = (cells as Array).filter(func(c): return not _is_road_cell(c, null))
		return out
	if (ordered as Array).is_empty():
		out["reason"] = "built"
		return out
	out["new"] = ordered
	out["ok"] = true
	out["affordable"] = affordable_road_tiles((ordered as Array).size())
	return out

## Cuantos tramos de carretera (hasta `wanted`) se pueden pagar ahora.
static func affordable_road_tiles(wanted: int) -> int:
	var road := load_building_data(ROAD_ID)
	if road == null or road.get_cost().is_empty():
		return wanted
	var one := road.get_cost()
	var lo := 0
	var hi := wanted
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		var cost := {}
		for type in one:
			cost[type] = int(one[type]) * mid
		if ResourceManager.can_afford(cost):
			lo = mid
		else:
			hi = mid - 1
	return lo

## Tiende (y cobra) una carretera larga con `placer`, rehaciendo el plan con el
## mapa y el oro de ahora. Devuelve {"laid", "wanted", "reason"}: puestos,
## los que pedia el tramo y por que no (la razon del plan, o "gold").
static func lay_road_line(placer: Node, a: Vector2i, b: Vector2i, flip: bool = false) -> Dictionary:
	var plan := plan_road_line(a, b, flip)
	var wanted: int = (plan["new"] as Array).size()
	if not bool(plan["ok"]):
		return {"laid": 0, "wanted": wanted, "reason": String(plan["reason"])}
	var k := int(plan["affordable"])
	if k <= 0:
		return {"laid": 0, "wanted": wanted, "reason": "gold"}
	var laid := pave_route(placer, (plan["new"] as Array).slice(0, k))
	return {"laid": laid, "wanted": wanted, "reason": "" if laid >= wanted else "gold"}

## El rotulo de la vista previa: "12 tramos · 12 oro", "Solo hay oro para 5 de
## 12 tramos" o por que no se puede.
static func road_line_label(plan: Dictionary) -> String:
	if plan.is_empty():
		return ""
	if not bool(plan["ok"]):
		return road_line_reason_text(String(plan["reason"]))
	var n: int = (plan["new"] as Array).size()
	var k := int(plan["affordable"])
	var gold := int(route_cost((plan["new"] as Array)).get(ResourceManager.Type.GOLD, 0))
	if k < n:
		return Tr.t("LBL_ROAD_LINE_SHORT") % [k, n]
	return Tr.t("LBL_ROAD_LINE_COST") % [n, gold]

## Lo que se dice al soltar: cuantos se pusieron o por que no.
static func road_line_result_text(result: Dictionary) -> String:
	var laid := int(result["laid"])
	var wanted := int(result["wanted"])
	if laid > 0 and laid < wanted:
		return Tr.t("LBL_ROAD_LINE_PARTIAL") % [laid, wanted]
	if laid > 0:
		return Tr.t("LBL_ROAD_LINE_LAID") % laid
	return road_line_reason_text(String(result["reason"]))

static func road_line_reason_text(reason: String) -> String:
	match reason:
		"water":
			return Tr.t("LBL_ON_WATER")
		"occupied":
			return Tr.t("LBL_ROAD_LINE_BLOCKED")
		"road":
			return Tr.t("LBL_NEEDS_ROAD")
		"built":
			return Tr.t("LBL_ROAD_LINE_BUILT")
		"gold":
			return Tr.t("LBL_ROAD_LINE_NO_GOLD")
	return ""

# ── Camino de acceso alrededor de un yacimiento (2026-10-04) ───────────
#
# El primer extractor que se planta junto a un yacimiento tiende gratis un
# anillo de carretera alrededor, para que siempre haya acceso. El anillo va a
# `extractor + 1` casillas del yacimiento (con los extractores de 2x2, a 3):
# asi la franja de 2 casillas pegada al yacimiento queda ENTERA libre para
# extractores —todos lo tocan (alcance 1) y todos tocan el anillo—, y el anillo
# es un lazo seguido en vez de trozos sueltos. Salta lo ocupado (edificios,
# yacimientos) y lo que cae fuera de la rejilla; de lo que queda solo se tiende
# lo que acaba unido a la red del Nucleo (sin Nucleo, todo). No se tiende una
# ruta extra: el extractor ya llego con la suya, que cruza el anillo. La
# Refineria se come su pozo, asi que su pozo no lleva anillo.

## El yacimiento ya tuvo su anillo (meta guardada con el yacimiento).
const ACCESS_RING_META := "access_ring"

## Las casillas del anillo de acceso alrededor de `deposit` para extractores de
## huella `extractor_size`, libres y unidas a la red. Sin tender nada.
static func access_ring_cells(deposit: Node, extractor_size: Vector2i) -> Array:
	if deposit == null or not is_instance_valid(deposit):
		return []
	var origin: Vector2i = deposit.get_meta("cell", Vector2i(-1, -1))
	var size: Vector2i = deposit.get_meta("deposit_size", Vector2i(2, 2))
	var gap := maxi(extractor_size.x, extractor_size.y)
	var outer := Rect2i(origin, size).grow(gap + 1)
	var free := {}
	for y in range(outer.position.y, outer.end.y):
		for x in range(outer.position.x, outer.end.x):
			var on_border := x == outer.position.x or x == outer.end.x - 1 \
				or y == outer.position.y or y == outer.end.y - 1
			var c := Vector2i(x, y)
			if on_border and GridManager.is_valid_cell(c) and GridManager.is_cell_free(c):
				free[c] = true
	if core_cells().is_empty():
		return free.keys()
	# Solo los trozos que tocan la red (o el Nucleo) llegan a ser camino.
	var reach := connected_roads()
	for c in core_cells():
		reach[c] = true
	var kept := {}
	var queue: Array = []
	for c in free:
		if _touches([c], reach):
			kept[c] = true
			queue.append(c)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in NEIGHBORS4:
			var n: Vector2i = cur + d
			if free.has(n) and not kept.has(n):
				kept[n] = true
				queue.append(n)
	return kept.keys()

## Toca anillo al plantar `data` con este veredicto? Solo un extractor con veta
## al lado (no la Refineria), el primero de ese yacimiento: ni el que ya tuvo
## anillo ni uno que ya tenia extractor pegado (partidas de antes del anillo).
## `building` es el recien plantado, que no cuenta como "otro extractor".
static func wants_access_ring(data: BuildingData, verdict: Dictionary, building: Node) -> bool:
	var rule: Dictionary = GameConfig.get_deposit_rule(data.id)
	if rule.is_empty() or bool(rule.get("consumes", false)):
		return false
	# Un banco de peces esta mar adentro (fix/peces-en-el-mar): su anillo caeria
	# casi todo en el agua y lo poco de tierra pavimentaria la costa donde van los
	# otros muelles. El muelle llega con su propia ruta.
	if bool(rule.get("shore", false)):
		return false
	var deposit: Node = verdict.get("deposit", null)
	if deposit == null or not is_instance_valid(deposit) or bool(deposit.get_meta(ACCESS_RING_META, false)):
		return false
	var origin: Vector2i = deposit.get_meta("cell", Vector2i(-1, -1))
	var size: Vector2i = deposit.get_meta("deposit_size", Vector2i(2, 2))
	for info in GridManager.buildings_view():
		var other: BuildingData = info.get("data")
		if info.get("node") == building or other == null:
			continue
		var other_rule: Dictionary = GameConfig.get_deposit_rule(other.id)
		if other_rule.get("deposit", "") != rule["deposit"]:
			continue
		if _deposit_within_reach(origin, size, info.get("cells", []), int(other_rule["reach"])):
			return false
	return true

## Misma cuenta que MapGenerator.deposit_within_reach (Chebyshev), sin cargar
## el generador.
static func _deposit_within_reach(dep_origin: Vector2i, dep_size: Vector2i, cells: Array, reach: int) -> bool:
	var max_x: int = dep_origin.x + dep_size.x - 1
	var max_y: int = dep_origin.y + dep_size.y - 1
	for c in cells:
		var dx: int = maxi(0, maxi(dep_origin.x - c.x, c.x - max_x))
		var dy: int = maxi(0, maxi(dep_origin.y - c.y, c.y - max_y))
		if maxi(dx, dy) <= reach:
			return true
	return false

## Tiende gratis el anillo de acceso si toca (wants_access_ring) con `placer`
## (3D o 2D) y marca el yacimiento. Llamar con el extractor ya en la rejilla y
## ANTES de emitir su building_placed: esa senal recalcula y guarda una vez para
## todo. Los tramos se registran como los de la acera del Nucleo, sin senal por
## tramo. Devuelve cuantos tramos puso.
static func pave_access_ring(placer: Node, data: BuildingData, verdict: Dictionary, building: Node) -> int:
	if not wants_access_ring(data, verdict, building):
		return 0
	var deposit: Node = verdict["deposit"]
	deposit.set_meta(ACCESS_RING_META, true)
	var road := load_building_data(ROAD_ID)
	if road == null:
		return 0
	var n := 0
	for c in access_ring_cells(deposit, data.grid_size):
		var node: Node = placer.place_building_at(road, c)
		if node != null:
			ProductionManager.register_building(node, road, 0.0)
			n += 1
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

## Subir de nivel `data` cambia algo? Produce mas, aloja mas, guarda mas, da mas
## moral, o es el Cuartel General (su nivel 3 convoca la Auditoria). El resto
## (Cuartel, Torre, carretera, Nucleo) no ofrece mejora: no daria nada.
static func upgrade_does_something(data: BuildingData) -> bool:
	if data == null or data.is_core or data.id == ROAD_ID:
		return false
	if data.id == "headquarters":
		return true
	return data.is_producer() or data.population_capacity > 0 or data.id == "warehouse" \
		or (data.is_decoration and data.morale_bonus > 0)

## Que da pasar de `level` a `level + 1`, en frases para el jugador (claves Tr
## con los numeros reales). [] si nada.
static func upgrade_effect_lines(data: BuildingData, level: int) -> Array:
	var out: Array = []
	var nxt := level + 1
	if data.is_producer():
		var parts: Array = []
		var now_m := GameConfig.get_production_multiplier(level)
		var next_m := GameConfig.get_production_multiplier(nxt)
		for pair in [["gold", data.produces_gold], ["steel", data.produces_steel], ["oil", data.produces_oil], ["wood", data.produces_wood], ["food", data.produces_food]]:
			if int(pair[1]) > 0:
				parts.append(Tr.t("FMT_UPGRADE_FROM_TO") % [int(int(pair[1]) * now_m), int(int(pair[1]) * next_m), Tr.res_name(String(pair[0]))])
		out.append(Tr.t("LBL_UPGRADE_PRODUCES") % [", ".join(parts), int(GameConfig.get_production_interval(data.production_interval))])
	if data.population_capacity > 0 and not data.is_core:
		out.append(Tr.t("LBL_UPGRADE_CAPACITY") % [
			int(data.population_capacity * GameConfig.level_mult(GameConfig.upgrade_capacity_multiplier, level)),
			int(data.population_capacity * GameConfig.level_mult(GameConfig.upgrade_capacity_multiplier, nxt))])
	if data.id == "warehouse":
		out.append(Tr.t("LBL_UPGRADE_STORAGE") % GameConfig.warehouse_level_bonus)
	if data.is_decoration and data.morale_bonus > 0:
		out.append(Tr.t("LBL_UPGRADE_MORALE") % [
			int(data.morale_bonus * GameConfig.level_mult(GameConfig.upgrade_morale_multiplier, level)),
			int(data.morale_bonus * GameConfig.level_mult(GameConfig.upgrade_morale_multiplier, nxt))])
	if data.id == "headquarters" and nxt == GameConfig.max_building_level:
		out.append(Tr.t("LBL_UPGRADE_HQ_AUDIT"))
	return out

## El almacen extra que dan los almacenes mejorados (suma de sus niveles por
## encima del 1).
static func warehouse_level_storage() -> int:
	var total := 0
	for info in GridManager.buildings_view():
		var data: BuildingData = info.get("data")
		var node: Node = info.get("node")
		if data != null and data.id == "warehouse" and node != null and is_instance_valid(node):
			total += maxi(0, int(node.get_meta("level", 1)) - 1) * GameConfig.warehouse_level_bonus
	return total

## La ruta a pie del Nucleo a `target` por la red: celdas de carretera, de la
## que toca el Nucleo a la que toca el edificio. [] si no hay (sin Nucleo, sin
## red, o el edificio suelto). La usan los trabajadores que se ven andar.
static func walk_route(target: Node) -> Array:
	var info := GridManager.get_building_info(target)
	if info.is_empty():
		return []
	var network := network_view()
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
	if data.id == ROAD_ID:
		var stranded := road_removal_stranded(building)
		if not stranded.is_empty():
			return {"blocked": move_first_message(stranded), "stranded": stranded}
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
