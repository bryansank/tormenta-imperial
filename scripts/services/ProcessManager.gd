extends Node
## Manages timed processes for buildings and mining for deposits.
## Reads definitions from GameConfig (durations already scaled).

var _type_map := {
	"gold": ResourceManager.Type.GOLD,
	"steel": ResourceManager.Type.STEEL,
	"oil": ResourceManager.Type.OIL,
	"wood": ResourceManager.Type.WOOD,
}

# Active processes: Node3D -> {id, name, remaining, duration, produces}
var _active: Dictionary = {}

## Cae ceniza y la Tormenta todavia no ha roto: la ultima ventana en la que lo
## que hay en la cola aun se puede salvar. Se lleva por señal y no preguntandole
## la fase a StormManager, para que este servicio no dependa de aquel.
var _ash_overhead: bool = false

func _ready() -> void:
	EventBus.storm_ash_started.connect(_on_ash_started)
	EventBus.storm_started.connect(_on_storm_started)
	EventBus.storm_ended.connect(_on_storm_ended)

func get_processes_for(building_id: String) -> Array:
	return GameConfig.get_processes_for(building_id)

func get_mining_info(deposit_id: String) -> Dictionary:
	return GameConfig.get_mining_info(deposit_id)

func is_busy(node: Node3D) -> bool:
	return _active.has(node)

## Lo que devolveria cancelar ahora mismo, sin cancelar nada. La UI lo ensena
## antes de que el jugador confirme, y es el mismo numero que luego se abona.
func get_refund_preview(node: Node3D) -> Dictionary:
	if not _active.has(node):
		return {}
	# Recortado al hueco que queda: con la bolsa compartida, prometer un 70% que
	# no cabe es mentirle al jugador en el propio boton.
	return ResourceManager.fit_into_storage(
		GameConfig.get_cancel_refund(_active[node].get("cost", {})))

## Lo que sobreviviria a la Tormenta si rompiera ahora mismo. Hoy es siempre
## vacio —se pierde con su coste— pero existe como funcion y no como cero escrito
## a mano para que la pantalla pueda ensenarlo igual que el reembolso de
## cancelar, y para que aflojar la regla sea tocar el ratio y nada mas.
func get_storm_loss_preview(node: Node3D) -> Dictionary:
	if not _active.has(node):
		return {}
	return ResourceManager.fit_into_storage(
		GameConfig.get_storm_loss_refund(_active[node].get("cost", {})))

## Cancela el proceso o minado en curso y devuelve parte de lo pagado.
## Devuelve el reembolso realmente abonado (recurso -> cantidad); vacio si no
## habia nada en curso o si lo que habia no costaba recursos (un minado).
func cancel(node: Node3D) -> Dictionary:
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
func _drop(node: Node3D, refund: Dictionary) -> Dictionary:
	_active.erase(node)
	for res_name in refund:
		if _type_map.has(res_name):
			ResourceManager.add(_type_map[res_name], refund[res_name])
	return refund

func get_active(node: Node3D) -> Dictionary:
	return _active.get(node, {})

func get_progress(node: Node3D) -> float:
	if not _active.has(node):
		return 0.0
	var info: Dictionary = _active[node]
	return clampf(1.0 - (info["remaining"] / info["duration"]), 0.0, 1.0)

func start_process(node: Node3D, process: Dictionary) -> bool:
	if _active.has(node):
		return false
	if process.has("cost") and not process["cost"].is_empty():
		var cost := _convert_cost(process["cost"])
		if not ResourceManager.can_afford(cost):
			return false
		ResourceManager.spend_cost(cost)
	_active[node] = {
		"id": process["id"],
		"name": Tr.t(process["name"]),
		"remaining": process["duration"],
		"duration": process["duration"],
		"produces": process["produces"],
		# Lo pagado se guarda con el proceso: sin esto, cancelar no puede
		# devolver nada porque nadie recuerda cuanto costo.
		"cost": process.get("cost", {}).duplicate(),
	}
	EventBus.process_started.emit(node, process["id"])
	# Nunca se bloquea la cola durante la ceniza, pero tampoco se deja que el
	# jugador meta ahi el almacen sin saber lo que arriesga.
	_warn_if_ash()
	return true

func start_mining(node: Node3D, deposit_id: String) -> bool:
	if _active.has(node):
		return false
	if not GameConfig.is_deposit_unlocked(deposit_id):
		return false
	var data := get_mining_info(deposit_id)
	if data.is_empty():
		return false
	_active[node] = {
		"id": data["id"],
		"name": Tr.t(data["name"]),
		"remaining": data["duration"],
		"duration": data["duration"],
		"produces": data["produces"],
		# Minar no cuesta recursos: cancelar solo cuesta el tiempo invertido.
		"cost": {},
	}
	EventBus.mining_started.emit(node, deposit_id)
	_warn_if_ash()
	return true

func _process(delta: float) -> void:
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
	# llegaba: el tipado de `_complete(node: Node3D)` rechaza un nodo liberado, de
	# modo que la entrada no se borraba nunca y el error se repetia cada frame.
	for node in vanished:
		_active.erase(node)
	for node in completed:
		_complete(node)

func _complete(node: Node3D) -> void:
	var info: Dictionary = _active[node]
	var pid: String = str(info["id"])
	_active.erase(node)
	# Un edificio que ya no existe no entrega nada. El guard vive aqui, donde se
	# paga, y no en quien llama: cuando la proteccion esta en quien llama, cada
	# camino nuevo tiene que acordarse de ella y basta con que uno se olvide para
	# que la produccion de una partida muerta caiga en la siguiente.
	if not is_instance_valid(node):
		return
	for res_name in info["produces"]:
		if _type_map.has(res_name):
			ResourceManager.add(_type_map[res_name], info["produces"][res_name])
			FloatingText.spawn_resource(get_tree(), node.global_position, info["produces"][res_name], res_name)
	if pid.begins_with("mine_"):
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
		var cost: Dictionary = _active[node].get("cost", {})
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
	if _active.is_empty():
		return
	for node in _active.keys():
		var info: Dictionary = _active[node]
		var pid: String = str(info.get("id", ""))
		var cost: Dictionary = info.get("cost", {})
		var refund := _drop(node, get_storm_loss_preview(node))
		# El minado no costo recursos: se perdio el tiempo, no la inversion, y
		# decirle "el coste no vuelve" a quien no pago nada suena a mentira.
		if cost.is_empty():
			EventBus.notification_posted.emit(
				Tr.t("NOTIF_STORM_ATE_MINING") % str(info.get("name", pid)),
				"danger", UITheme.DANGER)
		else:
			EventBus.notification_posted.emit(
				Tr.t("NOTIF_STORM_ATE_PROCESS") % [str(info.get("name", pid)), Tr.amount_list(cost)],
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
				"name": info["name"],
				"remaining": info["remaining"],
				"duration": info["duration"],
				"produces": info["produces"],
				"cost": info.get("cost", {}),
			})
		elif node.has_meta("cell"):
			var cell: Vector2i = node.get_meta("cell")
			result.append({
				"cell_x": cell.x,
				"cell_y": cell.y,
				"id": info["id"],
				"name": info["name"],
				"remaining": info["remaining"],
				"duration": info["duration"],
				"produces": info["produces"],
				"cost": info.get("cost", {}),
				"is_deposit": true,
			})
	return result

func load_save_data(data: Array) -> void:
	for entry in data:
		var cell := Vector2i(entry["cell_x"], entry["cell_y"])
		var node := GridManager.get_building_at(cell)
		if not node or not is_instance_valid(node):
			continue
		_active[node] = {
			"id": entry["id"],
			"name": entry["name"],
			"remaining": entry["remaining"],
			"duration": entry["duration"],
			"produces": entry["produces"],
			# Las partidas guardadas antes de que existiera la cancelacion no
			# traen coste: se cargan igual, y cancelarlas no devuelve nada.
			"cost": entry.get("cost", {}),
		}

