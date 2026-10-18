extends RefCounted
## El tablon de encargos: tres huecos, uno por fuente (la Regencia, los vecinos y
## el contrabandista). Cada hueco tiene un encargo a la vista ("10 tablones en
## 5 min -> 120 de oro") o espera a que llegue el siguiente.
##
## Modelo puro, al estilo de StormCycle y de los modelos de combate: sin nodos,
## sin EventBus, sin temporizadores y sin el `randf()` global. Lo que cambia el
## estado (`advance`, `deliver`, `discard`) devuelve un Array de eventos y
## ContractManager los publica. Asi un test puede jugar cien encargos sin escena.
##
## El modelo NO toca la bolsa: no sabe cuanto tienes. ContractManager mira si
## alcanza, cobra lo pedido, llama a `deliver()` y paga el premio que devuelve.
##
## Premios fijos y visibles (doc 21 §2.3: nada de cajas sorpresa): el premio se
## decide al aparecer el encargo y no cambia hasta que se entrega o se va.
##
## Reputacion (solo Gobernador, `ctx.reputation`): fallar o rechazar baja en 1 la
## de quien lo pidio (hasta `contract_reputation_min`); cumplir la sube en 1
## (hasta 0). Cada punto por debajo de 0 recorta los premios del siguiente
## encargo de esa fuente en `contract_reputation_step`. En Colono no se mueve.
##
## El contexto (`ctx`) que pasa el servicio en cada llamada:
##   era                 era actual (1..3)
##   unlocked            Array de nombres de recurso desbloqueados
##   colonists_ok        hay forma de dar colonos (PopulationManager.add_colonists)
##   morale_ok           la moral ya se mueve (en las fases 0-1 esta fija)
##   tithe_discount_ok   hay Diezmo y StormManager acepta rebajas
##   reputation          true en Gobernador

const SOURCES := ["regency", "neighbors", "smuggler"]
## El hilo del Telegrafo (feat/edificios-defensa-vida): un hueco de mas que se
## abre con un Telegrafo en pie (`ctx.extra_slots` > 0). Le llegan encargos de
## cualquier fuente abierta; el encargo guarda de quien es en `from` (su
## reputacion y su escala son las de esa fuente).
const WIRE := "telegraph"
## Todos los huecos del tablon, en orden: las tres fuentes y el hilo.
const ALL_SLOTS := ["regency", "neighbors", "smuggler", "telegraph"]
const SAVE_VERSION := 1

## source -> encargo ({} si el hueco espera). Un encargo:
##   id, source, template, ask {recurso: n}, reward {clase: n},
##   seconds_total, seconds_left
var slots: Dictionary = {}
## source -> segundos hasta el siguiente encargo (corre solo con la fuente abierta).
var cooldowns: Dictionary = {}
## source -> reputacion (0 = buena; negativa = paga menos). Solo Gobernador.
var reputation: Dictionary = {}
## source -> plantilla del ultimo encargo, para no repetir la misma dos veces.
var last_template: Dictionary = {}
var delivered_total: int = 0
var failed_total: int = 0
var _next_id: int = 1
var _rng := RandomNumberGenerator.new()

# ── Construccion ─────────────────────────────────────────────────────

## `rng_seed` negativo: semilla del sistema (el juego). Los tests pasan una.
static func create(rng_seed: int = -1) -> RefCounted:
	var board = load("res://scripts/economy/ContractBoard.gd").new()
	board.seed_rng(rng_seed)
	for source in ALL_SLOTS:
		board.slots[source] = {}
		var first: float = GameConfig.telegraph_first_delay if source == WIRE else float(GameConfig.contract_first_delay.get(source, 60.0))
		board.cooldowns[source] = GameConfig.get_duration(first)
		board.reputation[source] = 0
		board.last_template[source] = ""
	return board

func seed_rng(rng_seed: int) -> void:
	if rng_seed < 0:
		_rng.randomize()
	else:
		_rng.seed = rng_seed

# ── Consultas ────────────────────────────────────────────────────────

func get_contract(source: String) -> Dictionary:
	return slots.get(source, {})

func has_contract(source: String) -> bool:
	return not get_contract(source).is_empty()

## Los encargos a la vista, en el orden del tablon.
func active_contracts() -> Array:
	var out: Array = []
	for source in ALL_SLOTS:
		if has_contract(source):
			out.append(slots[source])
	return out

## La fuente ya encarga en esta era.
static func source_open(source: String, era: int) -> bool:
	return era >= int(GameConfig.contract_source_era.get(source, 1))

## El hueco `slot` saca encargos ahora: una fuente, en su era; el hilo del
## Telegrafo, con un Telegrafo en pie (`ctx.extra_slots` > 0) y alguna fuente
## abierta. Un encargo ya a la vista sigue su plazo aunque el hueco se cierre.
static func slot_open(slot: String, era: int, ctx: Dictionary = {}) -> bool:
	if slot == WIRE:
		if int(ctx.get("extra_slots", 0)) <= 0:
			return false
		for source in SOURCES:
			if source_open(source, era):
				return true
		return false
	return source_open(slot, era)

## De quien es el encargo de un hueco (la fuente real; en el hilo, `from`).
static func origin_of(contract: Dictionary, slot: String) -> String:
	return String(contract.get("from", slot))

## Lo que multiplica los premios de esa fuente por su reputacion (1.0 = entero).
func reward_mult(source: String) -> float:
	var rep: int = int(reputation.get(source, 0))
	return maxf(0.1, 1.0 + float(rep) * GameConfig.contract_reputation_step)

## Fraccion de plazo que queda (1 = recien llegado, 0 = se va).
static func time_fraction(contract: Dictionary) -> float:
	var total: float = float(contract.get("seconds_total", 0.0))
	if total <= 0.0:
		return 0.0
	return clampf(float(contract.get("seconds_left", 0.0)) / total, 0.0, 1.0)

# ── Reloj ────────────────────────────────────────────────────────────

## Avanza `delta` segundos de juego. Los plazos bajan; un encargo sin entregar a
## tiempo se va ("expired"); un hueco vacio de una fuente abierta cuenta su
## espera y, al llegar a 0, saca un encargo nuevo ("offered").
func advance(delta: float, ctx: Dictionary) -> Array:
	var events: Array = []
	if delta <= 0.0:
		return events
	var era: int = int(ctx.get("era", 1))
	for source in ALL_SLOTS:
		var contract: Dictionary = slots.get(source, {})
		if not contract.is_empty():
			contract["seconds_left"] = float(contract["seconds_left"]) - delta
			if float(contract["seconds_left"]) <= 0.0:
				contract["seconds_left"] = 0.0
				events.append_array(_close(source, "expired", ctx))
			continue
		if not slot_open(source, era, ctx):
			continue
		cooldowns[source] = float(cooldowns.get(source, 0.0)) - delta
		if float(cooldowns[source]) > 0.0:
			continue
		var fresh: Dictionary = roll(source, ctx)
		if fresh.is_empty():
			# Ninguna plantilla cabe aun (falta desbloquear lo que piden): se
			# vuelve a mirar dentro de un rato, sin gastar dados cada fotograma.
			cooldowns[source] = GameConfig.get_duration(GameConfig.contract_retry_delay)
			continue
		slots[source] = fresh
		cooldowns[source] = 0.0
		events.append({"type": "offered", "source": source, "contract": fresh.duplicate(true)})
	return events

## Entrega el encargo de `source`. Quien llama ya cobro lo pedido. Devuelve
## [{"type": "delivered", ...}] con el premio, o [] si no habia encargo.
func deliver(source: String, ctx: Dictionary) -> Array:
	if not has_contract(source):
		return []
	return _close(source, "delivered", ctx)

## "No, gracias": el hueco queda libre y el siguiente llega tras la espera de
## siempre. En Gobernador cuenta como no cumplir.
func discard(source: String, ctx: Dictionary) -> Array:
	if not has_contract(source):
		return []
	return _close(source, "discarded", ctx)

func _close(source: String, kind: String, ctx: Dictionary) -> Array:
	var contract: Dictionary = slots[source]
	slots[source] = {}
	cooldowns[source] = GameConfig.get_duration(GameConfig.contract_cooldown)
	# La reputacion es de quien lo pidio: en el hilo del Telegrafo, `from`.
	var who: String = origin_of(contract, source)
	var rep_before: int = int(reputation.get(who, 0))
	if kind == "delivered":
		delivered_total += 1
		if bool(ctx.get("reputation", false)):
			reputation[who] = mini(0, rep_before + 1)
	else:
		if kind == "expired":
			failed_total += 1
		if bool(ctx.get("reputation", false)):
			reputation[who] = maxi(GameConfig.contract_reputation_min, rep_before - 1)
	return [{
		"type": kind,
		"source": source,
		"from": who,
		"contract": contract,
		"reward": (contract.get("reward", {}) as Dictionary).duplicate() if kind == "delivered" else {},
		"reputation": int(reputation.get(who, 0)),
		"reputation_changed": int(reputation.get(who, 0)) != rep_before,
	}]

# ── Sorteo ───────────────────────────────────────────────────────────

## Un encargo nuevo de `source` para este contexto, o {} si ninguna plantilla
## cabe. No lo pone en el tablon (eso lo hace `advance`).
func roll(source: String, ctx: Dictionary) -> Dictionary:
	if source == WIRE:
		return _roll_wire(ctx)
	var pool: Array = fitting_templates(source, ctx)
	if pool.is_empty():
		return {}
	# No repetir el ultimo si hay otro.
	if pool.size() > 1:
		var last: String = String(last_template.get(source, ""))
		pool = pool.filter(func(t): return String(t.get("id", "")) != last)
	var template: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
	last_template[source] = String(template.get("id", ""))
	return build_contract(source, template, ctx)

## Un encargo por el hilo del Telegrafo: de una fuente abierta al azar que tenga
## alguna plantilla que quepa, sin repetir la ultima plantilla del hilo. El
## encargo es de esa fuente (`from`) pero vive en el hueco del hilo.
func _roll_wire(ctx: Dictionary) -> Dictionary:
	var era: int = int(ctx.get("era", 1))
	var origins: Array = []
	for s in SOURCES:
		if source_open(s, era) and not fitting_templates(s, ctx).is_empty():
			origins.append(s)
	if origins.is_empty():
		return {}
	var origin: String = origins[_rng.randi_range(0, origins.size() - 1)]
	var pool: Array = fitting_templates(origin, ctx)
	if pool.size() > 1:
		var last: String = String(last_template.get(WIRE, ""))
		pool = pool.filter(func(t): return String(t.get("id", "")) != last)
	var template: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
	last_template[WIRE] = String(template.get("id", ""))
	var contract: Dictionary = build_contract(origin, template, ctx)
	contract["source"] = WIRE
	contract["from"] = origin
	return contract

## Las plantillas de `source` que se pueden pedir ahora: su era llego, todo lo
## que piden y lo que pagan en recursos esta desbloqueado, y si pagan colonos
## hay como darlos (y si pagan moral, la moral ya se mueve).
static func fitting_templates(source: String, ctx: Dictionary) -> Array:
	var era: int = int(ctx.get("era", 1))
	var unlocked: Array = ctx.get("unlocked", [])
	var out: Array = []
	for template in GameConfig.contract_templates.get(source, []):
		if era < int(template.get("era", 1)):
			continue
		var ok := true
		for res in template.get("ask", {}):
			if not (String(res) in unlocked):
				ok = false
		for kind in template.get("reward", {}):
			if _is_resource_reward(String(kind)) and not (String(kind) in unlocked):
				ok = false
			if String(kind) == "colonists" and not bool(ctx.get("colonists_ok", false)):
				ok = false
			if String(kind) == "morale" and not bool(ctx.get("morale_ok", true)):
				ok = false
		if ok:
			out.append(template)
	return out

## Monta el encargo: cantidades escaladas por era, plazo y premio ya fijado.
func build_contract(source: String, template: Dictionary, ctx: Dictionary) -> Dictionary:
	var era: int = int(ctx.get("era", 1))
	var scale: float = era_scale(int(template.get("era", 1)), era)
	var ask := {}
	for res in template.get("ask", {}):
		ask[String(res)] = maxi(1, roundi(float(template["ask"][res]) * scale))
	var reward := {}
	var mult: float = reward_mult(source) if bool(ctx.get("reputation", false)) else 1.0
	for kind in template.get("reward", {}):
		var k := String(kind)
		var base: float = float(template["reward"][kind])
		# Lo que se cuenta en la bolsa crece con la era; moral, colonos y rebaja no.
		if _is_resource_reward(k):
			base *= scale
		reward[k] = maxi(1, roundi(base * mult))
	# Sin Diezmo (Constructor) o sin donde apuntar la rebaja, la Regencia paga en oro.
	if reward.has("tithe_discount") and not bool(ctx.get("tithe_discount_ok", false)):
		reward.erase("tithe_discount")
		reward["gold"] = int(reward.get("gold", 0)) + maxi(1, roundi(GameConfig.contract_tithe_fallback_gold * scale * mult))
	var seconds: float = GameConfig.get_duration(float(template.get("minutes", 5.0)) * 60.0)
	# Con un Telegrafo en pie, los plazos nuevos duran mas (ctx.duration_mult).
	seconds *= maxf(1.0, float(ctx.get("duration_mult", 1.0)))
	var contract := {
		"id": _next_id,
		"source": source,
		"template": String(template.get("id", "")),
		"ask": ask,
		"reward": reward,
		"seconds_total": seconds,
		"seconds_left": seconds,
	}
	_next_id += 1
	return contract

## Cuanto crece un encargo pensado para `template_era` cuando sale en `era`.
static func era_scale(template_era: int, era: int) -> float:
	return 1.0 + GameConfig.contract_era_step * float(maxi(0, era - template_era))

static func _is_resource_reward(kind: String) -> bool:
	return kind in ["gold", "wood", "steel", "oil", "food", "planks", "ingots", "beams", "fuel"]

# ── Guardado ─────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"v": SAVE_VERSION,
		"slots": slots.duplicate(true),
		"cooldowns": cooldowns.duplicate(),
		"reputation": reputation.duplicate(),
		"last_template": last_template.duplicate(),
		"delivered": delivered_total,
		"failed": failed_total,
		"next_id": _next_id,
	}

## Un tablon desde lo guardado. Sin datos (guardado viejo) es uno recien
## creado. Una fuente que falta o trae basura vuelve a su estado de serie. El
## dado se vuelve a sembrar del sistema, como StormCycle: lo que ya salio esta
## guardado tal cual, lo que salga despues no tiene por que repetirse.
static func from_dict(data: Dictionary) -> RefCounted:
	var board = create(-1)
	if data.is_empty():
		return board
	var saved_slots: Variant = data.get("slots", {})
	var saved_cd: Variant = data.get("cooldowns", {})
	var saved_rep: Variant = data.get("reputation", {})
	var saved_last: Variant = data.get("last_template", {})
	# Todos los huecos, el hilo del Telegrafo incluido (un guardado de antes no
	# lo trae: se queda como recien creado).
	for source in ALL_SLOTS:
		if saved_slots is Dictionary:
			var c: Variant = saved_slots.get(source, {})
			if c is Dictionary and _valid_contract(c):
				board.slots[source] = _clean_contract(c, source)
		if saved_cd is Dictionary and saved_cd.has(source):
			board.cooldowns[source] = maxf(0.0, float(saved_cd[source]))
		if saved_rep is Dictionary and saved_rep.has(source):
			board.reputation[source] = clampi(int(saved_rep[source]), GameConfig.contract_reputation_min, 0)
		if saved_last is Dictionary:
			board.last_template[source] = String(saved_last.get(source, ""))
	board.delivered_total = maxi(0, int(data.get("delivered", 0)))
	board.failed_total = maxi(0, int(data.get("failed", 0)))
	board._next_id = maxi(1, int(data.get("next_id", 1)))
	return board

static func _valid_contract(c: Dictionary) -> bool:
	return c.get("ask", null) is Dictionary and c.get("reward", null) is Dictionary \
		and not (c["ask"] as Dictionary).is_empty() and float(c.get("seconds_total", 0.0)) > 0.0

## JSON devuelve floats: se vuelven a enteros las cantidades.
static func _clean_contract(c: Dictionary, source: String) -> Dictionary:
	var ask := {}
	for res in c["ask"]:
		ask[String(res)] = maxi(1, int(c["ask"][res]))
	var reward := {}
	for kind in c["reward"]:
		reward[String(kind)] = maxi(1, int(c["reward"][kind]))
	var total: float = float(c["seconds_total"])
	var out := {
		"id": int(c.get("id", 0)),
		"source": source,
		"template": String(c.get("template", "")),
		"ask": ask,
		"reward": reward,
		"seconds_total": total,
		"seconds_left": clampf(float(c.get("seconds_left", total)), 0.0, total),
	}
	# El hilo del Telegrafo guarda de quien es el encargo.
	if source == WIRE:
		var origin: String = String(c.get("from", ""))
		out["from"] = origin if origin in SOURCES else "neighbors"
	return out
