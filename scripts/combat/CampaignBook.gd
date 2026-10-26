extends RefCounted
class_name CampaignBook
## Las tres campanas de la partida: Tierra, Mar y Aire (feat/tres-campanas,
## docs/15 §13). Cuantas misiones lleva ganadas cada una, cuando se puede lanzar
## la siguiente y la semilla de la que salen todos sus mapas.
##
## Puro, como SortieBoard: sin nodos, sin senales y sin azar propio. La semilla
## y el reloj (segundos jugados) se los da quien llama (CombatManager). Cada
## metodo que cambia algo devuelve eventos; el servicio los vuelca al EventBus.
##
## Una mision se gana solo si cae su ultimo combate (el jefe de la mision, o el
## jefe de campana en la ultima). Perder o abandonar no avanza nada: la misma
## mision espera, con el mismo mapa (la semilla no cambia: la Regencia sigue en
## su sitio).
##
## Niveles (feat/ritmo-colono): Colono juega menos misiones que Gobernador
## (GameConfig.campaign_mission_list). Las misiones se nombran SIEMPRE por su
## indice en la tabla (campaign_defs): `progress` es el indice de la tabla de la
## siguiente mision por jugar (la tabla entera = campana completa). Asi un
## guardado de antes, que contaba misiones de la tabla, carga tal cual; y lo que
## se ensena ("3 de 4") cuenta solo las misiones del nivel (won / total).
##
## La pieza (una sola llave, feat/ritmo-colono): el jefe de cada campana entrega
## una pieza del Cuartel General nivel 3. Tenerla es haber ganado al jefe, o sea
## la campana completa: has_piece() == is_complete(). Un guardado viejo con el
## jefe ganado ya la tiene; sin el jefe, no.

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")

const DOMAINS := ["land", "sea", "air"]

## Semilla de la partida: cada mision la mezcla con su medio y su numero.
var seed_value: int = 0
## La siguiente mision por jugar de cada campana, como indice de la tabla
## (0 .. campaign_base_count). Igual al total de la tabla = campana completa.
var progress: Dictionary = {"land": 0, "sea": 0, "air": 0}
## Segundos jugados a partir de los cuales se puede lanzar la siguiente mision.
var next_at: Dictionary = {"land": 0.0, "sea": 0.0, "air": 0.0}
## La ultima mision que el jugador ya vio en el panel (para el punto rojo).
## -1 = ninguna.
var seen: Dictionary = {"land": -1, "sea": -1, "air": -1}
## Intentos perdidos o abandonados, por campana (solo para el parte y la sonda).
var setbacks: Dictionary = {"land": 0, "sea": 0, "air": 0}
## Derrotas en la mision que toca ahora (se pone a 0 al ganarla). Cada una
## debilita al enemigo de esa mision (campaign_retry_ease): el combate no tira
## dados y, sin esto, una mision perdida con una columna se perdia siempre.
var fails: Dictionary = {"land": 0, "sea": 0, "air": 0}

# ── Consultas ────────────────────────────────────────────────────────

## Misiones de la campana en este nivel (jefe incluido).
static func total(domain: String) -> int:
	return GameConfig.campaign_mission_count(domain)

## Misiones de la tabla (las de Gobernador).
static func base_total(domain: String) -> int:
	return GameConfig.campaign_base_count(domain)

## El numero que se ensena de una mision de la tabla en este nivel (1..total):
## en Colono la mision 3 de la tabla puede ser la "2 de 4". -1 si este nivel no
## la juega.
static func number_of(domain: String, mission: int) -> int:
	var i: int = GameConfig.campaign_mission_list(domain).find(mission)
	return i + 1 if i >= 0 else -1

## El indice de la tabla de la siguiente mision por jugar.
func base_progress(domain: String) -> int:
	return clampi(int(progress.get(domain, 0)), 0, base_total(domain))

## Misiones de este nivel ya ganadas (lo que se ensena: "2 de 4").
func won(domain: String) -> int:
	if is_complete(domain):
		return total(domain)
	var at: int = base_progress(domain)
	var n := 0
	for m in GameConfig.campaign_mission_list(domain):
		if int(m) < at:
			n += 1
	return mini(n, maxi(0, total(domain) - 1))

func is_complete(domain: String) -> bool:
	return base_total(domain) > 0 and base_progress(domain) >= base_total(domain)

## La pieza del Cuartel General de esta campana: la entrega su jefe.
func has_piece(domain: String) -> bool:
	return is_complete(domain)

## Las campanas cuya pieza falta, en el orden de las pestanas.
func missing_pieces() -> Array:
	var out: Array = []
	for domain in DOMAINS:
		if not has_piece(domain):
			out.append(domain)
	return out

func pieces_count() -> int:
	return DOMAINS.size() - missing_pieces().size()

func all_complete() -> bool:
	for domain in DOMAINS:
		if not is_complete(domain):
			return false
	return true

func completed_count() -> int:
	var n := 0
	for domain in DOMAINS:
		if is_complete(domain):
			n += 1
	return n

## La mision que toca, como indice de la tabla, o -1 si la campana esta
## completa: la primera de este nivel que no se ha jugado.
func next_mission(domain: String) -> int:
	if is_complete(domain):
		return -1
	var at: int = base_progress(domain)
	for m in GameConfig.campaign_mission_list(domain):
		if int(m) >= at:
			return int(m)
	return base_total(domain) - 1

func is_started(domain: String) -> bool:
	return base_progress(domain) > 0

## Segundos que faltan para poder lanzar la siguiente (0 = ya).
func cooldown_left(domain: String, now: float) -> float:
	return maxf(0.0, float(next_at.get(domain, 0.0)) - now)

## La oferta de la mision que toca (vacia si la campana esta completa). `era` es
## la de la colonia: la mision nunca sale por debajo de su era minima.
func offer_for(domain: String, era: int) -> Dictionary:
	var mission: int = next_mission(domain)
	if mission < 0:
		return {}
	var offer: Dictionary = Generator.campaign_offer(domain, mission, seed_value, era)
	offer["retries"] = int(fails.get(domain, 0))
	return offer

## Hay una mision nueva que el jugador aun no ha mirado.
func is_unseen(domain: String) -> bool:
	var mission: int = next_mission(domain)
	return mission >= 0 and int(seen.get(domain, -1)) < mission

# ── Cambios ──────────────────────────────────────────────────────────

## Pone la semilla de la partida si aun no la tiene (partida nueva o guardado
## anterior a las campanas). Nunca la cambia despues: los mapas no se mueven.
func ensure_seed(fresh_seed: int) -> void:
	if seed_value == 0:
		seed_value = fresh_seed if fresh_seed != 0 else 1

## La columna de la mision `mission` de `domain` ha vuelto. Solo una mision
## ganada (su ultimo combate) avanza la campana, y solo si es la que tocaba (una
## partida cargada a medias no puede saltarse ninguna).
func finish(domain: String, mission: int, won_it: bool, now: float, cooldown: float) -> Array:
	if not DOMAINS.has(domain):
		return []
	if not won_it:
		setbacks[domain] = int(setbacks.get(domain, 0)) + 1
		if mission == next_mission(domain):
			fails[domain] = int(fails.get(domain, 0)) + 1
		return [{"e": "campaign_changed"}]
	if mission != next_mission(domain):
		return [{"e": "campaign_changed"}]
	progress[domain] = mission + 1
	fails[domain] = 0
	next_at[domain] = now + maxf(0.0, cooldown)
	var boss: bool = Generator.campaign_is_boss_mission(domain, mission)
	var events: Array = [{"e": "campaign_mission_won", "domain": domain, "mission": mission, "boss": boss}]
	if is_complete(domain):
		events.append({"e": "campaign_completed", "domain": domain})
		events.append({"e": "campaign_piece_won", "domain": domain})
		if all_complete():
			events.append({"e": "campaigns_all_completed"})
	events.append({"e": "campaign_changed"})
	return events

## El jugador ha mirado el panel: las misiones a la vista dejan de ser nuevas.
func mark_all_seen() -> Array:
	var changed := false
	for domain in DOMAINS:
		var mission: int = next_mission(domain)
		if mission >= 0 and int(seen.get(domain, -1)) < mission:
			seen[domain] = mission
			changed = true
	return [{"e": "campaign_changed"}] if changed else []

# ── Guardado ─────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"seed": seed_value,
		"progress": progress.duplicate(),
		"next_at": next_at.duplicate(),
		"seen": seen.duplicate(),
		"setbacks": setbacks.duplicate(),
		"fails": fails.duplicate(),
	}

## Idempotente: lo cargado sustituye a todo, nunca se suma. Sin datos (guardado
## anterior a las campanas) = ninguna empezada. Un numero fuera de rango se
## recorta al total de la tabla. `progress` siempre fue (y sigue siendo) un indice
## de la tabla: un guardado de antes de los niveles carga igual, y su pieza sale
## de si gano al jefe.
static func from_dict(data: Dictionary) -> CampaignBook:
	var book := CampaignBook.new()
	if data.is_empty():
		return book
	book.seed_value = int(data.get("seed", 0))
	for domain in DOMAINS:
		var p: Dictionary = data.get("progress", {}) if data.get("progress", {}) is Dictionary else {}
		var n: Dictionary = data.get("next_at", {}) if data.get("next_at", {}) is Dictionary else {}
		var s: Dictionary = data.get("seen", {}) if data.get("seen", {}) is Dictionary else {}
		var b: Dictionary = data.get("setbacks", {}) if data.get("setbacks", {}) is Dictionary else {}
		book.progress[domain] = clampi(int(p.get(domain, 0)), 0, base_total(domain))
		book.next_at[domain] = maxf(0.0, float(n.get(domain, 0.0)))
		book.seen[domain] = int(s.get(domain, -1))
		book.setbacks[domain] = maxi(0, int(b.get(domain, 0)))
		var f: Dictionary = data.get("fails", {}) if data.get("fails", {}) is Dictionary else {}
		book.fails[domain] = maxi(0, int(f.get(domain, 0)))
	return book
