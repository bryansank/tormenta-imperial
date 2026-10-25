extends RefCounted
## El barco del contrabandista (doc 14 §P4, doc 21 §6.3 n.º 13): modelo puro.
##
## Cada 6-10 minutos de juego, si hay un Puerto comercial en marcha y no cae
## Ceniza, atraca 90 s con tres ofertas que no estan en el Mercado. Si no se
## aprovechan, se va con ellas. Este modelo solo lleva el reloj, sortea las
## ofertas y dice que se vendio; NO toca la bolsa ni emite senales: devuelve
## eventos (diccionarios) y EconomyManager los publica, como ContractBoard.
##
## Sin nodos, sin temporizadores, sin randf() global: un RandomNumberGenerator
## propio cuyo estado viaja en el guardado (prueba sin cabeza, mismo barco al
## cargar).
##
## Una OFERTA es un diccionario:
##   {"kind": "parts" | "plan" | "material" | "sell" | "buy",
##    "give": {recurso: n}   lo que da el barco (parts, material, sell),
##    "plan": id             el plano que da (plan),
##    "price": oro           lo que pide por ello (parts, plan, material, sell),
##    "ask": {recurso: n}    lo que quiere (buy),
##    "pay": oro             lo que paga por ello (buy),
##    "sold": bool}
##
## Eventos que devuelve advance()/close():
##   {"e": "ready"}                 toca atracar: quien lo lleva llama dock(ctx)
##   {"e": "docked", "offers": []}  (lo devuelve dock)
##   {"e": "departed", "reason": "time" | "storm" | "no_port"}

const KINDS := ["parts", "plan", "material", "sell", "buy"]

## Segundos hasta el proximo barco (solo corre con Puerto y en calma).
var wait_left := 0.0
## Segundos que le quedan atracado; 0 = no hay barco.
var docked_left := 0.0
## Las ofertas del barco atracado ([] si no hay).
var offers: Array = []
## Barcos que han atracado en la partida (la primera espera es mas corta).
var visits := 0
## El reloj llego a cero y aun no se llamo a dock(); mientras tanto, cada
## advance() en calma repite "ready".
var pending := false
var _rng := RandomNumberGenerator.new()

## Un barco nuevo para una partida nueva. `seed_value` 0 = al azar.
static func create(seed_value: int = 0) -> RefCounted:
	var ship = load("res://scripts/economy/SmugglerShip.gd").new()
	if seed_value != 0:
		ship._rng.seed = seed_value
	else:
		ship._rng.randomize()
	ship.wait_left = -1.0  # sin sortear: la pone la primera vez que hay Puerto
	return ship

func is_docked() -> bool:
	return docked_left > 0.0

## Avanza `dt` segundos de juego. `ctx`: {"port": bool (Puerto en marcha),
## "calm": bool (sin Ceniza ni Tormenta), "first_wait", "interval_min",
## "interval_max" (ya escalados por get_duration)}.
func advance(dt: float, ctx: Dictionary) -> Array:
	var events: Array = []
	var port: bool = bool(ctx.get("port", false))
	var calm: bool = bool(ctx.get("calm", true))
	if is_docked():
		if not port:
			events.append(_leave("no_port"))
			return events
		if not calm:
			events.append(_leave("storm"))
			return events
		docked_left = maxf(0.0, docked_left - dt)
		if docked_left <= 0.0:
			events.append(_leave("time"))
		return events
	if not port:
		pending = false
		return events
	if wait_left < 0.0:
		# El primer Puerto: el primer barco llega pronto.
		wait_left = float(ctx.get("first_wait", 75.0)) if visits == 0 else _roll_wait(ctx)
	wait_left = maxf(0.0, wait_left - dt)
	# Con Ceniza o Tormenta el barco no entra: espera en alta mar.
	if wait_left <= 0.0 and calm:
		pending = true
		events.append({"e": "ready"})
	return events

## Atraca con tres ofertas sorteadas para `ctx` (ver roll_offers).
func dock(ctx: Dictionary) -> Array:
	pending = false
	visits += 1
	offers = roll_offers(ctx)
	docked_left = float(ctx.get("dock_seconds", 90.0))
	wait_left = _roll_wait(ctx)
	return [{"e": "docked", "offers": offers.duplicate(true)}]

## Se va ya (con lo que quede sin vender).
func close(reason: String = "time") -> Array:
	if not is_docked():
		return []
	return [_leave(reason)]

func _leave(reason: String) -> Dictionary:
	docked_left = 0.0
	offers = []
	return {"e": "departed", "reason": reason}

func _roll_wait(ctx: Dictionary) -> float:
	var lo := float(ctx.get("interval_min", 360.0))
	var hi := maxf(lo, float(ctx.get("interval_max", 600.0)))
	return _rng.randf_range(lo, hi)

## La oferta `index` del barco atracado ({} si no hay o ya se vendio).
func offer(index: int) -> Dictionary:
	if not is_docked() or index < 0 or index >= offers.size():
		return {}
	var o: Dictionary = offers[index]
	return {} if bool(o.get("sold", false)) else o

## Marca la oferta como hecha. Quien cobra y paga es EconomyManager.
func mark_sold(index: int) -> bool:
	if offer(index).is_empty():
		return false
	offers[index]["sold"] = true
	return true

# ── Sorteo de ofertas ────────────────────────────────────────────────

## Tres huecos: uno exclusivo (repuestos o un plano menor), un material del
## taller y uno de recursos (te vende barato o te compra caro). `ctx`:
##   "materials": Array de materiales abiertos ("planks"...),
##   "resources": Array de recursos abiertos que no son oro ("wood", "steel"...),
##   "prices": {recurso: {"buy": int, "sell": int}} del Mercado de ahora,
##   "plans": Array de ids de planos que se pueden vender (ya filtrados),
##   "plan_ranks": {id: rango que lo abre},
##   "cfg": los numeros (smuggler_* de GameConfig, ver EconomyManager.ship_config()).
func roll_offers(ctx: Dictionary) -> Array:
	var cfg: Dictionary = ctx.get("cfg", {})
	var out: Array = []
	out.append(_roll_exclusive(ctx, cfg))
	var mat := _roll_material(ctx, cfg)
	if not mat.is_empty():
		out.append(mat)
	var res := _roll_resource(ctx, cfg)
	if not res.is_empty():
		out.append(res)
	# Si falto algun hueco (partida muy temprana), mas recursos.
	var guard := 0
	while out.size() < int(cfg.get("offer_count", 3)) and guard < 4:
		guard += 1
		var extra := _roll_resource(ctx, cfg)
		if extra.is_empty():
			break
		out.append(extra)
	return out

func _roll_exclusive(ctx: Dictionary, cfg: Dictionary) -> Dictionary:
	var plans: Array = ctx.get("plans", [])
	if not plans.is_empty() and _rng.randf() < float(cfg.get("plan_chance", 0.45)):
		var id: String = String(plans[_rng.randi_range(0, plans.size() - 1)])
		var rank: int = int((ctx.get("plan_ranks", {}) as Dictionary).get(id, 1))
		var price: int = maxi(int(cfg.get("plan_price_min", 120)), rank * int(cfg.get("plan_price_per_rank", 40)))
		return {"kind": "plan", "plan": id, "price": price, "sold": false}
	var amount: Array = cfg.get("parts_amount", [2, 4])
	var n: int = _rng.randi_range(int(amount[0]), int(amount[1]))
	return {"kind": "parts", "give": {"parts": n}, "price": n * int(cfg.get("parts_price", 60)), "sold": false}

func _roll_material(ctx: Dictionary, cfg: Dictionary) -> Dictionary:
	var open: Array = ctx.get("materials", [])
	var table: Dictionary = cfg.get("materials", {})
	var pool: Array = []
	for m in open:
		if table.has(String(m)):
			pool.append(String(m))
	if pool.is_empty():
		return {}
	var id: String = pool[_rng.randi_range(0, pool.size() - 1)]
	var row: Dictionary = table[id]
	var amount: Array = row.get("amount", [4, 8])
	var n: int = _rng.randi_range(int(amount[0]), int(amount[1]))
	return {"kind": "material", "give": {id: n}, "price": n * int(row.get("price", 10)), "sold": false}

func _roll_resource(ctx: Dictionary, cfg: Dictionary) -> Dictionary:
	var open: Array = ctx.get("resources", [])
	var prices: Dictionary = ctx.get("prices", {})
	var pool: Array = []
	for r in open:
		if prices.has(String(r)):
			pool.append(String(r))
	if pool.is_empty():
		return {}
	var id: String = pool[_rng.randi_range(0, pool.size() - 1)]
	var amount: Array = cfg.get("resource_amount", [40, 80])
	# Cifras redondas de 10 en 10: se leen de un vistazo.
	var n: int = int(round(float(_rng.randi_range(int(amount[0]), int(amount[1]))) / 10.0)) * 10
	n = maxi(10, n)
	var p: Dictionary = prices[id]
	if _rng.randf() < float(cfg.get("buy_chance", 0.5)):
		var pay: int = maxi(1, int(round(float(p.get("sell", 1)) * float(cfg.get("buy_premium", 1.6)) * n)))
		return {"kind": "buy", "ask": {id: n}, "pay": pay, "sold": false}
	var price: int = maxi(1, int(round(float(p.get("buy", 1)) * float(cfg.get("sell_discount", 0.75)) * n)))
	return {"kind": "sell", "give": {id: n}, "price": price, "sold": false}

# ── Guardado ─────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"wait_left": wait_left,
		"docked_left": docked_left,
		"offers": offers.duplicate(true),
		"visits": visits,
		"pending": pending,
		"rng_seed": _rng.seed,
		"rng_state": _rng.state,
	}

## Idempotente: todo sale de lo guardado. Sin datos = barco nuevo.
static func from_dict(data: Dictionary) -> RefCounted:
	var ship = create()
	if data.is_empty():
		return ship
	ship.wait_left = float(data.get("wait_left", -1.0))
	ship.docked_left = maxf(0.0, float(data.get("docked_left", 0.0)))
	var raw: Variant = data.get("offers", [])
	ship.offers = (raw as Array).duplicate(true) if raw is Array else []
	if ship.offers.is_empty():
		ship.docked_left = 0.0
	ship.visits = int(data.get("visits", 0))
	ship.pending = bool(data.get("pending", false))
	if data.has("rng_seed"):
		ship._rng.seed = int(data["rng_seed"])
	if data.has("rng_state"):
		ship._rng.state = int(data["rng_state"])
	return ship
