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

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")

const DOMAINS := ["land", "sea", "air"]

## Semilla de la partida: cada mision la mezcla con su medio y su numero.
var seed_value: int = 0
## Misiones ganadas por campana (0 .. total). Igual al total = campana completa.
var progress: Dictionary = {"land": 0, "sea": 0, "air": 0}
## Segundos jugados a partir de los cuales se puede lanzar la siguiente mision.
var next_at: Dictionary = {"land": 0.0, "sea": 0.0, "air": 0.0}
## La ultima mision que el jugador ya vio en el panel (para el punto rojo).
## -1 = ninguna.
var seen: Dictionary = {"land": -1, "sea": -1, "air": -1}
## Intentos perdidos o abandonados, por campana (solo para el parte y la sonda).
var setbacks: Dictionary = {"land": 0, "sea": 0, "air": 0}

# ── Consultas ────────────────────────────────────────────────────────

static func total(domain: String) -> int:
	return GameConfig.campaign_mission_count(domain)

func won(domain: String) -> int:
	return clampi(int(progress.get(domain, 0)), 0, total(domain))

func is_complete(domain: String) -> bool:
	return total(domain) > 0 and won(domain) >= total(domain)

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

## La mision que toca (indice desde 0), o -1 si la campana esta completa.
func next_mission(domain: String) -> int:
	return -1 if is_complete(domain) else won(domain)

func is_started(domain: String) -> bool:
	return won(domain) > 0

## Segundos que faltan para poder lanzar la siguiente (0 = ya).
func cooldown_left(domain: String, now: float) -> float:
	return maxf(0.0, float(next_at.get(domain, 0.0)) - now)

## La oferta de la mision que toca (vacia si la campana esta completa). `era` es
## la de la colonia: la mision nunca sale por debajo de su era minima.
func offer_for(domain: String, era: int) -> Dictionary:
	var mission: int = next_mission(domain)
	if mission < 0:
		return {}
	return Generator.campaign_offer(domain, mission, seed_value, era)

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
		return [{"e": "campaign_changed"}]
	if mission != next_mission(domain):
		return [{"e": "campaign_changed"}]
	progress[domain] = won(domain) + 1
	next_at[domain] = now + maxf(0.0, cooldown)
	var boss: bool = Generator.campaign_is_boss_mission(domain, mission)
	var events: Array = [{"e": "campaign_mission_won", "domain": domain, "mission": mission, "boss": boss}]
	if is_complete(domain):
		events.append({"e": "campaign_completed", "domain": domain})
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
	}

## Idempotente: lo cargado sustituye a todo, nunca se suma. Sin datos (guardado
## anterior a las campanas) = ninguna empezada. Un numero fuera de rango se
## recorta al total de su campana.
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
		book.progress[domain] = clampi(int(p.get(domain, 0)), 0, total(domain))
		book.next_at[domain] = maxf(0.0, float(n.get(domain, 0.0)))
		book.seen[domain] = int(s.get(domain, -1))
		book.setbacks[domain] = maxi(0, int(b.get(domain, 0)))
	return book
