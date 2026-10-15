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
## - "tavern_houses" (int) en las Tabernas: casas en pie en su barrio.

const MILL_META := "mill_bonus"
const WELL_META := "well_cover"
const TAVERN_META := "tavern_houses"

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
		"lighthouse": lighthouse, "taverns": taverns.size()}

## Partida nueva: nada de lo de arriba sigue en pie.
static func clear() -> void:
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
