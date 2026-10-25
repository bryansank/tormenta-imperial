extends RefCounted
class_name ThreatBoard
## Las amenazas de costa (feat/amenazas-costa, 1.2, docs/15 §14): que marcas hay
## ahora en la orilla, cuanto les queda, cual esta atacando la columna y que
## pecio estan explorando los trabajadores.
##
## Decision de Bryan (2026-10-18): SOLO BOTIN OPCIONAL. Aparecen cada cierto
## tiempo, duran un rato y SE VAN SOLAS sin hacer ningun dano. Atacarlas (un
## combate de dominio puro: tierra en la orilla, mar si estan en el agua) o
## explorar el pecio da botin.
##
## Puro, como SortieBoard o StormCycle: sin nodos, sin senales y sin azar global.
## El reloj (segundos jugados), la semilla de cada marca nueva y las casillas
## libres de la costa se los da quien llama (ThreatManager). Cada metodo que
## cambia algo devuelve eventos; el servicio los vuelca al EventBus.
##
## Una AMENAZA es un Dictionary:
##   {id, type, cell: Vector2i, water: bool, seed, era, born, ends,
##    state: "idle" | "engaged" | "exploring", explore_ends, seen}
## Su combate y su botin se rehacen con la semilla (ExpeditionGenerator.threat_*):
## el guardado solo lleva esto.
##
## Eventos: {"e": "appeared", "id", "type", "water"}, {"e": "left", "id", "type"},
## {"e": "cleared", "id", "type"}, {"e": "explore_started", "id"},
## {"e": "explored", "id", "type", "offer"}, {"e": "changed"}.

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")

const STATE_IDLE := "idle"
const STATE_ENGAGED := "engaged"
const STATE_EXPLORING := "exploring"

## Las ofertas de amenaza llevan id = OFFER_ID_BASE + id de la amenaza, para no
## chocar con los ids del tablon de salidas en la misma lista de ATAQUES RAPIDOS.
const OFFER_ID_BASE := 1000000

var threats: Array = []
## Segundos jugados a partir de los cuales puede aparecer la siguiente. -1 = aun
## sin armar: se arma en el primer refresh() con las condiciones cumplidas.
var next_spawn_at: float = -1.0
## Cuantas han salido en la partida (para la variedad y las pruebas).
var spawned: int = 0
var _next_id: int = 1

# ── Consultas ────────────────────────────────────────────────────────

func get_threat(threat_id: int) -> Dictionary:
	for threat in threats:
		if int(threat.get("id", 0)) == threat_id:
			return threat
	return {}

func count() -> int:
	return threats.size()

## La que esta atacando la columna ahora mismo (0 = ninguna).
func engaged_id() -> int:
	for threat in threats:
		if String(threat.get("state", "")) == STATE_ENGAGED:
			return int(threat["id"])
	return 0

## Trabajadores ocupados explorando pecios.
func exploring_count() -> int:
	var n := 0
	for threat in threats:
		if String(threat.get("state", "")) == STATE_EXPLORING:
			n += 1
	return n

func has_unseen() -> bool:
	for threat in threats:
		if not bool(threat.get("seen", false)) and String(threat.get("state", "")) == STATE_IDLE:
			return true
	return false

## Segundos que le quedan en la orilla (o al pecio para terminar de explorarse).
func seconds_left(threat_id: int, now: float) -> float:
	var threat: Dictionary = get_threat(threat_id)
	if threat.is_empty():
		return 0.0
	if String(threat.get("state", "")) == STATE_EXPLORING:
		return maxf(0.0, float(threat.get("explore_ends", now)) - now)
	return maxf(0.0, float(threat.get("ends", now)) - now)

## La amenaza que hay en `cell` o a `radius` casillas (Chebyshev), la mas cercana.
## 0 si ninguna. Para tocar la marca en el mapa.
func threat_at(cell: Vector2i, radius: int = 1) -> int:
	var best: int = 0
	var best_d: int = radius + 1
	for threat in threats:
		var c: Vector2i = threat.get("cell", Vector2i(-99, -99))
		var d: int = maxi(absi(c.x - cell.x), absi(c.y - cell.y))
		if d <= radius and d < best_d:
			best_d = d
			best = int(threat["id"])
	return best

## La oferta de combate de una amenaza ({} si no se pelea o no existe). Con ella
## ExpeditionGenerator rehace el mapa y CombatManager lanza la columna.
static func offer_for(threat: Dictionary) -> Dictionary:
	if threat.is_empty():
		return {}
	return {
		"id": OFFER_ID_BASE + int(threat.get("id", 0)),
		"kind": Generator.KIND_THREAT,
		"threat_id": int(threat.get("id", 0)),
		"threat_type": String(threat.get("type", Generator.THREAT_RAIDERS)),
		"seed": int(threat.get("seed", 1)),
		"era": maxi(1, int(threat.get("era", 1))),
		"domain": "sea" if bool(threat.get("water", false)) else "land",
		"blueprint": "",
	}

# ── El reloj ─────────────────────────────────────────────────────────

## ¿Toca sortear una marca nueva? El servicio solo busca casillas libres en la
## costa (lo caro) cuando esto dice que si.
func spawn_due(now: float, ctx: Dictionary) -> bool:
	if not bool(ctx.get("enabled", false)):
		return false
	if next_spawn_at < 0.0:
		return false
	return now >= next_spawn_at and threats.size() < maxi(0, int(ctx.get("max", 2)))

## Avanza el reloj: se van las que caducaron (si nadie las esta atacando), se
## termina de explorar el pecio y, si toca y hay sitio, aparece una nueva.
## `ctx`:
##   enabled (bool), era (int), sea_ok (bool: hay barcos con los que atacar en el
##   agua), max (int), first_delay (s), interval (Vector2, s), lifetimes
##   ({tipo: s}), weights ({tipo: peso}), sea_chance (float), spacing (casillas).
## `spots`: {"land": Array[Vector2i], "sea": Array[Vector2i]} (vacio si no toca).
## `fresh_seed`: la semilla de la marca nueva (si sale una).
func refresh(now: float, ctx: Dictionary, spots: Dictionary, fresh_seed: int) -> Array:
	var events: Array = []
	var enabled: bool = bool(ctx.get("enabled", false))
	# El primer plazo se arma cuando las amenazas se abren (primer Cuartel y
	# primera escaramuza ganada), no en el minuto 0.
	if next_spawn_at < 0.0 and enabled:
		next_spawn_at = now + maxf(0.0, float(ctx.get("first_delay", 60.0)))
	for i in range(threats.size() - 1, -1, -1):
		var threat: Dictionary = threats[i]
		match String(threat.get("state", STATE_IDLE)):
			STATE_EXPLORING:
				if now >= float(threat.get("explore_ends", now)):
					threats.remove_at(i)
					events.append({"e": "explored", "id": int(threat["id"]),
						"type": String(threat["type"]), "offer": offer_for(threat)})
			STATE_IDLE:
				if now >= float(threat.get("ends", now)):
					threats.remove_at(i)
					events.append({"e": "left", "id": int(threat["id"]), "type": String(threat["type"])})
	if enabled and spawn_due(now, ctx):
		var made: Dictionary = _spawn(now, ctx, spots, fresh_seed)
		if not made.is_empty():
			events.append({"e": "appeared", "id": int(made["id"]), "type": String(made["type"]),
				"water": bool(made["water"])})
		# Con o sin hueco, el siguiente intento espera su plazo: sin sitio en la
		# costa no se mira cada pocos segundos.
		next_spawn_at = now + _roll_interval(fresh_seed, ctx.get("interval", Vector2(150.0, 270.0)))
	if not events.is_empty():
		events.append({"e": "changed"})
	return events

func _roll_interval(seed_value: int, interval: Vector2) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 13 + 5
	return rng.randf_range(minf(interval.x, interval.y), maxf(interval.x, interval.y))

## Sortea tipo, sitio y duracion. {} si no cabe ninguna (sin costa libre).
func _spawn(now: float, ctx: Dictionary, spots: Dictionary, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var threat_type: String = _pick_type(rng, ctx.get("weights", {}))
	if threat_type == "":
		return {}
	var land: Array = spots.get("land", [])
	var sea: Array = spots.get("sea", [])
	# En el agua solo los saqueadores (un bote), y solo si hay barcos con que ir.
	var water: bool = threat_type == Generator.THREAT_RAIDERS and bool(ctx.get("sea_ok", false)) \
		and not sea.is_empty() and rng.randf() < float(ctx.get("sea_chance", 0.0))
	var cell: Vector2i = _pick_cell(rng, sea if water else land, int(ctx.get("spacing", 6)))
	if cell == Vector2i(-1, -1) and water:
		# Sin hueco en el agua, a la orilla.
		water = false
		cell = _pick_cell(rng, land, int(ctx.get("spacing", 6)))
	if cell == Vector2i(-1, -1):
		return {}
	var lifetimes: Dictionary = ctx.get("lifetimes", {})
	var threat := {
		"id": _next_id,
		"type": threat_type,
		"cell": cell,
		"water": water,
		"seed": seed_value if seed_value != 0 else 1,
		"era": maxi(1, int(ctx.get("era", 1))),
		"born": now,
		"ends": now + maxf(1.0, float(lifetimes.get(threat_type, 240.0))),
		"state": STATE_IDLE,
		"explore_ends": 0.0,
		"seen": false,
	}
	_next_id += 1
	spawned += 1
	threats.append(threat)
	return threat

func _pick_type(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total: int = 0
	for key in Generator.THREAT_TYPES:
		total += maxi(0, int(weights.get(key, 0)))
	if total <= 0:
		return ""
	var roll: int = rng.randi_range(1, total)
	for key in Generator.THREAT_TYPES:
		roll -= maxi(0, int(weights.get(key, 0)))
		if roll <= 0:
			return String(key)
	return ""

## La primera casilla (barajadas con el azar de la marca) lejos de las demas.
func _pick_cell(rng: RandomNumberGenerator, candidates: Array, spacing: int) -> Vector2i:
	if candidates.is_empty():
		return Vector2i(-1, -1)
	var order: Array = candidates.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	for cand in order:
		var c: Vector2i = cand
		var crowded := false
		for threat in threats:
			var o: Vector2i = threat.get("cell", Vector2i(-99, -99))
			if maxi(absi(o.x - c.x), absi(o.y - c.y)) < spacing:
				crowded = true
				break
		if not crowded:
			return c
	return Vector2i(-1, -1)

# ── Ordenes ──────────────────────────────────────────────────────────

## La columna sale contra esta amenaza: queda "atacada" y no se va mientras
## dure el combate. Devuelve su oferta ({} si no se puede: no existe, no se
## pelea o ya esta ocupada).
func engage(threat_id: int) -> Dictionary:
	var threat: Dictionary = get_threat(threat_id)
	if threat.is_empty() or String(threat.get("state", "")) != STATE_IDLE:
		return {}
	if not Generator.threat_is_fight(String(threat.get("type", ""))):
		return {}
	threat["state"] = STATE_ENGAGED
	threat["seen"] = true
	return offer_for(threat)

## La columna volvio. Ganada: la amenaza se va (botin cobrado por CombatManager).
## Perdida o abandonada: sigue en la orilla lo que le quedaba (o se va si ya se
## le acabo el tiempo mientras peleaban).
func finish_engagement(won: bool, now: float) -> Array:
	var id: int = engaged_id()
	if id == 0:
		return []
	var threat: Dictionary = get_threat(id)
	if won:
		threats.erase(threat)
		return [{"e": "cleared", "id": id, "type": String(threat["type"])}, {"e": "changed"}]
	threat["state"] = STATE_IDLE
	if now >= float(threat.get("ends", now)):
		threats.erase(threat)
		return [{"e": "left", "id": id, "type": String(threat["type"])}, {"e": "changed"}]
	return [{"e": "changed"}]

## Un guardado con la columna fuera contra una amenaza, pero sin la columna (o
## una carga rara): la amenaza vuelve a estar libre.
func release_engaged() -> Array:
	var id: int = engaged_id()
	if id == 0:
		return []
	get_threat(id)["state"] = STATE_IDLE
	return [{"e": "changed"}]

## Los trabajadores salen a explorar el pecio: termina en `duration` segundos y
## mientras tanto el pecio no se va.
func start_explore(threat_id: int, now: float, duration: float) -> Array:
	var threat: Dictionary = get_threat(threat_id)
	if threat.is_empty() or String(threat.get("type", "")) != Generator.THREAT_WRECK:
		return []
	if String(threat.get("state", "")) != STATE_IDLE:
		return []
	threat["state"] = STATE_EXPLORING
	threat["seen"] = true
	threat["explore_ends"] = now + maxf(1.0, duration)
	return [{"e": "explore_started", "id": threat_id}, {"e": "changed"}]

## Se vio la marca (su tarjeta o la lista de ATAQUES RAPIDOS): se apaga la
## sugerencia de "botin facil" de esa.
func mark_seen(threat_id: int) -> Array:
	var threat: Dictionary = get_threat(threat_id)
	if threat.is_empty() or bool(threat.get("seen", false)):
		return []
	threat["seen"] = true
	return [{"e": "changed"}]

func mark_all_seen() -> Array:
	var changed := false
	for threat in threats:
		if not bool(threat.get("seen", false)):
			threat["seen"] = true
			changed = true
	return [{"e": "changed"}] if changed else []

## Quita una amenaza sin botin (su casilla quedo ocupada por un edificio).
func dismiss(threat_id: int) -> Array:
	var threat: Dictionary = get_threat(threat_id)
	if threat.is_empty() or String(threat.get("state", "")) != STATE_IDLE:
		return []
	threats.erase(threat)
	return [{"e": "left", "id": threat_id, "type": String(threat["type"])}, {"e": "changed"}]

# ── Guardado ─────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	var list: Array = []
	for threat in threats:
		var c: Vector2i = threat.get("cell", Vector2i.ZERO)
		list.append({
			"id": int(threat["id"]),
			"type": String(threat["type"]),
			"x": c.x,
			"y": c.y,
			"water": bool(threat.get("water", false)),
			"seed": int(threat.get("seed", 1)),
			"era": int(threat.get("era", 1)),
			"born": float(threat.get("born", 0.0)),
			"ends": float(threat.get("ends", 0.0)),
			"state": String(threat.get("state", STATE_IDLE)),
			"explore_ends": float(threat.get("explore_ends", 0.0)),
			"seen": bool(threat.get("seen", false)),
		})
	return {
		"threats": list,
		"next_spawn_at": next_spawn_at,
		"spawned": spawned,
		"next_id": _next_id,
	}

## Idempotente: lo cargado sustituye a todo. Sin clave (guardado anterior a las
## amenazas) = orilla vacia y el primer plazo sin armar. Un tipo desconocido se
## ignora.
static func from_dict(data: Dictionary) -> ThreatBoard:
	var board := ThreatBoard.new()
	if data.is_empty():
		return board
	for raw in data.get("threats", []):
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var threat_type: String = String(entry.get("type", ""))
		if not threat_type in Generator.THREAT_TYPES:
			continue
		var state: String = String(entry.get("state", STATE_IDLE))
		if not state in [STATE_IDLE, STATE_ENGAGED, STATE_EXPLORING]:
			state = STATE_IDLE
		board.threats.append({
			"id": int(entry.get("id", 0)),
			"type": threat_type,
			"cell": Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))),
			"water": bool(entry.get("water", false)),
			"seed": int(entry.get("seed", 1)),
			"era": maxi(1, int(entry.get("era", 1))),
			"born": float(entry.get("born", 0.0)),
			"ends": float(entry.get("ends", 0.0)),
			"state": state,
			"explore_ends": float(entry.get("explore_ends", 0.0)),
			"seen": bool(entry.get("seen", false)),
		})
	board.next_spawn_at = float(data.get("next_spawn_at", -1.0))
	board.spawned = maxi(0, int(data.get("spawned", 0)))
	var highest: int = 0
	for threat in board.threats:
		highest = maxi(highest, int(threat["id"]))
	board._next_id = maxi(int(data.get("next_id", 1)), highest + 1)
	return board
