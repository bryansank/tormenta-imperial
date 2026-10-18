extends RefCounted
class_name Archipelago
## Volverse el Imperio (feat/volverse-imperio, docs/06 §Volverse el Imperio): el
## archipielago que rodea tu isla despues de ganar el Ataque Final. Que islas
## llevas conquistadas, cuantas misiones de cada una, cuando se puede lanzar la
## siguiente y cuando toca cobrar el tributo.
##
## Puro, como CampaignBook: sin nodos, sin senales y sin azar propio. La semilla
## y el reloj (segundos jugados) se los da quien llama (EmpireManager). Cada
## metodo que cambia algo devuelve eventos; el servicio los vuelca al EventBus.
##
## Las islas salen de GameConfig.empire_islands (id, nivel, cuantas hacen falta
## antes, escudo, cadena de misiones, tributo y recompensa). Una isla se
## conquista al ganar su ultima mision; perder o abandonar no avanza nada y la
## misma mision espera con el mismo mapa.

## Semilla de la partida: cada mision la mezcla con su isla y su numero.
var seed_value: int = 0
## La fase ha empezado (se gano el Ataque Final y el reloj del tributo corre).
var started: bool = false
## Misiones ganadas por isla (0 .. total). Igual al total = conquistada.
var progress: Dictionary = {}
## Segundos jugados a partir de los cuales se puede lanzar la siguiente mision.
var next_at: Dictionary = {}
## Segundos jugados en que se conquisto cada isla (orden de conquista).
var conquered_at: Dictionary = {}
## Intentos perdidos o abandonados, por isla (para el parte y la sonda).
var setbacks: Dictionary = {}
## Segundos jugados del proximo cobro.
var tribute_next_at: float = 0.0
## Cobros hechos y lo cobrado en total (recurso -> cantidad), para el panel.
var tributes_paid: int = 0
var tribute_total: Dictionary = {}
## El instructor ya conto de que va la fase (la primera vez que se abre el mapa).
var intro_seen: bool = false

# ── Las islas (de GameConfig) ────────────────────────────────────────

static func island_ids() -> Array:
	return GameConfig.empire_island_ids()

static func island_def(island_id: String) -> Dictionary:
	return GameConfig.empire_island(island_id)

static func has_island(island_id: String) -> bool:
	return not island_def(island_id).is_empty()

static func missions_of(island_id: String) -> Array:
	return island_def(island_id).get("missions", [])

static func total(island_id: String) -> int:
	return missions_of(island_id).size()

static func mission_def(island_id: String, mission: int) -> Dictionary:
	var list: Array = missions_of(island_id)
	if mission < 0 or mission >= list.size():
		return {}
	return list[mission]

static func mission_domain(island_id: String, mission: int) -> String:
	return String(mission_def(island_id, mission).get("domain", "land"))

## La ultima mision de la isla: la que la conquista.
static func is_final_mission(island_id: String, mission: int) -> bool:
	return mission == total(island_id) - 1

static func tier(island_id: String) -> int:
	return clampi(int(island_def(island_id).get("tier", 1)), 1, 3)

static func needs(island_id: String) -> int:
	return maxi(0, int(island_def(island_id).get("needs", 0)))

static func tribute_of(island_id: String) -> Dictionary:
	return island_def(island_id).get("tribute", {})

static func reward_of(island_id: String) -> Dictionary:
	return island_def(island_id).get("reward", {})

# ── Consultas ────────────────────────────────────────────────────────

func won(island_id: String) -> int:
	return clampi(int(progress.get(island_id, 0)), 0, total(island_id))

func is_conquered(island_id: String) -> bool:
	return total(island_id) > 0 and won(island_id) >= total(island_id)

func conquered_ids() -> Array:
	var out: Array = []
	for island_id in island_ids():
		if is_conquered(String(island_id)):
			out.append(String(island_id))
	return out

func conquered_count() -> int:
	return conquered_ids().size()

func all_conquered() -> bool:
	return conquered_count() >= island_ids().size() and not island_ids().is_empty()

## La mision que toca (indice desde 0), o -1 si la isla ya es tuya.
func next_mission(island_id: String) -> int:
	return -1 if is_conquered(island_id) else won(island_id)

## Hay bastantes islas conquistadas para atacar esta.
func needs_met(island_id: String) -> bool:
	return conquered_count() >= needs(island_id)

func cooldown_left(island_id: String, now: float) -> float:
	return maxf(0.0, float(next_at.get(island_id, 0.0)) - now)

## La isla que ¿QUE HACER? propone: la primera sin conquistar que ya se pueda
## atacar (en el orden del mapa), con preferencia por una a medias. "" si todas
## son tuyas.
func next_target() -> String:
	var first_open: String = ""
	for island_id in island_ids():
		var id: String = String(island_id)
		if is_conquered(id) or not needs_met(id):
			continue
		if won(id) > 0:
			return id
		if first_open == "":
			first_open = id
	return first_open

## Lo que pagan juntas todas las islas conquistadas en cada cobro.
func tribute_per_cycle() -> Dictionary:
	var out: Dictionary = {}
	for island_id in conquered_ids():
		var t: Dictionary = tribute_of(String(island_id))
		for res in t:
			out[String(res)] = int(out.get(String(res), 0)) + int(t[res])
	return out

## Segundos hasta el proximo cobro (0 si no hay nada que cobrar).
func tribute_left(now: float) -> float:
	if not started or conquered_count() == 0:
		return 0.0
	return maxf(0.0, tribute_next_at - now)

## El titulo mas alto por islas conquistadas ("" si ninguna).
func title_key() -> String:
	var count: int = conquered_count()
	var best: String = ""
	for entry in GameConfig.empire_titles:
		if count >= int(entry.get("count", 99)):
			best = String(entry.get("key", ""))
	return best

## ¿Abre alguna isla conquistada esta pieza? `kind`: "buildings", "patterns",
## "emblems" o "colors" (las claves de reward).
func unlocks(kind: String, id: String) -> bool:
	for island_id in conquered_ids():
		if id in (reward_of(String(island_id)).get(kind, []) as Array):
			return true
	return false

## La oferta de la mision que toca en `island_id` ({} si ya es tuya).
func offer_for(island_id: String, era: int) -> Dictionary:
	var mission: int = next_mission(island_id)
	if mission < 0 or not has_island(island_id):
		return {}
	return ConquestGenerator.offer(island_id, mission, seed_value, era)

# ── Cambios ──────────────────────────────────────────────────────────

## Pone la semilla si aun no la tiene. Nunca la cambia despues.
func ensure_seed(fresh_seed: int) -> void:
	if seed_value == 0:
		seed_value = fresh_seed if fresh_seed != 0 else 1

## Empieza la fase (una vez): el reloj del tributo se pone en marcha.
func start(now: float, interval: float) -> Array:
	if started:
		return []
	started = true
	tribute_next_at = now + maxf(1.0, interval)
	return [{"e": "empire_phase_started"}, {"e": "empire_changed"}]

## La columna de la mision `mission` de `island_id` ha vuelto. Solo una mision
## ganada, y la que tocaba, avanza la isla. Al ganar la ultima, la isla es tuya.
func finish(island_id: String, mission: int, won_it: bool, now: float, cooldown: float, interval: float) -> Array:
	if not has_island(island_id):
		return []
	if not won_it:
		setbacks[island_id] = int(setbacks.get(island_id, 0)) + 1
		return [{"e": "empire_changed"}]
	if mission != next_mission(island_id):
		return [{"e": "empire_changed"}]
	var had_any: bool = conquered_count() > 0
	progress[island_id] = won(island_id) + 1
	next_at[island_id] = now + maxf(0.0, cooldown)
	var conquered: bool = is_conquered(island_id)
	var events: Array = [{"e": "conquest_mission_won", "island": island_id, "mission": mission, "conquered": conquered}]
	if conquered:
		conquered_at[island_id] = now
		# La primera isla abre el cobro: el primero llega un intervalo despues.
		if not had_any:
			tribute_next_at = now + maxf(1.0, interval)
		events.append({"e": "island_conquered", "island": island_id})
		if all_conquered():
			events.append({"e": "archipelago_conquered"})
	events.append({"e": "empire_changed"})
	return events

## El reloj: si toca, cobra el tributo de todas las islas conquistadas. Un cobro
## por llamada como mucho (una pausa larga no amontona cobros).
func tick(now: float, interval: float) -> Array:
	if not started or conquered_count() == 0:
		return []
	if now < tribute_next_at:
		return []
	var amounts: Dictionary = tribute_per_cycle()
	tribute_next_at = now + maxf(1.0, interval)
	if amounts.is_empty():
		return []
	tributes_paid += 1
	for res in amounts:
		tribute_total[res] = int(tribute_total.get(res, 0)) + int(amounts[res])
	return [{"e": "tribute", "amounts": amounts.duplicate()}, {"e": "empire_changed"}]

func mark_intro_seen() -> void:
	intro_seen = true

# ── Guardado ─────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"seed": seed_value,
		"started": started,
		"progress": progress.duplicate(),
		"next_at": next_at.duplicate(),
		"conquered_at": conquered_at.duplicate(),
		"setbacks": setbacks.duplicate(),
		"tribute_next_at": tribute_next_at,
		"tributes_paid": tributes_paid,
		"tribute_total": tribute_total.duplicate(),
		"intro_seen": intro_seen,
	}

## Idempotente: lo cargado sustituye a todo, nunca se suma. Sin datos (guardado
## anterior a esta fase) = nada empezado. Una isla que ya no existe se ignora; un
## numero fuera de rango se recorta.
static func from_dict(data: Dictionary) -> Archipelago:
	var book := Archipelago.new()
	if data.is_empty():
		return book
	book.seed_value = int(data.get("seed", 0))
	book.started = bool(data.get("started", false))
	var p: Dictionary = data.get("progress", {}) if data.get("progress", {}) is Dictionary else {}
	var n: Dictionary = data.get("next_at", {}) if data.get("next_at", {}) is Dictionary else {}
	var c: Dictionary = data.get("conquered_at", {}) if data.get("conquered_at", {}) is Dictionary else {}
	var s: Dictionary = data.get("setbacks", {}) if data.get("setbacks", {}) is Dictionary else {}
	for island_id in island_ids():
		var id: String = String(island_id)
		if p.has(id):
			book.progress[id] = clampi(int(p[id]), 0, total(id))
		if n.has(id):
			book.next_at[id] = maxf(0.0, float(n[id]))
		if c.has(id) and book.is_conquered(id):
			book.conquered_at[id] = maxf(0.0, float(c[id]))
		if s.has(id):
			book.setbacks[id] = maxi(0, int(s[id]))
	book.tribute_next_at = maxf(0.0, float(data.get("tribute_next_at", 0.0)))
	book.tributes_paid = maxi(0, int(data.get("tributes_paid", 0)))
	var t: Dictionary = data.get("tribute_total", {}) if data.get("tribute_total", {}) is Dictionary else {}
	for res in t:
		book.tribute_total[String(res)] = maxi(0, int(t[res]))
	book.intro_seen = bool(data.get("intro_seen", false))
	return book
