extends Node
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
## Manages timed processes for buildings and mining for deposits.
## Reads definitions from GameConfig (durations already scaled).

var _type_map := {
	"gold": ResourceManager.Type.GOLD,
	"steel": ResourceManager.Type.STEEL,
	"oil": ResourceManager.Type.OIL,
	"wood": ResourceManager.Type.WOOD,
	"planks": ResourceManager.Type.PLANKS,
	"ingots": ResourceManager.Type.INGOTS,
	"beams": ResourceManager.Type.BEAMS,
	"fuel": ResourceManager.Type.FUEL,
	"food": ResourceManager.Type.FOOD,
}

# Active processes: Node -> {id, name_key, remaining, duration, produces, cost,
#   count, total, workers}
# Se guarda la CLAVE de traduccion, no el texto: el nombre se traduce al
# ensenarlo, asi que cambiar de idioma no deja la cola hablando el anterior.
#
# Lotes (2026-10-14): `cost` es lo de UNA vuelta; `count` las vueltas que faltan
# por entregar (la de ahora incluida) y `total` las que se pidieron. Todo se paga
# al arrancar. `workers` son los trabajadores que ocupa mientras dura (minar a
# mano: en una veta o desde el Nucleo).
var _active: Dictionary = {}

## Cae ceniza y la Tormenta todavia no ha roto: la ultima ventana en la que lo
## que hay en la cola aun se puede salvar. Se lleva por señal y no preguntandole
## la fase a StormManager, para que este servicio no dependa de aquel.
var _ash_overhead: bool = false

func _ready() -> void:
	EventBus.storm_ash_started.connect(_on_ash_started)
	EventBus.storm_started.connect(_on_storm_started)
	EventBus.storm_ended.connect(_on_storm_ended)
	# Al cargar partida, el estado de ceniza se reconstruye preguntando la fase.
	# Es transitorio y no viaja en el guardado: sin esto, quien guarda con la
	# ceniza encima recarga creyendo que no pasa nada y pierde la cola sin haber
	# visto un solo aviso en esa sesion.
	EventBus.game_load_completed.connect(_resync_storm_phase)

func _resync_storm_phase() -> void:
	_ash_overhead = StormManager.is_ashfall() and not StormManager.is_trial_running()

## Los procesos que ofrece un edificio. El Nucleo, ademas de los suyos, los de
## todos los talleres y el minado a mano de cada yacimiento, mas lentos
## (GameConfig.get_core_extra_processes). Quien los ensena filtra los que
## tengan un recurso o material aun bloqueado.
func get_processes_for(building_id: String) -> Array:
	var own := GameConfig.get_processes_for(building_id)
	if building_id == "nucleo":
		own.append_array(GameConfig.get_core_extra_processes())
	return own

func get_mining_info(deposit_id: String) -> Dictionary:
	return GameConfig.get_mining_info(deposit_id)

func is_busy(node: Node) -> bool:
	return _active.has(node)

## Lo que devolveria cancelar ahora mismo, sin cancelar nada. La UI lo ensena
## antes de que el jugador confirme, y es el mismo numero que luego se abona.
func get_refund_preview(node: Node) -> Dictionary:
	if not _active.has(node):
		return {}
	# Ronda ui3 (2026-10-19): la tasa solo muerde a la tanda en marcha; las que
	# esperan en la cola no se empezaron y vuelven enteras, como con −1 / Vaciar
	# (si no, cancelar todo devolveria menos que vaciar y cancelar despues).
	var info: Dictionary = _active[node]
	var refund := GameConfig.get_cancel_refund(info.get("cost", {}))
	var waiting := _cost_times(info.get("cost", {}), int(info.get("count", 1)) - 1) if int(info.get("count", 1)) > 1 else {}
	for res_name in waiting:
		refund[res_name] = int(refund.get(res_name, 0)) + int(waiting[res_name])
	return _promise(node, refund)

## Lo que de verdad vuelve de `amounts`: en un edificio, todo (lo que no cabe
## en la bolsa se queda dentro para RECOGER); fuera de uno (una veta), lo que
## quepa. Prometer un 70% que no cabe seria mentir en el propio boton.
func _promise(node: Node, amounts: Dictionary) -> Dictionary:
	if amounts.is_empty():
		return {}
	if _keeps_leftover(node):
		return amounts.duplicate()
	return ResourceManager.fit_into_storage(amounts)

func _keeps_leftover(node: Node) -> bool:
	return node != null and is_instance_valid(node) and not GridManager.get_building_info(node).is_empty()

## Lo que sobreviviria a la Tormenta si rompiera ahora mismo. Hoy es siempre
## vacio —se pierde con su coste— pero existe como funcion y no como cero escrito
## a mano para que la pantalla pueda ensenarlo igual que el reembolso de
## cancelar, y para que aflojar la regla sea tocar el ratio y nada mas.
func get_storm_loss_preview(node: Node) -> Dictionary:
	if not _active.has(node):
		return {}
	return ResourceManager.fit_into_storage(
		GameConfig.get_storm_loss_refund(_paid_cost(_active[node])))

## Cancela el proceso o minado en curso y devuelve parte de lo pagado.
## Devuelve el reembolso realmente abonado (recurso -> cantidad); vacio si no
## habia nada en curso o si lo que habia no costaba recursos (un minado).
func cancel(node: Node) -> Dictionary:
	if not _active.has(node):
		return {}
	var info: Dictionary = _active[node]
	# Lo prometido y lo abonado salen de la misma llamada: nunca pueden divergir.
	var refund := _drop(node, get_refund_preview(node))
	EventBus.process_cancelled.emit(node, str(info.get("id", "")), refund)
	return refund

## Saca algo de la cola y abona lo que le corresponda. Arrepentirse y perderlo
## por la Tormenta son la misma operacion con distinto precio: un unico sitio
## donde se borra y se paga evita que una de las dos vias se olvide de la otra
## mitad el dia que esto cambie.
func _drop(node: Node, refund: Dictionary) -> Dictionary:
	_active.erase(node)
	_give_back(node, refund)
	return refund

## Devuelve `amounts`: a la bolsa lo que quepa y, en un edificio, el resto se
## queda dentro (ProductionManager.keep_in_building), como la produccion que no
## cabe. Nada pagado se pierde por devolverlo con la bolsa llena.
func _give_back(node: Node, amounts: Dictionary) -> void:
	var leftover := {}
	var keep := _keeps_leftover(node)
	for res_name in amounts:
		if not _type_map.has(res_name):
			continue
		var amount := int(amounts[res_name])
		if keep:
			var rest: int = ResourceManager.add_fitting(_type_map[res_name], amount)
			if rest > 0:
				leftover[res_name] = rest
		else:
			ResourceManager.add(_type_map[res_name], amount)
	if not leftover.is_empty():
		ProductionManager.keep_in_building(node, leftover)

func get_active(node: Node) -> Dictionary:
	return _active.get(node, {})

## Nombre del proceso en curso, traducido ahora. Vacio si no hay nada.
func get_active_name(node: Node) -> String:
	if not _active.has(node):
		return ""
	return _display_name(_active[node])

func _display_name(info: Dictionary) -> String:
	var key := str(info.get("name_key", ""))
	if key != "":
		return Tr.t(key)
	# Guardado viejo cuyo id ya no existe: se ensena el texto que trajo.
	return str(info.get("legacy_name", info.get("id", "")))

## La clave de traduccion de un proceso o minado por su id. Sirve para cargar
## guardados de antes, que traian el nombre ya traducido y no la clave.
func _name_key_for(process_id: String) -> String:
	for building_id in GameConfig.building_processes:
		for proc in GameConfig.building_processes[building_id]:
			if str(proc.get("id", "")) == process_id:
				return str(proc.get("name", ""))
	# El minado desde el Nucleo es "core_" + el id de la veta.
	var mine_id := process_id.trim_prefix(GameConfig.CORE_MINING_PREFIX)
	for deposit_id in GameConfig.mining_data:
		var mine: Dictionary = GameConfig.mining_data[deposit_id]
		if str(mine.get("id", "")) == mine_id:
			return str(mine.get("name", ""))
	return ""

## Lo pagado y aun no entregado: el coste de una vuelta por las que faltan.
func _paid_cost(info: Dictionary) -> Dictionary:
	return _cost_times(info.get("cost", {}), int(info.get("count", 1)))

func _cost_times(cost: Dictionary, times: int) -> Dictionary:
	var out := {}
	for res_name in cost:
		out[res_name] = int(cost[res_name]) * maxi(1, times)
	return out

## Vueltas que faltan del lote en curso (la de ahora incluida); 0 si no hay nada.
func get_batch_left(node: Node) -> int:
	if not _active.has(node):
		return 0
	return int(_active[node].get("count", 1))

## Vueltas que se pidieron en el lote en curso; 0 si no hay nada.
func get_batch_total(node: Node) -> int:
	if not _active.has(node):
		return 0
	return int(_active[node].get("total", get_batch_left(node)))

## Tiempo que falta para acabar el lote entero (la vuelta de ahora y las demas).
func get_batch_remaining(node: Node) -> float:
	if not _active.has(node):
		return 0.0
	var info: Dictionary = _active[node]
	return float(info["remaining"]) + float(info["duration"]) * float(get_batch_left(node) - 1)

## Usos que le quedan a un yacimiento, o -1 si no es un yacimiento (sin limite).
func deposit_uses_left(node: Node) -> int:
	if node == null or not is_instance_valid(node) or not node.has_meta("uses_remaining"):
		return -1
	return int(node.get_meta("uses_remaining"))

## Cuantas vueltas caben en un lote ahora mismo (lo que ofrece MAX), de 0 a
## GameConfig.process_batch_max. Lo limitan:
##   - los recursos para pagarlas todas por adelantado;
##   - los usos que le queden al yacimiento (`uses_left`, -1 = sin limite);
##   - el hueco de la bolsa compartida: lo que entra de mas menos lo que se paga
##     por vuelta (los materiales del taller no ocupan bolsa). Siempre cabe una.
## Los trabajadores no limitan el numero: un lote ocupa los mismos todo el rato;
## si faltan, el bloqueo lo dice (`process_blocker` / `mining_blocker`).
func max_batch(process: Dictionary, uses_left: int = -1) -> int:
	var n: int = GameConfig.process_batch_max
	var cost: Dictionary = process.get("cost", {})
	for res_name in cost:
		var per: int = int(cost[res_name])
		if per <= 0 or not _type_map.has(res_name):
			continue
		n = mini(n, floori(float(ResourceManager.get_amount(_type_map[res_name])) / float(per)))
	if uses_left >= 0:
		n = mini(n, uses_left)
	if n <= 0:
		return 0
	var net := 0
	var produces: Dictionary = process.get("produces", {})
	for res_name in produces:
		if not ResourceManager.is_material_name(String(res_name)):
			net += int(produces[res_name])
	for res_name in cost:
		if not ResourceManager.is_material_name(String(res_name)):
			net -= int(cost[res_name])
	if net > 0:
		n = mini(n, maxi(1, floori(float(ResourceManager.get_free_space()) / float(net))))
	return n

## Por que no se puede arrancar este proceso ahora (aparte de pagarlo): "" si se
## puede, o una clave de Tr. Hoy solo el minado a mano desde el Nucleo pide
## trabajadores libres.
func process_blocker(process: Dictionary) -> String:
	var w: int = int(process.get("workers", 0))
	if w > 0 and PopulationManager.get_free_workers() < w:
		return "MINE_NEEDS_WORKERS"
	return ""

func get_progress(node: Node) -> float:
	if not _active.has(node):
		return 0.0
	var info: Dictionary = _active[node]
	return clampf(1.0 - (info["remaining"] / info["duration"]), 0.0, 1.0)

## Arranca un proceso, o un lote de `count` vueltas seguidas del mismo. Se paga
## todo al arrancar; si no alcanza para todas, no arranca ninguna.
func start_process(node: Node, process: Dictionary, count: int = 1) -> bool:
	if _active.has(node):
		return false
	count = clampi(count, 1, GameConfig.process_batch_max)
	if process_blocker(process) != "":
		return false
	if process.has("cost") and not process["cost"].is_empty():
		var cost := _convert_cost(_cost_times(process["cost"], count))
		if not ResourceManager.can_afford(cost):
			return false
		ResourceManager.spend_cost(cost)
	var workers: int = int(process.get("workers", 0))
	_active[node] = {
		"id": process["id"],
		"name_key": str(process["name"]),
		"remaining": process["duration"],
		"duration": process["duration"],
		"produces": process["produces"],
		# Lo pagado se guarda con el proceso: sin esto, cancelar no puede
		# devolver nada porque nadie recuerda cuanto costo. Es lo de UNA vuelta.
		"cost": process.get("cost", {}).duplicate(),
		"count": count,
		"total": count,
		"workers": workers,
	}
	# Minar a mano desde el Nucleo ocupa trabajadores: se anuncia como minado
	# para que PopulationManager los descuente (escucha mining_started).
	if workers > 0:
		EventBus.mining_started.emit(node, str(process["id"]))
	else:
		EventBus.process_started.emit(node, process["id"])
	# Nunca se bloquea la cola durante la ceniza, pero tampoco se deja que el
	# jugador meta ahi el almacen sin saber lo que arriesga.
	_warn_if_ash()
	return true

## Tandas que acumulan (decision de Bryan, 2026-10-19): cada x1 / x5 / MAX de la
## ficha SUMA una tanda a la cola de ese proceso (x1 + x1 + x5 = 7). Se cobra al
## encolar, como al arrancar un lote: lo que esta en la cola ya esta pagado, asi
## que cancelar o la Tormenta siguen leyendo `count` x coste. Un edificio hace un
## proceso a la vez: con otro en marcha no se encola (la ficha lo dice). Nunca
## mas de GameConfig.process_batch_max en la cola. El guardado no cambia: la cola
## son `count` / `total` de la entrada (los guardados viejos valen).
func enqueue_process(node: Node, process: Dictionary, count: int = 1) -> bool:
	if not _active.has(node):
		return start_process(node, process, count)
	var info: Dictionary = _active[node]
	if str(info.get("id", "")) != str(process.get("id", "")):
		return false
	var room: int = GameConfig.process_batch_max - int(info.get("count", 1))
	count = mini(count, room)
	if count <= 0:
		return false
	if process.has("cost") and not process["cost"].is_empty():
		var cost := _convert_cost(_cost_times(process["cost"], count))
		if not ResourceManager.can_afford(cost):
			return false
		ResourceManager.spend_cost(cost)
	info["count"] = int(info.get("count", 1)) + count
	info["total"] = int(info.get("total", 1)) + count
	EventBus.process_started.emit(node, str(info["id"]))
	_warn_if_ash()
	return true

## Lo mismo para el minado a mano de una veta (no cuesta recursos; nunca mas que
## los usos que le queden).
func enqueue_mining(node: Node, deposit_id: String, count: int = 1) -> bool:
	if not _active.has(node):
		return start_mining(node, deposit_id, count)
	var info: Dictionary = _active[node]
	var data := get_mining_info(deposit_id)
	if data.is_empty() or str(info.get("id", "")) != str(data.get("id", "")):
		return false
	var room: int = GameConfig.process_batch_max - int(info.get("count", 1))
	var uses := deposit_uses_left(node)
	if uses >= 0:
		room = mini(room, uses - int(info.get("count", 1)))
	count = mini(count, room)
	if count <= 0:
		return false
	info["count"] = int(info.get("count", 1)) + count
	info["total"] = int(info.get("total", 1)) + count
	EventBus.mining_started.emit(node, deposit_id)
	return true

## Cuantas tandas hay en la cola sin empezar (las que se pueden quitar).
func queued_not_started(node: Node) -> int:
	if not _active.has(node):
		return 0
	return maxi(0, int(_active[node].get("count", 1)) - 1)

## Cuantas tandas mas caben en la cola de `node` para `process` (0 si el
## edificio hace otra cosa). Sin nada en marcha, lo que dice max_batch.
func room_for(node: Node, process: Dictionary, uses_left: int = -1) -> int:
	var mx := max_batch(process, uses_left)
	if not _active.has(node):
		return mx
	var info: Dictionary = _active[node]
	if str(info.get("id", "")) != str(process.get("id", "")):
		return 0
	var room: int = GameConfig.process_batch_max - int(info.get("count", 1))
	if uses_left >= 0:
		room = mini(room, uses_left - int(info.get("count", 1)))
	return clampi(mini(mx, room), 0, GameConfig.process_batch_max)

## Quita `n` tandas sin empezar (la de ahora sigue) y devuelve ENTERO lo que se
## pago por ellas: no se empezaron, asi que no hay tasa de cancelacion. Lo que
## no quepa en la bolsa se recorta como cualquier reembolso.
func dequeue(node: Node, n: int = 1) -> Dictionary:
	var take := mini(n, queued_not_started(node))
	if take <= 0:
		return {}
	var info: Dictionary = _active[node]
	info["count"] = int(info.get("count", 1)) - take
	info["total"] = maxi(int(info["count"]), int(info.get("total", 1)) - take)
	var refund := _promise(node, _cost_times(info.get("cost", {}), take)) if not (info.get("cost", {}) as Dictionary).is_empty() else {}
	_give_back(node, refund)
	EventBus.process_started.emit(node, str(info.get("id", "")))
	return refund

## Por que no se puede sacar a mano esta veta ahora: "" si se puede, o una clave
## de Tr. Dos reglas (2026-09-28): la veta tiene que tocar una carretera unida al
## Nucleo, y hacen falta trabajadores libres (GameConfig.mining_workers).
func mining_blocker(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return "MINE_NEEDS_ROAD"
	# Sin Nucleo (una escena de prueba montada a mano) no hay red ni reparto que
	# exigir, como en la regla de carreteras.
	if Rules.core_cells().is_empty():
		return ""
	var cell: Vector2i = node.get_meta("cell", Vector2i(-1, -1))
	var size: Vector2i = node.get_meta("deposit_size", Vector2i(2, 2))
	if not Rules.touches_network(GridManager.cells_for(cell, size), Rules.network_view()):
		return "MINE_NEEDS_ROAD"
	if PopulationManager.get_free_workers() < GameConfig.mining_workers:
		return "MINE_NEEDS_WORKERS"
	return ""

## Trabajadores ocupados ahora mismo sacando vetas a mano (en una veta o desde
## el Nucleo). PopulationManager los descuenta al repartir: mientras se mina,
## esos no estan en ningun edificio. Un lote ocupa los mismos todo el rato.
func busy_mining_workers() -> int:
	var n := 0
	for node in _active:
		if is_instance_valid(node):
			n += _workers_of(_active[node])
	return n

## Los trabajadores que ocupa una entrada. Las de antes de los lotes no traen
## `workers`: un minado de veta ocupaba GameConfig.mining_workers.
func _workers_of(info: Dictionary) -> int:
	if info.has("workers"):
		return int(info["workers"])
	return GameConfig.mining_workers if String(info.get("id", "")).begins_with("mine_") else 0

## Si una entrada es un minado a mano (en una veta o desde el Nucleo): esos
## avisan con mining_started / mining_completed.
func _is_mining(info: Dictionary) -> bool:
	return String(info.get("id", "")).begins_with("mine_") or _workers_of(info) > 0

## Mina a mano una veta, o un lote de `count` vueltas seguidas (nunca mas que
## los usos que le queden: la ultima vuelta agota la veta).
func start_mining(node: Node, deposit_id: String, count: int = 1) -> bool:
	if _active.has(node):
		return false
	count = clampi(count, 1, GameConfig.process_batch_max)
	var uses := deposit_uses_left(node)
	if uses >= 0:
		count = mini(count, maxi(1, uses))
	if not GameConfig.is_deposit_unlocked(deposit_id):
		return false
	if mining_blocker(node) != "":
		return false
	var data := get_mining_info(deposit_id)
	if data.is_empty():
		return false
	_active[node] = {
		"id": data["id"],
		"name_key": str(data["name"]),
		"remaining": data["duration"],
		"duration": data["duration"],
		"produces": data["produces"],
		# Minar no cuesta recursos: cancelar solo cuesta el tiempo invertido.
		"cost": {},
		"count": count,
		"total": count,
		"workers": GameConfig.mining_workers,
	}
	EventBus.mining_started.emit(node, deposit_id)
	_warn_if_ash()
	return true

func _process(delta: float) -> void:
	# x2: la simulacion avanza al doble (GameConfig.sim_delta).
	delta = GameConfig.sim_delta(delta)
	var completed: Array = []
	var vanished: Array = []
	for node in _active:
		if not is_instance_valid(node):
			vanished.append(node)
			continue
		_active[node]["remaining"] -= delta
		if _active[node]["remaining"] <= 0.0:
			completed.append(node)
	# Un edificio que ya no existe no entrega nada: su entrada se tira sin abonar.
	# Antes se mandaba a `_complete()`, que abonaba la produccion igual —el guard
	# de validez solo envolvia el texto flotante y la señal— y ademas ni siquiera
	# llegaba: el tipado de `_complete(node: Node)` rechaza un nodo liberado, de
	# modo que la entrada no se borraba nunca y el error se repetia cada frame.
	for node in vanished:
		_active.erase(node)
	for node in completed:
		_complete(node)

func _complete(node: Node) -> void:
	var info: Dictionary = _active[node]
	var pid: String = str(info["id"])
	# Un edificio que ya no existe no entrega nada. El guard vive aqui, donde se
	# paga, y no en quien llama: cuando la proteccion esta en quien llama, cada
	# camino nuevo tiene que acordarse de ella y basta con que uno se olvide para
	# que la produccion de una partida muerta caiga en la siguiente.
	if not is_instance_valid(node):
		_active.erase(node)
		return
	# Lote: si quedan vueltas, la siguiente empieza ya (con lo que sobro de este
	# fotograma); si no, la entrada se va. Se decide ANTES de avisar, para que
	# quien escuche la senal vea el lote como esta de verdad.
	var left: int = int(info.get("count", 1)) - 1
	if left > 0:
		info["count"] = left
		info["remaining"] = float(info["remaining"]) + float(info["duration"])
	else:
		_active.erase(node)
	# Lo que no cabe en la bolsa se queda en el edificio para recogerlo despues
	# (2026-10-04: bolsa llena = parar, no tirar). Un minado no tiene donde
	# guardarlo: ahi lo que no cabe se sigue perdiendo, avisado.
	var leftover := {}
	var in_building: bool = not GridManager.get_building_info(node).is_empty()
	for res_name in info["produces"]:
		if _type_map.has(res_name):
			var amount: int = int(info["produces"][res_name])
			if in_building:
				var rest: int = ResourceManager.add_fitting(_type_map[res_name], amount)
				if rest > 0:
					leftover[res_name] = rest
				amount -= rest
			else:
				ResourceManager.add(_type_map[res_name], amount)
			if amount > 0:
				FloatingText.spawn_resource_on(node, amount, res_name)
	if not leftover.is_empty():
		ProductionManager.keep_in_building(node, leftover)
	if _is_mining(info):
		EventBus.mining_completed.emit(node, pid)
	else:
		EventBus.process_completed.emit(node, pid)

func _convert_cost(cost_dict: Dictionary) -> Dictionary:
	var result := {}
	for res_name in cost_dict:
		if _type_map.has(res_name):
			result[_type_map[res_name]] = cost_dict[res_name]
	return result

# ── La Tormenta arruina la cola ──
#
# La cola sigue abierta las tres fases: gastar el almacen es una decision del
# jugador y nadie se la quita. Lo que cambia es que deja de ser un escondite —
# el coste se paga al arrancar, asi que llenar la cola hacia que los Tasadores
# auditaran ceros, y con el margen de 1,5x de los procesos eso no solo salvaba
# los recursos, los multiplicaba.
#
# Se cierra sin quitar la decision: lo que siga dentro cuando rompa la TORMENTA
# se pierde con su coste. Refugiarse ahi pasa a ser una apuesta contra un reloj
# que no se ve.

## Empieza la ceniza: la ultima ventana para sacar de la cola lo que haya dentro.
func _on_ash_started() -> void:
	# La tormenta de prueba de la era 1 no se lleva la cola: es un ensayo.
	if StormManager.is_trial_running():
		return
	_ash_overhead = true
	_warn_if_ash()

## Lo que la cola se lleva por delante si rompe ahora: la suma de lo que se pago
## por arrancar cada cosa. Es el COSTE, no el reembolso de cancelar — la Tormenta
## no devuelve nada, asi que lo que se pierde no pasa por la bolsa ni se recorta
## al hueco libre. Anunciar aqui el reembolso diria "vas a perder 0" con el
## almacen lleno, justo antes de quitarle 20 de madera.
func get_queue_at_risk() -> Dictionary:
	var at_risk := {}
	for node in _active:
		var cost: Dictionary = _paid_cost(_active[node])
		for res_name in cost:
			at_risk[res_name] = int(at_risk.get(res_name, 0)) + int(cost[res_name])
	return at_risk

## El aviso. Se da al entrar en la ceniza y otra vez cada vez que el jugador mete
## algo nuevo mientras cae, porque quien encola durante la ceniza es justo quien
## va a perderlo. Una regla dura que nadie te conto es una regla injusta.
func _warn_if_ash() -> void:
	if not _ash_overhead or _active.is_empty():
		return
	var at_risk := get_queue_at_risk()
	# Solo minados: no se pago nada por ellos, y hablar de coste donde no lo hubo
	# suena a mentira. Lo que se pierde ahi es el trabajo hecho.
	if at_risk.is_empty():
		EventBus.notification_posted.emit(
			Tr.t("STORM_ASH_QUEUE_WARNING_FREE") % _active.size(), "warning", UITheme.WARNING)
		return
	EventBus.notification_posted.emit(
		Tr.t("STORM_ASH_QUEUE_WARNING") % [_active.size(), Tr.amount_list(at_risk)],
		"warning", UITheme.WARNING)

## Rompe la Tormenta. Todo lo que estuviera en curso se echa a perder con su
## coste, y se dice pieza por pieza: un solo mensaje de resumen deja al jugador
## sin saber que perdio, y saberlo es lo que le ensena a vaciar la cola antes.
func _on_storm_started(_severity: int) -> void:
	_ash_overhead = false
	# La tormenta de prueba de la era 1 no se lleva la cola: es un ensayo.
	if StormManager.is_trial_running():
		return
	if _active.is_empty():
		return
	for node in _active.keys():
		var info: Dictionary = _active[node]
		var pid: String = str(info.get("id", ""))
		var cost: Dictionary = _paid_cost(info)
		var refund := _drop(node, get_storm_loss_preview(node))
		# El minado no costo recursos: se perdio el tiempo, no la inversion, y
		# decirle "el coste no vuelve" a quien no pago nada suena a mentira.
		if cost.is_empty():
			EventBus.notification_posted.emit(
				Tr.t("NOTIF_STORM_ATE_MINING") % _display_name(info),
				"danger", UITheme.DANGER)
		else:
			EventBus.notification_posted.emit(
				Tr.t("NOTIF_STORM_ATE_PROCESS") % [_display_name(info), Tr.amount_list(cost)],
				"danger", UITheme.DANGER)
		# Se emite tambien como cancelacion para que la UI que sigue la cola se
		# entere por el mismo canal, con el reembolso real: ninguno.
		if is_instance_valid(node):
			EventBus.process_cancelled.emit(node, pid, refund)

## Pasa la tormenta. Lo que se encole a partir de aqui ya no corre peligro hasta
## la siguiente ceniza.
func _on_storm_ended(_severity: int) -> void:
	_ash_overhead = false

# ── Partida nueva ──

## Vacia la cola sin abonar nada y sin decir nada. Un reinicio no es una entrega
## ni una perdida: nadie quiere leer "has perdido tu proceso" al empezar.
##
## Sin esto, un proceso vivo sobrevivia al cambio de escena. Su nodo quedaba
## invalido, `_process` lo daba por completado y `_complete()` abonaba la
## produccion —el guard de `is_instance_valid` solo envuelve el texto flotante y
## la señal, no el `ResourceManager.add()`— de modo que empezar partida nueva con
## algo en la cola le regalaba esos recursos a la partida nueva.
func reset() -> void:
	_active.clear()
	# Partida nueva: el cielo tambien empieza limpio.
	_ash_overhead = false

# ── Save/Load ──

func get_save_data() -> Array:
	var result: Array = []
	for node in _active:
		if not is_instance_valid(node):
			continue
		var info: Dictionary = _active[node]
		var binfo := GridManager.get_building_info(node)
		if not binfo.is_empty():
			result.append({
				"cell_x": (binfo["origin_cell"] as Vector2i).x,
				"cell_y": (binfo["origin_cell"] as Vector2i).y,
				"id": info["id"],
				"name_key": str(info.get("name_key", "")),
				"remaining": info["remaining"],
				"duration": info["duration"],
				"produces": info["produces"],
				"cost": info.get("cost", {}),
				"count": int(info.get("count", 1)),
				"total": int(info.get("total", info.get("count", 1))),
				"workers": _workers_of(info),
			})
		elif node.has_meta("cell"):
			var cell: Vector2i = node.get_meta("cell")
			result.append({
				"cell_x": cell.x,
				"cell_y": cell.y,
				"id": info["id"],
				"name_key": str(info.get("name_key", "")),
				"remaining": info["remaining"],
				"duration": info["duration"],
				"produces": info["produces"],
				"cost": info.get("cost", {}),
				"count": int(info.get("count", 1)),
				"total": int(info.get("total", info.get("count", 1))),
				"workers": _workers_of(info),
				"is_deposit": true,
			})
	return result

func load_save_data(data: Array) -> void:
	for entry in data:
		var cell := Vector2i(entry["cell_x"], entry["cell_y"])
		var node := GridManager.get_building_at(cell)
		if not node or not is_instance_valid(node):
			continue
		# Antes se guardaba el nombre ya traducido ("name"); ahora la clave. Un
		# guardado viejo recupera la clave por el id, y si ni eso, conserva el texto.
		var name_key := str(entry.get("name_key", ""))
		if name_key == "":
			name_key = _name_key_for(str(entry.get("id", "")))
		# Lotes (2026-10-14): un guardado de antes no trae `count`, y es una vuelta.
		var count: int = maxi(1, int(entry.get("count", 1)))
		var restored := {
			"id": entry["id"],
			"name_key": name_key,
			"legacy_name": str(entry.get("name", "")),
			"remaining": entry["remaining"],
			"duration": entry["duration"],
			"produces": entry["produces"],
			# Las partidas guardadas antes de que existiera la cancelacion no
			# traen coste: se cargan igual, y cancelarlas no devuelve nada.
			"cost": entry.get("cost", {}),
			"count": count,
			"total": maxi(count, int(entry.get("total", count))),
		}
		# Sin `workers` (guardado de antes), _workers_of lo deduce del id.
		if entry.has("workers"):
			restored["workers"] = int(entry["workers"])
		# Se asigna, no se suma: cargar dos veces deja lo mismo.
		_active[node] = restored

