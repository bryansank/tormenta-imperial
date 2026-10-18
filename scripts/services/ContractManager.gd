extends Node
## El tablon de encargos: dueno del modelo puro ContractBoard, lo hace avanzar
## con el tiempo de juego y publica en el EventBus lo que devuelve.
##
## Es el unico que toca la bolsa por un encargo: mira si alcanza, cobra lo
## pedido y paga el premio (recursos, moral, colonos o la rebaja del Diezmo). El
## panel (ContractPanel) solo lee y llama a deliver()/discard().
##
## Va el ultimo de la lista de autoloads: usa ResourceManager, PopulationManager,
## ProgressionManager, StormManager, CombatManager, GameManager y RankManager, y
## nadie lo necesita durante su _ready.
##
## Guardado: clave "contracts" (GameManager). load_save_data() reemplaza el
## tablon entero por el guardado (idempotente); sin clave, tablon nuevo.

const BoardScript := preload("res://scripts/economy/ContractBoard.gd")

## Untyped a proposito: el modelo no tiene class_name (se usa con preload).
var _board

func _ready() -> void:
	_board = BoardScript.create()

func _process(delta: float) -> void:
	if not GameManager.is_started() or not GameMode.contracts_enabled():
		return
	# Con un combate abierto el reloj de los encargos espera: no se puede
	# fabricar ni entregar desde el tablero.
	if CombatManager.is_board_open():
		return
	_publish(_board.advance(GameConfig.sim_delta(delta), context()))

# ── Consultas ────────────────────────────────────────────────────────

func get_board() -> Variant:
	return _board

func is_enabled() -> bool:
	return GameMode.contracts_enabled()

## El encargo de una fuente ({} si espera).
func get_contract(source: String) -> Dictionary:
	return _board.get_contract(source)

## Segundos hasta el siguiente encargo de una fuente con el hueco vacio.
func seconds_until_next(source: String) -> float:
	return maxf(0.0, float(_board.cooldowns.get(source, 0.0)))

func is_source_open(source: String) -> bool:
	return BoardScript.slot_open(source, ProgressionManager.current_era, context())

## Los huecos que ensena el tablon: las tres fuentes y, con un Telegrafo en pie
## (o un encargo suyo aun a la vista), el hilo (feat/edificios-defensa-vida).
func slot_ids() -> Array:
	var out: Array = BoardScript.SOURCES.duplicate()
	if GameConfig.contract_extra_slots > 0 or not get_contract(BoardScript.WIRE).is_empty():
		out.append(BoardScript.WIRE)
	return out

## De quien es el encargo de un hueco (en el hilo del Telegrafo, su fuente real).
func origin_of(slot: String) -> String:
	return BoardScript.origin_of(get_contract(slot), slot)

func get_reputation(source: String) -> int:
	return int(_board.reputation.get(source, 0))

## Lo que falta para entregar (recurso -> cantidad). {} = se puede.
func missing_for(source: String) -> Dictionary:
	var contract: Dictionary = get_contract(source)
	var out := {}
	for res in contract.get("ask", {}):
		var type: int = ResourceManager.name_to_type(String(res))
		if type < 0:
			continue
		var short: int = int(contract["ask"][res]) - ResourceManager.get_amount(type)
		if short > 0:
			out[String(res)] = short
	return out

func can_deliver(source: String) -> bool:
	return is_enabled() and not get_contract(source).is_empty() and missing_for(source).is_empty()

## Alguna fuente tiene un encargo que ya se puede entregar. Para ¿QUE HACER?.
func first_deliverable() -> String:
	for source in slot_ids():
		if can_deliver(source):
			return source
	return ""

## Lo que el modelo necesita saber de la partida.
func context() -> Dictionary:
	var unlocked: Array = []
	for res in ["gold", "wood", "steel", "oil", "food", "planks", "ingots", "beams", "fuel"]:
		if ResourceManager.is_unlocked_by_name(res):
			unlocked.append(res)
	return {
		"era": ProgressionManager.current_era,
		"unlocked": unlocked,
		"colonists_ok": PopulationManager.has_method("add_colonists"),
		"morale_ok": ProgressionManager.current_phase >= GameConfig.Phase.ECONOMY,
		"tithe_discount_ok": GameMode.tithe_enabled() and StormManager.has_method("add_tithe_discount"),
		"reputation": GameMode.is_governor(),
		# Telegrafo (DefenseLifeEffects): un hueco mas y plazos mas largos.
		"extra_slots": GameConfig.contract_extra_slots,
		"duration_mult": GameConfig.contract_duration_mult,
	}

# ── Ordenes ──────────────────────────────────────────────────────────

## Entrega el encargo de `source`: cobra lo pedido y paga el premio. false si no
## hay encargo o no alcanza (sin tocar nada).
func deliver(source: String) -> bool:
	if not can_deliver(source):
		return false
	var contract: Dictionary = get_contract(source)
	var cost := {}
	for res in contract["ask"]:
		cost[ResourceManager.name_to_type(String(res))] = int(contract["ask"][res])
	if not ResourceManager.spend_cost(cost):
		return false
	_publish(_board.deliver(source, context()))
	return true

## "No, gracias": libera el hueco. En Gobernador cuenta como no cumplir.
func discard(source: String) -> bool:
	if get_contract(source).is_empty():
		return false
	_publish(_board.discard(source, context()))
	return true

# ── Publicar ─────────────────────────────────────────────────────────

func _publish(events: Array) -> void:
	if events.is_empty():
		return
	for event in events:
		var source: String = String(event.get("source", ""))
		var contract: Dictionary = event.get("contract", {})
		match String(event.get("type", "")):
			"offered":
				EventBus.contract_offered.emit(source, contract)
				EventBus.notification_posted.emit(
					Tr.t("NOTIF_CONTRACT_NEW") % Tr.t(source_name_key(source)), "notice", UITheme.INFO)
			"delivered":
				var reward: Dictionary = event.get("reward", {})
				_pay(reward)
				EventBus.contract_delivered.emit(source, contract, reward)
				EventBus.notification_posted.emit(
					Tr.t("NOTIF_CONTRACT_DONE") % Tr.t(source_name_key(source)), "success", UITheme.POSITIVE)
				if RankManager.has_method("add_xp"):
					RankManager.add_xp(GameConfig.contract_rank_xp)
			"expired":
				EventBus.contract_expired.emit(source, contract, int(event.get("reputation", 0)))
				var key := "NOTIF_CONTRACT_LOST_REP" if bool(event.get("reputation_changed", false)) else "NOTIF_CONTRACT_LOST"
				EventBus.notification_posted.emit(
					Tr.t(key) % Tr.t(source_name_key(source)), "warning", UITheme.WARNING)
			"discarded":
				EventBus.contract_discarded.emit(source, contract)
	EventBus.contract_board_changed.emit()
	GameManager.request_save()

## Paga un premio. Cada clase tiene su sitio; la rebaja del Diezmo pasa por un
## unico metodo aditivo de StormManager (rama feat/orden-regencia). Si aun no
## existe, el modelo ya la cambio por oro al sortear (context()); si existe pero
## no la apunta (devuelve -1), se paga el oro de reserva.
func _pay(reward: Dictionary) -> void:
	for kind in reward:
		var amount: int = int(reward[kind])
		match String(kind):
			"morale":
				PopulationManager.adjust_morale(amount)
			"colonists":
				if PopulationManager.has_method("add_colonists"):
					PopulationManager.call("add_colonists", amount)
			"tithe_discount":
				# API de feat/orden-regencia (PR #53):
				#   add_tithe_discount(source: String, pct: float, notify := true) -> float
				# `pct` es fraccion (0,10 = 10 %), aditiva, tope 0,5, dura hasta el
				# proximo Diezmo; devuelve -1.0 si no la apunto (entonces, oro).
				var recorded: float = -1.0
				if StormManager.has_method("add_tithe_discount"):
					recorded = float(StormManager.call("add_tithe_discount", "contrato", float(amount) / 100.0))
				if recorded < 0.0:
					ResourceManager.add(ResourceManager.Type.GOLD, GameConfig.contract_tithe_fallback_gold)
			_:
				var type: int = ResourceManager.name_to_type(String(kind))
				if type >= 0:
					ResourceManager.add(type, amount)

static func source_name_key(source: String) -> String:
	return "CONTRACT_SRC_" + source.to_upper()

# ── Guardado ─────────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return _board.to_dict()

## Idempotente: el tablon entero sale de lo guardado. Sin clave (guardado de
## antes de los encargos) = tablon nuevo, con la primera espera de cada fuente.
func load_save_data(data: Dictionary) -> void:
	_board = BoardScript.from_dict(data)
	EventBus.contract_board_changed.emit()

## Tira el tablon de la partida anterior. Sin avisos.
func reset() -> void:
	_board = BoardScript.create()
	EventBus.contract_board_changed.emit()
