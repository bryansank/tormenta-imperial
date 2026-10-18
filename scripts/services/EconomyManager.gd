extends Node
## Los tres edificios de economia de la 1.2 (feat/edificios-economia, doc 21
## §6.3 n.º 13, 14 y 16):
## - Puerto comercial: dueno del barco del contrabandista (modelo puro
##   scripts/economy/SmugglerShip.gd). Lleva su reloj, lo atraca con sus
##   ofertas, cobra y paga los tratos y publica en el EventBus.
## - Central diesel: cada `diesel_plant_interval` segundos de juego cada Central
##   con obreros quema combustible; sin el, se para (meta `diesel_running` en el
##   nodo) y su area deja de dar (UtilityEffects la recalcula SOLO al cambiar).
## - Casa de cambio: el spread lo pone UtilityEffects (GameConfig.market_spread_cut);
##   aqui solo el interes de Gobernador sobre el oro guardado.
##
## Cuales hay en pie y en marcha lo dice UtilityEffects.refresh() (al construir,
## terminar, demoler, arruinar, reparar o cambiar los obreros), que llama a
## register_buildings(): nada se busca por frame. El _process solo resta
## segundos.
##
## Va el ultimo de los autoloads: usa GameManager, ResourceManager,
## MarketManager, StormManager, CombatManager, RankManager y ProgressionManager.
##
## Guardado: clave "economy" (GameManager). load_save_data() lo reemplaza todo
## por lo guardado (idempotente); sin clave, todo nuevo.

const ShipScript := preload("res://scripts/economy/SmugglerShip.gd")
const UtilityEffects := preload("res://scripts/buildings/UtilityEffects.gd")

## Meta en cada Central: si quemo su combustible en el ultimo pago.
const DIESEL_RUNNING_META := "diesel_running"

## Untyped a proposito: el modelo no tiene class_name (se usa con preload).
var _ship
## Planos menores comprados al barco (ids de edificio).
var _plans: Array = []
## Segundos de juego hasta el proximo pago de las Centrales y del interes.
var _diesel_left := -1.0
var _interest_left := -1.0
## Lo que UtilityEffects encontro en pie (runtime, no se guarda).
var _ports: Array = []
var _exchanges: Array = []
var _plants: Array = []
## UtilityEffects ya conto lo que hay en pie (tras una carga o un reset, no).
var _registered := false
## Oro que pago la Casa de cambio en el ultimo interes (para la ficha).
var last_interest := 0

func _ready() -> void:
	_ship = ShipScript.create()
	# Retirar o poner obreros cambia que Central, Puerto o Casa estan en marcha:
	# se recalculan las areas (agrupado y diferido en ProductionManager).
	EventBus.workers_changed.connect(func(_u, _t): _request_areas())

func _request_areas() -> void:
	if ProductionManager.has_method("request_area_refresh"):
		ProductionManager.request_area_refresh()

# ── Lo que hay en pie (lo llama UtilityEffects.refresh) ──────────────

## Los Puertos, Casas de cambio y Centrales en pie (BuildingHealth.is_operational).
## Una Central nueva arranca "en marcha": el primer pago llega con el reloj.
func register_buildings(ports: Array, exchanges: Array, plants: Array) -> void:
	_ports = ports.duplicate()
	_exchanges = exchanges.duplicate()
	_plants = plants.duplicate()
	_registered = true
	for node in _plants:
		if is_instance_valid(node) and not node.has_meta(DIESEL_RUNNING_META):
			node.set_meta(DIESEL_RUNNING_META, true)

## ¿Trabaja este edificio? En pie, con carretera y con sus obreros.
static func is_working(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not BuildingHealth.is_operational(node):
		return false
	if not bool(node.get_meta("connected", true)):
		return false
	return PopulationManager.is_building_staffed(node)

## El Puerto que trabaja ahora (null si ninguno).
func get_port() -> Node:
	for node in _ports:
		if is_working(node):
			return node
	return null

## El Puerto en pie aunque no trabaje (para la ficha y el barco a la vista).
func get_any_port() -> Node:
	for node in _ports:
		if is_instance_valid(node):
			return node
	# Aun sin recuento (justo tras cargar): se busca en la rejilla.
	if not _registered:
		for info in GridManager.buildings_view():
			var data: BuildingData = info.get("data")
			if data != null and data.id == GameConfig.TRADE_PORT_ID:
				return info.get("node")
	return null

func is_exchange_working() -> bool:
	for node in _exchanges:
		if is_working(node):
			return true
	return false

## ¿Da su area esta Central? Trabaja y quemo combustible.
func is_plant_running(node: Node) -> bool:
	return is_working(node) and bool(node.get_meta(DIESEL_RUNNING_META, true))

# ── Reloj ────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not GameManager.is_started():
		return
	# Con un combate abierto el puerto y las calderas esperan.
	if CombatManager.is_board_open():
		return
	var dt := GameConfig.sim_delta(delta)
	_tick_ship(dt)
	if not _plants.is_empty():
		_tick_diesel(dt)
	if not _exchanges.is_empty() and GameMode.is_governor():
		_tick_interest(dt)

func _calm() -> bool:
	return not (StormManager.is_ashfall() or StormManager.is_storming())

func _ship_clock_ctx() -> Dictionary:
	return {
		"port": get_port() != null,
		"calm": _calm(),
		"first_wait": GameConfig.get_duration(GameConfig.smuggler_first_wait),
		"interval_min": GameConfig.get_duration(GameConfig.smuggler_interval_min),
		"interval_max": GameConfig.get_duration(GameConfig.smuggler_interval_max),
		"dock_seconds": GameConfig.get_duration(GameConfig.smuggler_dock_seconds),
	}

func _tick_ship(dt: float) -> void:
	# Hasta el primer recuento tras cargar no se sabe si hay Puerto: un barco
	# atracado en el guardado no puede zarpar por "no hay Puerto" en ese hueco.
	if not _registered:
		return
	# Sin Puerto y sin barco no hay nada que contar (lo normal en la era 1).
	if _ports.is_empty() and not _ship.is_docked():
		return
	var ctx := _ship_clock_ctx()
	var events: Array = _ship.advance(dt, ctx)
	for event in events:
		if String(event.get("e", "")) == "ready":
			var full := offer_context()
			full.merge(ctx)
			_publish(_ship.dock(full))
		else:
			_publish([event])

## Lo que el modelo necesita para sortear ofertas.
func offer_context() -> Dictionary:
	var materials: Array = []
	for m in ["planks", "ingots", "beams", "fuel"]:
		if ResourceManager.is_unlocked_by_name(m):
			materials.append(m)
	var resources: Array = []
	var prices := {}
	for r in ["wood", "food", "steel", "oil"]:
		if ResourceManager.is_unlocked_by_name(r) and GameConfig.market_base_prices.has(r):
			resources.append(r)
			prices[r] = {"buy": MarketManager.get_buy_price(r), "sell": MarketManager.get_sell_price(r)}
	var plans := plan_pool()
	var ranks := {}
	for id in plans:
		ranks[id] = RankManager.building_rank(String(id))
	return {
		"materials": materials,
		"resources": resources,
		"prices": prices,
		"plans": plans,
		"plan_ranks": ranks,
		"cfg": ship_config(),
	}

## Los numeros del barco, de GameConfig.
static func ship_config() -> Dictionary:
	return {
		"offer_count": GameConfig.smuggler_offer_count,
		"parts_amount": GameConfig.smuggler_parts_amount,
		"parts_price": GameConfig.smuggler_parts_price,
		"plan_chance": GameConfig.smuggler_plan_chance,
		"plan_price_per_rank": GameConfig.smuggler_plan_price_per_rank,
		"plan_price_min": GameConfig.smuggler_plan_price_min,
		"materials": GameConfig.smuggler_material_offers,
		"resource_amount": GameConfig.smuggler_resource_amount,
		"sell_discount": GameConfig.smuggler_sell_discount,
		"buy_premium": GameConfig.smuggler_buy_premium,
		"buy_chance": GameConfig.smuggler_buy_chance,
	}

## Planos menores que el barco puede vender: edificios que abre el RANGO por
## encima del de ahora, que aun no se compraron y que existen. Nunca uno de
## los que piden plano de mision (combat_blueprint_buildings).
func plan_pool() -> Array:
	var out: Array = []
	if GameMode.all_unlocked():
		return out
	var rank: int = RankManager.get_rank()
	for r in GameConfig.rank_rewards:
		if int(r) <= rank:
			continue
		for id in GameConfig.rank_rewards[r].get("buildings", []):
			var building_id := String(id)
			if building_id in out or _plans.has(building_id):
				continue
			if building_id in GameConfig.combat_blueprint_buildings:
				continue
			if not ResourceLoader.exists("res://data/buildings/%s.tres" % building_id):
				continue
			out.append(building_id)
	return out

func _tick_diesel(dt: float) -> void:
	if _diesel_left < 0.0:
		_diesel_left = GameConfig.get_duration(GameConfig.diesel_plant_interval)
	_diesel_left -= dt
	if _diesel_left > 0.0:
		return
	_diesel_left = GameConfig.get_duration(GameConfig.diesel_plant_interval)
	burn_fuel()

## Cada Central que trabaja quema su combustible. Publica solo lo que cambia.
## Devuelve cuantas quedaron en marcha (lo usan las pruebas).
func burn_fuel() -> int:
	var changed := false
	var running := 0
	for node in _plants:
		if not is_working(node):
			continue
		var cost := {ResourceManager.Type.FUEL: GameConfig.diesel_plant_fuel_cost}
		var ok := ResourceManager.can_afford(cost)
		if ok:
			ResourceManager.spend_cost(cost)
			running += 1
		var was: bool = bool(node.get_meta(DIESEL_RUNNING_META, true))
		if was != ok:
			node.set_meta(DIESEL_RUNNING_META, ok)
			changed = true
			EventBus.diesel_plant_fuel_changed.emit(node, ok)
			if not ok:
				EventBus.notification_posted.emit(Tr.t("NOTIF_DIESEL_NO_FUEL"), "warning", UITheme.WARNING)
	if changed:
		UtilityEffects.refresh()
		EventBus.economy_changed.emit()
	return running

func _tick_interest(dt: float) -> void:
	if _interest_left < 0.0:
		_interest_left = GameConfig.get_duration(GameConfig.exchange_interest_interval)
	_interest_left -= dt
	if _interest_left > 0.0:
		return
	_interest_left = GameConfig.get_duration(GameConfig.exchange_interest_interval)
	pay_interest()

## Gobernador: interes sobre el oro guardado si una Casa de cambio trabaja.
## Devuelve lo que entro.
func pay_interest() -> int:
	last_interest = 0
	if not GameMode.is_governor() or not is_exchange_working():
		return 0
	var due := interest_due()
	if due <= 0:
		return 0
	last_interest = ResourceManager.add(ResourceManager.Type.GOLD, due)
	if last_interest > 0:
		EventBus.exchange_interest_paid.emit(last_interest)
		EventBus.economy_changed.emit()
	return last_interest

## Lo que pagaria ahora el interes (con el tope).
func interest_due() -> int:
	var gold: int = ResourceManager.get_amount(ResourceManager.Type.GOLD)
	return mini(GameConfig.exchange_interest_cap, int(floor(float(gold) * GameConfig.exchange_interest_rate)))

# ── El barco: consultas ──────────────────────────────────────────────

func is_ship_docked() -> bool:
	return _ship.is_docked()

func ship_seconds_left() -> float:
	return _ship.docked_left

## Segundos hasta el proximo barco (-1 si no hay Puerto que lo llame).
func seconds_until_ship() -> float:
	if get_port() == null:
		return -1.0
	return maxf(0.0, _ship.wait_left)

func get_offers() -> Array:
	return _ship.offers.duplicate(true)

func get_ship():
	return _ship

## Lo que falta para aceptar la oferta `index` ({} = se puede).
func missing_for(index: int) -> Dictionary:
	var o: Dictionary = _ship.offer(index)
	if o.is_empty():
		return {"_": 1}
	var out := {}
	if String(o.get("kind", "")) == "buy":
		for res in o.get("ask", {}):
			var type: int = ResourceManager.name_to_type(String(res))
			var short: int = int(o["ask"][res]) - ResourceManager.get_amount(type)
			if short > 0:
				out[String(res)] = short
	else:
		var short_gold: int = int(o.get("price", 0)) - ResourceManager.get_amount(ResourceManager.Type.GOLD)
		if short_gold > 0:
			out["gold"] = short_gold
	return out

func can_take(index: int) -> bool:
	return not _ship.offer(index).is_empty() and missing_for(index).is_empty()

## Cierra el trato `index`: cobra y paga. false si no se puede (sin tocar nada).
func take_offer(index: int) -> bool:
	if not can_take(index):
		return false
	var o: Dictionary = _ship.offer(index)
	match String(o.get("kind", "")):
		"buy":
			var cost := {}
			for res in o.get("ask", {}):
				cost[ResourceManager.name_to_type(String(res))] = int(o["ask"][res])
			if not ResourceManager.spend_cost(cost):
				return false
			ResourceManager.add(ResourceManager.Type.GOLD, int(o.get("pay", 0)))
		"plan":
			if not ResourceManager.spend(ResourceManager.Type.GOLD, int(o.get("price", 0))):
				return false
			grant_plan(String(o.get("plan", "")))
		_:
			if not ResourceManager.spend(ResourceManager.Type.GOLD, int(o.get("price", 0))):
				return false
			for res in o.get("give", {}):
				var type: int = ResourceManager.name_to_type(String(res))
				if type >= 0:
					# Un material del barco abre su fila del HUD aunque aun no
					# exista su taller (los repuestos, por ejemplo).
					if not ResourceManager.is_unlocked(type) and ResourceManager.is_material(type):
						ResourceManager.unlock(type)
					ResourceManager.add(type, int(o["give"][res]))
	_ship.mark_sold(index)
	EventBus.smuggler_offer_taken.emit(index, o)
	if RankManager.has_method("add_xp"):
		RankManager.add_xp(GameConfig.smuggler_rank_xp)
	EventBus.economy_changed.emit()
	GameManager.request_save()
	return true

# ── Planos menores ───────────────────────────────────────────────────

func has_plan(building_id: String) -> bool:
	return _plans.has(building_id)

func get_plans() -> Array:
	return _plans.duplicate()

## Abre `building_id` aunque el rango aun no llegue (RankManager.is_building_unlocked).
func grant_plan(building_id: String) -> void:
	if building_id == "" or _plans.has(building_id):
		return
	_plans.append(building_id)
	EventBus.building_plan_bought.emit(building_id)

# ── Donde atraca (para las dos vistas y el toque) ────────────────────

## El amarre del barco junto al Puerto `port` (o el que trabaja): {} si no hay.
## "pos": centro del barco en el mundo (y = 0); "out": hacia el mar (unitario,
## XZ); "along": a lo largo de la orilla. El barco se pone a lo largo, a una
## casilla y media del frente del Puerto (el frente es el lado que da al agua:
## el Puerto se orienta solo al colocarlo, PlacementRules.FACES_WATER).
func ship_berth(port: Node = null) -> Dictionary:
	if port == null:
		port = get_any_port()
	if port == null or not is_instance_valid(port):
		return {}
	var info := GridManager.get_building_info(port)
	if info.is_empty():
		return {}
	var origin: Vector2i = info.get("origin_cell", Vector2i.ZERO)
	var data: BuildingData = info.get("data")
	var steps: int = int(port.get_meta("rotation_steps", 0))
	var size := Vector2i(2, 2)
	if data != null:
		size = data.grid_size if steps % 2 == 0 else Vector2i(data.grid_size.y, data.grid_size.x)
	return berth_for(origin, size, steps)

## La cuenta de ship_berth, sin nodos (la usan las pruebas).
static func berth_for(origin: Vector2i, size: Vector2i, rotation_steps: int) -> Dictionary:
	# rotation_steps (convenio 3D) -> lado del mundo al que mira el frente
	# (PlacementRules.steps_to_face al reves): 0 N (-z), 1 E (+x), 2 S (+z), 3 O (-x).
	var side := posmod(2 - rotation_steps, 4)
	var outs := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	var out: Vector3 = outs[side]
	var along := Vector3(-out.z, 0, out.x)
	var center: Vector3 = GridManager.building_center(origin, size)
	var half: float = (float(size.y) if side % 2 == 0 else float(size.x)) * GridManager.cell_size * 0.5
	var pos := center + out * (half + GridManager.cell_size * 1.5)
	return {"pos": pos, "out": out, "along": along, "side": side}

## ¿Cae `world` (punto del suelo, y = 0) sobre el barco atracado?
func ship_hit(world: Vector3) -> bool:
	if not is_ship_docked():
		return false
	var berth := ship_berth()
	if berth.is_empty():
		return false
	var d: Vector3 = world - (berth["pos"] as Vector3)
	d.y = 0.0
	var along: float = absf(d.dot(berth["along"]))
	var across: float = absf(d.dot(berth["out"]))
	return along <= GridManager.cell_size * 1.6 and across <= GridManager.cell_size * 0.9

# ── Publicar ─────────────────────────────────────────────────────────

func _publish(events: Array) -> void:
	if events.is_empty():
		return
	for event in events:
		match String(event.get("e", "")):
			"docked":
				var port := get_port()
				EventBus.smuggler_ship_arrived.emit(event.get("offers", []), port)
				EventBus.notification_posted.emit(Tr.t("NOTIF_SMUGGLER_ARRIVED") % int(round(_ship.docked_left)),
					"notice", UITheme.ACCENT)
				AudioManager.play_sfx("event_positive")
			"departed":
				var reason := String(event.get("reason", "time"))
				EventBus.smuggler_ship_departed.emit(reason)
				if reason == "storm":
					EventBus.notification_posted.emit(Tr.t("NOTIF_SMUGGLER_STORM"), "notice", UITheme.WARNING)
	EventBus.economy_changed.emit()
	GameManager.request_save()

# ── Guardado ─────────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return {
		"ship": _ship.to_dict(),
		"plans": _plans.duplicate(),
		"diesel_left": _diesel_left,
		"interest_left": _interest_left,
	}

## Idempotente: todo sale de lo guardado. Sin clave (partida anterior a la
## economia) = barco nuevo, sin planos, relojes sin empezar.
func load_save_data(data: Dictionary) -> void:
	var ship_data: Variant = data.get("ship", {})
	_ship = ShipScript.from_dict(ship_data if ship_data is Dictionary else {})
	_plans = []
	var raw: Variant = data.get("plans", [])
	if raw is Array:
		for id in raw:
			if not _plans.has(String(id)):
				_plans.append(String(id))
	_diesel_left = float(data.get("diesel_left", -1.0))
	_interest_left = float(data.get("interest_left", -1.0))
	last_interest = 0
	_registered = false
	EventBus.economy_changed.emit()

## Partida nueva: tira el barco, los planos y los relojes. Sin avisos.
func reset() -> void:
	_ship = ShipScript.create()
	_plans = []
	_diesel_left = -1.0
	_interest_left = -1.0
	_ports = []
	_exchanges = []
	_plants = []
	_registered = false
	last_interest = 0
	GameConfig.market_spread_cut = 0.0
	EventBus.economy_changed.emit()
