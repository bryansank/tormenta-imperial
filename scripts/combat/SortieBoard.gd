extends RefCounted
class_name SortieBoard
## El tablon de salidas (doc 21 §3, 2026-10-14): que incursion y que expedicion
## hay a la vista ahora mismo, cuando aparece la siguiente, y lo que la colonia
## ya se trajo de fuera y aun no ha gastado (planos y la rebaja del Diezmo).
##
## Puro, como Expedition o StormCycle: sin nodos, sin senales y sin azar propio.
## Las semillas se las da quien llama (CombatManager) y el reloj tambien (los
## segundos jugados de ProgressionManager). Cada metodo que cambia algo devuelve
## eventos; el servicio los vuelca al EventBus.
##
## Una OFERTA es {id, kind, flavor, seed, era, blueprint, seen}. Con la oferta
## se rehace el mapa entero (ExpeditionGenerator.sortie_map), asi que el jugador
## ve los enemigos y el botin antes de salir, y el guardado solo lleva esto.

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")

var offers: Array = []
## Segundos jugados a partir de los cuales puede aparecer la siguiente de cada
## tipo. Empiezan en 0: la primera aparece en cuanto se cumplen las condiciones.
var next_raid_at: float = 0.0
var next_expedition_at: float = 0.0
## Planos conseguidos (ids de edificio). Abren edificios (CombatManager.blueprint_locked).
var blueprints: Array = []
## Rebaja del proximo Diezmo ganada (la avanzadilla echada), en %. Es solo el
## apunte para ensenarla y para no ofrecer otra avanzadilla: quien la aplica de
## verdad es StormManager.add_tithe_discount() (rama de la Orden), si existe.
var tithe_cut_pct: int = 0
## Incursiones sorteadas: alternan saqueadores y avanzadilla cuando se puede.
var raids_rolled: int = 0
var _next_id: int = 1

# ── Consultas ────────────────────────────────────────────────────────

func get_offer(offer_id: int) -> Dictionary:
	for offer in offers:
		if int(offer.get("id", 0)) == offer_id:
			return offer
	return {}

func has_kind(kind: String) -> bool:
	for offer in offers:
		if String(offer.get("kind", "")) == kind:
			return true
	return false

func has_unseen() -> bool:
	for offer in offers:
		if not bool(offer.get("seen", false)):
			return true
	return false

func has_outpost() -> bool:
	for offer in offers:
		if String(offer.get("flavor", "")) == Generator.FLAVOR_OUTPOST:
			return true
	return false

func has_blueprint(building_id: String) -> bool:
	return blueprints.has(building_id)

## Planos que ya estan prometidos en una oferta (para no sortear el mismo dos veces).
func offered_blueprints() -> Array:
	var list: Array = []
	for offer in offers:
		var id: String = String(offer.get("blueprint", ""))
		if id != "":
			list.append(id)
	return list

# ── El reloj ─────────────────────────────────────────────────────────

## Pone ofertas nuevas si toca. `ctx`:
##   raids (bool), expeditions (bool), outpost (bool), era (int),
##   blueprint (String: el plano que llevaria una expedicion nueva, "" = ninguno),
##   raid_out / expedition_out (bool: hay una columna de ese tipo fuera).
## `fresh_seed` es la semilla de la oferta nueva (si sale una). Devuelve
## [{"e": "offers_changed"}] si algo cambio.
func refresh(now: float, ctx: Dictionary, fresh_seed: int) -> Array:
	var changed := false
	# Una columna que ya no esta fuera (guardado raro, partida recargada sin
	# ella) no puede dejar su tipo bloqueado para siempre.
	if next_raid_at == INF and not bool(ctx.get("raid_out", false)):
		next_raid_at = now
	if next_expedition_at == INF and not bool(ctx.get("expedition_out", false)):
		next_expedition_at = now
	# Una avanzadilla sin Tormenta armada (Sandbox, Constructor, tras ganar) no
	# tiene Diezmo que rebajar: se va.
	if not bool(ctx.get("outpost", false)) and has_outpost():
		_drop_flavor(Generator.FLAVOR_OUTPOST)
		changed = true
	if bool(ctx.get("raids", false)) and not has_kind(Generator.KIND_RAID) and now >= next_raid_at:
		var flavor: String = Generator.FLAVOR_BANDITS
		if bool(ctx.get("outpost", false)) and tithe_cut_pct <= 0 and raids_rolled % 2 == 0:
			flavor = Generator.FLAVOR_OUTPOST
		raids_rolled += 1
		_add_offer(Generator.KIND_RAID, flavor, fresh_seed, int(ctx.get("era", 1)), "")
		changed = true
	if bool(ctx.get("expeditions", false)) and not has_kind(Generator.KIND_EXPEDITION) and now >= next_expedition_at:
		# Otra semilla para que la expedicion no copie a la incursion del mismo tic.
		_add_offer(Generator.KIND_EXPEDITION, "", fresh_seed * 31 + 7, int(ctx.get("era", 1)),
			String(ctx.get("blueprint", "")))
		changed = true
	return [{"e": "offers_changed"}] if changed else []

func _add_offer(kind: String, flavor: String, seed_value: int, era: int, blueprint: String) -> void:
	offers.append({
		"id": _next_id,
		"kind": kind,
		"flavor": flavor,
		"seed": seed_value if seed_value != 0 else 1,
		"era": maxi(1, era),
		"blueprint": blueprint,
		"seen": false,
	})
	_next_id += 1

func _drop_flavor(flavor: String) -> void:
	for i in range(offers.size() - 1, -1, -1):
		if String(offers[i].get("flavor", "")) == flavor:
			offers.remove_at(i)

# ── Lanzar y volver ──────────────────────────────────────────────────

## Saca la oferta del tablon para lanzarla. Devuelve la oferta (vacia si no
## existe). Mientras la columna esta fuera, no hay otra del mismo tipo: el
## reloj no corre hasta que vuelva (finish()).
func take(offer_id: int) -> Dictionary:
	for i in range(offers.size()):
		if int(offers[i].get("id", 0)) == offer_id:
			var offer: Dictionary = offers[i]
			offers.remove_at(i)
			# Hasta que vuelva, no sale otra de su tipo.
			if String(offer.get("kind", "")) == Generator.KIND_RAID:
				next_raid_at = INF
			else:
				next_expedition_at = INF
			return offer
	return {}

## La columna de esa oferta ha vuelto. `won` = la oferta se gasto (ganada, o
## con algun combate ganado y su botin cobrado): la siguiente de su tipo llega
## tras el enfriamiento. Si no se gano nada, el campamento sigue ahi: la misma
## oferta vuelve al tablon (ya vista) y se puede intentar otra vez.
func finish(offer: Dictionary, won: bool, now: float, cooldown: float) -> Array:
	var kind: String = String(offer.get("kind", ""))
	if not won and not offer.is_empty():
		var back: Dictionary = offer.duplicate(true)
		back["seen"] = true
		offers.append(back)
	if kind == Generator.KIND_RAID:
		next_raid_at = now + maxf(0.0, cooldown) if won else 0.0
	elif kind == Generator.KIND_EXPEDITION:
		next_expedition_at = now + maxf(0.0, cooldown) if won else 0.0
	return [{"e": "offers_changed"}]

## Lo traido de fuera que se queda en el tablon: planos y la rebaja del Diezmo.
## Lo demas (repuestos, colonos, oro) lo aplica el servicio a la colonia.
func bank_loot(loot: Dictionary) -> Array:
	var events: Array = []
	for id in loot.get("blueprints", []):
		var building_id: String = String(id)
		if building_id != "" and not blueprints.has(building_id):
			blueprints.append(building_id)
			events.append({"e": "blueprint_gained", "id": building_id})
	var cut: int = int(loot.get("tithe_pct", 0))
	if cut > 0:
		tithe_cut_pct += cut
		events.append({"e": "tithe_cut_gained", "pct": cut})
	if not events.is_empty():
		events.append({"e": "offers_changed"})
	return events

## El Diezmo ya paso: la rebaja se gasta y la avanzadilla que no se echo se va
## con los Tasadores (doc 21 §3.2).
func on_tithe_resolved() -> Array:
	var changed: bool = tithe_cut_pct > 0 or has_outpost()
	tithe_cut_pct = 0
	_drop_flavor(Generator.FLAVOR_OUTPOST)
	return [{"e": "offers_changed"}] if changed else []

## El jugador ha mirado el tablon: se apaga el punto rojo de "nuevo".
func mark_all_seen() -> Array:
	var changed := false
	for offer in offers:
		if not bool(offer.get("seen", false)):
			offer["seen"] = true
			changed = true
	return [{"e": "offers_changed"}] if changed else []

# ── Guardado ─────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"offers": offers.duplicate(true),
		# INF no cabe en JSON: -1 es "esperando a que vuelva la columna".
		"next_raid_at": next_raid_at if next_raid_at != INF else -1.0,
		"next_expedition_at": next_expedition_at if next_expedition_at != INF else -1.0,
		"blueprints": blueprints.duplicate(),
		"tithe_cut_pct": tithe_cut_pct,
		"raids_rolled": raids_rolled,
		"next_id": _next_id,
	}

## Idempotente: lo cargado sustituye a todo, nunca se suma. Una clave que falta
## es su valor por defecto (guardado anterior a esta rama: tablon vacio).
static func from_dict(data: Dictionary) -> SortieBoard:
	var board := SortieBoard.new()
	if data.is_empty():
		return board
	for raw in data.get("offers", []):
		if not raw is Dictionary:
			continue
		var offer: Dictionary = raw
		board.offers.append({
			"id": int(offer.get("id", 0)),
			"kind": String(offer.get("kind", "")),
			"flavor": String(offer.get("flavor", "")),
			"seed": int(offer.get("seed", 1)),
			"era": maxi(1, int(offer.get("era", 1))),
			"blueprint": String(offer.get("blueprint", "")),
			"seen": bool(offer.get("seen", false)),
		})
	var raid_at: float = float(data.get("next_raid_at", 0.0))
	var exp_at: float = float(data.get("next_expedition_at", 0.0))
	board.next_raid_at = INF if raid_at < 0.0 else raid_at
	board.next_expedition_at = INF if exp_at < 0.0 else exp_at
	for id in data.get("blueprints", []):
		if not board.blueprints.has(String(id)):
			board.blueprints.append(String(id))
	board.tithe_cut_pct = maxi(0, int(data.get("tithe_cut_pct", 0)))
	board.raids_rolled = maxi(0, int(data.get("raids_rolled", 0)))
	var highest: int = 0
	for offer in board.offers:
		highest = maxi(highest, int(offer["id"]))
	board._next_id = maxi(int(data.get("next_id", 1)), highest + 1)
	return board
