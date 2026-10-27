extends RefCounted
## Las areas de efecto de los edificios utiles de la 1.1 (doc 21 §6.3):
## Molino (+produccion de las Granjas cercanas), Silo y Deposito de combustible
## (bolsa aparte para comida y petroleo), Taberna (barrio con casas), Pozo
## (menos dano de la Tormenta alrededor) y Faro (Aviso mas largo).
##
## Regla pura sobre GridManager: `refresh()` recorre los edificios UNA vez y
## deja el resultado en metas de los nodos y en tres valores de runtime; los
## servicios solo leen. La llama ProductionManager, agrupada y diferida, al
## colocar, terminar, demoler, arruinar o reparar un edificio y al cargar
## (doc 21 §6.6: al construir o derribar, nunca por frame).
##
## Metas que escribe (y borra cuando ya no tocan):
## - "mill_bonus" (float) en las Granjas con un Molino en pie cerca;
## - "well_cover" (float) en los edificios con un Pozo en pie cerca;
## - "tavern_houses" (int) en las Tabernas: casas en pie en su barrio;
## - "diesel_bonus" (float) en los industriales con una Central diesel en
##   marcha cerca (feat/edificios-economia).
##
## Economia (feat/edificios-economia): tambien entrega a EconomyManager los
## Puertos, Casas de cambio y Centrales en pie, y pone el recorte del spread
## del Mercado (GameConfig.market_spread_cut) si una Casa de cambio trabaja.

const MILL_META := "mill_bonus"
const WELL_META := "well_cover"
const TAVERN_META := "tavern_houses"
const DIESEL_META := "diesel_bonus"

## Recalcula todo. Devuelve un resumen (lo usan las pruebas).
static func refresh() -> Dictionary:
	var views: Array = GridManager.buildings_view()
	var mills: Array = []
	var wells: Array = []
	var houses: Array = []
	var taverns: Array = []
	var farms: Array = []
	var silos := 0
	var depots := 0
	var lighthouse := false
	var ports: Array = []
	var exchanges: Array = []
	var plants: Array = []
	var industrials: Array = []
	for info in views:
		var data: BuildingData = info.get("data")
		var node: Node = info.get("node")
		if data == null or node == null or not is_instance_valid(node):
			continue
		var up := _standing(node)
		match data.id:
			"windmill":
				if up: mills.append(info)
			"well":
				if up: wells.append(info)
			"house":
				if up: houses.append(info)
			"tavern":
				taverns.append(info)
			"farm":
				farms.append(info)
			"silo":
				if up: silos += 1
			"fuel_depot":
				if up: depots += 1
			"lighthouse":
				if up: lighthouse = true
			"trade_port":
				if up: ports.append(node)
			"exchange":
				if up: exchanges.append(node)
			"diesel_plant":
				if up: plants.append(node)
		if data.id in GameConfig.diesel_plant_targets:
			industrials.append(info)
	# Economia: lo que hay en pie, para el barco, el combustible y el interes.
	var economy: Node = _economy()
	if economy != null:
		economy.register_buildings(ports, exchanges, plants)
	# Casa de cambio -> spread del Mercado (solo si trabaja: carretera y obreros)
	var exchange_on := false
	for node in exchanges:
		if economy != null and economy.is_working(node):
			exchange_on = true
	GameConfig.market_spread_cut = GameConfig.exchange_spread_cut if exchange_on else 0.0
	# Central diesel -> industriales cercanos (solo las que queman combustible)
	var running: Array = []
	for view in views:
		if view.get("node") in plants and economy != null and economy.is_plant_running(view.get("node")):
			running.append(view)
	for info in industrials:
		var near := not running.is_empty() and _any_within(info, running, GameConfig.diesel_plant_radius)
		_set_meta(info["node"], DIESEL_META, GameConfig.diesel_plant_bonus if near else 0.0)
	# Molino -> Granjas
	for f in farms:
		var near := _any_within(f, mills, GameConfig.windmill_radius)
		_set_meta(f["node"], MILL_META, GameConfig.windmill_farm_bonus if near else 0.0)
	# Pozo -> todo lo demas (inmunes incluidos no importa: no reciben dano)
	for info in views:
		var node: Node = info.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var covered := not wells.is_empty() and _any_within(info, wells, GameConfig.well_radius)
		_set_meta(node, WELL_META, GameConfig.well_storm_reduction if covered else 0.0)
	# Taberna -> casas del barrio
	for t in taverns:
		var n := 0
		for h in houses:
			if _gap(t, h) <= GameConfig.tavern_radius:
				n += 1
		_set_meta(t["node"], TAVERN_META, n)
	# Bolsas aparte y Faro
	ResourceManager.set_side_storage({
		ResourceManager.Type.FOOD: silos * GameConfig.silo_food_storage,
		ResourceManager.Type.OIL: depots * GameConfig.fuel_depot_oil_storage,
	})
	GameConfig.storm_warning_bonus = GameConfig.lighthouse_warning_bonus if lighthouse else 0.0
	GameConfig.food_spoil_delay_mult = GameConfig.silo_spoil_delay_mult if silos > 0 else 1.0
	return {"mills": mills.size(), "wells": wells.size(), "silos": silos, "depots": depots,
		"lighthouse": lighthouse, "taverns": taverns.size(), "ports": ports.size(),
		"exchange": exchange_on, "plants": plants.size(), "plants_running": running.size()}

## EconomyManager (autoload) o null si no esta (escenas de prueba sin el arbol).
static func _economy() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("EconomyManager")

## Los industriales a los que llega una Central diesel en marcha (para la ficha).
static func diesel_targets_of(plant: Node) -> int:
	if plant == null or not is_instance_valid(plant):
		return 0
	var plant_info := GridManager.get_building_info(plant)
	if plant_info.is_empty():
		return 0
	var n := 0
	for info in GridManager.buildings_view():
		var data: BuildingData = info.get("data")
		if data == null or not (data.id in GameConfig.diesel_plant_targets):
			continue
		if _gap(info, plant_info) <= GameConfig.diesel_plant_radius:
			n += 1
	return n

## Partida nueva: nada de lo de arriba sigue en pie.
static func clear() -> void:
	GameConfig.market_spread_cut = 0.0
	GameConfig.storm_warning_bonus = 0.0
	GameConfig.food_spoil_delay_mult = 1.0
	ResourceManager.set_side_storage({})

## En pie y terminado (BuildingHealth.is_operational).
static func _standing(node: Node) -> bool:
	return BuildingHealth.is_operational(node)

static func _set_meta(node: Node, key: String, value) -> void:
	if node == null or not is_instance_valid(node):
		return
	var empty: bool = (value is float and is_zero_approx(value)) or (value is int and value == 0)
	if empty:
		if node.has_meta(key):
			node.remove_meta(key)
	else:
		node.set_meta(key, value)

static func _any_within(info: Dictionary, sources: Array, radius: int) -> bool:
	for s in sources:
		if s.get("node") == info.get("node"):
			continue
		if _gap(info, s) <= radius:
			return true
	return false

## Casillas libres entre dos huellas (0 si se tocan), en Chebyshev.
static func _gap(a: Dictionary, b: Dictionary) -> int:
	return footprint_gap(a.get("cells", []), b.get("cells", []))

static func footprint_gap(ca: Array, cb: Array) -> int:
	if ca.is_empty() or cb.is_empty():
		return 1 << 20
	var ra := _bounds(ca)
	var rb := _bounds(cb)
	var dx := maxi(0, maxi(rb.position.x - ra.end.x, ra.position.x - rb.end.x))
	var dy := maxi(0, maxi(rb.position.y - ra.end.y, ra.position.y - rb.end.y))
	return maxi(dx, dy)

## Rectangulo de celdas, con `end` = la ultima celda + 1.
static func _bounds(cells: Array) -> Rect2i:
	var lo: Vector2i = cells[0]
	var hi: Vector2i = cells[0]
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)
